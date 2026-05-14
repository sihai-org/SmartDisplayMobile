import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/audit/audit_mode.dart';
import '../../core/auth/auth_manager.dart';
import '../../core/constants/app_environment.dart';
import '../../core/constants/storage_keys.dart';
import '../../core/log/app_log.dart';
import '../../core/models/driver_binding.dart';
import '../../core/network/http_timeouts.dart';

class DriverBindException implements Exception {
  const DriverBindException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DriversRepository {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _currentUserId() {
    if (AuditMode.enabled) return AuditMode.auditUserId;
    return Supabase.instance.client.auth.currentUser?.id;
  }

  String? _keyForCurrentUser() {
    final uid = _currentUserId();
    if (uid == null) return null;
    return '${StorageKeys.driversBase}_$uid';
  }

  Future<List<DriverBinding>> loadLocal() async {
    final key = _keyForCurrentUser();
    if (key == null) return const [];
    final jsonStr = await _storage.read(key: key);
    if (jsonStr == null || jsonStr.isEmpty) return const [];
    try {
      final data = json.decode(jsonStr) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(DriverBinding.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveLocal(List<DriverBinding> list) async {
    final key = _keyForCurrentUser();
    if (key == null) return;
    final jsonStr = json.encode(list.map((e) => e.toJson()).toList());
    await _storage.write(key: key, value: jsonStr);
  }

  /// 绑定龙虾驱动到指定设备。
  ///
  /// POST `${AppEnvironment.apiServerUrl}/clawdriver/bind`
  /// header: X-Access-Token
  /// body:   { device_id, driver_hw_id }
  Future<DriverBinding> bind({
    required String deviceId,
    required String driverHwId,
    String? deviceName,
  }) async {
    final accessToken = await AuthManager.instance.getFreshAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      throw const DriverBindException('Login expired');
    }

    final response = await http
        .post(
          Uri.parse('${AppEnvironment.apiServerUrl}/clawdriver/bind'),
          headers: {
            'Content-Type': 'application/json',
            'X-Access-Token': accessToken,
          },
          body: jsonEncode({
            'device_id': deviceId,
            'driver_hw_id': driverHwId,
          }),
        )
        .timeout(HttpTimeouts.business);

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[clawdriver_bind] non-200: ${response.statusCode} ${response.body}',
        tag: 'Driver',
      );
      throw DriverBindException('HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      AppLog.instance.warning(
        '[clawdriver_bind] invalid body: ${response.body}',
        tag: 'Driver',
      );
      throw const DriverBindException('Invalid response');
    }
    final map = decoded.map((k, v) => MapEntry(k.toString(), v));
    if (map['code'] != 200) {
      final message = map['message']?.toString().trim();
      AppLog.instance.warning(
        '[clawdriver_bind] code=${map['code']} message=$message',
        tag: 'Driver',
      );
      throw DriverBindException(
        message == null || message.isEmpty ? 'Request failed' : message,
      );
    }

    final data = map['data'];
    final dataMap = data is Map
        ? data.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};

    final returnedDeviceId =
        dataMap['device_id']?.toString().trim().isNotEmpty == true
        ? dataMap['device_id'].toString()
        : deviceId;
    final returnedHwId =
        dataMap['driver_hw_id']?.toString().trim().isNotEmpty == true
        ? dataMap['driver_hw_id'].toString()
        : driverHwId;

    return DriverBinding(
      driverHwId: returnedHwId,
      deviceId: returnedDeviceId,
      deviceName: deviceName,
      boundAt: DateTime.now(),
    );
  }

  Future<void> clearCurrentUserData() async {
    final key = _keyForCurrentUser();
    if (key == null) return;
    await _storage.delete(key: key);
  }
}
