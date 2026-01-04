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
  final List<String> localWallpaperPaths;

  const CustomizationFetchResult({
    required this.customization,
    this.localWallpaperPaths = const [],
  });

  const CustomizationFetchResult.empty()
      : customization = const DeviceCustomization.empty(),
        localWallpaperPaths = const [];
}

/// 本地持久化：用户为不同设备设置的壁纸/布局偏好。
///
/// 存储规则：
/// - 如果保存时壁纸、布局都为默认，则会直接删除该设备的自定义记录以保持存储整洁。
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

  String? _resolveUserId({String? fallbackUserId}) {
    final uid = _currentUserId();
    if (uid != null && uid.isNotEmpty) return uid;
    if (fallbackUserId != null && fallbackUserId.isNotEmpty) {
      return fallbackUserId;
    }
    return null;
  }

  String? _storageKeyForUser({String? fallbackUserId}) {
    final uid = _resolveUserId(fallbackUserId: fallbackUserId);
    if (uid == null || uid.isEmpty) return null;
    return '${StorageKeys.deviceCustomizationBase}_$uid';
  }

  String _userFolder({String? fallbackUserId}) {
    final uid = _resolveUserId(fallbackUserId: fallbackUserId);
    if (uid == null || uid.isEmpty) return 'guest';
    return _safeDeviceId(uid);
  }

  /// 读本地缓存 { deviceId: DeviceCustomization }
  Future<Map<String, DeviceCustomization>> _loadAll() async {
    final key = _storageKeyForUser();
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
    final key = _storageKeyForUser();
    if (key == null) return;
    final encoded = json.encode(
      data.map((k, v) => MapEntry(k, v.toJson())),
    );
    await _storage.write(key: key, value: encoded);
  }

  /// 读指定设备的缓存
  ///
  /// 当设备没有任何自定义时，返回空对象（等同于 default）。
  Future<DeviceCustomization> getUserCustomization(
      String displayDeviceId) async {
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
    final all = await _loadAll();

    if (customization.isLikeDefault) {
      all.remove(displayDeviceId);
    } else {
      all[displayDeviceId] = customization;
    }

    await _saveAll(all);
  }

  /// 清空当前用户所有设备的缓存（用于登出）。
  Future<void> clearCurrentUserData({String? fallbackUserId}) async {
    final userId = _resolveUserId(fallbackUserId: fallbackUserId);
    if (userId == null || userId.isEmpty) return;

    final userFolder = _userFolder(fallbackUserId: userId);
    final key = _storageKeyForUser(fallbackUserId: userId);
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
  /// 调用失败则返回 null
  Future<CustomizationFetchResult?> fetchUserCustomizationRemote(
    String displayDeviceId,
  ) async {
    if (displayDeviceId.isEmpty) {
      return const CustomizationFetchResult.empty();
    }
    // 审核模式直接走本地缓存，避免网络访问
    if (AuditMode.enabled) {
      final cached = await getUserCustomization(displayDeviceId);
      final localPaths = await getCachedWallpaperPaths(
        displayDeviceId,
        infos: cached.wallpaperInfos,
      );
      return CustomizationFetchResult(
        customization: cached,
        localWallpaperPaths: localPaths,
      );
    }

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'device_customization_get?device_id=${displayDeviceId}',
        method: HttpMethod.get, // 一定要加
      );
      final respData = response.data;

      AppLog.instance.info(
          "device_customization_get status=${response.status}, data=${respData}");


      if (response.status != 200) {
        final respMsg = _responseMessage(respData);
        throw respMsg == null || respMsg.isEmpty
            ? '服务异常（${response.status}）'
            : respMsg;
      }

      final customizationMap = _extractCustomizationMap(respData);

      if (customizationMap == null) {
        return const CustomizationFetchResult.empty();
      }

      final newCustomization = DeviceCustomization.fromJson(customizationMap);
      await saveUserCustomization(displayDeviceId, newCustomization);

      final newLocalPaths = await _syncWallpaperListCache(
        deviceId: displayDeviceId,
        wallpaperInfos: newCustomization.wallpaperInfos,
      );

      return CustomizationFetchResult(
        customization: newCustomization,
        localWallpaperPaths: newLocalPaths,
      );
    } on FunctionException catch (error, stackTrace) {
      AppLog.instance.warning(
        '[device_customization_get] status=${error.status}, details=${error.details}',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        'Unexpected error when fetching customization',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Map<String, dynamic>? _extractCustomizationMap(dynamic responseData) {
    if (responseData is! Map) return null;

    final data = responseData['data'];
    if (data == null) return null;

    if (data is! Map) return null;

    return data.map((key, value) => MapEntry(key.toString(), value));
  }

  String? _responseMessage(dynamic data) {
    if (data is Map && data['message'] != null) {
      return data['message']?.toString();
    }
    return data?.toString();
  }

  /// 全部壁纸 本地路径
  Future<List<String>> getCachedWallpaperPaths(
    String displayDeviceId, {
    List<CustomWallpaperInfo> infos = const [],
  }) async {
    if (displayDeviceId.isEmpty || infos.isEmpty) return const [];

    final results = <String>[];
    for (var i = 0; i < infos.length; i++) {
      final filePath = await _wallpaperFilePath(
        displayDeviceId,
        extension: _resolveExtension(infos[i]),
        index: i,
      );
      final file = File(filePath);
      if (await file.exists()) {
        results.add(file.path);
      }
    }
    return results;
  }

  /// 单张壁纸 本地路径
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
    int index = 0,
  }) async {
    final targetPath = await _wallpaperFilePath(
      deviceId,
      extension: extension,
      index: index,
    );
    final target = File(targetPath);
    await target.writeAsBytes(bytes, flush: true);
    _evictImageCache(target.path);
    return target.path;
  }

  Future<void> clearLocalWallpaperCache(String deviceId) async {
    if (deviceId.isEmpty) return;

    // 清理旧的散列文件（迁移到 deviceId 子目录前遗留的）
    await _cleanupLegacyDeviceFiles(deviceId);

    final dir = await _wallpaperDeviceDir(deviceId);
    if (!await dir.exists()) return;

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        _evictImageCache(entity.path);
        await entity.delete();
      } catch (_) {
        // ignore deletion failure
      }
    }

    try {
      await dir.delete(recursive: true);
    } catch (_) {
      // ignore deletion failure
    }
  }

  /// 按需更新本地缓存的壁纸图片
  Future<List<String>> _syncWallpaperListCache({
    required String deviceId,
    required List<CustomWallpaperInfo> wallpaperInfos,
  }) async {
    if (wallpaperInfos.isEmpty) {
      await clearLocalWallpaperCache(deviceId);
      return const [];
    }

    final localPaths = <String>[];
    final expectedPaths = <String>[];

    for (var i = 0; i < wallpaperInfos.length; i++) {
      final info = wallpaperInfos[i];

      final ext = _resolveExtension(info);
      final filePath = await _wallpaperFilePath(
        deviceId,
        extension: ext,
        index: i,
      );
      final file = File(filePath);
      expectedPaths.add(file.path);
      final remoteMd5 = info.md5.trim();
      final downloadUrl = info.downloadUrl;

      try {
        if (await file.exists()) {
          final localMd5 = await _computeFileMd5(file);
          if (localMd5 != null &&
              remoteMd5.isNotEmpty &&
              remoteMd5 == localMd5) {
            localPaths.add(file.path);
            continue;
          }
        }

        if (downloadUrl == null || downloadUrl.isEmpty) {
          if (await file.exists()) {
            localPaths.add(file.path);
          }
          continue;
        }

        await _downloadToFile(downloadUrl, file);
        final downloadedMd5 = await _computeFileMd5(file);
        if (remoteMd5.isNotEmpty &&
            downloadedMd5 != null &&
            remoteMd5 != downloadedMd5) {
          AppLog.instance.warning(
            'Wallpaper md5 mismatch, remote=$remoteMd5, local=$downloadedMd5',
            tag: 'Customization',
          );
        }
        localPaths.add(file.path);
      } catch (error, stackTrace) {
        AppLog.instance.warning(
          'Failed to sync wallpaper cache',
          tag: 'Customization',
          error: error,
          stackTrace: stackTrace,
        );
        if (await file.exists()) {
          localPaths.add(file.path);
        }
      }
    }

    await _removeStaleCachedWallpapers(
      deviceId: deviceId,
      keepPaths: expectedPaths,
    );

    return localPaths;
  }

  Future<void> _removeStaleCachedWallpapers({
    required String deviceId,
    required List<String> keepPaths,
  }) async {
    final dir = await _wallpaperDeviceDir(deviceId);
    if (!await dir.exists()) return;

    final keep = keepPaths.toSet();

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (keep.contains(entity.path)) continue;
      try {
        _evictImageCache(entity.path);
        await entity.delete();
      } catch (_) {
        // ignore deletion failure
      }
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
    int index = 0,
  }) async {
    final dir = await _wallpaperDeviceDir(deviceId);
    final ext = _resolveExtension(null, fallbackExtension: extension);
    final safeIndex = index < 0 ? 0 : index;
    return p.join(dir.path, '$safeIndex$ext');
  }

  Future<Directory> _wallpaperDir({String? userFolder}) async {
    final base = await getApplicationSupportDirectory();
    final folder = userFolder ?? _userFolder();
    final dir = Directory(p.join(base.path, 'wallpapers', folder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> _wallpaperDeviceDir(
    String deviceId, {
    String? userFolder,
  }) async {
    final baseDir = await _wallpaperDir(userFolder: userFolder);
    final safeId = _safeDeviceId(deviceId);

    // 迁移：移除旧的平铺文件，避免与新目录结构混用
    await _cleanupLegacyDeviceFiles(deviceId, baseDir: baseDir);

    final dir = Directory(p.join(baseDir.path, safeId));
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

  Future<void> _cleanupLegacyDeviceFiles(
    String deviceId, {
    Directory? baseDir,
  }) async {
    final base = baseDir ?? await _wallpaperDir();
    final safeId = _safeDeviceId(deviceId);

    await for (final entity in base.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith(safeId)) continue;
      try {
        _evictImageCache(entity.path);
        await entity.delete();
      } catch (_) {
        // ignore deletion failure
      }
    }
  }
}
