import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../features/qr_scanner/models/device_qr_data.dart';

class SavedDeviceRecord {
  final String deviceId;
  final String deviceName;
  final String publicKey;
  final String? lastBleAddress;
  final DateTime? lastConnectedAt;

  const SavedDeviceRecord({
    required this.deviceId,
    required this.deviceName,
    required this.publicKey,
    this.lastBleAddress,
    this.lastConnectedAt,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'publicKey': publicKey,
        'lastBleAddress': lastBleAddress,
        'lastConnectedAt': lastConnectedAt?.toIso8601String(),
      };

  static SavedDeviceRecord fromJson(Map<String, dynamic> json) => SavedDeviceRecord(
        deviceId: json['deviceId'] as String,
        deviceName: json['deviceName'] as String,
        publicKey: json['publicKey'] as String,
        lastBleAddress: json['lastBleAddress'] as String?,
        lastConnectedAt: json['lastConnectedAt'] != null
            ? DateTime.tryParse(json['lastConnectedAt'] as String)
            : null,
      );

  SavedDeviceRecord copyWith({
    String? deviceId,
    String? deviceName,
    String? publicKey,
    String? lastBleAddress,
    DateTime? lastConnectedAt,
  }) =>
      SavedDeviceRecord(
        deviceId: deviceId ?? this.deviceId,
        deviceName: deviceName ?? this.deviceName,
        publicKey: publicKey ?? this.publicKey,
        lastBleAddress: lastBleAddress ?? this.lastBleAddress,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      );
}

class SavedDevicesRepository {
  static const _keyDevices = 'saved_devices_v1';
  static const _keyLastSelectedId = 'saved_devices_last_selected_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<List<SavedDeviceRecord>> loadAll() async {
    // Fetch device list from Supabase instead of local storage.
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      return [];
    }

    try {
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
        final bindTime = map['bind_time'] as String?;
        return SavedDeviceRecord(
          deviceId: deviceId,
          deviceName: deviceName,
          publicKey: publicKey,
          lastBleAddress: null,
          lastConnectedAt: bindTime != null ? DateTime.tryParse(bindTime) : null,
        );
      }).toList();
    } catch (e) {
      // On failure, show toast and return empty list; no local cache fallback.
      Fluttertoast.showToast(msg: '获取设备列表失败');
      return [];
    }
  }

  Future<String?> loadLastSelectedId() async {
    return _storage.read(key: _keyLastSelectedId);
  }

  Future<void> saveLastSelectedId(String deviceId) async {
    await _storage.write(key: _keyLastSelectedId, value: deviceId);
  }

  Future<void> upsertFromQr(DeviceQrData qr, {String? lastBleAddress}) async {
    // No longer cache devices locally. Only remember last selected id.
    await saveLastSelectedId(qr.deviceId);
  }

  Future<void> removeDevice(String deviceId) async {
    // Do not modify remote data here. Just clear last selected if it matches.
    final currentLastSelected = await loadLastSelectedId();
    if (currentLastSelected == deviceId) {
      await _storage.delete(key: _keyLastSelectedId);
    }
  }
}
