class AndroidIapProductData {
  const AndroidIapProductData({
    required this.packageCode,
    required this.productId,
    required this.creditAmount,
    required this.sortOrder,
    this.displayName,
    this.description,
    this.currency,
    this.amount,
  });

  factory AndroidIapProductData.fromJson(Map<String, dynamic> json) {
    return AndroidIapProductData(
      packageCode: json['package_code']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      displayName: json['display_name']?.toString(),
      description: json['description']?.toString(),
      creditAmount: _asDouble(json['credit_amount']),
      currency: json['currency']?.toString(),
      amount: _asNullableDouble(json['amount']),
      sortOrder: _asInt(json['sort_order']),
    );
  }

  final String packageCode;
  final String productId;
  final String? displayName;
  final String? description;
  final double creditAmount;
  final String? currency;
  final double? amount;
  final int sortOrder;

  Map<String, dynamic> toJson() {
    return {
      'package_code': packageCode,
      'product_id': productId,
      'display_name': displayName,
      'description': description,
      'credit_amount': creditAmount,
      'currency': currency,
      'amount': amount,
      'sort_order': sortOrder,
    };
  }
}

class AndroidIapOrderData {
  const AndroidIapOrderData({
    required this.orderId,
    required this.packageCode,
    required this.productId,
    required this.status,
    required this.creditAmount,
    this.currency,
    this.amount,
  });

  factory AndroidIapOrderData.fromJson(Map<String, dynamic> json) {
    return AndroidIapOrderData(
      orderId: json['order_id']?.toString() ?? '',
      packageCode: json['package_code']?.toString() ?? '',
      productId: json['product_id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      creditAmount: _asDouble(json['credit_amount']),
      currency: json['currency']?.toString(),
      amount: _asNullableDouble(json['amount']),
    );
  }

  final String orderId;
  final String packageCode;
  final String productId;
  final String status;
  final double creditAmount;
  final String? currency;
  final double? amount;

  Map<String, dynamic> toJson() {
    return {
      'order_id': orderId,
      'package_code': packageCode,
      'product_id': productId,
      'status': status,
      'credit_amount': creditAmount,
      'currency': currency,
      'amount': amount,
    };
  }
}

class AndroidIapVerifyResult {
  const AndroidIapVerifyResult({
    required this.provider,
    required this.status,
    required this.granted,
    this.grantId,
    this.paymentReference,
    this.orderId,
  });

  factory AndroidIapVerifyResult.fromJson(Map<String, dynamic> json) {
    return AndroidIapVerifyResult(
      provider: json['provider']?.toString() ?? 'google_play',
      status: json['status']?.toString() ?? '',
      granted: json['granted'] == true,
      grantId: _asNullableInt(json['grant_id']),
      paymentReference: json['payment_reference']?.toString(),
      orderId: json['order_id']?.toString(),
    );
  }

  final String provider;
  final String status;
  final bool granted;
  final int? grantId;
  final String? paymentReference;
  final String? orderId;

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'status': status,
      'granted': granted,
      'grant_id': grantId,
      'payment_reference': paymentReference,
      'order_id': orderId,
    };
  }
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
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  return fallback;
}

int? _asNullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
