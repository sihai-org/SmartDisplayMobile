import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../data/repositories/saved_devices_repository.dart';
import '../../core/providers/ble_connection_provider.dart' as conn;
import '../../core/models/device_qr_data.dart';
import '../../core/router/app_router.dart';
import 'package:fluttertoast/fluttertoast.dart';

class DeviceManagementPage extends ConsumerStatefulWidget {
  const DeviceManagementPage({super.key});

  @override
  ConsumerState<DeviceManagementPage> createState() =>
      _DeviceManagementPageState();
}

class _DeviceManagementPageState extends ConsumerState<DeviceManagementPage> {
  ProviderSubscription<SavedDevicesState>? _devicesLogSub;

  @override
  void initState() {
    super.initState();
    _devicesLogSub = ref.listenManual<SavedDevicesState>(
      savedDevicesProvider,
      (previous, next) => _logDeviceList(next),
      fireImmediately: true,
    );
    // 确保加载最新的设备列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(savedDevicesProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _devicesLogSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final savedDevicesState = ref.watch(savedDevicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.device_management),
        elevation: 1,
        actions: [
          IconButton(
            onPressed: () => _addNewDevice(),
            icon: const Icon(Icons.add),
            tooltip: context.l10n.scan_qr,
          ),
        ],
      ),
      body: _buildDeviceList(context, savedDevicesState),
    );
  }

  Future<bool> _connectSavedDevice(SavedDeviceRecord device) async {
    // 允许在缺少本地 BLE 地址时尝试连接：扫描流程会补上实际地址
    if (device.displayDeviceId.isEmpty || device.publicKey.isEmpty) {
      Fluttertoast.showToast(msg: context.l10n.missing_ble_params);
      return false;
    }
    final qr = DeviceQrData(
      displayDeviceId: device.displayDeviceId,
      deviceName: device.deviceName,
      bleDeviceId: device.lastBleDeviceId ?? '',
      publicKey: device.publicKey,
    );
    await ref.read(conn.bleConnectionProvider.notifier).enableBleConnection(qr);
    return true;
  }

  Widget _buildDeviceList(BuildContext context, SavedDevicesState state) {
    if (state.devices.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      itemCount: state.devices.length,
      itemBuilder: (context, index) {
        final device = state.devices[index];
        final isSelected = device.displayDeviceId == state.lastSelectedId;

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Image.asset(
              'assets/images/device.png',
              width: 56,
              height: 56,
              fit: BoxFit.contain,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    device.deviceName.isNotEmpty ? device.deviceName : context.l10n.unknown_device,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    if (isSelected) return;
                    await _selectDevice(device.displayDeviceId);
                    if (!mounted) return;
                    final ok = await _connectSavedDevice(device);
                    if (ok && mounted) {
                      context.go('${AppRoutes.home}?deviceId=${Uri.encodeComponent(device.displayDeviceId)}');
                    }
                  },
                  icon: Icon(
                    isSelected ? Icons.task_alt : Icons.radio_button_unchecked,
                  ),
                  color: isSelected ? Colors.green : Colors.grey,
                  tooltip: isSelected ? null : context.l10n.set_current_device,
                ),
              ],
            ),
            onTap: () async {
              await ref
                  .read(savedDevicesProvider.notifier)
                  .select(device.displayDeviceId);
              if (!mounted) return;
              final ok = await _connectSavedDevice(device);
              if (ok && mounted) {
                context.go('${AppRoutes.home}?deviceId=${Uri.encodeComponent(device.displayDeviceId)}');
              }
            },
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  '${context.l10n.device_id_label}: ${device.displayDeviceId}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
                // 隐藏 BLE 地址展示
                if (device.lastConnectedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${context.l10n.last_connected_at}: ${_formatDateTime(device.lastConnectedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices_other,
              size: 80,
              color: Theme.of(context).colorScheme.surfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.empty_saved_devices,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.empty_hint_add_by_scan,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _addNewDevice(),
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(context.l10n.scan_qr_add_device),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addNewDevice() {
    context.go(AppRoutes.qrScanner);
  }

  Future<void> _selectDevice(String displayDeviceId) async {
    try {
      await ref.read(savedDevicesProvider.notifier).select(displayDeviceId);
      if (mounted) {
        Fluttertoast.showToast(msg: context.l10n.device_switched);
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(
          msg: context.l10n.switch_device_failed(e.toString()),
        );
      }
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}小时前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  void _logDeviceList(SavedDevicesState state) {
    final devices = state.devices;
    if (devices.isEmpty) {
      print('[DeviceManagementPage] 设备列表为空');
      return;
    }
    print('[DeviceManagementPage] 当前设备数量: ${devices.length}');
    for (final device in devices) {
      final name = device.deviceName.isNotEmpty ? device.deviceName : '未命名设备';
      final ble = device.lastBleDeviceId ?? '-';
      print('[DeviceManagementPage] 设备: id=${device.displayDeviceId}, name=$name, ble=$ble');
    }
  }
}
