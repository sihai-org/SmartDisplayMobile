import 'dart:async';
import 'dart:io';
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

  // 权限就绪广播（供上层监听）
  static final _permissionStreamController = StreamController<bool>.broadcast();
  static Stream<bool> get permissionStream => _permissionStreamController.stream;

  // ✅ 统一的“刚就绪”时间戳 & 老安卓定位门槛缓存
  static bool _legacyNeedsLocation = false; // Android < 12 是否需要定位服务开关

  /// 申请更大的 MTU
  static Future<int> requestMtu(String deviceId, int mtu) async {
    try {
      final negotiatedMtu = await _ble.requestMtu(deviceId: deviceId, mtu: mtu);
      print('📏 已请求MTU=$mtu，协商结果: $negotiatedMtu');
      if (negotiatedMtu > 0) {
        _mtuByDevice[deviceId] = negotiatedMtu;
      }
      return negotiatedMtu;
    } catch (e) {
      print('❌ requestMtu 失败: $e');
      return 23; // 默认最小MTU
    }
  }

  static int getNegotiatedMtu(String deviceId) {
    return _mtuByDevice[deviceId] ?? BleConstants.minMtu;
  }

  /// 查询 BLE 当前状态（忽略 unknown）
  static Future<BleStatus> checkBleStatus() async {
    try {
      final status = await _ble.statusStream
          .firstWhere((s) => s != BleStatus.unknown,
              orElse: () => BleStatus.unknown)
          .timeout(const Duration(seconds: 5));
      return status;
    } catch (_) {
      return BleStatus.unknown;
    }
  }

  static Future<bool> ensureBleReady() async {
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
          final rs = await reqs.request();
          if (rs.values.any((s) => !s.isGranted)) {
            _permissionStreamController.add(false);
            return false;
          }
          if (_legacyNeedsLocation) {
            final service = await Permission.locationWhenInUse.serviceStatus;
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

      var s = await waitReady(const Duration(seconds: 2));
      if (s != BleStatus.ready) s = await waitReady(const Duration(seconds: 2));

      final ok = (s == BleStatus.ready);
      _permissionStreamController.add(ok);
      return ok;
    } catch (_) {
      _permissionStreamController.add(false);
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
    _startScanningProcess(timeout);
    return _scanController!.stream;
  }

  static void _startScanningProcess(Duration timeout) async {
    try {
      await stopScan(); // 确保冷启动
      _discoveredDevices.clear();
      _isScanning = true;

      // ✅ 固定用 lowLatency，别切 balanced
      _scanSubscription = _ble.scanForDevices(
        withServices: [],
        scanMode: ScanMode.lowLatency,
        requireLocationServicesEnabled: _legacyNeedsLocation, // Android<12 仍保留
      ).listen((device) {
        if (!_isScanning) return;
        final result = SimpleBLEScanResult.fromDiscoveredDevice(device);
        _discoveredDevices[result.deviceId] = result;
        _scanController?.add(result);
        _throttledLog(result); // 你的节流日志函数保留即可
      }, onError: (e) {
        _scanController?.addError(e); // ❌ 不做重扫预算
        _isScanning = false;
        _scanController?.close();
      }, onDone: () {
        _isScanning = false;
        _scanController?.close();
      });

      // 超时停止（单次）
      Timer(timeout, () async {
        if (_isScanning) await stopScan();
      });
    } catch (e) {
      _isScanning = false;
      _scanController?.addError(e);
      _scanController?.close();
    }
  }

  static Future<void> stopScan() async {
    if (!_isScanning && _scanSubscription == null) return;
    _isScanning = false;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (_scanController != null && !_scanController!.isClosed) {
      await _scanController?.close();
    }
    _scanController = null;
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
    try {
      await stopScan();

      final connectionStream = _ble.connectToDevice(
        id: bleDeviceData.displayDeviceId,
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
        print('[BLE] connectionState=${update.connectionState} device=${update.deviceId} failure=${update.failure}');
        switch (update.connectionState) {
          case DeviceConnectionState.connected:
            await Future.delayed(BleConstants.kPostConnectStabilize);
            completeOnce(bleDeviceData.copyWith(
              status: BleDeviceStatus.connected,
              connectedAt: DateTime.now(),
            ));
            break;
          case DeviceConnectionState.disconnected:
            completeOnce(null);
            break;
          default:
            break;
        }
      }, onError: (_) {
        // ignore: avoid_print
        print('[BLE] connection stream error: _');
        completeOnce(null);
      });

      // ▼ 超时兜底（会在 completeOnce 里被 cancel）
      timer = Timer(timeout, () => completeOnce(null));
      // ▲

      final res = await completer.future;
      // 保持连接订阅存活，直至显式调用 disconnect()
      return res;
    } catch (_) {
      return null;
    }
  }

  /// 断开连接
  static Future<void> disconnect() async {
    await stopScan();
    await _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = null;

    // ✅ 仅保留这一处固定等待
    await Future.delayed(BleConstants.kDisconnectStabilize);

    // 清状态（避免下一轮粘连）
    _discoveredDevices.clear();
    _lastLogAt.clear();
    _lastLogRssi.clear();
  }

  /// 读特征
  static Future<List<int>?> readCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    try {
      final q = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(characteristicUuid),
      );
      return await _ble.readCharacteristic(q);
    } catch (_) {
      return null;
    }
  }

  /// 主动触发服务发现，确保 GATT 就绪（尤其 Android）
  static Future<bool> discoverServices(String deviceId) async {
    try {
      final services = await _ble.discoverServices(deviceId);
      print('🧭 已发现服务数量: ${services.length}');
      return services.isNotEmpty;
    } catch (e) {
      print('❌ discoverServices 失败: $e');
      return false;
    }
  }

  /// 检查是否存在指定的 Service/Characteristic
  static Future<bool> hasCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    try {
      final services = await _ble.discoverServices(deviceId);
      for (final s in services) {
        print('🧭 Service: ${s.serviceId}');
        for (final c in s.characteristicIds) {
          print('   • Char: $c');
        }
      }
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
        print('🔎 未发现目标服务 $serviceUuid');
        return false;
      }
      final found = targetService.characteristicIds
          .any((c) => c.toString().toLowerCase() == characteristicUuid.toLowerCase());
      if (!found) {
        print('🔎 服务中未发现特征 $characteristicUuid');
      }
      return found;
    } catch (e) {
      print('❌ hasCharacteristic 失败: $e');
      return false;
    }
  }

  /// 确保 GATT 就绪：稳定延时 -> 服务发现 -> MTU 协商 -> 再次稳定
  static Future<bool> ensureGattReady(String deviceId) async {
    // Allow connection to fully settle before first discovery
    await Future.delayed(BleConstants.kPostConnectStabilize);

    // Retry service discovery once to mitigate transient 133/135
    bool ok = await discoverServices(deviceId);
    if (!ok) {
      await Future.delayed(const Duration(milliseconds: 600));
      ok = await discoverServices(deviceId);
    }

    if (!ok) return false;

    // Request MTU once per connection; cache result for framing
    if (Platform.isAndroid) {
      try {
        final mtu = await requestMtu(deviceId, BleConstants.preferredMtu);
        if (mtu > 0) _mtuByDevice[deviceId] = mtu;
      } catch (_) {}
    }

    await Future.delayed(BleConstants.kPostConnectStabilize);
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
    final q = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(characteristicUuid),
    );
    try {
      print("ble_service_simple: writeCharacteristic withResponse=$withResponse, len=${data.length}");
      if (withResponse) {
        await _ble.writeCharacteristicWithResponse(q, value: data);
      } else {
        await _ble.writeCharacteristicWithoutResponse(q, value: data);
      }
      return true;
    } catch (e) {
      print('❌ 写入失败，准备重试: $e');
      try {
        await Future.delayed(Duration(milliseconds: BleConstants.writeRetryDelayMs));
        if (withResponse) {
          await _ble.writeCharacteristicWithResponse(q, value: data);
        } else {
          await _ble.writeCharacteristicWithoutResponse(q, value: data);
        }
        print('✅ 重试写入成功');
        return true;
      } catch (e2) {
        print('❌ 写入失败，已放弃: $e2');
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
      return hasRx && hasTx;
    } catch (_) {
      return false;
    }
  }

  /// 清理
  static void dispose() {
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = null;
    _scanController?.close();
    _scanController = null;
    _discoveredDevices.clear();
    _isScanning = false;
    _mtuByDevice.clear();
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
