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
        final raw = jsonDecode(trimmed);
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('JSON需为对象');
        }
        final Map<String, dynamic> json = Map<String, dynamic>.from(raw);
        // 放宽：bleAddress 可缺省
        final id = (json['deviceId'] ?? '').toString();
        final name = (json['deviceName'] ?? '').toString();
        final pk = (json['publicKey'] ?? '').toString();
        final ble = (json['bleAddress'] ?? '').toString();
        final normalizedFv = _extractVersion(
              json['firmwareVersion']?.toString() ?? json['version']?.toString(),
            );
        final deviceData = DeviceQrData(
          deviceId: id,
          deviceName: name,
          bleAddress: ble, // 可为空，连接流程会扫描覆盖
          publicKey: pk,
          firmwareVersion: normalizedFv,
          timestamp: int.tryParse((json['timestamp'] ?? json['ts'] ?? '').toString()),
        );
        print("✅ 解析成功: deviceId=${deviceData.deviceId}, deviceName=${deviceData.deviceName}");
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
          String? fv = _extractVersion(uri.queryParameters['fv']);
          String? tsStr = uri.queryParameters['ts'];
          int? ts = int.tryParse(tsStr ?? '');

          if (id != null && name != null && pk != null) {
            final data = DeviceQrData(
              deviceId: id,
              deviceName: name,
              bleAddress: ble ?? '',
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
        // 自定义 Scheme：仅支持 smartdisplay://connect?...
        final target = uri.host.isNotEmpty
            ? uri.host
            : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '');
        if (target == 'connect') {
          String? id = uri.queryParameters['id'];
          String? name = uri.queryParameters['n'];
          String? ble = uri.queryParameters['ba'];
          String? pk = uri.queryParameters['pk'];
          String? fv = _extractVersion(uri.queryParameters['fv']);
          String? tsStr = uri.queryParameters['ts'];
          int? ts = int.tryParse(tsStr ?? '');

          if (id != null && name != null && pk != null) {
            final data = DeviceQrData(
              deviceId: id,
              deviceName: name,
              bleAddress: ble ?? '',
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

  // 尝试从输入中提取干净的版本号（如 v1.2.3 或 1.0.0）
  static String? _extractVersion(String? input) {
    if (input == null) return null;
    final s = input.trim();
    if (s.isEmpty) return null;
    // 若是 JSON，优先解析常见键
    if (s.startsWith('{') && s.endsWith('}')) {
      try {
        final obj = jsonDecode(s);
        if (obj is Map<String, dynamic>) {
          final direct = (obj['version'] ?? obj['firmwareVersion'] ?? obj['ver'] ?? obj['fv'] ?? obj['fw'])?.toString();
          if (direct != null && direct.isNotEmpty) return direct;
          // 从其余字段中正则提取
          for (final v in obj.values) {
            final m = _matchVersion(v?.toString());
            if (m != null && m.isNotEmpty) return m;
          }
          return null;
        }
      } catch (_) {}
    }
    return _matchVersion(s);
  }

  static String? _matchVersion(String? s) {
    if (s == null) return null;
    final reg = RegExp(r'v?\d+(?:\.\d+){1,3}');
    final m = reg.firstMatch(s);
    return m?.group(0);
  }
}
