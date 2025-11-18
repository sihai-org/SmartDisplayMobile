import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_display_mobile/data/repositories/saved_devices_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ble_connection_provider.dart';
import '../providers/locale_provider.dart';
import '../../l10n/app_localizations_en.dart';
import '../../l10n/app_localizations_zh.dart';
import '../log/app_log.dart';

class SavedDevicesState {
  // 设备列表
  final List<SavedDeviceRecord> devices;
  // TODO: 当前设备（校验）
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

  Future<void> _load() async {
    // Load local cache first for instant UI
    final list = await _repo.loadLocal();
    final last = await _repo.loadLastSelectedId();
    state = SavedDevicesState(devices: list, lastSelectedId: last ?? (list.isNotEmpty ? list.last.displayDeviceId : null), loaded: true);
  }

  /// 确保本地缓存已加载（仅访问本地，不触发远端同步）
  Future<void> ensureLoaded() async {
    if (state.loaded) return;
    try {
      await _load();
    } catch (_) {}
  }

  // TODO: 防抖
  Future<void> syncFromServer({bool allowToast = false}) async {
    // Require login session; skip if not logged in
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      return;
    }
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
    } catch (e, st) {
      AppLog.instance.warning(
        'syncFromServer failed',
        tag: 'Supabase',
        error: e,
        stackTrace: st,
      );
      if (allowToast) {
        final locale = _ref.read(localeProvider);
        final l10n = (locale?.languageCode == 'zh') ? AppLocalizationsZh() : AppLocalizationsEn();
        Fluttertoast.showToast(msg: l10n.sync_devices_failed, gravity: ToastGravity.TOP);
      }
    }
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

  Future<void> select(String displayDeviceId) async {
    await _repo.saveLastSelectedId(displayDeviceId);
    state = state.copyWith(lastSelectedId: displayDeviceId);
  }

  SavedDeviceRecord getSelectedRec() {
    var res = SavedDeviceRecord.empty();
    if (state.lastSelectedId == null || state.lastSelectedId!.isEmpty) {
      return res;
    }
    res = state.devices.firstWhere(
          (e) => e.displayDeviceId == state.lastSelectedId,
      orElse: () => res,
    );
    return res;
  }

  /// 判断某设备 ID 是否存在于本地缓存
  bool existsLocally(String displayDeviceId) {
    return state.devices.any((e) => e.displayDeviceId == displayDeviceId);
  }

  // 清空当前用户的本地设备列表与选择（用于登出）
  Future<void> clearForLogout() async {
    await _repo.clearCurrentUserData();
    state = const SavedDevicesState(devices: [], lastSelectedId: null, loaded: true);
  }
}

final savedDevicesProvider = StateNotifierProvider<SavedDevicesNotifier, SavedDevicesState>((ref) {
  return SavedDevicesNotifier(SavedDevicesRepository(), ref);
});
