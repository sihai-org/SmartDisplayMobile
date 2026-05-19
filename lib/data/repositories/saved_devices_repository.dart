import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models/device_qr_data.dart';
import 'dart:convert';
import '../../core/audit/audit_mode.dart';
import '../../core/auth/auth_manager.dart';
import '../../core/constants/app_environment.dart';
import '../../core/constants/storage_keys.dart';
import '../../core/log/app_log.dart';
import '../../core/network/http_timeouts.dart';

class SavedDeviceRecord {
  final String displayDeviceId;
  final int? versionCode;
  // 展示名：优先 nick，否则 name
  final String deviceName;
  // 原始设备名（服务端 device_name）
  final String name;
  // 设备别名（服务端 alias）
  final String nick;
  final String publicKey;

  final String? lastBleDeviceId;
  final DateTime? lastConnectedAt;

  final String? firmwareVersion; // overlay from BLE when available
  final String? networkSummary; // e.g., SSID or "offline"

  const SavedDeviceRecord({
    required this.displayDeviceId,
    this.versionCode,
    required this.deviceName,
    this.name = '',
    this.nick = '',
    required this.publicKey,
    this.lastBleDeviceId,
    this.lastConnectedAt,
    this.firmwareVersion,
    this.networkSummary,
  });

  // Convenient empty constructor used by UI fallbacks
  const SavedDeviceRecord.empty()
    : displayDeviceId = '',
      versionCode = null,
      deviceName = '',
      name = '',
      nick = '',
      publicKey = '',
      lastBleDeviceId = null,
      lastConnectedAt = null,
      firmwareVersion = null,
      networkSummary = null;

  Map<String, dynamic> toJson() => {
    'deviceId': displayDeviceId,
    'versionCode': versionCode,
    'deviceName': deviceName,
    'name': name,
    'nick': nick,
    'publicKey': publicKey,
    'lastConnectedAt': lastConnectedAt?.toIso8601String(),
    'firmwareVersion': firmwareVersion,
    'networkSummary': networkSummary,
  };

  static SavedDeviceRecord fromJson(Map<String, dynamic> json) =>
      SavedDeviceRecord(
        displayDeviceId: json['deviceId'] as String,
        versionCode: (json['versionCode'] as num?)?.toInt(),
        deviceName:
            (json['deviceName'] as String?) ??
            (((json['nick'] as String?)?.isNotEmpty ?? false)
                ? (json['nick'] as String)
                : ((json['name'] as String?) ?? '')),
        name: (json['name'] as String?) ?? (json['deviceName'] as String? ?? ''),
        nick: (json['nick'] as String?) ?? '',
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
    int? versionCode,
    String? deviceName,
    String? name,
    String? nick,
    String? publicKey,
    String? lastBleDeviceId,
    DateTime? lastConnectedAt,
    String? firmwareVersion,
    String? networkSummary,
  }) => SavedDeviceRecord(
    displayDeviceId: deviceId ?? displayDeviceId,
    versionCode: versionCode ?? this.versionCode,
    deviceName: deviceName ?? this.deviceName,
    name: name ?? this.name,
    nick: nick ?? this.nick,
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

  // Fetch device list from backend API
  Future<List<SavedDeviceRecord>> fetchRemote() async {
    // In audit mode, treat remote list as local cache to avoid any network
    if (AuditMode.enabled) {
      return await loadLocal();
    }

    final accessToken = await AuthManager.instance.getFreshAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      return [];
    }

    List<dynamic> rows = const [];
    try {
      final response = await http
          .post(
            Uri.parse('${AppEnvironment.apiServerUrl}/monitorapp/device_list'),
            headers: {
              'Content-Type': 'application/json',
              'X-Access-Token': accessToken,
            },
          )
          .timeout(HttpTimeouts.business);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid response: expected JSON object');
      }

      if (decoded['code'] != 200) {
        final message = decoded['message']?.toString().trim();
        throw Exception(
          message == null || message.isEmpty ? 'device_list failed' : message,
        );
      }

      final data = decoded['data'];
      if (data is! List) {
        throw Exception('Invalid response: data is not a list');
      }
      rows = data;
    } catch (e, st) {
      // Report backend request error to Sentry via AppLog
      AppLog.instance.error(
        'device_list fetchRemote failed',
        tag: 'DeviceApi',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }

    return rows.map((row) {
      final map = (row as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final deviceId = (map['device_id'] ?? '').toString();
      final deviceAlias = (map['alias'] ?? '').toString().trim();
      final deviceNameRaw = (map['device_name'] ?? '').toString().trim();
      final deviceName = deviceAlias.isNotEmpty ? deviceAlias : deviceNameRaw;
      final publicKey = (map['device_public_key'] ?? '').toString();
      final firmwareVersion = (map['device_firmware_version'] ?? '').toString();
      return SavedDeviceRecord(
        displayDeviceId: deviceId,
        versionCode: null,
        deviceName: deviceName,
        name: deviceNameRaw,
        nick: deviceAlias,
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

  Future<void> clearLastSelectedId() async {
    final key = _lastSelectedKeyForCurrentUser();
    if (key == null) return;
    await _storage.delete(key: key);
  }

  Future<void> selectFromQr(DeviceQrData qr) async {
    await saveLastSelectedId(qr.displayDeviceId);

    final key = _devicesKeyForCurrentUser();
    if (key == null) {
      return;
    }

    final devices = await loadLocal();
    final idx = devices.indexWhere(
      (e) => e.displayDeviceId == qr.displayDeviceId,
    );
    if (idx >= 0) {
      final current = devices[idx];
      devices[idx] = current.copyWith(
        versionCode: qr.versionCode,
        deviceName: qr.deviceName.isNotEmpty
            ? qr.deviceName
            : current.deviceName,
        name: qr.deviceName.isNotEmpty ? qr.deviceName : current.name,
        nick: current.nick,
        publicKey: qr.publicKey.isNotEmpty ? qr.publicKey : current.publicKey,
      );
    } else {
      devices.add(
        SavedDeviceRecord(
          displayDeviceId: qr.displayDeviceId,
          versionCode: qr.versionCode,
          deviceName: qr.deviceName,
          name: qr.deviceName,
          nick: '',
          publicKey: qr.publicKey,
          lastConnectedAt: DateTime.now(),
        ),
      );
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
