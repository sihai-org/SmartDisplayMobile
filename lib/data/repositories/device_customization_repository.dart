import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/audit/audit_mode.dart';
import '../../core/constants/storage_keys.dart';
import '../../core/log/app_log.dart';
import '../../core/models/device_customization.dart';

class CustomizationFetchResult {
  final DeviceCustomization customization;
  final String? localWallpaperPath;

  const CustomizationFetchResult({
    required this.customization,
    this.localWallpaperPath,
  });

  const CustomizationFetchResult.empty()
      : customization = const DeviceCustomization.empty(),
        localWallpaperPath = null;
}

/// 本地持久化：用户为不同设备设置的壁纸/布局偏好。
///
/// 存储规则：
/// - 壁纸、布局字段都允许为空；为空表示使用默认。
/// - 如果保存时两者都为空，则会直接删除该设备的自定义记录以保持存储整洁。
class DeviceCustomizationRepository {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _currentUserId() {
    if (AuditMode.enabled) return AuditMode.auditUserId;
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  String? _storageKeyForCurrentUser() {
    final uid = _currentUserId();
    if (uid == null || uid.isEmpty) return null;
    return '${StorageKeys.deviceCustomizationBase}_$uid';
  }

  String _currentUserFolder() {
    final uid = _currentUserId();
    if (uid == null || uid.isEmpty) return 'guest';
    return _safeDeviceId(uid);
  }

  /// 读本地缓存 { deviceId: DeviceCustomization }
  Future<Map<String, DeviceCustomization>> _loadAll() async {
    final key = _storageKeyForCurrentUser();
    if (key == null) return {};
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return decoded.map((deviceId, value) {
        if (value is Map<String, dynamic>) {
          return MapEntry(deviceId, DeviceCustomization.fromJson(value));
        }
        return MapEntry(deviceId, const DeviceCustomization.empty());
      });
    } catch (_) {
      return {};
    }
  }

  /// 写本地缓存 { deviceId: DeviceCustomization }
  Future<void> _saveAll(Map<String, DeviceCustomization> data) async {
    final key = _storageKeyForCurrentUser();
    if (key == null) return;
    final encoded = json.encode(
      data.map((k, v) => MapEntry(k, v.normalized().toJson())),
    );
    await _storage.write(key: key, value: encoded);
  }

  /// 读指定设备的缓存
  ///
  /// 当设备没有任何自定义时，返回空对象（等同于 default）。
  Future<DeviceCustomization> getUserCustomization(String displayDeviceId) async {
    if (displayDeviceId.isEmpty) return const DeviceCustomization.empty();
    final all = await _loadAll();
    return all[displayDeviceId] ?? const DeviceCustomization.empty();
  }

  /// 写指定设备的缓存
  ///
  /// 如果壁纸、布局均为空，则删除对应记录，使其回退为默认。
  Future<void> saveUserCustomization(
    String displayDeviceId,
    DeviceCustomization customization,
  ) async {
    if (displayDeviceId.isEmpty) return;
    final normalized = customization.normalized();
    final all = await _loadAll();

    final wallpaperSelectedCustom =
        normalized.effectiveWallpaper == DeviceCustomization.customWallpaper;
    final hasWallpaper =
        normalized.hasCustomWallpaper || wallpaperSelectedCustom;
    final hasLayout = normalized.layout != null;

    if (!hasWallpaper && !hasLayout) {
      all.remove(displayDeviceId);
    } else {
      all[displayDeviceId] = normalized;
    }

    await _saveAll(all);
  }

  /// 清空当前用户所有设备的缓存（用于登出）。
  Future<void> clearCurrentUserData() async {
    final userFolder = _currentUserFolder();
    final key = _storageKeyForCurrentUser();
    if (key != null) {
      await _storage.delete(key: key);
    }
    try {
      final dir = await _wallpaperDir(userFolder: userFolder);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // ignore deletion failure
    }
  }

