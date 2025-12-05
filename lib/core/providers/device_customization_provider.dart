import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
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
  final List<String> localWallpaperPaths;

  const DeviceCustomizationState({
    this.displayDeviceId,
    this.customization = const DeviceCustomization.empty(),
    this.isLoading = false,
    this.isSaving = false,
    this.isUploading = false,
    this.loaded = false,
    this.localWallpaperPaths = const [],
  });

  // 👇 新增一个内部哨兵，用来区分「没传」和「传 null」
  static const Object _unset = Object();

  DeviceCustomizationState copyWith({
    Object? displayDeviceId = _unset, // 可空字段用 Object? + 默认 _unset
    DeviceCustomization? customization,
    bool? isLoading,
    bool? isSaving,
    bool? isUploading,
    bool? loaded,
    Object? localWallpaperPaths = _unset,
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

      localWallpaperPaths: identical(localWallpaperPaths, _unset)
          ? this.localWallpaperPaths
          : _toStringList(localWallpaperPaths),
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
    if (displayDeviceId == null || displayDeviceId.isEmpty) {
      state = state.copyWith(
        displayDeviceId: displayDeviceId,
        customization: const DeviceCustomization.empty(),
        localWallpaperPaths: const [],
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
      final localPaths = await _repo.getCachedWallpaperPaths(
        displayDeviceId,
        infos: local.customWallpaperInfos,
      );
      state = state.copyWith(
        customization: local.normalized(),
        localWallpaperPaths: localPaths,
      );

      // 再远端
      final remote = await _repo.fetchUserCustomizationRemote(displayDeviceId);
      state = state.copyWith(
        customization: remote.customization.normalized(),
        localWallpaperPaths: remote.localWallpaperPaths,
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
      customWallpaperInfos: current.customWallpaperInfos,
      wallpaper: current.wallpaper,
      layout: layout,
    ).normalized();
    state = state.copyWith(customization: next);
  }

  /// 更新壁纸信息；仅修改状态，不立即持久化。
  void updateWallpaper({
    List<CustomWallpaperInfo>? customWallpapers,
    String? wallpaper,
  }) {
    final current = state.customization;
    final next = DeviceCustomization(
      customWallpaperInfos: customWallpapers ?? current.customWallpaperInfos,
      wallpaper: wallpaper ?? current.wallpaper,
      layout: current.layout,
    ).normalized();
    state = state.copyWith(customization: next);
  }

  /// 上传后的结果处理（Widget 负责权限 & 选图 & 调用 ImageProcessor）
  Future<void> applyProcessedWallpapers({
    required String deviceId,
    required List<ImageProcessingResult> processedList,
  }) async {
    if (deviceId.isEmpty) throw '缺少设备 ID';
    if (state.isUploading || processedList.isEmpty) return;

    state = state.copyWith(isUploading: true);

    try {
      await _repo.clearLocalWallpaperCache(deviceId);

      final limited =
          processedList.take(DeviceCustomization.maxCustomWallpapers).toList();
      final uploadedInfos =
          await _uploadWallpapers(images: limited, deviceId: deviceId);
      final infos = <CustomWallpaperInfo>[];
      final localPaths = <String>[];

      if (uploadedInfos.length < limited.length) {
        throw '壁纸上传失败，请稍后重试';
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

      final next = state.customization
          .copyWith(
            customWallpaperInfos: infos,
            wallpaper: DeviceCustomization.customWallpaper,
          )
          .normalized();

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

    final wasUsingCustom = state.customization.effectiveWallpaper ==
        DeviceCustomization.customWallpaper;

    final next = state.customization.copyWith(
      customWallpaperInfos: const [],
      wallpaper: wasUsingCustom
          ? DeviceCustomization.defaultWallpaper
          : state.customization.wallpaper,
    );

    state = state.copyWith(
      customization: next,
      localWallpaperPaths: const [],
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
      final wallpaperInfos = normalized.customWallpaperInfos
          .where((info) => info.hasData)
          .toList();

      final payload = <String, dynamic>{
        'device_id': deviceId,
        // 发送归一化后的有效值，避免默认值被当成「不更新」而无法清空远端壁纸
        'layout': normalized.effectiveLayout,
        'wallpaper': normalized.effectiveWallpaper,
        'wallpaper_infos': wallpaperInfos.map((info) => info.toJson()).toList(),
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
        localWallpaperPaths: remote.localWallpaperPaths,
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
      localWallpaperPaths: const [],
      loaded: true,
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

      files.add(http.MultipartFile.fromBytes(
        'files',
        image.bytes,
        filename: filename,
        contentType: http.MediaType.parse(image.mimeType),
      ));
    }

    try {
      final response = await supabase.functions.invoke(
        'device_wallpaper_upload',
        method: HttpMethod.post,
        files: files,
        headers: {
          'x-device-id': deviceId,
        },
      );

      final data = response.data;

      final keys = _extractKeys(data);
      if (keys.isEmpty) {
        AppLog.instance.warning(
          '[device_wallpaper_upload] empty keys from response: ${response.data}',
          tag: 'Supabase',
        );
        throw '服务返回的 key 无效';
      }

      if (keys.length != images.length) {
        AppLog.instance.warning(
          '[device_wallpaper_upload] key count mismatch, expected=${images.length}, got=${keys.length}',
          tag: 'Supabase',
        );
        throw '服务返回的 key 数量异常';
      }

      final infos = <CustomWallpaperInfo>[];

      for (var i = 0; i < keys.length; i++) {
        infos.add(
          CustomWallpaperInfo(
            key: keys[i],
            md5: md5List[i],
            mime: mimeList[i],
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
}

/// 设备自定义配置的 provider，供设备编辑页消费。
final deviceCustomizationProvider = StateNotifierProvider.autoDispose<
    DeviceCustomizationNotifier, DeviceCustomizationState>((ref) {
  return DeviceCustomizationNotifier(DeviceCustomizationRepository());
});
