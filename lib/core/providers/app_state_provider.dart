import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/qr_scanner/models/device_qr_data.dart';

/// 应用全局状态
class AppState {
  final DeviceQrData? scannedDeviceData;
  // 扫码后从云端检查的绑定状态
  final bool? scannedIsBound;
  final bool? scannedIsOwner;

  const AppState({
    this.scannedDeviceData,
    this.scannedIsBound,
    this.scannedIsOwner,
  });

  AppState copyWith({
    DeviceQrData? scannedDeviceData,
    bool? scannedIsBound,
    bool? scannedIsOwner,
  }) {
    return AppState(
      scannedDeviceData: scannedDeviceData ?? this.scannedDeviceData,
      scannedIsBound: scannedIsBound ?? this.scannedIsBound,
      scannedIsOwner: scannedIsOwner ?? this.scannedIsOwner,
    );
  }
}

/// 应用状态管理器
class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier() : super(const AppState());

  /// 设置扫描到的设备数据
  void setScannedDeviceData(DeviceQrData deviceData) {
    state = state.copyWith(
      scannedDeviceData: deviceData,
      // 重置绑定检查结果，等待新检查
      scannedIsBound: null,
      scannedIsOwner: null,
    );
  }

  /// 清空扫描数据
  void clearScannedDeviceData() {
    state = state.copyWith(
      scannedDeviceData: null,
      scannedIsBound: null,
      scannedIsOwner: null,
    );
  }

  /// 根据设备ID获取扫描数据
  DeviceQrData? getDeviceDataById(String deviceId) {
    if (state.scannedDeviceData?.deviceId == deviceId) {
      return state.scannedDeviceData;
    }
    return null;
  }

  /// 记录扫码绑定检查结果
  void setScannedBindingStatus({required bool isBound, required bool isOwner}) {
    state = state.copyWith(scannedIsBound: isBound, scannedIsOwner: isOwner);
  }
}

/// 全局应用状态Provider
final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier();
});
