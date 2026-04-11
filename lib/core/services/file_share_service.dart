import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_display_mobile/core/constants/app_environment.dart';
import 'package:smart_display_mobile/core/l10n/l10n_extensions.dart';
import 'package:smart_display_mobile/core/models/task_vo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FileShareService {
  static Future<void> shareTaskFile(BuildContext context, TaskVO task) async {
    final l10n = context.l10n;
    final shareOrigin = _shareOriginRect(context);
    try {
      final downloadUrl = await _fetchTaskDownloadUrl(
        task,
        loginExpiredMessage: l10n.login_expired,
        missingTaskIdMessage: l10n.task_pdf_missing_task_id,
        noAvailableLinkMessage: l10n.task_pdf_no_available_link,
      );
      final localFile = await _downloadToTemp(task, downloadUrl);
      final shareFile = await _prepareShareFile(task, localFile);
      final fileName = _buildFileName(task);

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(shareFile.path, mimeType: _mimeType(task), name: fileName),
          ],
          text: fileName,
          sharePositionOrigin: shareOrigin,
        ),
      );
    } catch (_) {
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

  static Future<File> _downloadToTemp(TaskVO task, String downloadUrl) async {
    final response = await http.get(Uri.parse(downloadUrl));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.isEmpty) {
      throw const HttpException('Empty response body');
    }

    final tempDir = await getTemporaryDirectory();
    final downloadRoot = Directory('${tempDir.path}/task_file_downloads');
    await downloadRoot.create(recursive: true);

    final file = File('${downloadRoot.path}/${_buildFileName(task)}');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
  }

  static Future<File> _prepareShareFile(TaskVO task, File sourceFile) async {
    final tempDir = await getTemporaryDirectory();
    final shareRoot = Directory('${tempDir.path}/task_file_share');
    await shareRoot.create(recursive: true);

    final targetFile = File('${shareRoot.path}/${_buildFileName(task)}');
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
    final extension = task.isPpt ? 'pptx' : 'pdf';
    if (safeName.toLowerCase().endsWith('.$extension')) {
      return safeName;
    }
    return '$safeName.$extension';
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
}
