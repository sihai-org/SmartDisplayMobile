import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/ble_constants.dart';
import '../../../core/utils/result.dart' as AppResult;
import '../../../core/errors/failures.dart';
import '../models/ble_device_data.dart';

/// BLE连接和通信服务
class BleService {
  static final FlutterReactiveBle _ble = FlutterReactiveBle();
  
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _characteristicSubscription;
  
  String? _connectedDeviceId;
  
  /// 检查蓝牙状态
  static Future<BleStatus> checkBleStatus() async {
    return _ble.status;
  }
  
  /// 请求蓝牙权限
  static Future<bool> requestPermissions() async {
    try {
      // 检查并请求蓝牙相关权限
      final permissions = [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.locationWhenInUse,
      ];
      
      // 检查当前权限状态
      Map<Permission, PermissionStatus> statuses = await permissions.request();
      
      // 检查所有权限是否被授予
      bool allGranted = true;
      for (final permission in permissions) {
        final status = statuses[permission];
        if (status != PermissionStatus.granted) {
          print('权限 ${permission.toString()} 状态: $status');
          if (status != PermissionStatus.limited && permission != Permission.bluetoothAdvertise) {
            // bluetoothAdvertise 权限在某些设备上可能不可用，但不影响扫描和连接
            allGranted = false;
          }
        }
      }
      
      if (!allGranted) {
        // 如果权限被拒绝，提示用户手动开启
        print('部分权限未授予，请到设置中手动开启蓝牙和位置权限');
        return false;
      }
      
      // 检查蓝牙状态
      final bleStatus = await checkBleStatus();
      if (bleStatus != BleStatus.ready) {
        print('蓝牙状态: $bleStatus');
        return false;
      }
      
      return true;
    } catch (e) {
      print('请求权限时发生错误: $e');
      return false;
    }
  }
  
  /// 扫描指定的BLE设备
  Stream<BleScanResult> scanForDevice({
    required String targetDeviceId,
    Duration timeout = const Duration(seconds: 30),
  }) async* {
    try {
      // 检查蓝牙状态
      final status = await checkBleStatus();
      if (status != BleStatus.ready) {
        throw Exception('蓝牙未就绪: ${status.toString()}');
      }
      
      // 停止之前的扫描
      await stopScan();
      
      // 开始扫描
      _scanSubscription = _ble.scanForDevices(
        withServices: [Uuid.parse(BleConstants.serviceUuid)],
        scanMode: ScanMode.lowLatency,
        requireLocationServicesEnabled: true,
      ).listen(
        (device) {
          // 过滤目标设备
          if (device.id.toLowerCase().contains(targetDeviceId.toLowerCase()) ||
              device.name.toLowerCase().contains(targetDeviceId.toLowerCase())) {
            // 通过StreamController发送结果
          }
        },
        onError: (error) {
          throw Exception('扫描错误: $error');
        },
      );
      
      // 设置超时
      Timer(timeout, () {
        stopScan();
      });
      
      // 将扫描结果转换为BleScanResult
      await for (final device in _ble.scanForDevices(
        withServices: [Uuid.parse(BleConstants.serviceUuid)],
        scanMode: ScanMode.lowLatency,
      )) {
        if (device.id.toLowerCase().contains(targetDeviceId.toLowerCase()) ||
            device.name.toLowerCase().contains(targetDeviceId.toLowerCase())) {
          yield BleScanResult.fromDiscoveredDevice(device);
        }
      }
      
    } catch (e) {
      throw Exception('扫描失败: $e');
    }
  }
  
