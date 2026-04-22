import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_environment.dart';
import '../../core/log/app_log.dart';

const int billingLedgerPageSize = 20;

class BillingRequestException implements Exception {
  const BillingRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BillingBalanceData {
  const BillingBalanceData({
    required this.availableBalance,
    required this.totalConsumed,
    required this.totalExpired,
  });

  final double availableBalance;
  final double totalConsumed;
  final double totalExpired;
}

class BillingLedgerItem {
  const BillingLedgerItem({
    required this.displayText,
    this.amount,
    this.totalCredit,
    this.occurredAt,
  });

  final String displayText;
  final double? amount;
  final double? totalCredit;
  final DateTime? occurredAt;

  double get displayValue => amount ?? totalCredit ?? 0;
}

class BillingLedgerPageData {
  const BillingLedgerPageData({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.total,
  });

  final List<BillingLedgerItem> items;
  final int page;
  final int pageSize;
  final int total;
}

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

class BillingRepository {
  Future<BillingBalanceData> fetchBalance({required String accessToken}) async {
    final response = await http.get(
      Uri.parse('${AppEnvironment.apiServerUrl}/api/billing/balance'),
      headers: {'X-Access-Token': accessToken},
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_balance] non-200: ${response.statusCode} ${response.body}',
        tag: 'BillingApi',
      );
      throw BillingRequestException('HTTP ${response.statusCode}');
    }

    final decoded = _decodeResponse(response.body, endpoint: 'balance');
    final data = _requireDataMap(decoded, endpoint: 'balance');

    AppLog.instance.info(
      '[billing_balance] parsed available_balance=${data['available_balance']}, total_consumed=${data['total_consumed']}, total_expired=${data['total_expired']}',
      tag: 'BillingApi',
    );

    return BillingBalanceData(
      availableBalance: _asDouble(data['available_balance']),
      totalConsumed: _asDouble(data['total_consumed']),
      totalExpired: _asDouble(data['total_expired']),
    );
  }

  Future<BillingLedgerPageData> fetchLedger({
    required String accessToken,
    required int page,
    required int pageSize,
  }) async {
    final uri = Uri.parse(
      '${AppEnvironment.apiServerUrl}/api/billing/ledger',
    ).replace(queryParameters: {'page': '$page', 'page_size': '$pageSize'});

    final response = await http.get(
      uri,
      headers: {'X-Access-Token': accessToken},
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[billing_ledger] non-200: ${response.statusCode} ${response.body}',
        tag: 'BillingApi',
      );
      throw BillingRequestException('HTTP ${response.statusCode}');
    }

    final decoded = _decodeResponse(response.body, endpoint: 'ledger');
    final data = _requireDataMap(decoded, endpoint: 'ledger');
    final rawItems = data['items'];
    final items = <BillingLedgerItem>[];

    AppLog.instance.info(
      '[billing_ledger] parsed page=${data['page']}, page_size=${data['page_size']}, total=${data['total']}, items=${rawItems is List ? rawItems.length : 0}',
      tag: 'BillingApi',
    );

    if (rawItems is List) {
      for (final rawItem in rawItems) {
        if (rawItem is! Map) continue;
        final item = rawItem.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final displayText = item['display_text']?.toString().trim() ?? '';
        if (displayText.isEmpty) continue;
        items.add(
          BillingLedgerItem(
            displayText: displayText,
            amount: _asNullableDouble(item['amount']),
            totalCredit: _asNullableDouble(item['total_credit']),
            occurredAt: _parseLedgerDateTime(item['display_time']),
          ),
        );
        AppLog.instance.info(
          '[billing_ledger_item] display_text=$displayText, amount=${item['amount']}, total_credit=${item['total_credit']}, display_time=${item['display_time']}',
          tag: 'BillingApi',
        );
      }
    }

    return BillingLedgerPageData(
      items: items,
      page: _asInt(data['page'], fallback: page),
      pageSize: _asInt(data['page_size'], fallback: pageSize),
      total: _asInt(data['total'], fallback: items.length),
    );
  }

  Future<List<AppleIapProductData>> fetchAppleIapProducts({
    required String accessToken,
  }) async {
    final response = await http.get(
      Uri.parse(
        '${AppEnvironment.apiServerUrl}/api/billing/apple-iap/products',
      ),
      headers: {'X-Access-Token': accessToken},
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

    return data
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
  }

  Future<AppleIapOrderData> createAppleIapOrder({
    required String accessToken,
    required String packageCode,
  }) async {
    final response = await http.post(
      Uri.parse('${AppEnvironment.apiServerUrl}/api/billing/apple-iap/orders'),
      headers: {
        'Content-Type': 'application/json',
        'X-Access-Token': accessToken,
      },
      body: jsonEncode({'package_code': packageCode}),
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

  DateTime? _parseLedgerDateTime(dynamic value) {
    if (value == null) return null;

    if (value is num) {
      return _parseEpochDateTime(value.toInt());
    }

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    final epoch = int.tryParse(text);
    if (epoch != null) {
      return _parseEpochDateTime(epoch);
    }

    final sanitized = text.replaceFirst(' ', 'T');
    final normalized = sanitized.replaceFirstMapped(
      RegExp(r'([+-]\d{2})$'),
      (match) => '${match[1]}:00',
    );
    return DateTime.tryParse(normalized);
  }

  DateTime? _parseEpochDateTime(int value) {
    if (value <= 0) return null;
    final milliseconds = value > 1000000000000 ? value : value * 1000;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  }
}
