import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/app_router.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/constants/ble_constants.dart';
import '../../features/device_connection/providers/device_connection_provider.dart';
import '../../features/qr_scanner/models/device_qr_data.dart';
import '../../features/qr_scanner/providers/qr_scanner_provider.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../features/device_connection/models/ble_device_data.dart';

class BindConfirmPage extends ConsumerStatefulWidget {
  const BindConfirmPage({super.key, required this.deviceId});

  final String deviceId;

  @override
  ConsumerState<BindConfirmPage> createState() => _BindConfirmPageState();
}

class _BindConfirmPageState extends ConsumerState<BindConfirmPage> {
  bool _navigated = false; // 防止重复跳转
  bool _sending = false;   // 按钮loading

  void _goHomeOnce() {
    if (_navigated || !mounted) return;
    _navigated = true;
    context.go(AppRoutes.home);
  }

  // 返回时：若当前设备不在设备列表且蓝牙已连接，则断开
  Future<void> _maybeDisconnectIfEphemeral() async {
    final conn = ref.read(deviceConnectionProvider);
    final devId = conn.deviceData?.deviceId;
    final st = conn.status;
    final isBleConnected = st == BleDeviceStatus.connected ||
        st == BleDeviceStatus.authenticating ||
        st == BleDeviceStatus.authenticated;
    if (devId == null || devId.isEmpty || !isBleConnected) return;
    await ref.read(savedDevicesProvider.notifier).load();
    final saved = ref.read(savedDevicesProvider);
    final inList = saved.devices.any((e) => e.deviceId == devId);
    if (!inList) {
      // ignore: avoid_print
      print('[BindConfirmPage] 返回且设备不在列表，主动断开BLE: $devId');
      await ref.read(deviceConnectionProvider.notifier).disconnect();
      Fluttertoast.showToast(msg: '已断开未绑定设备的蓝牙连接');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final app = ref.watch(appStateProvider);
    final scanned = app.scannedDeviceData;
    final same = scanned?.deviceId == widget.deviceId;

    // 监听设备端 login_success，确保即使未点击按钮也能自动跳转
    ref.listen<DeviceConnectionState>(
      deviceConnectionProvider,
      (prev, next) {
        final s = (next.provisionStatus ?? '').toLowerCase();
        final matchedId = next.lastProvisionDeviceId ?? scanned?.deviceId;
        final isMatch = matchedId == null || matchedId.isEmpty || matchedId == widget.deviceId;
        if (isMatch && (s == 'login_success' || s.contains('login_success'))) {
          Fluttertoast.showToast(msg: '登录成功');
          _goHomeOnce();
        }
      },
    );

    // 如果没有扫描数据，提示返回扫码
    if (!same || scanned == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('绑定设备')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('未找到设备信息，请返回重新扫码'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoutes.qrScanner),
                child: const Text('返回扫码'),
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
        ref.read(appStateProvider.notifier).clearScannedDeviceData();
        ref.read(deviceConnectionProvider.notifier).reset();
        ref.read(qrScannerProvider.notifier).reset();
        if (context.mounted) context.go(AppRoutes.qrScanner);
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('确认绑定'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _maybeDisconnectIfEphemeral();
            // 清理扫描与连接状态，返回扫码页后重新初始化
            ref.read(appStateProvider.notifier).clearScannedDeviceData();
            ref.read(deviceConnectionProvider.notifier).reset();
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
                      Text('ID: ${scanned.deviceId}', style: const TextStyle(fontFamily: 'monospace')),
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 24),
            const Text('是否将该设备绑定到当前账号？'),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await _maybeDisconnectIfEphemeral();
                      // 清理扫描与连接状态，返回扫码页后重新初始化
                      ref.read(appStateProvider.notifier).clearScannedDeviceData();
                      ref.read(deviceConnectionProvider.notifier).reset();
                      ref.read(qrScannerProvider.notifier).reset();
                      context.go(AppRoutes.qrScanner);
                    },
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _sending
                        ? null
                        : () async {
                            setState(() => _sending = true);
                            final ok = await _bindViaOtp(context, ref, scanned);
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
                                await ref.read(savedDevicesProvider.notifier).select(scanned.deviceId);
                              } catch (_) {}
                              _goHomeOnce();
                            }
                            if (mounted) setState(() => _sending = false);
                          },
                    child: _sending
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('绑定'),
                            ],
                          )
                        : const Text('绑定'),
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

  Future<bool> _bindViaOtp(BuildContext context, WidgetRef ref, DeviceQrData device) async {
    try {
      // 确保可信通道
      final okChannel = await ref.read(deviceConnectionProvider.notifier).ensureTrustedChannel();
      if (!okChannel) {
        // 兜底：如果实际上已绑定成功（比如前次已完成），则不报错
        final recovered = await _attemptSuccessFallback(ref, device.deviceId);
        if (recovered) return true;
        Fluttertoast.showToast(msg: '蓝牙通道未就绪，请靠近设备重试');
        return false;
      }

      final supabase = Supabase.instance.client;
      final response = await supabase.functions.invoke(
        'pairing-otp',
        body: {'device_id': device.deviceId},
      );
      if (response.status != 200) {
        final recovered = await _attemptSuccessFallback(ref, device.deviceId);
        if (recovered) return true;
        Fluttertoast.showToast(msg: '获取授权码失败: ${response.data}');
        return false;
      }
      final data = response.data as Map;
      final email = (data['email'] ?? '') as String;
      final otpToken = (data['token'] ?? '') as String;
      if (email.isEmpty || otpToken.isEmpty) {
        final recovered = await _attemptSuccessFallback(ref, device.deviceId);
        if (recovered) return true;
        Fluttertoast.showToast(msg: '授权码为空');
        return false;
      }

      // 构造负载并通过连接管理器进行加密发送
      final notifier = ref.read(deviceConnectionProvider.notifier);
      final payload = <String, dynamic>{
        'deviceId': device.deviceId,
        'email': email,
        'otpToken': otpToken,
        'userId': notifier.currentUserId(),
      };
      final ok = await notifier.writeEncryptedJson(
        characteristicUuid: BleConstants.loginAuthCodeCharUuid,
        json: payload,
      );
      if (!ok) {
        // 写入失败但设备可能已收到（某些平台 withResponse 不可靠），尝试快速验证绑定结果
        final recovered = await _attemptSuccessFallback(ref, device.deviceId);
        if (recovered) return true;
        Fluttertoast.showToast(msg: '下发绑定指令失败');
        return false;
      }
      return true;
    } catch (e) {
      // 发生异常时也尝试兜底验证是否已绑定成功
      final recovered = await _attemptSuccessFallback(ref, device.deviceId);
      if (recovered) return true;
      Fluttertoast.showToast(msg: '绑定失败: $e');
      return false;
    }
  }

  // 快速兜底：同步服务器设备列表，若已包含该设备则视为成功
  Future<bool> _attemptSuccessFallback(WidgetRef ref, String deviceId) async {
    try {
      // 第一次立即同步
      await ref.read(savedDevicesProvider.notifier).syncFromServer();
      if (ref.read(savedDevicesProvider).devices.any((e) => e.deviceId == deviceId)) {
        return true;
      }
      // 短暂等待后再同步一次
      await Future.delayed(const Duration(seconds: 2));
      await ref.read(savedDevicesProvider.notifier).syncFromServer();
      return ref.read(savedDevicesProvider).devices.any((e) => e.deviceId == deviceId);
    } catch (_) {
      return false;
    }
  }
}
