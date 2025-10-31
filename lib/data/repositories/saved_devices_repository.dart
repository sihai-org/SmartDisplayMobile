import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/device_qr_data.dart';
import 'dart:convert';

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
  static const _keyDevices = 'saved_devices_v1';
  static const _keyLastSelectedId = 'saved_devices_last_selected_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _currentUserId() => Supabase.instance.client.auth.currentUser?.id;

  String? _devicesKeyForCurrentUser() {
    final uid = _currentUserId();
    if (uid == null) return null;
    return '${_keyDevices}_$uid';
  }

  String? _lastSelectedKeyForCurrentUser() {
    final uid = _currentUserId();
    if (uid == null) return null;
    return '${_keyLastSelectedId}_$uid';
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
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      return [];
    }
    final List<dynamic> rows = await client
        .from('account_device_binding_log')
        .select('device_id, device_name, device_public_key, bind_time')
        .eq('user_id', user.id)
        .eq('bind_status', 1)
        .order('bind_time');

    return rows.map((row) {
      final map = row as Map<String, dynamic>;
      final deviceId = (map['device_id'] ?? '').toString();
      final deviceName = (map['device_name'] ?? '').toString();
      final publicKey = (map['device_public_key'] ?? '').toString();
      final firmwareVersion = (map['device_firmware_version'] ?? '').toString();
      final bindTime = map['bind_time'] as String?;
      return SavedDeviceRecord(
        displayDeviceId: deviceId,
        deviceName: deviceName,
        publicKey: publicKey,
        firmwareVersion: firmwareVersion,
        lastBleDeviceId: null,
        lastConnectedAt: bindTime != null ? DateTime.tryParse(bindTime) : null,
      );
    }).toList();
  }

  // For backward compatibility with callers expecting loadAll
  Future<List<SavedDeviceRecord>> loadAll() => loadLocal();

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

  Future<void> removeDevice(String deviceId) async {
    // Do not modify remote data here. Just clear last selected if it matches.
    final currentLastSelected = await loadLastSelectedId();
    if (currentLastSelected == deviceId) {
      final key = _lastSelectedKeyForCurrentUser();
      if (key != null) {
        await _storage.delete(key: key);
      }
    }
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
