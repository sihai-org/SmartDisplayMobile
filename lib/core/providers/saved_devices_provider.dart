import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_display_mobile/data/repositories/saved_devices_repository.dart';
import '../../features/qr_scanner/models/device_qr_data.dart';
import '../../features/device_connection/providers/device_connection_provider.dart';

class SavedDevicesState {
  final List<SavedDeviceRecord> devices;
  final String? lastSelectedId;
  final bool loaded;
  const SavedDevicesState({this.devices = const [], this.lastSelectedId, this.loaded = false});

  SavedDevicesState copyWith({List<SavedDeviceRecord>? devices, String? lastSelectedId, bool? loaded}) =>
      SavedDevicesState(devices: devices ?? this.devices, lastSelectedId: lastSelectedId ?? this.lastSelectedId, loaded: loaded ?? this.loaded);
}

class SavedDevicesNotifier extends StateNotifier<SavedDevicesState> {
  SavedDevicesNotifier(this._repo, this._ref) : super(const SavedDevicesState());
  final SavedDevicesRepository _repo;
  final Ref _ref;

  Future<void> load() async {
    final list = await _repo.loadAll();
    final last = await _repo.loadLastSelectedId();
    state = SavedDevicesState(devices: list, lastSelectedId: last ?? (list.isNotEmpty ? list.last.deviceId : null), loaded: true);
  }

  Future<void> upsertFromQr(DeviceQrData qr, {String? lastBleAddress}) async {
    await _repo.upsertFromQr(qr, lastBleAddress: lastBleAddress);
    await load();
  }

  Future<void> select(String deviceId) async {
    await _repo.saveLastSelectedId(deviceId);
    state = state.copyWith(lastSelectedId: deviceId);
  }

  Future<void> removeDevice(String deviceId) async {
    // 检查是否是当前连接的设备，如果是则先断开连接
    final deviceConnectionNotifier = _ref.read(deviceConnectionProvider.notifier);
    final currentConnectionState = _ref.read(deviceConnectionProvider);

    // 如果当前有连接的设备且设备ID匹配，先断开连接
    if (currentConnectionState.deviceData?.deviceId == deviceId) {
      print('🔌 删除设备前先断开BLE连接: $deviceId');
      await deviceConnectionNotifier.disconnect();
      print('✅ BLE连接已断开');
    }

    await _repo.removeDevice(deviceId);
    await load(); // 重新加载状态
  }

  SavedDeviceRecord? get selected => state.devices.firstWhere((e) => e.deviceId == state.lastSelectedId, orElse: () => const SavedDeviceRecord(deviceId: '', deviceName: '', publicKey: ''));

  bool contains(String deviceId) => state.devices.any((e) => e.deviceId == deviceId);
}

final savedDevicesProvider = StateNotifierProvider<SavedDevicesNotifier, SavedDevicesState>((ref) {
  return SavedDevicesNotifier(SavedDevicesRepository(), ref);
});

