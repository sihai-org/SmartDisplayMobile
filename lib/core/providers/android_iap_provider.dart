import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/android_iap_repository.dart';
import '../log/app_log.dart';
import '../models/android_iap_models.dart';
import '../services/android_iap_service.dart';
import 'lifecycle_provider.dart';

final androidIapRepositoryProvider = Provider<AndroidIapRepository>((ref) {
  return AndroidIapRepository();
});

final androidIapServiceProvider = Provider<AndroidIapService>((ref) {
  return AndroidIapService();
});

final androidIapProvider =
    StateNotifierProvider<AndroidIapNotifier, AndroidIapState>((ref) {
      final notifier = AndroidIapNotifier(
        ref: ref,
        repository: ref.read(androidIapRepositoryProvider),
        service: ref.read(androidIapServiceProvider),
      );
      ref.onDispose(notifier.dispose);
      return notifier;
    });

enum AndroidIapStage {
  idle,
  loadingCatalog,
  ready,
  creatingOrder,
  purchasing,
  awaitingPurchaseResult,
  verifying,
  success,
  failure,
}

enum AndroidIapFailureKind {
  unavailable,
  cancelled,
  catalogLoadFailed,
  generic,
}

class AndroidIapProductOption {
  const AndroidIapProductOption({
    required this.catalogProduct,
    required this.productDetails,
  });

  final AndroidIapProductData catalogProduct;
  final ProductDetails productDetails;

  String get packageCode => catalogProduct.packageCode;
  String get productId => catalogProduct.productId;
  double get creditAmount => catalogProduct.creditAmount;
  String get priceText => productDetails.price;
  String get displayName =>
      catalogProduct.displayName?.trim().isNotEmpty == true
      ? catalogProduct.displayName!.trim()
      : productDetails.title.trim();
  String? get description {
    final text = catalogProduct.description?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }
}

class AndroidIapSession {
  const AndroidIapSession({
    required this.orderId,
    required this.packageCode,
    required this.productId,
  });

  final String orderId;
  final String packageCode;
  final String productId;
}

class AndroidIapState {
  const AndroidIapState({
    this.stage = AndroidIapStage.idle,
    this.products = const [],
    this.isStoreAvailable = true,
    this.failureKind,
    this.failureDetail,
    this.activeSession,
    this.successTick = 0,
    this.lastCompletedOrderId,
  });

  final AndroidIapStage stage;
  final List<AndroidIapProductOption> products;
  final bool isStoreAvailable;
  final AndroidIapFailureKind? failureKind;
  final String? failureDetail;
  final AndroidIapSession? activeSession;
  final int successTick;
  final String? lastCompletedOrderId;

  bool get isBusy =>
      stage == AndroidIapStage.loadingCatalog ||
      stage == AndroidIapStage.creatingOrder ||
      stage == AndroidIapStage.purchasing ||
      stage == AndroidIapStage.awaitingPurchaseResult ||
      stage == AndroidIapStage.verifying;

  AndroidIapState copyWith({
    AndroidIapStage? stage,
    List<AndroidIapProductOption>? products,
    bool? isStoreAvailable,
    AndroidIapFailureKind? failureKind,
    String? failureDetail,
    bool clearFailure = false,
    AndroidIapSession? activeSession,
    bool clearActiveSession = false,
    int? successTick,
    String? lastCompletedOrderId,
    bool clearLastCompletedOrderId = false,
  }) {
    return AndroidIapState(
      stage: stage ?? this.stage,
      products: products ?? this.products,
      isStoreAvailable: isStoreAvailable ?? this.isStoreAvailable,
      failureKind: clearFailure ? null : (failureKind ?? this.failureKind),
      failureDetail: clearFailure
          ? null
          : (failureDetail ?? this.failureDetail),
      activeSession: clearActiveSession
          ? null
          : (activeSession ?? this.activeSession),
      successTick: successTick ?? this.successTick,
      lastCompletedOrderId: clearLastCompletedOrderId
          ? null
          : (lastCompletedOrderId ?? this.lastCompletedOrderId),
    );
  }
}

class AndroidIapNotifier extends StateNotifier<AndroidIapState> {
  AndroidIapNotifier({
    required Ref ref,
    required AndroidIapRepository repository,
    required AndroidIapService service,
  }) : _ref = ref,
       _repository = repository,
       _service = service,
       super(const AndroidIapState()) {
    _foregroundSub = _ref.listen<bool>(isForegroundProvider, (
      previous,
      current,
    ) {
      if (previous == false && current == true) {
        _scheduleForegroundPurchaseRecovery();
      }
    });
    _purchaseSubscription = _service.purchaseStream.listen(
      (purchases) => unawaited(_handlePurchaseUpdates(purchases)),
      onError: (Object error, StackTrace stackTrace) {
        AppLog.instance.error(
          '[android_iap] purchase stream error',
          tag: 'AndroidIap',
          error: error,
          stackTrace: stackTrace,
        );
        _setFailure(
          AndroidIapFailureKind.generic,
          detail: error.toString(),
          clearActiveSession: false,
        );
      },
    );
  }

