import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/ble_constants.dart';
import '../../../features/qr_scanner/models/device_qr_data.dart';
import '../models/ble_device_data.dart';
import '../services/ble_service_simple.dart';

/// 设备连接状态数据
class DeviceConnectionState {
  final BleDeviceStatus status;
  final BleDeviceData? deviceData;
  final List<SimpleBLEScanResult> scanResults;
  final String? errorMessage;
  final double progress; // 0.0 - 1.0

  const DeviceConnectionState({
    this.status = BleDeviceStatus.disconnected,
    this.deviceData,
    this.scanResults = const [],
    this.errorMessage,
    this.progress = 0.0,
  });

  DeviceConnectionState copyWith({
    BleDeviceStatus? status,
    BleDeviceData? deviceData,
    List<SimpleBLEScanResult>? scanResults,
    String? errorMessage,
    double? progress,
  }) {
    return DeviceConnectionState(
      status: status ?? this.status,
      deviceData: deviceData ?? this.deviceData,
      scanResults: scanResults ?? this.scanResults,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
    );
  }
}

/// 设备连接管理器
class DeviceConnectionNotifier extends StateNotifier<DeviceConnectionState> {
  DeviceConnectionNotifier() : super(const DeviceConnectionState());

  // Using static BLE service methods
  StreamSubscription? _scanSubscription;
  Timer? _timeoutTimer;

  /// 开始连接流程
  Future<void> startConnection(DeviceQrData qrData) async {
    print('🚀 ==> startConnection 被调用！QR数据: ${qrData.deviceId}');
    try {
      // 重置状态
      state = const DeviceConnectionState();
      print('✅ 状态已重置');
      
      // 创建BLE设备数据
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

      // 检查蓝牙权限  
      print('🔄 开始检查蓝牙权限和状态...');
      final hasPermission = await BleServiceSimple.requestPermissions();
      print('🔐 权限检查结果: $hasPermission');
      if (!hasPermission) {
        final bleStatus = await BleServiceSimple.checkBleStatus();
        String errorMessage = '蓝牙权限未授予或蓝牙未开启';
        
        switch (bleStatus) {
          case BleStatus.poweredOff:
            errorMessage = '蓝牙已关闭，请在设置中开启蓝牙';
            break;
          case BleStatus.unauthorized:
            errorMessage = '蓝牙权限未授权，请在设置中允许蓝牙权限';
            break;
          case BleStatus.locationServicesDisabled:
            errorMessage = '位置服务已禁用，请在设置中开启位置服务';
            break;
          case BleStatus.unsupported:
            errorMessage = '此设备不支持蓝牙功能';
            break;
          case BleStatus.unknown:
            errorMessage = '位置权限被拒绝，请前往设置 > 隐私与安全性 > 定位服务，允许应用使用位置服务';
            break;
          default:
            errorMessage = '蓝牙权限未授予或蓝牙未开启，请检查设置';
        }
        
        print('❌ 权限检查失败: $errorMessage (状态: $bleStatus)');
        _setError(errorMessage);
        return;
      }
      
      print('✅ 蓝牙权限检查通过，开始设备扫描');

      state = state.copyWith(progress: 0.2);

      // 开始扫描设备 (或在调试模式下模拟)
      if (AppConstants.skipBleScanning && AppConstants.isDebugMode) {
        print('🧪 调试模式：跳过真实BLE扫描，模拟设备连接');
        await _simulateDeviceConnection(deviceData);
      } else {
        print('📡 开始真实BLE设备扫描...');
        await _scanForDevice(deviceData);
      }

    } catch (e) {
      _setError('启动连接失败: $e');
    }
  }

  /// 扫描目标设备
  Future<void> _scanForDevice(BleDeviceData deviceData) async {
    try {
      state = state.copyWith(
        status: BleDeviceStatus.scanning,
        progress: 0.3,
      );

      // 设置扫描超时
      _timeoutTimer = Timer(const Duration(seconds: 30), () {
        if (state.status == BleDeviceStatus.scanning) {
          _setError('扫描超时：未找到目标设备');
        }
      });

      // 开始扫描
      _scanSubscription = BleServiceSimple.scanForDevice(
        targetDeviceId: deviceData.deviceId,
        timeout: const Duration(seconds: 30),
      ).listen(
        (scanResult) {
          // 更新扫描结果
          final updatedResults = [...state.scanResults, scanResult];
          state = state.copyWith(
            scanResults: updatedResults,
            progress: 0.5,
          );

          // 找到目标设备，开始连接
          if (_isTargetDevice(scanResult, deviceData)) {
            _timeoutTimer?.cancel();
            // 在iOS上使用扫描到的设备ID作为连接地址
            final connectionAddress = Platform.isIOS ? scanResult.deviceId : scanResult.address;
            _connectToDevice(deviceData.copyWith(
              bleAddress: connectionAddress, // iOS上这是系统UUID，Android上是MAC地址
              rssi: scanResult.rssi,
            ));
          }
        },
        onError: (error) {
          _setError('扫描错误: $error');
        },
      );

    } catch (e) {
      _setError('扫描失败: $e');
    }
  }

