import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_display_mobile/data/repositories/saved_devices_repository.dart';
import '../models/device_qr_data.dart';
import 'ble_connection_provider.dart';
import '../providers/locale_provider.dart';
import '../../l10n/app_localizations_en.dart';
import '../../l10n/app_localizations_zh.dart';

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
    // Load local cache first for instant UI
    final list = await _repo.loadLocal();
    final last = await _repo.loadLastSelectedId();
    state = SavedDevicesState(devices: list, lastSelectedId: last ?? (list.isNotEmpty ? list.last.displayDeviceId : null), loaded: true);
  }

  Future<void> syncFromServer({bool allowToast = false}) async {
    // Show top toast for syncing
    if (allowToast) {
      final locale = _ref.read(localeProvider);
      final l10n = (locale?.languageCode == 'zh') ? AppLocalizationsZh() : AppLocalizationsEn();
      Fluttertoast.showToast(msg: l10n.sync_devices_in_progress, gravity: ToastGravity.TOP);
    }
    try {
      final remote = await _repo.fetchRemote();
      await _repo.saveLocal(remote);
      // Preserve lastSelectedId if still valid; otherwise pick last
      final currentSelected = state.lastSelectedId;
      final stillExists = remote.any((e) => e.displayDeviceId == currentSelected);
      final selected = stillExists
          ? currentSelected
          : (remote.isNotEmpty ? remote.last.displayDeviceId : null);
      state = state.copyWith(devices: remote, lastSelectedId: selected);
      if(allowToast) {
        final locale = _ref.read(localeProvider);
        final l10n = (locale?.languageCode == 'zh') ? AppLocalizationsZh() : AppLocalizationsEn();
        Fluttertoast.showToast(msg: l10n.sync_devices_success, gravity: ToastGravity.TOP);
      }
    } catch (e) {
      if (allowToast) {
        final locale = _ref.read(localeProvider);
        final l10n = (locale?.languageCode == 'zh') ? AppLocalizationsZh() : AppLocalizationsEn();
        Fluttertoast.showToast(msg: l10n.sync_devices_failed, gravity: ToastGravity.TOP);
      }
    }
  }

  // 覆盖（叠加）从 BLE 即时获取的设备信息，基于最新远端列表进行本地增强
  Future<void> overlayInlineInfo({
    required String displayDeviceId,
    String? firmwareVersion,
    String? networkSummary,
    String? lastBleDeviceId,
  }) async {
    // 确保有最新的远端数据
    if (!state.loaded || state.devices.isEmpty) {
      try {
        await syncFromServer();
      } catch (_) {}
    }

    final updated = state.devices.map((e) {
      if (e.displayDeviceId != displayDeviceId) return e;
      return e.copyWith(
        firmwareVersion: firmwareVersion ?? e.firmwareVersion,
        networkSummary: networkSummary ?? e.networkSummary,
        lastBleDeviceId: lastBleDeviceId ?? e.lastBleDeviceId,
      );
    }).toList();

    state = state.copyWith(devices: updated);
    // 持久化本地缓存（不影响远端源）
    await _repo.saveLocal(updated);
  }

  // 局部字段更新：只在本地列表与缓存中更新指定字段，不触发远端同步
  Future<void> updateFields({
    required String displayDeviceId,
    String? deviceName,
    String? publicKey,
    String? lastBleDeviceId,
    DateTime? lastConnectedAt,
    String? firmwareVersion,
    String? networkSummary,
  }) async {
    // 确保已加载本地数据（不访问远端）
    if (!state.loaded) {
      try {
        await load();
      } catch (_) {}
    }

    final hasDevice = state.devices.any((e) => e.displayDeviceId == displayDeviceId);
    if (!hasDevice) return; // 若不存在则忽略

    final updated = state.devices.map((e) {
      if (e.displayDeviceId != displayDeviceId) return e;
      return e.copyWith(
        deviceName: deviceName ?? e.deviceName,
        publicKey: publicKey ?? e.publicKey,
        lastBleDeviceId: lastBleDeviceId ?? e.lastBleDeviceId,
        lastConnectedAt: lastConnectedAt ?? e.lastConnectedAt,
        firmwareVersion: firmwareVersion ?? e.firmwareVersion,
        networkSummary: networkSummary ?? e.networkSummary,
      );
    }).toList();

    state = state.copyWith(devices: updated);
    await _repo.saveLocal(updated);
  }

  Future<void> selectFromQr(DeviceQrData qr) async {
    await _repo.selectFromQr(qr);
    // Keep behavior consistent: refresh local state and mark selection
    await load();
    await select(qr.displayDeviceId);
  }

  Future<void> select(String displayDeviceId) async {
    await _repo.saveLastSelectedId(displayDeviceId);
    state = state.copyWith(lastSelectedId: displayDeviceId);
  }

  Future<void> removeDevice(String displayDeviceId) async {
    // 检查是否是当前连接的设备，如果是则先断开连接
    final bleConnectionNotifier = _ref.read(bleConnectionProvider.notifier);
    final currentConnectionState = _ref.read(bleConnectionProvider);

    // 如果当前有连接的设备且设备ID匹配，先断开连接
    if (currentConnectionState.bleDeviceData?.displayDeviceId == displayDeviceId) {
      print('🔌 删除设备前先断开BLE连接: $displayDeviceId');
      await bleConnectionNotifier.disconnect();
      print('✅ BLE连接已断开');
    }

    await _repo.removeDevice(displayDeviceId);
    await load(); // 重新加载状态
  }

  // 清空当前用户的本地设备列表与选择（用于登出）
  Future<void> clearForLogout() async {
    await _repo.clearCurrentUserData();
    state = const SavedDevicesState(devices: [], lastSelectedId: null, loaded: true);
  }

  SavedDeviceRecord? get selected => state.devices.firstWhere((e) => e.displayDeviceId == state.lastSelectedId, orElse: () => const SavedDeviceRecord(displayDeviceId: '', deviceName: '', publicKey: ''));

  bool contains(String deviceId) => state.devices.any((e) => e.displayDeviceId == deviceId);
}

final savedDevicesProvider = StateNotifierProvider<SavedDevicesNotifier, SavedDevicesState>((ref) {
  return SavedDevicesNotifier(SavedDevicesRepository(), ref);
});
