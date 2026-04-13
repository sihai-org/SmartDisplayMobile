import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_display_mobile/core/constants/app_environment.dart';
import 'package:smart_display_mobile/core/l10n/l10n_extensions.dart';
import 'package:smart_display_mobile/core/log/app_log.dart';
import 'package:smart_display_mobile/core/models/task_vo.dart';
import 'package:smart_display_mobile/core/utils/task_file_name_formatter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TaskFileService {
  static const String _shareLogTag = 'TaskFileShare';

  static Future<void> shareTaskFile(BuildContext context, TaskVO task) async {
    final l10n = context.l10n;
    final shareOrigin = _shareOriginRect(context);
    final totalStopwatch = Stopwatch()..start();
    final taskId = task.id.trim();
    final fileName = _buildFileName(task);

    AppLog.instance.info(
      'start taskId=$taskId type=${task.normalizedType} fileName="$fileName"',
      tag: _shareLogTag,
    );

    try {
      final cacheLookupStopwatch = Stopwatch()..start();
      final cachedFile = await readValidCachedFileForTask(task);
      cacheLookupStopwatch.stop();

      File localFile;
      if (cachedFile != null) {
        final cachedSize = await cachedFile.length();
        AppLog.instance.info(
          'cache hit taskId=$taskId lookupMs=${cacheLookupStopwatch.elapsedMilliseconds} '
          'size=${_formatBytes(cachedSize)} path=${_fileLabel(cachedFile)}',
          tag: _shareLogTag,
        );
        localFile = cachedFile;
      } else {
        AppLog.instance.info(
          'cache miss taskId=$taskId lookupMs=${cacheLookupStopwatch.elapsedMilliseconds}',
          tag: _shareLogTag,
        );

        final fetchUrlStopwatch = Stopwatch()..start();
        final downloadUrl = await _fetchTaskDownloadUrl(
          task,
          loginExpiredMessage: l10n.login_expired,
          missingTaskIdMessage: l10n.task_pdf_missing_task_id,
          noAvailableLinkMessage: l10n.task_pdf_no_available_link,
        );
        fetchUrlStopwatch.stop();
        AppLog.instance.info(
          'fetch url done taskId=$taskId fetchUrlMs=${fetchUrlStopwatch.elapsedMilliseconds} '
          'host=${_urlHost(downloadUrl)}',
          tag: _shareLogTag,
        );

        final downloadStopwatch = Stopwatch()..start();
        localFile = await downloadToCacheIfNeeded(task, downloadUrl);
        downloadStopwatch.stop();
        final downloadedSize = await localFile.length();
        AppLog.instance.info(
          'download done taskId=$taskId downloadMs=${downloadStopwatch.elapsedMilliseconds} '
          'size=${_formatBytes(downloadedSize)} path=${_fileLabel(localFile)}',
          tag: _shareLogTag,
        );
      }

      final prepareShareStopwatch = Stopwatch()..start();
      final shareFile = await prepareShareFile(task, localFile);
      prepareShareStopwatch.stop();
      final shareFileSize = await shareFile.length();
      AppLog.instance.info(
        'prepare share file done taskId=$taskId prepareShareMs=${prepareShareStopwatch.elapsedMilliseconds} '
        'size=${_formatBytes(shareFileSize)} path=${_fileLabel(shareFile)}',
        tag: _shareLogTag,
      );

      AppLog.instance.info(
        'invoke system share taskId=$taskId totalMs=${totalStopwatch.elapsedMilliseconds}',
        tag: _shareLogTag,
      );
      final shareStopwatch = Stopwatch()..start();
      final shareResult = await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(shareFile.path, mimeType: _mimeType(task), name: fileName),
          ],
          text: fileName,
          sharePositionOrigin: shareOrigin,
        ),
      );
      shareStopwatch.stop();
      totalStopwatch.stop();

      AppLog.instance.info(
        'share result taskId=$taskId shareMs=${shareStopwatch.elapsedMilliseconds} '
        'totalMs=${totalStopwatch.elapsedMilliseconds} status=${shareResult.status.name} '
        'raw=${_shareRaw(shareResult.raw)}',
        tag: _shareLogTag,
      );
    } catch (error, stackTrace) {
      totalStopwatch.stop();
      AppLog.instance.error(
        'share failed taskId=$taskId type=${task.normalizedType} '
        'totalMs=${totalStopwatch.elapsedMilliseconds}',
        tag: _shareLogTag,
        error: error,
        stackTrace: stackTrace,
      );
      Fluttertoast.showToast(msg: l10n.task_pdf_share_failed);
    }
  }

  static Future<String> _fetchTaskDownloadUrl(
    TaskVO task, {
    required String loginExpiredMessage,
    required String missingTaskIdMessage,
    required String noAvailableLinkMessage,
  }) async {
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw HttpException(loginExpiredMessage);
    }

    final taskId = task.id.trim();
    if (taskId.isEmpty) {
      throw HttpException(missingTaskIdMessage);
    }

    final parsedTaskId = int.tryParse(taskId);
    final response = await http.post(
      Uri.parse('${AppEnvironment.apiServerUrl}${_endpoint(task)}'),
      headers: {
        'Content-Type': 'application/json',
        'X-Access-Token': accessToken,
      },
      body: jsonEncode({'agent_task_id': parsedTaskId ?? taskId}),
    );

    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final downloadUrl = _extractDownloadUrl(task, decoded);
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw HttpException(noAvailableLinkMessage);
    }
    return downloadUrl;
  }

  static String _endpoint(TaskVO task) {
    return task.isPpt
        ? '/agent_task/deepresearch/get_ppt'
        : '/agent_task/deepresearch/get_pdf';
  }

  static String? _extractDownloadUrl(TaskVO task, dynamic response) {
    if (response is! Map) return null;
    final map = response.map((key, value) => MapEntry(key.toString(), value));
    final code = map['code'];
    if (code != null && code != 200) return null;

    final data = map['data'];
    if (data is Map) {
      final dataMap = data.map((key, value) => MapEntry(key.toString(), value));
      final nested = _pickFirstString(
        dataMap,
        task.isPpt
            ? const ['ppt_url', 'url', 'download_url']
            : const ['pdf_download_url', 'pdf_url', 'url', 'download_url'],
      );
      if (nested != null) return nested;
    }

    return _pickFirstString(
      map,
      task.isPpt
          ? const ['ppt_url', 'url', 'download_url']
          : const ['pdf_download_url', 'pdf_url', 'url', 'download_url'],
    );
  }

  static String? _pickFirstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static String cacheIdentityForTask(TaskVO? task, {String? fileExtension}) {
    final taskId = task?.id.trim() ?? '';
    final createTime = task?.createTime.trim() ?? '';
    final finishTime = task?.finishTime.trim() ?? '';
    final extension = _normalizedExtension(task, fileExtension);
    return '$taskId|$createTime|$finishTime|$extension';
  }

  static String cacheFileNameForTask(TaskVO? task, {String? fileExtension}) {
    final identity = cacheIdentityForTask(task, fileExtension: fileExtension);
    final digest = crypto.md5.convert(utf8.encode(identity)).toString();
    final extension = _normalizedExtension(task, fileExtension);
    return 'task_file_cache_$digest.$extension';
  }

  static Future<File?> readValidCachedFileForTask(
    TaskVO? task, {
    String? fileExtension,
  }) async {
    final cacheRoot = await _cacheRootDirectory();
    final extension = _normalizedExtension(task, fileExtension);
    final file = File(
      '${cacheRoot.path}/${cacheFileNameForTask(task, fileExtension: extension)}',
    );
    final tempFile = File('${file.path}.tmp');
    await _deleteIfExists(tempFile);
    return _readAndValidateCachedFile(file, extension: extension);
  }

  static Future<File> downloadToCacheIfNeeded(
    TaskVO task,
    String downloadUrl, {
    String? fileExtension,
  }) async {
    final extension = _normalizedExtension(task, fileExtension);
    final cached = await readValidCachedFileForTask(
      task,
      fileExtension: extension,
    );
    if (cached != null) {
      return cached;
    }

    final response = await http.get(Uri.parse(downloadUrl));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.isEmpty) {
      throw const HttpException('Empty response body');
    }

    final cacheRoot = await _cacheRootDirectory();
    final file = File(
      '${cacheRoot.path}/${cacheFileNameForTask(task, fileExtension: extension)}',
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
    return file;
  }

  static Future<File> prepareShareFile(
    TaskVO task,
    File sourceFile, {
    String? displayFileName,
  }) async {
    final shareRoot = await _shareRootDirectory();
    final targetFile = File(
      '${shareRoot.path}/${displayFileName ?? _buildFileName(task)}',
    );
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    return sourceFile.copy(targetFile.path);
  }

  static String _buildFileName(TaskVO task) {
    final rawName = task.title.trim().isEmpty
        ? 'task_${_safeTaskId(task)}'
        : task.title.trim();
    final safeName = rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return appendFileExtensionIfMissing(
      safeName,
      extension: task.isPpt ? 'pptx' : 'pdf',
    );
  }

  static String _safeTaskId(TaskVO task) {
    final taskId = task.id.trim();
    if (taskId.isEmpty) {
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
    return taskId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  static String _mimeType(TaskVO task) {
    return task.isPpt
        ? 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
        : 'application/pdf';
  }

  static String _normalizedExtension(TaskVO? task, String? fileExtension) {
    final explicit = fileExtension?.trim().toLowerCase();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit.startsWith('.') ? explicit.substring(1) : explicit;
    }
    return task?.isPpt == true ? 'pptx' : 'pdf';
  }

  static Future<Directory> _cacheRootDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final cacheRoot = Directory('${tempDir.path}/task_file_cache');
    await cacheRoot.create(recursive: true);
    return cacheRoot;
  }

  static Future<Directory> _shareRootDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final shareRoot = Directory('${tempDir.path}/task_file_share');
    await shareRoot.create(recursive: true);
    return shareRoot;
  }

  static Rect _shareOriginRect(BuildContext context) {
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

  static String _fileLabel(File file) {
    final segments = file.uri.pathSegments;
    return segments.isEmpty ? file.path : segments.last;
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  static String _urlHost(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.isEmpty ? '(empty-host)' : uri.host;
    } catch (_) {
      return '(invalid-url)';
    }
  }

  static String _shareRaw(String raw) {
    if (raw.isEmpty) return '(empty)';
    return raw;
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
    final normalized = extension.trim().toLowerCase();
    if (normalized == 'pdf') {
      return _looksLikePdf(file);
    }
    if (normalized == 'pptx') {
      return _looksLikeZipContainer(file);
    }
    return true;
  }

  static Future<bool> _looksLikePdf(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length < 8) return false;

    const header = '%PDF-';
    if (!_hasPrefix(bytes, ascii.encode(header))) {
      return false;
    }

    const eof = '%%EOF';
    return _lastIndexOf(bytes, ascii.encode(eof)) >= 0;
  }

  static Future<bool> _looksLikeZipContainer(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length < 22) return false;

    const localFileHeader = [0x50, 0x4B, 0x03, 0x04];
    if (!_hasPrefix(bytes, localFileHeader)) {
      return false;
    }

    const eocd = [0x50, 0x4B, 0x05, 0x06];
    return _lastIndexOf(bytes, eocd) >= 0;
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
      'delete invalid task cache file=${_fileLabel(file)} extension=$extension reason=$reason',
      tag: _shareLogTag,
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
}