  /// 停止扫描
  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }
  
  /// 连接到BLE设备
  Future<AppResult.Result<BleDeviceData>> connectToDevice({
    required BleDeviceData deviceData,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      // 检查是否已连接
      if (_connectedDeviceId == deviceData.deviceId) {
        return Result.success(deviceData.copyWith(status: BleDeviceStatus.connected));
      }
      
      // 断开之前的连接
      await disconnect();
      
      final completer = Completer<AppResult.Result<BleDeviceData>>();
      
      // 设置连接超时
      Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(AppResult.Result.failure(const BleFailure(message: '连接超时')));
        }
      });
      
      // 开始连接
      _connectionSubscription = _ble.connectToDevice(
        id: deviceData.bleAddress,
        connectionTimeout: timeout,
      ).listen(
        (connectionState) async {
          switch (connectionState.connectionState) {
            case DeviceConnectionState.connecting:
              // 连接中状态已通过状态管理器处理
              break;
              
            case DeviceConnectionState.connected:
              _connectedDeviceId = deviceData.deviceId;
              
              try {
                // 请求更大的MTU
                final mtu = await _ble.requestMtu(
                  deviceId: deviceData.bleAddress,
                  mtu: BleConstants.preferredMtu,
                );
                
                // 发现服务
                await _discoverServices(deviceData.bleAddress);
                
                if (!completer.isCompleted) {
                  completer.complete(Result.success(
                    deviceData.copyWith(
                      status: BleDeviceStatus.connected,
                      mtu: mtu,
                      connectedAt: DateTime.now(),
                    ),
                  ));
                }
              } catch (e) {
                if (!completer.isCompleted) {
                  completer.complete(Result.failure(BleFailure(message: '连接后初始化失败: $e')));
                }
              }
              break;
              
            case DeviceConnectionState.disconnecting:
            case DeviceConnectionState.disconnected:
              _connectedDeviceId = null;
              if (!completer.isCompleted) {
                completer.complete(Result.failure(const BleFailure(message: '设备连接断开')));
              }
              break;
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.complete(Result.failure(BleFailure(message: '连接错误: $error')));
          }
        },
      );
      
      return await completer.future;
      
    } catch (e) {
      return Result.failure(BleFailure(message: '连接失败: $e'));
    }
  }
  
  /// 发现服务
  Future<List<BleServiceInfo>> _discoverServices(String deviceId) async {
    try {
      final services = await _ble.discoverServices(deviceId);
      
      return services.map((service) {
        final characteristics = service.characteristics.map((char) {
          return BleCharacteristicInfo(
            characteristicUuid: char.characteristicId.toString(),
            canRead: char.isReadable,
            canWrite: char.isWritableWithoutResponse || char.isWritableWithResponse,
            canNotify: char.isNotifiable,
            canIndicate: char.isIndicatable,
          );
        }).toList();
        
        return BleServiceInfo(
          serviceUuid: service.serviceId.toString(),
          characteristics: characteristics,
        );
      }).toList();
      
    } catch (e) {
      throw Exception('服务发现失败: $e');
    }
  }
  
  /// 断开连接
  Future<void> disconnect() async {
    await _connectionSubscription?.cancel();
    await _characteristicSubscription?.cancel();
    _connectionSubscription = null;
    _characteristicSubscription = null;
    _connectedDeviceId = null;
  }
  
  /// 读取特征值
  Future<Result<List<int>>> readCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    try {
      final characteristic = QualifiedCharacteristic(
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(characteristicUuid),
        deviceId: deviceId,
      );
      
      final data = await _ble.readCharacteristic(characteristic);
      return Result.success(data);
      
    } catch (e) {
      return Result.failure(BleFailure(message: '读取特征值失败: $e'));
    }
  }
  
  /// 写入特征值
  Future<Result<void>> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> data,
    bool withResponse = true,
  }) async {
    try {
      final characteristic = QualifiedCharacteristic(
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(characteristicUuid),
        deviceId: deviceId,
      );
      
      if (withResponse) {
        await _ble.writeCharacteristicWithResponse(characteristic, data);
      } else {
        await _ble.writeCharacteristicWithoutResponse(characteristic, data);
      }
      
      return Result.success(null);
      
    } catch (e) {
      return Result.failure(BleFailure(message: '写入特征值失败: $e'));
    }
  }
  
  /// 订阅特征值通知
  Stream<List<int>> subscribeToCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(characteristicUuid),
      deviceId: deviceId,
    );
    
    return _ble.subscribeToCharacteristic(characteristic);
  }
  
  /// 获取连接状态
  bool get isConnected => _connectedDeviceId != null;
  
  /// 获取连接的设备ID
  String? get connectedDeviceId => _connectedDeviceId;
  
  /// 释放资源
  void dispose() {
    stopScan();
    disconnect();
  }
}