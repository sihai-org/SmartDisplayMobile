import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_environment.dart';
import '../../core/log/app_log.dart';
import '../../core/log/buy_log.dart';
import '../../core/log/biz_log_tag.dart';
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
    this.displayPrice,
    this.sortOrder = 0,
  });

  final String packageCode;
  final String productId;
  final double creditAmount;
  final String? displayName;
  final String? description;
  final String? currency;
  final double? amount;
  final String? displayPrice;
  final int sortOrder;

  AppleIapProductData copyWith({
    String? packageCode,
    String? productId,
    double? creditAmount,
    String? displayName,
    String? description,
    String? currency,
    double? amount,
    String? displayPrice,
    int? sortOrder,
  }) {
    return AppleIapProductData(
      packageCode: packageCode ?? this.packageCode,
      productId: productId ?? this.productId,
      creditAmount: creditAmount ?? this.creditAmount,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      currency: currency ?? this.currency,
      amount: amount ?? this.amount,
      displayPrice: displayPrice ?? this.displayPrice,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
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
  static const _productsPath = '/api/billing/apple-iap/products';
  static const _ordersPath = '/api/billing/apple-iap/orders';
  static const _verifyPath =
      '/api/billing/apple-iap/purchases/one-time/verify';

  Future<List<AppleIapProductData>> fetchAppleIapProducts({
    required String accessToken,
  }) async {
    logBuyRequest(
      method: 'GET',
      path: _productsPath,
    );
    final response = await http.get(
      Uri.parse(
        '${AppEnvironment.apiServerUrl}$_productsPath',
      ),
      headers: {'X-Access-Token': accessToken},
    );
    logBuyResponse(
      endpoint: _productsPath,
      statusCode: response.statusCode,
      responseBody: response.body,
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_apple_iap_products] non-200: ${response.statusCode} ${response.body}',
        tag: BizLogTag.buy.tag,
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
        tag: BizLogTag.buy.tag,
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
    return products;
  }

  Future<AppleIapOrderData> createAppleIapOrder({
    required String accessToken,
    required String packageCode,
  }) async {
    final requestBody = {'package_code': packageCode};
    logBuyRequest(
      method: 'POST',
      path: _ordersPath,
      requestBody: requestBody,
    );
    final response = await http.post(
      Uri.parse('${AppEnvironment.apiServerUrl}$_ordersPath'),
      headers: {
        'Content-Type': 'application/json',
        'X-Access-Token': accessToken,
      },
      body: jsonEncode(requestBody),
    );
    logBuyResponse(
      endpoint: _ordersPath,
      statusCode: response.statusCode,
      responseBody: response.body,
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_apple_iap_order] non-200: ${response.statusCode} ${response.body}',
        tag: BizLogTag.buy.tag,
      );
      throw BillingRequestException('HTTP ${response.statusCode}');
    }

    final decoded = _decodeResponse(response.body, endpoint: 'apple_iap_order');
    final data = _requireDataMap(decoded, endpoint: 'apple_iap_order');

    return AppleIapOrderData(
      orderId: data['order_id']?.toString() ?? '',
      packageCode: data['package_code']?.toString() ?? '',
      productId: data['product_id']?.toString() ?? '',
      status: data['status']?.toString() ?? '',
      creditAmount: _asDouble(data['credit_amount']),
      currency: data['currency']?.toString(),
      amount: _asNullableDouble(data['amount']),
    );
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
    logBuyRequest(
      method: 'POST',
      path: _verifyPath,
      requestBody: body,
    );

    final response = await http.post(
      Uri.parse('${AppEnvironment.apiServerUrl}$_verifyPath'),
      headers: {
        'Content-Type': 'application/json',
        'X-Access-Token': accessToken,
      },
      body: jsonEncode(body),
    );
    logBuyResponse(
      endpoint: _verifyPath,
      statusCode: response.statusCode,
      responseBody: response.body,
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_apple_iap_verify] non-200: ${response.statusCode} ${response.body}',
        tag: BizLogTag.buy.tag,
      );
      throw BillingRequestException('HTTP ${response.statusCode}');
    }

    final decoded = _decodeResponse(
      response.body,
      endpoint: 'apple_iap_verify',
    );
    final data = _requireDataMap(decoded, endpoint: 'apple_iap_verify');

    return AppleIapVerifyResult(
      status: data['status']?.toString() ?? '',
      granted: data['granted'] == true,
      grantId: data['grant_id'] is num
          ? (data['grant_id'] as num).toInt()
          : null,
      paymentReference: data['payment_reference']?.toString(),
      orderId: data['order_id']?.toString(),
    );
  }

  Map<String, dynamic> _decodeResponse(
    String body, {
    required String endpoint,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      AppLog.instance.warning(
        '[billing_$endpoint] invalid body: $body',
        tag: BizLogTag.buy.tag,
      );
      throw const BillingRequestException('Invalid response');
    }

    final map = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (map['code'] != 200) {
      final message = map['message']?.toString().trim();
      AppLog.instance.warning(
        '[billing_$endpoint] code=${map['code']} message=$message',
        tag: BizLogTag.buy.tag,
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
        tag: BizLogTag.buy.tag,
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
}
