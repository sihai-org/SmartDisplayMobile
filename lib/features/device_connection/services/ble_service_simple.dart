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

  /// 检查BLE状态
  static Future<BleStatus> checkBleStatus() async {
    try {
      print('🔍 获取BLE状态流...');
      final statusStream = _ble.statusStream;
      print('⏱️  等待BLE状态（最多10秒）...');
      
      final status = await statusStream.first.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('⚠️  BLE状态获取超时，返回unknown');
          return BleStatus.unknown;
        },
      );
      
      print('📡 BLE状态获取完成: $status');
      return status;
    } catch (e) {
      print('❌ 检查BLE状态失败: $e');
      return BleStatus.unknown;
    }
  }

  /// 请求蓝牙权限 - 简化版本
  static Future<bool> requestPermissions() async {
    try {
      // 开发模式跳过权限检查
      if (AppConstants.skipPermissionCheck) {
        print('🔧 开发模式：跳过权限检查');
        return true;
      }
      
      print('🔍 检查蓝牙权限和状态...');
      
      // 检查蓝牙硬件状态
      final bleStatus = await checkBleStatus();
      print('📶 蓝牙状态: $bleStatus');
      
      if (bleStatus == BleStatus.unsupported) {
        print('❌ 此设备不支持蓝牙');
        return false;
      }
      
      if (bleStatus == BleStatus.poweredOff) {
        print('❌ 蓝牙已关闭，请在设置中开启蓝牙');
        return false;
      }
      
      // 检查权限状态 - iOS和Android兼容处理
      print('📋 检查当前权限状态...');
      print('📱 当前平台: ${Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : 'Unknown'}');
      
      // iOS BLE中心模式不需要位置权限
      if (Platform.isIOS) {
        print('🍎 iOS系统 - BLE中心模式无需位置权限');
        // iOS中心模式扫描BLE设备无需位置权限，直接检查蓝牙状态即可
        final finalBleStatus = await checkBleStatus();
        if (finalBleStatus == BleStatus.ready) {
          print('✅ iOS蓝牙状态正常，可以扫描');
          return true;
        } else {
          print('❌ iOS蓝牙状态不可用: $finalBleStatus');
          return false;
        }
      }
      
      // Android或其他平台的完整权限检查
      List<Permission> requiredPermissions = [];
      
      if (Platform.isAndroid) {
        try {
          // 检查Android特有的蓝牙权限
          final bluetoothScanStatus = await Permission.bluetoothScan.status;
          final bluetoothConnectStatus = await Permission.bluetoothConnect.status;
          
          print('📱 Android系统，检查蓝牙权限:');
          print('   蓝牙扫描: $bluetoothScanStatus');
          print('   蓝牙连接: $bluetoothConnectStatus');
          
          if (!bluetoothScanStatus.isGranted) {
            requiredPermissions.add(Permission.bluetoothScan);
          }
          if (!bluetoothConnectStatus.isGranted) {
            requiredPermissions.add(Permission.bluetoothConnect);
          }
        } catch (e) {
          print('⚠️  Android蓝牙权限检查失败，可能是旧版本: $e');
        }
      }
      
      // 检查位置权限（所有平台都需要）
      final locationStatus = await Permission.locationWhenInUse.status;
      print('   位置权限: $locationStatus');
      
      if (!locationStatus.isGranted) {
        requiredPermissions.add(Permission.locationWhenInUse);
      }
      
      // 如果蓝牙就绪且没有需要请求的权限，直接返回成功
      if (requiredPermissions.isEmpty && bleStatus == BleStatus.ready) {
        print('✅ 所有权限已授予，蓝牙可用');
        return true;
      }
      
      // 请求未授予的权限
      if (requiredPermissions.isNotEmpty) {
        print('📱 请求必要权限: ${requiredPermissions.map((p) => p.toString()).join(', ')}');
        final Map<Permission, PermissionStatus> results = await requiredPermissions.request();
        
        // 检查请求结果
        final allGranted = results.values.every((status) => status.isGranted);
        if (!allGranted) {
          print('❌ 权限未完全授予:');
          for (final entry in results.entries) {
            if (!entry.value.isGranted) {
              print('   ${entry.key}: ${entry.value}');
            }
          }
          return false;
        }
      }
      
      // 最终检查蓝牙状态
      final finalBleStatus = await checkBleStatus();
      if (finalBleStatus == BleStatus.ready) {
        print('✅ 权限授予成功，蓝牙可用');
        return true;
      } else {
        print('❌ 蓝牙状态不可用: $finalBleStatus');
        return false;
      }
      
    } catch (e) {
      print('❌ 权限检查失败: $e');
      return false;
    }
  }

  /// 扫描指定设备 - 使用StreamController管理订阅
  static Stream<SimpleBLEScanResult> scanForDevice({
    required String targetDeviceId,
    required Duration timeout,
  }) {
    // 并发控制：如果已经在扫描，返回空流
    if (_isScanning) {
      print('⚠️ 扫描已在进行中，跳过新的扫描请求');
      return Stream.empty();
    }

    // 创建StreamController
    _scanController?.close(); // 关闭之前的controller
    _scanController = StreamController<SimpleBLEScanResult>.broadcast();
    
    _startScanningProcess(targetDeviceId, timeout);
    
    return _scanController!.stream;
  }
  
  /// 内部扫描处理逻辑
  static void _startScanningProcess(String targetDeviceId, Duration timeout) async {
    try {
      print('🔍 开始扫描设备: $targetDeviceId');
      _isScanning = true;
      
      // 先停止任何现有的扫描
      await _stopScanSubscription();
      
      // 设置超时自动停止扫描
      Timer(timeout, () async {
        if (_isScanning) {
          print('⏰ 扫描超时，停止扫描');
          await stopScan();
        }
      });
      
      // 清空之前的扫描结果
      _discoveredDevices.clear();
      
      // 开始扫描 - 暂时不使用Service UUID过滤以便调试
      print('🔍 开始BLE扫描，目标服务UUID: ${BleConstants.serviceUuid}');

      // 按服务UUID过滤，提升匹配稳定性（iOS/Android均建议开启）
      _scanSubscription = _ble.scanForDevices(
        withServices: [Uuid.parse(BleConstants.serviceUuid)],
        scanMode: ScanMode.balanced,
        requireLocationServicesEnabled: Platform.isAndroid, // 仅Android需要
      ).listen(
        (device) {
          if (!_isScanning) return; // 如果已停止，忽略结果
          
          print('📱 发现BLE设备: "${device.name}" (${device.id})');
          print('   RSSI: ${device.rssi}, 可连接: ${device.connectable}');
          print('   服务UUID: ${device.serviceUuids.map((u) => u.toString()).join(', ')}');
          print('   制造商数据: ${device.manufacturerData}');
          
          final result = SimpleBLEScanResult.fromDiscoveredDevice(device);
          
          // 设备去重：如果已存在该设备ID，更新RSSI和时间戳
          final deviceId = result.deviceId;
          final existingDevice = _discoveredDevices[deviceId];
          
          if (existingDevice != null) {
            // 更新现有设备信息（保留更强的信号）
            if (result.rssi > existingDevice.rssi) {
              _discoveredDevices[deviceId] = result;
              print('🔄 更新设备信息: ${device.name}, 新RSSI: ${result.rssi}');
            }
          } else {
            // 新设备，添加到映射表
            _discoveredDevices[deviceId] = result;
            print('✅ 新发现设备: ${device.name}');
            
            // 通过StreamController发送新设备结果
            if (_scanController != null && !_scanController!.isClosed) {
              _scanController!.add(result);
            }
          }
        },
        onError: (error) {
          print('扫描设备时出错: $error');
          if (_scanController != null && !_scanController!.isClosed) {
            _scanController!.addError(error);
          }
          _isScanning = false;
        },
        onDone: () {
          print('🏁 BLE扫描完成');
          _isScanning = false;
          if (_scanController != null && !_scanController!.isClosed) {
            _scanController!.close();
          }
        },
      );
      
    } catch (e) {
      print('启动扫描失败: $e');
      _isScanning = false;
      if (_scanController != null && !_scanController!.isClosed) {
        _scanController!.addError(e);
        _scanController!.close();
      }
    }
  }
  
  /// 内部方法：停止扫描订阅
  static Future<void> _stopScanSubscription() async {
    if (_scanSubscription != null) {
      print('🛑 取消现有的BLE扫描订阅');
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      // 给一些时间让取消操作完成
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  /// 停止当前扫描 - 幂等操作
  static Future<void> stopScan() async {
    if (!_isScanning && _scanSubscription == null) {
      print('🔄 扫描未在进行或已停止，跳过停止操作');
      return; // 幂等：如果没有在扫描，直接返回
    }
    
    print('🛑 停止BLE扫描');
    _isScanning = false; // 先设置状态，防止新的扫描结果被处理
    
    // 停止扫描订阅
    await _stopScanSubscription();
    
    // 关闭StreamController
    if (_scanController != null && !_scanController!.isClosed) {
      await _scanController!.close();
      _scanController = null;
    }
    
    print('✅ BLE扫描已完全停止');
  }

  /// 连接到BLE设备
  static Future<BleDeviceData?> connectToDevice({
    required BleDeviceData deviceData,
    required Duration timeout,
  }) async {
    try {
      print('🔗 开始真实BLE GATT连接到设备: ${deviceData.deviceName}');
      print('   设备地址: ${deviceData.bleAddress}');
      
      // 停止扫描（如果还在扫描）
      await stopScan();
      
      // 使用设备的真实地址进行连接
      final deviceId = deviceData.bleAddress.isNotEmpty 
          ? deviceData.bleAddress 
          : deviceData.deviceId;
      
      print('🔌 尝试连接设备ID: $deviceId');
      
      // 建立BLE连接
      final connectionStream = _ble.connectToDevice(
        id: deviceId,
        connectionTimeout: timeout,
      );
      
      // 监听连接状态
      final completer = Completer<BleDeviceData?>();
      // 若已有连接订阅，先取消以避免多路订阅
      await _deviceConnectionSubscription?.cancel();
      _deviceConnectionSubscription = connectionStream.listen(
        (connectionState) async {
          print('📶 连接状态更新: ${connectionState.connectionState}');
          
          switch (connectionState.connectionState) {
            case DeviceConnectionState.connecting:
              print('⏳ 正在连接中...');
              break;
              
            case DeviceConnectionState.connected:
              print('✅ BLE连接成功！');
              // 不要取消订阅！保持订阅以维持连接
              // 首次连接成功时完成结果
              // 请求更大的MTU（Android生效，iOS忽略），减少通知截断
              try {
                final negotiated = await _ble.requestMtu(
                  deviceId: deviceId,
                  mtu: BleConstants.preferredMtu,
                );
                print('📏 已请求MTU，协商结果: $negotiated');
              } catch (e) {
                print('⚠️ 请求MTU失败或不支持: $e');
              }
              completer.complete(deviceData.copyWith(
                status: BleDeviceStatus.connected,
                connectedAt: DateTime.now(),
              ));
              break;
              
            case DeviceConnectionState.disconnected:
              print('❌ BLE连接断开');
              // 连接断开时，如未完成则返回null
              if (!completer.isCompleted) {
                completer.complete(null);
              }
              break;
              
            case DeviceConnectionState.disconnecting:
              print('⏸️ 正在断开连接...');
              break;
          }
        },
        onError: (error) {
          print('❌ BLE连接错误: $error');
          // 出错时返回null
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        },
      );
      
      // 设置连接超时
      Timer(timeout, () {
        if (!completer.isCompleted) {
          print('⏰ BLE连接超时');
          _deviceConnectionSubscription?.cancel();
          completer.complete(null);
        }
      });
      
      return await completer.future;
      
    } catch (e) {
      print('❌ BLE连接过程出错: $e');
      return null;
    }
  }

  /// 断开连接
  static Future<void> disconnect() async {
    try {
      await stopScan(); // 先停止扫描
      _scanSubscription?.cancel();
      _scanSubscription = null;
      await _deviceConnectionSubscription?.cancel();
      _deviceConnectionSubscription = null;
    print('✅ BLE连接已断开');
    } catch (e) {
      print('断开连接时出错: $e');
    }
  }

  /// 读取特征值（返回原始字节；失败返回null）
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
      final data = await _ble.readCharacteristic(q);
      return data;
    } catch (e) {
      print('❌ 读取特征值失败: $e');
      return null;
    }
  }

  /// 写入特征值（默认有响应）
  static Future<bool> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> data,
    bool withResponse = true,
  }) async {
    try {
      // 添加详细的写入调试信息
      print('🔍 准备写入BLE特征值:');
      print('   设备ID: $deviceId');
      print('   服务UUID: $serviceUuid');
      print('   特征值UUID: $characteristicUuid');
      print('   数据长度: ${data.length} 字节');
      print('   需要响应: $withResponse');

      // 首先尝试发现服务来验证连接和特征值是否可用
      print('🔍 验证特征值可用性...');
      try {
        final services = await _ble.discoverServices(deviceId);
        print('📋 发现 ${services.length} 个服务');

        // 检查目标服务是否存在
        DiscoveredService? targetService;
        try {
          targetService = services.firstWhere(
            (s) {
              final serviceIdStr = s.serviceId.toString().toLowerCase();
              final targetUuidStr = serviceUuid.toLowerCase();
              // 支持完整格式和简短格式的匹配
              // a100 = 0000a100-0000-1000-8000-00805f9b34fb
              return serviceIdStr == targetUuidStr ||
                     serviceIdStr == targetUuidStr.substring(4, 8) ||
                     targetUuidStr.contains(serviceIdStr);
            },
          );
        } catch (e) {
          targetService = null;
        }

        if (targetService == null) {
          throw Exception('目标服务 $serviceUuid 未找到，可用服务: ${services.map((s) => s.serviceId).join(', ')}');
        }

        print('✅ 找到目标服务: ${targetService.serviceId}');

        // 检查目标特征值是否存在
        DiscoveredCharacteristic? targetChar;
        try {
          targetChar = targetService.characteristics.firstWhere(
            (c) {
              final charIdStr = c.characteristicId.toString().toLowerCase();
              final targetCharUuidStr = characteristicUuid.toLowerCase();
              // 支持完整格式和简短格式的匹配
              // a105 = 0000a105-0000-1000-8000-00805f9b34fb
              return charIdStr == targetCharUuidStr ||
                     charIdStr == targetCharUuidStr.substring(4, 8) ||
                     targetCharUuidStr.contains(charIdStr);
            },
          );
        } catch (e) {
          targetChar = null;
        }

        if (targetChar == null) {
          throw Exception('目标特征值 $characteristicUuid 未找到，可用特征值: ${targetService.characteristics.map((c) => c.characteristicId).join(', ')}');
        }

        print('✅ 找到目标特征值: ${targetChar.characteristicId}');
        print('   特征值属性: 可读=${targetChar.isReadable}, 可写响应=${targetChar.isWritableWithResponse}, 可写无响应=${targetChar.isWritableWithoutResponse}, 可通知=${targetChar.isNotifiable}');

        // 检查写入权限
        final canWrite = targetChar.isWritableWithResponse || targetChar.isWritableWithoutResponse;
        if (!canWrite) {
          throw Exception('特征值 $characteristicUuid 不支持写入操作');
        }

      } catch (serviceError) {
        print('⚠️ 服务发现或验证失败: $serviceError');
        throw Exception('服务验证失败: $serviceError');
      }

      final q = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(characteristicUuid),
      );

      if (withResponse) {
        await _ble.writeCharacteristicWithResponse(q, value: data);
        print('✅ 写入特征值成功 (with response)');
      } else {
        await _ble.writeCharacteristicWithoutResponse(q, value: data);
        print('✅ 写入特征值成功 (without response)');
      }
      return true;
    } catch (e) {
      print('❌ 写入特征值失败: $e');
      print('   目标设备: $deviceId');
      print('   特征值: $serviceUuid/$characteristicUuid');
      return false;
    }
  }

  /// 订阅特征值通知
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

  /// 释放资源 - 幂等清理
  static void dispose() {
    _bleStatusSubscription?.cancel();
    _bleStatusSubscription = null;
    
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = null;
    
    _scanController?.close();
    _scanController = null;
    
    // 清理设备去重映射表
    _discoveredDevices.clear();
    
    _isScanning = false;
    print('🧹 BleServiceSimple资源已清理');
  }
}

/// 简化的BLE扫描结果
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
    // 转换服务UUID列表
    final serviceUuids = device.serviceUuids.map((uuid) => uuid.toString()).toList();
    
    // 转换服务数据
    Map<String, List<int>>? convertedServiceData;
    if (device.serviceData.isNotEmpty) {
      convertedServiceData = {};
      device.serviceData.forEach((uuid, data) {
        convertedServiceData![uuid.toString()] = data;
      });
    }
    
    // 转换制造商数据
    Map<String, dynamic>? convertedManufacturerData;
    if (device.manufacturerData.isNotEmpty) {
      convertedManufacturerData = {'data': device.manufacturerData};
    }

    return SimpleBLEScanResult(
      deviceId: device.id,
      name: device.name.isNotEmpty ? device.name : 'Unknown Device',
      address: device.id,
      rssi: device.rssi,
      timestamp: DateTime.now(),
      serviceUuids: serviceUuids,
      serviceData: convertedServiceData,
      manufacturerData: convertedManufacturerData,
      connectable: device.connectable == Connectable.available,
    );
  }
}
