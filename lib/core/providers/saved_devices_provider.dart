import 'package:collection/collection.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_display_mobile/core/auth/auth_manager.dart';
import 'package:smart_display_mobile/data/repositories/saved_devices_repository.dart';
import '../models/device_qr_data.dart';
import '../providers/locale_provider.dart';
import '../../l10n/app_localizations_en.dart';
import '../../l10n/app_localizations_zh.dart';
import '../log/app_log.dart';

class SavedDevicesState {
  static const _unset = Object();
  // 设备列表
  final List<SavedDeviceRecord> devices;
  // TODO: 当前设备（校验）
  final String? lastSelectedId;

  final bool loaded;
  const SavedDevicesState({
    this.devices = const [],
    this.lastSelectedId,
    this.loaded = false,
  });

  SavedDevicesState copyWith({
    List<SavedDeviceRecord>? devices,
    Object? lastSelectedId = _unset,
    bool? loaded,
  }) => SavedDevicesState(
    devices: devices ?? this.devices,
    lastSelectedId: identical(lastSelectedId, _unset)
        ? this.lastSelectedId
        : lastSelectedId as String?,
    loaded: loaded ?? this.loaded,
  );
}

class SavedDevicesNotifier extends StateNotifier<SavedDevicesState> {
  SavedDevicesNotifier(this._repo, this._ref)
    : super(const SavedDevicesState());
  final SavedDevicesRepository _repo;
  final Ref _ref;

  /// 确保本地缓存已加载（仅访问本地，不触发远端同步）
  Future<void> ensureLocalLoaded() async {
    if (state.loaded) return;
    try {
      final list = await _repo.loadLocal();
      final last = await _repo.loadLastSelectedId();
      state = SavedDevicesState(
        devices: list,
        lastSelectedId:
            last ?? (list.isNotEmpty ? list.last.displayDeviceId : null),
        loaded: true,
      );
    } catch (_) {}
  }

  // TODO: 防抖
  Future<bool> syncFromServer({bool allowToast = false}) async {
    // 保证本地已加载
    await ensureLocalLoaded();

    try {
      // Require login session; skip if not logged in
      final session = await AuthManager.instance.ensureFreshSession();
      if (session == null) {
        return false;
      }
      // Show top toast for syncing
      if (allowToast) {
        final locale = _ref.read(localeProvider);
        final l10n = (locale?.languageCode == 'zh')
            ? AppLocalizationsZh()
            : AppLocalizationsEn();
        Fluttertoast.showToast(
          msg: l10n.sync_devices_in_progress,
          gravity: ToastGravity.TOP,
        );
      }
      final remote = await _repo.fetchRemote();
      // 仅保留本地的 lastConnectedAt（上次 BLE 连接时间），远端不提供该字段
      final local = state.devices;
      final merged = remote.map((r) {
        final localRec = local
            .where((e) => e.displayDeviceId == r.displayDeviceId)
            .firstOrNull;
        if (localRec != null) {
          return r.copyWith(
            versionCode: localRec.versionCode,
            lastConnectedAt: localRec.lastConnectedAt,
          );
        }
        return r;
      }).toList();
      await _repo.saveLocal(merged);
      // Preserve lastSelectedId if still valid; otherwise pick last
      final currentSelected = state.lastSelectedId;
      final stillExists = merged.any(
        (e) => e.displayDeviceId == currentSelected,
      );
      final selected = stillExists
          ? currentSelected
          : (merged.isNotEmpty ? merged.last.displayDeviceId : null);
      state = state.copyWith(devices: merged, lastSelectedId: selected);
      if (allowToast) {
        final locale = _ref.read(localeProvider);
        final l10n = (locale?.languageCode == 'zh')
            ? AppLocalizationsZh()
            : AppLocalizationsEn();
        Fluttertoast.showToast(
          msg: l10n.sync_devices_success,
          gravity: ToastGravity.TOP,
        );
      }
      return true;
    } catch (e, st) {
      AppLog.instance.error(
        'syncFromServer failed',
        tag: 'Supabase',
        error: e,
        stackTrace: st,
      );
      if (allowToast) {
        final locale = _ref.read(localeProvider);
        final l10n = (locale?.languageCode == 'zh')
            ? AppLocalizationsZh()
            : AppLocalizationsEn();
        Fluttertoast.showToast(
          msg: l10n.sync_devices_failed,
          gravity: ToastGravity.TOP,
        );
      }
      return false;
    }
  }

