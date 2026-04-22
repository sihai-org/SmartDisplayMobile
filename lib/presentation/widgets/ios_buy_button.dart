import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/log/app_log.dart';
import '../../data/repositories/ios_iap_repository.dart';
import 'ios_product_sheet.dart';

class IosBuyButton extends StatefulWidget {
  const IosBuyButton({super.key, this.onPurchaseSuccess});

  final Future<void> Function()? onPurchaseSuccess;

  @override
  State<IosBuyButton> createState() => _IosBuyButtonState();
}

class _IosBuyButtonState extends State<IosBuyButton> {
  final IosIapRepository _iosIapRepository = IosIapRepository();
  late final StreamSubscription<List<PurchaseDetails>> _purchaseSubscription;

  List<AppleIapProductData> _products = const [];
  bool _isProductsLoading = false;
  bool _hasProductsError = false;
  bool _isPurchasing = false;

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
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      if (!mounted) return;
      setState(() {
        _products = const [];
        _isProductsLoading = false;
        _hasProductsError = true;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isProductsLoading = true;
        _hasProductsError = false;
      });
    }

    try {
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
      if (!mounted) return;
      setState(() {
        _products = List<AppleIapProductData>.unmodifiable(products);
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

  Future<void> _handlePressed() async {
    if (_isProductsLoading || _isPurchasing) return;

    if (_hasProductsError) {
      await _loadProducts();
      return;
    }

    if (_products.isEmpty) {
      Fluttertoast.showToast(msg: 'No iOS products available');
      return;
    }

    final product = await showModalBottomSheet<AppleIapProductData>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) => IosProductSheet(
        products: _products,
        isLoading: _isProductsLoading,
        hasError: _hasProductsError,
        onRetry: _loadProducts,
      ),
    );
    if (product == null) return;

    await _purchase(product);
  }

  Future<void> _purchase(AppleIapProductData catalogProduct) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final accessToken =
          Supabase.instance.client.auth.currentSession?.accessToken;
      if (user == null || accessToken == null || accessToken.isEmpty) {
        Fluttertoast.showToast(msg: 'Please sign in first');
        return;
      }

      if (mounted) {
        setState(() {
          _isPurchasing = true;
        });
      }

      final isAvailable = await InAppPurchase.instance.isAvailable();
      _logIapDebug('store_availability', {'is_available': isAvailable});

      if (!isAvailable) {
        Fluttertoast.showToast(msg: 'App Store unavailable');
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

      final response = await InAppPurchase.instance
          .queryProductDetails({order.productId})
          .timeout(const Duration(seconds: 15));

      _logProductQueryResponse(response);

      if (response.productDetails.isEmpty) {
        _clearPendingOrder();
        Fluttertoast.showToast(msg: 'Product not found');
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

      if (!started && mounted) {
        setState(() {
          _isPurchasing = false;
        });
      }
    } catch (error, stackTrace) {
      _clearPendingOrder();
      AppLog.instance.error(
        'Unexpected error during iOS IAP purchase flow',
        tag: 'IosIap',
        error: error,
        stackTrace: stackTrace,
      );
      Fluttertoast.showToast(msg: 'IAP error: $error');
      if (!mounted) return;
      setState(() {
        _isPurchasing = false;
      });
    }
  }

  Future<void> _onPurchaseUpdated(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
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
        Fluttertoast.showToast(msg: 'Purchase pending');
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        _logIapDebug('purchase_error_payload', {
          'product_id': purchase.productID,
          'error': _serializePurchaseError(purchase.error),
        });
        _clearPendingOrder();
        Fluttertoast.showToast(
          msg: 'Purchase error: ${purchase.error?.message ?? 'unknown'}',
        );
        if (mounted) {
          setState(() {
            _isPurchasing = false;
          });
        }
        continue;
      }

      if (purchase.status == PurchaseStatus.canceled) {
        _clearPendingOrder();
        Fluttertoast.showToast(msg: 'Purchase canceled');

        if (purchase.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchase);
        }
        if (mounted) {
          setState(() {
            _isPurchasing = false;
          });
        }
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased) {
        try {
          final delivered = await _deliverPurchaseToServer(purchase);

          if (!delivered) {
            Fluttertoast.showToast(msg: 'Token delivery failed');
            if (mounted) {
              setState(() {
                _isPurchasing = false;
              });
            }
            continue;
          }

          await widget.onPurchaseSuccess?.call();
          await _loadProducts();

          if (purchase.pendingCompletePurchase) {
            await InAppPurchase.instance.completePurchase(purchase);
          }

          _clearPendingOrder();
          Fluttertoast.showToast(msg: 'Purchase applied');
          if (!mounted) return;
          setState(() {
            _isPurchasing = false;
          });
        } catch (error, stackTrace) {
          AppLog.instance.error(
            'Failed to deliver iOS IAP purchase to server',
            tag: 'IosIap',
            error: error,
            stackTrace: stackTrace,
          );
          Fluttertoast.showToast(msg: 'Token delivery failed');
          if (!mounted) return;
          setState(() {
            _isPurchasing = false;
          });
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
    final theme = Theme.of(context);
    final buttonLabel = _buttonLabel();

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: FilledButton(
        onPressed: (_isProductsLoading || _isPurchasing)
            ? null
            : _handlePressed,
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          foregroundColor: theme.colorScheme.primary,
          disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest,
          disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
          shape: const StadiumBorder(),
          textStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        child: _isProductsLoading || _isPurchasing
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(buttonLabel),
                ],
              )
            : Text(buttonLabel),
      ),
    );
  }

  String _buttonLabel() {
    if (_isPurchasing) return 'Purchasing...';
    if (_isProductsLoading) return 'Loading...';
    if (_hasProductsError) return 'Retry purchase';
    return 'Buy credits';
  }
}

class _AppleIapVerificationContext {
  const _AppleIapVerificationContext({required this.packageCode, this.orderId});

  final String packageCode;
  final String? orderId;
}
