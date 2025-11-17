import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../ble/ble_device_data.dart';
import '../log/app_log.dart';
import '../providers/app_state_provider.dart';
import '../providers/ble_connection_provider.dart';
import '../l10n/l10n_extensions.dart';

/// 绑定流程相关的通用工具方法
class BindingFlowUtils {
  BindingFlowUtils._();

  /// 用户主动离开绑定流程（退出、返回、关闭）时调用：
  /// - 若当前存在进行中的 BLE 连接，则主动断开
  /// - 清理扫描数据与 BLE 状态
  static Future<void> disconnectAndClearOnUserExit(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final conn = ref.read(bleConnectionProvider);
    final st = conn.bleDeviceStatus;
    final isBleActive = st == BleDeviceStatus.scanning ||
        st == BleDeviceStatus.connecting ||
        st == BleDeviceStatus.connected ||
        st == BleDeviceStatus.authenticating ||
        st == BleDeviceStatus.authenticated;

    if (isBleActive) {
      AppLog.instance.info(
        '[BindingFlow] 用户主动离开绑定流程，断开 BLE（status=$st, deviceId=${conn.bleDeviceData?.displayDeviceId}）',
        tag: 'Binding',
      );
      try {
        await ref
            .read(bleConnectionProvider.notifier)
            .disconnect(shouldReset: true);
      } catch (e) {
        AppLog.instance.warning(
          '[BindingFlow] disconnect error: $e',
          tag: 'Binding',
          error: e,
        );
      }
      Fluttertoast.showToast(
        msg: context.l10n.ble_disconnected_on_exit,
      );
    }

    ref.read(appStateProvider.notifier).clearScannedData();
    ref.read(bleConnectionProvider.notifier).resetState();
  }
}
