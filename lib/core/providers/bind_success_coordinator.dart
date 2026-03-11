import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../log/app_log.dart';
import '../models/device_qr_data.dart';
import 'ble_connection_provider.dart' as conn;
import 'saved_devices_provider.dart';

class BindSuccessCoordinator {
  BindSuccessCoordinator(this._ref);

  final Ref _ref;

  Future<void> onBindSuccess(DeviceQrData device) async {
    final deviceNotifier = _ref.read(savedDevicesProvider.notifier);
    final bleNotifier = _ref.read(conn.bleConnectionProvider.notifier);

    try {
      await deviceNotifier.addOrSelectLocalFromQr(device);
    } catch (e, st) {
      AppLog.instance.error(
        'bind success local insert failed',
        tag: 'BindSuccessCoordinator',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }

    try {
      bleNotifier.syncDeviceInfoAfterBind();
    } catch (e, st) {
      AppLog.instance.warning(
        'bind success device.info sync trigger failed',
        tag: 'BindSuccessCoordinator',
        error: e,
        stackTrace: st,
      );
    }

    unawaited(_syncInBackground(deviceNotifier));
  }

  Future<void> _syncInBackground(SavedDevicesNotifier deviceNotifier) async {
    final synced = await deviceNotifier.syncFromServer();
    if (!synced) {
      AppLog.instance.warning(
        'background sync after bind failed',
        tag: 'BindSuccessCoordinator',
      );
    }
  }
}

final bindSuccessCoordinatorProvider = Provider<BindSuccessCoordinator>((ref) {
  return BindSuccessCoordinator(ref);
});
