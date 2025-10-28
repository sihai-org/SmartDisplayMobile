import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:fluttertoast/fluttertoast.dart';
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

/// 设备连接状态数据
class DeviceConnectionState {
  final BleDeviceStatus status;
  final BleDeviceData? deviceData;
  final List<SimpleBLEScanResult> scanResults;
  final String? errorMessage;
  final double progress;
  final String? provisionStatus;
  final String? lastProvisionDeviceId;
  final String? lastProvisionSsid;
  final List<WifiAp> wifiNetworks;
  final List<String> connectionLogs;
  final NetworkStatus? networkStatus;
  final bool isCheckingNetwork;
  final DateTime? networkStatusUpdatedAt;
  final String? firmwareVersion;
  final String? lastHandshakeErrorCode;
  final String? lastHandshakeErrorMessage;
  // Update check UI state
  final bool isCheckingUpdate;

  const DeviceConnectionState({
    this.status = BleDeviceStatus.disconnected,
    this.deviceData,
    this.scanResults = const [],
    this.errorMessage,
    this.progress = 0.0,
    this.provisionStatus,
    this.lastProvisionDeviceId,
    this.lastProvisionSsid,
    this.wifiNetworks = const [],
    this.connectionLogs = const [],
    this.networkStatus,
    this.isCheckingNetwork = false,
    this.networkStatusUpdatedAt,
    this.firmwareVersion,
    this.lastHandshakeErrorCode,
    this.lastHandshakeErrorMessage,
    this.isCheckingUpdate = false,
  });

  DeviceConnectionState copyWith({
    BleDeviceStatus? status,
    BleDeviceData? deviceData,
    List<SimpleBLEScanResult>? scanResults,
    String? errorMessage,
    double? progress,
    String? provisionStatus,
    String? lastProvisionDeviceId,
    String? lastProvisionSsid,
    List<WifiAp>? wifiNetworks,
    List<String>? connectionLogs,
    NetworkStatus? networkStatus,
    bool? isCheckingNetwork,
    DateTime? networkStatusUpdatedAt,
    String? firmwareVersion,
    String? lastHandshakeErrorCode,
    String? lastHandshakeErrorMessage,
    bool? isCheckingUpdate,
  }) {
    return DeviceConnectionState(
      status: status ?? this.status,
      deviceData: deviceData ?? this.deviceData,
      scanResults: scanResults ?? this.scanResults,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
      provisionStatus: provisionStatus ?? this.provisionStatus,
      lastProvisionDeviceId: lastProvisionDeviceId ?? this.lastProvisionDeviceId,
      lastProvisionSsid: lastProvisionSsid ?? this.lastProvisionSsid,
      wifiNetworks: wifiNetworks ?? this.wifiNetworks,
      connectionLogs: connectionLogs ?? this.connectionLogs,
      networkStatus: networkStatus ?? this.networkStatus,
      isCheckingNetwork: isCheckingNetwork ?? this.isCheckingNetwork,
      networkStatusUpdatedAt: networkStatusUpdatedAt ?? this.networkStatusUpdatedAt,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      lastHandshakeErrorCode: lastHandshakeErrorCode ?? this.lastHandshakeErrorCode,
      lastHandshakeErrorMessage: lastHandshakeErrorMessage ?? this.lastHandshakeErrorMessage,
      isCheckingUpdate: isCheckingUpdate ?? this.isCheckingUpdate,
    );
  }
}

/// 设备连接管理器
class DeviceConnectionNotifier extends StateNotifier<DeviceConnectionState> {
  DeviceConnectionNotifier(this._ref) : super(const DeviceConnectionState()) {
    // 前后台切换：回到前台时尝试确保可信通道
    _foregroundSub = _ref.listen<bool>(isForegroundProvider, (prev, curr) {
      if (curr == true) _onEnterForeground();
    });

    // 监听 BLE 权限/就绪变化：若之前因“权限未就绪”报错，恢复后自动重启连接
    BleServiceSimple.permissionStream.listen((granted) {
      if (granted &&
          state.status == BleDeviceStatus.error &&
          (state.errorMessage?.contains('权限') ?? false)) {
        _log('✅ 检测到 BLE 就绪，自动重启连接');
        final d = state.deviceData;
        if (d != null) {
          startConnection(DeviceQrData(
            deviceId: d.deviceId,
            deviceName: d.deviceName,
            bleAddress: d.bleAddress,
            publicKey: d.publicKey,
          ));
        }
      }
    });
  }

