import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/ble_constants.dart';
import 'ble_device_data.dart';

/// 简化的BLE服务类，用于基本的蓝牙操作（已合并权限与就绪逻辑）
class BleServiceSimple {
  static final FlutterReactiveBle _ble = FlutterReactiveBle();

  static StreamSubscription<DiscoveredDevice>? _scanSubscription;
  static StreamSubscription<ConnectionStateUpdate>? _deviceConnectionSubscription;

  static bool _isScanning = false;
  static StreamController<SimpleBLEScanResult>? _scanController;

  // 设备去重映射表 - 按设备ID去重
  static final Map<String, SimpleBLEScanResult> _discoveredDevices = {};

  // 每个设备的最近一次打印时间与RSSI，用于节流日志
  static final Map<String, DateTime> _lastLogAt = {};
  static final Map<String, int> _lastLogRssi = {};
  static const Duration _perDeviceLogInterval = Duration(seconds: 3);

  // Track negotiated MTU per device for framing without re-requesting MTU each time
  static final Map<String, int> _mtuByDevice = {};

  // 打点：统一会话起点
  static DateTime? _sessionStart;

  static void _log(String msg) {
    developer.log(msg, name: 'BLE_SIMPLE');
  }

  static void _logWithTime(String label) {
    final now = DateTime.now();
    if (_sessionStart != null) {
      final ms = now.difference(_sessionStart!).inMilliseconds;
      _log('⏱ [$ms ms] $label');
    } else {
      _log('⏱ $label');
    }
  }

  // 权限就绪广播（供上层监听）
  static final _permissionStreamController = StreamController<bool>.broadcast();
  static Stream<bool> get permissionStream => _permissionStreamController.stream;

  // ✅ 统一的“刚就绪”时间戳 & 老安卓定位门槛缓存
  static bool _legacyNeedsLocation = false; // Android < 12 是否需要定位服务开关

