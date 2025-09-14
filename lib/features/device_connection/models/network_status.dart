import 'dart:convert';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'network_status.freezed.dart';
part 'network_status.g.dart';

/// 设备网络连接状态
@freezed
class NetworkStatus with _$NetworkStatus {
  const factory NetworkStatus({
    @Default(false) bool connected,
    String? ssid,
    String? ip,
    int? signal,      // RSSI值
    int? frequency,   // 频率
  }) = _NetworkStatus;

  factory NetworkStatus.fromJson(Map<String, dynamic> json) =>
      _$NetworkStatusFromJson(json);
}

/// 网络状态扩展方法
extension NetworkStatusExtensions on NetworkStatus {
  /// 获取信号强度描述
  String get signalDescription {
    if (signal == null) return '未知';
    if (signal! >= -50) return '优秀';
    if (signal! >= -60) return '良好';
    if (signal! >= -70) return '一般';
    return '较弱';
  }

  /// 获取信号强度图标数量 (1-4)
  int get signalBars {
    if (signal == null) return 0;
    if (signal! >= -50) return 4;
    if (signal! >= -60) return 3;
    if (signal! >= -70) return 2;
    return 1;
  }

  /// 是否为5G网络
  bool get is5GHz {
    return frequency != null && frequency! > 5000;
  }

  /// 格式化显示的SSID（移除引号）
  String? get displaySsid {
    if (ssid == null) return null;
    return ssid!.replaceAll(RegExp(r'^"|"$'), '');
  }
}

/// 从BLE特征数据解析网络状态
class NetworkStatusParser {
  static NetworkStatus? fromBleData(List<int> data) {
    try {
      final jsonString = utf8.decode(data);
      final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
      return NetworkStatus.fromJson(jsonMap);
    } catch (e) {
      print('解析网络状态数据失败: $e');
      return null;
    }
  }
}