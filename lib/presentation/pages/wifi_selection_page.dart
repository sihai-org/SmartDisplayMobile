import 'dart:async';
import '../../core/log/app_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ble/ble_device_data.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/ble_connection_provider.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/router/app_router.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/utils/binding_flow_utils.dart';

class WiFiSelectionPage extends ConsumerStatefulWidget {
  const WiFiSelectionPage({super.key, this.scannedDisplayDeviceId});

  final String? scannedDisplayDeviceId;

  @override
  ConsumerState<WiFiSelectionPage> createState() => _WiFiSelectionPageState();
}

class _WiFiSelectionPageState extends ConsumerState<WiFiSelectionPage> {
  final _ssidController = TextEditingController();
  final _pwdController = TextEditingController();
  bool _sending = false;
  Future<void> _disconnectAndClearOnUserExit() async {
    await BindingFlowUtils.disconnectAndClearOnUserExit(context, ref);
  }

  @override
  void initState() {
    super.initState();
    // 进入页面后自动触发一次Wi‑Fi扫描
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(bleConnectionProvider.notifier).requestWifiScan();
      }
    });
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  void _handleSend() async {
    if (_sending) return;

    final ssid = _ssidController.text.trim();
    final pwd = _pwdController.text;
    if (ssid.isEmpty) {
      Fluttertoast.showToast(msg: context.l10n.please_enter_wifi_name);
      return;
    }

    setState(() => _sending = true);
    final ok = await ref
        .read(bleConnectionProvider.notifier)
        .sendWifiConfig(ssid, pwd);
    setState(() => _sending = false);

    if (ok) {
      Fluttertoast.showToast(msg: context.l10n.provision_success);

      if (!mounted) return;

      if (widget.scannedDisplayDeviceId != null &&
          widget.scannedDisplayDeviceId!.isNotEmpty) {
        final idParam = Uri.encodeComponent(widget.scannedDisplayDeviceId ?? "");
        if (ref.read(bleConnectionProvider).emptyBound) {
          context.go('${AppRoutes.bindConfirm}?displayDeviceId=$idParam');
        } else {
          context.go('${AppRoutes.home}?displayDeviceId=$idParam');
        }
      }
    } else {
      Fluttertoast.showToast(msg: context.l10n.provision_request_failed);
    }
  }

  bool getIsScanned() {
    return widget.scannedDisplayDeviceId != null && widget.scannedDisplayDeviceId!.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final bleState = ref.watch(bleConnectionProvider);
    final wifiNetworks = bleState.wifiNetworks;
    final isScanning = bleState.isScanningWifi;
    final lastScanAt = bleState.wifiScanUpdatedAt;

    return PopScope(
      // 允许系统返回手势/按钮先尝试出栈
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop && getIsScanned()) {
          unawaited(_disconnectAndClearOnUserExit());
        }

        if (!didPop && context.mounted) {
          if (context.canPop()) {
            context.pop();
          } else {
            // 无回退栈时退回首页（设备详情）
            context.go(AppRoutes.home);
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.wifi_selection),
          // 使用全局主题的默认配色，去掉蓝色背景
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (getIsScanned()) {
                await _disconnectAndClearOnUserExit();
              }
              if (!context.mounted) return;
              if (context.canPop()) {
                context.pop();
              } else {
                // 无回退栈时退回首页（设备详情）
                context.go(AppRoutes.home);
              }
            },
          ),
          // 移除右侧关闭按钮，统一使用左侧返回
        ),
        // 让内容可滚动，并在键盘弹出时自动上移，避免溢出
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bottomInset = MediaQuery.of(context).viewInsets.bottom;
              final content = SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight - 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 附近Wi‑Fi列表
                      Row(
                        children: [
                          const Icon(Icons.wifi, size: 18),
                          const SizedBox(width: 8),
                      Text(
                          context.l10n
                              .nearby_networks_count(wifiNetworks.length),
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                          TextButton.icon(
                            icon: isScanning
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh),
                            label: Text(context.l10n.rescan),
                            onPressed: isScanning
                                ? null
                                : () => ref
                                    .read(bleConnectionProvider.notifier)
                                    .requestWifiScan(),
                          )
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (isScanning)
                        Text(
                          context.l10n.wifi_scanning,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.secondary),
                        )
                      else if (lastScanAt != null)
                        Text(
                          context.l10n.last_wifi_scan_time(
                              _formatDateTime(context, lastScanAt)),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context).colorScheme.outline),
                        ),
                      const SizedBox(height: 8),
                      _buildWifiNetworks(wifiNetworks, isScanning),
                      const SizedBox(height: 16),
                      Text(context.l10n.manual_wifi_entry_title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ssidController,
                        decoration: InputDecoration(
                          labelText: context.l10n.wifi_name_label,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _pwdController,
                        decoration: InputDecoration(
                          labelText: context.l10n.wifi_password_label,
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                      ),

                      const SizedBox(height: 16),
                      _buildSendBtn(),
                    ],
                  ),
                ),
              );
              return Stack(
                children: [
                  content,
                  if (_sending)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black45,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 12),
                              Text(context.l10n.provisioning_please_wait,
                                  style: const TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        // 附近网络列表已放入正文区域，移除底部栏
      ),
    );
  }

  Widget _buildSendBtn() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _handleSend,
        icon: _sending
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.send),
        label: Text(context.l10n.send_provision_request),
      ),
    );
  }

  Widget _buildWifiNetworks(List<WifiAp> wifiNetworks, bool isScanning) {
    final hasNetworks = wifiNetworks.isNotEmpty;
    final list = Container(
      height: 220,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: hasNetworks
          ? ListView.separated(
              itemCount: wifiNetworks.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, idx) {
                final ap = wifiNetworks[idx];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    ap.secure ? Icons.lock : Icons.wifi,
                    size: 18,
                    color: ap.secure ? Colors.orange : Colors.green,
                  ),
                  title: Text(ap.ssid,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: (ap.bssid != null && ap.bssid!.isNotEmpty) ||
                          (ap.frequency != null && ap.frequency! > 0) ||
                          (ap.rssi > 0)
                      ? Text([
                          if (ap.bssid != null && ap.bssid!.isNotEmpty)
                            context.l10n.wifi_bssid_label(ap.bssid!),
                          if (ap.frequency != null && ap.frequency! > 0)
                            context.l10n.wifi_frequency_mhz_label(ap.frequency!),
                          if (ap.rssi > 0)
                            context.l10n.wifi_rssi_percent_label(ap.rssi),
                        ].join(' · '))
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _ssidController.text = ap.ssid;
                    Fluttertoast.showToast(
                        msg: context.l10n.selected_network(ap.ssid));
                  },
                );
              },
            )
          : Center(
              child: Text(
                isScanning
                    ? context.l10n.wifi_scanning
                    : context.l10n.no_scan_results_hint,
                textAlign: TextAlign.center,
              ),
            ),
    );

    if (!isScanning || !hasNetworks) return list;

    return Stack(
      children: [
        list,
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.wifi_scanning,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
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
      String twoDigits(int v) => v.toString().padLeft(2, '0');
      return '${dateTime.month}/${dateTime.day} ${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
    }
  }
}
