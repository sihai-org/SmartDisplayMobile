import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_display_mobile/presentation/widgets/device_card.dart';
import 'package:smart_display_mobile/presentation/widgets/device_edit_trigger.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/log/app_log.dart';

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

        return Stack(
          children: [
            DeviceCard(
              name: device.deviceName,
              id: device.displayDeviceId,
              version: device.firmwareVersion,
              lastConnectedAt: device.lastConnectedAt,
              enableViewDetails: !isSelected,
            ),
            // Card(
            //   elevation: 0,
            //   margin: const EdgeInsets.only(bottom: 12),
            //   child: ListTile(
            //     contentPadding:
            //         const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            //
            //     leading: Image.asset(
            //       'assets/images/device.png',
            //       width: 56,
            //       height: 56,
            //       fit: BoxFit.contain,
            //     ),
            //
            //     // 主要文字区域（名称 + 描述）
            //     title: Text(
            //       device.deviceName.isNotEmpty
            //           ? device.deviceName
            //           : context.l10n.unknown_device,
            //       style: Theme.of(context).textTheme.titleMedium?.copyWith(
            //             fontWeight:
            //                 isSelected ? FontWeight.bold : FontWeight.normal,
            //           ),
            //     ),
            //     subtitle: Column(
            //       crossAxisAlignment: CrossAxisAlignment.start,
            //       children: [
            //         const SizedBox(height: 6),
            //         Text(
            //           '${context.l10n.device_id_label}: ${device.displayDeviceId}',
            //           style: Theme.of(context).textTheme.bodySmall?.copyWith(
            //                 fontFamily: 'monospace',
            //           ),
            //         ),
            //         if (device.lastConnectedAt != null) ...[
            //           const SizedBox(height: 4),
            //           Text(
            //             '${context.l10n.last_connected_at}: ${_formatDateTime(context, device.lastConnectedAt!)}',
            //             style: Theme.of(context).textTheme.bodySmall?.copyWith(
            //                   color: Theme.of(context)
            //                       .colorScheme
            //                       .onSurfaceVariant,
            //                 ),
            //           ),
            //         ],
            //       ],
            //     ),
            //
            //     // 右侧的 selected 图标
            //     trailing: Icon(
            //       isSelected ? Icons.task_alt : Icons.radio_button_unchecked,
            //       color: isSelected ? Colors.green : Colors.grey,
            //     ),
            //
            //     // 点击进入详情
            //     onTap: () {
            //       context.go(
            //         '${AppRoutes.home}?displayDeviceId=${Uri.encodeComponent(device.displayDeviceId)}',
            //       );
            //     },
            //   ),
            // ),
            //
            // // 右上角独立悬浮的 edit icon
            // Positioned(
            //   top: 4,
            //   right: 4,
            //   child: DeviceEditTrigger(
            //     displayDeviceId: device.displayDeviceId,
            //     deviceName: device.deviceName,
            //     padding: const EdgeInsets.all(4),
            //   ),
            // ),
          ],
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

  String _formatDateTime(BuildContext context, DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return context.l10n.relative_just_now;
    } else if (difference.inHours < 1) {
      return context.l10n.relative_minutes_ago(difference.inMinutes);
    } else if (difference.inDays < 1) {
      return context.l10n.relative_hours_ago(difference.inHours);
    } else if (difference.inDays < 7) {
      return context.l10n.relative_days_ago(difference.inDays);
    } else {
      return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }

  void _logDeviceList(SavedDevicesState state) {
    final devices = state.devices;
    if (devices.isEmpty) {
      AppLog.instance.debug('[DeviceManagementPage] 设备列表为空', tag: 'DeviceList');
      return;
    }
    AppLog.instance.debug('[DeviceManagementPage] 当前设备数量: ${devices.length}', tag: 'DeviceList');
    for (final device in devices) {
      final name = device.deviceName.isNotEmpty ? device.deviceName : '未命名设备';
      final ble = device.lastBleDeviceId ?? '-';
      AppLog.instance.debug('[DeviceManagementPage] 设备: id=${device.displayDeviceId}, name=$name, ble=$ble', tag: 'DeviceList');
    }
  }
}
