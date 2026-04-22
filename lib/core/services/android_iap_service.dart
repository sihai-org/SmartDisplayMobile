import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../log/app_log.dart';
import '../../data/repositories/billing_repository.dart';

class AndroidIapService {
  AndroidIapService({InAppPurchase? inAppPurchase})
    : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;

  Stream<List<PurchaseDetails>> get purchaseStream =>
      _inAppPurchase.purchaseStream;

  Future<bool> isAvailable() async {
    final isAvailable = await _inAppPurchase.isAvailable();
    _logDebug('google_play_store_availability', {'is_available': isAvailable});
    return isAvailable;
  }

  Future<List<ProductDetails>> queryProductDetails(
    Set<String> productIds,
  ) async {
    if (productIds.isEmpty) return const [];

    final response = await _inAppPurchase.queryProductDetails(productIds);
    _logProductQueryResponse(productIds, response);
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
    _logDebug('google_play_buy_consumable_request', {
      'application_user_name': applicationUserName,
      'product': _serializeProductDetails(productDetails),
    });
    final purchaseParam = defaultTargetPlatform == TargetPlatform.android
        ? GooglePlayPurchaseParam(
            productDetails: productDetails,
            applicationUserName: applicationUserName,
          )
        : PurchaseParam(
            productDetails: productDetails,
            applicationUserName: applicationUserName,
          );

    final launched = await _inAppPurchase.buyConsumable(
      purchaseParam: purchaseParam,
      autoConsume: false,
    );
    _logDebug('google_play_buy_consumable_result', {
      'launched': launched,
      'product_id': productDetails.id,
    });
    if (!launched) {
      throw const BillingRequestException(
        'Unable to start Android IAP purchase',
      );
    }
  }

  Future<void> completePendingPurchase(PurchaseDetails purchase) async {
    _logDebug('google_play_complete_purchase_request', {
      'purchase': _serializePurchaseDetails(purchase),
    });
    if (!purchase.pendingCompletePurchase) {
      _logDebug('google_play_complete_purchase_skipped', {
        'product_id': purchase.productID,
        'pending_complete_purchase': purchase.pendingCompletePurchase,
      });
      return;
    }
    await _inAppPurchase.completePurchase(purchase);
    _logDebug('google_play_complete_purchase_result', {
      'product_id': purchase.productID,
      'purchase_id': purchase.purchaseID,
      'completed': true,
    });
  }

  void _logProductQueryResponse(
    Set<String> productIds,
    ProductDetailsResponse response,
  ) {
    _logDebug('google_play_query_product_details_response', {
      'requested_product_ids': productIds.toList(growable: false),
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
    });
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

  void _logDebug(String event, Map<String, dynamic> payload) {
    AppLog.instance.debug(
      jsonEncode({'event': event, ...payload}),
      tag: 'AndroidIap',
    );
  }
}
