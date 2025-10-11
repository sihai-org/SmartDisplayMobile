import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/device_qr_data.dart';

/// QR码数据解析工具
class QrDataParser {
  /// 从 QR 码内容创建设备数据
  /// 支持两种格式：
  /// 1) JSON（历史格式）
  /// 2) URL 紧凑格式：https://m.smartdisplay.mareo.ai/launch.html?ts=...&id=...&n=...&fv=...&ba=...&pk=...
  static DeviceQrData fromQrContent(String qrContent) {
    final trimmed = qrContent.trim();
    print("📷 QrDataParser 收到内容(${trimmed.length}): $trimmed");

    // 1) 明显是 JSON 格式
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

    // 2) URL 紧凑格式（含自定义 scheme）
    try {
      final uri = Uri.parse(trimmed);
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        // 允许 smartdisplay.mareo.ai 与 m.smartdisplay.mareo.ai，路径为 /launch.html 或 /connect
        final hostOk = uri.host == 'm.smartdisplay.mareo.ai' || uri.host == 'smartdisplay.mareo.ai';
        final pathOk = uri.path == '/launch.html' || uri.path == '/connect';
        if (hostOk && pathOk) {
          String? id = uri.queryParameters['id'];
          String? name = uri.queryParameters['n'];
          String? ble = uri.queryParameters['ba'];
          String? pk = uri.queryParameters['pk'];
          String? fv = uri.queryParameters['fv'];
          String? tsStr = uri.queryParameters['ts'];
          int? ts = int.tryParse(tsStr ?? '');

          if (id != null && name != null && ble != null && pk != null) {
            final data = DeviceQrData(
              deviceId: id,
              deviceName: name,
              bleAddress: ble,
              publicKey: pk,
              firmwareVersion: fv,
              timestamp: ts,
            );
            if (kDebugMode) {
              print('✅ 紧凑URL解析成功: id=$id, name=$name');
            }
            return data;
          } else {
            throw FormatException('紧凑URL缺少必要参数');
          }
        }
      } else if (uri.scheme == 'smartdisplay') {
        // 自定义 Scheme: smartdisplay://connect?...
        final target = uri.host.isNotEmpty ? uri.host : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
        if (target == 'connect') {
          String? id = uri.queryParameters['id'];
          String? name = uri.queryParameters['n'];
          String? ble = uri.queryParameters['ba'];
          String? pk = uri.queryParameters['pk'];
          String? fv = uri.queryParameters['fv'];
          String? tsStr = uri.queryParameters['ts'];
          int? ts = int.tryParse(tsStr ?? '');

          if (id != null && name != null && ble != null && pk != null) {
            final data = DeviceQrData(
              deviceId: id,
              deviceName: name,
              bleAddress: ble,
              publicKey: pk,
              firmwareVersion: fv,
              timestamp: ts,
            );
            if (kDebugMode) {
              print('✅ 自定义scheme解析成功: id=$id, name=$name');
            }
            return data;
          } else {
            throw FormatException('自定义scheme缺少必要参数');
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
}
