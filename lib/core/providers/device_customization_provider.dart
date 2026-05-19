import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:smart_display_mobile/core/auth/auth_manager.dart';
import 'package:smart_display_mobile/core/constants/app_environment.dart';
import 'package:smart_display_mobile/core/constants/enum.dart';
import 'package:smart_display_mobile/core/audit/audit_mode.dart';
import 'package:smart_display_mobile/core/log/biz_log_tag.dart';
import 'package:smart_display_mobile/core/errors/network_error_util.dart';
import 'package:smart_display_mobile/core/network/http_timeouts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/device_customization_repository.dart';
import '../log/app_log.dart';
import '../models/device_customization.dart';
import '../utils/wallpaper_image_util.dart';

/// 设备自定义字段（PATCH 维度）。
///
/// `wireName` 是发给 edge function `device_customization_save` 的 key，
/// 同时用作 UI 锁字段标识。
enum CustomizationField {
  layout('layout'),
  wakeWord('wake_word'),
  wallpaper('wallpaper'),
  wallpaperInfos('wallpaper_infos');

  const CustomizationField(this.wireName);
  final String wireName;
}

/// 设备自定义配置的状态（供设备编辑页使用）。
class DeviceCustomizationState {
  final String? displayDeviceId;
  final DeviceCustomization customization;
  final bool isLoading;
  final bool isUploading;
  final List<String> localWallpaperPaths;
  final List<String> wakeWordCandidates;
  // 当前被异步操作锁定、UI 不应允许编辑的字段集合（保存中、壁纸下载中等）。
  final Set<CustomizationField> lockedFields;

  const DeviceCustomizationState({
    this.displayDeviceId,
    this.customization = const DeviceCustomization.empty(),
    this.isLoading = false,
    this.isUploading = false,
    this.localWallpaperPaths = const [],
    this.wakeWordCandidates = fallbackWakeWordCandidates,
    this.lockedFields = const <CustomizationField>{},
  });

  bool isFieldLocked(CustomizationField field) =>
      isLoading || isUploading || lockedFields.contains(field);

  // 👇 内部哨兵，用来区分「没传」和「传 null」
  static const Object _unset = Object();

  DeviceCustomizationState copyWith({
    Object? displayDeviceId = _unset, // 可空字段用 Object? + 默认 _unset
    DeviceCustomization? customization,
    bool? isLoading,
    bool? isUploading,
    Object? localWallpaperPaths = _unset,
    Object? wakeWordCandidates = _unset,
    Set<CustomizationField>? lockedFields,
  }) {
    return DeviceCustomizationState(
      displayDeviceId: identical(displayDeviceId, _unset)
          ? this.displayDeviceId
          : displayDeviceId as String?, // 允许传 null 清空

      customization: customization ?? this.customization,

      isLoading: isLoading ?? this.isLoading,
      isUploading: isUploading ?? this.isUploading,

      localWallpaperPaths: identical(localWallpaperPaths, _unset)
          ? this.localWallpaperPaths
          : _toStringList(localWallpaperPaths),
      wakeWordCandidates: identical(wakeWordCandidates, _unset)
          ? this.wakeWordCandidates
          : _toStringList(wakeWordCandidates),

      lockedFields: lockedFields ?? this.lockedFields,
    );
  }

  static List<String> _toStringList(Object? value) {
    if (value is List<String>) return value;
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }
}

