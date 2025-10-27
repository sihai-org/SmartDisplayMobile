import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../presentation/pages/qrcode_result_page.dart';
import '../router/app_router.dart';
import '../providers/app_state_provider.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../features/qr_scanner/utils/qr_data_parser.dart';

/// Centralized entry for both deep links and in-app QR scan
/// Ensures identical flow before navigating to connection page.
class DeviceEntryCoordinator {
  /// Process incoming QR/deeplink content and navigate accordingly.
  /// Flow:
  /// 1) Parse content -> DeviceQrData (fail -> show raw result page)
  /// 2) If already saved -> select and go home
  /// 3) Save scanned data to app state
  /// 4) Call device_check_binding
  ///    - bound+owner -> selectFromQr and go home
  ///    - bound+others -> toast and return (no navigation)
  ///    - unbound -> go device_connection (connection page handles wifi/bind)
  static Future<void> handle(BuildContext context, WidgetRef ref, String content) async {
    try {
      developer.log('entry: parse content', name: 'QR');
      final deviceData = QrDataParser.fromQrContent(content);

      // If already saved locally, select and go home
      developer.log('entry: check saved list for ${deviceData.deviceId}', name: 'QR');
      await ref.read(savedDevicesProvider.notifier).load();
      final saved = ref.read(savedDevicesProvider);
      if (saved.loaded && saved.devices.any((e) => e.deviceId == deviceData.deviceId)) {
        developer.log('entry: already saved -> select+home', name: 'QR');
        await ref.read(savedDevicesProvider.notifier).select(deviceData.deviceId);
        if (context.mounted) context.go(AppRoutes.home);
        return;
      }

      // Record scanned data into app state (reset binding flags)
      developer.log('entry: record scanned data ${deviceData.deviceId}', name: 'QR');
      ref.read(appStateProvider.notifier).setScannedDeviceData(deviceData);

      // Check binding status via Edge Function
      final supabase = Supabase.instance.client;
      try {
        developer.log('entry: invoke device_check_binding', name: 'QR');
        final resp = await supabase.functions.invoke(
          'device_check_binding',
          body: {'device_id': deviceData.deviceId},
        );
        if (resp.status != 200) {
          throw Exception('device_check_binding 调用失败: ${resp.data}');
        }
        final data = resp.data as Map;
        final isBound = (data['is_bound'] == true);
        final isOwner = (data['is_owner'] == true);
        developer.log('entry: binding result isBound=$isBound isOwner=$isOwner', name: 'QR');
        ref.read(appStateProvider.notifier)
            .setScannedBindingStatus(isBound: isBound, isOwner: isOwner);

        if (isBound && isOwner) {
          developer.log('entry: bound+owner -> selectFromQr + home', name: 'QR');
          await ref
              .read(savedDevicesProvider.notifier)
              .selectFromQr(deviceData, lastBleAddress: deviceData.bleAddress);
          if (context.mounted) context.go(AppRoutes.home);
          return;
        }

        if (isBound && !isOwner) {
          developer.log('entry: bound+notOwner -> toast and stay', name: 'QR');
          Fluttertoast.showToast(msg: '该设备已被他人绑定，如需操作请先解绑');
          // Do not navigate; caller context decides next UI state
          return;
        }

        // Unbound -> go to connection page
        if (context.mounted) {
          developer.log('entry: unbound -> go deviceConnection', name: 'QR');
          context.go('${AppRoutes.deviceConnection}?deviceId=${deviceData.deviceId}');
        }
      } catch (_) {
        // Fallback: proceed to connection page
        if (context.mounted) {
          developer.log('entry: check binding failed -> fallback deviceConnection', name: 'QR');
          context.go('${AppRoutes.deviceConnection}?deviceId=${deviceData.deviceId}');
        }
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
