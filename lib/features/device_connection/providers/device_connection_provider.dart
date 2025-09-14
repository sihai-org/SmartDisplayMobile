import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/ble_constants.dart';
import '../../../core/crypto/crypto_service.dart';
import '../../../features/qr_scanner/models/device_qr_data.dart';
import '../models/ble_device_data.dart';
import '../models/network_status.dart';
import '../services/ble_service_simple.dart';

/// 设备连接状态数据
class DeviceConnectionState {
  final BleDeviceStatus status;
  final BleDeviceData? deviceData;
  final List<SimpleBLEScanResult> scanResults;
  final String? errorMessage;
  final double progress; // 0.0 - 1.0
  final String? provisionStatus; // A107 最新状态文本
  final List<WifiAp> wifiNetworks; // A103 扫描结果
  final List<String> connectionLogs; // 连接日志
  final NetworkStatus? networkStatus; // A109 网络状态
  final bool isCheckingNetwork; // 是否正在检查网络状态

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

  // 通过 BleServiceSimple 提供的静态方法执行GATT读/写/订阅

  // Using static BLE service methods
  StreamSubscription? _scanSubscription;
  Timer? _timeoutTimer;
  Timer? _periodicScanTimer; // 定期扫描定时器
  StreamSubscription<List<int>>? _provisionStatusSubscription;
  StreamSubscription<List<int>>? _wifiScanResultSubscription;
  StreamSubscription<List<int>>? _handshakeSubscription;
  
  // 加密服务
  CryptoService? _cryptoService;

  // WiFi扫描notify接收标志
  bool _hasReceivedWifiScanNotify = false;

