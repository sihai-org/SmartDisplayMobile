import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/ble_connection_provider.dart';
import '../../core/router/app_router.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../core/l10n/l10n_extensions.dart';

// TODO: 页面返回，记得清理scanned所有状态
class WiFiSelectionPage extends ConsumerStatefulWidget {
  const WiFiSelectionPage({super.key});

  @override
  ConsumerState<WiFiSelectionPage> createState() => _WiFiSelectionPageState();
}

class _WiFiSelectionPageState extends ConsumerState<WiFiSelectionPage> {
  var _sendLoading = false;
  final _ssidController = TextEditingController();
  final _pwdController = TextEditingController();

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
    if (_sendLoading) return;

    final ssid = _ssidController.text.trim();
    final pwd = _pwdController.text;
    if (ssid.isEmpty) {
      Fluttertoast.showToast(msg: context.l10n.please_enter_wifi_name);
      return;
    }

    setState(() => _sendLoading = true);
    final ok = await ref
        .read(bleConnectionProvider.notifier)
        .sendWifiConfig(ssid, pwd);
    setState(() => _sendLoading = false);

    if (ok) {
      Fluttertoast.showToast(msg: context.l10n.provision_success);
    } else {
      Fluttertoast.showToast(msg: context.l10n.provision_request_failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wifiNetworks = ref.watch(bleConnectionProvider).wifiNetworks;

    return PopScope(
      // 允许系统返回手势/按钮先尝试出栈
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        // didPop 为 true 时已由框架完成出栈，这里不再强制跳转
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
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: () => ref
                                .read(bleConnectionProvider.notifier)
                                .requestWifiScan(),
                            tooltip: context.l10n.rescan,
                          )
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildWifiNetworks(wifiNetworks),
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
                  if (_sendLoading)
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
        icon: _sendLoading
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

  Widget _buildWifiNetworks(List<WifiAp> wifiNetworks) {
    return Container(
      height: 220,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: wifiNetworks.isEmpty
          ? Center(child: Text(context.l10n.no_scan_results_hint))
          : ListView.separated(
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
                            'BSSID: ${ap.bssid}',
                          if (ap.frequency != null && ap.frequency! > 0)
                            '${ap.frequency} MHz',
                          if (ap.rssi > 0) 'RSSI: ${ap.rssi}%',
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
            ),
    );
  }
}
