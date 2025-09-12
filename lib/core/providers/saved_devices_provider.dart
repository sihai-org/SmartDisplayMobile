import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_display_mobile/data/repositories/saved_devices_repository.dart';
import '../../features/qr_scanner/models/device_qr_data.dart';

class SavedDevicesState {
  final List<SavedDeviceRecord> devices;
  final String? lastSelectedId;
  final bool loaded;
  const SavedDevicesState({this.devices = const [], this.lastSelectedId, this.loaded = false});

  SavedDevicesState copyWith({List<SavedDeviceRecord>? devices, String? lastSelectedId, bool? loaded}) =>
      SavedDevicesState(devices: devices ?? this.devices, lastSelectedId: lastSelectedId ?? this.lastSelectedId, loaded: loaded ?? this.loaded);
}

class SavedDevicesNotifier extends StateNotifier<SavedDevicesState> {
  SavedDevicesNotifier(this._repo) : super(const SavedDevicesState());
  final SavedDevicesRepository _repo;

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

  SavedDeviceRecord? get selected => state.devices.firstWhere((e) => e.deviceId == state.lastSelectedId, orElse: () => const SavedDeviceRecord(deviceId: '', deviceName: '', publicKey: ''));

  bool contains(String deviceId) => state.devices.any((e) => e.deviceId == deviceId);
}

final savedDevicesProvider = StateNotifierProvider<SavedDevicesNotifier, SavedDevicesState>((ref) {
  return SavedDevicesNotifier(SavedDevicesRepository());
});

