import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:smart_display_mobile/core/services/task_file_service.dart';
import 'package:smart_display_mobile/data/repositories/device_customization_repository.dart';

/// 清理 app 产生的本地缓存文件（壁纸、任务文件、临时分享文件）。
///
/// 只动"丢了能从服务端重拉"的内容，不动 SecureStorage 里的用户设置。
class AppCacheCleanup {
  static Future<void> clearLocalCaches({String? fallbackUserId}) async {
    try {
      await DeviceCustomizationRepository().clearWallpaperFilesForCurrentUser(
        fallbackUserId: fallbackUserId,
      );
      await TaskFileService.clearCurrentUserCache(
        fallbackUserId: fallbackUserId,
      );
      final tempDir = await getTemporaryDirectory();
      await _deleteDirIfExists(Directory('${tempDir.path}/task_file_cache'));
      await _deleteDirIfExists(Directory('${tempDir.path}/task_file_share'));
      await _deleteDirIfExists(
        Directory('${tempDir.path}/task_file_downloads'),
      );
      await _deleteDirIfExists(Directory('${tempDir.path}/pdf_share'));
      await _deleteFilesByPrefix(tempDir, 'pdf_cache_');
    } catch (_) {
      // best effort，不要阻塞调用方
    }
  }

  static Future<void> _deleteFilesByPrefix(
    Directory directory,
    String fileNamePrefix,
  ) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments.last
          : '';
      if (!name.startsWith(fileNamePrefix)) continue;
      try {
        await entity.delete();
      } catch (_) {
        // best effort
      }
    }
  }

  static Future<void> _deleteDirIfExists(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // best effort
    }
  }
}