  static const _purchaseResultGracePeriod = Duration(seconds: 2);

  final Ref _ref;
  final AndroidIapRepository _repository;
  final AndroidIapService _service;
  ProviderSubscription<bool>? _foregroundSub;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Timer? _purchaseResultTimer;
  bool _receivedPurchaseUpdateForActiveSession = false;

  Future<void> loadProductCatalog() async {
    final accessToken = _currentAccessToken;
    if (accessToken == null) {
      _setFailure(
        AndroidIapFailureKind.catalogLoadFailed,
        detail: 'Missing access token',
        clearActiveSession: true,
      );
      return;
    }

    state = state.copyWith(
      stage: AndroidIapStage.loadingCatalog,
      clearFailure: true,
      clearLastCompletedOrderId: true,
    );

    try {
      final isAvailable = await _service.isAvailable();
      if (!isAvailable) {
        state = state.copyWith(
          stage: AndroidIapStage.failure,
          isStoreAvailable: false,
          failureKind: AndroidIapFailureKind.unavailable,
          failureDetail: 'Google Play billing unavailable',
          clearActiveSession: true,
        );
        return;
      }

      final catalogProducts = await _repository.fetchAndroidIapProducts(
        accessToken: accessToken,
      );
      _logDebug('catalog_products_loaded', {
        'count': catalogProducts.length,
        'products': catalogProducts
            .map((item) => item.toJson())
            .toList(growable: false),
      });
      if (catalogProducts.isEmpty) {
        state = state.copyWith(
          stage: AndroidIapStage.ready,
          products: const [],
          isStoreAvailable: true,
          clearFailure: true,
          clearActiveSession: true,
        );
        return;
      }

      final productDetails = await _service.queryProductDetails(
        catalogProducts.map((item) => item.productId).toSet(),
      );
      _logDebug('google_play_product_details_loaded', {
        'count': productDetails.length,
        'product_details': productDetails
            .map(
              (item) => {
                'id': item.id,
                'title': item.title,
                'description': item.description,
                'price': item.price,
                'raw_price': item.rawPrice,
                'currency_code': item.currencyCode,
                'currency_symbol': item.currencySymbol,
              },
            )
            .toList(growable: false),
      });
      final detailMap = {
        for (final detail in productDetails) detail.id: detail,
      };
      final options =
          catalogProducts
              .where((item) => detailMap.containsKey(item.productId))
              .map(
                (item) => AndroidIapProductOption(
                  catalogProduct: item,
                  productDetails: detailMap[item.productId]!,
                ),
              )
              .toList()
            ..sort(
              (left, right) => left.catalogProduct.sortOrder.compareTo(
                right.catalogProduct.sortOrder,
              ),
            );
      _logDebug('catalog_options_matched', {
        'count': options.length,
        'options': options
            .map(
              (item) => {
                'catalog_product': item.catalogProduct.toJson(),
                'google_play_product': {
                  'id': item.productDetails.id,
                  'title': item.productDetails.title,
                  'description': item.productDetails.description,
                  'price': item.productDetails.price,
                  'raw_price': item.productDetails.rawPrice,
                  'currency_code': item.productDetails.currencyCode,
                  'currency_symbol': item.productDetails.currencySymbol,
                },
              },
            )
            .toList(growable: false),
      });

      state = state.copyWith(
        stage: AndroidIapStage.ready,
        products: List<AndroidIapProductOption>.unmodifiable(options),
        isStoreAvailable: true,
        clearFailure: true,
        clearActiveSession: true,
      );
    } catch (error, stackTrace) {
      AppLog.instance.error(
        '[android_iap] loadProductCatalog failed',
        tag: 'AndroidIap',
        error: error,
        stackTrace: stackTrace,
      );
      _setFailure(
        AndroidIapFailureKind.catalogLoadFailed,
        detail: error.toString(),
        clearActiveSession: true,
      );
    }
  }