  final Ref _ref;

  StreamSubscription? _scanSubscription;
  Timer? _timeoutTimer;
  ProviderSubscription<bool>? _foregroundSub;
  ReliableRequestQueue? _rq; // dual-char reliable queue
  StreamSubscription<Map<String, dynamic>>? _rqEventsSub; // 设备侧推送

  // Backoff
  int _nextRetryMs = BleConstants.reconnectBackoffStartMs;
  DateTime? _lastAttemptAt;

  CryptoService? _cryptoService;

  bool _syncedAfterLogin = false;

  // Network status read de-dup & throttle
  DateTime? _lastNetworkStatusReadAt;
  Future<NetworkStatus?>? _inflightNetworkStatusRead;

  // 打点
  DateTime? _sessionStart;
  DateTime? _connectStart;

  // 配网后轮询
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
    // Reset per-session caches to avoid stale data from previous device
    _lastNetworkStatusReadAt = null;
    _inflightNetworkStatusRead = null;
    _postProvisionPoll = null;
    try {
      await _rqEventsSub?.cancel();
    } catch (_) {}
    _rqEventsSub = null;

    // ✅ 固定硬断开 + 稳定等待
    try {
      await BleServiceSimple.disconnect();
      await Future.delayed(BleConstants.kDisconnectStabilize);
    } catch (_) {}

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

    final ready = await BleServiceSimple.ensureBleReady();
    if (!ready) {
      _setError('蓝牙权限未授予或蓝牙未开启');
      return;
    }

