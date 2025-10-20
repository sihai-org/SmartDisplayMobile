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

class BindConfirmPage extends ConsumerWidget {
  const BindConfirmPage({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final scanned = app.scannedDeviceData;
    final same = scanned?.deviceId == deviceId;

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('确认绑定'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.qrScanner),
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
                    onPressed: () {
                      ref.read(appStateProvider.notifier).clearScannedDeviceData();
                      ref.read(deviceConnectionProvider.notifier).reset();
                      context.go(AppRoutes.qrScanner);
                    },
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      final ok = await _bindViaOtp(context, ref, scanned);
                      if (ok && context.mounted) {
                        // 等待设备BLE通知登录成功，连接管理器将刷新并选中
                        context.go(AppRoutes.home);
                      }
                    },
                    child: const Text('绑定'),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<bool> _bindViaOtp(BuildContext context, WidgetRef ref, DeviceQrData device) async {
    try {
      // 确保可信通道
      final okChannel = await ref.read(deviceConnectionProvider.notifier).ensureTrustedChannel();
      if (!okChannel) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('蓝牙通道未就绪，请靠近设备重试')),
        );
        return false;
      }

      final supabase = Supabase.instance.client;
      final response = await supabase.functions.invoke(
        'pairing-otp',
        body: {'device_id': device.deviceId},
      );
      if (response.status != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取授权码失败: ${response.data}')),
        );
        return false;
      }
      final data = response.data as Map;
      final email = (data['email'] ?? '') as String;
      final otpToken = (data['token'] ?? '') as String;
      if (email.isEmpty || otpToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('授权码为空')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下发绑定指令失败')),
        );
        return false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('绑定指令已发送，稍候完成登录')),
      );
      return true;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('绑定失败: $e')),
      );
      return false;
    }
  }
}