  /// 申请更大的 MTU
  static Future<int> requestMtu(String deviceId, int mtu) async {
    final t0 = DateTime.now();
    _log('📏 requestMtu 开始: target=$mtu, device=$deviceId');
    try {
      final negotiatedMtu = await _ble.requestMtu(deviceId: deviceId, mtu: mtu);
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('requestMtu.done(${elapsed}ms) -> $negotiatedMtu');
      if (negotiatedMtu > 0) {
        _mtuByDevice[deviceId] = negotiatedMtu;
      }
      return negotiatedMtu;
    } catch (e) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('requestMtu.fail(${elapsed}ms): $e');
      return 23; // 默认最小MTU
    }
  }

  static int getNegotiatedMtu(String deviceId) {
    return _mtuByDevice[deviceId] ?? BleConstants.minMtu;
  }

  /// 查询 BLE 当前状态（忽略 unknown）
  static Future<BleStatus> checkBleStatus() async {
    final t0 = DateTime.now();
    _log('🔎 checkBleStatus 开始');
    try {
      final status = await _ble.statusStream
          .firstWhere((s) => s != BleStatus.unknown,
              orElse: () => BleStatus.unknown)
          .timeout(const Duration(seconds: 5));
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('checkBleStatus.done(${elapsed}ms) -> $status');
      return status;
    } catch (_) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('checkBleStatus.error(${elapsed}ms)');
      return BleStatus.unknown;
    }
  }

  static Future<bool> ensureBleReady() async {
    final t0 = DateTime.now();
    _sessionStart ??= t0;
    _log('🚦 ensureBleReady 开始');
    try {
      final status = await checkBleStatus();
      if (status == BleStatus.unsupported || status == BleStatus.poweredOff)
        return false;

      if (Platform.isAndroid) {
        final reqs = <Permission>[];
        if (!await Permission.bluetoothScan.isGranted)
          reqs.add(Permission.bluetoothScan);
        if (!await Permission.bluetoothConnect.isGranted)
          reqs.add(Permission.bluetoothConnect);
        // 仅在老安卓需要定位权限：
        _legacyNeedsLocation = await _legacyNeedsLocationGate();
        if (_legacyNeedsLocation &&
            !await Permission.locationWhenInUse.isGranted) {
          reqs.add(Permission.locationWhenInUse);
        }
        if (reqs.isNotEmpty) {
          final p0 = DateTime.now();
          final rs = await reqs.request();
          final pElapsed = DateTime.now().difference(p0).inMilliseconds;
          _logWithTime('permissions.request.done(${pElapsed}ms)');
          if (rs.values.any((s) => !s.isGranted)) {
            _permissionStreamController.add(false);
            return false;
          }
          if (_legacyNeedsLocation) {
            final s0 = DateTime.now();
            final service = await Permission.locationWhenInUse.serviceStatus;
            final sElapsed = DateTime.now().difference(s0).inMilliseconds;
            _logWithTime('permissions.locationService.checked(${sElapsed}ms) -> $service');
            if (service != ServiceStatus.enabled) {
              _permissionStreamController.add(false);
              return false;
            }
          }
        }
      }

      // 单次等 Ready（2s），失败再兜底等 2s
      Future<BleStatus> waitReady(Duration t) => _ble.statusStream
          .timeout(t, onTimeout: (sink) {})
          .firstWhere((s) => s == BleStatus.ready,
              orElse: () => BleStatus.unknown);

      final w0 = DateTime.now();
      var s = await waitReady(const Duration(seconds: 2));
      if (s != BleStatus.ready) s = await waitReady(const Duration(seconds: 2));
      final wElapsed = DateTime.now().difference(w0).inMilliseconds;
      _logWithTime('status.waitReady.done(${wElapsed}ms) -> $s');

      final ok = (s == BleStatus.ready);
      _permissionStreamController.add(ok);
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('ensureBleReady.result(${elapsed}ms) -> $ok');
      return ok;
    } catch (_) {
      _permissionStreamController.add(false);
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('ensureBleReady.error(${elapsed}ms)');
      return false;
    }
  }

  // 老安卓门槛判断：用“是否具备 bluetoothScan 权限常量”近似判断系统代际。
  static Future<bool> _legacyNeedsLocationGate() async {
    if (!Platform.isAndroid) return false;
    try {
      final hasScan = await Permission.bluetoothScan.isGranted;
      return !hasScan; // 没有 scan 权限 → 旧系统 → 需要定位服务开关
    } catch (_) {
      return true; // 保守处理
    }
  }

  static Stream<SimpleBLEScanResult> scanForDevice({
    // required String targetDeviceId,
    required Duration timeout,
  }) {
    _scanController?.close();
    _scanController = StreamController<SimpleBLEScanResult>.broadcast();
    _sessionStart ??= DateTime.now();
    _startScanningProcess(timeout);
    return _scanController!.stream;
  }

  static void _startScanningProcess(Duration timeout) async {
    final t0 = DateTime.now();
    _log('🔎 开始扫描, timeout=${timeout.inSeconds}s');
    try {
      await stopScan(); // 确保冷启动
      _discoveredDevices.clear();
      _isScanning = true;

      var firstFound = false;
      _scanSubscription = _ble.scanForDevices(
        withServices: [],
        scanMode: ScanMode.lowLatency,
        requireLocationServicesEnabled: _legacyNeedsLocation, // Android<12 仍保留
      ).listen((device) {
        if (!_isScanning) return;
        final result = SimpleBLEScanResult.fromDiscoveredDevice(device);
        _discoveredDevices[result.deviceId] = result;
        _scanController?.add(result);
        if (!firstFound) {
          firstFound = true;
          final elapsed = DateTime.now().difference(t0).inMilliseconds;
          _logWithTime('scan.firstResult(${elapsed}ms): id=${result.deviceId}, rssi=${result.rssi}');
        }
        _throttledLog(result); // 你的节流日志函数保留即可
      }, onError: (e) {
        _scanController?.addError(e); // ❌ 不做重扫预算
        _isScanning = false;
        _scanController?.close();
        final elapsed = DateTime.now().difference(t0).inMilliseconds;
        _logWithTime('scan.error(${elapsed}ms): $e');
      }, onDone: () {
        _isScanning = false;
        _scanController?.close();
        final elapsed = DateTime.now().difference(t0).inMilliseconds;
        _logWithTime('scan.done(${elapsed}ms)');
      });

      // 超时停止（单次）
      Timer(timeout, () async {
        if (_isScanning) await stopScan();
      });
    } catch (e) {
      _isScanning = false;
      _scanController?.addError(e);
      _scanController?.close();
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('scan.exception(${elapsed}ms): $e');
    }
  }

  static Future<void> stopScan() async {
    final t0 = DateTime.now();
    _log('⏹️ stopScan 开始');
    if (!_isScanning && _scanSubscription == null) return;
    _isScanning = false;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (_scanController != null && !_scanController!.isClosed) {
      await _scanController?.close();
    }
    _scanController = null;
    final elapsed = DateTime.now().difference(t0).inMilliseconds;
    _logWithTime('stopScan.done(${elapsed}ms)');
  }

  // 放在 BleServiceSimple 类内部的任意位置（比如 stopScan() 下面）
  static void _throttledLog(SimpleBLEScanResult r) {
    final now = DateTime.now();
    final lastAt = _lastLogAt[r.deviceId];
    final lastRssi = _lastLogRssi[r.deviceId];

    final rssiChanged = lastRssi == null || (r.rssi - lastRssi).abs() >= 5;
    final timeOk =
        lastAt == null || now.difference(lastAt) >= _perDeviceLogInterval;

    if (timeOk || rssiChanged) {
      _lastLogAt[r.deviceId] = now;
      _lastLogRssi[r.deviceId] = r.rssi;

      // 这里按需打印你想看的字段
      print('🔍 发现设备: ${r.name}');
      print('  id=${r.deviceId}, rssi=${r.rssi}');
      print('  serviceUuids=${r.serviceUuids}');
      print('  manufacturerData=${r.manufacturerData}');
    }
  }

  /// 连接设备
  static Future<BleDeviceData?> connectToDevice({
    required BleDeviceData bleDeviceData,
    required Duration timeout,
  }) async {
    final t0 = DateTime.now();
    _sessionStart ??= t0;
    _log('🔗 connectToDevice 开始: id=${bleDeviceData.bleDeviceId}, timeout=${timeout.inSeconds}s');
    try {
      await stopScan();

      final connectionStream = _ble.connectToDevice(
        id: bleDeviceData.bleDeviceId,
        connectionTimeout: timeout,
      );

      final completer = Completer<BleDeviceData?>();

      // ▼ 可取消的超时定时器 & 完成函数
      late final Timer timer;
      void completeOnce(BleDeviceData? v) {
        if (!completer.isCompleted) {
          timer.cancel(); // 1) 先取消超时
          completer.complete(v); // 2) 再完成
        }
      }
      // ▲

      await _deviceConnectionSubscription?.cancel();
      _deviceConnectionSubscription = connectionStream.listen((update) async {
        // Minimal connection state logging to aid field debugging
        // ignore: avoid_print
        _log('connection.update state=${update.connectionState} device=${update.deviceId} failure=${update.failure}');
        switch (update.connectionState) {
          case DeviceConnectionState.connected:
            final connectedAtMs = DateTime.now().difference(t0).inMilliseconds;
            _logWithTime('connect.connected(${connectedAtMs}ms), stabilize=${BleConstants.kStabilizeAfterConnect.inMilliseconds}ms');
            await Future.delayed(BleConstants.kStabilizeAfterConnect);
            completeOnce(bleDeviceData.copyWith(
              status: BleDeviceStatus.connected,
              connectedAt: DateTime.now(),
            ));
            break;
          case DeviceConnectionState.disconnected:
            final elapsed = DateTime.now().difference(t0).inMilliseconds;
            _logWithTime('connect.disconnected(${elapsed}ms)');
            completeOnce(null);
            break;
          default:
            break;
        }
      }, onError: (_) {
        // ignore: avoid_print
        final elapsed = DateTime.now().difference(t0).inMilliseconds;
        _logWithTime('connect.stream.error(${elapsed}ms)');
        completeOnce(null);
      });

      // ▼ 超时兜底（会在 completeOnce 里被 cancel）
      timer = Timer(timeout, () => completeOnce(null));
      // ▲

      final res = await completer.future;
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('connect.complete(${elapsed}ms) -> ${res != null}');
      // 保持连接订阅存活，直至显式调用 disconnect()
      return res;
    } catch (_) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('connect.exception(${elapsed}ms)');
      return null;
    }
  }

  /// 断开连接
  static Future<void> disconnect() async {
    final t0 = DateTime.now();
    _log('🔌 disconnect 开始');
    await stopScan();
    await _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = null;

    // ✅ 仅保留这一处固定等待
    await Future.delayed(BleConstants.kDisconnectStabilize);

    // 清状态（避免下一轮粘连）
    _discoveredDevices.clear();
    _lastLogAt.clear();
    _lastLogRssi.clear();
    final elapsed = DateTime.now().difference(t0).inMilliseconds;
    _logWithTime('disconnect.done(${elapsed}ms)');
  }

  /// 读特征
  static Future<List<int>?> readCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    final t0 = DateTime.now();
    _log('📖 readCharacteristic 开始: service=$serviceUuid, char=$characteristicUuid');
    try {
      final q = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(characteristicUuid),
      );
      final data = await _ble.readCharacteristic(q);
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('readCharacteristic.done(${elapsed}ms), len=${data.length}');
      return data;
    } catch (e) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('readCharacteristic.fail(${elapsed}ms): $e');
      return null;
    }
  }

  /// 主动触发服务发现，确保 GATT 就绪（尤其 Android）
  static Future<bool> discoverServices(String deviceId) async {
    final t0 = DateTime.now();
    _log('🧭 discoverServices 开始: device=$deviceId');
    try {
      final services = await _ble.discoverServices(deviceId);
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('discoverServices.done(${elapsed}ms), count=${services.length}');
      return services.isNotEmpty;
    } catch (e) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('discoverServices.fail(${elapsed}ms): $e');
      return false;
    }
  }

  /// 检查是否存在指定的 Service/Characteristic
  static Future<bool> hasCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    final t0 = DateTime.now();
    _log('🔎 hasCharacteristic 开始: svc=$serviceUuid, char=$characteristicUuid');
    try {
      final services = await _ble.discoverServices(deviceId);
      _log('hasCharacteristic.services=${services.length}');
      final targetService = services.firstWhere(
        (s) =>
            s.serviceId.toString().toLowerCase() == serviceUuid.toLowerCase(),
        orElse: () => DiscoveredService(
          serviceId: Uuid.parse('00000000-0000-0000-0000-000000000000'),
          serviceInstanceId: '',
          characteristicIds: const [],
          characteristics: const [],
          includedServices: const [],
        ),
      );
      if (targetService.characteristicIds.isEmpty) {
        final elapsed = DateTime.now().difference(t0).inMilliseconds;
        _logWithTime('hasCharacteristic.noService(${elapsed}ms)');
        return false;
      }
      final found = targetService.characteristicIds
          .any((c) => c.toString().toLowerCase() == characteristicUuid.toLowerCase());
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('hasCharacteristic.result(${elapsed}ms) -> $found');
      return found;
    } catch (e) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('hasCharacteristic.fail(${elapsed}ms): $e');
      return false;
    }
  }

  /// 确保 GATT 就绪：稳定延时 -> 服务发现 -> MTU 协商 -> 再次稳定
  static Future<bool> ensureGattReady(String deviceId) async {
    final t0 = DateTime.now();
    _log('🛠 ensureGattReady 开始: device=$deviceId');
    // Allow connection to fully settle before first discovery
    await Future.delayed(BleConstants.kStabilizeBeforeDiscover);
    _logWithTime('ensureGattReady.stabilize1(${BleConstants.kStabilizeBeforeDiscover.inMilliseconds}ms)');

    // Retry service discovery once to mitigate transient 133/135
    final d0 = DateTime.now();
    bool ok = await discoverServices(deviceId);
    _logWithTime('ensureGattReady.discover.attempt1(${DateTime.now().difference(d0).inMilliseconds}ms) -> $ok');
    if (!ok) {
      await Future.delayed(const Duration(milliseconds: 600));
      final d1 = DateTime.now();
      ok = await discoverServices(deviceId);
      _logWithTime('ensureGattReady.discover.attempt2(${DateTime.now().difference(d1).inMilliseconds}ms) -> $ok');
    }

    if (!ok) return false;

    // Request MTU once per connection; cache result for framing
    if (Platform.isAndroid) {
      try {
        final m0 = DateTime.now();
        final mtu = await requestMtu(deviceId, BleConstants.preferredMtu);
        if (mtu > 0) _mtuByDevice[deviceId] = mtu;
        _logWithTime('ensureGattReady.mtu(${DateTime.now().difference(m0).inMilliseconds}ms) -> $mtu');
      } catch (_) {}
    }

    await Future.delayed(BleConstants.kStabilizeAfterMtu);
    _logWithTime('ensureGattReady.stabilize2(${BleConstants.kStabilizeAfterMtu.inMilliseconds}ms)');
    _logWithTime('ensureGattReady.done(${DateTime.now().difference(t0).inMilliseconds}ms)');
    return ok;
  }

  /// 写特征
  static Future<bool> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> data,
    bool withResponse = true,
  }) async {
    final t0 = DateTime.now();
    _log('✍️ writeCharacteristic 开始: svc=$serviceUuid, char=$characteristicUuid, len=${data.length}, withResp=$withResponse');
    final q = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(characteristicUuid),
    );
    try {
      if (withResponse) {
        await _ble.writeCharacteristicWithResponse(q, value: data);
      } else {
        await _ble.writeCharacteristicWithoutResponse(q, value: data);
      }
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('writeCharacteristic.done(${elapsed}ms)');
      return true;
    } catch (e) {
      final firstElapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('writeCharacteristic.fail1(${firstElapsed}ms): $e');
      try {
        await Future.delayed(Duration(milliseconds: BleConstants.writeRetryDelayMs));
        if (withResponse) {
          await _ble.writeCharacteristicWithResponse(q, value: data);
        } else {
          await _ble.writeCharacteristicWithoutResponse(q, value: data);
        }
        final retryElapsed = DateTime.now().difference(t0).inMilliseconds;
        _logWithTime('writeCharacteristic.retry.done(${retryElapsed}ms)');
        return true;
      } catch (e2) {
        final elapsed = DateTime.now().difference(t0).inMilliseconds;
        _logWithTime('writeCharacteristic.retry.fail(${elapsed}ms): $e2');
        return false;
      }
    }
  }

  /// 订阅特征
  static Stream<List<int>> subscribeToCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    _log('📡 subscribeToCharacteristic: svc=$serviceUuid, char=$characteristicUuid');
    final q = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(characteristicUuid),
    );
    return _ble.subscribeToCharacteristic(q);
  }

  /// 订阅 TX(indicate) 的语义包装
  static Stream<List<int>> subscribeToIndications({
    required String deviceId,
    required String serviceUuid,
    required String txCharacteristicUuid,
  }) {
    _log('📡 subscribeToIndications: svc=$serviceUuid, tx=$txCharacteristicUuid');
    return subscribeToCharacteristic(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: txCharacteristicUuid,
    );
  }

  /// 发现并校验 RX/TX 是否存在
  static Future<bool> hasRxTx({
    required String deviceId,
    required String serviceUuid,
    required String rxUuid,
    required String txUuid,
  }) async {
    final t0 = DateTime.now();
    _log('🔎 hasRxTx 开始: svc=$serviceUuid, rx=$rxUuid, tx=$txUuid');
    try {
      final services = await _ble.discoverServices(deviceId);
      final s = services.firstWhere(
        (e) =>
            e.serviceId.toString().toLowerCase() == serviceUuid.toLowerCase(),
        orElse: () => DiscoveredService(
          serviceId: Uuid.parse('00000000-0000-0000-0000-000000000000'),
          serviceInstanceId: '',
          characteristicIds: const [],
          characteristics: const [],
          includedServices: const [],
        ),
      );
      if (s.characteristicIds.isEmpty) return false;
      final hasRx = s.characteristicIds
          .any((c) => c.toString().toLowerCase() == rxUuid.toLowerCase());
      final hasTx = s.characteristicIds
          .any((c) => c.toString().toLowerCase() == txUuid.toLowerCase());
      final ok = hasRx && hasTx;
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('hasRxTx.result(${elapsed}ms) -> $ok');
      return ok;
    } catch (e) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('hasRxTx.fail(${elapsed}ms): $e');
      return false;
    }
  }

  /// 清理
  static void dispose() {
    _log('🧹 dispose');
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = null;
    _scanController?.close();
    _scanController = null;
    _discoveredDevices.clear();
    _isScanning = false;
    _mtuByDevice.clear();
    _sessionStart = null;
  }
}

