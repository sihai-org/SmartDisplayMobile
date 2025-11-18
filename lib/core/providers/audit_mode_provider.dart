import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../audit/audit_mode.dart';
import '../models/device_qr_data.dart';
import '../../data/repositories/saved_devices_repository.dart';
import 'saved_devices_provider.dart';
import '../log/app_log.dart';

class AuditState {
  final bool enabled;
  final DateTime? since;
  const AuditState({this.enabled = false, this.since});

  AuditState copyWith({bool? enabled, DateTime? since}) =>
      AuditState(enabled: enabled ?? this.enabled, since: since ?? this.since);
}

class AuditModeNotifier extends StateNotifier<AuditState> {
  AuditModeNotifier(this._ref) : super(const AuditState());
  final Ref _ref;

  Future<void> enable() async {
    AuditMode.enable();
    state = AuditState(enabled: true, since: DateTime.now());
    // Seed a mock device for audit mode if none exists yet
    await _seedMockDeviceIfNeeded();
    // Ensure provider state reflects saved list immediately（仅本地加载）
    await _ref.read(savedDevicesProvider.notifier).ensureLocalLoaded();
  }

  void disable() {
    AuditMode.disable();
    state = const AuditState(enabled: false, since: null);
  }

  Future<void> _seedMockDeviceIfNeeded() async {
    try {
      AppLog.instance.debug('_seedMockDeviceIfNeeded', tag: 'Audit');
      final repo = SavedDevicesRepository();
      final list = await repo.loadLocal();
      final exists = list.any((e) => e.displayDeviceId == AuditMode.mockDisplayDeviceId);
      if (!exists) {
        final mock = DeviceQrData(
          displayDeviceId: AuditMode.mockDisplayDeviceId,
          deviceName: AuditMode.mockDeviceName,
          bleDeviceId: AuditMode.mockBleDeviceId,
          publicKey: AuditMode.mockPublicKeyHex,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
        await repo.selectFromQr(mock);
      }
    } catch (_) {}
  }
}

final auditModeProvider =
    StateNotifierProvider<AuditModeNotifier, AuditState>((ref) {
  return AuditModeNotifier(ref);
});
