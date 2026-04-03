import 'package:flutter/foundation.dart';
import '../models/device_qr_data.dart';
import '../log/app_log.dart';

final validUrlHosts = [
  'm.vzngpt.com',
  'vzngpt.com',
  'm.smartdisplay.mareo.ai',
  'smartdisplay.mareo.ai',
];

/// QR码数据解析工具
class QrDataParser {
  /// 从 QR 码内容创建设备数据
  /// 紧凑URL格式：https://m.vzngpt.com/launch.html?ts=...&id=...&n=...&fv=...&ba=...&pk=...
  static DeviceQrData fromQrContent(String qrContent) {
    final trimmed = qrContent.trim();
    AppLog.instance.debug(
      "📷 QrDataParser 收到内容(${trimmed.length}): $trimmed",
      tag: 'QR',
    );

    // 紧凑URL（含自定义 scheme）
    try {
      final uri = Uri.parse(trimmed);
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        // 允许 vzngpt.com 与 m.vzngpt.com，路径为 /launch.html 或 /connect
        final hostOk = validUrlHosts.contains(uri.host);
        final pathOk = uri.path == '/launch.html' || uri.path == '/connect';
        if (hostOk && pathOk) {
          String? tsStr = uri.queryParameters['ts'];
          String? id = uri.queryParameters['id'];
          final versionCode = _parseVersionCode(uri.queryParameters['vc']);
          String? ble = uri.queryParameters['ble'];
          String? name = uri.queryParameters['n'];
          String? pk = uri.queryParameters['pk'];
          int? ts = int.tryParse(tsStr ?? '');

          if (id != null && name != null && pk != null) {
            final data = DeviceQrData(
              displayDeviceId: id,
              versionCode: versionCode,
              bleDeviceId: ble ?? '',
              deviceName: name,
              publicKey: pk,
              timestamp: ts,
            );
            if (kDebugMode) {
              AppLog.instance.debug(
                '✅ 紧凑URL解析成功: id=$id, vc=$versionCode, name=$name',
                tag: 'QR',
              );
            }
            return data;
          } else {
            throw const FormatException('紧凑URL缺少必要参数');
          }
        }
      } else if (uri.scheme == 'smartdisplay') {
        // 自定义 Scheme：仅支持 smartdisplay://connect?...
        final target = uri.host.isNotEmpty
            ? uri.host
            : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
        if (target == 'connect') {
          String? tsStr = uri.queryParameters['ts'];
          String? id = uri.queryParameters['id'];
          final versionCode = _parseVersionCode(uri.queryParameters['vc']);
          String? ble = uri.queryParameters['ble'];
          String? name = uri.queryParameters['n'];
          String? pk = uri.queryParameters['pk'];
          int? ts = int.tryParse(tsStr ?? '');

          if (id != null && name != null && pk != null) {
            final data = DeviceQrData(
              displayDeviceId: id,
              versionCode: versionCode,
              bleDeviceId: ble ?? '',
              deviceName: name,
              publicKey: pk,
              timestamp: ts,
            );
            if (kDebugMode) {
              AppLog.instance.debug(
                '✅ 自定义scheme解析成功: id=$id, vc=$versionCode, name=$name',
                tag: 'QR',
              );
            }
            return data;
          } else {
            throw const FormatException('自定义scheme缺少必要参数');
          }
        }
      }
    } catch (e) {
      // 继续抛出到上层处理
      throw FormatException('❌ URL 格式解析失败: $e');
    }

    // 非支持格式，判定为非法
    throw FormatException("❌ 非法二维码内容（不符合 JSON 或 指定 URL 紧凑格式）: $trimmed");
  }

  static int? _parseVersionCode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null) {
      throw FormatException('vc 不是合法整数: $raw');
    }
    return value;
  }
}
