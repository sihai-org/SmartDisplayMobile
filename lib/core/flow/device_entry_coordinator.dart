import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../router/app_router.dart';
import '../providers/app_state_provider.dart';
import '../providers/saved_devices_provider.dart';
import '../../features/qr_scanner/utils/qr_data_parser.dart';

/// Centralized entry for both deep links and in-app QR scan
/// Ensures identical flow before navigating to connection page.
class DeviceEntryCoordinator {
  /// Process incoming QR/deeplink content and navigate accordingly.
  static Future<void> handle(BuildContext context, WidgetRef ref, String content) async {
    try {
      // 1. 解析内容
      developer.log('entry: parse content', name: 'QR');
      final deviceData = QrDataParser.fromQrContent(content);

      // 2. 本地已有，直接跳转
      developer.log('entry: check saved list for ${deviceData.displayDeviceId}', name: 'QR');
      await ref.read(savedDevicesProvider.notifier).load();
      final saved = ref.read(savedDevicesProvider);
      if (saved.loaded && saved.devices.any((e) => e.displayDeviceId == deviceData.displayDeviceId)) {
        developer.log('entry: already saved -> select+home', name: 'QR');
        await ref.read(savedDevicesProvider.notifier).select(deviceData.displayDeviceId);
        if (context.mounted) context.go(AppRoutes.home);
        return;
      }

      // 3. 跳转连接页
      developer.log('entry: record scanned data ${deviceData.bleDeviceId}', name: 'QR');
      ref.read(appStateProvider.notifier).setScannedDeviceData(deviceData);
      if (context.mounted) {
        developer.log('entry: unbound -> go deviceConnection', name: 'QR');
        context.go('${AppRoutes.deviceConnection}?displayDeviceId=${deviceData.displayDeviceId}');
      }
    } catch (e) {
      // Parsing failed -> show raw content page for copy/reference
      if (context.mounted) {
        developer.log('entry: parse failed -> show raw content page (${e.toString()})', name: 'QR');
        final raw = Uri.encodeComponent(content);
        context.go('${AppRoutes.qrCodeResult}?text=$raw');
      }
    }
  }
}