  /// 从服务端获取指定设备的配置，并更新本地缓存
  Future<CustomizationFetchResult> fetchUserCustomizationRemote(
    String displayDeviceId,
  ) async {
    if (displayDeviceId.isEmpty) {
      return const CustomizationFetchResult.empty();
    }
    // 审核模式直接走本地缓存，避免网络访问
    if (AuditMode.enabled) {
      final cached = await getUserCustomization(displayDeviceId);
      final localPath =
          await getCachedWallpaperPath(displayDeviceId, info: cached.customWallpaperInfo);
      return CustomizationFetchResult(
        customization: cached,
        localWallpaperPath: localPath,
      );
    }

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'device_customization_get?device_id=${displayDeviceId}',
        method: HttpMethod.get, // 一定要加
      );

      AppLog.instance.info(
          "device_customization_get status=${response.status}, data=${response.data}");

      final detail = _responseMessage(response.data);
      if (response.status != 200) {
        throw detail == null || detail.isEmpty
            ? '服务异常（${response.status}）'
            : detail;
      }

      final parsed = _parseCustomization(response.data);
      if (parsed == null) {
        return const CustomizationFetchResult.empty();
      }

      final customization = DeviceCustomization.fromJson(parsed).normalized();
      await saveUserCustomization(displayDeviceId, customization);

      final downloadUrl = _parseDownloadUrl(response.data);
      final wallpaperPath = await _syncWallpaperCache(
        deviceId: displayDeviceId,
        wallpaperInfo: customization.customWallpaperInfo,
        downloadUrl: downloadUrl,
      );

