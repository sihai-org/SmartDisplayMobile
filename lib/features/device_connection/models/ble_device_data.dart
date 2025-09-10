import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../../qr_scanner/models/device_qr_data.dart';

part 'ble_device_data.freezed.dart';
part 'ble_device_data.g.dart';

/// BLE设备连接状态
enum BleDeviceStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  authenticating,
  authenticated,
  error,
  timeout,
}

/// BLE设备信息
@freezed
class BleDeviceData with _$BleDeviceData {
  const factory BleDeviceData({
    /// 设备ID
    required String deviceId,
    /// 设备名称
    required String deviceName,
    /// BLE设备地址
    required String bleAddress,
    /// 设备公钥
    required String publicKey,
    /// 连接状态
    @Default(BleDeviceStatus.disconnected) BleDeviceStatus status,
    /// RSSI信号强度
    int? rssi,
    /// MTU大小
    @Default(23) int mtu,
    /// 连接时间戳
    DateTime? connectedAt,
    /// 错误信息
    String? errorMessage,
  }) = _BleDeviceData;

  factory BleDeviceData.fromJson(Map<String, Object?> json) =>
      _$BleDeviceDataFromJson(json);
}

/// BLE连接结果
@freezed
class BleConnectionResult with _$BleConnectionResult {
  const factory BleConnectionResult.success(BleDeviceData device) = _Success;
  const factory BleConnectionResult.error(String message) = _Error;
  const factory BleConnectionResult.timeout() = _Timeout;
  const factory BleConnectionResult.cancelled() = _Cancelled;
}

/// BLE扫描结果
@freezed
class BleScanResult with _$BleScanResult {
  const factory BleScanResult({
    required String deviceId,
    required String name,
    required String address,
    required int rssi,
    required DateTime timestamp,
    Map<String, dynamic>? advertisementData,
  }) = _BleScanResult;

  factory BleScanResult.fromDiscoveredDevice(DiscoveredDevice device) {
    // 转换serviceData从Map<Uuid, Uint8List>到Map<String, dynamic>
    Map<String, dynamic>? convertedServiceData;
    if (device.serviceData.isNotEmpty) {
      convertedServiceData = <String, dynamic>{};
      device.serviceData.forEach((uuid, data) {
        convertedServiceData![uuid.toString()] = data.toList();
      });
    }
    
    return BleScanResult(
      deviceId: device.id,
      name: device.name.isNotEmpty ? device.name : 'Unknown Device',
      address: device.id,
      rssi: device.rssi,
      timestamp: DateTime.now(),
      advertisementData: convertedServiceData,
    );
  }
}

/// BLE GATT服务信息
@freezed
class BleServiceInfo with _$BleServiceInfo {
  const factory BleServiceInfo({
    required String serviceUuid,
    required List<BleCharacteristicInfo> characteristics,
  }) = _BleServiceInfo;
}

/// BLE GATT特征值信息
@freezed
class BleCharacteristicInfo with _$BleCharacteristicInfo {
  const factory BleCharacteristicInfo({
    required String characteristicUuid,
    required bool canRead,
    required bool canWrite,
    required bool canNotify,
    required bool canIndicate,
  }) = _BleCharacteristicInfo;
}

/// BleDeviceData 扩展方法
extension BleDeviceDataExtension on BleDeviceData {
  /// 从QR码数据创建BLE设备数据
  static BleDeviceData fromQrData(DeviceQrData qrData) {
    return BleDeviceData(
      deviceId: qrData.deviceId,
      deviceName: qrData.deviceName,
      bleAddress: qrData.bleAddress,
      publicKey: qrData.publicKey,
      status: BleDeviceStatus.disconnected,
    );
  }
}