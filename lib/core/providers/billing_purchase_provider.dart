import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/billing_purchase_repository.dart';
import '../log/app_log.dart';
import '../models/billing_purchase_models.dart';
import '../services/billing_purchase_service.dart';

final billingPurchaseRepositoryProvider = Provider<BillingPurchaseRepository>((
  ref,
) {
  return BillingPurchaseRepository();
});

final billingPurchaseServiceProvider = Provider<BillingPurchaseService>((ref) {
  return BillingPurchaseService();
});

final billingPurchaseProvider =
    StateNotifierProvider<BillingPurchaseNotifier, BillingPurchaseState>((ref) {
      final notifier = BillingPurchaseNotifier(
        repository: ref.read(billingPurchaseRepositoryProvider),
        service: ref.read(billingPurchaseServiceProvider),
      );
      ref.onDispose(notifier.dispose);
      return notifier;
    });

enum BillingPurchaseStage {
  idle,
  loadingCatalog,
  ready,
  creatingOrder,
  purchasing,
  verifying,
  success,
  failure,
}

enum BillingPurchaseFailureKind { unavailable, cancelled, generic }

class BillingPurchaseProductOption {
  const BillingPurchaseProductOption({
    required this.catalogProduct,
    required this.productDetails,
  });

  final GooglePlayCatalogProduct catalogProduct;
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

class BillingPurchaseSession {
  const BillingPurchaseSession({
    required this.orderId,
    required this.packageCode,
    required this.productId,
  });

  final String orderId;
  final String packageCode;
  final String productId;
}

class BillingPurchaseState {
  const BillingPurchaseState({
    this.stage = BillingPurchaseStage.idle,
    this.products = const [],
    this.isStoreAvailable = true,
    this.failureKind,
    this.failureDetail,
    this.activeSession,
    this.successTick = 0,
    this.lastCompletedOrderId,
  });

  final BillingPurchaseStage stage;
  final List<BillingPurchaseProductOption> products;
  final bool isStoreAvailable;
  final BillingPurchaseFailureKind? failureKind;
  final String? failureDetail;
  final BillingPurchaseSession? activeSession;
  final int successTick;
  final String? lastCompletedOrderId;

  bool get isBusy =>
      stage == BillingPurchaseStage.loadingCatalog ||
      stage == BillingPurchaseStage.creatingOrder ||
      stage == BillingPurchaseStage.purchasing ||
      stage == BillingPurchaseStage.verifying;

