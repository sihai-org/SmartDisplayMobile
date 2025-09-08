import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeviceConnectionPage extends ConsumerWidget {
  const DeviceConnectionPage({super.key, required this.deviceId});
  
  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接设备'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text('正在连接设备: $deviceId'),
            const SizedBox(height: 16),
            const Text('连接功能开发中...'),
          ],
        ),
      ),
    );
  }
}