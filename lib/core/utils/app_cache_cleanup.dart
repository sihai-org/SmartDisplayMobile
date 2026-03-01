import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Clears app-generated cache files that should not survive logout.
class AppCacheCleanup {
  static Future<void> clearOnLogout() async {
    await _clearPdfPreviewCache();
  }

  static Future<void> _clearPdfPreviewCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      await _deleteDirIfExists(Directory('${tempDir.path}/pdf_share'));
      await _deleteFilesByPrefix(tempDir, 'pdf_cache_');
    } catch (_) {
      // Ignore cleanup failure to avoid blocking logout flow.
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
