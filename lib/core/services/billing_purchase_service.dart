import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../../data/repositories/billing_repository.dart';

class BillingPurchaseService {
  BillingPurchaseService({InAppPurchase? inAppPurchase})
    : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;

  Stream<List<PurchaseDetails>> get purchaseStream =>
      _inAppPurchase.purchaseStream;

  Future<bool> isAvailable() {
    return _inAppPurchase.isAvailable();
  }

  Future<List<ProductDetails>> queryProducts(Set<String> productIds) async {
    if (productIds.isEmpty) return const [];

    final response = await _inAppPurchase.queryProductDetails(productIds);
    if (response.error != null && response.productDetails.isEmpty) {
      final message = response.error!.message.trim();
      throw BillingRequestException(
        message.isEmpty ? 'Unable to load Google Play products' : message,
      );
    }

    return response.productDetails;
  }

  Future<void> buyConsumable({
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

    final launched = await _inAppPurchase.buyConsumable(
      purchaseParam: purchaseParam,
      autoConsume: false,
    );
    if (!launched) {
      throw const BillingRequestException(
        'Unable to start Google Play purchase',
      );
    }
  }

  Future<void> completePurchase(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    await _inAppPurchase.completePurchase(purchase);
  }
}
