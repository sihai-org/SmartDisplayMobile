import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/ble_constants.dart';
import '../../../core/crypto/crypto_service.dart';
import '../../../features/qr_scanner/models/device_qr_data.dart';
import '../../qr_scanner/utils/device_fingerprint.dart';
import '../models/ble_device_data.dart';
import '../models/network_status.dart';
import '../services/ble_service_simple.dart';
import '../../../core/providers/lifecycle_provider.dart';
import '../../../core/providers/saved_devices_provider.dart';

/// 分包拼接工具（支持 {} 和 [] JSON）
class BleChunkAssembler {
  final String characteristic;
  final int timeoutMs;
  final void Function(String json) onCompleted;

  final List<int> _buffer = [];
  DateTime _lastChunkTime = DateTime.now();

  BleChunkAssembler({
    required this.characteristic,
    required this.timeoutMs,
    required this.onCompleted,
  });

  void addChunk(List<int> chunk) {
    final now = DateTime.now();

    // 超时重置（避免旧数据残留）
    if (now.difference(_lastChunkTime).inMilliseconds > timeoutMs) {
      _buffer.clear();
    }

    _buffer.addAll(chunk);
    _lastChunkTime = now;

    try {
      final decoded = utf8.decode(_buffer);
      final trimmed = decoded.trim();

      // 先简单检查结尾
      if (trimmed.endsWith("}") || trimmed.endsWith("]")) {
        // 用 jsonDecode 验证完整性
        jsonDecode(trimmed);

        // ✅ 是完整 JSON
        onCompleted(trimmed);
        _buffer.clear();
      }
    } catch (_) {
      // 还没收完整，继续等待
    }
  }

  void reset() {
    _buffer.clear();
  }
}

/// 设备连接状态数据
class DeviceConnectionState {
  final BleDeviceStatus status;
  final BleDeviceData? deviceData;
  final List<SimpleBLEScanResult> scanResults;
  final String? errorMessage;
  final double progress;
  final String? provisionStatus;
  final String? lastProvisionDeviceId;
  final List<WifiAp> wifiNetworks;
  final List<String> connectionLogs;
  final NetworkStatus? networkStatus;
  final bool isCheckingNetwork;
  final DateTime? networkStatusUpdatedAt;
  final String? firmwareVersion;
  final String? lastHandshakeErrorCode;
  final String? lastHandshakeErrorMessage;

  const DeviceConnectionState({
    this.status = BleDeviceStatus.disconnected,
    this.deviceData,
    this.scanResults = const [],
    this.errorMessage,
    this.progress = 0.0,
    this.provisionStatus,
    this.lastProvisionDeviceId,
    this.wifiNetworks = const [],
    this.connectionLogs = const [],
    this.networkStatus,
    this.isCheckingNetwork = false,
    this.networkStatusUpdatedAt,
    this.firmwareVersion,
    this.lastHandshakeErrorCode,
    this.lastHandshakeErrorMessage,
  });

  DeviceConnectionState copyWith({
    BleDeviceStatus? status,
    BleDeviceData? deviceData,
    List<SimpleBLEScanResult>? scanResults,
    String? errorMessage,
    double? progress,
    String? provisionStatus,
    String? lastProvisionDeviceId,
    List<WifiAp>? wifiNetworks,
    List<String>? connectionLogs,
    NetworkStatus? networkStatus,
    bool? isCheckingNetwork,
    DateTime? networkStatusUpdatedAt,
    String? firmwareVersion,
    String? lastHandshakeErrorCode,
    String? lastHandshakeErrorMessage,
  }) {
    return DeviceConnectionState(
      status: status ?? this.status,
      deviceData: deviceData ?? this.deviceData,
      scanResults: scanResults ?? this.scanResults,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
      provisionStatus: provisionStatus ?? this.provisionStatus,
      lastProvisionDeviceId: lastProvisionDeviceId ?? this.lastProvisionDeviceId,
      wifiNetworks: wifiNetworks ?? this.wifiNetworks,
      connectionLogs: connectionLogs ?? this.connectionLogs,
      networkStatus: networkStatus ?? this.networkStatus,
      isCheckingNetwork: isCheckingNetwork ?? this.isCheckingNetwork,
      networkStatusUpdatedAt: networkStatusUpdatedAt ?? this.networkStatusUpdatedAt,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      lastHandshakeErrorCode: lastHandshakeErrorCode ?? this.lastHandshakeErrorCode,
      lastHandshakeErrorMessage: lastHandshakeErrorMessage ?? this.lastHandshakeErrorMessage,
    );
  }
}

/// 设备连接管理器
class DeviceConnectionNotifier extends StateNotifier<DeviceConnectionState> {
  DeviceConnectionNotifier(this._ref) : super(const DeviceConnectionState()) {
    // Listen to foreground changes and try to ensure channel when returning to foreground
    _foregroundSub = _ref.listen<bool>(isForegroundProvider, (prev, curr) {
      if (curr == true) {
        _onEnterForeground();
      }
    });
  }