    _log('权限与就绪通过，开始扫描目标设备');
    await _scanForDevice(deviceData);
  }

  Future<void> _onEnterForeground() async {
    if (state.status == BleDeviceStatus.authenticated) return;
    final d = state.deviceData;
    if (d != null) await _ensureTrustedChannel(d);
  }

  Future<void> _ensureTrustedChannel(BleDeviceData deviceData) async {
    // ✅ 固定硬断开 + 稳定等待
    try {
      await BleServiceSimple.disconnect();
      await Future.delayed(BleConstants.kDisconnectStabilize);
    } catch (_) {}

    final now = DateTime.now();
    if (_lastAttemptAt != null &&
        now.difference(_lastAttemptAt!).inMilliseconds < _nextRetryMs) {
      return;
    }
    _lastAttemptAt = now;

    final ready = await BleServiceSimple.ensureBleReady();
    if (!ready) {
      _log('蓝牙未就绪，跳过');
      return;
    }

    await _scanForDevice(deviceData);
  }

  /// 对外：确保可信通道
  Future<bool> ensureTrustedChannel() async {
    final d = state.deviceData;
    if (d == null) return false;
    if (_rq != null) return true;
    if (state.status == BleDeviceStatus.authenticated) return true;
    await _ensureTrustedChannel(d);
    return state.status == BleDeviceStatus.authenticated;
  }

  Future<void> _scanForDevice(BleDeviceData deviceData) async {
    // ✅ 任何新一次扫描前，先停掉底层扫描，确保冷启动
    try {
      await BleServiceSimple.stopScan();
    } catch (_) {}

    state = state.copyWith(status: BleDeviceStatus.scanning, progress: 0.3);
    _t('scan.start');
    _log('开始扫描目标设备，最长 30s...');
    _targetFirstSeenAt = null;
    _lastWeakSignalNoteAt = null;

    _timeoutTimer = Timer(const Duration(seconds: 30), () async {
      if (state.status == BleDeviceStatus.scanning) {
        // 🔧 新增：确保底层扫描也停掉
        try {
          await BleServiceSimple.stopScan();
        } catch (_) {}
        _setError('扫描超时：未找到目标设备');
      }
    });

    _scanSubscription = BleServiceSimple.scanForDevice(
      // targetDeviceId: deviceData.deviceId,
      timeout: const Duration(seconds: 30),
    ).listen((scanResult) async {
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

        // 超过宽限期后，放宽RSSI限制
        const grace = Duration(seconds: 2);
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

        _maybePrintWeakSignal(scanResult.rssi);
      }
    }, onError: (error) {
      _setError('扫描出错: $error');
    });
  }

  // 扫描日志节流
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
      print('发现设备: ${scanResult.name} (${scanResult.deviceId}), RSSI=${scanResult.rssi}');
    }
  }

  void _maybePrintWeakSignal(int rssi) {
    final now = DateTime.now();
    if (_lastWeakSignalNoteAt == null || now.difference(_lastWeakSignalNoteAt!) >= _weakNoteInterval) {
      _lastWeakSignalNoteAt = now;
      print('⚠️ 信号强度不足，等待靠近后再连接 (rssi=$rssi)');
    }
  }

  bool _isTargetDevice(SimpleBLEScanResult result, String targetDeviceId) {
    if (result.manufacturerData != null) {
      final expected = createDeviceFingerprint(targetDeviceId);
      final actual = result.manufacturerData!;
      if (_containsSublist(actual, expected)) return true;
    }
    final d = state.deviceData;
    if (d != null && result.name == d.deviceName) return true;
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
            BleConstants.reconnectBackoffStartMs,
            BleConstants.reconnectBackoffMaxMs);
        return;
      }

      // Prefer dual-char RX/TX if available
      final hasDual = await BleServiceSimple.hasRxTx(
        deviceId: result.bleAddress,
        serviceUuid: BleConstants.serviceUuid,
        rxUuid: BleConstants.rxCharUuid,
        txUuid: BleConstants.txCharUuid,
      );

      if (!hasDual) {
        _log('❌ 设备不支持双特征通道 (RX/TX)，取消');
        await BleServiceSimple.disconnect();
        _setError('连接失败');
        _nextRetryMs = (_nextRetryMs * 2).clamp(
            BleConstants.reconnectBackoffStartMs,
            BleConstants.reconnectBackoffMaxMs);
        return;
      }

      // 准备可靠请求通道
      try {
        await _rq?.dispose();
      } catch (_) {}
      _rq = ReliableRequestQueue(deviceId: result.bleAddress);
      final ts = DateTime.now();
      await _rq!.prepare();
      _t('dualtx.ready(+${DateTime.now().difference(ts).inMilliseconds}ms prepare)');
      _log('✅ Dual-char RX/TX 可用，准备应用层握手');

      // 应用层握手
      state =
          state.copyWith(status: BleDeviceStatus.authenticating, progress: 0.9);
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

      final initObj = jsonDecode(handshakeInit) as Map<String, dynamic>;
      _t('handshake.start');
      final resp = await _rq!.send(
        initObj,
        timeout: const Duration(seconds: 8),
        retries: 1,
        isFinal: (msg) => (msg['type']?.toString() == 'handshake_response'),
      );

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
        state = state.copyWith(
            status: BleDeviceStatus.authenticated, progress: 1.0);
        _t('handshake.done');
        _log('🎉 应用层握手完成');

        // 安装加解密处理器
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

        // 订阅设备端事件
        try {
          await _rqEventsSub?.cancel();
          _rqEventsSub = _rq!.events.listen((evt) async {
            final type = (evt['type'] ?? '').toString();
            if (type == 'status') {
              final s = (evt['status'] ?? '').toString();
              _log('📣 收到设备事件: status=$s');
              if (s == 'authenticated') {
                state = state.copyWith(status: BleDeviceStatus.authenticated);
              } else if (s == 'wifi_online') {
                await _doReadNetworkStatus();
                _kickoffPostProvisionPolling();
              } else if (s == 'update_updating') {
                // Device started updating
                state = state.copyWith(
                  isCheckingUpdate: false,
                );
                // 立即提示用户
                try {
                  Fluttertoast.showToast(msg: '检测到新版本，正在更新...');
                } catch (_) {}
              } else if (s == 'update_latest') {
                // Device is already up to date
                state = state.copyWith(
                  isCheckingUpdate: false,
                );
                // 立即提示用户
                try {
                  Fluttertoast.showToast(msg: '已是最新版本，无需更新');
                } catch (_) {}
              }
            } else if (type == 'wifi.result') {
              final ok = evt['ok'] == true;
              final data = evt['data'];
              final err = evt['error'];
              String? status = (data is Map<String, dynamic>)
                  ? (data['status']?.toString())
                  : null;
              if (ok && status == 'connected') {
                _log('📣 wifi.result: connected');
                state = state.copyWith(
                  provisionStatus: 'wifi_online',
                  lastProvisionDeviceId:
                      state.deviceData?.deviceId ?? state.lastProvisionDeviceId,
                );
                await _doReadNetworkStatus();
                _kickoffPostProvisionPolling();
              } else {
                final code = (err is Map<String, dynamic>)
                    ? (err['code']?.toString())
                    : null;
                final message = (err is Map<String, dynamic>)
                    ? (err['message']?.toString())
                    : null;
                _log('📣 wifi.result: failed code=$code message=$message');
                state = state.copyWith(
                  provisionStatus: 'wifi_offline',
                  lastProvisionDeviceId:
                      state.deviceData?.deviceId ?? state.lastProvisionDeviceId,
                );
                await _doReadNetworkStatus();
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
            BleConstants.reconnectBackoffStartMs,
            BleConstants.reconnectBackoffMaxMs);
        return;
      }

      _nextRetryMs = BleConstants.reconnectBackoffStartMs; // 成功重置退避
    } else {
      _setError('连接失败');
      _nextRetryMs = (_nextRetryMs * 2).clamp(
          BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
    }
  }

  // =============== 对外方法：为项目中其他页面调用保留 ===============

  /// 断开 BLE、清理会话与加密器，并重置为 disconnected
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

  /// 清空内部状态（不主动断开已连接的底层；用于 UI 重置）
  void reset() {
    _timeoutTimer?.cancel();
    _scanSubscription?.cancel();
    try {
      _rqEventsSub?.cancel();
    } catch (_) {}
    _rqEventsSub = null;
    try {
      _rq?.dispose();
    } catch (_) {}
    _rq = null;
    try {
      _cryptoService?.cleanup();
    } catch (_) {}
    _cryptoService = null;

    // Clear per-session caches/state
    _lastNetworkStatusReadAt = null;
    _inflightNetworkStatusRead = null;
    _postProvisionPoll = null;
    _syncedAfterLogin = false;
    _sessionStart = null;
    _connectStart = null;
    state = const DeviceConnectionState();
  }

  /// 暴露当前登录用户ID（无则空串）
  String currentUserId() {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      return user?.id ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 以“加密 JSON 指令”形式写入（映射你项目中的特征/命令）
  Future<bool> writeEncryptedJson({
    required String characteristicUuid,
    required Map<String, dynamic> json,
  }) async {
    if (state.deviceData == null) return false;
    try {
      // 这里统一通过可靠队列发送业务指令，不再直接写 GATT
      // 映射已有特征常量到队列命令
      if (characteristicUuid == BleConstants.loginAuthCodeCharUuid) {
        final payload = {
          'type': 'login.auth',
          'data': {
            'email': json['email'] ?? '',
            'otpToken': json['otpToken'] ?? json['code'] ?? '',
          },
        };
        final resp = await _rq!.send(
          payload,
          timeout: const Duration(seconds: 25),
          retries: 0,
          isFinal: (msg) {
            final type = (msg['type'] ?? '').toString();
            final data = msg['data'];
            final status = data is Map<String, dynamic>
                ? (data['status'] ?? '').toString()
                : (msg['status'] ?? '').toString();
            return type == 'login.result' ||
                status == 'login_success' ||
                status == 'login_failed';
          },
        );

        try {
          final data = resp['data'];
          final status = data is Map<String, dynamic>
              ? (data['status'] ?? '').toString()
              : (resp['status'] ?? '').toString();
          if (status == 'login_success') {
            state = state.copyWith(
              provisionStatus: 'login_success',
              lastProvisionDeviceId: state.deviceData?.deviceId,
            );
            if (!_syncedAfterLogin) {
              _syncedAfterLogin = true;
              try {
                await _ref.read(savedDevicesProvider.notifier).syncFromServer();
                final id = state.deviceData?.deviceId;
                if (id != null && id.isNotEmpty) {
                  await _ref.read(savedDevicesProvider.notifier).select(id);
                }
              } catch (_) {}
            }
            return true;
          }
          if (status == 'login_failed') {
            _setError('设备登录失败');
            return false;
          }
        } catch (_) {}
        return resp['ok'] == true || resp['type'] == 'login.result';
      }

      if (characteristicUuid == BleConstants.logoutCharUuid) {
        final payload = {
          'type': 'logout',
          'data': {'userId': json['userId'] ?? currentUserId()},
        };
        final resp = await _rq!.send(payload);
        return resp['ok'] == true || resp['type'] == 'logout';
      }

      // 注意：检查更新已统一到 requestUpdateCheck()，不再通过 writeEncryptedJson 走分支

      _log('❌ 未知的映射特征：$characteristicUuid');
      return false;
    } catch (e) {
      _log('❌ writeEncryptedJson via queue 失败: $e');
      return false;
    }
  }

  /// 智能处理 Wi-Fi：若离线则触发一次 wifi.scan
  Future<void> handleWifiSmartly() async {
    final ns = await checkNetworkStatus();
    if (ns == null || !ns.connected) {
      await requestWifiScan();
    }
  }

  /// 发送 Wi-Fi 配网请求（兼容旧调用）
  Future<bool> sendWifiCredentials(String ssid, String password) async {
    return await sendProvisionRequest(ssid: ssid, password: password);
  }

  Future<bool> sendProvisionRequest({
    required String ssid,
    required String password,
  }) async {
    if (state.deviceData == null) return false;
    try {
      final currId = state.deviceData!.deviceId;
      state = state.copyWith(
        provisionStatus: 'provisioning',
        lastProvisionDeviceId: currId,
        lastProvisionSsid: ssid,
      );
      final resp = await _rq!.send({
        'type': 'wifi.config',
        'data': {'ssid': ssid, 'password': password}
      });
      final ok = resp['ok'] == true;
      if (!ok) state = state.copyWith(provisionStatus: 'failed');
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
        'data': {'email': '', 'otpToken': code},
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
        'data': {'userId': currentUserId()},
      });
      return resp['ok'] == true || resp['type'] == 'logout';
    } catch (e) {
      _log('❌ logout 失败: $e');
      return false;
    }
  }

  Future<bool> requestWifiScan() async {
    if (state.deviceData == null) return false;
    try {
      var okChannel = await ensureTrustedChannel();
      if (!okChannel || _rq == null) {
        await _waitForAuthenticated(const Duration(seconds: 6));
        okChannel = _rq != null || state.status == BleDeviceStatus.authenticated;
        if (!okChannel || _rq == null) {
          _log('❌ wifi.scan 取消：通道未就绪');
          return false;
        }
      }
      _log('⏳ 开始扫描附近Wi-Fi...');
      final resp = await _rq!.send(
        {'type': 'wifi.scan'},
        timeout: const Duration(seconds: 3),
        retries: 0,
      );
      final data = resp['data'];
      if (data is List) {
        final networks = data
            .map((e) => WifiAp(
                  ssid: (e['ssid'] ?? '').toString(),
                  rssi: int.tryParse((e['rssi'] ?? '0').toString()) ?? 0,
                  secure: (e['secure'] == true),
          bssid: e['bssid']?.toString(),
          frequency: int.tryParse((e['frequency'] ?? '').toString()),
                ))
            .toList();
        state = state.copyWith(wifiNetworks: networks);
        _log('📶 Wi-Fi 扫描完成，发现 ${networks.length} 个网络');
      }
      return true;
    } catch (e) {
      _log('❌ wifi.scan 失败: $e');
      return false;
    }
  }

  /// 检查设备固件更新（参考 requestWifiScan 的通道确保逻辑）
  Future<bool> requestUpdateCheck({String? channel}) async {
    if (state.deviceData == null) return false;
    try {
      // 1) 立即进入“检查更新中”以显示 loading（包含后续连接/握手时间）
      state =
          state.copyWith(isCheckingUpdate: true);

      // 2) 确保建立可信加密通道（必须等待到 authenticated，而不是仅 _rq 可用）
      var okChannel = await ensureTrustedChannel();
      if (!okChannel ||
          _rq == null ||
          state.status != BleDeviceStatus.authenticated) {
        await _waitForAuthenticated(const Duration(seconds: 10));
        okChannel =
            (state.status == BleDeviceStatus.authenticated) && _rq != null;
        if (!okChannel) {
          _log('❌ update.version 取消：通道未就绪');
          state = state.copyWith(isCheckingUpdate: false);
          return false;
        }
      }

      // 3) 发送检查更新指令；设备将通过事件推送 update_updating / update_latest 来结束 loading
      final resp = await _rq!.send({
        'type': 'update.version',
        'data': {'channel': channel},
      });
      final ok = resp['ok'] == true || resp['type'] == 'update.version';
      if (!ok) {
        // 若请求未被设备接受，及时结束 loading
        state = state.copyWith(isCheckingUpdate: false);
      }
      return ok;
    } catch (e) {
      _log('❌ update.version 失败: $e');
      // 异常时及时结束 loading
      state = state.copyWith(isCheckingUpdate: false);
      return false;
    }
  }

  Future<void> _waitForAuthenticated(Duration timeout) async {
    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      // 仅在完成应用层握手（加密通道可用）时返回
      if (state.status == BleDeviceStatus.authenticated && _rq != null) return;
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

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

  Future<NetworkStatus?> checkNetworkStatus() async {
    if (state.deviceData == null) return null;
    final now = DateTime.now();
    if (_lastNetworkStatusReadAt != null &&
        now.difference(_lastNetworkStatusReadAt!) < const Duration(milliseconds: 400)) {
      return state.networkStatus;
    }
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
      if (_rq == null) return null;
      final t0 = DateTime.now();
      final resp = await _rq!.send(
        {'type': 'network.status'},
        timeout: const Duration(milliseconds: 1200),
        retries: 0,
      );
      _t('network.status.rq.done(${DateTime.now().difference(t0).inMilliseconds}ms)');
      final data = resp['data'];
      if (data is Map<String, dynamic>) {
        final ns = NetworkStatus.fromJson(data);
        state = state.copyWith(networkStatus: ns, networkStatusUpdatedAt: DateTime.now());
        if (state.provisionStatus == 'provisioning' && ns.connected) {
          final reqSsid = state.lastProvisionSsid?.trim();
          final currSsid = ns.displaySsid?.trim() ?? ns.ssid?.trim();
          final ssidMatches = reqSsid != null && reqSsid.isNotEmpty &&
              currSsid != null && currSsid.isNotEmpty &&
              currSsid == reqSsid;
          if (ssidMatches) {
            state = state.copyWith(
              provisionStatus: 'wifi_online',
              lastProvisionDeviceId: state.deviceData?.deviceId ?? state.lastProvisionDeviceId,
            );
          }
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
    _postProvisionPoll = () async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      var delay = const Duration(milliseconds: 800);
      while (DateTime.now().isBefore(deadline)) {
        final ns = await _doReadNetworkStatus();
        if (ns?.connected == true) break;
        await Future.delayed(delay);
        final nextMs = (delay.inMilliseconds * 1.5).toInt();
        delay = Duration(milliseconds: nextMs > 3000 ? 3000 : nextMs);
      }
      if (state.provisionStatus == 'provisioning') {
        state = state.copyWith(
          provisionStatus: 'wifi_offline',
          lastProvisionDeviceId: state.deviceData?.deviceId ?? state.lastProvisionDeviceId,
        );
      }
      _postProvisionPoll = null;
    }();
  }

  // 杂项
  String _escapeJson(String s) => s
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');

  void _setError(String message) {
    state = state.copyWith(status: BleDeviceStatus.error, errorMessage: message);
  }

  static const int _maxConnectionLogs = 200;
  void _log(String msg) {
    final now = DateTime.now().toIso8601String();
    final nextLogs = [...state.connectionLogs, "[$now] $msg"];
    final trimmedLogs = nextLogs.length > _maxConnectionLogs
        ? nextLogs.sublist(nextLogs.length - _maxConnectionLogs)
        : nextLogs;
    state = state.copyWith(connectionLogs: trimmedLogs);
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
