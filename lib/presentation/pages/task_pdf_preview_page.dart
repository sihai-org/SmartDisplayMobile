import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:smart_display_mobile/core/constants/app_environment.dart';
import 'package:smart_display_mobile/core/l10n/l10n_extensions.dart';
import 'package:smart_display_mobile/core/models/task_vo.dart';
import 'package:smart_display_mobile/core/services/task_file_service.dart';
import 'package:smart_display_mobile/core/utils/task_file_name_formatter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

enum _PdfPreviewState { idle, loadingUrl, preparingPdf, ready, error }

class TaskPdfPreviewPage extends StatefulWidget {
  const TaskPdfPreviewPage({super.key, required this.task});

  final TaskVO? task;

  @override
  State<TaskPdfPreviewPage> createState() => _TaskPdfPreviewPageState();
}

class _TaskPdfPreviewPageState extends State<TaskPdfPreviewPage> {
  bool _isSharing = false;
  _PdfPreviewState _previewState = _PdfPreviewState.idle;
  bool _retryPreparePhase = false;
  File? _cachedPdfFile;
  String? _pdfUrl;
  String? _errorMessage;
  Future<File>? _inflightPdfFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      _preparePdfOfflineFirst();
    });
  }

  @override
  void didUpdateWidget(covariant TaskPdfPreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCacheIdentity = TaskFileService.cacheIdentityForTask(
      oldWidget.task,
      fileExtension: 'pdf',
    );
    final newCacheIdentity = TaskFileService.cacheIdentityForTask(
      widget.task,
      fileExtension: 'pdf',
    );
    if (oldCacheIdentity != newCacheIdentity) {
      _cachedPdfFile = null;
      _pdfUrl = null;
      _errorMessage = null;
      _previewState = _PdfPreviewState.idle;
      _inflightPdfFuture = null;
      _preparePdfOfflineFirst();
    }
  }

  Future<void> _preparePdfOfflineFirst() async {
    final l10n = context.l10n;
    final taskId = widget.task?.id.trim() ?? '';
    if (taskId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _previewState = _PdfPreviewState.error;
        _retryPreparePhase = false;
        _errorMessage = l10n.task_pdf_missing_task_id;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _previewState = _PdfPreviewState.preparingPdf;
        _retryPreparePhase = false;
        _errorMessage = null;
      });
    }

    final cachedFile = await _readValidCachedPdfForTask();
    if (cachedFile != null) {
      if (!mounted) return;
      setState(() {
        _cachedPdfFile = cachedFile;
        _previewState = _PdfPreviewState.ready;
        _retryPreparePhase = true;
      });
      return;
    }

    await _fetchPdfUrlAndPrepare();
  }

  Future<void> _fetchPdfUrlAndPrepare() async {
    final l10n = context.l10n;
    final taskId = widget.task?.id.trim() ?? '';
    if (taskId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _previewState = _PdfPreviewState.error;
        _retryPreparePhase = false;
        _errorMessage = l10n.task_pdf_missing_task_id;
      });
      return;
    }

    setState(() {
      _previewState = _PdfPreviewState.loadingUrl;
      _retryPreparePhase = false;
      _errorMessage = null;
      _pdfUrl = null;
      _cachedPdfFile = null;
    });

    try {
      final url = await _fetchPdfDownloadUrl(taskId);
      if (!mounted) return;
      setState(() {
        _pdfUrl = url;
      });
      _startPreparePdf();
    } catch (e, stackTrace) {
      _logError('fetchPdfUrl', e, stackTrace);
      if (!mounted) return;
      setState(() {
        _previewState = _PdfPreviewState.error;
        _retryPreparePhase = false;
        _errorMessage = _readableError(e);
      });
    }
  }

  Future<String> _fetchPdfDownloadUrl(String taskId) async {
    final noAvailableLinkMessage = context.l10n.task_pdf_no_available_link;
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw HttpException(context.l10n.login_expired);
    }

    final parsedTaskId = int.tryParse(taskId);
    final body = <String, dynamic>{'agent_task_id': parsedTaskId ?? taskId};

    final response = await http.post(
      Uri.parse(
        '${AppEnvironment.apiServerUrl}/agent_task/deepresearch/get_pdf',
      ),
      headers: {
        'Content-Type': 'application/json',
        'X-Access-Token': accessToken,
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final pdfUrl = _extractPdfUrl(decoded);
    if (pdfUrl == null || pdfUrl.isEmpty) {
      throw FormatException(noAvailableLinkMessage);
    }
    return pdfUrl;
  }

  String? _extractPdfUrl(dynamic response) {
    if (response is! Map) return null;
    final map = response.map((k, v) => MapEntry(k.toString(), v));
    final code = map['code'];
    if (code != null && code != 200) return null;

    final data = map['data'];
    if (data is Map) {
      final dataMap = data.map((k, v) => MapEntry(k.toString(), v));
      final nested = _pickFirstString(dataMap, const [
        'pdf_download_url',
        'pdf_url',
        'url',
        'download_url',
      ]);
      if (nested != null) return nested;
    }

    return _pickFirstString(map, const [
      'pdf_download_url',
      'pdf_url',
      'url',
      'download_url',
    ]);
  }

  String? _pickFirstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  void _startPreparePdf() {
    final pdfUrl = _pdfUrl?.trim() ?? '';
    if (pdfUrl.isEmpty) {
      if (!mounted) return;
      setState(() {
        _previewState = _PdfPreviewState.error;
        _retryPreparePhase = false;
        _errorMessage = context.l10n.task_pdf_no_preview_file;
      });
      return;
    }
    setState(() {
      _previewState = _PdfPreviewState.preparingPdf;
      _retryPreparePhase = true;
      _errorMessage = null;
    });
    _resolveLocalPdfFile(pdfUrl)
        .then((file) {
          if (!mounted) return;
          setState(() {
            _cachedPdfFile = file;
            _previewState = _PdfPreviewState.ready;
          });
        })
        .catchError((Object e, StackTrace stackTrace) {
          _logError('preparePdf', e, stackTrace);
          if (!mounted) return;
          setState(() {
            _previewState = _PdfPreviewState.error;
            _retryPreparePhase = true;
            _errorMessage = _readableError(e);
          });
        });
  }

  Future<void> _sharePdf(String pdfUrl, String displayFileName) async {
    if (_isSharing) return;
    final task = widget.task;
    final shareFailedMessage = context.l10n.task_pdf_share_failed;
    if (task == null) {
      Fluttertoast.showToast(msg: shareFailedMessage);
      return;
    }
    setState(() {
      _isSharing = true;
    });

    try {
      final localPdfFile = await _getShareablePdfFile(pdfUrl);
      if (mounted) {
        setState(() {
          _cachedPdfFile = localPdfFile;
        });
      }

      if (Platform.isIOS) {
        await _sharePdfOnIos(localPdfFile, displayFileName);
        return;
      }

      final fileToShare = await _prepareShareFile(
        task,
        localPdfFile,
        displayFileName,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              fileToShare.path,
              mimeType: 'application/pdf',
              name: displayFileName,
            ),
          ],
          text: displayFileName,
        ),
      );
    } catch (e, stackTrace) {
      _logError('sharePdf', e, stackTrace);
      Fluttertoast.showToast(msg: shareFailedMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  String _safeTaskId() {
    final rawId = (widget.task?.id.trim().isNotEmpty ?? false)
        ? widget.task!.id.trim()
        : DateTime.now().millisecondsSinceEpoch.toString();
    return rawId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  Future<void> _sharePdfOnIos(File localFile, String displayFileName) async {
    final task = widget.task;
    if (task == null) {
      throw HttpException(context.l10n.task_pdf_no_shareable_file);
    }
    try {
      final fileToShare = await _prepareShareFile(
        task,
        localFile,
        displayFileName,
      );
      final shareOrigin = _shareOriginRect();
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              fileToShare.path,
              mimeType: 'application/pdf',
              name: displayFileName,
            ),
          ],
          text: displayFileName,
          sharePositionOrigin: shareOrigin,
        ),
      );
    } catch (e, stackTrace) {
      _logError('sharePdfOnIos', e, stackTrace);
      rethrow;
    }
  }

  Future<File> _prepareShareFile(
    TaskVO task,
    File sourceFile,
    String displayFileName,
  ) async {
    return TaskFileService.prepareShareFile(
      task,
      sourceFile,
      displayFileName: displayFileName,
    );
  }

  Future<File> _resolveLocalPdfFile(String pdfUrl) {
    final inflight = _inflightPdfFuture;
    if (inflight != null) {
      return inflight;
    }
    final future = _downloadToCacheIfNeeded(pdfUrl);
    _inflightPdfFuture = future;
    return future.whenComplete(() {
      if (identical(_inflightPdfFuture, future)) {
        _inflightPdfFuture = null;
      }
    });
  }

  Future<File> _getShareablePdfFile(String pdfUrl) async {
    final task = widget.task;
    final noShareableFileMessage = context.l10n.task_pdf_no_shareable_file;
    if (task == null) {
      throw HttpException(noShareableFileMessage);
    }
    final existingCached = await _readValidCachedPdfForTask();
    if (existingCached != null) {
      return existingCached;
    }
    if (pdfUrl.trim().isNotEmpty) {
      return _resolveLocalPdfFile(pdfUrl);
    }
    throw HttpException(noShareableFileMessage);
  }

  Future<File?> _readValidCachedPdfForTask() async {
    return TaskFileService.readValidCachedFileForTask(
      widget.task,
      fileExtension: 'pdf',
    );
  }

  Future<File> _downloadToCacheIfNeeded(String pdfUrl) async {
    final task = widget.task;
    if (task == null) {
      throw HttpException(context.l10n.task_pdf_no_shareable_file);
    }
    final cached = await _readValidCachedPdfForTask();
    if (cached != null) {
      return cached;
    }
    return TaskFileService.downloadToCacheIfNeeded(
      task,
      pdfUrl,
      fileExtension: 'pdf',
    );
  }

  void _logError(String context, Object error, StackTrace stackTrace) {
    debugPrint('[TaskPdfPreviewPage][$context] $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  Rect _shareOriginRect() {
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

  String _readableError(Object error) {
    if (error is HttpException) {
      return error.message;
    }
    if (error is SocketException) {
      return context.l10n.task_pdf_network_error;
    }
    if (error is FormatException) {
      return context.l10n.task_pdf_invalid_link;
    }
    return context.l10n.task_pdf_retry_later;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final task = widget.task;
    final pdfUrl = _pdfUrl?.trim() ?? '';
    final title = (task?.title.trim().isNotEmpty ?? false)
        ? task!.title
        : l10n.task_pdf_default_title;
    final displayFileName = appendFileExtensionIfMissing(
      _safeFileName(title),
      extension: 'pdf',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: const BackButton(),
        actionsPadding: const EdgeInsets.only(right: 12),
        actions: [
          TextButton(
            onPressed: pdfUrl.isEmpty || _isSharing
                ? (_cachedPdfFile == null || _isSharing
                      ? null
                      : () => _sharePdf('', displayFileName))
                : () => _sharePdf(pdfUrl, displayFileName),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _isSharing
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share),
                const SizedBox(width: 2),
                Text(l10n.task_pdf_share),
              ],
            ),
          ),
        ],
      ),
      body: _buildPdfBody(),
    );
  }

  Widget _buildPdfBody() {
    final l10n = context.l10n;
    switch (_previewState) {
      case _PdfPreviewState.idle:
        return const _PdfLoadingView(showIndicator: false);
      case _PdfPreviewState.loadingUrl:
      case _PdfPreviewState.preparingPdf:
        return const _PdfLoadingView(showIndicator: true);
      case _PdfPreviewState.ready:
        final cachedFile = _cachedPdfFile;
        if (cachedFile != null) {
          return SfPdfViewer.file(cachedFile);
        }
        return Center(child: Text(l10n.task_pdf_no_preview_file));
      case _PdfPreviewState.error:
        final errorText = _errorMessage ?? l10n.task_pdf_retry_later;
        final retryAction = _retryPreparePhase
            ? _startPreparePdf
            : _fetchPdfUrlAndPrepare;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(errorText),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: retryAction,
                child: Text(l10n.task_pdf_retry),
              ),
            ],
          ),
        );
    }
  }

  String _safeFileName(String name) {
    final trimmed = name.trim();
    final fallback = trimmed.isEmpty ? 'task_${_safeTaskId()}' : trimmed;
    return fallback.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
}

class _PdfLoadingView extends StatelessWidget {
  const _PdfLoadingView({required this.showIndicator});

  final bool showIndicator;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: showIndicator ? 1 : 0,
            child: const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(),
            ),
          ),
          const SizedBox(height: 12),
          Text(l10n.task_pdf_loading),
        ],
      ),
    );
  }
}
