import 'dart:convert';
import 'package:freezed_annotation/freezed_annotation.dart';
import '../log/app_log.dart';

part 'network_status.freezed.dart';
part 'network_status.g.dart';

/// 设备网络连接状态
@freezed
class NetworkStatus with _$NetworkStatus {
  const factory NetworkStatus({
    @Default(false) bool connected,
    String? ssid,
    int? rawRssi,
  }) = _NetworkStatus;

  factory NetworkStatus.fromJson(Map<String, dynamic> json) =>
      _$NetworkStatusFromJson(json);
}

/// 网络状态扩展方法
extension NetworkStatusExtensions on NetworkStatus {
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
      AppLog.instance.warning('解析网络状态数据失败', tag: 'Network', error: e);
      return null;
    }
  }
}