  final Ref _ref;

  StreamSubscription? _scanSubscription;
  Timer? _timeoutTimer;
  StreamSubscription<List<int>>? _provisionStatusSubscription;
  StreamSubscription<List<int>>? _wifiScanResultSubscription;
  StreamSubscription<List<int>>? _handshakeSubscription;
  ProviderSubscription<bool>? _foregroundSub;

  // Backoff tracking
  int _nextRetryMs = BleConstants.reconnectBackoffStartMs;
  DateTime? _lastAttemptAt;

  CryptoService? _cryptoService;

  // 分包拼接器
  BleChunkAssembler? _wifiAssembler;
  BleChunkAssembler? _handshakeAssembler;

  bool _hasReceivedWifiScanNotify = false;
  bool _syncedAfterLogin = false;
  // Network status read de-dup & throttle
  DateTime? _lastNetworkStatusReadAt;
  Future<NetworkStatus?>? _inflightNetworkStatusRead;

  /// 开始连接流程
  Future<void> startConnection(DeviceQrData qrData) async {
    state = const DeviceConnectionState();
    _log('初始化连接：${qrData.deviceName} (${qrData.deviceId})');
    _syncedAfterLogin = false;

    final deviceData = BleDeviceData(
      deviceId: qrData.deviceId,
      deviceName: qrData.deviceName,
      bleAddress: qrData.bleAddress,
      publicKey: qrData.publicKey,
      status: BleDeviceStatus.scanning,
    );

    state = state.copyWith(
      deviceData: deviceData,
      status: BleDeviceStatus.scanning,
      progress: 0.1,
    );

    final hasPermission = await BleServiceSimple.requestPermissions();
    if (!hasPermission) {
      _setError('蓝牙权限未授予或蓝牙未开启');
      return;
    }

    _log('权限通过，开始扫描目标设备');
    await _scanForDevice(deviceData);
  }

  Future<void> _onEnterForeground() async {
    // If we already authenticated, nothing to do
    if (state.status == BleDeviceStatus.authenticated) return;
    // If we have device info, attempt to ensure channel
    final d = state.deviceData;
    if (d != null) {
      await _ensureTrustedChannel(d);
    }
  }

  Future<void> _ensureTrustedChannel(BleDeviceData deviceData) async {
    // Cooldown to avoid thrash
    final now = DateTime.now();
    if (_lastAttemptAt != null &&
        now.difference(_lastAttemptAt!).inMilliseconds < _nextRetryMs) {
      return;
    }
    _lastAttemptAt = now;

    final hasPermission = await BleServiceSimple.requestPermissions();
    if (!hasPermission) {
      _log('蓝牙未就绪，跳过');
      return;
    }
    // Start scanning and connect when close
    await _scanForDevice(deviceData);
  }

  // 对外：确保可信通道（用于前台进入或下发指令前）
  Future<bool> ensureTrustedChannel() async {
    final d = state.deviceData;
    if (d == null) return false;
    if (state.status == BleDeviceStatus.authenticated) return true;
    await _ensureTrustedChannel(d);
    return state.status == BleDeviceStatus.authenticated;
  }

