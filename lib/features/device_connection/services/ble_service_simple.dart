import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/ble_device_data.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/ble_constants.dart';

/// 简化的BLE服务类，用于基本的蓝牙操作
class BleServiceSimple {
  static final FlutterReactiveBle _ble = FlutterReactiveBle();
  static StreamSubscription<BleStatus>? _bleStatusSubscription;
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

  /// ✅ 新增：申请更大的 MTU
  static Future<int> requestMtu(String deviceId, int mtu) async {
    try {
      final negotiatedMtu = await _ble.requestMtu(deviceId: deviceId, mtu: mtu);
      print('📏 已请求MTU=$mtu，协商结果: $negotiatedMtu');
      return negotiatedMtu;
    } catch (e) {
      print('❌ requestMtu 失败: $e');
      return 23; // 默认最小MTU
    }
  }

  /// 检查BLE状态
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

  /// 请求蓝牙权限
  static Future<bool> requestPermissions() async {
    try {
      final bleStatus = await checkBleStatus();
      if (bleStatus == BleStatus.unsupported) return false;
      if (bleStatus == BleStatus.poweredOff) return false;

      if (Platform.isIOS) {
        return bleStatus == BleStatus.ready;
      }

      List<Permission> requiredPermissions = [];
      if (Platform.isAndroid) {
        if (!(await Permission.bluetoothScan.isGranted)) {
          requiredPermissions.add(Permission.bluetoothScan);
        }
        if (!(await Permission.bluetoothConnect.isGranted)) {
          requiredPermissions.add(Permission.bluetoothConnect);
        }
      }
      if (!(await Permission.locationWhenInUse.isGranted)) {
        requiredPermissions.add(Permission.locationWhenInUse);
      }

      if (requiredPermissions.isNotEmpty) {
        final results = await requiredPermissions.request();
        if (results.values.any((status) => !status.isGranted)) {
          return false;
        }
      }

      return (await checkBleStatus()) == BleStatus.ready;
    } catch (e) {
      print('❌ 权限检查失败: $e');
      return false;
    }
  }

  /// 扫描设备
  static Stream<SimpleBLEScanResult> scanForDevice({
    required String targetDeviceId,
    required Duration timeout,
  }) {
    _scanController?.close();
    _scanController = StreamController<SimpleBLEScanResult>.broadcast();
    _startScanningProcess(timeout);
    return _scanController!.stream;
  }

  static void _startScanningProcess(Duration timeout) async {
    try {
      // 确保先停止旧的扫描
      await stopScan();

      _isScanning = true;
      print("🔄 开始扫描，超时时间=${timeout.inSeconds}s");

      // 设置超时
      Timer(timeout, () async {
        if (_isScanning) {
          print("⏰ 扫描超时，自动停止");
          await stopScan();
        }
      });

      _scanSubscription = _ble.scanForDevices(
        withServices: [],
        scanMode: ScanMode.lowLatency,
        // ⚠️ 这里改为 false，避免 ROM 强制拦截
        requireLocationServicesEnabled: false,
      ).listen((device) {
        if (!_isScanning) return;

        final result = SimpleBLEScanResult.fromDiscoveredDevice(device);
        _discoveredDevices[result.deviceId] = result;
        _scanController?.add(result);

        // 节流打印，避免日志刷屏：
        // - 同一设备至少间隔 _perDeviceLogInterval 才打印
        // - 或者RSSI变化超过5dBm
        final now = DateTime.now();
        final lastAt = _lastLogAt[result.deviceId];
        final lastRssi = _lastLogRssi[result.deviceId];
        final rssiChanged = lastRssi == null || (result.rssi - lastRssi).abs() >= 5;
        final timeOk = lastAt == null || now.difference(lastAt) >= _perDeviceLogInterval;
        if (timeOk || rssiChanged) {
          _lastLogAt[result.deviceId] = now;
          _lastLogRssi[result.deviceId] = result.rssi;
          // 仅在开发时打印详细发现日志
          // ignore: avoid_print
          print('🔍 发现设备: ${result.name}');
          // ignore: avoid_print
          print('  id=${result.deviceId}, rssi=${result.rssi}');
          // ignore: avoid_print
          print('  serviceUuids=${result.serviceUuids}');
          // ignore: avoid_print
          print('  manufacturerData=${result.manufacturerData}');
        }
      }, onError: (error) {
        print("❌ 扫描出错: $error");
        _scanController?.addError(error);
        _isScanning = false;
      }, onDone: () {
        print("🛑 扫描完成");
        _isScanning = false;
        _scanController?.close();
      });
    } catch (e) {
      print("❌ 扫描启动失败: $e");
      _isScanning = false;
      _scanController?.addError(e);
      _scanController?.close();
    }
  }

