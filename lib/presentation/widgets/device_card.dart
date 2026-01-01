import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_display_mobile/core/l10n/l10n_extensions.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router/app_router.dart';
import 'device_edit_trigger.dart';

class DeviceCard extends StatelessWidget {
  final String name;
  final String id;

  final String? version;
  final DateTime? lastConnectedAt;
  final Widget? versionSlot;

  final bool? enableViewDetails;

  const DeviceCard({
    super.key,
    required this.name,
    required this.id,
    this.version,
    this.lastConnectedAt,
    this.versionSlot,
    this.enableViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            child: Column(
              children: [
                Padding(
                    padding: const EdgeInsets.all(AppConstants.defaultPadding),
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/images/device.png',
                          width: 56,
                          height: 56,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Builder(builder: (context) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  this.name,
                                  style: TextStyle(fontSize: 18),
                                ),
                                const SizedBox(height: 2),
                                // 显示设备ID（替换原来的状态展示）
                                Text(
                                  '${context.l10n.device_id_label}: ${this.id}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            );
                          }),
                        ),
                        // _buildActionButtons(connState),
                      ],
                    )),
                const Divider(height: 1, color: Colors.black12),
                // 扩展信息：固件版本与添加时间
                Padding(
                    padding: const EdgeInsets.all(AppConstants.defaultPadding),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 12,
                          children: [
                            Text(
                              context.l10n.firmware_version_label,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            Text(
                              this.version ?? '-',
                              style: Theme.of(context).textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (this.versionSlot != null) ...[
                              this.versionSlot!
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 12,
                          children: [
                            Text(
                              context.l10n.last_connected_at,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                            Text(
                              _formatDateTime(this.lastConnectedAt),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        )
                      ],
                    )),
                const Divider(height: 1, color: Colors.black12),

                if (enableViewDetails == true)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 左侧：编辑
                        Expanded(
                          child: DeviceEditTrigger(
                            displayDeviceId: id,
                            deviceName: name,
                          ),
                        ),

                        const VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: Colors.black12,
                        ),

                        // 右侧：查看详情
                        Expanded(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: Theme.of(context).textTheme.bodyMedium,
                              overlayColor: Colors.transparent,
                            ),
                            onPressed: () {
                              context.go(
                                '${AppRoutes.home}?displayDeviceId=${Uri.encodeComponent(id)}',
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(
                                  AppConstants.smallPadding),
                              child: Text(
                                context.l10n.viewDetails,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: DeviceEditTrigger(
                      displayDeviceId: id,
                      deviceName: name,
                    ),
                  )
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '-';
    // Simple human-readable format: yyyy-MM-dd HH:mm
    String two(int n) => n.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final m = two(dt.month);
    final d = two(dt.day);
    final hh = two(dt.hour);
    final mm = two(dt.minute);
    return '$y-$m-$d $hh:$mm';
  }
}
