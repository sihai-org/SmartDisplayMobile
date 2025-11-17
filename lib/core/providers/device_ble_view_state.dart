import '../ble/ble_device_data.dart';
import '../log/app_log.dart';
import 'saved_devices_provider.dart';
import 'ble_connection_provider.dart';
import '../../data/repositories/saved_devices_repository.dart';

/// 针对“当前选中设备”的 BLE 视图状态，供 UI 使用
class DeviceBleViewState {
  /// 当前详情页/列表中选中的设备记录（可能为空记录）
  final SavedDeviceRecord currentDevice;

  /// provider 中的当前连接设备是否就是当前选中设备
  final bool isCurrentDeviceActive;

  /// 当前选中设备是否处于“正在连接/建立通道”的 loading 状态
  final bool isLoadingForCurrent;

  /// 业务语义上的 BLE 状态：只有当连接设备等于当前设备时才采用真实状态，否则视为 disconnected
  final BleDeviceStatus bleStatus;

  /// UI 展示用的状态：在 loading 中且业务状态为 disconnected/error/timeout 时，映射为 connecting
  final BleDeviceStatus uiStatus;

  const DeviceBleViewState({
    required this.currentDevice,
    required this.isCurrentDeviceActive,
    required this.isLoadingForCurrent,
    required this.bleStatus,
    required this.uiStatus,
  });

  bool get isAuthenticated => bleStatus == BleDeviceStatus.authenticated;
}

/// 基于当前 SavedDevicesState 和 BleConnectionState，计算“当前选中设备”的 BLE 视图状态
DeviceBleViewState buildDeviceBleViewStateForCurrent(
  SavedDevicesState saved,
  BleConnectionState connState,
) {
  final currentId = saved.lastSelectedId;
  final currentRec = (currentId != null)
      ? saved.devices.firstWhere(
          (e) => e.displayDeviceId == currentId,
          orElse: () => const SavedDeviceRecord.empty(),
        )
      : const SavedDeviceRecord.empty();

  final isActive =
      connState.bleDeviceData?.displayDeviceId.isNotEmpty == true &&
          connState.bleDeviceData?.displayDeviceId ==
              currentRec.displayDeviceId;

  // 原始 BLE 状态：仅当 provider 当前连接设备等于当前选中设备时才采用其真实状态，否则视为未连接
  final BleDeviceStatus bleStatus =
      isActive ? connState.bleDeviceStatus : BleDeviceStatus.disconnected;

  // 仅当“正在建立连接”的 loading 与当前选中设备匹配时，才认为该设备处于连接中
  final bool loadingForCurrent =
      connState.enableBleConnectionLoading && isActive;

  // 供 UI 使用的状态：如果当前设备处于“连接中”加载态，则视为 connecting
  final BleDeviceStatus uiStatus = loadingForCurrent &&
          (bleStatus == BleDeviceStatus.disconnected ||
              bleStatus == BleDeviceStatus.error ||
              bleStatus == BleDeviceStatus.timeout)
      ? BleDeviceStatus.connecting
      : bleStatus;

  AppLog.instance.debug(
    '[ble_connection_provider] viewState bleStatus=$bleStatus uiStatus=$uiStatus isActive=$isActive loadingForCurrent=$loadingForCurrent',
    tag: 'DeviceDetail',
  );

  return DeviceBleViewState(
    currentDevice: currentRec,
    isCurrentDeviceActive: isActive,
    isLoadingForCurrent: loadingForCurrent,
    bleStatus: bleStatus,
    uiStatus: uiStatus,
  );
}

