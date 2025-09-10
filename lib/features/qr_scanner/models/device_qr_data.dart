import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_qr_data.freezed.dart';
part 'device_qr_data.g.dart';

/// QR码中包含的设备信息
@freezed
class DeviceQrData with _$DeviceQrData {
  const factory DeviceQrData({
    /// 设备ID
    required String deviceId,
    /// 设备名称
    required String deviceName,
    /// BLE设备MAC地址
    required String bleAddress,
    /// 设备公钥（用于加密握手）
    required String publicKey,
    /// 设备类型
    @Default('smart_display') String deviceType,
    /// 固件版本
    String? firmwareVersion,
    /// 生成时间戳
    int? timestamp,
  }) = _DeviceQrData;

  factory DeviceQrData.fromJson(Map<String, Object?> json) =>
      _$DeviceQrDataFromJson(json);
}

/// QR码扫描结果
@freezed
class QrScanResult with _$QrScanResult {
  const factory QrScanResult.success(DeviceQrData deviceData) = _Success;
  const factory QrScanResult.error(String message) = _Error;
  const factory QrScanResult.cancelled() = _Cancelled;
}