  /// 检查是否为目标设备 - 适配iOS平台特点
  bool _isTargetDevice(SimpleBLEScanResult scanResult, BleDeviceData deviceData) {
    print('🔍 检查设备匹配:');
    print('   扫描到: ${scanResult.name} (${scanResult.deviceId})');
    print('   目标: ${deviceData.deviceName} (${deviceData.deviceId})');
    
    // 优先级1: 服务UUID匹配（最可靠的匹配方式）
    if (scanResult.serviceUuids.isNotEmpty) {
      final targetServiceUuid = BleConstants.serviceUuid.toLowerCase();
      for (final serviceUuid in scanResult.serviceUuids) {
        if (serviceUuid.toLowerCase() == targetServiceUuid) {
          print('✅ 服务UUID匹配: $serviceUuid');
          return true;
        }
      }
    }
    
    // 优先级2: 设备名称智能匹配（去除括号后缀，前缀匹配）
    if (deviceData.deviceName.isNotEmpty && scanResult.name.isNotEmpty) {
      // 清理名称：去除括号及其内容，去除多余空格
      String cleanQrName = deviceData.deviceName
          .replaceAll(RegExp(r'\s*\([^)]*\)\s*'), '') // 去除 (Allwinner) 等后缀
          .trim()
          .toLowerCase();
      
      String cleanScanName = scanResult.name
          .replaceAll(RegExp(r'\s*\([^)]*\)\s*'), '')
          .trim()
          .toLowerCase();
      
      print('   清理后名称: "$cleanQrName" vs "$cleanScanName"');
      
      // 检查前缀匹配（至少8个字符以避免太短的误匹配）
      if (cleanQrName.length >= 8 && cleanScanName.length >= 8) {
        if (cleanQrName == cleanScanName || 
            cleanScanName.startsWith(cleanQrName) ||
            cleanQrName.startsWith(cleanScanName)) {
          print('✅ 设备名称匹配: "$cleanScanName" ≈ "$cleanQrName"');
          return true;
        }
      }
    }
    
    // iOS平台特殊处理：由于无法获取真实MAC地址，跳过地址和设备ID的精确匹配
    // 在iOS上主要依赖服务UUID和名称匹配
    
    print('❌ 设备不匹配');
    return false;
  }

  /// 连接到设备
  Future<void> _connectToDevice(BleDeviceData deviceData) async {
    try {
      await _scanSubscription?.cancel();
      _scanSubscription = null;

      state = state.copyWith(
        status: BleDeviceStatus.connecting,
        progress: 0.6,
        deviceData: deviceData.copyWith(status: BleDeviceStatus.connecting),
      );

      // 连接设备
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

        // 开始认证流程
        _startAuthentication(result);
      } else {
        _setError('连接失败');
      }

    } catch (e) {
      _setError('连接过程出错: $e');
    }
  }

  /// 开始设备认证
  Future<void> _startAuthentication(BleDeviceData deviceData) async {
    try {
      state = state.copyWith(
        status: BleDeviceStatus.authenticating,
        progress: 0.9,
        deviceData: deviceData.copyWith(status: BleDeviceStatus.authenticating),
      );

      // 模拟认证过程（实际实现需要加密握手）
      await Future.delayed(const Duration(seconds: 2));

      // 认证成功
      state = state.copyWith(
        status: BleDeviceStatus.authenticated,
        progress: 1.0,
        deviceData: deviceData.copyWith(status: BleDeviceStatus.authenticated),
      );

    } catch (e) {
      _setError('设备认证失败: $e');
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    await _scanSubscription?.cancel();
    _timeoutTimer?.cancel();
    await BleServiceSimple.disconnect();
    
    state = state.copyWith(
      status: BleDeviceStatus.disconnected,
      progress: 0.0,
    );
  }

  /// 重试连接
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

  /// 模拟设备连接 (仅用于调试和测试)
  Future<void> _simulateDeviceConnection(BleDeviceData deviceData) async {
    try {
      print('📡 模拟扫描阶段...');
      await Future.delayed(const Duration(seconds: 2));
      
      state = state.copyWith(
        status: BleDeviceStatus.connecting,
        progress: 0.4,
      );
      
      print('🔗 模拟连接阶段...');
      await Future.delayed(const Duration(seconds: 3));
      
      state = state.copyWith(
        status: BleDeviceStatus.connected,
        progress: 0.7,
        deviceData: deviceData.copyWith(
          status: BleDeviceStatus.connected,
          connectedAt: DateTime.now(),
        ),
      );
      
      print('🔐 模拟认证阶段...');
      await Future.delayed(const Duration(seconds: 2));
      
      state = state.copyWith(
        status: BleDeviceStatus.authenticated,
        progress: 1.0,
        deviceData: deviceData.copyWith(
          status: BleDeviceStatus.authenticated,
          connectedAt: DateTime.now(),
        ),
      );
      
      print('✅ 模拟连接流程完成！设备已认证');
      
    } catch (e) {
      _setError('模拟连接失败: $e');
    }
  }

  /// 设置错误状态
  void _setError(String message) {
    _timeoutTimer?.cancel();
    _scanSubscription?.cancel();
    
    state = state.copyWith(
      status: BleDeviceStatus.error,
      errorMessage: message,
    );
  }

  /// 重置状态到初始状态
  void reset() {
    _timeoutTimer?.cancel();
    _scanSubscription?.cancel();
    state = const DeviceConnectionState();
  }

  /// 释放资源
  @override
  void dispose() {
    _scanSubscription?.cancel();
    _timeoutTimer?.cancel();
    BleServiceSimple.dispose();
    super.dispose();
  }
}

/// 设备连接Provider
final deviceConnectionProvider = StateNotifierProvider<DeviceConnectionNotifier, DeviceConnectionState>((ref) {
  final notifier = DeviceConnectionNotifier();
  
  // 自动释放资源
  ref.onDispose(() {
    notifier.dispose();
  });
  
  return notifier;
});