  static Future<void> _stopScanSubscription() async {
    if (_scanSubscription != null) {
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  static Future<void> stopScan() async {
    if (!_isScanning && _scanSubscription == null) return;
    print("🛑 手动停止扫描");
    _isScanning = false;
    await _stopScanSubscription();
    if (_scanController != null && !_scanController!.isClosed) {
      await _scanController?.close();
    }
    _scanController = null;
  }

  /// 连接设备
  static Future<BleDeviceData?> connectToDevice({
    required BleDeviceData deviceData,
    required Duration timeout,
  }) async {
    try {
      await stopScan();
      final deviceId = deviceData.bleAddress.isNotEmpty
          ? deviceData.bleAddress
          : deviceData.deviceId;
      final connectionStream = _ble.connectToDevice(
        id: deviceId,
        connectionTimeout: timeout,
      );
      final completer = Completer<BleDeviceData?>();
      await _deviceConnectionSubscription?.cancel();
      _deviceConnectionSubscription = connectionStream.listen(
            (update) async {
          switch (update.connectionState) {
            case DeviceConnectionState.connected:
              try {
                await Future.delayed(Duration(milliseconds: BleConstants.postConnectStabilizeDelayMs));
                // 将 MTU 协商统一放到 ensureGattReady 流程中，避免重复请求
              } catch (e) {
                // ignore
              }
              completer.complete(deviceData.copyWith(
                status: BleDeviceStatus.connected,
                connectedAt: DateTime.now(),
              ));
              break;
            case DeviceConnectionState.disconnected:
              if (!completer.isCompleted) completer.complete(null);
              break;
            default:
              break;
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.complete(null);
        },
      );
      Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });
      return await completer.future;
    } catch (e) {
      return null;
    }
  }

  /// 断开连接
  static Future<void> disconnect() async {
    await stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = null;
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
        print('🧭 Service: ' + s.serviceId.toString());
        for (final c in s.characteristicIds) {
          print('   • Char: ' + c.toString());
        }
      }

      final targetService = services.firstWhere(
        (s) => s.serviceId.toString().toLowerCase() == serviceUuid.toLowerCase(),
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
    await Future.delayed(Duration(milliseconds: BleConstants.postConnectStabilizeDelayMs));
    final ok = await discoverServices(deviceId);
    // 仅在 Android 上主动请求更大 MTU；iOS 通常固定或自动协商
    if (Platform.isAndroid) {
      try {
        final mtu1 = await requestMtu(deviceId, BleConstants.preferredMtu);
        // 若首次协商未到期望值或异常返回（如 23），短暂延时后再重试一次
        if (mtu1 < BleConstants.preferredMtu) {
          await Future.delayed(Duration(milliseconds: BleConstants.writeRetryDelayMs));
          await requestMtu(deviceId, BleConstants.preferredMtu);
        }
      } catch (e) {
        print('❌ ensureGattReady.requestMtu 失败: $e');
      }
    }
    await Future.delayed(Duration(milliseconds: BleConstants.postConnectStabilizeDelayMs));
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

  /// 清理
  static void dispose() {
    _bleStatusSubscription?.cancel();
    _bleStatusSubscription = null;
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = null;
    _scanController?.close();
    _scanController = null;
    _discoveredDevices.clear();
    _isScanning = false;
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
