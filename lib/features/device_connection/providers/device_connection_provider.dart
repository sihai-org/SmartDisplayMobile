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
import '../services/reliable_queue.dart';
import '../../../core/providers/lifecycle_provider.dart';
import '../../../core/providers/saved_devices_provider.dart';
import 'dart:developer' as developer;

// 旧版分包拼接工具已移除；双特征通道统一使用帧协议 + 可靠队列。

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
  // 旧版特征订阅已移除（A103/A107/A105）
  ProviderSubscription<bool>? _foregroundSub;
  ReliableRequestQueue? _rq; // dual-char reliable queue
  StreamSubscription<Map<String, dynamic>>? _rqEventsSub; // push events from peripheral

  // Backoff tracking
  int _nextRetryMs = BleConstants.reconnectBackoffStartMs;
  DateTime? _lastAttemptAt;

  CryptoService? _cryptoService;

  // 旧版分包拼接器/标志已移除
  bool _syncedAfterLogin = false;
  // Network status read de-dup & throttle
  DateTime? _lastNetworkStatusReadAt;
  Future<NetworkStatus?>? _inflightNetworkStatusRead;

  // Timing markers for profiling
  DateTime? _sessionStart;
  DateTime? _connectStart;
  // Post-provision polling to settle network status
  Future<void>? _postProvisionPoll;

  void _t(String label) {
    final now = DateTime.now();
    if (_sessionStart != null) {
      final ms = now.difference(_sessionStart!).inMilliseconds;
      _log('⏱ [$ms ms] $label');
    } else {
      _log('⏱ $label');
    }
  }

  /// 开始连接流程
  Future<void> startConnection(DeviceQrData qrData) async {
    state = const DeviceConnectionState();
    _sessionStart = DateTime.now();
    _log('初始化连接：${qrData.deviceName} (${qrData.deviceId})');
    _t('session.start');
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
    // Dual-char queue ready implies trusted channel
    if (_rq != null) return true;
    if (state.status == BleDeviceStatus.authenticated) return true;
    await _ensureTrustedChannel(d);
    return state.status == BleDeviceStatus.authenticated;
  }

  Future<void> _scanForDevice(BleDeviceData deviceData) async {
    state = state.copyWith(status: BleDeviceStatus.scanning, progress: 0.3);
    _t('scan.start');
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
          _t('scan.first_target_ready');
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
          _t('scan.force_connect_after_grace');
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
    _connectStart = DateTime.now();
    _t('connect.start');
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
        _t('connect.done');
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
        // Prefer dual-char RX/TX if available
        final hasDual = await BleServiceSimple.hasRxTx(
          deviceId: result.bleAddress,
          serviceUuid: BleConstants.serviceUuid,
          rxUuid: BleConstants.rxCharUuid,
          txUuid: BleConstants.txCharUuid,
        );
        if (hasDual) {
          // 准备可靠请求通道
          try { await _rq?.dispose(); } catch (_) {}
          _rq = ReliableRequestQueue(deviceId: result.bleAddress);
          final ts = DateTime.now();
          await _rq!.prepare();
          _t('dualtx.ready(+${DateTime.now().difference(ts).inMilliseconds}ms prepare)');
          _log('✅ Dual-char RX/TX 可用，准备应用层握手');

          // 应用层握手（通过 RX/TX 帧协议）
          state = state.copyWith(status: BleDeviceStatus.authenticating, progress: 0.9);
          _cryptoService = CryptoService();
          await _cryptoService!.generateEphemeralKeyPair();
          var handshakeInit = await _cryptoService!.getHandshakeInitData();
          try {
            final supaUserId = Supabase.instance.client.auth.currentUser?.id;
            if (supaUserId != null && supaUserId.isNotEmpty) {
              final obj = jsonDecode(handshakeInit) as Map<String, dynamic>;
              obj['userId'] = supaUserId;
              handshakeInit = jsonEncode(obj);
            }
          } catch (_) {}

          // 发送握手请求并等待握手响应
          final initObj = jsonDecode(handshakeInit) as Map<String, dynamic>;
          _t('handshake.start');
          final resp = await _rq!.send(initObj, timeout: const Duration(seconds: 8), retries: 1,
              isFinal: (msg) => (msg['type']?.toString() == 'handshake_response'));
          try {
            final responseJson = jsonEncode(resp);
            final parsed = _cryptoService!.parseHandshakeResponse(responseJson);
            final publicKey = await _cryptoService!.getLocalPublicKey();
            await _cryptoService!.performKeyExchange(
              remoteEphemeralPubKey: parsed.publicKey,
              signature: parsed.signature,
              devicePublicKeyHex: result.publicKey,
              clientEphemeralPubKey: publicKey,
              timestamp: parsed.timestamp,
              clientTimestamp: _cryptoService!.clientTimestamp!,
            );
            state = state.copyWith(status: BleDeviceStatus.authenticated, progress: 1.0);
            _t('handshake.done');
            _log('🎉 应用层握手完成');

            // Install crypto handlers on reliable queue for post-handshake traffic
          try {
              _rq!.setCryptoHandlers(
                encrypt: (Map<String, dynamic> plain) async {
                  final text = jsonEncode(plain);
                  final enc = await _cryptoService!.encrypt(text);
                  final b64 = base64Encode(Uint8List.fromList(enc.toBytes()));
                  return {'type': 'enc', 'data': b64};
                },
                decrypt: (Map<String, dynamic> msg) async {
                  if (msg['type'] == 'enc' && msg['data'] is String) {
                    final raw = base64Decode(msg['data'] as String);
                    final ed = EncryptedData.fromBytes(raw);
                    final plain = await _cryptoService!.decrypt(ed);
                    final obj = jsonDecode(plain) as Map<String, dynamic>;
                    // Preserve reqId/hReqId for matching and diagnostics
                    final hReqId = msg['hReqId'];
                    if (hReqId != null) obj['hReqId'] = hReqId;
                    obj['reqId'] = obj['reqId'] ?? msg['reqId'] ?? hReqId;
                    return obj;
                  }
                  return msg;
                },
              );
            } catch (e) {
              _log('⚠️ 安装加密处理器失败: $e');
            }

            // 订阅设备端推送事件（如 notifyBleOnly 的加密 status 事件）
            try {
              await _rqEventsSub?.cancel();
              _rqEventsSub = _rq!.events.listen((evt) async {
                final type = (evt['type'] ?? '').toString();
                if (type == 'status') {
                  final s = (evt['status'] ?? '').toString();
                  _log('📣 收到设备事件: status=$s');
                  // 依据常见状态做一些内联动作
                  if (s == 'authenticated') {
                    state = state.copyWith(status: BleDeviceStatus.authenticated);
                  } else if (s == 'wifi_online') {
                    // 标记配网成功（去重），并刷新网络状态
                    if (state.provisionStatus != 'wifi_online') {
                      state = state.copyWith(
                        provisionStatus: 'wifi_online',
                        lastProvisionDeviceId: state.deviceData?.deviceId ?? state.lastProvisionDeviceId,
                      );
                    }
                    await _doReadNetworkStatus();
                    _kickoffPostProvisionPolling();
                  }
                } else if (type == 'error') {
                  _log('📣 设备事件错误: ${evt['error']}');
                } else {
                  _log('📣 收到设备事件: $evt');
                }
              });
            } catch (e) {
              _log('⚠️ 订阅设备推送事件失败: $e');
            }
          } catch (e) {
            _t('handshake.error');
            _log('❌ 应用层握手失败: $e');
            await BleServiceSimple.disconnect();
            _setError('连接失败');
            _nextRetryMs = (_nextRetryMs * 2).clamp(
                BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
            return;
          }
        } else {
          _log('❌ 设备不支持双特征通道 (RX/TX)，取消');
          await BleServiceSimple.disconnect();
          _setError('连接失败');
          _nextRetryMs = (_nextRetryMs * 2).clamp(
              BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
          return;
        }
        // Reset backoff on success
        _nextRetryMs = BleConstants.reconnectBackoffStartMs;
    } else {
      _setError('连接失败');
      // Exponential backoff up to max
      _nextRetryMs = (_nextRetryMs * 2).clamp(
          BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
    }
  }

  // 旧版设备信息读取（A101）已移除；设备信息改由业务层通过命令获取（如需）。

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

  // 旧版 GATT 会话/订阅（A103/A107）已移除；双特征下通过请求/响应帧传递状态与结果。

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

  // 旧版 A105 握手流程已移除；双特征下在连接后通过可靠队列发送 handshake_init 并等待 handshake_response。

  // ======================
  // 👉 补回你之前的全部方法
  // ======================

  Future<void> disconnect() async {
    _scanSubscription?.cancel();
    _timeoutTimer?.cancel();
    await _rq?.dispose();
    _rq = null;
    _cryptoService?.cleanup();
    _cryptoService = null;

    await BleServiceSimple.disconnect();
    state = state.copyWith(status: BleDeviceStatus.disconnected, progress: 0.0);
  }

  void reset() {
    _timeoutTimer?.cancel();
    _scanSubscription?.cancel();
    _rq?.dispose();
    _rq = null;
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
    try {
      // 进入配网中状态并记录设备ID
      final currId = state.deviceData!.deviceId;
      state = state.copyWith(provisionStatus: 'provisioning', lastProvisionDeviceId: currId);
      final resp = await _rq!.send({
        'type': 'wifi.config',
        'data': { 'ssid': ssid, 'password': password }
      });
      final ok = resp['ok'] == true;
      if (!ok) state = state.copyWith(provisionStatus: 'failed');
      // 启动后台轮询以尽快拿到最新网络状态（若事件稍后才到也能兜底）
      _kickoffPostProvisionPolling();
      return ok;
    } catch (e) {
      _log('❌ wifi.config 失败: $e');
      state = state.copyWith(provisionStatus: 'failed');
      return false;
    }
  }

  Future<bool> sendDeviceLoginCode(String code) async {
    if (state.deviceData == null) return false;
    try {
      final resp = await _rq!.send({
        'type': 'login.auth',
        'data': { 'email': '', 'otpToken': code },
      });
      return resp['ok'] == true || resp['type'] == 'login.auth';
    } catch (e) {
      _log('❌ login.auth 失败: $e');
      return false;
    }
  }

  Future<bool> sendDeviceLogout() async {
    if (state.deviceData == null) return false;
    try {
      final resp = await _rq!.send({
        'type': 'logout',
        'data': { 'userId': _currentUserIdOrEmpty() },
      });
      return resp['ok'] == true || resp['type'] == 'logout';
    } catch (e) {
      _log('❌ logout 失败: $e');
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
    try {
      // 确保可信通道（支持双通道/握手后）
      var okChannel = await ensureTrustedChannel();
      if (!okChannel || _rq == null) {
        // 等待认证完成（最多6秒），避免用户点击时通道尚未就绪导致“无反应”
        await _waitForAuthenticated(const Duration(seconds: 6));
        okChannel = _rq != null || state.status == BleDeviceStatus.authenticated;
        if (!okChannel || _rq == null) {
          _log('❌ wifi.scan 取消：通道未就绪');
          return false;
        }
      }
      _log('⏳ 开始扫描附近Wi‑Fi...');
      final resp = await _rq!.send(
        { 'type': 'wifi.scan' },
        timeout: const Duration(seconds: 3),
        retries: 0,
      );
      final data = resp['data'];
      if (data is List) {
        final networks = data.map((e) => WifiAp(
          ssid: (e['ssid'] ?? '').toString(),
          rssi: int.tryParse((e['rssi'] ?? '0').toString()) ?? 0,
          secure: (e['secure'] == true),
          bssid: e['bssid']?.toString(),
          frequency: int.tryParse((e['frequency'] ?? '').toString()),
        )).toList().cast<WifiAp>();
        state = state.copyWith(wifiNetworks: networks);
        _log('📶 Wi‑Fi 扫描完成，发现 ${networks.length} 个网络');
      }
      return true;
    } catch (e) {
      _log('❌ wifi.scan 失败: $e');
      return false;
    }
  }

  Future<void> _waitForAuthenticated(Duration timeout) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      if (state.status == BleDeviceStatus.authenticated || _rq != null) return;
      await Future.delayed(const Duration(milliseconds: 150));
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
    try {
      if (characteristicUuid == BleConstants.loginAuthCodeCharUuid) {
        final payload = {
          'type': 'login.auth',
          'data': {
            'email': json['email'] ?? '',
            'otpToken': json['otpToken'] ?? json['code'] ?? '',
          },
        };
        // 在双特征+帧协议下，将登录建模为“异步完成”的一次调用：
        // 1) 设备可先返回 ack/accepted；
        // 2) 登录完成后再返回 login.result 或包含 status=login_success 的事件帧（沿用同 reqId）。
        final resp = await _rq!.send(
          payload,
          timeout: const Duration(seconds: 25),
          retries: 0,
          isFinal: (msg) {
            final type = (msg['type'] ?? '').toString();
            final data = msg['data'];
            final status = data is Map<String, dynamic> ? (data['status'] ?? '').toString() : (msg['status'] ?? '').toString();
            if (type == 'login.result') return true;
            if (status == 'login_success' || status == 'login_failed') return true;
            return false; // 对 ack/accepted 等中间态继续等待
          },
        );
        // 同步状态，触发上层UI跳转与数据同步（与 A107 行为对齐）
        try {
          final data = resp['data'];
          final status = data is Map<String, dynamic> ? (data['status'] ?? '').toString() : (resp['status'] ?? '').toString();
          if (status == 'login_success') {
            state = state.copyWith(provisionStatus: 'login_success', lastProvisionDeviceId: state.deviceData?.deviceId);
            if (!_syncedAfterLogin) {
              _syncedAfterLogin = true;
              try {
                await _ref.read(savedDevicesProvider.notifier).syncFromServer();
                final id = state.deviceData?.deviceId;
                if (id != null && id.isNotEmpty) {
                  await _ref.read(savedDevicesProvider.notifier).select(id);
                }
                _maybeApplyInlineDeviceAndNetwork(data is Map<String, dynamic> ? jsonEncode(data) : null,
                    expectedDeviceId: state.deviceData?.deviceId);
              } catch (_) {}
            }
            return true;
          }
          if (status == 'login_failed') {
            _setError('设备登录失败');
            return false;
          }
        } catch (_) {}
        // 若未带明确状态，依据 ok/type 回退判断
        return resp['ok'] == true || resp['type'] == 'login.result';
      }
      if (characteristicUuid == BleConstants.logoutCharUuid) {
        final payload = {
          'type': 'logout',
          'data': { 'userId': json['userId'] ?? _currentUserIdOrEmpty() },
        };
        final resp = await _rq!.send(payload);
        return resp['ok'] == true || resp['type'] == 'logout';
      }
      if (characteristicUuid == BleConstants.updateVersionCharUuid) {
        final payload = {
          'type': 'update.version',
          'data': { 'channel': json['channel'] },
        };
        final resp = await _rq!.send(payload);
        return resp['ok'] == true || resp['type'] == 'update.version';
      }
      _log('❌ 未知的映射特征：$characteristicUuid');
      return false;
    } catch (e) {
      _log('❌ writeEncryptedJson via queue 失败: $e');
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
      // 仅双特征通道：通过帧协议查询
      if (_rq == null) return null;
      // 快速查询以避免首跳等待过久：1.2s 超时，不重试
      final t0 = DateTime.now();
      final resp = await _rq!.send(
        { 'type': 'network.status' },
        timeout: const Duration(milliseconds: 1200),
        retries: 0,
      );
      _t('network.status.rq.done(${DateTime.now().difference(t0).inMilliseconds}ms)');
      final data = resp['data'];
      if (data is Map<String, dynamic>) {
        final ns = NetworkStatus.fromJson(data);
        // 同步网络状态；若正在配网，仅在连接成功时切到 wifi_online，避免过早判定离线
        state = state.copyWith(networkStatus: ns, networkStatusUpdatedAt: DateTime.now());
        if (state.provisionStatus == 'provisioning' && ns.connected) {
          state = state.copyWith(
            provisionStatus: 'wifi_online',
            lastProvisionDeviceId: state.deviceData?.deviceId ?? state.lastProvisionDeviceId,
          );
        }
        return ns;
      }
      return null;
    } catch (e) {
      _t('network.status.error(${e.runtimeType})');
      return null;
    }
  }

  void _kickoffPostProvisionPolling() {
    if (_postProvisionPoll != null) return;
    // 软轮询：在有限时间内重复读取网络状态，直到已连接或超时
    _postProvisionPoll = () async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      var delay = const Duration(milliseconds: 800);
      while (DateTime.now().isBefore(deadline)) {
        final ns = await _doReadNetworkStatus();
        if (ns?.connected == true) break;
        await Future.delayed(delay);
        // 增量退避但限制上限
        final nextMs = (delay.inMilliseconds * 1.5).toInt();
        delay = Duration(milliseconds: nextMs > 3000 ? 3000 : nextMs);
      }
      _postProvisionPoll = null;
    }();
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
    // print(msg);
    developer.log(msg, name: 'BLE');
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _timeoutTimer?.cancel();
    _rqEventsSub?.cancel();
    _rq?.dispose();
    _rq = null;
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
