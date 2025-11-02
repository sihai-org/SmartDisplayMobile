import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_display_mobile/core/channel/secure_channel_manager_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/app_router.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/constants/ble_constants.dart';
import '../../core/providers/ble_connection_provider.dart';
import '../../core/models/device_qr_data.dart';
import '../../features/qr_scanner/providers/qr_scanner_provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../core/ble/ble_device_data.dart';
import '../../core/l10n/l10n_extensions.dart';

class BindConfirmPage extends ConsumerStatefulWidget {
  const BindConfirmPage({super.key, required this.displayDeviceId});

  final String displayDeviceId;

  @override
  ConsumerState<BindConfirmPage> createState() => _BindConfirmPageState();
}

class _BindConfirmPageState extends ConsumerState<BindConfirmPage> {
  bool _navigated = false; // 防止重复跳转
  bool _sending = false;   // 按钮loading

  @override
  void initState() {
    super.initState();
  }

  void _goHomeOnce() {
    if (_navigated || !mounted) return;
    _navigated = true;
    context.go(AppRoutes.home);
  }

  Future<void> handleClickBind(DeviceQrData scanned) async {
    if (_sending) return;
    setState(() => _sending = true);

    try {
      final ok = await _bindViaOtp(ref, scanned);
      if (ok && mounted) {
        // 异步后台同步（最多等待2秒），不阻塞跳转
        try {
          final sync = ref.read(savedDevicesProvider.notifier).syncFromServer();
          await Future.any([
            sync,
            Future.delayed(const Duration(seconds: 2)),
          ]);
        } catch (_) {}
        try {
          await ref
              .read(savedDevicesProvider.notifier)
              .select(scanned.displayDeviceId);
        } catch (_) {}
        _goHomeOnce();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // 返回时：若当前设备不在设备列表且蓝牙已连接，则断开
  Future<void> _maybeDisconnectIfEphemeral() async {
    final conn = ref.read(bleConnectionProvider);
    final displayDeviceId = conn.bleDeviceData?.displayDeviceId;
    final st = conn.bleDeviceStatus;
    final isBleConnected = st == BleDeviceStatus.connected ||
        st == BleDeviceStatus.authenticating ||
        st == BleDeviceStatus.authenticated;
    if (displayDeviceId == null || displayDeviceId.isEmpty || !isBleConnected)
      return;
    await ref.read(savedDevicesProvider.notifier).load();
    final saved = ref.read(savedDevicesProvider);
    final inList = saved.devices.any((e) =>
    e.displayDeviceId == displayDeviceId);
    if (!inList) {
      // ignore: avoid_print
      print(
          '[BindConfirmPage] 返回且设备不在列表，主动断开BLE: $displayDeviceId');
      await ref.read(bleConnectionProvider.notifier).disconnect();
      Fluttertoast.showToast(msg: context.l10n.ble_disconnected_ephemeral);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final app = ref.watch(appStateProvider);
    final scanned = app.scannedQrData;
    final same = scanned?.displayDeviceId == widget.displayDeviceId;

    print('[bind_confirm_page] scanned=$scanned, displayDeviceId=${widget.displayDeviceId}');
    
    // 如果没有扫描数据，提示返回扫码
    if (!same || scanned == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.bind_device_title)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.no_device_info_message),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoutes.qrScanner),
                child: Text(context.l10n.back_to_scan),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        await _maybeDisconnectIfEphemeral();
        // 清理扫描与连接状态，返回扫码页后重新初始化
        ref.read(appStateProvider.notifier).clearScannedData();
        ref.read(bleConnectionProvider.notifier).resetState();
        ref.read(qrScannerProvider.notifier).reset();
        if (context.mounted) context.go(AppRoutes.qrScanner);
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.confirm_binding_title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _maybeDisconnectIfEphemeral();
            // 清理扫描与连接状态，返回扫码页后重新初始化
            ref.read(appStateProvider.notifier).clearScannedData();
            ref.read(bleConnectionProvider.notifier).resetState();
            ref.read(qrScannerProvider.notifier).reset();
            context.go(AppRoutes.qrScanner);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tv, color: Colors.grey),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scanned.deviceName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('ID: ${scanned.displayDeviceId}',
                          style: const TextStyle(fontFamily: 'monospace')),
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 24),
            Text(context.l10n.confirm_binding_question),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await _maybeDisconnectIfEphemeral();
                      // 清理扫描与连接状态，返回扫码页后重新初始化
                      ref.read(appStateProvider.notifier).clearScannedData();
                      ref.read(bleConnectionProvider.notifier).resetState();
                      ref.read(qrScannerProvider.notifier).reset();
                      context.go(AppRoutes.qrScanner);
                    },
                    child: Text(context.l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                      onPressed:
                          _sending ? null : () => handleClickBind(scanned),
                      child: _sending
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(context.l10n.bind_button),
                              ],
                            )
                          : Text(context.l10n.bind_button),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    ),
  );
  }

  Future<bool> _bindViaOtp(WidgetRef ref, DeviceQrData device) async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.functions.invoke(
        'pairing-otp',
        body: {'device_id': device.displayDeviceId},
      );
      if (response.status != 200) {
        final recovered = await _attemptSuccessFallback(
            ref, device.displayDeviceId);
        if (recovered) return true;
        Fluttertoast.showToast(msg: context.l10n.fetch_otp_failed(response.data));
        return false;
      }
      final data = response.data as Map;
      final email = (data['email'] ?? '') as String;
      final otpToken = (data['token'] ?? '') as String;
      if (email.isEmpty || otpToken.isEmpty) {
        final recovered = await _attemptSuccessFallback(
            ref, device.displayDeviceId);
        if (recovered) return true;
        Fluttertoast.showToast(msg: context.l10n.otp_empty);
        return false;
      }

      // 构造负载并通过连接管理器进行加密发送
      final notifier = ref.read(bleConnectionProvider.notifier);
      final ok = await notifier.sendDeviceLoginCode(email, otpToken);

      if (!ok) {
        // 写入失败但设备可能已收到（某些平台 withResponse 不可靠），尝试快速验证绑定结果
        final recovered = await _attemptSuccessFallback(
            ref, device.displayDeviceId);
        if (recovered) return true;
        Fluttertoast.showToast(msg: context.l10n.bind_failed);
        return false;
      } else {
        Fluttertoast.showToast(msg: context.l10n.bind_success);
      }
      return true;
    } catch (e) {
      // 发生异常时也尝试兜底验证是否已绑定成功
      final recovered = await _attemptSuccessFallback(
          ref, device.displayDeviceId);
      if (recovered) return true;
      Fluttertoast.showToast(msg: context.l10n.bind_failed_error(e.toString()));
      return false;
    }
  }

  // 快速兜底：同步服务器设备列表，若已包含该设备则视为成功
  Future<bool> _attemptSuccessFallback(WidgetRef ref, String deviceId) async {
    try {
      // 第一次立即同步
      await ref.read(savedDevicesProvider.notifier).syncFromServer();
      if (ref
          .read(savedDevicesProvider)
          .devices
          .any((e) => e.displayDeviceId == deviceId)) {
        return true;
      }
      // 短暂等待后再同步一次
      await Future.delayed(const Duration(seconds: 2));
      await ref.read(savedDevicesProvider.notifier).syncFromServer();
      return ref
          .read(savedDevicesProvider)
          .devices
          .any((e) => e.displayDeviceId == deviceId);
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