  /// 开始连接流程
  Future<void> startConnection(DeviceQrData qrData) async {
    print('🚀 ==> startConnection 被调用！QR数据: ${qrData.deviceId}');
    try {
      // 重置状态
      state = const DeviceConnectionState();
      _log('初始化连接：${qrData.deviceName} (${qrData.deviceId})');
      
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
      _log('检查权限与蓝牙状态...');
      final hasPermission = await BleServiceSimple.requestPermissions();
      _log('权限检查结果: $hasPermission');
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
        
        _log('权限检查失败: $errorMessage (状态: $bleStatus)');
        _setError(errorMessage);
        return;
      }
      
      _log('权限通过，开始扫描目标设备');

      state = state.copyWith(progress: 0.2);

      // 开始扫描设备 (或在调试模式下模拟)
      if (AppConstants.skipBleScanning && AppConstants.isDebugMode) {
        _log('调试模式：跳过真实BLE扫描，模拟设备连接');
        await _simulateDeviceConnection(deviceData);
      } else {
        _log('开始真实BLE设备扫描（30s超时）');
        await _scanForDevice(deviceData);
      }

    } catch (e) {
      _setError('启动连接失败: $e');
    }
  }

  /// 扫描目标设备 - 每秒扫描一次直到找到匹配设备
  Future<void> _scanForDevice(BleDeviceData deviceData) async {
    try {
      state = state.copyWith(
        status: BleDeviceStatus.scanning,
        progress: 0.3,
      );
      _log('开始定期扫描... 目标: ${deviceData.deviceName} (${deviceData.deviceId})');

      // 设置总体超时（30秒）
      _timeoutTimer = Timer(const Duration(seconds: 30), () {
        if (state.status == BleDeviceStatus.scanning) {
          _log('扫描超时：未找到目标设备');
          _stopPeriodicScanning();
          _setError('扫描超时：未找到目标设备');
        }
      });

      // 开始每秒扫描一次
      _startPeriodicScanning(deviceData);

    } catch (e) {
      _setError('开始扫描失败: $e');
    }
  }

  /// 开始每秒定期扫描
  void _startPeriodicScanning(BleDeviceData deviceData) {
    _log('启动每秒定期扫描');
    
    // 立即进行第一次扫描
    _performSingleScan(deviceData);
    
    // 设置定期扫描定时器
    _periodicScanTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.status == BleDeviceStatus.scanning) {
        _performSingleScan(deviceData);
      } else {
        timer.cancel();
      }
    });
  }

  /// 执行单次扫描（扫描2秒）
  void _performSingleScan(BleDeviceData deviceData) {
    _log('执行单次BLE扫描...');
    
    // 取消之前的扫描
    _scanSubscription?.cancel();
    
    // 开始新的扫描
    _scanSubscription = BleServiceSimple.scanForDevice(
      targetDeviceId: deviceData.deviceId,
      timeout: const Duration(seconds: 2), // 每次扫描2秒
    ).listen(
      (scanResult) {
        _log('发现设备: ${scanResult.name} (${scanResult.deviceId}), RSSI=${scanResult.rssi}');
        
        // 更新扫描结果（避免重复）
        final existingResults = state.scanResults;
        final isNewResult = !existingResults.any((r) => r.deviceId == scanResult.deviceId);
        
        if (isNewResult) {
          final updatedResults = [...existingResults, scanResult];
          state = state.copyWith(
            scanResults: updatedResults,
            progress: 0.4 + (updatedResults.length * 0.02), // 根据找到设备数量增加进度
          );
        }

        // 检查是否匹配目标设备
        if (_isTargetDevice(scanResult, deviceData)) {
          _log('🎯 找到匹配设备！停止扫描，准备连接');
          _stopPeriodicScanning();
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
        _log('单次扫描出错: $error');
      },
    );
  }

  /// 停止定期扫描
  void _stopPeriodicScanning() {
    _log('停止定期扫描');
    _periodicScanTimer?.cancel();
    _periodicScanTimer = null;
    _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  /// 检查是否为目标设备 - 更宽松的匹配策略用于调试
  bool _isTargetDevice(SimpleBLEScanResult scanResult, BleDeviceData deviceData) {
    final scanDeviceName = scanResult.name.isNotEmpty ? scanResult.name : '[无名称]';
    print('🔍 检查设备匹配:');
    print('   扫描到: $scanDeviceName (${scanResult.deviceId})');
    print('   目标: ${deviceData.deviceName} (${deviceData.deviceId})');
    print('   扫描到的服务UUID: ${scanResult.serviceUuids}');
    print('   扫描设备RSSI: ${scanResult.rssi}');
    print('   扫描设备可连接: ${scanResult.connectable}');
    
    // 优先级1: 服务UUID匹配（最可靠的匹配方式）
    if (scanResult.serviceUuids.isNotEmpty) {
      final targetServiceUuid = BleConstants.serviceUuid.toLowerCase();
      for (final serviceUuid in scanResult.serviceUuids) {
        if (serviceUuid.toLowerCase() == targetServiceUuid) {
          print('✅ 服务UUID匹配: $serviceUuid -> 这是我们的目标设备!');
          return true;
        }
      }
      print('⚠️  服务UUID不匹配，期望: $targetServiceUuid');
      print('   实际UUID列表: ${scanResult.serviceUuids}');
    } else {
      print('⚠️  扫描结果中没有服务UUID');
    }
    
    // 优先级2: 设备名称精确匹配（现在TV端已恢复广播统一格式的设备名称 AI-TV-XXXX）
    if (deviceData.deviceName.isNotEmpty && scanResult.name.isNotEmpty) {
      final qrDeviceName = deviceData.deviceName.trim();
      final scanDeviceName = scanResult.name.trim();
      
      print('   精确名称比较: "$qrDeviceName" vs "$scanDeviceName"');
      
      // 由于现在使用统一的 AI-TV-XXXX 格式，可以直接精确匹配
      if (qrDeviceName == scanDeviceName) {
        print('✅ 设备名称精确匹配: "$scanDeviceName"');
        return true;
      } else {
        // 如果名称格式都是 AI-TV-XXXX，但后缀不匹配，说明是不同设备
        if (qrDeviceName.startsWith('AI-TV-') && scanDeviceName.startsWith('AI-TV-')) {
          print('⚠️  AI-TV设备但ID不匹配: "$scanDeviceName" != "$qrDeviceName"');
        } else {
          print('⚠️  设备名称不匹配: "$scanDeviceName" != "$qrDeviceName"');
        }
      }
    } else if (scanResult.name.isEmpty) {
      print('⚠️  扫描到的设备无名称');
    }
    
    // 优先级3: 临时调试 - 匹配所有AI-TV开头的设备
    if (scanResult.name.isNotEmpty && scanResult.name.startsWith('AI-TV')) {
      print('🧪 调试模式: 发现AI-TV设备 "${scanResult.name}" - 暂时匹配以便测试');
      return true;
    }
    
    // 优先级4: 临时调试 - 如果QR码设备名称也是AI-TV格式，尝试宽松匹配
    if (deviceData.deviceName.startsWith('AI-TV') && scanResult.name.isNotEmpty) {
      print('🧪 调试模式: QR设备名称是 "${deviceData.deviceName}"，扫描到 "${scanResult.name}" - 检查是否相似');
      if (scanResult.name.toLowerCase().contains('ai') || scanResult.name.toLowerCase().contains('tv')) {
        print('🧪 调试匹配: 设备名称包含相关关键词，暂时匹配');
        return true;
      }
    }
    
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
      _log('开始连接: addr=${deviceData.bleAddress}');

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
        _log('BLE 连接成功，准备认证');

        // 初始化GATT会话（读取设备信息/订阅状态通知）并开始认证流程
        await _initGattSession(result);
        await _startAuthentication(result);
      } else {
        _log('连接失败');
        _setError('连接失败');
      }

    } catch (e) {
      _log('连接过程出错: $e');
      _setError('连接过程出错: $e');
    }
  }

  /// 初始化GATT会话：读取A101并订阅A107
  Future<void> _initGattSession(BleDeviceData deviceData) async {
    try {
      final deviceId = deviceData.bleAddress; // iOS为系统UUID，Android为MAC/系统ID

      // 读取 A101 Device_Info（可用于校验）
      final infoBytes = await BleServiceSimple.readCharacteristic(
        deviceId: deviceId,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.deviceInfoCharUuid,
      );
      if (infoBytes != null) {
        final infoStr = utf8.decode(infoBytes);
        print('📖 读取Device_Info成功: $infoStr');
      } else {
        print('⚠️  读取Device_Info失败');
      }

      // 订阅 A107 Provision_Status 通知
      _provisionStatusSubscription?.cancel();
      _provisionStatusSubscription = BleServiceSimple
          .subscribeToCharacteristic(
            deviceId: deviceId,
            serviceUuid: BleConstants.serviceUuid,
            characteristicUuid: BleConstants.provisionStatusCharUuid,
          )
          .listen((data) {
        final status = utf8.decode(data);
        print('🔔 收到Provision_Status通知: $status');
        // 更新状态与进度
        double newProgress = state.progress;
        switch (status.toLowerCase()) {
          case 'connecting':
            newProgress = 0.95;
            break;
          case 'connected':
            newProgress = 0.8;
            break;
          case 'failed':
            _setError('配网失败');
            return;
        }
        state = state.copyWith(provisionStatus: status, progress: newProgress);
      }, onError: (e) {
        print('❌ 订阅Provision_Status出错: $e');
      });

      // 订阅 A103 Wi‑Fi 扫描结果
      _wifiScanResultSubscription?.cancel();
      _wifiScanResultSubscription = BleServiceSimple
          .subscribeToCharacteristic(
            deviceId: deviceId,
            serviceUuid: BleConstants.serviceUuid,
            characteristicUuid: BleConstants.wifiScanResultCharUuid,
          )
          .listen((_) async {
        // 标记已收到WiFi扫描结果notify
        _hasReceivedWifiScanNotify = true;

        // 为避免通知被MTU截断，收到任意通知后改为主动读取完整值
        try {
          final full = await BleServiceSimple.readCharacteristic(
            deviceId: deviceId,
            serviceUuid: BleConstants.serviceUuid,
            characteristicUuid: BleConstants.wifiScanResultCharUuid,
          );
          if (full != null) {
            final json = utf8.decode(full);
            print('📶 读取Wi‑Fi扫描结果(JSON ${json.length}B) [notify触发]');
            final parsed = _parseWifiScanJson(json);
            state = state.copyWith(wifiNetworks: parsed);
          }
        } catch (e) {
          print('❌ 读取Wi‑Fi扫描结果失败: $e');
        }
      }, onError: (e) {
        print('❌ 订阅Wi‑Fi扫描结果出错: $e');
      });

      // 移除自动WiFi扫描 - 改为在首页根据网络状态按需触发
      // await requestWifiScan();
    } catch (e) {
      print('❌ 初始化GATT会话失败: $e');
    }
  }

  /// 发送WiFi凭证（简化接口）
  Future<bool> sendWifiCredentials(String ssid, String password) async {
    return await sendProvisionRequest(ssid: ssid, password: password);
  }

  /// 发送配网请求（写入A106），供UI调用
  Future<bool> sendProvisionRequest({
    required String ssid,
    required String password,
  }) async {
    if (state.deviceData == null) return false;
    try {
      final deviceId = state.deviceData!.bleAddress;
      final payload = '{"ssid":"${_escapeJson(ssid)}","password":"${_escapeJson(password)}"}';
      final data = payload.codeUnits;
      final ok = await BleServiceSimple.writeCharacteristic(
        deviceId: deviceId,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.provisionRequestCharUuid,
        data: data,
        withResponse: true,
      );
      print(ok ? '📤 已写入Provision_Request: $payload' : '❌ 写入Provision_Request失败');
      return ok;
    } catch (e) {
      print('❌ 发送配网请求异常: $e');
      return false;
    }
  }

  /// 触发Wi‑F扫描（写入A102）
  Future<bool> requestWifiScan() async {
    if (state.deviceData == null) return false;
    try {
      // 重置notify接收标志
      _hasReceivedWifiScanNotify = false;
      final ok = await BleServiceSimple.writeCharacteristic(
        deviceId: state.deviceData!.bleAddress,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.wifiScanRequestCharUuid,
        data: '{}'.codeUnits,
        withResponse: true,
      );
      if (ok) {
        print('📤 已写入Wi‑Fi扫描请求');
        // 智能防御：只在未收到notify时进行防御性读取
        Future.delayed(const Duration(milliseconds: 800), () async {
          if (!_hasReceivedWifiScanNotify) {
            print('⚠️ 未收到WiFi扫描notify，执行防御性读取');
            try {
              final full = await BleServiceSimple.readCharacteristic(
                deviceId: state.deviceData!.bleAddress,
                serviceUuid: BleConstants.serviceUuid,
                characteristicUuid: BleConstants.wifiScanResultCharUuid,
              );
              if (full != null && full.isNotEmpty) {
                final json = utf8.decode(full);
                final parsed = _parseWifiScanJson(json);
                state = state.copyWith(wifiNetworks: parsed);
                print('📶 防御性读取Wi‑F列表(${parsed.length}项) [notify丢失]');
              }
            } catch (e) {
              print('❌ 防御性读取A103失败: $e');
            }
          } else {
            print('✅ 已收到WiFi扫描notify，跳过防御性读取');
          }
        });
      }
      return ok;
    } catch (e) {
      print('❌ 写入Wi‑Fi扫描请求失败: $e');
      return false;
    }
  }

  List<WifiAp> _parseWifiScanJson(String json) {
    try {
      final list = (jsonDecode(json) as List<dynamic>);
      return list.map((item) {
        if (item is String) {
          // 极简模式：仅 SSID 字符串
          return WifiAp(ssid: item, rssi: 0, secure: false);
        } else if (item is Map<String, dynamic>) {
          return WifiAp(
            ssid: (item['ssid'] ?? '').toString(),
            rssi: int.tryParse(item['rssi']?.toString() ?? '') ?? 0,
            secure: item['secure'] == true || item['secure']?.toString() == 'true',
            bssid: (item['bssid'] as String?)?.toString(),
            frequency: item['frequency'] == null ? null : int.tryParse(item['frequency'].toString()),
          );
        } else {
          return const WifiAp(ssid: '', rssi: 0, secure: false);
        }
      }).where((ap) => ap.ssid.isNotEmpty).toList();
    } catch (e) {
      print('⚠️  解析Wi‑Fi扫描JSON失败: $e');
      return const [];
    }
  }

  String _escapeJson(String s) => s
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');

  /// 检查设备当前网络连接状态 (读取A109特征)
  Future<NetworkStatus?> checkNetworkStatus() async {
    if (state.deviceData == null) {
      _log('检查网络状态失败：设备未连接');
      return null;
    }

    try {
      state = state.copyWith(isCheckingNetwork: true);
      _log('正在检查设备网络状态...');

      final deviceId = state.deviceData!.bleAddress;
      final data = await BleServiceSimple.readCharacteristic(
        deviceId: deviceId,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.networkStatusCharUuid,
      );

      if (data != null && data.isNotEmpty) {
        final networkStatus = NetworkStatusParser.fromBleData(data);
        if (networkStatus != null) {
          state = state.copyWith(
            networkStatus: networkStatus,
            isCheckingNetwork: false,
          );

          final statusText = networkStatus.connected
            ? '已连网: ${networkStatus.displaySsid} (${networkStatus.signalDescription})'
            : '未连网';
          _log('网络状态检查完成: $statusText');

          return networkStatus;
        } else {
          _log('解析网络状态数据失败');
        }
      } else {
        _log('读取网络状态特征失败 - 可能TV端不支持A109特征');
      }

      state = state.copyWith(isCheckingNetwork: false);
      return null;

    } catch (e) {
      _log('检查网络状态异常: $e');
      state = state.copyWith(isCheckingNetwork: false);
      return null;
    }
  }

  /// 智能WiFi处理：根据网络状态决定是否扫描WiFi
  Future<void> handleWifiSmartly() async {
    _log('开始智能WiFi处理...');

    // 首先检查网络状态
    final networkStatus = await checkNetworkStatus();

    if (networkStatus == null) {
      // 无法获取网络状态，回退到原有模式：直接扫描WiFi
      _log('无法获取网络状态，回退到WiFi扫描模式');
      await requestWifiScan();
    } else if (networkStatus.connected) {
      // 设备已连网，显示当前网络信息
      _log('设备已连网，显示当前网络状态');
      // UI会根据networkStatus自动显示网络信息
    } else {
      // 设备未连网，自动获取WiFi列表
      _log('设备未连网，自动获取WiFi列表');
      await requestWifiScan();
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
      _log('开始真实认证流程...');

      // 初始化加密服务
      _cryptoService = CryptoService();
      await _cryptoService!.generateEphemeralKeyPair();
      _log('加密服务初始化完成');

      // 订阅握手响应
      await _subscribeToHandshakeResponse(deviceData);
      
      // 发起握手请求
      await _initiateHandshake(deviceData);

    } catch (e) {
      _log('设备认证失败: $e');
      _setError('设备认证失败: $e');
    }
  }

  /// 订阅握手响应
  Future<void> _subscribeToHandshakeResponse(BleDeviceData deviceData) async {
    try {
      final deviceId = deviceData.bleAddress;
      
      _handshakeSubscription = BleServiceSimple
          .subscribeToCharacteristic(
            deviceId: deviceId,
            serviceUuid: BleConstants.serviceUuid,
            characteristicUuid: BleConstants.secureHandshakeCharUuid,
          )
          .listen((data) async {
        try {
          final responseJson = utf8.decode(data);
          _log('收到握手响应: ${responseJson.length}字节');
          
          // 解析握手响应
          final response = _cryptoService!.parseHandshakeResponse(responseJson);
          
          // 执行密钥交换
          await _cryptoService!.performKeyExchange(
            remotePublicKeyBytes: response.publicKey,
            devicePublicKey: deviceData.publicKey,
          );
          
          // 握手成功，标记为已认证
          state = state.copyWith(
            status: BleDeviceStatus.authenticated,
            progress: 1.0,
            deviceData: deviceData.copyWith(status: BleDeviceStatus.authenticated),
          );
          _log('🎉 真实认证完成，安全会话已建立');
          
        } catch (e) {
          _log('处理握手响应失败: $e');
          _setError('认证失败: $e');
        }
      }, onError: (e) {
        _log('握手订阅出错: $e');
        _setError('认证通信失败: $e');
      });
      
    } catch (e) {
      _log('订阅握手响应失败: $e');
      throw e;
    }
  }

  /// 发起握手请求
  Future<void> _initiateHandshake(BleDeviceData deviceData) async {
    try {
      final deviceId = deviceData.bleAddress;
      final handshakeInit = await _cryptoService!.getHandshakeInitData();
      
      final success = await BleServiceSimple.writeCharacteristic(
        deviceId: deviceId,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.secureHandshakeCharUuid,
        data: handshakeInit.codeUnits,
        withResponse: true,
      );
      
      if (success) {
        _log('握手请求已发送');
      } else {
        throw Exception('发送握手请求失败');
      }
      
    } catch (e) {
      _log('发起握手失败: $e');
      throw e;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    _stopPeriodicScanning();
    await _scanSubscription?.cancel();
    _timeoutTimer?.cancel();
    await _provisionStatusSubscription?.cancel();
    await _wifiScanResultSubscription?.cancel();
    await _handshakeSubscription?.cancel();
    
    // 清理加密服务
    _cryptoService?.cleanup();
    _cryptoService = null;
    
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
      connectionLogs: [...state.connectionLogs, _ts() + ' ❌ ' + message],
    );
  }

  void _log(String msg) {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final line = '[$h:$m:$s] ' + msg;
    print(line);
    state = state.copyWith(connectionLogs: [...state.connectionLogs, line]);
  }

  String _ts() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '[$h:$m:$s]';
  }

  /// 重置状态到初始状态
  void reset() {
    _timeoutTimer?.cancel();
    _periodicScanTimer?.cancel();
    _scanSubscription?.cancel();
    _provisionStatusSubscription?.cancel();
    _wifiScanResultSubscription?.cancel();
    _handshakeSubscription?.cancel();

    // 重置WiFi扫描notify标志
    _hasReceivedWifiScanNotify = false;

    // 清理加密服务
    _cryptoService?.cleanup();
    _cryptoService = null;

    state = const DeviceConnectionState();
  }

  /// 释放资源
  @override
  void dispose() {
    _scanSubscription?.cancel();
    _timeoutTimer?.cancel();
    _periodicScanTimer?.cancel();
    _provisionStatusSubscription?.cancel();
    _wifiScanResultSubscription?.cancel();
    _handshakeSubscription?.cancel();

    // 重置WiFi扫描notify标志
    _hasReceivedWifiScanNotify = false;

    // 清理加密服务
    _cryptoService?.cleanup();
    _cryptoService = null;

    BleServiceSimple.dispose();
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

/// 设备连接Provider
final deviceConnectionProvider = StateNotifierProvider<DeviceConnectionNotifier, DeviceConnectionState>((ref) {
  final notifier = DeviceConnectionNotifier();
  
  // 自动释放资源
  ref.onDispose(() {
    notifier.dispose();
  });
  
  return notifier;
});
