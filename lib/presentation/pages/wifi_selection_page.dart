import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/device_connection/providers/device_connection_provider.dart';
import '../../core/router/app_router.dart';
import 'package:go_router/go_router.dart';

class WiFiSelectionPage extends ConsumerStatefulWidget {
  const WiFiSelectionPage({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<WiFiSelectionPage> createState() => _WiFiSelectionPageState();
}

class _WiFiSelectionPageState extends ConsumerState<WiFiSelectionPage> {
  final _ssidController = TextEditingController();
  final _pwdController = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // 进入页面后自动触发一次Wi‑Fi扫描
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(deviceConnectionProvider.notifier).requestWifiScan();
      }
    });
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _pwdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(deviceConnectionProvider);
    final provisionStatus = connState.provisionStatus ?? '未开始';

    // 监听配网成功：online 或 connected 视为成功（TV 侧后续建议统一为 online）
    ref.listen<DeviceConnectionState>(deviceConnectionProvider, (prev, next) {
      final s = (next.provisionStatus ?? '').toLowerCase();
      if (s == 'online' || s == 'wifi_online' || s == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配网成功，设备已联网')),
        );
        context.go(AppRoutes.home);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('选择Wi-Fi网络'),
        // 使用全局主题的默认配色，去掉蓝色背景
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // 优先返回上一页；若无返回栈则根据上下文回退到合理页面
            if (context.canPop()) {
              context.pop();
              return;
            }
            if (widget.deviceId.isNotEmpty) {
              context.go('${AppRoutes.deviceConnection}?deviceId=${Uri.encodeComponent(widget.deviceId)}');
            } else {
              context.go(AppRoutes.home);
            }
          },
        ),
        // 移除右侧关闭按钮，统一使用左侧返回
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.devices_other, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '设备: ${widget.deviceId}',
                    style: const TextStyle(color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 附近Wi‑Fi列表
            Row(
              children: [
                const Icon(Icons.wifi, size: 18),
                const SizedBox(width: 8),
                Text('附近网络 (${connState.wifiNetworks.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => ref.read(deviceConnectionProvider.notifier).requestWifiScan(),
                  tooltip: '重新扫描',
                )
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: connState.wifiNetworks.isEmpty
                  ? const Center(child: Text('暂无扫描结果，请点击右上角刷新'))
                  : ListView.separated(
                      itemCount: connState.wifiNetworks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, idx) {
                        final ap = connState.wifiNetworks[idx];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            ap.secure ? Icons.lock : Icons.wifi,
                            size: 18,
                            color: ap.secure ? Colors.orange : Colors.green,
                          ),
                          title: Text(ap.ssid, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: (ap.bssid != null && ap.bssid!.isNotEmpty) ||
                                  (ap.frequency != null && ap.frequency! > 0) ||
                                  (ap.rssi > 0)
                              ? Text([
                                  if (ap.bssid != null && ap.bssid!.isNotEmpty) 'BSSID: ${ap.bssid}',
                                  if (ap.frequency != null && ap.frequency! > 0) '${ap.frequency} MHz',
                                  if (ap.rssi > 0) 'RSSI: ${ap.rssi}%',
                                ].join(' · '))
                              : null,
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            _ssidController.text = ap.ssid;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已选择网络: ${ap.ssid}')),
                            );
                          },
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            const Text('或手动输入 Wi‑Fi 信息', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _ssidController,
              decoration: const InputDecoration(
                labelText: 'Wi‑Fi 名称 (SSID)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pwdController,
              decoration: const InputDecoration(
                labelText: 'Wi‑Fi 密码',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _sending
                    ? null
                    : () async {
                      final ssid = _ssidController.text.trim();
                      final pwd = _pwdController.text;
                      if (ssid.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入Wi‑Fi名称')),
                        );
                        return;
                      }
                      setState(() => _sending = true);
                      final ok = await ref
                          .read(deviceConnectionProvider.notifier)
                          .sendProvisionRequest(ssid: ssid, password: pwd);
                      setState(() => _sending = false);
                      if (!ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('发送配网请求失败')),
                        );
                      }
                    },
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send),
                label: const Text('发送配网请求'),
              ),
            ),

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: () => ref.read(deviceConnectionProvider.notifier).requestWifiScan(),
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('扫描附近Wi‑Fi'),
              ),
            ),

            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text('配网状态:'),
                const SizedBox(width: 8),
                Chip(
                  label: Text(provisionStatus),
                  backgroundColor: _statusColor(provisionStatus).withOpacity(0.15),
                  labelStyle: TextStyle(color: _statusColor(provisionStatus)),
                ),
                const Spacer(),
                Text('${(connState.progress * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ],
        ),
      ),
      // 附近网络列表已放入正文区域，移除底部栏
    );
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'connecting':
        return Colors.orange;
      case 'connected':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'ready':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }
}
