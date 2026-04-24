import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/audit/audit_mode.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/log/app_log.dart';
import '../../core/log/buy_log.dart';
import '../../core/log/biz_log_tag.dart';
import '../../core/providers/audit_billing_provider.dart';
import '../../core/providers/ios_iap_order_context_provider.dart';
import '../../data/repositories/ios_iap_repository.dart';
import 'ios_product_sheet.dart';
import 'purchase_ui/purchase_entry_button.dart';

const List<AppleIapProductData> _auditFallbackProducts = [
  AppleIapProductData(
    packageCode: 'com.datou.vzngpt.credits.1000',
    productId: 'com.datou.vzngpt.credits.1000',
    creditAmount: 1000,
    displayName: '1,000 Credits',
    description: 'iOS top-up package for 1000 credits',
    currency: 'USD',
    amount: 0.99,
    sortOrder: 0,
  ),
  AppleIapProductData(
    packageCode: 'com.datou.vzngpt.credits.2000',
    productId: 'com.datou.vzngpt.credits.2000',
    creditAmount: 2000,
    displayName: '2,000 Credits',
    description: 'iOS top-up package for 2000 credits',
    currency: 'USD',
    amount: 1.79,
    sortOrder: 1,
  ),
  AppleIapProductData(
    packageCode: 'com.datou.vzngpt.credits.3000',
    productId: 'com.datou.vzngpt.credits.3000',
    creditAmount: 3000,
    displayName: '3,000 Credits',
    description: 'iOS top-up package for 3000 credits',
    currency: 'USD',
    amount: 2.49,
    sortOrder: 2,
  ),
];

class IosBuyButton extends ConsumerStatefulWidget {
  const IosBuyButton({super.key, this.onPurchaseSuccess});

  final Future<void> Function()? onPurchaseSuccess;

  @override
  ConsumerState<IosBuyButton> createState() => _IosBuyButtonState();
}

class _IosBuyButtonState extends ConsumerState<IosBuyButton> {
  final IosIapRepository _iosIapRepository = IosIapRepository();
  final ValueNotifier<IosPurchaseSheetState> _purchaseSheetState =
      ValueNotifier(const IosPurchaseSheetState());
  late final IosIapOrderContextNotifier _orderContextNotifier;
  late final StreamSubscription<List<PurchaseDetails>> _purchaseSubscription;

  List<AppleIapProductData> _products = const [];
  bool _isPurchasing = false;
  bool _isPurchaseSheetVisible = false;

