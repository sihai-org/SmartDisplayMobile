import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/router/app_router.dart';

class DeviceManagementPage extends ConsumerStatefulWidget {
  final void Function(String deviceId)? onDeviceTapped;
  const DeviceManagementPage({super.key, this.onDeviceTapped});

  @override
  ConsumerState<DeviceManagementPage> createState() =>
      _DeviceManagementPageState();
}

class _DeviceManagementPageState extends ConsumerState<DeviceManagementPage> {
  @override
  void initState() {
    super.initState();
    // 确保加载最新的设备列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(savedDevicesProvider.notifier).load();
    });
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

  Widget _buildDeviceList(BuildContext context, SavedDevicesState state) {
    if (state.devices.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      itemCount: state.devices.length,
      itemBuilder: (context, index) {
        final device = state.devices[index];
        final isSelected = device.deviceId == state.lastSelectedId;

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
                  onPressed: () =>
                      {if (!isSelected) _selectDevice(device.deviceId)},
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
                  .select(device.deviceId);
              if (mounted) {
                widget.onDeviceTapped?.call(device.deviceId);
              }
            },
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  '${context.l10n.device_id_label}: ${device.deviceId}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
                if (device.lastBleAddress != null)
                  Text(
                    '${context.l10n.ble_label}: ${device.lastBleAddress}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
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

  void _selectDevice(String deviceId) async {
    try {
      await ref.read(savedDevicesProvider.notifier).select(deviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.device_switched),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.switch_device_failed(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
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
}
