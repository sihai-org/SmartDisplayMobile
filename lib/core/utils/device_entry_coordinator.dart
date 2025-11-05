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


      // 2. 前往连接
      developer.log('[DeviceEntryCoordinator.handle] go connecting', name: 'Binding');
      ref.read(appStateProvider.notifier).setScannedData(qrData);
      if (context.mounted) {
        context.go('${AppRoutes.deviceConnection}?displayDeviceId=${qrData.displayDeviceId}');
      }
    } catch (e) {
      developer.log(
          '[DeviceEntryCoordinator.handle] parse failed -> show raw content page e=$e',
          name: 'Binding');
      // Parsing failed -> show raw content page for copy/reference
      if (context.mounted) {
        final raw = Uri.encodeComponent(content);
        // 使用 push 保留返回栈，支持返回按钮与手势返回
        context.push('${AppRoutes.qrCodeResult}?text=$raw');
      }
    }
  }
}
