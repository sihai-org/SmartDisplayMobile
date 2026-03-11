import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../log/app_log.dart';
import '../../data/repositories/saved_devices_repository.dart';
import 'ble_connection_provider.dart' as conn;
import 'saved_devices_provider.dart';

class DeviceUnbindCoordinator {
  DeviceUnbindCoordinator(this._ref);

  final Ref _ref;

  Future<bool> unbindDevice(SavedDeviceRecord device) async {
    try {
      final connState = _ref.read(conn.bleConnectionProvider);
      if (connState.bleDeviceData?.displayDeviceId != device.displayDeviceId) {
        return false;
      }

      final bleNotifier = _ref.read(conn.bleConnectionProvider.notifier);
      final deviceNotifier = _ref.read(savedDevicesProvider.notifier);

      final ok = await bleNotifier.sendDeviceLogout();
      if (!ok) {
        return false;
      }

      unawaited(
        _finalizeUnbind(
          displayDeviceId: device.displayDeviceId,
          bleNotifier: bleNotifier,
          deviceNotifier: deviceNotifier,
        ),
      );

      return true;
    } catch (e, st) {
      AppLog.instance.error(
        'unbindDevice failed',
        tag: 'DeviceUnbindCoordinator',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  Future<void> _finalizeUnbind({
    required String displayDeviceId,
    required conn.BleConnectionNotifier bleNotifier,
    required SavedDevicesNotifier deviceNotifier,
  }) async {
    try {
      await deviceNotifier.removeDeviceLocally(displayDeviceId);
    } catch (e, st) {
      AppLog.instance.warning(
        'unbind local remove failed',
        tag: 'DeviceUnbindCoordinator',
        error: e,
        stackTrace: st,
      );
    }

    try {
      await bleNotifier.disconnect();
    } catch (e, st) {
      AppLog.instance.warning(
        'unbind disconnect failed',
        tag: 'DeviceUnbindCoordinator',
        error: e,
        stackTrace: st,
      );
    }

    try {
      await deviceNotifier.syncFromServer();
    } catch (e, st) {
      AppLog.instance.warning(
        'unbind sync failed',
        tag: 'DeviceUnbindCoordinator',
        error: e,
        stackTrace: st,
      );
    }
  }
}

final deviceUnbindCoordinatorProvider = Provider<DeviceUnbindCoordinator>((
  ref,
) {
  return DeviceUnbindCoordinator(ref);
});
