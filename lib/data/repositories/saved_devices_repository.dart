import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/device_qr_data.dart';
import 'dart:convert';
import '../../core/audit/audit_mode.dart';
import '../../core/constants/storage_keys.dart';
import '../../core/log/app_log.dart';

class SavedDeviceRecord {
  final String displayDeviceId;
  final String deviceName;
  final String publicKey;

  final String? lastBleDeviceId;
  final DateTime? lastConnectedAt;

  final String? firmwareVersion; // overlay from BLE when available
  final String? networkSummary;  // e.g., SSID or "offline"

  const SavedDeviceRecord({
    required this.displayDeviceId,
    required this.deviceName,
    required this.publicKey,
    this.lastBleDeviceId,
    this.lastConnectedAt,
    this.firmwareVersion,
    this.networkSummary,
  });

  // Convenient empty constructor used by UI fallbacks
  const SavedDeviceRecord.empty()
      : displayDeviceId = '',
        deviceName = '',
        publicKey = '',
        lastBleDeviceId = null,
        lastConnectedAt = null,
        firmwareVersion = null,
        networkSummary = null;

  Map<String, dynamic> toJson() => {
        'deviceId': displayDeviceId,
        'deviceName': deviceName,
        'publicKey': publicKey,
        'lastConnectedAt': lastConnectedAt?.toIso8601String(),
        'firmwareVersion': firmwareVersion,
        'networkSummary': networkSummary,
      };

  static SavedDeviceRecord fromJson(Map<String, dynamic> json) => SavedDeviceRecord(
        displayDeviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String,
        publicKey: json['publicKey'] as String,
        lastBleDeviceId: json['lastBleDeviceId'] as String?,
        lastConnectedAt: json['lastConnectedAt'] != null
            ? DateTime.tryParse(json['lastConnectedAt'] as String)
            : null,
        firmwareVersion: json['firmwareVersion'] as String?,
        networkSummary: json['networkSummary'] as String?,
      );

  SavedDeviceRecord copyWith({
    String? deviceId,
    String? deviceName,
    String? publicKey,
    String? lastBleDeviceId,
    DateTime? lastConnectedAt,
    String? firmwareVersion,
    String? networkSummary,
  }) =>
      SavedDeviceRecord(
        displayDeviceId: deviceId ?? this.displayDeviceId,
        deviceName: deviceName ?? this.deviceName,
        publicKey: publicKey ?? this.publicKey,
        lastBleDeviceId: lastBleDeviceId ?? this.lastBleDeviceId,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
        firmwareVersion: firmwareVersion ?? this.firmwareVersion,
        networkSummary: networkSummary ?? this.networkSummary,
      );
}

class SavedDevicesRepository {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _currentUserId() {
    if (AuditMode.enabled) return AuditMode.auditUserId;
    return Supabase.instance.client.auth.currentUser?.id;
  }

  String? _devicesKeyForCurrentUser() {
    final uid = _currentUserId();
    if (uid == null) return null;
    return '${StorageKeys.savedDevicesBase}_$uid';
  }

  String? _lastSelectedKeyForCurrentUser() {
    final uid = _currentUserId();
    if (uid == null) return null;
    return '${StorageKeys.savedDevicesLastSelectedBase}_$uid';
  }

  // Load locally cached devices (scoped to current user)
  Future<List<SavedDeviceRecord>> loadLocal() async {
    final key = _devicesKeyForCurrentUser();
    if (key == null) return [];
    final jsonStr = await _storage.read(key: key);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final List<dynamic> data = json.decode(jsonStr) as List<dynamic>;
      return data
          .whereType<Map<String, dynamic>>()
          .map(SavedDeviceRecord.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveLocal(List<SavedDeviceRecord> list) async {
    final key = _devicesKeyForCurrentUser();
    if (key == null) return; // No user; do not persist
    final jsonStr = json.encode(list.map((e) => e.toJson()).toList());
    await _storage.write(key: key, value: jsonStr);
  }

  // Fetch device list from Supabase
  Future<List<SavedDeviceRecord>> fetchRemote() async {
    // In audit mode, treat remote list as local cache to avoid any network
    if (AuditMode.enabled) {
      return await loadLocal();
    }

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      return [];
    }
    List<dynamic> rows = const [];
    try {
      rows = await client
          .from('account_device_binding_log')
          .select('device_id, device_name, device_public_key, device_firmware_version')
          .eq('user_id', user.id)
          .eq('bind_status', 1)
          .order('bind_time');
    } catch (e, st) {
      // Report Supabase query error to Sentry via AppLog
      AppLog.instance.error(
        'Supabase fetchRemote failed',
        tag: 'Supabase',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }

    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      final deviceId = (map['device_id'] ?? '').toString();
      final deviceName = (map['device_name'] ?? '').toString();
      final publicKey = (map['device_public_key'] ?? '').toString();
      final firmwareVersion = (map['device_firmware_version'] ?? '').toString();
      return SavedDeviceRecord(
        displayDeviceId: deviceId,
        deviceName: deviceName,
        publicKey: publicKey,
        firmwareVersion: firmwareVersion,
        lastBleDeviceId: null,
        lastConnectedAt: null, // 仅表示本地上次 BLE 连接时间，不从远端 bind_time 同步
      );
    }).toList();
  }

  Future<String?> loadLastSelectedId() async {
    final key = _lastSelectedKeyForCurrentUser();
    if (key == null) return null;
    return _storage.read(key: key);
  }

  Future<void> saveLastSelectedId(String deviceId) async {
    final key = _lastSelectedKeyForCurrentUser();
    if (key == null) return;
    await _storage.write(key: key, value: deviceId);
  }

  Future<void> selectFromQr(DeviceQrData qr) async {
    await saveLastSelectedId(qr.displayDeviceId);

    final key = _devicesKeyForCurrentUser();
    if (key == null) {
      return;
    }

    final devices = await loadLocal();
    final idx =
        devices.indexWhere((e) => e.displayDeviceId == qr.displayDeviceId);
    if (idx >= 0) {
      final current = devices[idx];
      devices[idx] = current.copyWith(
        deviceName: qr.deviceName.isNotEmpty ? qr.deviceName : current.deviceName,
        publicKey: qr.publicKey.isNotEmpty ? qr.publicKey : current.publicKey,
      );
    } else {
      devices.add(SavedDeviceRecord(
        displayDeviceId: qr.displayDeviceId,
        deviceName: qr.deviceName,
        publicKey: qr.publicKey,
        lastConnectedAt: DateTime.now(),
      ));
    }

    await saveLocal(devices);
  }

  // Clear all local cached device data for the current user
  Future<void> clearCurrentUserData() async {
    final devicesKey = _devicesKeyForCurrentUser();
    final lastKey = _lastSelectedKeyForCurrentUser();
    if (devicesKey != null) {
      await _storage.delete(key: devicesKey);
    }
    if (lastKey != null) {
      await _storage.delete(key: lastKey);
    }
  }
}
