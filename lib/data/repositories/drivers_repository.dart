import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/audit/audit_mode.dart';
import '../../core/constants/storage_keys.dart';
import '../../core/models/driver_binding.dart';

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
  /// TODO: 接入真实接口
  /// POST `${AppEnvironment.apiServerUrl}/drivers/bind`
  /// body: { device_id, driver_hw_id }
  ///
  /// 目前为本地 mock：始终成功，约 300ms 延迟。
  Future<DriverBinding> bind({
    required String deviceId,
    required String driverHwId,
    String? deviceName,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return DriverBinding(
      driverHwId: driverHwId,
      deviceId: deviceId,
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
