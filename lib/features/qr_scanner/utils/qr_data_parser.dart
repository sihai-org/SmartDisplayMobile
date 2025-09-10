import 'dart:convert';
import '../models/device_qr_data.dart';

/// QR码数据解析工具
class QrDataParser {
  /// 从QR码内容创建设备数据
  static DeviceQrData fromQrContent(String qrContent) {
    try {
      // 尝试解析JSON格式
      final jsonData = jsonDecode(qrContent);
      return DeviceQrData.fromJson(jsonData);
    } catch (e) {
      // 如果不是JSON格式，创建一个简单的设备数据
      return DeviceQrData(
        deviceId: _extractDeviceIdFromContent(qrContent),
        deviceName: '扫描到的设备',
        bleAddress: '00:00:00:00:00:00',
        publicKey: qrContent, // 将整个内容作为publicKey存储
      );
    }
  }

  /// 从内容中提取设备ID（简化版本）
  static String _extractDeviceIdFromContent(String content) {
    if (content.length <= 20) {
      return content; // 如果内容较短，直接作为设备ID
    }
    // 如果内容较长，取前20个字符作为设备ID
    return content.substring(0, 20);
  }
}