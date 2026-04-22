import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_environment.dart';
import '../../core/log/app_log.dart';
import '../../core/models/android_iap_models.dart';
import 'billing_repository.dart';

class AndroidIapRepository {
  Future<List<AndroidIapProductData>> fetchAndroidIapProducts({
    required String accessToken,
  }) async {
    final response = await http.get(
      Uri.parse(
        '${AppEnvironment.apiServerUrl}/api/billing/google-play/products',
      ),
      headers: {'X-Access-Token': accessToken},
    );
    _logResponse(
      event: 'server_products_response',
      endpoint: '/api/billing/google-play/products',
      response: response,
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_android_iap_products] non-200: ${response.statusCode} ${response.body}',
        tag: 'BillingApi',
      );
      throw BillingRequestException('HTTP ${response.statusCode}');
    }

    final decoded = _decodeResponse(
      response.body,
      endpoint: 'android_iap_products',
    );
    final data = decoded['data'];
    if (data is! List) {
      throw const BillingRequestException('Invalid response data');
    }

    final products = data
        .whereType<Map>()
        .map(
          (item) => AndroidIapProductData.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .where(
          (item) => item.packageCode.isNotEmpty && item.productId.isNotEmpty,
        )
        .toList(growable: false);
    AppLog.instance.debug(
      jsonEncode({
        'event': 'server_products_parsed',
        'count': products.length,
        'products': products
            .map((item) => item.toJson())
            .toList(growable: false),
      }),
      tag: 'AndroidIap',
    );
    return products;
  }

  Future<AndroidIapOrderData> createAndroidIapOrder({
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
    _logResponse(
      event: 'server_order_response',
      endpoint: '/api/billing/google-play/orders',
      response: response,
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_android_iap_order] non-200: ${response.statusCode} ${response.body}',
        tag: 'BillingApi',
      );
      throw BillingRequestException('HTTP ${response.statusCode}');
    }

    final decoded = _decodeResponse(
      response.body,
      endpoint: 'android_iap_order',
    );
    final data = _requireDataMap(decoded, endpoint: 'android_iap_order');
    final order = AndroidIapOrderData.fromJson(data);
    AppLog.instance.debug(
      jsonEncode({'event': 'server_order_parsed', 'order': order.toJson()}),
      tag: 'AndroidIap',
    );
    return order;
  }

  Future<AndroidIapVerifyResult> verifyAndroidIapPurchase({
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
    _logResponse(
      event: 'server_verify_response',
      endpoint: '/api/billing/google-play/purchases/one-time/verify',
      response: response,
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_android_iap_verify] non-200: ${response.statusCode} ${response.body}',
        tag: 'BillingApi',
      );
      throw BillingRequestException('HTTP ${response.statusCode}');
    }

    final decoded = _decodeResponse(
      response.body,
      endpoint: 'android_iap_verify',
    );
    final data = _requireDataMap(decoded, endpoint: 'android_iap_verify');
    final result = AndroidIapVerifyResult.fromJson(data);
    AppLog.instance.debug(
      jsonEncode({'event': 'server_verify_parsed', 'result': result.toJson()}),
      tag: 'AndroidIap',
    );
    return result;
  }

  void _logResponse({
    required String event,
    required String endpoint,
    required http.Response response,
  }) {
    AppLog.instance.debug(
      jsonEncode({
        'event': event,
        'endpoint': endpoint,
        'status_code': response.statusCode,
        'body': _decodeBodyForLog(response.body),
      }),
      tag: 'AndroidIap',
    );
  }

  Object? _decodeBodyForLog(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
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
