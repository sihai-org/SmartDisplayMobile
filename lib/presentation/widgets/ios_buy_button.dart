import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/log/app_log.dart';
import '../../data/repositories/ios_iap_repository.dart';
import 'ios_product_sheet.dart';
import 'purchase_ui/purchase_entry_button.dart';

class IosBuyButton extends StatefulWidget {
  const IosBuyButton({super.key, this.onPurchaseSuccess});

  final Future<void> Function()? onPurchaseSuccess;

  @override
  State<IosBuyButton> createState() => _IosBuyButtonState();
}

class _IosBuyButtonState extends State<IosBuyButton> {
  final IosIapRepository _iosIapRepository = IosIapRepository();
  final ValueNotifier<IosPurchaseSheetState> _purchaseSheetState =
      ValueNotifier(const IosPurchaseSheetState());
  late final StreamSubscription<List<PurchaseDetails>> _purchaseSubscription;

  List<AppleIapProductData> _products = const [];
  bool _isProductsLoading = false;
  bool _hasProductsError = false;
  bool _isPurchasing = false;
  bool _isPurchaseSheetVisible = false;

  String? _pendingOrderId;
  String? _pendingPackageCode;
  String? _pendingProductId;

  @override
  void initState() {
    super.initState();
    _purchaseSubscription = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdated,
      onDone: () => _purchaseSubscription.cancel(),
      onError: (error) {
        debugPrint('purchaseStream error: $error');
      },
    );
    _loadProducts();
  }

  @override
  void dispose() {
    _purchaseSubscription.cancel();
    _purchaseSheetState.dispose();
    super.dispose();
  }

  Future<List<AppleIapProductData>> _requestProducts() async {
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Missing access token');
    }

    final products = await _iosIapRepository.fetchAppleIapProducts(
      accessToken: accessToken,
    );
    products.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _logIapDebug('catalog_products_loaded', {
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
              'sort_order': item.sortOrder,
            },
          )
          .toList(growable: false),
    });
    return List<AppleIapProductData>.unmodifiable(products);
  }

  Future<void> _loadProducts() async {
    if (mounted) {
      setState(() {
        _isProductsLoading = true;
        _hasProductsError = false;
      });
    }

    try {
      final products = await _requestProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _isProductsLoading = false;
        _hasProductsError = false;
      });
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when fetching Apple IAP products',
        tag: 'BillingApi',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _products = const [];
        _isProductsLoading = false;
        _hasProductsError = true;
      });
    }
  }

  Future<List<AppleIapProductData>> _reloadProductsForSheet() async {
    if (mounted) {
      setState(() {
        _isProductsLoading = true;
        _hasProductsError = false;
      });
    }

    try {
      final products = await _requestProducts();
      if (!mounted) return products;
      setState(() {
        _products = products;
        _isProductsLoading = false;
        _hasProductsError = false;
      });
      return products;
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when reloading Apple IAP products',
        tag: 'BillingApi',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _products = const [];
          _isProductsLoading = false;
          _hasProductsError = true;
        });
      }
      rethrow;
    }
  }

  Future<void> _handlePressed() async {
    if (_isProductsLoading || _isPurchasing) return;

    if (_hasProductsError) {
      await _loadProducts();
      return;
    }

    if (_products.isEmpty) {
      _showToast(context.l10n.billing_products_empty);
      return;
    }

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
      final user = Supabase.instance.client.auth.currentUser;
      final accessToken =
          Supabase.instance.client.auth.currentSession?.accessToken;
      if (user == null || accessToken == null || accessToken.isEmpty) {
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

      final isAvailable = await InAppPurchase.instance.isAvailable();
      _logIapDebug('store_availability', {'is_available': isAvailable});

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

      final order = await _iosIapRepository.createAppleIapOrder(
        accessToken: accessToken,
        packageCode: catalogProduct.packageCode,
      );

      _pendingOrderId = order.orderId;
      _pendingPackageCode = order.packageCode;
      _pendingProductId = order.productId;
      _logIapDebug('pending_order_created', {
        'order_id': _pendingOrderId,
        'package_code': _pendingPackageCode,
        'product_id': _pendingProductId,
      });
      _purchaseSheetState.value = _purchaseSheetState.value.copyWith(
        stage: IosPurchaseStage.purchasing,
        activeProductId: order.productId,
        clearFailure: true,
      );

      final response = await InAppPurchase.instance
          .queryProductDetails({order.productId})
          .timeout(const Duration(seconds: 15));

      _logProductQueryResponse(response);

      if (response.productDetails.isEmpty) {
        _clearPendingOrder();
        if (mounted) {
          setState(() {
            _isPurchasing = false;
          });
        }
        _setSheetFailure(
          IosPurchaseFailureKind.productNotFound,
          activeProductId: catalogProduct.productId,
        );
        return;
      }

      final product = response.productDetails.first;
      final purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: user.id,
      );
      _logIapDebug('buy_consumable_request', {
        'application_user_name': user.id,
        'product_id': product.id,
        'title': product.title,
        'description': product.description,
        'price': product.price,
        'currency_code': product.currencyCode,
        'currency_symbol': product.currencySymbol,
        'raw_price': product.rawPrice,
      });

      final started = await InAppPurchase.instance.buyConsumable(
        purchaseParam: purchaseParam,
      );
      _logIapDebug('buy_consumable_started', {'started': started});

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
        tag: 'IosIap',
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

    _logIapDebug('purchase_stream_batch', {
      'count': purchaseDetailsList.length,
    });
    for (final purchase in purchaseDetailsList) {
      _logPurchaseDetails('purchase_update', purchase);

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
        _logIapDebug('purchase_error_payload', {
          'product_id': purchase.productID,
          'error': _serializePurchaseError(purchase.error),
        });
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
          await InAppPurchase.instance.completePurchase(purchase);
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
          final delivered = await _deliverPurchaseToServer(purchase);

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

          if (purchase.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchase);
          }

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
            tag: 'IosIap',
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

  Future<bool> _deliverPurchaseToServer(PurchaseDetails purchase) async {
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;

    if (accessToken == null || accessToken.isEmpty) {
      _logIapDebug('deliver_purchase_failed', {
        'reason': 'missing_access_token',
      });
      return false;
    }

    final signedTransactionInfo = purchase
        .verificationData
        .serverVerificationData
        .trim();
    if (signedTransactionInfo.isEmpty) {
      _logIapDebug('deliver_purchase_failed', {
        'reason': 'missing_signed_transaction_info',
      });
      return false;
    }
    _logPurchaseDetails('deliver_purchase_input', purchase);
    _logIapDebug('signed_transaction_info', {
      'product_id': purchase.productID,
      'length': signedTransactionInfo.length,
      'value': signedTransactionInfo,
    });

    final verificationContext = await _resolveVerificationContext(
      accessToken: accessToken,
      productId: purchase.productID,
    );
    if (verificationContext == null) {
      _logIapDebug('deliver_purchase_failed', {
        'reason': 'verification_context_not_found',
        'product_id': purchase.productID,
      });
      return false;
    }
    _logIapDebug('verification_context_resolved', {
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

    _logIapDebug('deliver_purchase_verify_result', {
      'status': result.status,
      'granted': result.granted,
      'grant_id': result.grantId,
      'payment_reference': result.paymentReference,
      'order_id': result.orderId,
    });

    return result.status == 'granted' || result.status == 'already_granted';
  }

  Future<_AppleIapVerificationContext?> _resolveVerificationContext({
    required String accessToken,
    required String productId,
  }) async {
    if (_pendingPackageCode != null &&
        _pendingPackageCode!.isNotEmpty &&
        (_pendingProductId == null || _pendingProductId == productId)) {
      return _AppleIapVerificationContext(
        packageCode: _pendingPackageCode!,
        orderId: _pendingOrderId,
      );
    }

    final catalogProducts = await _iosIapRepository.fetchAppleIapProducts(
      accessToken: accessToken,
    );
    final matchedProduct = catalogProducts
        .where((item) => item.productId == productId)
        .firstOrNull;
    if (matchedProduct == null) {
      _logIapDebug('verification_context_lookup_miss', {
        'product_id': productId,
        'catalog_count': catalogProducts.length,
      });
      return null;
    }
    _logIapDebug('verification_context_lookup_hit', {
      'product_id': productId,
      'package_code': matchedProduct.packageCode,
    });
    return _AppleIapVerificationContext(
      packageCode: matchedProduct.packageCode,
    );
  }

  void _clearPendingOrder() {
    _logIapDebug('pending_order_cleared', {
      'order_id': _pendingOrderId,
      'package_code': _pendingPackageCode,
      'product_id': _pendingProductId,
    });
    _pendingOrderId = null;
    _pendingPackageCode = null;
    _pendingProductId = null;
  }

  void _logProductQueryResponse(ProductDetailsResponse response) {
    _logIapDebug('query_product_details_response', {
      'product_details_count': response.productDetails.length,
      'product_details': response.productDetails
          .map(
            (product) => {
              'id': product.id,
              'title': product.title,
              'description': product.description,
              'price': product.price,
              'raw_price': product.rawPrice,
              'currency_code': product.currencyCode,
              'currency_symbol': product.currencySymbol,
            },
          )
          .toList(growable: false),
      'not_found_ids': response.notFoundIDs,
      'error': response.error == null
          ? null
          : {
              'source': response.error!.source,
              'code': response.error!.code,
              'message': response.error!.message,
              'details': response.error!.details,
            },
    });
  }

  void _logPurchaseDetails(String event, PurchaseDetails purchase) {
    _logIapDebug(event, {
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

  Map<String, dynamic>? _serializePurchaseError(IAPError? error) {
    if (error == null) return null;
    return {
      'source': error.source,
      'code': error.code,
      'message': error.message,
      'details': error.details,
    };
  }

  void _logIapDebug(String event, Map<String, dynamic> payload) {
    AppLog.instance.debug(
      jsonEncode({'event': event, ...payload}),
      tag: 'IosIap',
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttonLabel = _buttonLabel(context);

    return PurchaseEntryButton(
      label: buttonLabel,
      isLoading: _isProductsLoading || _isPurchasing,
      onPressed: (_isProductsLoading || _isPurchasing) ? null : _handlePressed,
    );
  }

  String _buttonLabel(BuildContext context) {
    if (_hasProductsError) return context.l10n.billing_purchase_retry;
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
