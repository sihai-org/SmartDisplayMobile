import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:smart_display_mobile/core/auth/auth_manager.dart';
import 'package:smart_display_mobile/core/constants/app_environment.dart';
import 'package:smart_display_mobile/core/errors/network_error_util.dart';
import 'package:smart_display_mobile/core/l10n/l10n_extensions.dart';
import 'package:smart_display_mobile/core/log/app_log.dart';
import 'package:smart_display_mobile/core/models/meeting_minutes_item.dart';
import 'package:smart_display_mobile/core/network/http_timeouts.dart';
import 'package:smart_display_mobile/core/services/remote_file_cache.dart';
import 'package:smart_display_mobile/core/utils/task_file_name_formatter.dart';

class MeetingFileService {
  static const String _shareLogTag = 'MeetingFileShare';

  static const String _kNamespace = 'meetings';
  static const String _kCacheFilePrefix = 'meeting_file_cache_';
  static const String _kShareDirectoryName = 'meeting_file_share';
  static const String _kFileExtension = 'pdf';
  static const String _kMimeType = 'application/pdf';

  static Future<void> shareMeetingPdf(
    BuildContext context,
    MeetingMinutesItem item,
  ) async {
    final l10n = context.l10n;
    final shareOrigin = RemoteFileCache.shareOriginRect(context);
    final totalStopwatch = Stopwatch()..start();
    final meetingId = item.id.trim();
    final fileName = _buildFileName(item);

    AppLog.instance.info(
      'start meetingId=$meetingId fileName="$fileName"',
      tag: _shareLogTag,
    );

    try {
      final cacheLookupStopwatch = Stopwatch()..start();
      final cachedFile = await _readValidCachedFile(item);
      cacheLookupStopwatch.stop();

      File localFile;
      if (cachedFile != null) {
        final cachedSize = await cachedFile.length();
        AppLog.instance.info(
          'cache hit meetingId=$meetingId lookupMs=${cacheLookupStopwatch.elapsedMilliseconds} '
          'size=${_formatBytes(cachedSize)} path=${_fileLabel(cachedFile)}',
          tag: _shareLogTag,
        );
        localFile = cachedFile;
      } else {
        AppLog.instance.info(
          'cache miss meetingId=$meetingId lookupMs=${cacheLookupStopwatch.elapsedMilliseconds}',
          tag: _shareLogTag,
        );

        final fetchUrlStopwatch = Stopwatch()..start();
        final downloadUrl = await _fetchMeetingDownloadUrl(
          item,
          loginExpiredMessage: l10n.login_expired,
          missingIdMessage: l10n.meeting_minutes_missing_id,
          noAvailableLinkMessage: l10n.meeting_minutes_no_pdf_link,
        );
        fetchUrlStopwatch.stop();
        AppLog.instance.info(
          'fetch url done meetingId=$meetingId fetchUrlMs=${fetchUrlStopwatch.elapsedMilliseconds} '
          'host=${_urlHost(downloadUrl)}',
          tag: _shareLogTag,
        );

        final downloadStopwatch = Stopwatch()..start();
        localFile = await _downloadToCacheIfNeeded(item, downloadUrl);
        downloadStopwatch.stop();
        final downloadedSize = await localFile.length();
        AppLog.instance.info(
          'download done meetingId=$meetingId downloadMs=${downloadStopwatch.elapsedMilliseconds} '
          'size=${_formatBytes(downloadedSize)} path=${_fileLabel(localFile)}',
          tag: _shareLogTag,
        );
      }

      unawaited(RemoteFileCache.markFileAccessed(localFile));

      final prepareShareStopwatch = Stopwatch()..start();
      final shareFile = await RemoteFileCache.prepareShareFile(
        sourceFile: localFile,
        displayFileName: fileName,
        shareDirectoryName: _kShareDirectoryName,
      );
      prepareShareStopwatch.stop();
      final shareFileSize = await shareFile.length();
      AppLog.instance.info(
        'prepare share file done meetingId=$meetingId prepareShareMs=${prepareShareStopwatch.elapsedMilliseconds} '
        'size=${_formatBytes(shareFileSize)} path=${_fileLabel(shareFile)}',
        tag: _shareLogTag,
      );

      AppLog.instance.info(
        'invoke system share meetingId=$meetingId totalMs=${totalStopwatch.elapsedMilliseconds}',
        tag: _shareLogTag,
      );
      final shareStopwatch = Stopwatch()..start();
      final shareResult = await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(shareFile.path, mimeType: _kMimeType, name: fileName),
          ],
          text: fileName,
          sharePositionOrigin: shareOrigin,
        ),
      );
      shareStopwatch.stop();
      totalStopwatch.stop();

      AppLog.instance.info(
        'share result meetingId=$meetingId shareMs=${shareStopwatch.elapsedMilliseconds} '
        'totalMs=${totalStopwatch.elapsedMilliseconds} status=${shareResult.status.name} '
        'raw=${_shareRaw(shareResult.raw)}',
        tag: _shareLogTag,
      );
    } catch (error, stackTrace) {
      totalStopwatch.stop();
      AppLog.instance.error(
        'share failed meetingId=$meetingId totalMs=${totalStopwatch.elapsedMilliseconds}',
        tag: _shareLogTag,
        error: error,
        stackTrace: stackTrace,
      );
      Fluttertoast.showToast(
        msg: NetworkErrorUtil.isNetworkOrTimeout(error)
            ? l10n.network_or_timeout_tip
            : l10n.meeting_minutes_share_failed,
      );
    }
  }

  static Future<String> _fetchMeetingDownloadUrl(
    MeetingMinutesItem item, {
    required String loginExpiredMessage,
    required String missingIdMessage,
    required String noAvailableLinkMessage,
  }) async {
    final accessToken = await AuthManager.instance.getFreshAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      throw HttpException(loginExpiredMessage);
    }

    final meetingId = item.id.trim();
    if (meetingId.isEmpty) {
      throw HttpException(missingIdMessage);
    }

    final parsedId = int.tryParse(meetingId);
    final response = await http
        .post(
          Uri.parse('${AppEnvironment.apiServerUrl}/meeting/get_result_pdf'),
          headers: {
            'Content-Type': 'application/json',
            'X-Access-Token': accessToken,
          },
          body: jsonEncode({'meeting_task_id': parsedId ?? meetingId}),
        )
        .timeout(HttpTimeouts.business);

    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final downloadUrl = _extractDownloadUrl(decoded);
    if (downloadUrl == null || downloadUrl.isEmpty) {
      throw HttpException(noAvailableLinkMessage);
    }
    return downloadUrl;
  }

  static String? _extractDownloadUrl(dynamic response) {
    if (response is! Map) return null;
    final map = response.map((key, value) => MapEntry(key.toString(), value));
    final code = map['code'];
    if (code != null && code != 200) return null;

    final data = map['data'];
    if (data is Map) {
      final dataMap = data.map((key, value) => MapEntry(key.toString(), value));
      final nested = _pickFirstString(dataMap, const [
        'pdf_url',
        'url',
        'download_url',
      ]);
      if (nested != null) return nested;
    }

    return _pickFirstString(map, const ['pdf_url', 'url', 'download_url']);
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

  static String _cacheIdentity(MeetingMinutesItem item) {
    final id = item.id.trim();
    final title = item.title.trim();
    final date = item.date.trim();
    final time = item.time.trim();
    return '$id|$title|$date|$time|$_kFileExtension';
  }

  static Future<File?> _readValidCachedFile(MeetingMinutesItem item) {
    return RemoteFileCache.readValidCachedFile(
      namespace: _kNamespace,
      identity: _cacheIdentity(item),
      extension: _kFileExtension,
      filePrefix: _kCacheFilePrefix,
    );
  }

  static Future<File> _downloadToCacheIfNeeded(
    MeetingMinutesItem item,
    String downloadUrl,
  ) {
    return RemoteFileCache.downloadToCacheIfNeeded(
      namespace: _kNamespace,
      identity: _cacheIdentity(item),
      extension: _kFileExtension,
      filePrefix: _kCacheFilePrefix,
      downloadUrl: downloadUrl,
    );
  }

  static Future<void> clearCurrentUserCache({String? fallbackUserId}) {
    return RemoteFileCache.clearNamespaceForCurrentUser(
      namespace: _kNamespace,
      fallbackUserId: fallbackUserId,
    );
  }

  static String _buildFileName(MeetingMinutesItem item) {
    final rawName = item.title.trim().isEmpty
        ? 'meeting_${_safeId(item)}'
        : item.title.trim();
    final safeName = rawName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return appendFileExtensionIfMissing(
      safeName,
      extension: _kFileExtension,
    );
  }

  static String _safeId(MeetingMinutesItem item) {
    final id = item.id.trim();
    if (id.isEmpty) {
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
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
}
