import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:smart_display_mobile/core/audit/audit_mode.dart';
import 'package:smart_display_mobile/core/log/app_log.dart';
import 'package:smart_display_mobile/core/network/http_timeouts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 远端文件本地缓存与系统分享的通用底层。
///
/// 业务层（如 TaskFileService / MeetingFileService）按 `namespace` + `identity`
/// 拼出语义化的缓存身份串后，由本类负责：用户隔离目录、LRU 清理、下载、
/// PDF/ZIP 签名校验、share_plus 调用 anchor 等纯基础设施。
class RemoteFileCache {
  static const int defaultMaxCachedFiles = 20;
  static const int defaultTrimmedCachedFiles = 15;
  static const String _logTag = 'RemoteFileCache';

  /// 把 identity hash 成稳定的缓存文件名。前缀由业务层指定以保持向后兼容。
  static String cacheFileName({
    required String identity,
    required String extension,
    required String filePrefix,
  }) {
    final digest = crypto.md5.convert(utf8.encode(identity)).toString();
    final ext = _stripLeadingDot(extension);
    return '$filePrefix$digest.$ext';
  }

  static Future<File?> readValidCachedFile({
    required String namespace,
    required String identity,
    required String extension,
    required String filePrefix,
  }) async {
    final cacheRoot = await _cacheRootDirectory(namespace: namespace);
    final file = File(
      '${cacheRoot.path}/${cacheFileName(identity: identity, extension: extension, filePrefix: filePrefix)}',
    );
    final tempFile = File('${file.path}.tmp');
    await _deleteIfExists(tempFile);
    return _readAndValidateCachedFile(file, extension: extension);
  }

  static Future<File> downloadToCacheIfNeeded({
    required String namespace,
    required String identity,
    required String extension,
    required String filePrefix,
    required String downloadUrl,
    int maxCachedFiles = defaultMaxCachedFiles,
    int trimmedCachedFiles = defaultTrimmedCachedFiles,
  }) async {
    final cached = await readValidCachedFile(
      namespace: namespace,
      identity: identity,
      extension: extension,
      filePrefix: filePrefix,
    );
    if (cached != null) {
      return cached;
    }

    final response = await http
        .get(Uri.parse(downloadUrl))
        .timeout(HttpTimeouts.transfer);
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.isEmpty) {
      throw const HttpException('Empty response body');
    }

    final cacheRoot = await _cacheRootDirectory(namespace: namespace);
    final file = File(
      '${cacheRoot.path}/${cacheFileName(identity: identity, extension: extension, filePrefix: filePrefix)}',
    );
    final tempFile = File('${file.path}.tmp');
    await _deleteIfExists(tempFile);
    await tempFile.writeAsBytes(response.bodyBytes, flush: true);

    final validatedTemp = await _readAndValidateCachedFile(
      tempFile,
      extension: extension,
    );
    if (validatedTemp == null) {
      throw const HttpException('Invalid downloaded file');
    }