  Future<void> addOrSelectLocalFromQr(DeviceQrData qr) async {
    await ensureLocalLoaded();

    final updated = [...state.devices];
    final idx = updated.indexWhere(
      (e) => e.displayDeviceId == qr.displayDeviceId,
    );
    final now = DateTime.now();

    if (idx >= 0) {
      final current = updated[idx];
      updated[idx] = current.copyWith(
        deviceName: qr.deviceName.isNotEmpty
            ? qr.deviceName
            : current.deviceName,
        publicKey: qr.publicKey.isNotEmpty ? qr.publicKey : current.publicKey,
        versionCode: qr.versionCode,
        lastBleDeviceId: qr.bleDeviceId.isNotEmpty
            ? qr.bleDeviceId
            : current.lastBleDeviceId,
        lastConnectedAt: now,
      );
    } else {
      updated.add(
        SavedDeviceRecord(
          displayDeviceId: qr.displayDeviceId,
          versionCode: qr.versionCode,
          deviceName: qr.deviceName,
          publicKey: qr.publicKey,
          lastBleDeviceId: qr.bleDeviceId,
          lastConnectedAt: now,
        ),
      );
    }

    state = state.copyWith(
      devices: updated,
      lastSelectedId: qr.displayDeviceId,
      loaded: true,
    );
    await _repo.saveLocal(updated);
    await _repo.saveLastSelectedId(qr.displayDeviceId);
  }

  // 局部字段更新：只在本地列表与缓存中更新指定字段，不触发远端同步
  Future<void> updateFields({
    required String displayDeviceId,
    int? versionCode,
    String? deviceName,
    String? publicKey,
    String? lastBleDeviceId,
    DateTime? lastConnectedAt,
    String? firmwareVersion,
    String? networkSummary,
  }) async {
    final hasDevice = state.devices.any(
      (e) => e.displayDeviceId == displayDeviceId,
    );
    if (!hasDevice) return; // 若不存在则忽略

    final updated = state.devices.map((e) {
      if (e.displayDeviceId != displayDeviceId) return e;
      return e.copyWith(
        versionCode: versionCode ?? e.versionCode,
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

  Future<void> removeDeviceLocally(String displayDeviceId) async {
    await ensureLocalLoaded();

    final updated = state.devices
        .where((e) => e.displayDeviceId != displayDeviceId)
        .toList();
    final selected = state.lastSelectedId == displayDeviceId
        ? (updated.isNotEmpty ? updated.last.displayDeviceId : null)
        : state.lastSelectedId;

    state = state.copyWith(devices: updated, lastSelectedId: selected);
    await _repo.saveLocal(updated);

    if (selected == null) {
      await _repo.clearLastSelectedId();
      return;
    }

    await _repo.saveLastSelectedId(selected);
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

  /// 根据 ID 查找 SavedDeviceRecord，不存在返回 null
  SavedDeviceRecord? findById(String displayDeviceId) {
    try {
      return state.devices.firstWhere(
        (e) => e.displayDeviceId == displayDeviceId,
      );
    } catch (_) {
      return null;
    }
  }

  // 清空当前用户的本地设备列表与选择（用于登出）
  Future<void> clearForLogout() async {
    await _repo.clearCurrentUserData();
    state = const SavedDevicesState(
      devices: [],
      lastSelectedId: null,
      loaded: true,
    );
  }
}

final savedDevicesProvider =
    StateNotifierProvider<SavedDevicesNotifier, SavedDevicesState>((ref) {
      return SavedDevicesNotifier(SavedDevicesRepository(), ref);
    });
