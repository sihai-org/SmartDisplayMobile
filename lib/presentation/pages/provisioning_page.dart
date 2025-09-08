import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProvisioningPage extends ConsumerWidget {
  const ProvisioningPage({super.key, required this.deviceId, required this.ssid});
  
  final String deviceId;
  final String ssid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网络配置'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text('正在配置网络: $ssid'),
            const SizedBox(height: 16),
            const Text('配网功能开发中...'),
          ],
        ),
      ),
    );
  }
}