    await _deleteIfExists(file);
    await validatedTemp.rename(file.path);
    await markFileAccessed(file);
    await _trimCacheIfNeeded(
      cacheRoot,
      filePrefix: filePrefix,
      maxCachedFiles: maxCachedFiles,
      trimmedCachedFiles: trimmedCachedFiles,
    );
    return file;
  }

  static Future<File> prepareShareFile({
    required File sourceFile,
    required String displayFileName,
    String shareDirectoryName = 'remote_file_share',
  }) async {
    final shareRoot = await _shareRootDirectory(shareDirectoryName);
    final targetFile = File('${shareRoot.path}/$displayFileName');
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    return sourceFile.copy(targetFile.path);
  }

  static Rect shareOriginRect(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox) {
      final origin = renderObject.localToGlobal(Offset.zero);
      final size = renderObject.size;
      if (size.width > 0 && size.height > 0) {
        return origin & size;
      }
    }
    return const Rect.fromLTWH(1, 1, 1, 1);
  }

  static Future<void> markFileAccessed(File file) async {
    try {
      if (!await file.exists()) return;
      await file.setLastModified(DateTime.now());
    } catch (_) {
      // best effort
    }
  }

  static Future<void> clearNamespaceForCurrentUser({
    required String namespace,
    String? fallbackUserId,
  }) async {
    try {
      final dir = await _cacheRootDirectory(
        namespace: namespace,
        fallbackUserId: fallbackUserId,
        createIfMissing: false,
      );
      if (!await dir.exists()) return;
      await dir.delete(recursive: true);
    } catch (_) {
      // best effort
    }
  }

  static Future<bool> looksLikePdf(File file) async {
    const header = '%PDF-';
    final prefix = await _readFilePrefix(file, ascii.encode(header).length + 3);
    if (prefix.length < 8 || !_hasPrefix(prefix, ascii.encode(header))) {
      return false;
    }

    const eof = '%%EOF';
    final tail = await _readFileTail(file, 2048);
    return _lastIndexOf(tail, ascii.encode(eof)) >= 0;
  }

  static Future<bool> looksLikeZipContainer(File file) async {
    const localFileHeader = [0x50, 0x4B, 0x03, 0x04];
    final prefix = await _readFilePrefix(file, localFileHeader.length);
    if (prefix.length < 4 || !_hasPrefix(prefix, localFileHeader)) {
      return false;
    }

    const eocd = [0x50, 0x4B, 0x05, 0x06];
    final tail = await _readFileTail(file, 65557);
    return _lastIndexOf(tail, eocd) >= 0;
  }

  // —— 私有 ——————————————————————————————

  static String? _currentUserId() {
    if (AuditMode.enabled) return AuditMode.auditUserId;
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  static String _userFolder({String? fallbackUserId}) {
    final userId = _currentUserId();
    final resolved = (userId != null && userId.isNotEmpty)
        ? userId
        : ((fallbackUserId != null && fallbackUserId.isNotEmpty)
              ? fallbackUserId
              : 'guest');
    return resolved.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  static Future<Directory> _cacheRootDirectory({
    required String namespace,
    String? fallbackUserId,
    bool createIfMissing = true,
  }) async {
    final appSupportDir = await getApplicationSupportDirectory();
    final cacheRoot = Directory(
      '${appSupportDir.path}/$namespace/${_userFolder(fallbackUserId: fallbackUserId)}',
    );
    if (!createIfMissing) {
      return cacheRoot;
    }
    await cacheRoot.create(recursive: true);
    return cacheRoot;
  }

  static Future<Directory> _shareRootDirectory(String directoryName) async {
    final tempDir = await getTemporaryDirectory();
    final shareRoot = Directory('${tempDir.path}/$directoryName');
    await shareRoot.create(recursive: true);
    return shareRoot;
  }

  static Future<void> _trimCacheIfNeeded(
    Directory cacheRoot, {
    required String filePrefix,
    required int maxCachedFiles,
    required int trimmedCachedFiles,
  }) async {
    try {
      final files = await _cacheFiles(cacheRoot, filePrefix: filePrefix);
      if (files.length <= maxCachedFiles) {
        return;
      }

      final deleteCount = files.length - trimmedCachedFiles;
      if (deleteCount <= 0) {
        return;
      }

      for (var i = 0; i < deleteCount; i++) {
        await _deleteIfExists(files[i]);
      }
    } catch (_) {
      // best effort
    }
  }

  static Future<List<File>> _cacheFiles(
    Directory cacheRoot, {
    required String filePrefix,
  }) async {
    final files = <File>[];
    if (!await cacheRoot.exists()) {
      return files;
    }

    await for (final entity in cacheRoot.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = _fileLabel(entity);
      if (!name.startsWith(filePrefix)) continue;
      if (name.endsWith('.tmp')) continue;
      files.add(entity);
    }

    final timestamps = <File, DateTime>{};
    for (final file in files) {
      try {
        timestamps[file] = await file.lastModified();
      } catch (_) {
        timestamps[file] = DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    files.sort(
      (a, b) => (timestamps[a] ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(timestamps[b] ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );
    return files;
  }

  static Future<File?> _readAndValidateCachedFile(
    File file, {
    required String extension,
  }) async {
    if (!await file.exists()) return null;

    final length = await file.length();
    if (length <= 0) {
      await _deleteCorruptedFile(
        file,
        reason: 'empty file',
        extension: extension,
      );
      return null;
    }

    final isValid = await _isLikelyValidFile(file, extension: extension);
    if (!isValid) {
      await _deleteCorruptedFile(
        file,
        reason: 'signature check failed',
        extension: extension,
      );
      return null;
    }

    return file;
  }

  static Future<bool> _isLikelyValidFile(
    File file, {
    required String extension,
  }) async {
    final normalized = _stripLeadingDot(extension).toLowerCase();
    if (normalized == 'pdf') {
      return looksLikePdf(file);
    }
    if (normalized == 'pptx') {
      return looksLikeZipContainer(file);
    }
    return true;
  }

  static Future<List<int>> _readFilePrefix(File file, int byteCount) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open(mode: FileMode.read);
      return await handle.read(byteCount);
    } finally {
      await handle?.close();
    }
  }

  static Future<List<int>> _readFileTail(File file, int byteCount) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open(mode: FileMode.read);
      final length = await handle.length();
      if (length <= 0) return const [];
      final start = math.max(0, length - byteCount);
      await handle.setPosition(start);
      return await handle.read(length - start);
    } finally {
      await handle?.close();
    }
  }

  static bool _hasPrefix(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static int _lastIndexOf(List<int> bytes, List<int> pattern) {
    if (pattern.isEmpty || bytes.length < pattern.length) return -1;
    for (var i = bytes.length - pattern.length; i >= 0; i--) {
      var matched = true;
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }
    return -1;
  }

  static Future<void> _deleteCorruptedFile(
    File file, {
    required String reason,
    required String extension,
  }) async {
    AppLog.instance.warning(
      'delete invalid cache file=${_fileLabel(file)} extension=$extension reason=$reason',
      tag: _logTag,
    );
    await _deleteIfExists(file);
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // best effort
    }
  }

  static String _fileLabel(File file) {
    final segments = file.uri.pathSegments;
    return segments.isEmpty ? file.path : segments.last;
  }

  static String _stripLeadingDot(String extension) {
    final trimmed = extension.trim();
    if (trimmed.startsWith('.')) return trimmed.substring(1);
    return trimmed;
  }
}
