import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../data/repositories/saved_devices_repository.dart';
import '../../features/device_connection/providers/device_connection_provider.dart' as conn;
import '../../features/device_connection/models/ble_device_data.dart';
import '../../features/qr_scanner/models/device_qr_data.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _autoTried = false;

  @override
  void initState() {
    super.initState();
    // 加载已保存设备
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(savedDevicesProvider.notifier).load();
    });
  }

  void _tryAutoConnect() {
    final saved = ref.read(savedDevicesProvider);
    final connState = ref.read(conn.deviceConnectionProvider);
    
    // 如果已经尝试过连接，或者没有保存的设备，或者当前已经在连接/已连接状态，则不重试
    if (_autoTried || !saved.loaded || saved.lastSelectedId == null) return;
    if (connState.status == conn.BleDeviceStatus.connecting || 
        connState.status == conn.BleDeviceStatus.connected ||
        connState.status == conn.BleDeviceStatus.authenticating ||
        connState.status == conn.BleDeviceStatus.authenticated) return;
    
    SavedDeviceRecord? rec;
    try {
      rec = saved.devices.firstWhere((e) => e.deviceId == saved.lastSelectedId);
    } catch (e) {
      return; // 没找到记录，直接返回
    }
    if (rec.deviceId.isEmpty) return;
    
    _autoTried = true;
    print('[HomePage] 自动连接上次设备: ${rec.deviceName} (${rec.deviceId})');
    
    // 构造最小 QR 数据用于连接
    final qr = DeviceQrData(
      deviceId: rec.deviceId, 
      deviceName: rec.deviceName, 
      bleAddress: rec.lastBleAddress ?? '', 
      publicKey: rec.publicKey
    );
    ref.read(conn.deviceConnectionProvider.notifier).startConnection(qr);
  }
  
  // 智能重连：当连接断开或失败时自动重试
  void _handleSmartReconnect() {
    final saved = ref.read(savedDevicesProvider);
    final connState = ref.read(conn.deviceConnectionProvider);
    
    if (!saved.loaded || saved.lastSelectedId == null) return;
    
    // 只在断开、错误或超时状态下触发重连
    if (connState.status == conn.BleDeviceStatus.disconnected ||
        connState.status == conn.BleDeviceStatus.error ||
        connState.status == conn.BleDeviceStatus.timeout) {
      
      print('[HomePage] 检测到连接问题，5秒后尝试重连...');
      
      // 延迟5秒后重试连接
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          _autoTried = false; // 重置标记允许重连
          _tryAutoConnect();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedDevicesProvider);
    final connState = ref.watch(conn.deviceConnectionProvider);
    
    // 监听连接状态变化，实现智能重连
    ref.listen<conn.DeviceConnectionState>(conn.deviceConnectionProvider, (previous, current) {
      if (previous != null && previous.status != current.status) {
        print('[HomePage] 连接状态变化: ${previous.status} -> ${current.status}');
        _handleSmartReconnect();
      }
    });
    
    // 尝试自动连接
    if (saved.loaded && saved.lastSelectedId != null) {
      _tryAutoConnect();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartDisplay'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.settings),
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            onPressed: () => context.push(AppRoutes.deviceManagement),
            icon: const Icon(Icons.devices),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!saved.loaded || saved.devices.isEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  child: Column(
                    children: [
                      Icon(Icons.wifi_protected_setup, size: 64, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text('欢迎使用智能显示器配网助手', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text('通过扫描显示器上的二维码来开始配网', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // 显示最近设备卡片
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildStatusIcon(connState.status),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                saved.devices.firstWhere((e)=> e.deviceId==saved.lastSelectedId).deviceName, 
                                style: Theme.of(context).textTheme.titleMedium
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _statusText(connState.status), 
                                style: TextStyle(color: _statusColor(context, connState.status))
                              ),
                            ]),
                          ),
                          _buildActionButtons(connState),
                        ],
                      ),
                      // 显示详细状态信息
                      if (_shouldShowDetailedStatus(connState.status)) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              if (_isConnecting(connState.status))
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _statusColor(context, connState.status),
                                    ),
                                  ),
                                )
                              else
                                Icon(
                                  _getDetailedStatusIcon(connState.status),
                                  size: 16,
                                  color: _statusColor(context, connState.status),
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _getDetailedStatusText(connState.status),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _statusColor(context, connState.status),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 32),
            
            // Primary Action - Start Provisioning / Scan Again
            ElevatedButton(
              onPressed: () => context.push(AppRoutes.qrScanner),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.qr_code_scanner, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    saved.devices.isEmpty ? '扫描二维码配网' : '扫描新的设备',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Secondary Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.push(AppRoutes.deviceManagement),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.devices),
                        SizedBox(height: 8),
                        Text('设备管理'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.push(AppRoutes.settings),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.settings),
                        SizedBox(height: 8),
                        Text('设置'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            const Spacer(),
            
            // Help Section
            Card(
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.defaultPadding),
                child: Column(
                  children: [
                    Icon(
                      Icons.help_outline,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '使用帮助',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. 确保显示器已开机并显示二维码\n'
                      '2. 点击"扫描二维码配网"按钮\n'
                      '3. 对准显示器屏幕上的二维码扫描\n'
                      '4. 按照提示完成网络配置',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建状态图标
  Widget _buildStatusIcon(BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.disconnected:
        return Icon(Icons.tv_off, size: 40, color: Colors.grey);
      case BleDeviceStatus.scanning:
      case BleDeviceStatus.connecting:
      case BleDeviceStatus.authenticating:
        return Icon(Icons.tv, size: 40, color: Colors.orange);
      case BleDeviceStatus.connected:
      case BleDeviceStatus.authenticated:
        return Icon(Icons.tv, size: 40, color: Colors.green);
      case BleDeviceStatus.error:
      case BleDeviceStatus.timeout:
        return Icon(Icons.tv_off, size: 40, color: Colors.red);
    }
  }

  // 构建操作按钮
  Widget _buildActionButtons(conn.DeviceConnectionState connState) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (connState.status == conn.BleDeviceStatus.disconnected ||
            connState.status == conn.BleDeviceStatus.error ||
            connState.status == conn.BleDeviceStatus.timeout)
          IconButton(
            onPressed: () {
              _autoTried = false; // 重置标记
              _tryAutoConnect();
            },
            icon: const Icon(Icons.refresh),
            tooltip: '重新连接',
          ),
        IconButton(
          onPressed: () => context.push(AppRoutes.qrScanner),
          icon: const Icon(Icons.qr_code_scanner),
          tooltip: '扫描新设备',
        ),
      ],
    );
  }

  // 是否显示详细状态
  bool _shouldShowDetailedStatus(BleDeviceStatus status) {
    return status != BleDeviceStatus.authenticated;
  }

  // 是否正在连接
  bool _isConnecting(BleDeviceStatus status) {
    return status == BleDeviceStatus.scanning ||
           status == BleDeviceStatus.connecting ||
           status == BleDeviceStatus.authenticating;
  }

  // 获取详细状态图标
  IconData _getDetailedStatusIcon(BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.disconnected:
        return Icons.info_outline;
      case BleDeviceStatus.connected:
        return Icons.check_circle_outline;
      case BleDeviceStatus.error:
        return Icons.error_outline;
      case BleDeviceStatus.timeout:
        return Icons.timer_off;
      default:
        return Icons.info_outline;
    }
  }

  // 获取详细状态文本
  String _getDetailedStatusText(BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.disconnected:
        return '设备未连接，正在自动重连中...';
      case BleDeviceStatus.scanning:
        return '正在搜索设备...';
      case BleDeviceStatus.connecting:
        return '正在建立连接...';
      case BleDeviceStatus.connected:
        return '连接成功，正在进行认证...';
      case BleDeviceStatus.authenticating:
        return '正在验证设备身份...';
      case BleDeviceStatus.error:
        return '连接失败，5秒后将自动重试';
      case BleDeviceStatus.timeout:
        return '连接超时，5秒后将自动重试';
      case BleDeviceStatus.authenticated:
        return '设备已就绪';
    }
  }

  String _statusText(BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.disconnected:
        return '未连接';
      case BleDeviceStatus.scanning:
        return '扫描中...';
      case BleDeviceStatus.connecting:
        return '连接中...';
      case BleDeviceStatus.connected:
        return '已连接';
      case BleDeviceStatus.authenticating:
        return '认证中...';
      case BleDeviceStatus.authenticated:
        return '已就绪';
      case BleDeviceStatus.error:
        return '连接失败';
      case BleDeviceStatus.timeout:
        return '连接超时';
    }
  }

  Color _statusColor(BuildContext context, BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.connected:
      case BleDeviceStatus.authenticated:
        return Colors.green;
      case BleDeviceStatus.connecting:
      case BleDeviceStatus.scanning:
      case BleDeviceStatus.authenticating:
        return Colors.orange;
      case BleDeviceStatus.error:
      case BleDeviceStatus.timeout:
        return Colors.red;
      case BleDeviceStatus.disconnected:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }
}
