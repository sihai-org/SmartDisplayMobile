import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_environment.dart';
import '../../core/log/app_log.dart';
import 'billing_repository.dart';

class AppleIapProductData {
  const AppleIapProductData({
    required this.packageCode,
    required this.productId,
    required this.creditAmount,
    this.displayName,
    this.description,
    this.currency,
    this.amount,
    this.sortOrder = 0,
  });

  final String packageCode;
  final String productId;
  final double creditAmount;
  final String? displayName;
  final String? description;
  final String? currency;
  final double? amount;
  final int sortOrder;
}

class AppleIapOrderData {
  const AppleIapOrderData({
    required this.orderId,
    required this.packageCode,
    required this.productId,
    required this.status,
    required this.creditAmount,
    this.currency,
    this.amount,
  });

  final String orderId;
  final String packageCode;
  final String productId;
  final String status;
  final double creditAmount;
  final String? currency;
  final double? amount;
}

class AppleIapVerifyResult {
  const AppleIapVerifyResult({
    required this.status,
    required this.granted,
    this.grantId,
    this.paymentReference,
    this.orderId,
  });

  final String status;
  final bool granted;
  final int? grantId;
  final String? paymentReference;
  final String? orderId;
}

class IosIapRepository {
  Future<List<AppleIapProductData>> fetchAppleIapProducts({
    required String accessToken,
  }) async {
    _logRequest(
      endpoint: 'apple_iap_products',
      method: 'GET',
      path: '/api/billing/apple-iap/products',
    );
    final response = await http.get(
      Uri.parse(
        '${AppEnvironment.apiServerUrl}/api/billing/apple-iap/products',
      ),
      headers: {'X-Access-Token': accessToken},
    );
    _logResponse(
      endpoint: 'apple_iap_products',
      statusCode: response.statusCode,
      responseBody: response.body,
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_apple_iap_products] non-200: ${response.statusCode} ${response.body}',
        tag: 'BillingApi',
      );
      throw BillingRequestException('HTTP ${response.statusCode}');
    }

    final decoded = _decodeResponse(
      response.body,
      endpoint: 'apple_iap_products',
    );
    final data = decoded['data'];
    if (data is! List) {
      AppLog.instance.warning(
        '[billing_apple_iap_products] invalid data: $decoded',
        tag: 'BillingApi',
      );
      throw const BillingRequestException('Invalid response data');
    }

    final products = data
        .whereType<Map>()
        .map(
          (rawItem) =>
              rawItem.map((key, value) => MapEntry(key.toString(), value)),
        )
        .map(
          (item) => AppleIapProductData(
            packageCode: item['package_code']?.toString() ?? '',
            productId: item['product_id']?.toString() ?? '',
            creditAmount: _asDouble(item['credit_amount']),
            displayName: item['display_name']?.toString(),
            description: item['description']?.toString(),
            currency: item['currency']?.toString(),
            amount: _asNullableDouble(item['amount']),
            sortOrder: _asInt(item['sort_order']),
          ),
        )
        .where(
          (item) => item.packageCode.isNotEmpty && item.productId.isNotEmpty,
        )
        .toList(growable: false);
    AppLog.instance.debug(
      jsonEncode({
        'event': 'billing_apple_iap_products_parsed',
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
      }),
      tag: 'BillingApi',
    );
    return products;
  }

  Future<AppleIapOrderData> createAppleIapOrder({
    required String accessToken,
    required String packageCode,
  }) async {
    final requestBody = {'package_code': packageCode};
    _logRequest(
      endpoint: 'apple_iap_order',
      method: 'POST',
      path: '/api/billing/apple-iap/orders',
      requestBody: requestBody,
    );
    final response = await http.post(
      Uri.parse('${AppEnvironment.apiServerUrl}/api/billing/apple-iap/orders'),
      headers: {
        'Content-Type': 'application/json',
        'X-Access-Token': accessToken,
      },
      body: jsonEncode(requestBody),
    );
    _logResponse(
      endpoint: 'apple_iap_order',
      statusCode: response.statusCode,
      responseBody: response.body,
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_apple_iap_order] non-200: ${response.statusCode} ${response.body}',
        tag: 'BillingApi',
      );
      throw BillingRequestException('HTTP ${response.statusCode}');
    }

    final decoded = _decodeResponse(response.body, endpoint: 'apple_iap_order');
    final data = _requireDataMap(decoded, endpoint: 'apple_iap_order');

    final order = AppleIapOrderData(
      orderId: data['order_id']?.toString() ?? '',
      packageCode: data['package_code']?.toString() ?? '',
      productId: data['product_id']?.toString() ?? '',
      status: data['status']?.toString() ?? '',
      creditAmount: _asDouble(data['credit_amount']),
      currency: data['currency']?.toString(),
      amount: _asNullableDouble(data['amount']),
    );
    AppLog.instance.debug(
      jsonEncode({
        'event': 'billing_apple_iap_order_parsed',
        'order_id': order.orderId,
        'package_code': order.packageCode,
        'product_id': order.productId,
        'status': order.status,
        'credit_amount': order.creditAmount,
        'currency': order.currency,
        'amount': order.amount,
      }),
      tag: 'BillingApi',
    );
    return order;
  }

  Future<AppleIapVerifyResult> verifyAppleIapOneTimePurchase({
    required String accessToken,
    required String packageCode,
    required String signedTransactionInfo,
    String? orderId,
  }) async {
    final body = <String, dynamic>{
      'package_code': packageCode,
      'signed_transaction_info': signedTransactionInfo,
    };
    if (orderId != null && orderId.isNotEmpty) {
      body['order_id'] = orderId;
    }
    _logRequest(
      endpoint: 'apple_iap_verify',
      method: 'POST',
      path: '/api/billing/apple-iap/purchases/one-time/verify',
      requestBody: body,
    );

    final response = await http.post(
      Uri.parse(
        '${AppEnvironment.apiServerUrl}/api/billing/apple-iap/purchases/one-time/verify',
      ),
      headers: {
        'Content-Type': 'application/json',
        'X-Access-Token': accessToken,
      },
      body: jsonEncode(body),
    );
    _logResponse(
      endpoint: 'apple_iap_verify',
      statusCode: response.statusCode,
      responseBody: response.body,
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_apple_iap_verify] non-200: ${response.statusCode} ${response.body}',
        tag: 'BillingApi',
      );
      throw BillingRequestException('HTTP ${response.statusCode}');
    }

    final decoded = _decodeResponse(
      response.body,
      endpoint: 'apple_iap_verify',
    );
    final data = _requireDataMap(decoded, endpoint: 'apple_iap_verify');

    final result = AppleIapVerifyResult(
      status: data['status']?.toString() ?? '',
      granted: data['granted'] == true,
      grantId: data['grant_id'] is num
          ? (data['grant_id'] as num).toInt()
          : null,
      paymentReference: data['payment_reference']?.toString(),
      orderId: data['order_id']?.toString(),
    );
    AppLog.instance.debug(
      jsonEncode({
        'event': 'billing_apple_iap_verify_parsed',
        'status': result.status,
        'granted': result.granted,
        'grant_id': result.grantId,
        'payment_reference': result.paymentReference,
        'order_id': result.orderId,
      }),
      tag: 'BillingApi',
    );
    return result;
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

  double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  double? _asNullableDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final intValue = int.tryParse(value);
      if (intValue != null) return intValue;
      final doubleValue = double.tryParse(value);
      if (doubleValue != null) return doubleValue.toInt();
    }
    return fallback;
  }

  void _logRequest({
    required String endpoint,
    required String method,
    required String path,
    Object? requestBody,
  }) {
    AppLog.instance.debug(
      jsonEncode({
        'event': 'billing_request',
        'endpoint': endpoint,
        'method': method,
        'url': '${AppEnvironment.apiServerUrl}$path',
        'request_body': requestBody,
      }),
      tag: 'BillingApi',
    );
  }

  void _logResponse({
    required String endpoint,
    required int statusCode,
    required String responseBody,
  }) {
    AppLog.instance.debug(
      jsonEncode({
        'event': 'billing_response',
        'endpoint': endpoint,
        'status_code': statusCode,
        'response_body': responseBody,
      }),
      tag: 'BillingApi',
    );
  }
}