/// 扫描结果模型
class SimpleBLEScanResult {
  final String deviceId;
  final String name;
  final String address;
  final int rssi;
  final DateTime timestamp;
  final List<String> serviceUuids;
  final Map<String, List<int>>? serviceData;
  final Uint8List? manufacturerData;
  final List<int>? rawAdvertisementData;
  final bool connectable;

  SimpleBLEScanResult({
    required this.deviceId,
    required this.name,
    required this.address,
    required this.rssi,
    required this.timestamp,
    this.serviceUuids = const [],
    this.serviceData,
    this.manufacturerData,
    this.rawAdvertisementData,
    this.connectable = true,
  });

  static SimpleBLEScanResult fromDiscoveredDevice(DiscoveredDevice device) {
    return SimpleBLEScanResult(
      deviceId: device.id,
      name: device.name.isNotEmpty ? device.name : 'Unknown Device',
      address: device.id,
      rssi: device.rssi,
      timestamp: DateTime.now(),
      serviceUuids: device.serviceUuids.map((u) => u.toString()).toList(),
      serviceData: device.serviceData.map((k, v) => MapEntry(k.toString(), v)),
      manufacturerData:
      device.manufacturerData.isNotEmpty ? device.manufacturerData : null,
      connectable: device.connectable == Connectable.available,
    );
  }
}
