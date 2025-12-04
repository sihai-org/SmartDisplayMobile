import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/device_customization_repository.dart';
import '../log/app_log.dart';
import '../models/device_customization.dart';
import '../utils/image_processing.dart';

/// 设备自定义配置的状态（供设备编辑页使用）。
class DeviceCustomizationState {
  final String? displayDeviceId;
  final DeviceCustomization customization;
  final bool isLoading;
  final bool isSaving;
  final bool isUploading;
  final bool loaded;
  final String? localWallpaperPath;

  const DeviceCustomizationState({
    this.displayDeviceId,
    this.customization = const DeviceCustomization.empty(),
    this.isLoading = false,
    this.isSaving = false,
    this.isUploading = false,
    this.loaded = false,
    this.localWallpaperPath,
  });

  // 👇 新增一个内部哨兵，用来区分「没传」和「传 null」
  static const Object _unset = Object();

  DeviceCustomizationState copyWith({
    Object? displayDeviceId = _unset,   // 可空字段用 Object? + 默认 _unset
    DeviceCustomization? customization,
    bool? isLoading,
    bool? isSaving,
    bool? isUploading,
    bool? loaded,
    Object? localWallpaperPath = _unset,
  }) {
    return DeviceCustomizationState(
      displayDeviceId: identical(displayDeviceId, _unset)
          ? this.displayDeviceId
          : displayDeviceId as String?, // 允许传 null 清空

      customization: customization ?? this.customization,

      // 这些是非空 bool，本身就不能设成 null，用原来的 ?? 语义就够了
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      isUploading: isUploading ?? this.isUploading,
      loaded: loaded ?? this.loaded,

      localWallpaperPath: identical(localWallpaperPath, _unset)
          ? this.localWallpaperPath
          : localWallpaperPath as String?, // 允许传 null 清空
    );
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
    if (displayDeviceId == null || displayDeviceId.isEmpty) {
      state = state.copyWith(
        displayDeviceId: displayDeviceId,
        customization: const DeviceCustomization.empty(),
        localWallpaperPath: null,
        loaded: true,
      );
      return;
    }

    state = state.copyWith(
      displayDeviceId: displayDeviceId,
      isLoading: true,
    );

    try {
      // 先本地
      final local = await _repo.getUserCustomization(displayDeviceId);
      final localPath = await _repo.getCachedWallpaperPath(
        displayDeviceId,
        info: local.customWallpaperInfo,
      );
      state = state.copyWith(
        customization: local.normalized(),
        localWallpaperPath: localPath,
      );

      // 再远端
      final remote = await _repo.fetchUserCustomizationRemote(displayDeviceId);
      state = state.copyWith(
        customization: remote.customization.normalized(),
        localWallpaperPath: remote.localWallpaperPath,
        loaded: true,
      );
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        'Failed to load customization for $displayDeviceId',
        tag: 'Customization',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  /// 更新布局；仅修改状态，不立即持久化。
  void updateLayout(String? layout) {
    final current = state.customization;
    final next = DeviceCustomization(
      customWallpaperInfo: current.customWallpaperInfo,
      wallpaper: current.wallpaper,
      layout: layout,
    ).normalized();
    state = state.copyWith(customization: next);
  }

  /// 更新壁纸信息；仅修改状态，不立即持久化。
  void updateWallpaper(CustomWallpaperInfo? customWallpaperInfo,
      {String? wallpaper}) {
    final current = state.customization;
    final next = DeviceCustomization(
      customWallpaperInfo: customWallpaperInfo ?? current.customWallpaperInfo,
      wallpaper: wallpaper ?? current.wallpaper,
      layout: current.layout,
    ).normalized();
    state = state.copyWith(customization: next);
  }

  /// 上传后的结果处理（Widget 负责权限 & 选图 & 调用 ImageProcessor）
  Future<void> applyProcessedWallpaper({
    required String deviceId,
    required ImageProcessingResult processed,
  }) async {
    if (deviceId.isEmpty) throw '缺少设备 ID';
    if (state.isUploading) return;

    state = state.copyWith(isUploading: true);

    try {
      final info = await _uploadWallpaper(processed, deviceId: deviceId);

      final savedPath = await _repo.cacheWallpaperBytes(
        deviceId: deviceId,
        bytes: processed.bytes,
        extension: processed.extension,
      );

      final next = state.customization
          .copyWith(
            customWallpaperInfo: info,
            wallpaper: DeviceCustomization.customWallpaper,
          )
          .normalized();

      state = state.copyWith(
        customization: next,
        localWallpaperPath: savedPath,
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

    final wasUsingCustom = state.customization.effectiveWallpaper ==
        DeviceCustomization.customWallpaper;

    final next = state.customization.copyWith(
      customWallpaperInfo: null,
      wallpaper: wasUsingCustom
          ? DeviceCustomization.defaultWallpaper
          : state.customization.wallpaper,
    );

    state = state.copyWith(
      customization: next,
      localWallpaperPath: null,
    );
  }

  /// 将当前状态保存到远端
  Future<void> saveRemote() async {
    final deviceId = state.displayDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      throw '缺少设备 ID';
    }
    if (state.isSaving || state.isUploading) return;

    state = state.copyWith(isSaving: true);

    try {
      final normalized = state.customization.normalized();
      final wallpaperInfo = normalized.customWallpaperInfo;

      final payload = <String, dynamic>{
        'device_id': deviceId,
        'layout': normalized.layout,
        'wallpaper': normalized.wallpaper,
        if (wallpaperInfo != null && wallpaperInfo.hasData)
          'wallpaper_info': wallpaperInfo.toJson(),
      }..removeWhere((_, value) => value == null);

      final response = await Supabase.instance.client.functions.invoke(
        'device_customization_save',
        body: payload,
      );

      if (response.status != 200) {
        final data = response.data;
        final detail = data is Map && data['message'] != null
            ? data['message'].toString()
            : data?.toString();
        throw detail == null || detail.isEmpty
            ? '服务异常（${response.status}）'
            : detail;
      }

      // 成功后再刷新一次远端，保证状态一致
      final remote = await _repo.fetchUserCustomizationRemote(deviceId);
      state = state.copyWith(
        customization: remote.customization.normalized(),
        localWallpaperPath: remote.localWallpaperPath,
        loaded: true,
      );
    } on FunctionException catch (error, stackTrace) {
      AppLog.instance.error(
        '[device_customization_save] status=${error.status}, details=${error.details}',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      final detail = error.details?.toString();
      throw detail == null || detail.isEmpty ? '保存失败，请稍后重试' : '保存失败：$detail';
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when saving customization',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      throw '保存失败：$error';
    } finally {
      state = state.copyWith(isSaving: false);
    }
  }

  /// 重置为默认配置（不触发持久化）。
  void resetToDefault() {
    state = state.copyWith(
      customization: const DeviceCustomization.empty(),
      localWallpaperPath: null,
      loaded: true,
    );
  }

  /// 上传壁纸到 Supabase（你原来的 _uploadWallpaper 基本原样搬过来）。
  Future<CustomWallpaperInfo> _uploadWallpaper(
    ImageProcessingResult image, {
    required String deviceId,
  }) async {
    final supabase = Supabase.instance.client;
    final ext = image.extension.replaceFirst('.', '').toLowerCase();
    final normalizedExt = ext.isEmpty ? 'jpg' : ext;
    final fallbackMd5 = crypto.md5.convert(image.bytes).toString();

    try {
      final response = await supabase.functions.invoke(
        'device_wallpaper_upload',
        method: HttpMethod.post,
        body: image.bytes,
        headers: {
          'x-file-ext': normalizedExt,
          'x-device-id': deviceId,
        },
      );

      final data = response.data;
      String key = '';
      String mime = image.mimeType;
      String md5 = fallbackMd5;

      if (data is Map) {
        key = (data['key'] ?? '').toString().trim();
        mime = (data['mime'] ??
                data['mime_type'] ??
                data['mimeType'] ??
                data['content_type'] ??
                mime)
            .toString();
        md5 =
            (data['md5'] ?? data['checksum'] ?? data['hash'] ?? md5).toString();
      } else if (data is String) {
        key = data.trim();
      }

      if (key.isEmpty) {
        AppLog.instance.warning(
          '[device_wallpaper_upload] empty key from response: ${response.data}',
          tag: 'Supabase',
        );
        throw '服务返回的 key 无效';
      }

      return CustomWallpaperInfo(
        key: key,
        md5: md5,
        mime: mime,
      );
    } on FunctionException catch (error, stackTrace) {
      AppLog.instance.error(
        '[device_wallpaper_upload] status=${error.status}, details=${error.details}',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      final detail = error.details?.toString();
      throw detail != null && detail.isNotEmpty
          ? detail
          : '服务异常（${error.status}）';
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when uploading wallpaper',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      throw '请稍后重试';
    }
  }
}

/// 设备自定义配置的 provider，供设备编辑页消费。
final deviceCustomizationProvider = StateNotifierProvider.autoDispose<
    DeviceCustomizationNotifier, DeviceCustomizationState>((ref) {
  return DeviceCustomizationNotifier(DeviceCustomizationRepository());
});
