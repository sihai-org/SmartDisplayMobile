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

        print('🔍 发现设备: ${result.name}');
        print('  id=${result.deviceId}, rssi=${result.rssi}');
        print('  serviceUuids=${result.serviceUuids}');
        print('  manufacturerData=${result.manufacturerData}');
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
                await _ble.requestMtu(
                    deviceId: deviceId, mtu: BleConstants.preferredMtu);
              } catch (e) {
                print('❌ requestMtu 失败: $e');
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

  /// 确保 GATT 就绪：稳定延时 -> 服务发现 -> MTU 协商 -> 再次稳定
  static Future<bool> ensureGattReady(String deviceId) async {
    await Future.delayed(Duration(milliseconds: BleConstants.postConnectStabilizeDelayMs));
    final ok = await discoverServices(deviceId);
    try {
      await _ble.requestMtu(deviceId: deviceId, mtu: BleConstants.preferredMtu);
    } catch (e) {
      print('❌ ensureGattReady.requestMtu 失败: $e');
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