  @override
  void initState() {
    super.initState();
    _orderContextNotifier = ref.read(iosIapOrderContextProvider.notifier);
    _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdated,
      onDone: () => _purchaseSubscription.cancel(),
      onError: (error) {
        debugPrint('purchaseStream error: $error');
      },
    );
  }

  @override
  void dispose() {
    _purchaseSubscription.cancel();
    _orderContextNotifier.clear();
    _purchaseSheetState.dispose();
    super.dispose();
  }

  Future<List<AppleIapProductData>> _requestProducts() async {
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (AuditMode.enabled && (accessToken == null || accessToken.isEmpty)) {
      return _loadAuditFallbackProducts(reason: 'missing_access_token');
    }
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Missing access token');
    }

    List<AppleIapProductData> catalogProducts;
    try {
      catalogProducts = await _iosIapRepository.fetchAppleIapProducts(
        accessToken: accessToken,
      );
    } catch (error, stackTrace) {
      if (AuditMode.enabled) {
        AppLog.instance.warning(
          'Falling back to fixed Apple IAP catalog in audit mode',
          tag: BizLogTag.buy.tag,
          error: error,
          stackTrace: stackTrace,
        );
        return _loadAuditFallbackProducts(reason: 'server_fetch_failed');
      }
      rethrow;
    }

    catalogProducts.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final products = await _attachStorePrices(catalogProducts);
    logBuyInfo('catalog_products_loaded', {
      'count': products.length,
      'products': products
          .map(
            (item) => {
              'package_code': item.packageCode,
              'product_id': item.productId,
              'credit_amount': item.creditAmount,
              'display_name': item.displayName,
              'description': item.description,
              'currency': item.currency,
              'amount': item.amount,
              'display_price': item.displayPrice,
              'sort_order': item.sortOrder,
            },
          )
          .toList(growable: false),
    });
    return List<AppleIapProductData>.unmodifiable(products);
  }

  Future<List<AppleIapProductData>> _loadAuditFallbackProducts({
    required String reason,
  }) async {
    final products = await _attachStorePrices(_auditFallbackProducts);
    logBuyInfo('catalog_products_audit_fallback_loaded', {
      'reason': reason,
      'count': products.length,
      'products': products
          .map(
            (item) => {
              'package_code': item.packageCode,
              'product_id': item.productId,
              'credit_amount': item.creditAmount,
              'display_name': item.displayName,
              'description': item.description,
              'currency': item.currency,
              'amount': item.amount,
              'display_price': item.displayPrice,
              'sort_order': item.sortOrder,
            },
          )
          .toList(growable: false),
    });
    return List<AppleIapProductData>.unmodifiable(products);
  }

  Future<List<AppleIapProductData>> _attachStorePrices(
    List<AppleIapProductData> catalogProducts,
  ) async {
    if (catalogProducts.isEmpty) return catalogProducts;

    final productIds = catalogProducts
        .map((item) => item.productId)
        .where((id) => id.isNotEmpty)
        .toSet();
    if (productIds.isEmpty) return catalogProducts;

    try {
      logBuyIapRequest(
        action: 'isAvailable',
        payload: {
          'scene': 'attachStorePrices',
          'product_id_count': productIds.length,
        },
      );
      final isAvailable = await InAppPurchase.instance.isAvailable();
      logBuyIapResponse(
        action: 'isAvailable',
        payload: {'scene': 'attachStorePrices', 'is_available': isAvailable},
      );
      if (!isAvailable) {
        return catalogProducts;
      }

      logBuyIapRequest(
        action: 'queryProductDetails',
        payload: {
          'scene': 'attachStorePrices',
          'product_ids': productIds.toList(growable: false),
        },
      );
      final response = await InAppPurchase.instance
          .queryProductDetails(productIds)
          .timeout(const Duration(seconds: 15));
      logBuyIapResponse(
        action: 'queryProductDetails',
        payload: {
          'scene': 'attachStorePrices',
          'product_details_count': response.productDetails.length,
          'product_details': response.productDetails
              .map(_serializeProductDetails)
              .toList(growable: false),
          'not_found_ids': response.notFoundIDs,
          'error': _serializeIapError(response.error),
        },
      );

      final detailsById = {
        for (final detail in response.productDetails) detail.id: detail,
      };
      final products = catalogProducts
          .map((item) {
            final detail = detailsById[item.productId];
            if (detail == null) return item;
            return item.copyWith(
              currency: detail.currencyCode,
              amount: detail.rawPrice,
              displayPrice: detail.price,
            );
          })
          .toList(growable: false);
      logBuyInfo('catalog_store_prices_attached', {
        'matched_count': detailsById.length,
        'products': products
            .map(
              (item) => {
                'product_id': item.productId,
                'currency': item.currency,
                'amount': item.amount,
                'display_price': item.displayPrice,
              },
            )
            .toList(growable: false),
      });
      return products;
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        'Failed to attach App Store prices to iOS IAP catalog',
        tag: BizLogTag.buy.tag,
        error: error,
        stackTrace: stackTrace,
      );
      return catalogProducts;
    }
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _requestProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
      });
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when fetching Apple IAP products',
        tag: BizLogTag.buy.tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<List<AppleIapProductData>> _reloadProductsForSheet() async {
    try {
      final products = await _requestProducts();
      if (!mounted) return products;
      setState(() {
        _products = products;
      });
      return products;
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when reloading Apple IAP products',
        tag: BizLogTag.buy.tag,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _handlePressed() async {
    if (_isPurchasing) return;

    _purchaseSheetState.value = const IosPurchaseSheetState();
    setState(() {
      _isPurchaseSheetVisible = true;
    });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) => IosProductSheet(
        initialProducts: _products,
        loadOnOpen: true,
        onReload: _reloadProductsForSheet,
        onPurchase: _purchase,
        purchaseStateListenable: _purchaseSheetState,
      ),
    );
    if (!mounted) return;
    setState(() {
      _isPurchaseSheetVisible = false;
    });
    _purchaseSheetState.value = const IosPurchaseSheetState();
  }

  Future<void> _purchase(AppleIapProductData catalogProduct) async {
    try {
      final isAuditMode = AuditMode.enabled;
      final user = Supabase.instance.client.auth.currentUser;
      final accessToken =
          Supabase.instance.client.auth.currentSession?.accessToken;
      if (!isAuditMode &&
          (user == null || accessToken == null || accessToken.isEmpty)) {
        _setSheetFailure(
          IosPurchaseFailureKind.signInRequired,
          activeProductId: catalogProduct.productId,
        );
        return;
      }

      if (mounted) {
        setState(() {
          _isPurchasing = true;
        });
      }
      _purchaseSheetState.value = IosPurchaseSheetState(
        stage: IosPurchaseStage.creatingOrder,
        activeProductId: catalogProduct.productId,
      );

      logBuyIapRequest(
        action: 'isAvailable',
        payload: {'scene': 'purchase', 'product_id': catalogProduct.productId},
      );
      final isAvailable = await InAppPurchase.instance.isAvailable();
      logBuyIapResponse(
        action: 'isAvailable',
        payload: {
          'scene': 'purchase',
          'product_id': catalogProduct.productId,
          'is_available': isAvailable,
        },
      );

      if (!isAvailable) {
        _clearPendingOrder();
        if (mounted) {
          setState(() {
            _isPurchasing = false;
          });
        }
        _setSheetFailure(
          IosPurchaseFailureKind.storeUnavailable,
          activeProductId: catalogProduct.productId,
        );
        return;
      }

      final shouldCreateOrder = !isAuditMode;
      var purchaseProductId = catalogProduct.productId;
      if (shouldCreateOrder) {
        final order = await _iosIapRepository.createAppleIapOrder(
          accessToken: accessToken!,
          packageCode: catalogProduct.packageCode,
        );
        ref
            .read(iosIapOrderContextProvider.notifier)
            .setContext(
              orderId: order.orderId,
              packageCode: order.packageCode,
              productId: order.productId,
            );
        purchaseProductId = order.productId;
      } else {
        ref
            .read(iosIapOrderContextProvider.notifier)
            .setContext(
              packageCode: catalogProduct.packageCode,
              productId: catalogProduct.productId,
            );
        logBuyInfo('audit_mode_skip_create_order', {
          'package_code': catalogProduct.packageCode,
          'product_id': catalogProduct.productId,
        });
        await _tryFinalizeAuditStoreTransactions(
          productId: catalogProduct.productId,
          scene: 'beforePurchaseAuditCleanup',
        );
      }
      _purchaseSheetState.value = _purchaseSheetState.value.copyWith(
        stage: IosPurchaseStage.purchasing,
        activeProductId: purchaseProductId,
        clearFailure: true,
      );

      logBuyIapRequest(
        action: 'queryProductDetails',
        payload: {
          'scene': 'purchase',
          'product_ids': [purchaseProductId],
        },
      );
      final response = await InAppPurchase.instance
          .queryProductDetails({purchaseProductId})
          .timeout(const Duration(seconds: 15));
      logBuyIapResponse(
        action: 'queryProductDetails',
        payload: {
          'scene': 'purchase',
          'product_details_count': response.productDetails.length,
          'product_details': response.productDetails
              .map(_serializeProductDetails)
              .toList(growable: false),
          'not_found_ids': response.notFoundIDs,
          'error': _serializeIapError(response.error),
        },
      );

      if (response.productDetails.isEmpty) {
        _clearPendingOrder();
        if (mounted) {
          setState(() {
            _isPurchasing = false;
          });
        }
        _setSheetFailure(
          IosPurchaseFailureKind.productNotFound,
          activeProductId: purchaseProductId,
        );
        return;
      }

      final product = response.productDetails.first;
      final applicationUserName = isAuditMode
          ? AuditMode.auditStoreAccountToken
          : user?.id;
      final purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: applicationUserName,
      );
      logBuyIapRequest(
        action: 'buyConsumable',
        payload: {
          'product': _serializeProductDetails(product),
          'application_user_name': applicationUserName,
        },
      );

      final started = await InAppPurchase.instance.buyConsumable(
        purchaseParam: purchaseParam,
      );
      logBuyIapResponse(
        action: 'buyConsumable',
        payload: {'started': started, 'product_id': product.id},
      );

      if (!started) {
        _clearPendingOrder();
        if (mounted) {
          setState(() {
            _isPurchasing = false;
          });
        }
        _setSheetFailure(
          IosPurchaseFailureKind.generic,
          activeProductId: product.id,
        );
      }
    } catch (error, stackTrace) {
      _clearPendingOrder();
      AppLog.instance.error(
        'Unexpected error during iOS IAP purchase flow',
        tag: BizLogTag.buy.tag,
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _isPurchasing = false;
      });
      _setSheetFailure(
        IosPurchaseFailureKind.generic,
        activeProductId: catalogProduct.productId,
      );
    }
  }

  Future<void> _onPurchaseUpdated(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    final l10n = context.l10n;

    logBuyInfo('purchase_stream_batch', {'count': purchaseDetailsList.length});
    for (final purchase in purchaseDetailsList) {
      _logPurchaseDetails('purchase_update', purchase);
      final isAuditStorePurchase = _isAuditStorePurchase(purchase);
      if (AuditMode.enabled && !isAuditStorePurchase) {
        logBuyInfo('audit_purchase_update_skipped', {
          'reason': 'store_account_token_mismatch',
          'product_id': purchase.productID,
          'purchase_id': purchase.purchaseID,
          'status': purchase.status.name,
          'purchase_type': purchase.runtimeType.toString(),
          'has_store_account_token':
              _storeAccountTokenForPurchase(purchase)?.isNotEmpty == true,
        });
        continue;
      }
      if (!AuditMode.enabled && isAuditStorePurchase) {
        logBuyInfo('audit_purchase_update_skipped', {
          'reason': 'audit_store_purchase_outside_audit_mode',
          'product_id': purchase.productID,
          'purchase_id': purchase.purchaseID,
          'status': purchase.status.name,
          'purchase_type': purchase.runtimeType.toString(),
        });
        continue;
      }

      if (purchase.status == PurchaseStatus.pending) {
        if (mounted) {
          setState(() {
            _isPurchasing = true;
          });
        }
        _purchaseSheetState.value = _purchaseSheetState.value.copyWith(
          stage: IosPurchaseStage.awaitingResult,
          activeProductId: purchase.productID,
          clearFailure: true,
        );
        if (!_isPurchaseSheetVisible) {
          _showToast(l10n.billing_ios_purchase_awaiting_result);
        }
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        logBuyInfo('purchase_error_payload', {
          'product_id': purchase.productID,
          'error': _serializePurchaseError(purchase.error),
        });
        if (purchase.pendingCompletePurchase) {
          logBuyIapRequest(
            action: 'completePurchase',
            payload: {
              'scene': 'purchaseError',
              'purchase': _serializePurchaseDetails(purchase),
            },
          );
          await InAppPurchase.instance.completePurchase(purchase);
          logBuyIapResponse(
            action: 'completePurchase',
            payload: {
              'scene': 'purchaseError',
              'completed': true,
              'product_id': purchase.productID,
              'purchase_id': purchase.purchaseID,
            },
          );
        }
        _clearPendingOrder();
        if (mounted) {
          setState(() {
            _isPurchasing = false;
          });
        }
        _setSheetFailure(
          IosPurchaseFailureKind.generic,
          activeProductId: purchase.productID,
        );
        continue;
      }

      if (purchase.status == PurchaseStatus.canceled) {
        _clearPendingOrder();

        if (purchase.pendingCompletePurchase) {
          logBuyIapRequest(
            action: 'completePurchase',
            payload: {
              'scene': 'purchaseCanceled',
              'purchase': _serializePurchaseDetails(purchase),
            },
          );
          await InAppPurchase.instance.completePurchase(purchase);
          logBuyIapResponse(
            action: 'completePurchase',
            payload: {
              'scene': 'purchaseCanceled',
              'completed': true,
              'product_id': purchase.productID,
              'purchase_id': purchase.purchaseID,
            },
          );
        }
        if (mounted) {
          setState(() {
            _isPurchasing = false;
          });
        }
        _setSheetFailure(
          IosPurchaseFailureKind.cancelled,
          activeProductId: purchase.productID,
        );
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased) {
        try {
          _purchaseSheetState.value = _purchaseSheetState.value.copyWith(
            stage: IosPurchaseStage.verifying,
            activeProductId: purchase.productID,
            clearFailure: true,
          );
          final delivered = AuditMode.enabled
              ? _deliverAuditPurchaseLocally(purchase)
              : await _deliverPurchaseToServer(purchase);

          if (!delivered) {
            if (mounted) {
              setState(() {
                _isPurchasing = false;
              });
            }
            _setSheetFailure(
              IosPurchaseFailureKind.deliveryFailed,
              activeProductId: purchase.productID,
            );
            continue;
          }

          await _completeDeliveredPurchase(
            purchase,
            scene: 'purchaseSuccess',
            allowAuditFallback: AuditMode.enabled,
          );

          await widget.onPurchaseSuccess?.call();
          _closePurchaseSheet();
          unawaited(_loadProducts());
          _clearPendingOrder();
          _showToast(l10n.billing_purchase_success);
          if (!mounted) return;
          setState(() {
            _isPurchasing = false;
          });
          _purchaseSheetState.value = const IosPurchaseSheetState();
        } catch (error, stackTrace) {
          AppLog.instance.error(
            'Failed to deliver iOS IAP purchase to server',
            tag: BizLogTag.buy.tag,
            error: error,
            stackTrace: stackTrace,
          );
          if (!mounted) return;
          setState(() {
            _isPurchasing = false;
          });
          _setSheetFailure(
            IosPurchaseFailureKind.generic,
            activeProductId: purchase.productID,
          );
        }
      }
    }
  }

  bool _isAuditStorePurchase(PurchaseDetails purchase) {
    return _matchesAuditStoreToken(_storeAccountTokenForPurchase(purchase));
  }

  String? _storeAccountTokenForPurchase(PurchaseDetails purchase) {
    if (purchase is SK2PurchaseDetails) {
      return purchase.appAccountToken;
    }
    if (purchase is AppStorePurchaseDetails) {
      return purchase.skPaymentTransaction.payment.applicationUsername;
    }
    return null;
  }

  bool _matchesAuditStoreToken(String? token) {
    final normalizedToken = token?.trim().toUpperCase();
    return normalizedToken == AuditMode.auditStoreAccountToken;
  }

  bool _deliverAuditPurchaseLocally(PurchaseDetails purchase) {
    if (!_isAuditStorePurchase(purchase)) {
      logBuyInfo('deliver_audit_purchase_failed', {
        'reason': 'store_account_token_mismatch',
        'product_id': purchase.productID,
        'purchase_id': purchase.purchaseID,
      });
      return false;
    }

    final purchaseKey =
        purchase.purchaseID ??
        '${purchase.productID}:${purchase.transactionDate ?? ''}';
    final matchedProduct = _findCatalogProduct(purchase.productID);
    final credits = matchedProduct?.creditAmount.toDouble() ?? 0;

    if (credits <= 0) {
      logBuyInfo('deliver_audit_purchase_failed', {
        'reason': 'missing_catalog_product',
        'product_id': purchase.productID,
      });
      return false;
    }

    ref
        .read(auditBillingProvider.notifier)
        .recordReviewPurchase(
          purchaseKey: purchaseKey,
          productName: matchedProduct?.displayName ?? purchase.productID,
          credits: credits,
        );
    logBuyInfo('deliver_audit_purchase_locally', {
      'product_id': purchase.productID,
      'purchase_id': purchase.purchaseID,
      'credits': credits,
    });
    return true;
  }

  AppleIapProductData? _findCatalogProduct(String productId) {
    for (final product in _products) {
      if (product.productId == productId) {
        return product;
      }
    }
    for (final product in _auditFallbackProducts) {
      if (product.productId == productId) {
        return product;
      }
    }
    return null;
  }

  Future<bool> _deliverPurchaseToServer(PurchaseDetails purchase) async {
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;

    if (accessToken == null || accessToken.isEmpty) {
      logBuyInfo('deliver_purchase_failed', {'reason': 'missing_access_token'});
      return false;
    }

    final signedTransactionInfo = purchase
        .verificationData
        .serverVerificationData
        .trim();
    if (signedTransactionInfo.isEmpty) {
      logBuyInfo('deliver_purchase_failed', {
        'reason': 'missing_signed_transaction_info',
      });
      return false;
    }
    _logPurchaseDetails('deliver_purchase_input', purchase);
    final signedTransactionPreview = signedTransactionInfo.length <= 12
        ? signedTransactionInfo
        : '${signedTransactionInfo.substring(0, 12)}...';
    logBuyInfo('signed_transaction_info', {
      'product_id': purchase.productID,
      'length': signedTransactionInfo.length,
      'value_preview': signedTransactionPreview,
    });

    final verificationContext = await _resolveVerificationContext(
      accessToken: accessToken,
      productId: purchase.productID,
    );
    if (verificationContext == null) {
      logBuyInfo('deliver_purchase_failed', {
        'reason': 'verification_context_not_found',
        'product_id': purchase.productID,
      });
      return false;
    }
    logBuyInfo('verification_context_resolved', {
      'product_id': purchase.productID,
      'package_code': verificationContext.packageCode,
      'order_id': verificationContext.orderId,
    });

    final result = await _iosIapRepository.verifyAppleIapOneTimePurchase(
      accessToken: accessToken,
      packageCode: verificationContext.packageCode,
      signedTransactionInfo: signedTransactionInfo,
      orderId: verificationContext.orderId,
    );

    return result.status == 'granted' || result.status == 'already_granted';
  }

  Future<void> _completeDeliveredPurchase(
    PurchaseDetails purchase, {
    required String scene,
    required bool allowAuditFallback,
  }) async {
    if (purchase.pendingCompletePurchase) {
      logBuyIapRequest(
        action: 'completePurchase',
        payload: {
          'scene': scene,
          'purchase': _serializePurchaseDetails(purchase),
        },
      );
      await InAppPurchase.instance.completePurchase(purchase);
      logBuyIapResponse(
        action: 'completePurchase',
        payload: {
          'scene': scene,
          'completed': true,
          'product_id': purchase.productID,
          'purchase_id': purchase.purchaseID,
        },
      );
      return;
    }

    if (!allowAuditFallback) {
      logBuyIapResponse(
        action: 'completePurchase',
        payload: {
          'scene': scene,
          'skipped': true,
          'product_id': purchase.productID,
          'purchase_id': purchase.purchaseID,
          'pending_complete_purchase': purchase.pendingCompletePurchase,
        },
      );
      return;
    }

    await _tryFinalizeAuditStoreTransactions(
      productId: purchase.productID,
      purchaseId: purchase.purchaseID,
      scene: '$scene:fallbackFinishTransaction',
    );
  }

  Future<void> _tryFinalizeAuditStoreTransactions({
    required String productId,
    String? purchaseId,
    required String scene,
  }) async {
    if (productId.isEmpty) {
      return;
    }

    try {
      final finishedSk2Count = await _finishAuditStoreKit2Transactions(
        productId: productId,
        purchaseId: purchaseId,
        scene: scene,
      );
      final finishedSk1Count = await _finishAuditStoreKit1Transactions(
        productId: productId,
        purchaseId: purchaseId,
        scene: scene,
      );
      logBuyInfo('audit_store_transactions_finalize_result', {
        'scene': scene,
        'product_id': productId,
        'purchase_id': purchaseId,
        'finished_sk2_count': finishedSk2Count,
        'finished_sk1_count': finishedSk1Count,
      });
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        'Failed to finalize audit-mode iOS store transactions',
        tag: BizLogTag.buy.tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<int> _finishAuditStoreKit2Transactions({
    required String productId,
    String? purchaseId,
    required String scene,
  }) async {
    final unfinishedTransactions =
        await SK2Transaction.unfinishedTransactions();
    var finishedCount = 0;

    for (final transaction in unfinishedTransactions) {
      final matchesProduct = transaction.productId == productId;
      final matchesPurchase =
          purchaseId == null || transaction.id == purchaseId;
      final matchesAuditStoreToken = _matchesAuditStoreToken(
        transaction.appAccountToken,
      );
      if (!matchesProduct || !matchesPurchase || !matchesAuditStoreToken) {
        continue;
      }

      final transactionId = int.tryParse(transaction.id);
      if (transactionId == null) {
        logBuyInfo('audit_storekit2_finish_skipped', {
          'scene': scene,
          'reason': 'invalid_transaction_id',
          'product_id': productId,
          'purchase_id': purchaseId,
          'transaction_id': transaction.id,
        });
        continue;
      }

      logBuyIapRequest(
        action: 'finishTransaction',
        payload: {
          'scene': scene,
          'storekit': 2,
          'product_id': productId,
          'purchase_id': purchaseId,
          'transaction_id': transaction.id,
          'app_account_token': transaction.appAccountToken,
        },
      );
      await SK2Transaction.finish(transactionId);
      finishedCount += 1;
      logBuyIapResponse(
        action: 'finishTransaction',
        payload: {
          'scene': scene,
          'storekit': 2,
          'finished': true,
          'product_id': productId,
          'purchase_id': purchaseId,
          'transaction_id': transaction.id,
        },
      );
    }

    return finishedCount;
  }

  Future<int> _finishAuditStoreKit1Transactions({
    required String productId,
    String? purchaseId,
    required String scene,
  }) async {
    final queue = SKPaymentQueueWrapper();
    final transactions = await queue.transactions();
    var finishedCount = 0;

    for (final transaction in transactions) {
      final transactionId = transaction.transactionIdentifier;
      final matchesProduct = transaction.payment.productIdentifier == productId;
      final matchesPurchase = purchaseId == null || transactionId == purchaseId;
      final matchesAuditStoreToken = _matchesAuditStoreToken(
        transaction.payment.applicationUsername,
      );
      final finishable =
          transaction.transactionState !=
              SKPaymentTransactionStateWrapper.purchasing &&
          transaction.transactionState !=
              SKPaymentTransactionStateWrapper.deferred;
      if (!matchesProduct ||
          !matchesPurchase ||
          !matchesAuditStoreToken ||
          !finishable) {
        continue;
      }

      logBuyIapRequest(
        action: 'finishTransaction',
        payload: {
          'scene': scene,
          'storekit': 1,
          'product_id': productId,
          'purchase_id': purchaseId,
          'transaction_id': transactionId,
          'transaction_state': transaction.transactionState.name,
          'application_username': transaction.payment.applicationUsername,
        },
      );
      await queue.finishTransaction(transaction);
      finishedCount += 1;
      logBuyIapResponse(
        action: 'finishTransaction',
        payload: {
          'scene': scene,
          'storekit': 1,
          'finished': true,
          'product_id': productId,
          'purchase_id': purchaseId,
          'transaction_id': transactionId,
        },
      );
    }

    return finishedCount;
  }

  Future<_AppleIapVerificationContext?> _resolveVerificationContext({
    required String accessToken,
    required String productId,
  }) async {
    final pendingContext = ref.read(iosIapOrderContextProvider);
    if (pendingContext != null &&
        pendingContext.packageCode.isNotEmpty &&
        pendingContext.productId == productId) {
      return _AppleIapVerificationContext(
        packageCode: pendingContext.packageCode,
        orderId: pendingContext.orderId,
      );
    }

    final catalogProducts = await _iosIapRepository.fetchAppleIapProducts(
      accessToken: accessToken,
    );
    final matchedProduct = catalogProducts
        .where((item) => item.productId == productId)
        .firstOrNull;
    if (matchedProduct == null) {
      logBuyInfo('verification_context_lookup_miss', {
        'product_id': productId,
        'catalog_count': catalogProducts.length,
      });
      return null;
    }
    logBuyInfo('verification_context_lookup_hit', {
      'product_id': productId,
      'package_code': matchedProduct.packageCode,
    });
    return _AppleIapVerificationContext(
      packageCode: matchedProduct.packageCode,
    );
  }

  void _clearPendingOrder() {
    final pendingContext = ref.read(iosIapOrderContextProvider);
    logBuyInfo('pending_order_cleared', {
      'order_id': pendingContext?.orderId,
      'package_code': pendingContext?.packageCode,
      'product_id': pendingContext?.productId,
    });
    ref.read(iosIapOrderContextProvider.notifier).clear();
  }

  void _logPurchaseDetails(String event, PurchaseDetails purchase) {
    logBuyInfo(event, {
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
      'error': _serializePurchaseError(purchase.error),
    });
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
      'error': _serializePurchaseError(purchase.error),
    };
  }

  Map<String, dynamic> _serializeProductDetails(ProductDetails product) {
    return {
      'id': product.id,
      'title': product.title,
      'description': product.description,
      'price': product.price,
      'raw_price': product.rawPrice,
      'currency_code': product.currencyCode,
      'currency_symbol': product.currencySymbol,
    };
  }

  Map<String, dynamic>? _serializeIapError(IAPError? error) {
    if (error == null) return null;
    return {
      'source': error.source,
      'code': error.code,
      'message': error.message,
      'details': error.details,
    };
  }

  Map<String, dynamic>? _serializePurchaseError(IAPError? error) {
    if (error == null) return null;
    return {
      'source': error.source,
      'code': error.code,
      'message': error.message,
      'details': error.details,
    };
  }

  @override
  Widget build(BuildContext context) {
    final buttonLabel = _buttonLabel(context);

    return PurchaseEntryButton(
      label: buttonLabel,
      isLoading: _isPurchasing,
      onPressed: _isPurchasing ? null : _handlePressed,
    );
  }

  String _buttonLabel(BuildContext context) {
    return context.l10n.billing_buy_credits;
  }

  void _closePurchaseSheet() {
    if (!_isPurchaseSheetVisible || !mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  void _setSheetFailure(
    IosPurchaseFailureKind kind, {
    String? activeProductId,
  }) {
    _purchaseSheetState.value = _purchaseSheetState.value.copyWith(
      stage: IosPurchaseStage.failure,
      activeProductId: activeProductId,
      failureKind: kind,
    );
    if (!_isPurchaseSheetVisible) {
      _showToast(_failureMessage(kind));
    }
  }

  String _failureMessage(IosPurchaseFailureKind kind) {
    final l10n = context.l10n;
    return switch (kind) {
      IosPurchaseFailureKind.signInRequired =>
        l10n.billing_purchase_sign_in_first,
      IosPurchaseFailureKind.storeUnavailable =>
        l10n.billing_ios_purchase_store_unavailable,
      IosPurchaseFailureKind.productNotFound =>
        l10n.billing_ios_purchase_product_not_found,
      IosPurchaseFailureKind.cancelled => l10n.billing_purchase_cancelled,
      IosPurchaseFailureKind.deliveryFailed =>
        l10n.billing_purchase_delivery_failed,
      IosPurchaseFailureKind.generic => l10n.billing_purchase_failed,
    };
  }

  void _showToast(String message) {
    Fluttertoast.showToast(msg: message);
  }
}

class _AppleIapVerificationContext {
  const _AppleIapVerificationContext({required this.packageCode, this.orderId});

  final String packageCode;
  final String? orderId;
}
