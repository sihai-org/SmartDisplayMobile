import 'dart:async';
import 'dart:io';
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
      if (AppConstants.skipPermissionCheck) {
        print('🔧 开发模式：跳过权限检查');
        return true;
      }

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
    if (_isScanning) return Stream.empty();
    _scanController?.close();
    _scanController = StreamController<SimpleBLEScanResult>.broadcast();
    _startScanningProcess(targetDeviceId, timeout);
    return _scanController!.stream;
  }

  static void _startScanningProcess(String targetDeviceId, Duration timeout) async {
    try {
      _isScanning = true;
      await _stopScanSubscription();
      Timer(timeout, () async {
        if (_isScanning) await stopScan();
      });
      _discoveredDevices.clear();

      _scanSubscription = _ble.scanForDevices(
        withServices: [Uuid.parse(BleConstants.serviceUuid)],
        scanMode: ScanMode.balanced,
        requireLocationServicesEnabled: Platform.isAndroid,
      ).listen((device) {
        if (!_isScanning) return;
        final result = SimpleBLEScanResult.fromDiscoveredDevice(device);
        final existing = _discoveredDevices[result.deviceId];
        if (existing == null || result.rssi > existing.rssi) {
          _discoveredDevices[result.deviceId] = result;
          _scanController?.add(result);
        }
      }, onError: (error) {
        _scanController?.addError(error);
        _isScanning = false;
      }, onDone: () {
        _isScanning = false;
        _scanController?.close();
      });
    } catch (e) {
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
    _isScanning = false;
    await _stopScanSubscription();
    await _scanController?.close();
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
                await _ble.requestMtu(deviceId: deviceId, mtu: BleConstants.preferredMtu);
              } catch (_) {}
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

  /// 写特征
  static Future<bool> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> data,
    bool withResponse = true,
  }) async {
    try {
      final q = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(characteristicUuid),
      );
      if (withResponse) {
        await _ble.writeCharacteristicWithResponse(q, value: data);
      } else {
        await _ble.writeCharacteristicWithoutResponse(q, value: data);
      }
      return true;
    } catch (e) {
      return false;
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
  final Map<String, dynamic>? manufacturerData;
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
      device.manufacturerData.isNotEmpty ? {'data': device.manufacturerData} : null,
      connectable: device.connectable == Connectable.available,
    );
  }
}
