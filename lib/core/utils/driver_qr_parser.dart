import 'dart:convert';

/// 龙虾驱动二维码解析。
/// 二维码内容形如：{"driver_hw_id":"xxxx"}
class DriverQrParser {
  /// 命中返回 driver_hw_id；不是龙虾二维码则返回 null（不抛异常）。
  static String? tryParse(String content) {
    final trimmed = content.trim();
    if (!trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      final hwId = decoded['driver_hw_id'];
      if (hwId is String && hwId.trim().isNotEmpty) {
        return hwId.trim();
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
