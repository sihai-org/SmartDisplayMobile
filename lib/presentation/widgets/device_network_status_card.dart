import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/network/network_status.dart';

class DeviceNetworkStatusCard extends StatelessWidget {
  const DeviceNetworkStatusCard({
    super.key,
    required this.networkStatus,
    required this.isCheckingNetwork,
    required this.networkStatusUpdatedAt,
    required this.onRefresh,
    this.onManageNetwork,
  });

  final NetworkStatus? networkStatus;
  final bool isCheckingNetwork;
  final DateTime? networkStatusUpdatedAt;
  final VoidCallback onRefresh;
  final VoidCallback? onManageNetwork;

  @override
  Widget build(BuildContext context) {
    final connected = networkStatus?.connected == true;
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outline.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.4 : 0.25,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            dense: true,
            leading: SizedBox(
              width: 28,
              child: Icon(
                connected ? Icons.wifi : Icons.signal_wifi_off,
                size: 22,
                color: connected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            title: Text(
              connected
                  ? (networkStatus?.displaySsid ?? context.l10n.unknown_network)
                  : context.l10n.network_not_connected,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: context.l10n.refresh,
                  onPressed: isCheckingNetwork ? null : onRefresh,
                  icon: isCheckingNetwork
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
                if (onManageNetwork != null) const Icon(Icons.chevron_right),
              ],
            ),
            onTap: onManageNetwork,
          ),
        ),
        if (networkStatusUpdatedAt != null) ...[
          const SizedBox(height: 8),
          Text(
            '${context.l10n.last_updated}: ${_fmtTime(networkStatusUpdatedAt!)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ],
    );
  }

  String _fmtTime(DateTime t) {
    final lt = t.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(lt.hour)}:${two(lt.minute)}:${two(lt.second)}';
  }
}
