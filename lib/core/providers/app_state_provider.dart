import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/qr_scanner/models/device_qr_data.dart';

/// 应用全局状态
class AppState {
  final DeviceQrData? scannedDeviceData;

  const AppState({
    this.scannedDeviceData,
  });

  AppState copyWith({
    DeviceQrData? scannedDeviceData,
  }) {
    return AppState(
      scannedDeviceData: scannedDeviceData ?? this.scannedDeviceData,
    );
  }
}

/// 应用状态管理器
class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier() : super(const AppState());

  /// 设置扫描到的设备数据
  void setScannedDeviceData(DeviceQrData deviceData) {
    state = state.copyWith(scannedDeviceData: deviceData);
  }

  /// 清空扫描数据
  void clearScannedDeviceData() {
    state = state.copyWith(scannedDeviceData: null);
  }

  /// 根据设备ID获取扫描数据
  DeviceQrData? getDeviceDataById(String deviceId) {
    if (state.scannedDeviceData?.deviceId == deviceId) {
      return state.scannedDeviceData;
    }
    return null;
  }
}

/// 全局应用状态Provider
final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier();
});