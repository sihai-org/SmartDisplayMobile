import 'dart:async';
import 'ble_scanner.dart';
import '../models/device_qr_data.dart';

class BleScannerMock implements BleScanner {
  @override
  Future<String> findBleDeviceId(DeviceQrData qr,
      {Duration timeout = const Duration(seconds: 30)}) async {
    // Simulate a quick local resolution of BLE id
    await Future.delayed(const Duration(milliseconds: 120));
    return qr.bleDeviceId.isNotEmpty ? qr.bleDeviceId : 'BLE-MOCK-001';
  }

  @override
  Future<void> stop() async {
    // no-op
  }
}

