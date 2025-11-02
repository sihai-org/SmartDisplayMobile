import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/device_qr_data.dart';

/// 应用全局状态
class AppState {
  // 绑定过程中的设备
  final DeviceQrData? scannedQrData;

  // 当前选中的已绑定设备id
  final String? selectedDisplayDeviceId;

  // 本应用会话内是否已在设备详情页触发过一次自动连接
  final bool didAutoConnectOnDetailPage;

  const AppState({
    this.scannedQrData,
    this.selectedDisplayDeviceId,
    this.didAutoConnectOnDetailPage = false,
  });

  AppState copyWith({
    DeviceQrData? scannedQrData,
    String? selectedDisplayDeviceId,
    bool? didAutoConnectOnDetailPage,
  }) {
    return AppState(
      scannedQrData: scannedQrData ?? this.scannedQrData,
      selectedDisplayDeviceId:
          selectedDisplayDeviceId ?? this.selectedDisplayDeviceId,
      didAutoConnectOnDetailPage:
          didAutoConnectOnDetailPage ?? this.didAutoConnectOnDetailPage,
    );
  }
}

/// 应用状态管理器
class AppStateNotifier extends StateNotifier<AppState> {
  AppStateNotifier() : super(const AppState());

  /// 设置扫描到的设备数据
  void setScannedData(DeviceQrData qrData) {
    state = state.copyWith(
      scannedQrData: qrData,
    );
  }

  /// 清空扫描数据
  void clearScannedData() {
    state = state.copyWith(
      scannedQrData: null,
    );
  }

  /// 记录本会话内已在设备详情页触发过一次自动连接
  void markAutoConnectOnDetailPage() {
    if (!state.didAutoConnectOnDetailPage) {
      state = state.copyWith(didAutoConnectOnDetailPage: true);
    }
  }
}

/// 全局应用状态Provider
final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier();
});
