import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/providers/drivers_provider.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/router/app_router.dart';

class DriverListPage extends ConsumerStatefulWidget {
  const DriverListPage({super.key});

  @override
  ConsumerState<DriverListPage> createState() => _DriverListPageState();
}

class _DriverListPageState extends ConsumerState<DriverListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(driversProvider.notifier).ensureLocalLoaded();
      ref.read(savedDevicesProvider.notifier).ensureLocalLoaded();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final drivers = ref.watch(driversProvider).drivers;
    final devices = ref.watch(savedDevicesProvider).devices;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.driver_list_title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // 从 Profile 进入：栈里有上一页，pop 回去
            // 从绑定成功跳入（context.go 重置栈）：栈空，回首页
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: l10n.scan_qr,
            onPressed: () => context.push(AppRoutes.qrScanner),
          ),
        ],
      ),
      body: drivers.isEmpty
          ? _emptyView(context)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: drivers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final d = drivers[index];
                final deviceName = devices
                    .where((e) => e.displayDeviceId == d.deviceId)
                    .map((e) => e.deviceName)
                    .firstOrNull;
                final shownName = (deviceName?.isNotEmpty == true)
                    ? deviceName!
                    : (d.deviceName?.isNotEmpty == true
                          ? d.deviceName!
                          : d.deviceId);

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
                          const Text('🦞', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              d.driverHwId,
                              style: Theme.of(
                                context,
                              ).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.driver_list_bound_device(shownName),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.driver_list_device_id(d.deviceId),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _emptyView(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🦞', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 12),
          Text(
            l10n.driver_list_empty,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

