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
  DeviceConnectionNotifier() : super(const DeviceConnectionState());

  StreamSubscription? _scanSubscription;
  Timer? _timeoutTimer;
  StreamSubscription<List<int>>? _provisionStatusSubscription;
  StreamSubscription<List<int>>? _wifiScanResultSubscription;
  StreamSubscription<List<int>>? _handshakeSubscription;

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
        _log('✅ 找到目标设备！准备连接');
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
      _log('BLE 连接成功，准备认证');
      await _initGattSession(result);
      await _startAuthentication(result);
    } else {
      _setError('连接失败');
    }
  }

  Future<void> _initGattSession(BleDeviceData deviceData) async {
    final deviceId = deviceData.bleAddress;

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

    await BleServiceSimple.writeCharacteristic(
      deviceId: deviceId,
      serviceUuid: BleConstants.serviceUuid,
      characteristicUuid: BleConstants.secureHandshakeCharUuid,
      data: handshakeInit.codeUnits,
      withResponse: true,
    );
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
    if (_cryptoService == null || !_cryptoService!.hasSecureSession) {
      print('❌ 未完成认证，不能发送WiFi凭证');
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
        if (!ok) return false;
        offset = end;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestWifiScan() async {
    if (state.deviceData == null) return false;
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
      }
      return ok;
    } catch (_) {
      return false;
    }
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
  final notifier = DeviceConnectionNotifier();
  ref.onDispose(() => notifier.dispose());
  return notifier;
});
