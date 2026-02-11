import 'dart:async';
import 'package:smart_display_mobile/core/constants/ble_constants.dart';

import '../models/device_qr_data.dart';

abstract class BleScanner {
  /// 扫描直到找到目标，返回可用于 GATT 的 bleDeviceId
  Future<String> findBleDeviceId(DeviceQrData qr);

  /// 主动取消或结束扫描
  Future<void> stop();
}
