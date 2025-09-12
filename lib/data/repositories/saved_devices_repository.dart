import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    final raw = await _storage.read(key: _keyDevices);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(SavedDeviceRecord.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAll(List<SavedDeviceRecord> devices) async {
    final raw = jsonEncode(devices.map((e) => e.toJson()).toList());
    await _storage.write(key: _keyDevices, value: raw);
  }

  Future<String?> loadLastSelectedId() async {
    return _storage.read(key: _keyLastSelectedId);
  }

  Future<void> saveLastSelectedId(String deviceId) async {
    await _storage.write(key: _keyLastSelectedId, value: deviceId);
  }

  Future<void> upsertFromQr(DeviceQrData qr, {String? lastBleAddress}) async {
    final all = await loadAll();
    final idx = all.indexWhere((e) => e.deviceId == qr.deviceId);
    final rec = SavedDeviceRecord(
      deviceId: qr.deviceId,
      deviceName: qr.deviceName,
      publicKey: qr.publicKey,
      lastBleAddress: lastBleAddress,
      lastConnectedAt: DateTime.now(),
    );
    if (idx >= 0) {
      all[idx] = all[idx]
          .copyWith(deviceName: rec.deviceName, publicKey: rec.publicKey, lastBleAddress: lastBleAddress, lastConnectedAt: DateTime.now());
    } else {
      all.add(rec);
    }
    await saveAll(all);
    await saveLastSelectedId(rec.deviceId);
  }

  Future<void> removeDevice(String deviceId) async {
    final all = await loadAll();
    all.removeWhere((e) => e.deviceId == deviceId);
    await saveAll(all);
    
    // 如果删除的是最后选中的设备，更新lastSelectedId
    final currentLastSelected = await loadLastSelectedId();
    if (currentLastSelected == deviceId) {
      if (all.isNotEmpty) {
        await saveLastSelectedId(all.last.deviceId);
      } else {
        await _storage.delete(key: _keyLastSelectedId);
      }
    }
  }
}

