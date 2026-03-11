import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../constants/enum.dart';
import '../ble/ble_device_data.dart';
import '../log/app_log.dart';
import '../providers/app_state_provider.dart';
import '../providers/ble_connection_provider.dart';
import '../l10n/l10n_extensions.dart';

/// 绑定流程相关的通用工具方法
class BindingFlowUtils {
  BindingFlowUtils._();

  static bool isBleConnectSuccess(BleConnectResult result) {
    return result == BleConnectResult.success ||
        result == BleConnectResult.alreadyConnected;
  }

  static void toastBleConnectResult(
    BuildContext context,
    BleConnectResult result, {
    String logTag = 'Binding',
  }) {
    switch (result) {
      case BleConnectResult.success:
      case BleConnectResult.alreadyConnected:
      case BleConnectResult.cancelled:
        break;
      case BleConnectResult.userMismatch:
        Fluttertoast.showToast(msg: context.l10n.device_bound_elsewhere);
        AppLog.instance.info('ble: 用户不匹配', tag: logTag);
        break;
      case BleConnectResult.failed:
        Fluttertoast.showToast(msg: context.l10n.connect_failed_retry);
        AppLog.instance.info('ble: 连接失败', tag: logTag);
        break;
      case BleConnectResult.timeout:
        Fluttertoast.showToast(
          msg: context.l10n.ble_connect_timeout_relaunch_toast,
        );
        AppLog.instance.error('ble: 连接超时（提示重启App）', tag: logTag);
        break;
      case BleConnectResult.scanTimeout:
        Fluttertoast.showToast(
          msg: context.l10n.ble_scan_timeout_device_not_found,
        );
        AppLog.instance.info('ble: 扫描超时', tag: logTag);
        break;
      case BleConnectResult.notReady:
        Fluttertoast.showToast(
          msg: context.l10n.ble_not_ready_enable_bluetooth_check_permission,
        );
        AppLog.instance.info('ble: 蓝牙未就绪', tag: logTag);
        break;
    }
  }

  /// 用户主动离开绑定流程（退出、返回、关闭）时调用：
  /// - 若当前存在进行中的 BLE 连接，则主动断开
  /// - 清理扫描数据与 BLE 状态
  static Future<void> disconnectAndClearOnUserExit(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final conn = ref.read(bleConnectionProvider);
    final st = conn.bleDeviceStatus;
    final isBleActive =
        st == BleDeviceStatus.scanning ||
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
      Fluttertoast.showToast(msg: context.l10n.ble_disconnected_on_exit);
    }
    ref.read(appStateProvider.notifier).clearScannedData();
  }
}
