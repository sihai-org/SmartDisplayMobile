import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_environment.dart';
import '../../core/log/app_log.dart';
import '../../core/models/billing_purchase_models.dart';
import 'billing_repository.dart';

class BillingPurchaseRepository {
  Future<List<GooglePlayCatalogProduct>> fetchGooglePlayProducts({
    required String accessToken,
  }) async {
    final response = await http.get(
      Uri.parse(
        '${AppEnvironment.apiServerUrl}/api/billing/google-play/products',
      ),
      headers: {'X-Access-Token': accessToken},
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_purchase_products] non-200: ${response.statusCode} ${response.body}',
        tag: 'BillingApi',
      );
      throw BillingRequestException('HTTP ${response.statusCode}');
    }

    final decoded = _decodeResponse(
      response.body,
      endpoint: 'google_play_products',
    );
    final data = decoded['data'];
    if (data is! List) {
      throw const BillingRequestException('Invalid response data');
    }

    return data
        .whereType<Map>()
        .map(
          (item) => GooglePlayCatalogProduct.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where(
          (item) => item.packageCode.isNotEmpty && item.productId.isNotEmpty,
        )
        .toList(growable: false);
  }

  Future<GooglePlayCreateOrderResponse> createGooglePlayOrder({
    required String accessToken,
    required String packageCode,
  }) async {
    final response = await http.post(
      Uri.parse(
        '${AppEnvironment.apiServerUrl}/api/billing/google-play/orders',
      ),
      headers: {
        'Content-Type': 'application/json',
        'X-Access-Token': accessToken,
      },
      body: jsonEncode({'package_code': packageCode}),
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_purchase_create_order] non-200: ${response.statusCode} ${response.body}',
        tag: 'BillingApi',
      );
      throw BillingRequestException('HTTP ${response.statusCode}');
    }

    final decoded = _decodeResponse(
      response.body,
      endpoint: 'google_play_order',
    );
    final data = _requireDataMap(decoded, endpoint: 'google_play_order');
    return GooglePlayCreateOrderResponse.fromJson(data);
  }

  Future<GooglePlayVerifyResponse> verifyGooglePlayPurchase({
    required String accessToken,
    required String packageCode,
    required String productId,
    required String purchaseToken,
    String? orderId,
    String? packageName,
  }) async {
    final response = await http.post(
      Uri.parse(
        '${AppEnvironment.apiServerUrl}/api/billing/google-play/purchases/one-time/verify',
      ),
      headers: {
        'Content-Type': 'application/json',
        'X-Access-Token': accessToken,
      },
      body: jsonEncode({
        'order_id': orderId,
        'package_code': packageCode,
        'product_id': productId,
        'purchase_token': purchaseToken,
        'package_name': packageName,
      }),
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_purchase_verify] non-200: ${response.statusCode} ${response.body}',
        tag: 'BillingApi',
      );
      throw BillingRequestException('HTTP ${response.statusCode}');
    }

    final decoded = _decodeResponse(
      response.body,
      endpoint: 'google_play_verify',
    );
    final data = _requireDataMap(decoded, endpoint: 'google_play_verify');
    return GooglePlayVerifyResponse.fromJson(data);
  }

  Map<String, dynamic> _decodeResponse(
    String body, {
    required String endpoint,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      AppLog.instance.warning(
        '[billing_$endpoint] invalid body: $body',
        tag: 'BillingApi',
      );
      throw const BillingRequestException('Invalid response');
    }

    final map = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (map['code'] != 200) {
      final message = map['message']?.toString().trim();
      AppLog.instance.warning(
        '[billing_$endpoint] code=${map['code']} message=$message',
        tag: 'BillingApi',
      );
      throw BillingRequestException(
        message == null || message.isEmpty ? 'Request failed' : message,
      );
    }

    return map;
  }

  Map<String, dynamic> _requireDataMap(
    Map<String, dynamic> response, {
    required String endpoint,
  }) {
    final data = response['data'];
    if (data is! Map) {
      AppLog.instance.warning(
        '[billing_$endpoint] invalid data: $response',
        tag: 'BillingApi',
      );
      throw const BillingRequestException('Invalid response data');
    }
    return data.map((key, value) => MapEntry(key.toString(), value));
  }
}
