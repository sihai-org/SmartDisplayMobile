import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../log/buy_log.dart';
import '../../data/repositories/billing_repository.dart';

class AndroidIapService {
  AndroidIapService({InAppPurchase? inAppPurchase})
    : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;

  Stream<List<PurchaseDetails>> get purchaseStream =>
      _inAppPurchase.purchaseStream;

  Future<bool> isAvailable() async {
    logBuyIapRequest(action: 'isAvailable');
    final isAvailable = await _inAppPurchase.isAvailable();
    logBuyIapResponse(
      action: 'isAvailable',
      payload: {'is_available': isAvailable},
    );
    return isAvailable;
  }

  Future<List<ProductDetails>> queryProductDetails(
    Set<String> productIds,
  ) async {
    if (productIds.isEmpty) return const [];

    logBuyIapRequest(
      action: 'queryProductDetails',
      payload: {'product_ids': productIds.toList(growable: false)},
    );
    final response = await _inAppPurchase.queryProductDetails(productIds);
    logBuyIapResponse(
      action: 'queryProductDetails',
      payload: {
        'product_details_count': response.productDetails.length,
        'product_details': response.productDetails
            .map(_serializeProductDetails)
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
      },
    );
    if (response.error != null && response.productDetails.isEmpty) {
      final message = response.error!.message.trim();
      throw BillingRequestException(
        message.isEmpty ? 'Unable to load Android IAP products' : message,
      );
    }

    return response.productDetails;
  }

  Future<void> launchConsumablePurchase({
    required ProductDetails productDetails,
    required String applicationUserName,
  }) async {
    final purchaseParam = defaultTargetPlatform == TargetPlatform.android
        ? GooglePlayPurchaseParam(
            productDetails: productDetails,
            applicationUserName: applicationUserName,
          )
        : PurchaseParam(
            productDetails: productDetails,
            applicationUserName: applicationUserName,
          );
    logBuyIapRequest(
      action: 'buyConsumable',
      payload: {
        'auto_consume': false,
        'application_user_name': applicationUserName,
        'product': _serializeProductDetails(productDetails),
      },
    );
    final launched = await _inAppPurchase.buyConsumable(
      purchaseParam: purchaseParam,
      autoConsume: false,
    );
    logBuyIapResponse(
      action: 'buyConsumable',
      payload: {'launched': launched, 'product_id': productDetails.id},
    );
    if (!launched) {
      throw const BillingRequestException(
        'Unable to start Android IAP purchase',
      );
    }
  }

  Future<void> completePendingPurchase(PurchaseDetails purchase) async {
    logBuyIapRequest(
      action: 'completePurchase',
      payload: {'purchase': _serializePurchaseDetails(purchase)},
    );
    if (!purchase.pendingCompletePurchase) {
      logBuyIapResponse(
        action: 'completePurchase',
        payload: {
          'skipped': true,
          'product_id': purchase.productID,
          'pending_complete_purchase': purchase.pendingCompletePurchase,
        },
      );
      return;
    }
    await _inAppPurchase.completePurchase(purchase);
    logBuyIapResponse(
      action: 'completePurchase',
      payload: {
        'completed': true,
        'product_id': purchase.productID,
        'purchase_id': purchase.purchaseID,
      },
    );
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
}
