import 'dart:async';
import '../models/device_qr_data.dart';

abstract class BleScanner {
  /// 扫描直到找到目标，返回可用于 GATT 的 bleDeviceId
  Future<String> findBleDeviceId(
      DeviceQrData qr, {
        Duration timeout = const Duration(seconds: 30),
      });

  /// 主动取消或结束扫描
  Future<void> stop();
}
