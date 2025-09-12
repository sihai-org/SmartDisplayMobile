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
    if (_autoTried || !saved.loaded || saved.lastSelectedId == null) return;
    SavedDeviceRecord? rec;
    try {
      rec = saved.devices.firstWhere((e) => e.deviceId == saved.lastSelectedId);
    } catch (e) {
      return; // 没找到记录，直接返回
    }
    if (rec.deviceId.isEmpty) return;
    _autoTried = true;
    // 构造最小 QR 数据用于连接
    final qr = DeviceQrData(deviceId: rec.deviceId, deviceName: rec.deviceName, bleAddress: rec.lastBleAddress ?? '', publicKey: rec.publicKey);
    ref.read(conn.deviceConnectionProvider.notifier).startConnection(qr);
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedDevicesProvider);
    final connState = ref.watch(conn.deviceConnectionProvider);
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
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  child: Row(
                    children: [
                      const Icon(Icons.tv, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(saved.devices.firstWhere((e)=> e.deviceId==saved.lastSelectedId).deviceName, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(_statusText(connState.status), style: TextStyle(color: _statusColor(context, connState.status))),
                        ]),
                      ),
                      IconButton(onPressed: () => ref.read(conn.deviceConnectionProvider.notifier).retry(), icon: const Icon(Icons.refresh)),
                      IconButton(onPressed: () => context.push(AppRoutes.qrScanner), icon: const Icon(Icons.qr_code_scanner)),
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
