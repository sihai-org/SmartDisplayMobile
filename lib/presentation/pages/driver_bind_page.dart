import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/log/app_log.dart';
import '../../core/providers/drivers_provider.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/saved_devices_repository.dart';

class DriverBindPage extends ConsumerStatefulWidget {
  const DriverBindPage({super.key, required this.driverHwId});

  final String driverHwId;

  @override
  ConsumerState<DriverBindPage> createState() => _DriverBindPageState();
}

class _DriverBindPageState extends ConsumerState<DriverBindPage> {
  String? _selectedDeviceId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref.read(savedDevicesProvider.notifier).ensureLocalLoaded();
      if (!mounted) return;
      final devices = ref.read(savedDevicesProvider).devices;
      if (devices.isNotEmpty) {
        setState(() => _selectedDeviceId = devices.first.displayDeviceId);
      }
    });
  }

  Future<void> _onSubmit(SavedDeviceRecord device) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(driversProvider.notifier)
          .bind(
            deviceId: device.displayDeviceId,
            driverHwId: widget.driverHwId,
            deviceName: device.deviceName.isEmpty ? null : device.deviceName,
          );
      AppLog.instance.info(
        '[DriverBindPage] bind ok hwId=${widget.driverHwId} '
        'device=${device.displayDeviceId}',
        tag: 'Driver',
      );
      if (!mounted) return;
      Fluttertoast.showToast(msg: context.l10n.driver_bind_success);
      context.go(AppRoutes.driverList);
    } catch (e, st) {
      AppLog.instance.error(
        '[DriverBindPage] bind failed',
        tag: 'Driver',
        error: e,
        stackTrace: st,
      );
      if (!mounted) return;
      Fluttertoast.showToast(msg: context.l10n.driver_bind_failed);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final devices = ref.watch(savedDevicesProvider).devices;

    SavedDeviceRecord? selected;
    if (devices.isNotEmpty) {
      final id = _selectedDeviceId ?? devices.first.displayDeviceId;
      selected = devices.firstWhere(
        (e) => e.displayDeviceId == id,
        orElse: () => devices.first,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.driver_bind_title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // 进入路径是 context.go（栈被替换），需显式回扫码页
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.qrScanner);
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _headerCard(context),
              const SizedBox(height: 16),
              Text(
                l10n.driver_bind_choose_device,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: devices.isEmpty
                    ? _emptyDevicesView(context)
                    : _deviceList(context, devices),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (selected == null || _submitting)
                    ? null
                    : () => _onSubmit(selected!),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.driver_bind_submit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCard(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🦞', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                l10n.driver_bind_hw_id_label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 与下方设备筛选中的 deviceName 样式一致（ListTile title 默认 bodyLarge）
          Text(
            widget.driverHwId,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  Widget _emptyDevicesView(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.devices_other, size: 56, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            l10n.driver_bind_empty_devices,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _deviceList(BuildContext context, List<SavedDeviceRecord> devices) {
    final singleDevice = devices.length == 1;
    return ListView.separated(
      itemCount: devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final d = devices[index];
        final selected = d.displayDeviceId == _selectedDeviceId;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: RadioListTile<String>(
            value: d.displayDeviceId,
            groupValue: _selectedDeviceId,
            onChanged: singleDevice
                ? null
                : (v) => setState(() => _selectedDeviceId = v),
            title: Text(
              d.deviceName.isNotEmpty ? d.deviceName : d.displayDeviceId,
            ),
            subtitle: Text(d.displayDeviceId),
          ),
        );
      },
    );
  }
}
