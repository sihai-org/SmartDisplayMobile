import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/audit/audit_mode.dart';
import '../../core/models/device_customization.dart';

/// 本地持久化：用户为不同设备设置的壁纸/布局偏好。
///
/// 存储规则：
/// - 壁纸、布局字段都允许为空；为空表示使用默认。
/// - 如果保存时两者都为空，则会直接删除该设备的自定义记录以保持存储整洁。
class DeviceCustomizationRepository {
  static const _keyBase = 'device_customization_v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _currentUserId() {
    if (AuditMode.enabled) return AuditMode.auditUserId;
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  String? _storageKeyForCurrentUser() {
    final uid = _currentUserId();
    if (uid == null || uid.isEmpty) return null;
    return '${_keyBase}_$uid';
  }

  Future<Map<String, DeviceCustomization>> _loadAll() async {
    final key = _storageKeyForCurrentUser();
    if (key == null) return {};
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return decoded.map((deviceId, value) {
        if (value is Map<String, dynamic>) {
          return MapEntry(deviceId, DeviceCustomization.fromJson(value));
        }
        return MapEntry(deviceId, const DeviceCustomization.empty());
      });
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveAll(Map<String, DeviceCustomization> data) async {
    final key = _storageKeyForCurrentUser();
    if (key == null) return;
    final encoded = json.encode(
      data.map((k, v) => MapEntry(k, v.normalized().toJson())),
    );
    await _storage.write(key: key, value: encoded);
  }

  /// 获取指定设备的用户自定义（本地缓存）。
  ///
  /// 当设备没有任何自定义时，返回空对象（等同于 default）。
  Future<DeviceCustomization> getUserCustomization(String displayDeviceId) async {
    if (displayDeviceId.isEmpty) return const DeviceCustomization.empty();
    final all = await _loadAll();
    return all[displayDeviceId] ?? const DeviceCustomization.empty();
  }

  /// 保存指定设备的用户自定义（本地缓存）。
  ///
  /// 如果壁纸、布局均为空，则删除对应记录，使其回退为默认。
  Future<void> saveUserCustomization(
    String displayDeviceId,
    DeviceCustomization customization,
  ) async {
    if (displayDeviceId.isEmpty) return;
    final normalized = customization.normalized();
    final all = await _loadAll();
    final hasWallpaper = normalized.hasCustomWallpaper;
    final hasLayout =
        normalized.layout != null && normalized.layout!.isNotEmpty;

    if (!hasWallpaper && !hasLayout) {
      all.remove(displayDeviceId);
    } else {
      all[displayDeviceId] = normalized;
    }

    await _saveAll(all);
  }

  /// 清空当前用户的所有自定义缓存（通常用于登出或重置）。
  Future<void> clearCurrentUserData() async {
    final key = _storageKeyForCurrentUser();
    if (key == null) return;
    await _storage.delete(key: key);
  }

  // ====== 远端接口占位 ======
  // 后续接入服务端时使用；当前仅声明签名，便于 UI/业务层调用。

  /// TODO: 从服务端获取用户在某设备的自定义配置。
  Future<DeviceCustomization> fetchUserCustomizationRemote(
    String displayDeviceId,
  ) async {
    // 待接入远端接口；返回默认值占位
    return const DeviceCustomization.empty();
  }

  /// TODO: 将用户自定义配置保存到服务端。
  Future<void> saveUserCustomizationRemote(
    String displayDeviceId,
    DeviceCustomization customization,
  ) async {
    // 待接入远端接口
  }
}
