import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../core/providers/app_state_provider.dart';
import '../../features/device_connection/models/ble_device_data.dart';
import '../../features/device_connection/providers/device_connection_provider.dart';
import '../../features/device_connection/services/ble_service_simple.dart';
import '../../features/qr_scanner/models/device_qr_data.dart';
import '../../features/qr_scanner/providers/qr_scanner_provider.dart';

class DeviceConnectionPage extends ConsumerStatefulWidget {
  const DeviceConnectionPage({super.key, required this.deviceId});
  
  final String deviceId;

  @override
  ConsumerState<DeviceConnectionPage> createState() => _DeviceConnectionPageState();
}

class _DeviceConnectionPageState extends ConsumerState<DeviceConnectionPage> {
  Timer? _scanTimer;
  StreamSubscription<SimpleBLEScanResult>? _currentScanSubscription;
  bool _isScanning = false;
  DateTime? _lastScanTime;  // 防抖：记录上次扫描时间
  static const Duration _scanCooldown = Duration(milliseconds: 500);  // 500ms防抖间隔

  @override
  void initState() {
    super.initState();
    
    // 设置ref.listen监听器（仅注册一次）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 监听连接状态，认证成功后跳转
      ref.listen<DeviceConnectionState>(deviceConnectionProvider, (previous, current) {
        if (current.status == BleDeviceStatus.authenticated && current.deviceData != null) {
          context.go('${AppRoutes.wifiSelection}?deviceId=${Uri.encodeComponent(current.deviceData!.deviceId)}');
        }
      });
      
      // 从全局状态获取QR扫描结果（仅显示信息，不启动连接）
      final deviceData = ref.read(appStateProvider.notifier).getDeviceDataById(widget.deviceId);
      if (deviceData == null) {
        // 如果没有扫描数据，显示错误并返回扫描页面
        _showNoDataError();
      } else {
        // 不再自动启动扫描，改为手动触发
        print('📱 设备连接页面已加载，可手动启动BLE扫描');
      }
    });
  }

  @override
  void dispose() {
    // 幂等清理：确保多次调用安全
    _stopCurrentScanSync();
    _scanTimer?.cancel();
    _scanTimer = null;  // 避免重复取消
    super.dispose();
  }

  /// 停止当前扫描 (异步版本)
  Future<void> _stopCurrentScan() async {
    if (_currentScanSubscription != null) {
      print('🛑 停止当前BLE扫描');
      await _currentScanSubscription?.cancel();
      _currentScanSubscription = null;
      _isScanning = false;
    }
    
    // 调用BLE服务的停止扫描方法
    await BleServiceSimple.stopScan();
  }

  /// 停止当前扫描 (同步版本 - 用于dispose等不能await的场景)
  void _stopCurrentScanSync() {
    if (_currentScanSubscription != null) {
      print('🛑 停止当前BLE扫描 (同步)');
      _currentScanSubscription?.cancel();
      _currentScanSubscription = null;
    }
    
    // 幂等设置状态
    if (_isScanning) {
      _isScanning = false;
      print('📴 已重置扫描状态');
    }
    
    // 同步调用BLE服务的停止扫描方法（幂等操作）
    BleServiceSimple.stopScan();
  }

  /// 显示无数据错误
  void _showNoDataError() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误'),
        content: const Text('未找到设备数据，请重新扫描二维码。'),
        actions: [
          TextButton(
            onPressed: () {
              context.go(AppRoutes.qrScanner);
            },
            child: const Text('重新扫描'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(deviceConnectionProvider);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('连接设备'),
        elevation: 0,
        backgroundColor: Colors.white,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48, // 减去padding
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 设备信息卡片
                    _buildDeviceInfoCard(connectionState),
                    
                    const SizedBox(height: 32),
                    
                    // 连接进度
                    _buildConnectionProgress(connectionState),
                    
                    const SizedBox(height: 32),
                    
                    // 蓝牙扫描结果 (调试用) - 始终显示
                    _buildBleScanResults(connectionState),
                    
                    const SizedBox(height: 32),
                    
                    // 状态信息
                    _buildStatusInfo(connectionState),
                    
                    const SizedBox(height: 32),
                    
                    // 操作按钮
                    _buildActionButtons(connectionState),
                    
                    const SizedBox(height: 24), // 底部留白
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 构建设备信息卡片
  Widget _buildDeviceInfoCard(DeviceConnectionState state) {
    // 从全局状态获取QR扫描的设备数据
    final qrDeviceData = ref.read(appStateProvider.notifier).getDeviceDataById(widget.deviceId);
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.tv,
                    color: Colors.grey,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        qrDeviceData?.deviceName ?? '智能显示器',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${qrDeviceData?.deviceId ?? widget.deviceId}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.info_outline,
                  color: Colors.blue,
                  size: 24,
                ),
              ],
            ),
            if (qrDeviceData != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              _buildDeviceDetail('设备类型', qrDeviceData.deviceType),
              _buildDeviceDetail('BLE地址', qrDeviceData.bleAddress),
              if (qrDeviceData.firmwareVersion != null)
                _buildDeviceDetail('固件版本', qrDeviceData.firmwareVersion!),
              if (qrDeviceData.timestamp != null)
                _buildDeviceDetail('创建时间', 
                  DateTime.fromMillisecondsSinceEpoch(qrDeviceData.timestamp!).toString().substring(0, 19)),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建设备详情行
  Widget _buildDeviceDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建连接进度
  Widget _buildConnectionProgress(DeviceConnectionState state) {
    // 检查是否有QR扫描数据
    final qrDeviceData = ref.read(appStateProvider.notifier).getDeviceDataById(widget.deviceId);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              qrDeviceData != null ? '设备信息' : '连接进度',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (qrDeviceData != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '已就绪',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              Text(
                '${(state.progress * 100).round()}%',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (qrDeviceData != null) ...[
          Container(
            width: double.infinity,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 12,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                '设备信息已解析完成',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ] else ...[
          LinearProgressIndicator(
            value: state.progress,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation(_getStatusColor(state.status)),
            minHeight: 6,
          ),
          const SizedBox(height: 16),
          _buildProgressSteps(state),
        ],
      ],
    );
  }

  /// 构建进度步骤
  Widget _buildProgressSteps(DeviceConnectionState state) {
    final steps = [
      ('检查权限', BleDeviceStatus.disconnected),
      ('扫描设备', BleDeviceStatus.scanning),
      ('建立连接', BleDeviceStatus.connecting),
      ('设备认证', BleDeviceStatus.authenticating),
      ('连接完成', BleDeviceStatus.authenticated),
    ];

    return Column(
      children: steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;
        final isActive = _getStepIndex(state.status) >= index;
        final isCurrent = _getStepIndex(state.status) == index;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isActive 
                    ? _getStatusColor(state.status) 
                    : Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: isActive
                  ? Icon(
                      isCurrent ? Icons.radio_button_checked : Icons.check,
                      color: Colors.white,
                      size: 12,
                    )
                  : null,
              ),
              const SizedBox(width: 12),
              Text(
                step.$1,
                style: TextStyle(
                  fontSize: 14,
                  color: isActive ? Colors.black87 : Colors.grey[500],
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 获取步骤索引
  int _getStepIndex(BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.disconnected:
        return 0;
      case BleDeviceStatus.scanning:
        return 1;
      case BleDeviceStatus.connecting:
        return 2;
      case BleDeviceStatus.connected:
        return 2;
      case BleDeviceStatus.authenticating:
        return 3;
      case BleDeviceStatus.authenticated:
        return 4;
      case BleDeviceStatus.error:
      case BleDeviceStatus.timeout:
        return 0;
    }
  }

  /// 构建状态信息
  Widget _buildStatusInfo(DeviceConnectionState state) {
    // 检查是否有QR扫描数据
    final qrDeviceData = ref.read(appStateProvider.notifier).getDeviceDataById(widget.deviceId);
    
    if (qrDeviceData != null) {
      // 显示设备信息模式的状态
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.blue.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.info_outline,
              color: Colors.blue,
              size: 20,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                '设备信息显示完成，点击"开始连接"按钮启动BLE连接',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // 原有的连接状态显示
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getStatusColor(state.status).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getStatusColor(state.status).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _getStatusIcon(state.status).icon,
            color: _getStatusColor(state.status),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _getStatusMessage(state),
              style: TextStyle(
                fontSize: 14,
                color: _getStatusColor(state.status),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建操作按钮
  Widget _buildActionButtons(DeviceConnectionState state) {
    // 检查是否有QR扫描数据
    final qrDeviceData = ref.read(appStateProvider.notifier).getDeviceDataById(widget.deviceId);
    
    // 如果有QR数据且未开始连接，显示"开始连接"按钮
    if (qrDeviceData != null && state.status == BleDeviceStatus.disconnected) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                // 使用QR数据开始连接
                ref.read(deviceConnectionProvider.notifier).startConnection(qrDeviceData);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('开始连接'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: () {
                // 清理全局状态
                ref.read(appStateProvider.notifier).clearScannedDeviceData();
                ref.read(deviceConnectionProvider.notifier).reset();
                ref.read(qrScannerProvider.notifier).reset();
                // 返回扫描页面
                context.go(AppRoutes.qrScanner);
              },
              child: const Text('返回扫描'),
            ),
          ),
        ],
      );
    }
    
    if (state.status == BleDeviceStatus.error) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => ref.read(deviceConnectionProvider.notifier).retry(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('重试连接'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: () {
                // 清理全局状态和设备连接状态
                ref.read(appStateProvider.notifier).clearScannedDeviceData();
                ref.read(deviceConnectionProvider.notifier).reset();
                // 清理QR扫描器状态 (为了重新开始扫描)
                ref.read(qrScannerProvider.notifier).reset();
                // 返回扫描页面
                context.go(AppRoutes.qrScanner);
              },
              child: const Text('返回扫描'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: () {
                // 临时跳过权限检查，直接跳转到Wi-Fi选择页面进行测试
                context.go('${AppRoutes.wifiSelection}?deviceId=${Uri.encodeComponent(widget.deviceId)}');
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.orange.withOpacity(0.1),
              ),
              child: const Text('跳过权限检查（测试用）', style: TextStyle(color: Colors.orange)),
            ),
          ),
        ],
      );
    }

    if (state.status == BleDeviceStatus.authenticated) {
      return SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: () {
            context.go('${AppRoutes.wifiSelection}?deviceId=${Uri.encodeComponent(state.deviceData!.deviceId)}');
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('继续配网'),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: TextButton(
        onPressed: () async {
          await ref.read(deviceConnectionProvider.notifier).disconnect();
          if (mounted) context.go(AppRoutes.qrScanner);
        },
        child: const Text('取消连接'),
      ),
    );
  }

  /// 获取状态颜色
  Color _getStatusColor(BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.disconnected:
        return Colors.grey;
      case BleDeviceStatus.scanning:
        return Colors.blue;
      case BleDeviceStatus.connecting:
        return Colors.orange;
      case BleDeviceStatus.connected:
        return Colors.orange;
      case BleDeviceStatus.authenticating:
        return Colors.purple;
      case BleDeviceStatus.authenticated:
        return Colors.green;
      case BleDeviceStatus.error:
        return Colors.red;
      case BleDeviceStatus.timeout:
        return Colors.red;
    }
  }

  /// 获取状态图标
  Icon _buildStatusIcon(BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.disconnected:
        return const Icon(Icons.bluetooth_disabled, color: Colors.grey, size: 24);
      case BleDeviceStatus.scanning:
        return const Icon(Icons.bluetooth_searching, color: Colors.blue, size: 24);
      case BleDeviceStatus.connecting:
        return const Icon(Icons.bluetooth_connected, color: Colors.orange, size: 24);
      case BleDeviceStatus.connected:
        return const Icon(Icons.bluetooth_connected, color: Colors.orange, size: 24);
      case BleDeviceStatus.authenticating:
        return const Icon(Icons.security, color: Colors.purple, size: 24);
      case BleDeviceStatus.authenticated:
        return const Icon(Icons.check_circle, color: Colors.green, size: 24);
      case BleDeviceStatus.error:
        return const Icon(Icons.error, color: Colors.red, size: 24);
      case BleDeviceStatus.timeout:
        return const Icon(Icons.timer_off, color: Colors.red, size: 24);
    }
  }

  /// 获取状态图标
  Icon _getStatusIcon(BleDeviceStatus status) {
    return _buildStatusIcon(status);
  }

  /// 获取状态消息
  String _getStatusMessage(DeviceConnectionState state) {
    if (state.errorMessage != null) {
      return state.errorMessage!;
    }
    
    switch (state.status) {
      case BleDeviceStatus.disconnected:
        return '准备开始连接...';
      case BleDeviceStatus.scanning:
        return '正在扫描设备...';
      case BleDeviceStatus.connecting:
        return '正在建立BLE连接...';
      case BleDeviceStatus.connected:
        return 'BLE连接已建立';
      case BleDeviceStatus.authenticating:
        return '正在进行设备认证...';
      case BleDeviceStatus.authenticated:
        return '设备连接和认证成功！';
      case BleDeviceStatus.error:
        return '连接失败，请重试';
      case BleDeviceStatus.timeout:
        return '连接超时';
    }
  }

  /// 构建蓝牙扫描结果列表 (调试用)
  Widget _buildBleScanResults(DeviceConnectionState state) {
    final qrDeviceData = ref.read(appStateProvider.notifier).getDeviceDataById(widget.deviceId);
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bluetooth_searching, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(
                  '蓝牙扫描结果 (${state.scanResults.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // 定时扫描开关
                ElevatedButton.icon(
                  onPressed: () {
                    if (_scanTimer != null) {
                      // 停止定时扫描
                      _scanTimer?.cancel();
                      _scanTimer = null;
                      _stopCurrentScanSync();
                    } else {
                      // 启动定时扫描
                      _startPeriodicBLEScan();
                    }
                    setState(() {}); // 更新UI
                  },
                  icon: Icon(
                    _scanTimer != null ? Icons.timer_off : Icons.timer,
                    size: 16,
                  ),
                  label: Text(_scanTimer != null ? '停止' : '自动'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    backgroundColor: _scanTimer != null ? Colors.orange : Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 手动扫描按钮
                ElevatedButton.icon(
                  onPressed: _isScanning ? null : () {
                    _performBLEScan();
                  },
                  icon: _isScanning 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.search, size: 16),
                  label: Text(_isScanning ? '扫描中' : '扫描'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (qrDeviceData != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '目标设备 (来自QR码)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '设备ID: ${qrDeviceData.deviceId}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    Text(
                      'BLE地址: ${qrDeviceData.bleAddress}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    Text(
                      '设备名称: ${qrDeviceData.deviceName}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            // 扫描结果列表
            if (state.scanResults.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.bluetooth_disabled,
                      color: Colors.grey[600],
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.status == BleDeviceStatus.scanning 
                          ? '正在扫描蓝牙设备...'
                          : '暂无扫描结果 (点击"开始连接"开始扫描)',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...state.scanResults.asMap().entries.map((entry) {
              final index = entry.key;
              final scanResult = entry.value;
              final isTarget = qrDeviceData != null && _isMatchingDevice(scanResult, qrDeviceData);
              
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isTarget 
                    ? Colors.green.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isTarget ? Colors.green : Colors.grey.withOpacity(0.2),
                    width: isTarget ? 2 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.bluetooth,
                          color: isTarget ? Colors.green : Colors.grey[600],
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '设备 ${index + 1}${isTarget ? ' (匹配!)' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isTarget ? FontWeight.bold : FontWeight.normal,
                            color: isTarget ? Colors.green : Colors.black87,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${scanResult.rssi} dBm',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ID: ${scanResult.deviceId}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    Text(
                      '名称: ${scanResult.name}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    Text(
                      '地址: ${scanResult.address}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    Text(
                      '扫描时间: ${scanResult.timestamp.toString().substring(11, 19)}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    Text(
                      '可连接: ${scanResult.connectable ? '是' : '否'}',
                      style: TextStyle(
                        fontSize: 12, 
                        fontFamily: 'monospace',
                        color: scanResult.connectable ? Colors.green : Colors.orange,
                      ),
                    ),
                    if (scanResult.serviceUuids.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '服务UUID (${scanResult.serviceUuids.length}):',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      ...scanResult.serviceUuids.take(3).map((uuid) => Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Text(
                          '• ${uuid}',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                      )),
                      if (scanResult.serviceUuids.length > 3)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Text(
                            '• ... 还有 ${scanResult.serviceUuids.length - 3} 个',
                            style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                          ),
                        ),
                    ],
                    if (scanResult.manufacturerData != null && scanResult.manufacturerData!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '制造商数据 (${scanResult.manufacturerData!.length}):',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      ...scanResult.manufacturerData!.entries.take(2).map((entry) => Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Text(
                          '• ID ${entry.key}: ${entry.value.toString().length > 20 ? '${entry.value.toString().substring(0, 20)}...' : entry.value.toString()}',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                      )),
                      if (scanResult.manufacturerData!.length > 2)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Text(
                            '• ... 还有 ${scanResult.manufacturerData!.length - 2} 个',
                            style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                          ),
                        ),
                    ],
                    if (scanResult.serviceData != null && scanResult.serviceData!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '服务数据 (${scanResult.serviceData!.length}):',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      ...scanResult.serviceData!.entries.take(2).map((entry) => Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Text(
                          '• ${entry.key}: [${entry.value.length} bytes]',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        ),
                      )),
                      if (scanResult.serviceData!.length > 2)
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Text(
                            '• ... 还有 ${scanResult.serviceData!.length - 2} 个',
                            style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                          ),
                        ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  /// 检查扫描结果是否与目标设备匹配
  bool _isMatchingDevice(SimpleBLEScanResult scanResult, DeviceQrData qrDeviceData) {
    // 检查设备ID匹配
    if (scanResult.deviceId == qrDeviceData.deviceId) return true;
    
    // 检查BLE地址匹配
    if (scanResult.address == qrDeviceData.bleAddress) return true;
    
    // 检查设备名称匹配
    if (scanResult.name.contains(qrDeviceData.deviceName) || 
        qrDeviceData.deviceName.contains(scanResult.name)) {
      return true;
    }
    
    return false;
  }

  /// 启动定期蓝牙扫描
  void _startPeriodicBLEScan() {
    // 确保先停止任何现有的扫描
    _stopCurrentScanSync();
    
    // 延迟一点再开始扫描，确保停止操作完成
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        // 立即执行一次扫描
        _performBLEScan();
        
        // 启动定时器，每3秒扫描一次（降低频率避免冲突）
        _scanTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
          if (mounted) {
            _performBLEScan();
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  /// 执行单次蓝牙扫描
  void _performBLEScan() async {
    // 防抖：检查是否在冷却时间内
    final now = DateTime.now();
    if (_lastScanTime != null && now.difference(_lastScanTime!) < _scanCooldown) {
      print('⏸️  扫描冷却中，跳过本次扫描 (${_scanCooldown.inMilliseconds}ms防抖)');
      return;
    }
    
    // 避免重复扫描
    if (_isScanning) {
      print('⏸️  扫描已在进行中，跳过本次扫描');
      return;
    }
    
    _lastScanTime = now;  // 更新防抖时间
    
    try {
      print('🔍 开始执行蓝牙扫描...');
      _isScanning = true;
      
      // 先停止任何现有的扫描
      await _stopCurrentScan();
      // 给一点时间让停止操作完成
      await Future.delayed(const Duration(milliseconds: 200));
      
      // 检查蓝牙权限
      final hasPermission = await BleServiceSimple.requestPermissions();
      if (!hasPermission) {
        print('🚫 蓝牙权限未授予');
        _isScanning = false;
        return;
      }

      // 使用Stream扫描设备，收集1秒内的结果
      final List<SimpleBLEScanResult> scanResults = [];
      
      final completer = Completer<void>();
      final timer = Timer(const Duration(milliseconds: 800), () {
        _currentScanSubscription?.cancel();
        _currentScanSubscription = null;
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
      
      try {
        _currentScanSubscription = BleServiceSimple.scanForDevice(
          targetDeviceId: '', // 空字符串表示扫描所有设备
          timeout: const Duration(milliseconds: 800),
        ).listen(
          (result) {
            scanResults.add(result);
            print('🔍 发现设备: ${result.name} (${result.deviceId}) [${result.rssi} dBm]');
          },
          onError: (error) {
            print('扫描错误: $error');
            timer.cancel();
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          onDone: () {
            timer.cancel();
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
        );
        
        // 等待扫描完成
        await completer.future;
        
        print('🔍 扫描完成，发现 ${scanResults.length} 个设备');
        
        // 清理扫描订阅
        _currentScanSubscription?.cancel();
        _currentScanSubscription = null;
        
        // 更新provider中的扫描结果
        if (mounted) {
          final currentState = ref.read(deviceConnectionProvider);
          ref.read(deviceConnectionProvider.notifier).state = currentState.copyWith(
            scanResults: scanResults,
          );
        }
        
      } catch (e) {
        print('❌ 扫描流错误: $e');
        timer.cancel();
        _currentScanSubscription?.cancel();
        _currentScanSubscription = null;
        
        // 清空扫描结果
        if (mounted) {
          final currentState = ref.read(deviceConnectionProvider);
          ref.read(deviceConnectionProvider.notifier).state = currentState.copyWith(
            scanResults: [],
          );
        }
      }
      
    } catch (e) {
      print('❌ 蓝牙扫描出错: $e');
    } finally {
      _isScanning = false;
    }
  }

}