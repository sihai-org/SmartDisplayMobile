import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/drivers_repository.dart';
import '../models/driver_binding.dart';

class DriversState {
  final List<DriverBinding> drivers;
  final bool loaded;

  const DriversState({this.drivers = const [], this.loaded = false});

  DriversState copyWith({List<DriverBinding>? drivers, bool? loaded}) =>
      DriversState(
        drivers: drivers ?? this.drivers,
        loaded: loaded ?? this.loaded,
      );
}

class DriversNotifier extends StateNotifier<DriversState> {
  DriversNotifier(this._repo) : super(const DriversState());

  final DriversRepository _repo;

  Future<void> ensureLocalLoaded() async {
    if (state.loaded) return;
    final list = await _repo.loadLocal();
    state = DriversState(drivers: list, loaded: true);
  }

  /// 绑定龙虾驱动到指定设备：调用 repo（当前 mock），成功后落本地。
  /// 同 driver_hw_id 已存在则覆盖。
  Future<DriverBinding> bind({
    required String deviceId,
    required String driverHwId,
    String? deviceName,
  }) async {
    await ensureLocalLoaded();
    final record = await _repo.bind(
      deviceId: deviceId,
      driverHwId: driverHwId,
      deviceName: deviceName,
    );
    final updated = [...state.drivers];
    final idx = updated.indexWhere((e) => e.driverHwId == record.driverHwId);
    if (idx >= 0) {
      updated[idx] = record;
    } else {
      updated.add(record);
    }
    state = state.copyWith(drivers: updated, loaded: true);
    await _repo.saveLocal(updated);
    return record;
  }

  Future<void> clearForLogout() async {
    await _repo.clearCurrentUserData();
    state = const DriversState(drivers: [], loaded: true);
  }
}

final driversProvider =
    StateNotifierProvider<DriversNotifier, DriversState>((ref) {
      return DriversNotifier(DriversRepository());
    });