      return CustomizationFetchResult(
        customization: customization,
        localWallpaperPath: wallpaperPath,
      );
    } on FunctionException catch (error, stackTrace) {
      AppLog.instance.warning(
        '[device_customization_get] status=${error.status}, details=${error.details}',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      final fallback = await getUserCustomization(displayDeviceId);
      final wallpaperPath =
          await getCachedWallpaperPath(displayDeviceId, info: fallback.customWallpaperInfo);
      return CustomizationFetchResult(
        customization: fallback,
        localWallpaperPath: wallpaperPath,
      );
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        'Unexpected error when fetching customization',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      final fallback = await getUserCustomization(displayDeviceId);
      final wallpaperPath =
          await getCachedWallpaperPath(displayDeviceId, info: fallback.customWallpaperInfo);
      return CustomizationFetchResult(
        customization: fallback,
        localWallpaperPath: wallpaperPath,
      );
    }
  }

  Map<String, dynamic>? _parseCustomization(dynamic responseData) {
    final raw = _extractCustomizationMap(responseData);
    if (raw == null) return null;

    // 兼容 snake_case 返回字段
    return {
      ...raw,
      if (!raw.containsKey('customWallpaperInfo') &&
          raw.containsKey('wallpaper_info'))
        'customWallpaperInfo': raw['wallpaper_info'],
      if (!raw.containsKey('wallpaperOption') &&
          raw.containsKey('wallpaper_option'))
        'wallpaperOption': raw['wallpaper_option'],
    };
  }

  Map<String, dynamic>? _extractCustomizationMap(dynamic responseData) {
    if (responseData is Map) {
      final maybeData = responseData['data'];
      final target = maybeData is Map ? maybeData : responseData;
      return target.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  String? _parseDownloadUrl(dynamic responseData) {
    if (responseData is Map && responseData['customWallpaperDownloadUrl'] != null) {
      final value = responseData['customWallpaperDownloadUrl'];
      return value == null ? null : value.toString();
    }
    return null;
  }

  String? _responseMessage(dynamic data) {
    if (data is Map && data['message'] != null) {
      return data['message']?.toString();
    }
    return data?.toString();
  }

  Future<String?> getCachedWallpaperPath(
    String displayDeviceId, {
    CustomWallpaperInfo? info,
  }) async {
    if (displayDeviceId.isEmpty) return null;
    final filePath = await _wallpaperFilePath(
      displayDeviceId,
      extension: _resolveExtension(info),
    );
    final file = File(filePath);
    return await file.exists() ? file.path : null;
  }

  Future<String> cacheWallpaperBytes({
    required String deviceId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final targetPath = await _wallpaperFilePath(deviceId, extension: extension);
    final target = File(targetPath);
    await target.writeAsBytes(bytes, flush: true);
    _evictImageCache(target.path);
    return target.path;
  }

  Future<void> clearLocalWallpaperCache(String deviceId) async {
    final dir = await _wallpaperDir();
    final safeId = _safeDeviceId(deviceId);
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('$safeId.')) {
        try {
          _evictImageCache(entity.path);
          await entity.delete();
        } catch (_) {
          // ignore deletion failure
        }
      }
    }
  }

  /// 按需更新本地缓存的壁纸图片
  Future<String?> _syncWallpaperCache({
    required String deviceId,
    required CustomWallpaperInfo? wallpaperInfo,
    required String? downloadUrl,
  }) async {
    if (wallpaperInfo == null || !wallpaperInfo.hasData) {
      await clearLocalWallpaperCache(deviceId);
      return null;
    }
    if (downloadUrl == null || downloadUrl.isEmpty) {
      return await getCachedWallpaperPath(deviceId, info: wallpaperInfo);
    }

    final ext = _resolveExtension(wallpaperInfo);
    final filePath = await _wallpaperFilePath(deviceId, extension: ext);
    final file = File(filePath);
    final remoteMd5 = wallpaperInfo.md5.trim();

    try {
      if (await file.exists()) {
        final localMd5 = await _computeFileMd5(file);
        if (localMd5 != null && remoteMd5.isNotEmpty && remoteMd5 == localMd5) {
          return file.path;
        }
      }

      await _downloadToFile(downloadUrl, file);
      final downloadedMd5 = await _computeFileMd5(file);
      if (remoteMd5.isNotEmpty && downloadedMd5 != null && remoteMd5 != downloadedMd5) {
        AppLog.instance.warning(
          'Wallpaper md5 mismatch, remote=$remoteMd5, local=$downloadedMd5',
          tag: 'Customization',
        );
      }
      return file.path;
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        'Failed to sync wallpaper cache',
        tag: 'Customization',
        error: error,
        stackTrace: stackTrace,
      );
      return await getCachedWallpaperPath(deviceId, info: wallpaperInfo);
    }
  }

  Future<void> _downloadToFile(String url, File target) async {
    final directory = target.parent;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'Failed to download wallpaper: status ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      await target.writeAsBytes(bytes, flush: true);
      _evictImageCache(target.path);
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _computeFileMd5(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return crypto.md5.convert(bytes).toString();
    } catch (_) {
      return null;
    }
  }

  Future<String> _wallpaperFilePath(
    String deviceId, {
    String? extension,
  }) async {
    final dir = await _wallpaperDir();
    final safeId = _safeDeviceId(deviceId);
    final ext = _resolveExtension(null, fallbackExtension: extension);
    return p.join(dir.path, '$safeId$ext');
  }

  Future<Directory> _wallpaperDir({String? userFolder}) async {
    final base = await getApplicationSupportDirectory();
    final folder = userFolder ?? _currentUserFolder();
    final dir = Directory(p.join(base.path, 'wallpapers', folder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _resolveExtension(
    CustomWallpaperInfo? info, {
    String? fallbackExtension,
  }) {
    final fromKey = info == null ? null : p.extension(info.key);
    final mime = info?.mime.toLowerCase() ?? '';
    String? candidate = (fallbackExtension ?? fromKey)?.trim().toLowerCase();

    if ((candidate == null || candidate.isEmpty) && mime.isNotEmpty) {
      if (mime.contains('png')) {
        candidate = '.png';
      } else if (mime.contains('jpeg') || mime.contains('jpg')) {
        candidate = '.jpg';
      }
    }

    candidate ??= '.jpg';
    if (candidate.isEmpty) return '.jpg';
    if (candidate.startsWith('.')) return candidate;
    return '.$candidate';
  }

  void _evictImageCache(String path) {
    try {
      PaintingBinding.instance.imageCache.evict(FileImage(File(path)));
    } catch (_) {
      // 如果 imageCache 尚未就绪或清除失败，忽略即可
    }
  }

  String _safeDeviceId(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }
}