  Future<void> _scanForDevice(BleDeviceData deviceData) async {
    state = state.copyWith(status: BleDeviceStatus.scanning, progress: 0.3);
    _log('开始扫描目标设备，最长 30s...');
    // 重置目标首次出现时间与弱信号提示时间
    _targetFirstSeenAt = null;
    _lastWeakSignalNoteAt = null;

    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (state.status == BleDeviceStatus.scanning) {
        _setError('扫描超时：未找到目标设备');
      }
    });

    _scanSubscription = BleServiceSimple.scanForDevice(
      targetDeviceId: deviceData.deviceId,
      timeout: const Duration(seconds: 30),
    ).listen((scanResult) async {
      // 节流发现日志，避免刷屏（同一设备3秒内只打一条，除非RSSI变化>5）。
      // 注意：这里仅使用 print 而不更新 state，避免频繁重建影响连接时序。
      _maybePrintScanResult(scanResult);

      if (_isTargetDevice(scanResult, deviceData.deviceId)) {
        final now = DateTime.now();
        _targetFirstSeenAt ??= now;

        if (scanResult.rssi >= BleConstants.rssiProximityThreshold) {
          _log('✅ 找到目标设备且距离合适！准备连接');
          _timeoutTimer?.cancel();
          _scanSubscription?.cancel();
          await BleServiceSimple.stopScan();
          final connectionAddress = Platform.isIOS ? scanResult.deviceId : scanResult.address;
          _connectToDevice(deviceData.copyWith(bleAddress: connectionAddress));
          return;
        }

        // 如果持续找到目标设备超过宽限期，放宽RSSI限制以便尝试连接（可能用户设备远一点）
        const grace = Duration(seconds: 6);
        if (now.difference(_targetFirstSeenAt!) >= grace) {
          _log('⚠️ 信号偏弱(rssi=${scanResult.rssi})，已超过${grace.inSeconds}s，尝试连接');
          _timeoutTimer?.cancel();
          _scanSubscription?.cancel();
          await BleServiceSimple.stopScan();
          final connectionAddress = Platform.isIOS ? scanResult.deviceId : scanResult.address;
          _connectToDevice(deviceData.copyWith(bleAddress: connectionAddress));
          return;
        }

        // 节流提醒，避免每次都刷屏
        _maybePrintWeakSignal(scanResult.rssi);
      }
    }, onError: (error) {
      _setError('扫描出错: $error');
    });
  }

  // 用于节流的最近日志时间与RSSI
  final Map<String, DateTime> _lastScanLogAt = {};
  final Map<String, int> _lastScanLogRssi = {};
  static const Duration _scanLogInterval = Duration(seconds: 3);
  DateTime? _targetFirstSeenAt;
  DateTime? _lastWeakSignalNoteAt;
  static const Duration _weakNoteInterval = Duration(seconds: 5);

  void _maybePrintScanResult(SimpleBLEScanResult scanResult) {
    final id = scanResult.deviceId;
    final now = DateTime.now();
    final lastAt = _lastScanLogAt[id];
    final lastRssi = _lastScanLogRssi[id];
    final rssiChanged = lastRssi == null || (scanResult.rssi - lastRssi).abs() >= 5;
    final timeOk = lastAt == null || now.difference(lastAt) >= _scanLogInterval;
    if (timeOk || rssiChanged) {
      _lastScanLogAt[id] = now;
      _lastScanLogRssi[id] = scanResult.rssi;
      // ignore: avoid_print
      print('发现设备: ${scanResult.name} (${scanResult.deviceId}), RSSI=${scanResult.rssi}');
    }
  }

  void _maybePrintWeakSignal(int rssi) {
    final now = DateTime.now();
    if (_lastWeakSignalNoteAt == null || now.difference(_lastWeakSignalNoteAt!) >= _weakNoteInterval) {
      _lastWeakSignalNoteAt = now;
      // ignore: avoid_print
      print('⚠️ 信号强度不足，等待靠近后再连接 (rssi=$rssi)');
    }
  }

  bool _isTargetDevice(SimpleBLEScanResult result, String targetDeviceId) {
    // 优先使用厂商数据中的指纹匹配
    if (result.manufacturerData != null) {
      final expected = createDeviceFingerprint(targetDeviceId);
      final actual = result.manufacturerData!;
      if (_containsSublist(actual, expected)) return true;
    }
    // 兼容方案：部分设备固件未携带指纹时，回退到名称精确匹配
    // 仅当扫描得到的名称与二维码中的名称一致时视为目标设备
    final d = state.deviceData;
    if (d != null && result.name == d.deviceName) {
      return true;
    }
    return false;
  }

  bool _containsSublist(Uint8List data, Uint8List pattern) {
    for (int i = 0; i <= data.length - pattern.length; i++) {
      if (const ListEquality().equals(data.sublist(i, i + pattern.length), pattern)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _connectToDevice(BleDeviceData deviceData) async {
    state = state.copyWith(
      status: BleDeviceStatus.connecting,
      progress: 0.6,
    );
    _log('开始连接: ${deviceData.bleAddress}');

    final result = await BleServiceSimple.connectToDevice(
      deviceData: deviceData,
      timeout: const Duration(seconds: 15),
    );

      if (result != null) {
      state = state.copyWith(
        status: BleDeviceStatus.connected,
        progress: 0.8,
        deviceData: result,
      );
        _log('BLE 连接成功，准备发现服务并初始化');
        final ready = await BleServiceSimple.ensureGattReady(result.bleAddress);
        if (!ready) {
          _log('服务发现失败，触发重连');
          await BleServiceSimple.disconnect();
          _setError('连接失败');
          _nextRetryMs = (_nextRetryMs * 2).clamp(
              BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
          return;
        }
        await _initGattSession(result);
        await Future.delayed(Duration(milliseconds: BleConstants.postConnectStabilizeDelayMs));
        _log('开始认证握手');
        await _startAuthentication(result);
        // Reset backoff on success
        _nextRetryMs = BleConstants.reconnectBackoffStartMs;
    } else {
      _setError('连接失败');
      // Exponential backoff up to max
      _nextRetryMs = (_nextRetryMs * 2).clamp(
          BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
    }
  }

  /// 同步设备信息（A101），解析固件版本等，更新到状态
  Future<void> _syncDeviceInfo() async {
    try {
      final d = state.deviceData;
      if (d == null) return;
      final data = await BleServiceSimple.readCharacteristic(
        deviceId: d.bleAddress,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.deviceInfoCharUuid,
      );
      if (data == null || data.isEmpty) return;
      String text;
      // 尝试解密（若握手已建立，设备可能返回密文）
      try {
        if (_cryptoService != null && _cryptoService!.hasSecureSession) {
          final ed = EncryptedData.fromBytes(data);
          text = await _cryptoService!.decrypt(ed);
        } else {
          text = utf8.decode(data, allowMalformed: true).trim();
        }
      } catch (_) {
        text = utf8.decode(data, allowMalformed: true).trim();
      }
      // 尝试从返回的数据中提取版本号
      String? fw;
      // 1) 优先按 JSON 解析常见键位
      try {
        final obj = jsonDecode(text);
        if (obj is Map<String, dynamic>) {
          fw = (obj['version'] ?? obj['firmwareVersion'] ?? obj['ver'] ?? obj['fv'] ?? obj['fw'])
              ?.toString();
          // 如果仍然没有，从所有字符串值中正则提取类似 1.2.3 的版本号
          fw ??= obj.values
              .whereType<Object>()
              .map((e) => e.toString())
              .map(_extractVersion)
              .firstWhere((e) => e != null && e.isNotEmpty, orElse: () => null);
        }
      } catch (_) {
        // 非标准 JSON，尝试正则从原始文本中提取版本
        fw = _extractVersion(text);
      }
      if (fw != null && fw.isNotEmpty) {
        state = state.copyWith(firmwareVersion: fw);
        _log('📦 已同步固件版本: $fw');
      }
    } catch (_) {
      // ignore
    }
  }

  // 从字符串中提取常见版本号格式，例如 v1.2.3 或 1.0.0
  String? _extractVersion(String? input) {
    if (input == null) return null;
    final s = input.trim();
    if (s.isEmpty) return null;
    // 直接匹配版本片段
    final reg = RegExp(r'v?\d+(?:\.\d+){1,3}');
    final m = reg.firstMatch(s);
    if (m != null) return m.group(0);
    return null;
  }

  Future<void> _initGattSession(BleDeviceData deviceData) async {
    final deviceId = deviceData.bleAddress;

    // 清理旧订阅，避免重连后出现多路回调
    await _provisionStatusSubscription?.cancel();
    await _wifiScanResultSubscription?.cancel();
    await _handshakeSubscription?.cancel();
    _provisionStatusSubscription = null;
    _wifiScanResultSubscription = null;
    _handshakeSubscription = null;
    _wifiAssembler?.reset();
    _handshakeAssembler?.reset();

    // 订阅 A107（Wifi_Config_Status）
    _provisionStatusSubscription =
        BleServiceSimple.subscribeToCharacteristic(
          deviceId: deviceId,
          serviceUuid: BleConstants.serviceUuid,
          characteristicUuid: BleConstants.wifiConfigStatusCharUuid,
        ).listen((data) async {
          // Debug: trace incoming A107
          try {
            // ignore: avoid_print
            print('[A107] notify len=${data.length}');
          } catch (_) {}
          // 若已建立会话，则尝试按密文解密，否则回退到明文
          String? status;
          try {
            if (_cryptoService != null && _cryptoService!.hasSecureSession) {
              final ed = EncryptedData.fromBytes(data);
              status = await _cryptoService!.decrypt(ed);
            }
          } catch (_) {
            // ignore and fallback
          }
          status ??= utf8.decode(data, allowMalformed: true);
          // Debug: log normalized status key
          try {
            final peek = status?.length ?? 0;
            // ignore: avoid_print
            print('[A107] payload peek=${peek}');
          } catch (_) {}
          final normalized = _normalizeBleStatus(status);
          try { print('[A107] status=$normalized'); } catch (_) {}
          final devId = _extractDeviceId(status);
          state = state.copyWith(provisionStatus: normalized, lastProvisionDeviceId: devId);
          // 绑定登录成功后，主动同步远端绑定列表并选中当前设备
          final s = (normalized).toLowerCase();
          if (!_syncedAfterLogin && (s == 'login_success' || s.contains('login_success'))) {
            _syncedAfterLogin = true;
            try {
              // 先远端同步，确保列表与元数据以服务端为准
              await _ref.read(savedDevicesProvider.notifier).syncFromServer();
              final id = state.deviceData?.deviceId;
              if (id != null && id.isNotEmpty) {
                await _ref.read(savedDevicesProvider.notifier).select(id);
              }
              // 再叠加 BLE 内联设备/网络信息（仅当前设备）
              _maybeApplyInlineDeviceAndNetwork(status, expectedDeviceId: state.deviceData?.deviceId);
            } catch (_) {}
          }
        });

    // 订阅 A103 + 分包拼接
    _wifiAssembler = BleChunkAssembler(
      characteristic: 'A103',
      timeoutMs: 2000,
      onCompleted: (json) {
        final parsed = _parseWifiScanJson(json);
        state = state.copyWith(wifiNetworks: parsed);
      },
    );

    _wifiScanResultSubscription = BleServiceSimple.subscribeToCharacteristic(
      deviceId: deviceId,
      serviceUuid: BleConstants.serviceUuid,
      characteristicUuid: BleConstants.wifiScanResultCharUuid,
    ).listen((chunk) {
      _wifiAssembler?.addChunk(chunk);
    });
  }

  // 统一规范化 BLE 文本/JSON 状态载荷，提取 status 字段
  String _normalizeBleStatus(String? raw) {
    if (raw == null) return '';
    final s = raw.trim();
    if (s.isEmpty) return s;
    if (s.startsWith('{')) {
      try {
        final obj = jsonDecode(s);
        if (obj is Map<String, dynamic>) {
          final st = obj['status']?.toString();
          if (st != null && st.isNotEmpty) return st;
        }
      } catch (_) {
        // ignore and fallback
      }
    }
    return s;
  }

  // 当 login_success 载荷带上了设备信息/网络信息时，尽早更新本地可见状态
  void _maybeApplyInlineDeviceAndNetwork(String? raw, {String? expectedDeviceId}) {
    if (raw == null) return;
    final s = raw.trim();
    if (!s.startsWith('{')) return;
    try {
      final obj = jsonDecode(s);
      if (obj is! Map<String, dynamic>) return;
      // 如果载荷包含 deviceId 且与当前设备不一致，则忽略该通知
      final payloadDeviceId = obj['deviceId']?.toString();
      if (expectedDeviceId != null && expectedDeviceId.isNotEmpty) {
        if (payloadDeviceId != null && payloadDeviceId.isNotEmpty && payloadDeviceId != expectedDeviceId) {
          return;
        }
      }
      // 设备信息字段容错：device/deviceInfo/info
      final dinfo = (obj['device'] ?? obj['deviceInfo'] ?? obj['info']);
      String? fwValue;
      if (dinfo is Map<String, dynamic>) {
        // 常见字段：version/firmwareVersion/fw
        final fw = (dinfo['version'] ?? dinfo['firmwareVersion'] ?? dinfo['fw'] ?? dinfo['ver'])?.toString();
        if (fw != null && fw.isNotEmpty) fwValue = _extractVersion(fw);
      }
      // 网络信息字段容错：network/networkStatus/net
      final ninfo = (obj['network'] ?? obj['networkStatus'] ?? obj['net']);
      String? networkSummary;
      if (ninfo is Map<String, dynamic>) {
        try {
          final ns = NetworkStatus.fromJson(ninfo);
          state = state.copyWith(networkStatus: ns, networkStatusUpdatedAt: DateTime.now());
          networkSummary = ns.connected ? (ns.displaySsid ?? 'connected') : 'offline';
        } catch (_) {}
      }
      // 将 BLE 获取到的信息叠加到设备列表中（基于远端同步的结果）
      final targetId = expectedDeviceId ?? payloadDeviceId ?? state.deviceData?.deviceId;
      if (targetId != null && targetId.isNotEmpty) {
        _ref.read(savedDevicesProvider.notifier).overlayInlineInfo(
              deviceId: targetId,
              firmwareVersion: fwValue,
              networkSummary: networkSummary,
              lastBleAddress: state.deviceData?.bleAddress,
            );
      }
    } catch (_) {}
  }

  // 从 BLE 文本/JSON 载荷中提取 deviceId（若存在）
  String? _extractDeviceId(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('{')) {
      try {
        final obj = jsonDecode(s);
        if (obj is Map<String, dynamic>) {
          final id = obj['deviceId']?.toString();
          if (id != null && id.isNotEmpty) return id;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _startAuthentication(BleDeviceData deviceData) async {
    state = state.copyWith(status: BleDeviceStatus.authenticating, progress: 0.9);
    _cryptoService = CryptoService();
    await _cryptoService!.generateEphemeralKeyPair();

    final deviceId = deviceData.bleAddress;

    var handshakeInit = await _cryptoService!.getHandshakeInitData();
    try {
      final supaUserId = Supabase.instance.client.auth.currentUser?.id;
      if (supaUserId != null && supaUserId.isNotEmpty) {
        final obj = jsonDecode(handshakeInit) as Map<String, dynamic>;
        obj['userId'] = supaUserId;
        handshakeInit = jsonEncode(obj);
      }
    } catch (_) {}

    _handshakeAssembler = BleChunkAssembler(
      characteristic: 'A105',
      timeoutMs: 2000,
      onCompleted: (json) async {
        // 兼容 A105 的后续简短通知，例如 {"type":"authenticated"}
        try {
          final response = _cryptoService!.parseHandshakeResponse(json);
          final publicKey = await _cryptoService!.getLocalPublicKey();
          await _cryptoService!.performKeyExchange(
            remoteEphemeralPubKey: response.publicKey,
            signature: response.signature,
            devicePublicKeyHex: deviceData.publicKey,
            clientEphemeralPubKey: publicKey,
            timestamp: response.timestamp,
            clientTimestamp: _cryptoService!.clientTimestamp!,
          );
          state = state.copyWith(status: BleDeviceStatus.authenticated, progress: 1.0);
          _log('🎉 认证完成');
          // 握手完成后，立刻通过加密通道同步设备信息与网络状态
          await _syncDeviceInfo();
          await checkNetworkStatus();
        } catch (_) {
          // 非握手响应，尝试解析通用 JSON 并根据 type 处理
          try {
            final map = jsonDecode(json) as Map<String, dynamic>;
            final type = map['type']?.toString();
            // 显式错误处理：设备已被其他账号绑定
            final message = (map['message'] ?? map['reason'] ?? '').toString();
            final code = (map['code'] ?? '').toString();
            final isBoundByOther =
                type == 'error' && (
                  code == 'user_mismatch' ||
                  message.contains('仅允许相同 userId') ||
                  message.contains('设备已登录') ||
                  message.contains('已被其他账号绑定')
                );
            if (isBoundByOther) {
              _log('❌ 设备拒绝握手：设备已被其他账号绑定');
              // 记录最近一次握手错误，供上层UI兜底识别
              state = state.copyWith(
                lastHandshakeErrorCode: code.isNotEmpty ? code : 'user_mismatch',
                lastHandshakeErrorMessage: message.isNotEmpty ? message : 'device already logged in; only same userId allowed',
              );
              // 断开以清理会话
              await BleServiceSimple.disconnect();
              // 设置明确的错误消息供 UI 感知
              _setError('设备已被其他账号绑定');
              return;
            }
            if (type == 'authenticated') {
              // 如果先收到 authenticated 快速通知，也标记为已认证
              if (state.status != BleDeviceStatus.authenticated) {
                state = state.copyWith(status: BleDeviceStatus.authenticated, progress: 1.0);
                _log('📣 收到 A105 authenticated 通知，标记为已认证');
              }
              // 确认认证后，同步信息
              await _syncDeviceInfo();
              await checkNetworkStatus();
            }
          } catch (_) {
            // 忽略无法解析的负载
          }
        }
      },
    );

    _handshakeSubscription = BleServiceSimple.subscribeToCharacteristic(
      deviceId: deviceId,
      serviceUuid: BleConstants.serviceUuid,
      characteristicUuid: BleConstants.secureHandshakeCharUuid,
    ).listen((chunk) {
      _handshakeAssembler?.addChunk(chunk);
    });

    final ok = await BleServiceSimple.writeCharacteristic(
      deviceId: deviceId,
      serviceUuid: BleConstants.serviceUuid,
      characteristicUuid: BleConstants.secureHandshakeCharUuid,
      data: handshakeInit.codeUnits,
      withResponse: true,
    );
    if (!ok) {
      _log('握手首包写入失败，准备断开重连（可能是 GATT 133/服务未就绪）');
      await BleServiceSimple.disconnect();
      _setError('连接失败');
      _nextRetryMs = (_nextRetryMs * 2).clamp(
          BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
      return;
    }
    _log('握手请求已发送');
  }

  // ======================
  // 👉 补回你之前的全部方法
  // ======================

  Future<void> disconnect() async {
    _scanSubscription?.cancel();
    _timeoutTimer?.cancel();
    await _provisionStatusSubscription?.cancel();
    await _wifiScanResultSubscription?.cancel();
    await _handshakeSubscription?.cancel();
    _cryptoService?.cleanup();
    _cryptoService = null;

    await BleServiceSimple.disconnect();
    state = state.copyWith(status: BleDeviceStatus.disconnected, progress: 0.0);
  }

  void reset() {
    _timeoutTimer?.cancel();
    _scanSubscription?.cancel();
    _provisionStatusSubscription?.cancel();
    _wifiScanResultSubscription?.cancel();
    _handshakeSubscription?.cancel();
    _cryptoService?.cleanup();
    _cryptoService = null;
    state = const DeviceConnectionState();
  }

  Future<bool> sendWifiCredentials(String ssid, String password) async {
    return await sendProvisionRequest(ssid: ssid, password: password);
  }

  Future<bool> sendProvisionRequest({
    required String ssid,
    required String password,
  }) async {
    if (state.deviceData == null) return false;
    // 确保可信通道
    final okChannel = await ensureTrustedChannel();
    if (!okChannel) {
      _log('❌ 未建立可信通道，取消发送WiFi凭证');
      return false;
    }

    try {
      final deviceAddr = state.deviceData!.bleAddress;
      final json = jsonEncode({
        'deviceId': state.deviceData!.deviceId,
        'ssid': _escapeJson(ssid),
        'password': _escapeJson(password),
      });
      final ed = await _cryptoService!.encrypt(json);
      final ok = await BleServiceSimple.writeCharacteristic(
        deviceId: deviceAddr,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.wifiConfigRequestCharUuid,
        data: ed.toBytes(),
        withResponse: true,
      );
      if (!ok) {
        _log('写入加密WiFi凭证失败，触发断开以自愈');
        await BleServiceSimple.disconnect();
        _setError('连接失败');
        _nextRetryMs = (_nextRetryMs * 2).clamp(
            BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendDeviceLoginCode(String code) async {
    if (state.deviceData == null) return false;
    final okChannel = await ensureTrustedChannel();
    if (!okChannel) {
      _log('❌ 未建立可信通道，取消发送登录验证码');
      return false;
    }
    try {
      final deviceAddr = state.deviceData!.bleAddress;
      final json = jsonEncode({
        'deviceId': state.deviceData!.deviceId,
        'code': _escapeJson(code),
      });
      final ed = await _cryptoService!.encrypt(json);
      final data = ed.toBytes();
      final ok = await BleServiceSimple.writeCharacteristic(
        deviceId: deviceAddr,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.loginAuthCodeCharUuid,
        data: data,
        withResponse: true,
      );
      if (!ok) {
        _log('写入登录验证码失败，触发断开以自愈');
        await BleServiceSimple.disconnect();
        _setError('连接失败');
        _nextRetryMs = (_nextRetryMs * 2).clamp(
            BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendDeviceLogout() async {
    if (state.deviceData == null) return false;
    final okChannel = await ensureTrustedChannel();
    if (!okChannel) {
      _log('❌ 未建立可信通道，取消发送退出登录');
      return false;
    }
    try {
      final deviceAddr = state.deviceData!.bleAddress;
      final payload = jsonEncode({
        'deviceId': state.deviceData!.deviceId,
        'userId': _currentUserIdOrEmpty(),
      });
      final ed = await _cryptoService!.encrypt(payload);
      final ok = await BleServiceSimple.writeCharacteristic(
        deviceId: deviceAddr,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.logoutCharUuid,
        data: ed.toBytes(),
        withResponse: true,
      );
      if (!ok) {
        _log('退出登录写入失败，触发断开以自愈');
        await BleServiceSimple.disconnect();
        _setError('连接失败');
        _nextRetryMs = (_nextRetryMs * 2).clamp(
            BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  // TODO: 从真实账号体系获取当前用户ID；此处占位返回空字符串
  String _currentUserIdOrEmpty() {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      return user?.id ?? '';
    } catch (_) {
      return '';
    }
  }

  // 对外暴露：当前登录用户ID（无则空串）
  String currentUserId() => _currentUserIdOrEmpty();

  Future<bool> requestWifiScan() async {
    if (state.deviceData == null) return false;
    // 确保可信通道
    final okChannel = await ensureTrustedChannel();
    if (!okChannel) {
      _log('❌ 未建立可信通道，取消发送WiFi扫描请求');
      return false;
    }
    try {
      // WiFi 扫描请求目前保持明文（无敏感信息）
      final ok = await BleServiceSimple.writeCharacteristic(
        deviceId: state.deviceData!.bleAddress,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.wifiScanRequestCharUuid,
        data: '{}'.codeUnits,
        withResponse: true,
      );
      if (ok) {
        print('📤 已写入WiFi扫描请求');
      } else {
        _log('WiFi扫描请求写入失败，触发断开以自愈');
        await BleServiceSimple.disconnect();
        _setError('连接失败');
        _nextRetryMs = (_nextRetryMs * 2).clamp(
            BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  // 通用：带可信通道检查的写接口（供未来指令统一调用）
  Future<bool> writeWithTrustedChannel({
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> data,
    bool withResponse = true,
  }) async {
    if (state.deviceData == null) return false;
    final okChannel = await ensureTrustedChannel();
    if (!okChannel) {
      _log('❌ 可信通道不可用，写入取消');
      return false;
    }
    final ok = await BleServiceSimple.writeCharacteristic(
      deviceId: state.deviceData!.bleAddress,
      serviceUuid: serviceUuid,
      characteristicUuid: characteristicUuid,
      data: data,
      withResponse: withResponse,
    );
    if (!ok) {
      _log('❌ 写入失败，触发断开以自愈');
      await BleServiceSimple.disconnect();
      _setError('连接失败');
      _nextRetryMs = (_nextRetryMs * 2).clamp(
          BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
    }
    return ok;
  }

  // 使用会话密钥对 JSON 负载加密并写入指定特征
  Future<bool> writeEncryptedJson({
    required String characteristicUuid,
    required Map<String, dynamic> json,
  }) async {
    if (state.deviceData == null) return false;
    final okChannel = await ensureTrustedChannel();
    if (!okChannel || _cryptoService == null || !_cryptoService!.hasSecureSession) {
      _log('❌ 可信通道不可用或未建立会话密钥');
      return false;
    }
    try {
      // 保险：确认目标特征存在，避免 INVALID_HANDLE
      final deviceId = state.deviceData!.bleAddress;
      final hasChar = await BleServiceSimple.hasCharacteristic(
        deviceId: deviceId,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: characteristicUuid,
      );
      if (!hasChar) {
        _log('❌ 目标特征不存在：$characteristicUuid');
        return false;
      }
      final payload = jsonEncode(json);
      final ed = await _cryptoService!.encrypt(payload);
      final ok = await BleServiceSimple.writeCharacteristic(
        deviceId: deviceId,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: characteristicUuid,
        data: ed.toBytes(),
        withResponse: true,
      );
      if (!ok) {
        _log('❌ 加密写入失败，触发断开以自愈');
        await BleServiceSimple.disconnect();
        _setError('连接失败');
        _nextRetryMs = (_nextRetryMs * 2).clamp(
            BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<NetworkStatus?> checkNetworkStatus() async {
    if (state.deviceData == null) return null;
    // Throttle: if read within last 400ms, return cached value
    final now = DateTime.now();
    if (_lastNetworkStatusReadAt != null &&
        now.difference(_lastNetworkStatusReadAt!) < const Duration(milliseconds: 400)) {
      return state.networkStatus;
    }
    // Deduplicate concurrent reads
    if (_inflightNetworkStatusRead != null) {
      return _inflightNetworkStatusRead;
    }
    state = state.copyWith(isCheckingNetwork: true);
    _lastNetworkStatusReadAt = now;
    final future = _doReadNetworkStatus();
    _inflightNetworkStatusRead = future;
    final res = await future;
    _inflightNetworkStatusRead = null;
    state = state.copyWith(isCheckingNetwork: false);
    return res;
  }

  Future<NetworkStatus?> _doReadNetworkStatus() async {
    try {
      final data = await BleServiceSimple.readCharacteristic(
        deviceId: state.deviceData!.bleAddress,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.networkStatusCharUuid,
      );
      if (data != null && data.isNotEmpty) {
        // 优先尝试解密（握手完成后设备可能返回密文）
        NetworkStatus? networkStatus;
        try {
          if (_cryptoService != null && _cryptoService!.hasSecureSession) {
            final ed = EncryptedData.fromBytes(data);
            final plain = await _cryptoService!.decrypt(ed);
            final map = jsonDecode(plain) as Map<String, dynamic>;
            networkStatus = NetworkStatus.fromJson(map);
          }
        } catch (_) {
          // ignore and fallback to plaintext JSON
        }
        networkStatus ??= NetworkStatusParser.fromBleData(data);
        if (networkStatus != null) {
          state = state.copyWith(
            networkStatus: networkStatus,
            networkStatusUpdatedAt: DateTime.now(),
          );
          return networkStatus;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> handleWifiSmartly() async {
    final ns = await checkNetworkStatus();
    if (ns == null || !ns.connected) {
      await requestWifiScan();
    }
  }

  // ======================

  List<WifiAp> _parseWifiScanJson(String json) {
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list
          .map((e) => WifiAp(
          ssid: e['ssid'] ?? '',
          rssi: int.tryParse(e['rssi']?.toString() ?? '') ?? 0,
          secure: e['secure'] == true,
          bssid: e['bssid'],
          frequency: e['frequency']))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _escapeJson(String s) => s
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');

  void _setError(String message) {
    state = state.copyWith(status: BleDeviceStatus.error, errorMessage: message);
  }

  static const int _maxConnectionLogs = 200; // 限制保留的连接日志条数，避免内存与重建压力
  void _log(String msg) {
    final now = DateTime.now().toIso8601String();
    final nextLogs = [...state.connectionLogs, "[$now] $msg"];
    final trimmedLogs = nextLogs.length > _maxConnectionLogs
        ? nextLogs.sublist(nextLogs.length - _maxConnectionLogs)
        : nextLogs;
    state = state.copyWith(connectionLogs: trimmedLogs);
    print(msg);
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _timeoutTimer?.cancel();
    _provisionStatusSubscription?.cancel();
    _wifiScanResultSubscription?.cancel();
    _handshakeSubscription?.cancel();
    _cryptoService?.cleanup();
    super.dispose();
  }
}

class WifiAp {
  final String ssid;
  final int rssi;
  final bool secure;
  final String? bssid;
  final int? frequency;

  const WifiAp({
    required this.ssid,
    required this.rssi,
    required this.secure,
    this.bssid,
    this.frequency,
  });
}

final deviceConnectionProvider =
StateNotifierProvider<DeviceConnectionNotifier, DeviceConnectionState>((ref) {
  final notifier = DeviceConnectionNotifier(ref);
  ref.onDispose(() => notifier.dispose());
  return notifier;
});
