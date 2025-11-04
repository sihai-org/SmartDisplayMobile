import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_display_mobile/core/constants/enum.dart';
import 'package:smart_display_mobile/core/l10n/l10n_extensions.dart';
import 'package:smart_display_mobile/core/supabase/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      developer.log('[DeviceEntryCoordinator.handle] invoke', name: 'Binding');
      final qrData = QrDataParser.fromQrContent(content);

      // 2. 检查是否绑定
      developer.log('[DeviceEntryCoordinator.handle] check bound', name: 'Binding');
      CheckBoundRes checkBoundRes = CheckBoundRes.notBound;
      try {
        checkBoundRes =
            await SupabaseService.checkBound(qrData.displayDeviceId);
      } catch (e) {
        developer.log('[DeviceEntryCoordinator.handle] checkBound err=$e', name: 'Binding');
        Fluttertoast.showToast(msg: "系统繁忙，请稍后再试");
        if (context.mounted) {
          context.pop();
        }
        return;
      }
      developer.log('[DeviceEntryCoordinator.handle] checkBoundRes=$checkBoundRes', name: 'Binding');
      if (checkBoundRes == CheckBoundRes.isOwner) {
        // 2.1 自己绑：直接跳
        developer.log('[DeviceEntryCoordinator.handle] check local', name: 'Binding');
        final savedNotifier = ref.read(savedDevicesProvider.notifier);
        await savedNotifier.load();
        await savedNotifier.syncFromServer();
        final saved = ref.read(savedDevicesProvider);
        if (saved.loaded && saved.devices.any((e) => e.displayDeviceId == qrData.displayDeviceId)) {
          developer.log('[DeviceEntryCoordinator.handle] already saved', name: 'Binding');
          await savedNotifier.select(qrData.displayDeviceId);
          if (context.mounted) context.go(AppRoutes.home);
        } else {
          // TODO: 自己绑了没找到
        }
      } else if (checkBoundRes == CheckBoundRes.isBound) {
        // 2.2 别人绑：给提示
        Fluttertoast.showToast(msg: context.l10n.device_bound_elsewhere);
        if (context.mounted) {
          context.pop();
        }
      } else {
        // 2.3 没人绑：去绑定
        developer.log('[DeviceEntryCoordinator.handle] go binding', name: 'Binding');
        ref.read(appStateProvider.notifier).setScannedData(qrData);
        if (context.mounted) {
          context.go('${AppRoutes.deviceConnection}?displayDeviceId=${qrData.displayDeviceId}');
        }
      }
    } catch (e) {
      developer.log(
          '[DeviceEntryCoordinator.handle] parse failed -> show raw content page e=$e',
          name: 'Binding');
      // Parsing failed -> show raw content page for copy/reference
      if (context.mounted) {
        final raw = Uri.encodeComponent(content);
        context.go('${AppRoutes.qrCodeResult}?text=$raw');
      }
    }
  }
}