/// 负责在设备编辑页与 DeviceCustomizationRepository 之间做状态管理。
class DeviceCustomizationNotifier
    extends StateNotifier<DeviceCustomizationState> {
  DeviceCustomizationNotifier(this._repo)
    : super(const DeviceCustomizationState());

  final DeviceCustomizationRepository _repo;

  /// 初始化 / 加载（本地 + 远端）。
  Future<void> load(String? displayDeviceId) async {
    final totalStopwatch = Stopwatch()..start();
    if (displayDeviceId == null || displayDeviceId.isEmpty) {
      state = state.copyWith(
        displayDeviceId: displayDeviceId,
        customization: const DeviceCustomization.empty(),
        isLoading: false,
        localWallpaperPaths: const [],
        wakeWordCandidates: fallbackWakeWordCandidates,
      );
      AppLog.instance.info(
        'load skipped emptyDeviceId totalMs=${totalStopwatch.elapsedMilliseconds}',
        tag: 'CustomizationPerf',
      );
      return;
    }

    AppLog.instance.info(
      'load start deviceId=$displayDeviceId',
      tag: 'CustomizationPerf',
    );
    state = state.copyWith(displayDeviceId: displayDeviceId, isLoading: true);

    try {
      final localStopwatch = Stopwatch()..start();
      final local = await _repo.getUserCustomization(displayDeviceId);
      final localPaths = await _repo.getCachedWallpaperPaths(
        displayDeviceId,
        infos: local.wallpaperInfos,
      );
      final cachedWakeWordCandidates = await _repo.getCachedWakeWordCandidates(
        displayDeviceId,
      );
      localStopwatch.stop();
      // 唤醒词不在客户端兜底默认值：空 = 用户未显式选择，设备固件按内置词唤醒。
      final mergedWakeWordCandidates = _mergeWakeWordCandidates(
        cachedWakeWordCandidates,
        selectedWakeWord: local.wakeWord,
      );
      AppLog.instance.info(
        'local customization loaded deviceId=$displayDeviceId localMs=${localStopwatch.elapsedMilliseconds} wallpapers=${localPaths.length} wakeWords=${cachedWakeWordCandidates.length}',
        tag: 'CustomizationPerf',
      );
      // 本地数据先合并入 state，但保持 isLoading = true：
      // 阻塞用户编辑直到远端 customization + 候选词都到达，避免在本地→远端
      // 合并窗口期内用户切 layout/wakeWord 触发竞态。
      state = state.copyWith(
        customization: local,
        localWallpaperPaths: localPaths,
        wakeWordCandidates: mergedWakeWordCandidates,
      );

      // 并行拉取远端 customization 和唤醒词候选；两者内部都自带 try/catch，
      // 不会让 Future.wait 整体失败。等都返回后再放开 isLoading。
      // 壁纸图片下载（_refreshWallpaperCache）由 _refreshRemoteCustomization
      // 在内部 unawaited 触发，允许它在 isLoading=false 之后继续在后台跑，
      // 配合壁纸 tile 自己的 inline loading 占位。
      await Future.wait<void>([
        _refreshRemoteCustomization(displayDeviceId),
        _refreshWakeWordCandidates(displayDeviceId),
      ]);
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        'Failed to load customization for $displayDeviceId',
        tag: 'Customization',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      if (mounted && state.isLoading) {
        state = state.copyWith(isLoading: false);
        if (totalStopwatch.isRunning) {
          totalStopwatch.stop();
        }
        AppLog.instance.info(
          'load loading false deviceId=$displayDeviceId totalMs=${totalStopwatch.elapsedMilliseconds}',
          tag: 'CustomizationPerf',
        );
      }
    }
  }

  Future<void> _refreshRemoteCustomization(String deviceId) async {
    // 竞态由 UI 锁切断：load 期间 isLoading=true、保存期间 lockedFields，
    // 用户无法在 fetch 窗口里编辑同字段，所以不再需要 baseline 数据守卫。
    // 这里只保留身份守卫（mounted + displayDeviceId）防止页面销毁/切设备。
    try {
      final remoteStopwatch = Stopwatch()..start();
      final remote = await _repo.fetchUserCustomizationRemote(
        deviceId,
        syncWallpapers: false,
      );
      remoteStopwatch.stop();
      AppLog.instance.info(
        'remote customization finished deviceId=$deviceId remoteTotalMs=${remoteStopwatch.elapsedMilliseconds} hasRemote=${remote != null} wallpapers=${remote?.localWallpaperPaths.length ?? 0}',
        tag: 'CustomizationPerf',
      );
      if (remote == null || !mounted || state.displayDeviceId != deviceId) {
        return;
      }

      final saveStopwatch = Stopwatch()..start();
      await _repo.saveUserCustomization(deviceId, remote.customization);
      saveStopwatch.stop();
      AppLog.instance.info(
        'remote customization local save done deviceId=$deviceId saveMs=${saveStopwatch.elapsedMilliseconds}',
        tag: 'CustomizationPerf',
      );
      if (!mounted || state.displayDeviceId != deviceId) {
        return;
      }

      final mergedWakeWordCandidates = _mergeWakeWordCandidates(
        state.wakeWordCandidates,
        selectedWakeWord: remote.customization.wakeWord,
      );
      final nextCustomization = remote.customization;
      final shouldResetLocalWallpaperPaths = !_sameWallpaperCacheIdentity(
        state.customization.wallpaperInfos,
        nextCustomization.wallpaperInfos,
      );
      state = state.copyWith(
        customization: nextCustomization,
        wakeWordCandidates: mergedWakeWordCandidates,
        localWallpaperPaths: shouldResetLocalWallpaperPaths
            ? const []
            : state.localWallpaperPaths,
      );
      unawaited(_refreshWallpaperCache(deviceId, nextCustomization));
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        'Failed to refresh customization for $deviceId',
        tag: 'Customization',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _refreshWallpaperCache(
    String deviceId,
    DeviceCustomization baselineCustomization,
  ) async {
    // 下载期间锁住壁纸相关字段——用户无法在 UI 上换壁纸/重传，
    // 因此不再需要 _sameWallpaperInfos 守卫。
    const wallpaperLocks = <CustomizationField>{
      CustomizationField.wallpaper,
      CustomizationField.wallpaperInfos,
    };
    state = state.copyWith(
      lockedFields: state.lockedFields.union(wallpaperLocks),
    );

    try {
      final wallpaperStopwatch = Stopwatch()..start();
      final localPaths = await _repo.syncWallpaperListCache(
        deviceId: deviceId,
        wallpaperInfos: baselineCustomization.wallpaperInfos,
      );
      wallpaperStopwatch.stop();
      AppLog.instance.info(
        'wallpaper cache refresh finished deviceId=$deviceId wallpaperTotalMs=${wallpaperStopwatch.elapsedMilliseconds} wallpapers=${localPaths.length}',
        tag: 'CustomizationPerf',
      );
      if (!mounted || state.displayDeviceId != deviceId) return;

      state = state.copyWith(localWallpaperPaths: localPaths);
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        'Failed to refresh wallpaper cache for $deviceId',
        tag: 'Customization',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted) {
        state = state.copyWith(
          lockedFields: state.lockedFields.difference(wallpaperLocks),
        );
      }
    }
  }

  bool _sameWallpaperCacheIdentity(
    List<CustomWallpaperInfo> a,
    List<CustomWallpaperInfo> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (_normalizeWallpaperIdentityPart(left.mime) !=
          _normalizeWallpaperIdentityPart(right.mime)) {
        return false;
      }

      final leftMd5 = _normalizeWallpaperIdentityPart(left.md5);
      final rightMd5 = _normalizeWallpaperIdentityPart(right.md5);
      if (leftMd5.isNotEmpty || rightMd5.isNotEmpty) {
        if (leftMd5 != rightMd5) return false;
        continue;
      }

      if (left.key.trim() != right.key.trim()) return false;
    }
    return true;
  }

  String _normalizeWallpaperIdentityPart(String value) {
    return value.trim().toLowerCase();
  }

  Future<void> _refreshWakeWordCandidates(String deviceId) async {
    try {
      final wakeWordStopwatch = Stopwatch()..start();
      final wakeWordCandidates = await _fetchWakeWordCandidates(
        deviceId,
        returnFallbackOnError: false,
      );
      wakeWordStopwatch.stop();
      AppLog.instance.info(
        'wake word candidates loaded deviceId=$deviceId wakeWordTotalMs=${wakeWordStopwatch.elapsedMilliseconds} count=${wakeWordCandidates.length}',
        tag: 'CustomizationPerf',
      );
      try {
        await _repo.saveWakeWordCandidates(deviceId, wakeWordCandidates);
      } catch (error, stackTrace) {
        AppLog.instance.warning(
          'Failed to cache wake word candidates for $deviceId',
          tag: BizLogTag.wakeword.value,
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (!mounted || state.displayDeviceId != deviceId) return;

      // wakeWord 兜底由服务端 GET 接口（device_customization_get）统一处理，
      // 客户端这里只更新候选列表，不再二次合成。
      final mergedWakeWordCandidates = _mergeWakeWordCandidates(
        wakeWordCandidates,
        selectedWakeWord: state.customization.wakeWord,
      );
      state = state.copyWith(
        wakeWordCandidates: mergedWakeWordCandidates,
      );
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        'Failed to refresh wake word candidates for $deviceId',
        tag: BizLogTag.wakeword.value,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// 更新布局；仅修改状态，不立即持久化。
  void updateLayout(LayoutType layout) {
    final current = state.customization;
    final next = current.copyWith(layout: layout);
    state = state.copyWith(customization: next);
  }

  /// 更新唤醒词；仅修改状态，不立即持久化。
  void updateWakeWord(String wakeWord) {
    final current = state.customization;
    final next = current.copyWith(wakeWord: wakeWord);
    state = state.copyWith(
      customization: next,
      wakeWordCandidates: _mergeWakeWordCandidates(
        state.wakeWordCandidates,
        selectedWakeWord: wakeWord,
      ),
    );
  }

  /// 更新壁纸信息；仅修改状态，不立即持久化。
  void updateWallpaper(WallpaperType wallpaper) {
    final current = state.customization;
    final next = current.copyWith(wallpaper: wallpaper);
    state = state.copyWith(customization: next);
  }

  /// 上传后的结果处理（Widget 负责权限 & 选图 & 调用 ImageProcessor）
  /// 图片写入本地文件、更新本地路径。downloadUrl 先为空，等下一次 fetch 从远端获取
  Future<void> applyProcessedWallpapers({
    required String deviceId,
    required List<ImageProcessingResult> processedList,
  }) async {
    if (deviceId.isEmpty) throw Exception('缺少设备 ID');
    if (state.isUploading || processedList.isEmpty) return;

    state = state.copyWith(isUploading: true);

    try {
      await _repo.clearLocalWallpaperCache(deviceId);

      final limited = processedList
          .take(DeviceCustomization.maxCustomWallpapers)
          .toList();
      final uploadedInfos = await _uploadWallpapers(
        images: limited,
        deviceId: deviceId,
      );
      final infos = <CustomWallpaperInfo>[];
      final localPaths = <String>[];

      if (uploadedInfos.length < limited.length) {
        throw Exception('壁纸上传失败，请稍后重试');
      }

      for (var i = 0; i < limited.length; i++) {
        final processed = limited[i];
        infos.add(uploadedInfos[i]);

        final savedPath = await _repo.cacheWallpaperBytes(
          deviceId: deviceId,
          bytes: processed.bytes,
          extension: processed.extension,
          index: i,
        );
        localPaths.add(savedPath);
      }

      final next = state.customization.copyWith(
        wallpaperInfos: infos,
        wallpaper: WallpaperType.custom,
      );

      state = state.copyWith(
        customization: next,
        localWallpaperPaths: localPaths,
      );
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Failed to upload wallpaper for $deviceId',
        tag: 'Customization',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      state = state.copyWith(isUploading: false);
    }
  }

  /// 删除壁纸（含清缓存），不立即通知服务端。
  Future<void> deleteWallpaper(String deviceId) async {
    if (deviceId.isEmpty) return;

    await _repo.clearLocalWallpaperCache(deviceId);

    final next = state.customization.copyWith(
      wallpaperInfos: const [],
      wallpaper: WallpaperType.defaultWallpaper,
    );

    state = state.copyWith(customization: next, localWallpaperPaths: const []);
  }

  /// 单字段（或多字段）PATCH 保存。
  ///
  /// 服务端约定（edge function `device_customization_save`）：
  /// - patch 里的 key 才会被写入；未传的字段保留旧值
  /// - 值为 null 表示显式置空
  ///
  /// 客户端约定：
  /// - patch.keys 在保存期间加入 lockedFields，UI 显示为 disabled
  /// - state.customization 已经在调用前被 `update*` 乐观更新，
  ///   服务端响应不再二次合并；写本地缓存用当前 state。
  Future<void> savePartial(Map<CustomizationField, dynamic> patch) async {
    final deviceId = state.displayDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception('缺少设备 ID');
    }
    if (patch.isEmpty) return;

    final keys = patch.keys.toSet();
    state = state.copyWith(
      lockedFields: state.lockedFields.union(keys),
    );

    try {
      final payload = <String, dynamic>{
        'device_id': deviceId,
        for (final entry in patch.entries) entry.key.wireName: entry.value,
      };

      await AuthManager.instance.ensureFreshSession();
      final response = await Supabase.instance.client.functions
          .invoke('device_customization_save', body: payload)
          .timeout(HttpTimeouts.business);

      if (response.status != 200) {
        final data = response.data;
        final detail = data is Map && data['message'] != null
            ? data['message'].toString()
            : data?.toString();
        throw Exception(
          detail == null || detail.isEmpty
              ? '服务异常（${response.status}）'
              : detail,
        );
      }

      // 写本地缓存：state.customization 已是用户乐观更新后的最新值，
      // 服务端 PATCH 成功就是写入这些值，所以直接用当前 state 落盘。
      if (mounted && state.displayDeviceId == deviceId) {
        try {
          await _repo.saveUserCustomization(deviceId, state.customization);
        } catch (e, st) {
          AppLog.instance.warning(
            'saveUserCustomization failed for $deviceId',
            tag: 'Customization',
            error: e,
            stackTrace: st,
          );
        }
      }
    } on FunctionException catch (error, stackTrace) {
      AppLog.instance.error(
        '[device_customization_save] status=${error.status}, details=${error.details}',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      final detail = error.details?.toString();
      throw Exception(
        detail == null || detail.isEmpty ? '保存失败，请稍后重试' : '保存失败：$detail',
      );
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when saving customization',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      if (NetworkErrorUtil.isNetworkOrTimeout(error)) {
        rethrow;
      }
      if (error is Exception) rethrow;
      throw Exception('保存失败：$error');
    } finally {
      if (mounted) {
        state = state.copyWith(
          lockedFields: state.lockedFields.difference(keys),
        );
      }
    }
  }

  /// 重置为默认配置（不触发持久化）。
  /// wakeWord 同样清空，UI 显示由后续 savePartial → 下次 load 时
  /// 通过服务端 GET 的 default 兜底统一填充，客户端不做任何合成。
  void resetToDefault() {
    state = state.copyWith(
      customization: const DeviceCustomization.empty(),
      localWallpaperPaths: const [],
    );
  }

  /// 批量上传壁纸到 Supabase。
  Future<List<CustomWallpaperInfo>> _uploadWallpapers({
    required List<ImageProcessingResult> images,
    required String deviceId,
  }) async {
    final supabase = Supabase.instance.client;
    if (images.isEmpty) return const [];

    final files = <http.MultipartFile>[];
    final md5List = <String>[];
    final mimeList = <String>[];

    for (var i = 0; i < images.length; i++) {
      final image = images[i];
      final ext = image.extension.replaceFirst('.', '').toLowerCase();
      final normalizedExt = ext.isEmpty ? 'jpg' : ext;

      // 先算 md5（你本来就要算的）
      final md5 = crypto.md5.convert(image.bytes).toString();
      md5List.add(md5);
      mimeList.add(image.mimeType);

      // 用 md5 作为上传时的文件名
      final filename = '$md5.$normalizedExt';

      files.add(
        http.MultipartFile.fromBytes(
          'files',
          image.bytes,
          filename: filename,
          contentType: http.MediaType.parse(image.mimeType),
        ),
      );
    }

    try {
      await AuthManager.instance.ensureFreshSession();
      final response = await supabase.functions
          .invoke(
            'device_wallpaper_upload',
            method: HttpMethod.post,
            files: files,
            headers: {'x-device-id': deviceId},
          )
          .timeout(HttpTimeouts.transfer);

      final data = response.data;

      final keys = _extractKeys(data);
      if (keys.isEmpty) {
        AppLog.instance.warning(
          '[device_wallpaper_upload] empty keys from response: ${response.data}',
          tag: 'Supabase',
        );
        throw Exception('服务返回的 key 无效');
      }

      if (keys.length != images.length) {
        AppLog.instance.warning(
          '[device_wallpaper_upload] key count mismatch, expected=${images.length}, got=${keys.length}',
          tag: 'Supabase',
        );
        throw Exception('服务返回的 key 数量异常');
      }

      final infos = <CustomWallpaperInfo>[];

      for (var i = 0; i < keys.length; i++) {
        infos.add(
          CustomWallpaperInfo(
            key: keys[i],
            md5: md5List[i],
            mime: mimeList[i],
            downloadUrl: '',
          ),
        );
      }

      return infos;
    } on FunctionException catch (error, stackTrace) {
      AppLog.instance.error(
        '[device_wallpaper_upload] status=${error.status}, details=${error.details}',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      final detail = error.details?.toString();
      throw Exception(
        detail != null && detail.isNotEmpty ? detail : '服务异常（${error.status}）',
      );
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when uploading wallpaper',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      if (NetworkErrorUtil.isNetworkOrTimeout(error)) {
        rethrow;
      }
      throw Exception('请稍后重试');
    }
  }

  List<String> _extractKeys(dynamic data) {
    if (data is Map) {
      final raw = data['keys'];
      if (raw is List) {
        return raw
            .map((item) => item?.toString().trim() ?? '')
            .where((value) => value.isNotEmpty)
            .toList();
      }
      if (raw is String) {
        final value = raw.trim();
        return value.isEmpty ? const [] : [value];
      }
    }

    if (data is List) {
      return data
          .map((item) => item?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toList();
    }

    if (data is String) {
      final value = data.trim();
      return value.isEmpty ? const [] : [value];
    }

    return const [];
  }

  Future<List<String>> _fetchWakeWordCandidates(
    String deviceId, {
    bool returnFallbackOnError = true,
  }) async {
    final totalStopwatch = Stopwatch()..start();
    if (AuditMode.enabled) {
      AppLog.instance.info(
        'api wakeword/get_word_candidates skipped auditMode deviceId=$deviceId apiMs=${totalStopwatch.elapsedMilliseconds}',
        tag: 'CustomizationPerf',
      );
      return fallbackWakeWordCandidates;
    }

    final tokenStopwatch = Stopwatch()..start();
    final accessToken = await AuthManager.instance.getFreshAccessToken();
    tokenStopwatch.stop();
    AppLog.instance.info(
      'wakeword token ready deviceId=$deviceId tokenMs=${tokenStopwatch.elapsedMilliseconds} hasToken=${accessToken != null && accessToken.isNotEmpty}',
      tag: 'CustomizationPerf',
    );
    if (accessToken == null || accessToken.isEmpty || deviceId.isEmpty) {
      AppLog.instance.error(
        '_fetchWakeWordCandidates invalid params',
        tag: BizLogTag.wakeword.value,
      );
      AppLog.instance.info(
        'api wakeword/get_word_candidates skipped invalidParams deviceId=$deviceId apiMs=${totalStopwatch.elapsedMilliseconds}',
        tag: 'CustomizationPerf',
      );

      return fallbackWakeWordCandidates;
    }

    try {
      final apiStopwatch = Stopwatch()..start();

      final url = '${AppEnvironment.apiServerUrl}/wakeword/get_word_candidates';
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'X-Access-Token': accessToken,
              'X-Device-Id': deviceId,
            },
          )
          .timeout(HttpTimeouts.business);
      apiStopwatch.stop();
      AppLog.instance.info(
        'api wakeword/get_word_candidates status=${response.statusCode} deviceId=$deviceId httpMs=${apiStopwatch.elapsedMilliseconds} totalMs=${totalStopwatch.elapsedMilliseconds}',
        tag: 'CustomizationPerf',
      );

      AppLog.instance.info(
        'response=${response.body}',
        tag: BizLogTag.wakeword.value,
      );

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final candidates = _extractWakeWordCandidates(decoded);

      if (candidates.isEmpty) {
        return fallbackWakeWordCandidates;
      }
      return candidates;
    } catch (error, stackTrace) {
      AppLog.instance.info(
        'api wakeword/get_word_candidates failed deviceId=$deviceId totalMs=${totalStopwatch.elapsedMilliseconds}',
        tag: 'CustomizationPerf',
      );
      AppLog.instance.warning(
        'Failed to fetch wake word candidates for $deviceId',
        tag: BizLogTag.wakeword.value,
        error: error,
        stackTrace: stackTrace,
      );
      if (!returnFallbackOnError) {
        rethrow;
      }
      return fallbackWakeWordCandidates;
    }
  }

  List<String> _extractWakeWordCandidates(dynamic data) {
    if (data is! Map) return const [];
    final map = data.map((key, value) => MapEntry(key.toString(), value));
    final nestedData = map['data'];
    final raw = nestedData is Map
        ? nestedData['wake_word_candidates'] ?? map['wake_word_candidates']
        : map['wake_word_candidates'];

    if (raw is! List) return const [];
    return raw
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  List<String> _mergeWakeWordCandidates(
    List<String> candidates, {
    required String selectedWakeWord,
  }) {
    final merged = <String>[
      ...candidates.where((item) => item.trim().isNotEmpty),
    ];
    final selected = selectedWakeWord.trim();
    if (selected.isNotEmpty && !merged.contains(selected)) {
      merged.insert(0, selected);
    }
    if (merged.isEmpty) {
      merged.addAll(fallbackWakeWordCandidates);
    }
    return merged;
  }

}

/// 设备自定义配置的 provider，供设备编辑页消费。
final deviceCustomizationProvider =
    StateNotifierProvider.autoDispose<
      DeviceCustomizationNotifier,
      DeviceCustomizationState
    >((ref) {
      return DeviceCustomizationNotifier(DeviceCustomizationRepository());
    });
