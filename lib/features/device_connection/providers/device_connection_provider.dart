import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../../core/constants/ble_constants.dart';
import '../../../core/crypto/crypto_service.dart';
import '../../../features/qr_scanner/models/device_qr_data.dart';
import '../../qr_scanner/utils/device_fingerprint.dart';
import '../models/ble_device_data.dart';
import '../models/network_status.dart';
import '../services/ble_service_simple.dart';
import '../../../core/providers/lifecycle_provider.dart';

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
  final List<WifiAp> wifiNetworks;
  final List<String> connectionLogs;
  final NetworkStatus? networkStatus;
  final bool isCheckingNetwork;

  const DeviceConnectionState({
    this.status = BleDeviceStatus.disconnected,
    this.deviceData,
    this.scanResults = const [],
    this.errorMessage,
    this.progress = 0.0,
    this.provisionStatus,
    this.wifiNetworks = const [],
    this.connectionLogs = const [],
    this.networkStatus,
    this.isCheckingNetwork = false,
  });

  DeviceConnectionState copyWith({
    BleDeviceStatus? status,
    BleDeviceData? deviceData,
    List<SimpleBLEScanResult>? scanResults,
    String? errorMessage,
    double? progress,
    String? provisionStatus,
    List<WifiAp>? wifiNetworks,
    List<String>? connectionLogs,
    NetworkStatus? networkStatus,
    bool? isCheckingNetwork,
  }) {
    return DeviceConnectionState(
      status: status ?? this.status,
      deviceData: deviceData ?? this.deviceData,
      scanResults: scanResults ?? this.scanResults,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
      provisionStatus: provisionStatus ?? this.provisionStatus,
      wifiNetworks: wifiNetworks ?? this.wifiNetworks,
      connectionLogs: connectionLogs ?? this.connectionLogs,
      networkStatus: networkStatus ?? this.networkStatus,
      isCheckingNetwork: isCheckingNetwork ?? this.isCheckingNetwork,
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

  /// 开始连接流程
  Future<void> startConnection(DeviceQrData qrData) async {
    state = const DeviceConnectionState();
    _log('初始化连接：${qrData.deviceName} (${qrData.deviceId})');

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

    _timeoutTimer = Timer(const Duration(seconds: 30), () {
      if (state.status == BleDeviceStatus.scanning) {
        _setError('扫描超时：未找到目标设备');
      }
    });

    _scanSubscription = BleServiceSimple.scanForDevice(
      targetDeviceId: deviceData.deviceId,
      timeout: const Duration(seconds: 30),
    ).listen((scanResult) {
      _log('发现设备: ${scanResult.name} (${scanResult.deviceId}), RSSI=${scanResult.rssi}');

      if (_isTargetDevice(scanResult, deviceData.deviceId)) {
        if (scanResult.rssi < BleConstants.rssiProximityThreshold) {
          _log('⚠️ 信号强度不足，等待靠近后再连接 (rssi=${scanResult.rssi})');
          return;
        }
        _log('✅ 找到目标设备且距离合适！准备连接');
        _timeoutTimer?.cancel();
        _scanSubscription?.cancel();

        final connectionAddress =
        Platform.isIOS ? scanResult.deviceId : scanResult.address;
        _connectToDevice(deviceData.copyWith(bleAddress: connectionAddress));
      }
    }, onError: (error) {
      _setError('扫描出错: $error');
    });
  }

  bool _isTargetDevice(SimpleBLEScanResult result, String targetDeviceId) {
    if (result.manufacturerData == null) return false;
    final expected = createDeviceFingerprint(targetDeviceId);
    final actual = result.manufacturerData!;
    return _containsSublist(actual, expected);
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

    // 订阅 A107
    _provisionStatusSubscription =
        BleServiceSimple.subscribeToCharacteristic(
          deviceId: deviceId,
          serviceUuid: BleConstants.serviceUuid,
          characteristicUuid: BleConstants.provisionStatusCharUuid,
        ).listen((data) {
          final status = utf8.decode(data);
          state = state.copyWith(provisionStatus: status);
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

  Future<void> _startAuthentication(BleDeviceData deviceData) async {
    state = state.copyWith(status: BleDeviceStatus.authenticating);
    _cryptoService = CryptoService();
    await _cryptoService!.generateEphemeralKeyPair();

    final deviceId = deviceData.bleAddress;

    final handshakeInit = await _cryptoService!.getHandshakeInitData();

    _handshakeAssembler = BleChunkAssembler(
      characteristic: 'A105',
      timeoutMs: 2000,
      onCompleted: (json) async {
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
        state = state.copyWith(status: BleDeviceStatus.authenticated);
        _log('🎉 认证完成');
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

  Future<void> retry() async {
    if (state.deviceData != null) {
      final qrData = DeviceQrData(
        deviceId: state.deviceData!.deviceId,
        deviceName: state.deviceData!.deviceName,
        bleAddress: state.deviceData!.bleAddress,
        publicKey: state.deviceData!.publicKey,
      );
      await startConnection(qrData);
    }
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
      final deviceId = state.deviceData!.bleAddress;
      final payload =
          '{"ssid":"${_escapeJson(ssid)}","password":"${_escapeJson(password)}"}';
      final utf8Data = utf8.encode(payload);

      final mtu = await BleServiceSimple.requestMtu(deviceId, 512);
      final chunkSize = (mtu) - 3;

      var offset = 0;
      while (offset < utf8Data.length) {
        final end = (offset + chunkSize < utf8Data.length)
            ? offset + chunkSize
            : utf8Data.length;
        final chunk = utf8Data.sublist(offset, end);

        final ok = await BleServiceSimple.writeCharacteristic(
          deviceId: deviceId,
          serviceUuid: BleConstants.serviceUuid,
          characteristicUuid: BleConstants.provisionRequestCharUuid,
          data: chunk,
          withResponse: true,
        );
        if (!ok) {
          _log('写入分包失败，触发断开以自愈');
          await BleServiceSimple.disconnect();
          _setError('连接失败');
          _nextRetryMs = (_nextRetryMs * 2).clamp(
              BleConstants.reconnectBackoffStartMs, BleConstants.reconnectBackoffMaxMs);
          return false;
        }
        offset = end;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestWifiScan() async {
    if (state.deviceData == null) return false;
    // 确保可信通道
    final okChannel = await ensureTrustedChannel();
    if (!okChannel) {
      _log('❌ 未建立可信通道，取消发送WiFi扫描请求');
      return false;
    }
    try {
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

  Future<NetworkStatus?> checkNetworkStatus() async {
    if (state.deviceData == null) return null;
    try {
      final data = await BleServiceSimple.readCharacteristic(
        deviceId: state.deviceData!.bleAddress,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.networkStatusCharUuid,
      );
      if (data != null && data.isNotEmpty) {
        final networkStatus = NetworkStatusParser.fromBleData(data);
        if (networkStatus != null) {
          state = state.copyWith(networkStatus: networkStatus);
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

  void _log(String msg) {
    final now = DateTime.now().toIso8601String();
    state = state.copyWith(
        connectionLogs: [...state.connectionLogs, "[$now] $msg"]);
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