  BillingPurchaseState copyWith({
    BillingPurchaseStage? stage,
    List<BillingPurchaseProductOption>? products,
    bool? isStoreAvailable,
    BillingPurchaseFailureKind? failureKind,
    String? failureDetail,
    bool clearFailure = false,
    BillingPurchaseSession? activeSession,
    bool clearActiveSession = false,
    int? successTick,
    String? lastCompletedOrderId,
    bool clearLastCompletedOrderId = false,
  }) {
    return BillingPurchaseState(
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

class BillingPurchaseNotifier extends StateNotifier<BillingPurchaseState> {
  BillingPurchaseNotifier({
    required BillingPurchaseRepository repository,
    required BillingPurchaseService service,
  }) : _repository = repository,
       _service = service,
       super(const BillingPurchaseState()) {
    _purchaseSubscription = _service.purchaseStream.listen(
      (purchases) => unawaited(_handlePurchaseUpdates(purchases)),
      onError: (Object error, StackTrace stackTrace) {
        AppLog.instance.error(
          '[billing_purchase] purchase stream error',
          tag: 'BillingPurchase',
          error: error,
          stackTrace: stackTrace,
        );
        _setFailure(
          BillingPurchaseFailureKind.generic,
          detail: error.toString(),
          clearActiveSession: false,
        );
      },
    );
  }

  final BillingPurchaseRepository _repository;
  final BillingPurchaseService _service;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  Future<void> loadCatalog() async {
    if (!Platform.isAndroid) {
      _setFailure(
        BillingPurchaseFailureKind.unavailable,
        clearActiveSession: true,
      );
      return;
    }

    final accessToken = _currentAccessToken;
    if (accessToken == null) {
      _setFailure(
        BillingPurchaseFailureKind.generic,
        detail: 'Missing access token',
        clearActiveSession: true,
      );
      return;
    }

    state = state.copyWith(
      stage: BillingPurchaseStage.loadingCatalog,
      clearFailure: true,
      clearLastCompletedOrderId: true,
    );

    try {
      final isAvailable = await _service.isAvailable();
      if (!isAvailable) {
        state = state.copyWith(
          stage: BillingPurchaseStage.failure,
          isStoreAvailable: false,
          failureKind: BillingPurchaseFailureKind.unavailable,
          failureDetail: 'Google Play billing unavailable',
          clearActiveSession: true,
        );
        return;
      }

      final catalogProducts = await _repository.fetchGooglePlayProducts(
        accessToken: accessToken,
      );
      if (catalogProducts.isEmpty) {
        state = state.copyWith(
          stage: BillingPurchaseStage.ready,
          products: const [],
          isStoreAvailable: true,
          clearFailure: true,
          clearActiveSession: true,
        );
        return;
      }

      final productDetails = await _service.queryProducts(
        catalogProducts.map((item) => item.productId).toSet(),
      );
      final detailMap = {
        for (final detail in productDetails) detail.id: detail,
      };
      final options =
          catalogProducts
              .where((item) => detailMap.containsKey(item.productId))
              .map(
                (item) => BillingPurchaseProductOption(
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

      state = state.copyWith(
        stage: BillingPurchaseStage.ready,
        products: List<BillingPurchaseProductOption>.unmodifiable(options),
        isStoreAvailable: true,
        clearFailure: true,
        clearActiveSession: true,
      );
    } catch (error, stackTrace) {
      AppLog.instance.error(
        '[billing_purchase] loadCatalog failed',
        tag: 'BillingPurchase',
        error: error,
        stackTrace: stackTrace,
      );
      _setFailure(
        BillingPurchaseFailureKind.generic,
        detail: error.toString(),
        clearActiveSession: true,
      );
    }
  }

  Future<void> beginPurchase(BillingPurchaseProductOption option) async {
    final accessToken = _currentAccessToken;
    final user = Supabase.instance.client.auth.currentUser;
    if (accessToken == null || user == null) {
      _setFailure(
        BillingPurchaseFailureKind.generic,
        detail: 'Missing auth session',
        clearActiveSession: true,
      );
      return;
    }

    try {
      state = state.copyWith(
        stage: BillingPurchaseStage.creatingOrder,
        clearFailure: true,
        clearActiveSession: true,
      );

      final order = await _repository.createGooglePlayOrder(
        accessToken: accessToken,
        packageCode: option.packageCode,
      );

      if (order.orderId.isEmpty || order.productId != option.productId) {
        throw const BillingRequestException(
          'Google Play order payload mismatch',
        );
      }

      state = state.copyWith(
        stage: BillingPurchaseStage.purchasing,
        activeSession: BillingPurchaseSession(
          orderId: order.orderId,
          packageCode: order.packageCode,
          productId: order.productId,
        ),
      );

      await _service.buyConsumable(
        productDetails: option.productDetails,
        applicationUserName: user.id,
      );
    } catch (error, stackTrace) {
      AppLog.instance.error(
        '[billing_purchase] beginPurchase failed',
        tag: 'BillingPurchase',
        error: error,
        stackTrace: stackTrace,
      );
      _setFailure(
        BillingPurchaseFailureKind.generic,
        detail: error.toString(),
        clearActiveSession: true,
      );
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (!_isTrackedProduct(purchase.productID)) {
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(
            stage: BillingPurchaseStage.purchasing,
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
            BillingPurchaseFailureKind.cancelled,
            detail: 'Purchase cancelled by user',
            clearActiveSession: true,
          );
          break;
        case PurchaseStatus.error:
          await _safeCompletePurchase(purchase);
          _setFailure(
            BillingPurchaseFailureKind.generic,
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
        BillingPurchaseFailureKind.generic,
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
        BillingPurchaseFailureKind.generic,
        detail: 'Unable to resolve purchase session',
        clearActiveSession: false,
      );
      return;
    }

    final purchaseToken = purchase.verificationData.serverVerificationData
        .trim();
    if (purchaseToken.isEmpty) {
      _setFailure(
        BillingPurchaseFailureKind.generic,
        detail: 'Missing purchase token',
        clearActiveSession: false,
      );
      return;
    }

    state = state.copyWith(
      stage: BillingPurchaseStage.verifying,
      activeSession: session,
      clearFailure: true,
    );

    try {
      final result = await _repository.verifyGooglePlayPurchase(
        accessToken: accessToken,
        orderId: session.orderId,
        packageCode: session.packageCode,
        productId: session.productId,
        purchaseToken: purchaseToken,
      );

      if (result.status == 'granted' || result.status == 'already_granted') {
        await _service.completePurchase(purchase);
        state = state.copyWith(
          stage: BillingPurchaseStage.success,
          clearFailure: true,
          clearActiveSession: true,
          successTick: state.successTick + 1,
          lastCompletedOrderId: result.orderId ?? session.orderId,
        );
        return;
      }

      await _service.completePurchase(purchase);
      _setFailure(
        BillingPurchaseFailureKind.generic,
        detail: 'Unexpected verify status: ${result.status}',
        clearActiveSession: true,
      );
    } catch (error, stackTrace) {
      AppLog.instance.error(
        '[billing_purchase] verify failed',
        tag: 'BillingPurchase',
        error: error,
        stackTrace: stackTrace,
      );
      _setFailure(
        BillingPurchaseFailureKind.generic,
        detail: error.toString(),
        clearActiveSession: false,
      );
    }
  }

  Future<void> _safeCompletePurchase(PurchaseDetails purchase) async {
    try {
      await _service.completePurchase(purchase);
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        '[billing_purchase] completePurchase failed',
        tag: 'BillingPurchase',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<BillingPurchaseSession?> _resolveSessionForPurchase({
    required String productId,
    required String accessToken,
  }) async {
    final activeSession = state.activeSession;
    if (activeSession != null && activeSession.productId == productId) {
      return activeSession;
    }

    final option = _findOption(productId);
    if (option == null) return null;

    final order = await _repository.createGooglePlayOrder(
      accessToken: accessToken,
      packageCode: option.packageCode,
    );
    final session = BillingPurchaseSession(
      orderId: order.orderId,
      packageCode: order.packageCode,
      productId: order.productId,
    );
    state = state.copyWith(activeSession: session);
    return session;
  }

  BillingPurchaseProductOption? _findOption(String productId) {
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
    BillingPurchaseFailureKind kind, {
    String? detail,
    required bool clearActiveSession,
  }) {
    state = state.copyWith(
      stage: BillingPurchaseStage.failure,
      failureKind: kind,
      failureDetail: detail,
      clearActiveSession: clearActiveSession,
    );
  }

  @override
  void dispose() {
    unawaited(_purchaseSubscription?.cancel());
    super.dispose();
  }
}