  Future<void> startPurchaseFlow(AndroidIapProductOption option) async {
    final accessToken = _currentAccessToken;
    final user = Supabase.instance.client.auth.currentUser;
    if (accessToken == null || user == null) {
      _setFailure(
        AndroidIapFailureKind.generic,
        detail: 'Missing auth session',
        clearActiveSession: true,
      );
      return;
    }

    try {
      state = state.copyWith(
        stage: AndroidIapStage.creatingOrder,
        clearFailure: true,
        clearActiveSession: true,
      );

      final order = await _repository.createAndroidIapOrder(
        accessToken: accessToken,
        packageCode: option.packageCode,
      );
      _logDebug('pending_order_created', {'order': order.toJson()});

      if (order.orderId.isEmpty || order.productId != option.productId) {
        throw const BillingRequestException(
          'Google Play order payload mismatch',
        );
      }

      state = state.copyWith(
        stage: AndroidIapStage.purchasing,
        activeSession: AndroidIapSession(
          orderId: order.orderId,
          packageCode: order.packageCode,
          productId: order.productId,
        ),
      );
      _logDebug('active_session_started', {
        'order_id': order.orderId,
        'package_code': order.packageCode,
        'product_id': order.productId,
      });
      _receivedPurchaseUpdateForActiveSession = false;
      _cancelPurchaseResultTimer();

      await _service.launchConsumablePurchase(
        productDetails: option.productDetails,
        applicationUserName: user.id,
      );
    } catch (error, stackTrace) {
      AppLog.instance.error(
        '[android_iap] startPurchaseFlow failed',
        tag: 'AndroidIap',
        error: error,
        stackTrace: stackTrace,
      );
      _setFailure(
        AndroidIapFailureKind.generic,
        detail: error.toString(),
        clearActiveSession: true,
      );
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    _logDebug('purchase_stream_batch', {'count': purchases.length});
    for (final purchase in purchases) {
      _logPurchaseDetails('purchase_update', purchase);
      if (!_isTrackedProduct(purchase.productID)) {
        _logDebug('purchase_update_ignored', {
          'product_id': purchase.productID,
        });
        continue;
      }

      _receivedPurchaseUpdateForActiveSession = true;
      _cancelPurchaseResultTimer();

      switch (purchase.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(
            stage: AndroidIapStage.purchasing,
            clearFailure: true,
          );
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndFinalizePurchase(purchase);
          break;
        case PurchaseStatus.canceled:
          await _safeCompletePurchase(purchase);
          _setFailure(
            AndroidIapFailureKind.cancelled,
            detail: 'Purchase cancelled by user',
            clearActiveSession: true,
          );
          break;
        case PurchaseStatus.error:
          await _safeCompletePurchase(purchase);
          _setFailure(
            AndroidIapFailureKind.generic,
            detail: purchase.error?.message ?? 'Google Play purchase error',
            clearActiveSession: true,
          );
          break;
      }
    }
  }

  Future<void> _verifyAndFinalizePurchase(PurchaseDetails purchase) async {
    final accessToken = _currentAccessToken;
    if (accessToken == null) {
      _setFailure(
        AndroidIapFailureKind.generic,
        detail: 'Missing access token during verify',
        clearActiveSession: false,
      );
      return;
    }

    final session = await _resolveSessionForPurchase(
      productId: purchase.productID,
      accessToken: accessToken,
    );
    if (session == null) {
      _setFailure(
        AndroidIapFailureKind.generic,
        detail: 'Unable to resolve purchase session',
        clearActiveSession: false,
      );
      return;
    }

    final purchaseToken = purchase.verificationData.serverVerificationData
        .trim();
    if (purchaseToken.isEmpty) {
      _setFailure(
        AndroidIapFailureKind.generic,
        detail: 'Missing purchase token',
        clearActiveSession: false,
      );
      return;
    }

    state = state.copyWith(
      stage: AndroidIapStage.verifying,
      activeSession: session,
      clearFailure: true,
    );
    _logDebug('verify_purchase_request', {
      'session': {
        'order_id': session.orderId,
        'package_code': session.packageCode,
        'product_id': session.productId,
      },
      'purchase': _serializePurchaseDetails(purchase),
      'purchase_token': purchaseToken,
      'purchase_token_length': purchaseToken.length,
    });

    try {
      final result = await _repository.verifyAndroidIapPurchase(
        accessToken: accessToken,
        orderId: session.orderId,
        packageCode: session.packageCode,
        productId: session.productId,
        purchaseToken: purchaseToken,
      );
      _logDebug('verify_purchase_result', {'result': result.toJson()});

      if (result.status == 'granted' || result.status == 'already_granted') {
        await _service.completePendingPurchase(purchase);
        state = state.copyWith(
          stage: AndroidIapStage.success,
          clearFailure: true,
          clearActiveSession: true,
          successTick: state.successTick + 1,
          lastCompletedOrderId: result.orderId ?? session.orderId,
        );
        return;
      }

      await _service.completePendingPurchase(purchase);
      _setFailure(
        AndroidIapFailureKind.generic,
        detail: 'Unexpected verify status: ${result.status}',
        clearActiveSession: true,
      );
    } catch (error, stackTrace) {
      AppLog.instance.error(
        '[android_iap] verify failed',
        tag: 'AndroidIap',
        error: error,
        stackTrace: stackTrace,
      );
      _setFailure(
        AndroidIapFailureKind.generic,
        detail: error.toString(),
        clearActiveSession: false,
      );
    }
  }

  void _scheduleForegroundPurchaseRecovery() {
    if ((state.stage != AndroidIapStage.purchasing &&
            state.stage != AndroidIapStage.awaitingPurchaseResult) ||
        _receivedPurchaseUpdateForActiveSession) {
      return;
    }

    if (state.stage == AndroidIapStage.purchasing) {
      state = state.copyWith(stage: AndroidIapStage.awaitingPurchaseResult);
    }

    _cancelPurchaseResultTimer();
    _purchaseResultTimer = Timer(_purchaseResultGracePeriod, () {
      if (!mounted) return;
      if ((state.stage != AndroidIapStage.purchasing &&
              state.stage != AndroidIapStage.awaitingPurchaseResult) ||
          _receivedPurchaseUpdateForActiveSession) {
        return;
      }

      AppLog.instance.info(
        '[android_iap] purchase flow dismissed without purchase update; treating as cancelled',
        tag: 'AndroidIap',
      );
      state = state.copyWith(
        stage: AndroidIapStage.failure,
        failureKind: AndroidIapFailureKind.cancelled,
        failureDetail: 'Purchase cancelled by user',
      );
    });
  }

  void _cancelPurchaseResultTimer() {
    _purchaseResultTimer?.cancel();
    _purchaseResultTimer = null;
  }

  Future<void> _safeCompletePurchase(PurchaseDetails purchase) async {
    try {
      await _service.completePendingPurchase(purchase);
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        '[android_iap] completePendingPurchase failed',
        tag: 'AndroidIap',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<AndroidIapSession?> _resolveSessionForPurchase({
    required String productId,
    required String accessToken,
  }) async {
    final activeSession = state.activeSession;
    if (activeSession != null && activeSession.productId == productId) {
      return activeSession;
    }

    final option = _findOption(productId);
    if (option == null) return null;

    final order = await _repository.createAndroidIapOrder(
      accessToken: accessToken,
      packageCode: option.packageCode,
    );
    final session = AndroidIapSession(
      orderId: order.orderId,
      packageCode: order.packageCode,
      productId: order.productId,
    );
    state = state.copyWith(activeSession: session);
    return session;
  }

  AndroidIapProductOption? _findOption(String productId) {
    for (final option in state.products) {
      if (option.productId == productId) {
        return option;
      }
    }
    return null;
  }

  bool _isTrackedProduct(String productId) {
    final activeSession = state.activeSession;
    if (activeSession != null && activeSession.productId == productId) {
      return true;
    }
    return _findOption(productId) != null;
  }

  String? get _currentAccessToken {
    final session = Supabase.instance.client.auth.currentSession;
    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return null;
    }
    return accessToken;
  }

  void _setFailure(
    AndroidIapFailureKind kind, {
    String? detail,
    required bool clearActiveSession,
  }) {
    state = state.copyWith(
      stage: AndroidIapStage.failure,
      failureKind: kind,
      failureDetail: detail,
      clearActiveSession: clearActiveSession,
    );
  }

  Map<String, dynamic> _serializePurchaseDetails(PurchaseDetails purchase) {
    return {
      'product_id': purchase.productID,
      'purchase_id': purchase.purchaseID,
      'status': purchase.status.name,
      'transaction_date': purchase.transactionDate,
      'pending_complete_purchase': purchase.pendingCompletePurchase,
      'verification_data': {
        'source': purchase.verificationData.source,
        'server_verification_data':
            purchase.verificationData.serverVerificationData,
        'server_verification_data_length':
            purchase.verificationData.serverVerificationData.length,
        'local_verification_data':
            purchase.verificationData.localVerificationData,
        'local_verification_data_length':
            purchase.verificationData.localVerificationData.length,
      },
      'error': purchase.error == null
          ? null
          : {
              'source': purchase.error!.source,
              'code': purchase.error!.code,
              'message': purchase.error!.message,
              'details': purchase.error!.details,
            },
    };
  }

  void _logPurchaseDetails(String event, PurchaseDetails purchase) {
    _logDebug(event, _serializePurchaseDetails(purchase));
  }

  void _logDebug(String event, Map<String, dynamic> payload) {
    AppLog.instance.debug(
      jsonEncode({'event': event, ...payload}),
      tag: 'AndroidIap',
    );
  }

  @override
  void dispose() {
    _cancelPurchaseResultTimer();
    _foregroundSub?.close();
    unawaited(_purchaseSubscription?.cancel());
    super.dispose();
  }
}
