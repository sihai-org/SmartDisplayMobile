import 'package:flutter/material.dart';
import '../log/app_log.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_display_mobile/core/constants/enum.dart';
import 'package:smart_display_mobile/core/l10n/l10n_extensions.dart';
import 'package:smart_display_mobile/core/providers/ble_connection_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../audit/audit_mode.dart';

import '../router/app_router.dart';
import '../providers/app_state_provider.dart';
import '../providers/saved_devices_provider.dart';
import '../../features/qr_scanner/utils/qr_data_parser.dart';
import '../models/device_qr_data.dart';

/// Centralized entry for both deep links and in-app QR scan
/// Ensures identical flow before navigating to connection page.
class DeviceEntryCoordinator {
  /// Process incoming QR/deeplink content and navigate accordingly.
  static Future<void> handle(BuildContext context, WidgetRef ref, String content) async {
    try {
      // 1. 解析或在审核模式下强制使用本地 Mock 设备
      AppLog.instance.debug('[DeviceEntryCoordinator.handle] invoke', tag: 'Binding');

      // 审核模式 + 当前选中mock设备：直接去首页
      if (AuditMode.enabled) {
        final curDisplayId = ref.read(bleConnectionProvider).bleDeviceData?.displayDeviceId;
        if (curDisplayId != null && curDisplayId == AuditMode.mockDisplayDeviceId) {
          context.go('${AppRoutes.home}?displayDeviceId=${AuditMode.mockDisplayDeviceId}');
          return;
        }
      }
      final qrData = AuditMode.enabled
          ? DeviceQrData(
              displayDeviceId: AuditMode.mockDisplayDeviceId,
              deviceName: AuditMode.mockDeviceName,
              bleDeviceId: AuditMode.mockBleDeviceId,
              publicKey: AuditMode.mockPublicKeyHex,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            )
          : QrDataParser.fromQrContent(content);


      // 2. 前往连接
      AppLog.instance.info('[DeviceEntryCoordinator.handle] go connecting', tag: 'Binding');
      ref.read(appStateProvider.notifier).setScannedData(qrData);
      if (context.mounted) {
        context.go('${AppRoutes.deviceConnection}?displayDeviceId=${qrData.displayDeviceId}');
      }
    } catch (e) {
      AppLog.instance.warning('[DeviceEntryCoordinator.handle] parse failed -> show raw content page', tag: 'Binding', error: e);
      // Parsing failed -> show raw content page for copy/reference
      if (context.mounted) {
        final raw = Uri.encodeComponent(content);
        // 使用 push 保留返回栈，支持返回按钮与手势返回
        context.push('${AppRoutes.qrCodeResult}?text=$raw');
      }
    }
  }
}
