import 'package:smart_display_mobile/data/repositories/saved_devices_repository.dart';

import '../ble/ble_device_data.dart';
import '../models/device_qr_data.dart';

DeviceQrData deviceDataToQrData(BleDeviceData d) {
  return DeviceQrData(
    displayDeviceId: d.displayDeviceId,
    versionCode: d.versionCode,
    bleDeviceId: d.bleDeviceId,
    deviceName: d.deviceName,
    publicKey: d.publicKey,
  );
}

BleDeviceData qrDataToDeviceData(DeviceQrData qr) {
  return BleDeviceData(
    displayDeviceId: qr.displayDeviceId,
    versionCode: qr.versionCode,
    bleDeviceId: qr.bleDeviceId,
    deviceName: qr.deviceName,
    publicKey: qr.publicKey,
  );
}

BleDeviceData savedDeviceRecordToDeviceData(SavedDeviceRecord rec) {
  return BleDeviceData(
    displayDeviceId: rec.displayDeviceId,
    versionCode: rec.versionCode,
    bleDeviceId: rec.lastBleDeviceId ?? "",
    deviceName: rec.deviceName,
    publicKey: rec.publicKey,
  );
}

DeviceQrData savedDeviceRecordToQrData(SavedDeviceRecord rec) {
  return DeviceQrData(
    displayDeviceId: rec.displayDeviceId,
    versionCode: rec.versionCode,
    bleDeviceId: rec.lastBleDeviceId ?? "",
    deviceName: rec.deviceName,
    publicKey: rec.publicKey,
  );
}
