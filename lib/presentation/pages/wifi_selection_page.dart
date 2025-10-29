import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/ble_connection_provider.dart';
import '../../core/network/network_status.dart';
import '../../core/ble/ble_device_data.dart';
import '../../core/router/app_router.dart';
import '../../core/providers/saved_devices_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';

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
  bool _shownSuccessToast = false;
  bool _shownFailureToast = false;
  bool _navigatedOnSuccess = false;

  @override
  void initState() {
    super.initState();
    // 进入页面后自动触发一次Wi‑Fi扫描
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // 确保本地设备列表已加载，便于后续跳转判断
        ref.read(savedDevicesProvider.notifier).load();
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

  @override
  Widget build(BuildContext context) {
    final connState = ref.watch(bleConnectionProvider);
    final provisionStatus = connState.provisionStatus ?? '未开始';

    // 返回时：若当前设备不在设备列表且蓝牙已连接，则断开
    Future<void> _maybeDisconnectIfEphemeral() async {
      final conn = ref.read(bleConnectionProvider);
      final devId = conn.bleDeviceData?.displayDeviceId;
      final st = conn.bleDeviceStatus;
      final isBleConnected = st == BleDeviceStatus.connected ||
          st == BleDeviceStatus.authenticating ||
          st == BleDeviceStatus.authenticated;
      if (devId == null || devId.isEmpty || !isBleConnected) return;
      // 确保本地设备列表已加载
      await ref.read(savedDevicesProvider.notifier).load();
      final saved = ref.read(savedDevicesProvider);
      final inList = saved.devices.any((e) => e.displayDeviceId == devId);
      if (!inList) {
        // 日志与用户提示
        // ignore: avoid_print
        print('[WiFiSelectionPage] 返回且设备不在列表，主动断开BLE: $devId');
        await ref.read(bleConnectionProvider.notifier).disconnect();
        Fluttertoast.showToast(msg: '已断开未绑定设备的蓝牙连接');
      }
    }

    // 监听配网结果：wifi_online/wifi_offline，若未在设备列表则跳转绑定页
    ref.listen<BleConnectionState>(bleConnectionProvider, (prev, next) {
      String s = (next.provisionStatus ?? '').toLowerCase();
      final String prevS = (prev?.provisionStatus ?? '').toLowerCase();
      // 兼容设备端发送的 JSON 载荷：{"deviceId":"...","status":"wifi_online"}
      if (s.startsWith('{')) {
        try {
          final Map<String, dynamic> obj = jsonDecode(next.provisionStatus ?? '{}');
          final st = (obj['status']?.toString() ?? '').toLowerCase();
          if (st.isNotEmpty) s = st;
        } catch (_) {
          // ignore JSON parse failure and fallback to raw string
        }
      }
      // 校验 deviceId：优先使用 provider 中解析到的 lastProvisionDeviceId
      final provDeviceId = next.lastProvisionDeviceId;
      final isDeviceMatch = provDeviceId == null || provDeviceId.isEmpty
          ? true // 未传则放行（向后兼容）
          : provDeviceId == widget.deviceId;

      // 成功：只在状态从非成功 -> 成功时提示一次，且必须确认网络真实连接并匹配本次 SSID
      final bool nextIsSuccess = (s == 'wifi_online' || s.contains('wifi_online'));
      final bool prevWasSuccess = (prevS == 'wifi_online' || prevS.contains('wifi_online'));
      final ns = next.networkStatus; // 需为已连接
      final reqSsid = (next.lastProvisionSsid ?? '').trim();
      final currSsid = ((ns?.displaySsid ?? ns?.ssid) ?? '').trim();
      final bool ssidMatches = reqSsid.isNotEmpty && currSsid.isNotEmpty && reqSsid == currSsid;
      final bool successSatisfied = nextIsSuccess && isDeviceMatch && ns?.connected == true && ssidMatches;
      if (successSatisfied && (!_shownSuccessToast || !prevWasSuccess)) {
        if (!_shownSuccessToast) {
          _shownSuccessToast = true;
          Fluttertoast.showToast(msg: '配网成功，设备已联网');
        }
        final id = widget.deviceId;
        if (!_navigatedOnSuccess && id.isNotEmpty) {
          // 未绑定（设备列表中不存在）→ 跳转绑定页
          final saved = ref.read(savedDevicesProvider);
          final inList = saved.devices.any((e) => e.displayDeviceId == id);
          if (!inList) {
            _navigatedOnSuccess = true;
            context.go('${AppRoutes.bindConfirm}?deviceId=${Uri.encodeComponent(id)}');
          }
          // 已绑定 → 保持当前页面，不做跳转
        }
      } else if (nextIsSuccess && !isDeviceMatch) {
        // 设备不匹配时仅记录，不进行跳转
        // ignore: avoid_print
        print('[WiFiSelectionPage] 忽略其他设备的 wifi_online: from=$provDeviceId, current=${widget.deviceId}');
      }

      // 失败：只在状态从非失败 -> 失败时提示一次
      final bool nextIsFail = (s == 'wifi_offline' || s.contains('wifi_offline') || s == 'failed');
      // 去掉对 prevWasFail 的限制，改为由页面内一次性标志控制每次“尝试”的 toast 频率
      if (nextIsFail && isDeviceMatch) {
        if (!_shownFailureToast) {
          _shownFailureToast = true;
          Fluttertoast.showToast(msg: '配网失败，设备未能连接网络');
        }
      }
    });

    return PopScope(
      // 允许系统返回手势/按钮先尝试出栈
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        // 无论是否已经出栈，都做一次临时设备断开检查
        await _maybeDisconnectIfEphemeral();
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
        title: const Text('选择Wi-Fi网络'),
        // 使用全局主题的默认配色，去掉蓝色背景
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _maybeDisconnectIfEphemeral();
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
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
                  onPressed: () => ref.read(bleConnectionProvider.notifier).requestWifiScan(),
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
                            Fluttertoast.showToast(msg: '已选择网络: ${ap.ssid}');
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
                        Fluttertoast.showToast(msg: '请输入Wi‑Fi名称');
                        return;
                      }
                      // 新的一次请求前，重置一次性提示标志
                      _shownSuccessToast = false;
                      _shownFailureToast = false;
                      _navigatedOnSuccess = false;
                      setState(() => _sending = true);
                      final ok = await ref
                          .read(bleConnectionProvider.notifier)
                          .sendProvisionRequest(ssid: ssid, password: pwd);
                      setState(() => _sending = false);
                      if (!ok) {
                        Fluttertoast.showToast(msg: '发送配网请求失败');
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
                onPressed: () => ref.read(bleConnectionProvider.notifier).requestWifiScan(),
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
              ],
            ),
          ],
        ),
              ),
            );
            final showLoading = _sending || provisionStatus.toLowerCase() == 'provisioning';
            return Stack(
              children: [
                content,
                if (showLoading)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black45,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('正在配网，请稍候…', style: TextStyle(color: Colors.white)),
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

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'provisioning':
        return Colors.orange;
      case 'wifi_online':
      case 'connected':
        return Colors.green;
      case 'wifi_offline':
      case 'connecting':
      case 'failed':
        return Colors.red;
      case 'ready':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }
}
