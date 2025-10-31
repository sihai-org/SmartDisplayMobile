import '../ble/ble_device_data.dart';
import '../models/device_qr_data.dart';

DeviceQrData deviceDataToQrData(BleDeviceData d) {
  return DeviceQrData(
    displayDeviceId: d.displayDeviceId,
    bleDeviceId: d.bleDeviceId,
    deviceName: d.deviceName,
    publicKey: d.publicKey,
  );
}

BleDeviceData qrDataToDeviceData(DeviceQrData qr) {
  return BleDeviceData(
    displayDeviceId: qr.displayDeviceId,
    bleDeviceId: qr.bleDeviceId,
    deviceName: qr.deviceName,
    publicKey: qr.publicKey,
  );
}
