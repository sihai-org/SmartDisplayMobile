import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_display_mobile/core/constants/app_environment.dart';
import 'package:smart_display_mobile/core/models/task_vo.dart';
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
  static const MethodChannel _androidDownloadChannel = MethodChannel(
    'com.datou.smart_display_mobile/downloads',
  );

  bool _isDownloading = false;
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
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      _fetchPdfUrlAndPrepare();
    });
  }

  @override
  void didUpdateWidget(covariant TaskPdfPreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldTaskId = oldWidget.task?.id.trim() ?? '';
    final newTaskId = widget.task?.id.trim() ?? '';
    if (oldTaskId != newTaskId) {
      _cachedPdfFile = null;
      _pdfUrl = null;
      _errorMessage = null;
      _previewState = _PdfPreviewState.idle;
      _inflightPdfFuture = null;
      _fetchPdfUrlAndPrepare();
    }
  }

  Future<void> _fetchPdfUrlAndPrepare() async {
    final taskId = widget.task?.id.trim() ?? '';
    if (taskId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _previewState = _PdfPreviewState.error;
        _retryPreparePhase = false;
        _errorMessage = '任务ID缺失';
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
    final accessToken = Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const HttpException('登录已过期，请重新登录');
    }

    final parsedTaskId = int.tryParse(taskId);
    final body = <String, dynamic>{
      'agent_task_id': parsedTaskId ?? taskId,
    };

    final response = await http.post(
      Uri.parse('${AppEnvironment.apiServerUrl}/agent_task/deepresearch/get_pdf'),
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
      throw const FormatException('无可用PDF链接');
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
        _errorMessage = '暂无可预览文件';
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

  Future<void> _downloadPdf(String pdfUrl, String displayFileName) async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
    });

    try {
      final localPdfFile = await _resolveLocalPdfFile(pdfUrl);
      if (mounted) {
        setState(() {
          _cachedPdfFile = localPdfFile;
        });
      }

      if (Platform.isIOS) {
        await _sharePdfOnIos(localPdfFile, displayFileName);
        return;
      }

      if (Platform.isAndroid) {
        await _downloadPdfOnAndroid(pdfUrl, displayFileName);
        return;
      }

      Fluttertoast.showToast(msg: '文件已缓存: ${localPdfFile.path}');
    } catch (e, stackTrace) {
      _logError('downloadPdf', e, stackTrace);
      Fluttertoast.showToast(msg: '下载失败: ${_readableError(e)}');
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _sharePdf(String pdfUrl, String displayFileName) async {
    if (_isSharing) return;
    setState(() {
      _isSharing = true;
    });

    try {
      final localPdfFile = await _resolveLocalPdfFile(pdfUrl);
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
      Fluttertoast.showToast(msg: '分享失败: ${_readableError(e)}');
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
    try {
      final fileToShare = await _prepareShareFile(localFile, displayFileName);
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
    File sourceFile,
    String displayFileName,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final shareRoot = Directory('${tempDir.path}/pdf_share');
    await shareRoot.create(recursive: true);
    final targetPath = '${shareRoot.path}/$displayFileName';
    final targetFile = File(targetPath);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    return sourceFile.copy(targetPath);
  }

  Future<void> _downloadPdfOnAndroid(
    String pdfUrl,
    String displayFileName,
  ) async {
    final hasPermission = await _ensureAndroidDownloadPermission();
    if (!hasPermission) {
      Fluttertoast.showToast(msg: '缺少存储权限，无法下载');
      return;
    }

    try {
      await _androidDownloadChannel.invokeMethod<void>(
        'enqueuePdfDownload',
        <String, dynamic>{
          'url': pdfUrl,
          'fileName': displayFileName,
          'title': displayFileName,
        },
      );
      Fluttertoast.showToast(msg: '开始下载，稍后可在 Download 查看');
    } on PlatformException catch (e) {
      Fluttertoast.showToast(msg: '下载失败: ${e.message ?? e.code}');
    }
  }

  Future<bool> _ensureAndroidDownloadPermission() async {
    if (!Platform.isAndroid) return true;
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;
    if (sdkInt >= 29) {
      return true;
    }

    final status = await Permission.storage.request();
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    return false;
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

  Future<File> _downloadToCacheIfNeeded(String pdfUrl) async {
    final dir = await getTemporaryDirectory();
    final cacheFileName = _cacheFileNameFromUrl(pdfUrl);
    final file = File('${dir.path}/$cacheFileName');
    final exists = await file.exists();
    if (exists) {
      final length = await file.length();
      if (length > 0) {
        return file;
      }
    }

    final response = await http.get(Uri.parse(pdfUrl));
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.isEmpty) {
      throw const HttpException('Empty response body');
    }
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file;
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
      return '网络异常，请检查连接';
    }
    if (error is FormatException) {
      return '链接格式错误';
    }
    return '请稍后重试';
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final pdfUrl = _pdfUrl?.trim() ?? '';
    final title = (task?.title.trim().isNotEmpty ?? false)
        ? task!.title
        : 'PDF预览';
    final displayFileName = '${_safeFileName(title)}.pdf';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: const BackButton(),
        actionsPadding: const EdgeInsets.only(right: 12), // ✅ 右侧留间距
        actions: [
          if (Platform.isAndroid)
            TextButton(
              onPressed: pdfUrl.isEmpty || _isDownloading
                  ? null
                  : () => _downloadPdf(pdfUrl, displayFileName),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _isDownloading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  const SizedBox(width: 2),
                  const Text('下载'),
                ],
              ),
            ),

          const SizedBox(width: 8), // ✅ 分享和下载之间的间距

          TextButton(
            onPressed: pdfUrl.isEmpty || _isSharing
                ? null
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
                const Text('分享'),
              ],
            ),
          ),
        ],
      ),
      body: _buildPdfBody(),
    );
  }

  Widget _buildPdfBody() {
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
        return const Center(child: Text('暂无可预览文件'));
      case _PdfPreviewState.error:
        final errorText = _errorMessage ?? '请稍后重试';
        final retryAction = _retryPreparePhase
            ? _startPreparePdf
            : _fetchPdfUrlAndPrepare;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('加载失败: $errorText'),
              const SizedBox(height: 12),
              FilledButton(onPressed: retryAction, child: const Text('重试')),
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

  String _cacheFileNameFromUrl(String pdfUrl) {
    final digest = crypto.md5.convert(utf8.encode(pdfUrl)).toString();
    return 'pdf_cache_$digest.pdf';
  }
}

class _PdfLoadingView extends StatelessWidget {
  const _PdfLoadingView({required this.showIndicator});

  final bool showIndicator;

  @override
  Widget build(BuildContext context) {
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
          const Text('正在加载PDF...'),
        ],
      ),
    );
  }
}
