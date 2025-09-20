import 'dart:convert';
import '../models/device_qr_data.dart';

/// QR码数据解析工具
class QrDataParser {
  /// 从 QR 码内容创建设备数据
  static DeviceQrData fromQrContent(String qrContent) {
    final trimmed = qrContent.trim();
    print("📷 QrDataParser 收到内容(${trimmed.length}): $trimmed");

    // 明显是 JSON 格式
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final Map<String, dynamic> json = jsonDecode(trimmed);
        final deviceData = DeviceQrData.fromJson(json);

        print("✅ 解析成功: deviceId=${deviceData.deviceId}, "
            "deviceName=${deviceData.deviceName}");
        return deviceData;
      } catch (e) {
        throw FormatException("❌ 无法解析二维码 JSON: $e, 内容=$trimmed");
      }
    }

    // 非 JSON，判定为非法
    throw FormatException("❌ 非法二维码内容（不是 JSON）: $trimmed");
  }
}
