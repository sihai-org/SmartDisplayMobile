import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:smart_display_mobile/core/constants/app_environment.dart';
import 'package:http/http.dart' as http;
import 'package:smart_display_mobile/core/log/app_log.dart';
import 'package:smart_display_mobile/core/models/task_vo.dart';
import 'package:smart_display_mobile/core/l10n/l10n_extensions.dart';
import 'package:smart_display_mobile/core/router/app_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key});

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  static const int _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  final List<TaskVO> _items = [];

  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasNextPage = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPage(reset: true);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasNextPage || _isLoading) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadPage();
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_isLoading) return;
    if (!mounted) return;
    if (!_hasNextPage && !reset) return;

    if (reset) {
      _page = 1;
      _hasNextPage = true;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _fetchTaskPage(page: _page, pageSize: _pageSize);
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(result.items);
        } else {
          _items.addAll(result.items);
        }
        _hasNextPage = result.hasNextPage;
        _page = _page + 1;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when fetching tasks',
        tag: 'TaskApi',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    await _loadPage(reset: true);
    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  Future<_TaskPageResult> _fetchTaskPage({
    required int page,
    required int pageSize,
  }) async {
    try {
      final accessToken =
          Supabase.instance.client.auth.currentSession?.accessToken;
      final response = await http.post(
        Uri.parse('${AppEnvironment.apiServerUrl}/agent_task/get_list'),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null && accessToken.isNotEmpty)
            'X-Access-Token': accessToken,
        },
        body: jsonEncode({'page': page, 'page_size': pageSize}),
      );

      if (response.statusCode != 200) {
        AppLog.instance.warning(
          '[task_get_list] non-200: ${response.statusCode} ${response.body}',
          tag: 'TaskApi',
        );
        return const _TaskPageResult.empty();
      }

      final decoded = jsonDecode(response.body);
      final realResult = _parseTaskResponse(decoded);
      if (realResult.items.isNotEmpty || realResult.hasNextPage) {
        AppLog.instance.info(
          '[task_get_list] parsed ${realResult.items.length} tasks from server',
          tag: 'TaskApi',
        );
      }

      return realResult;
    } catch (_) {
      rethrow;
    }
  }

  _TaskPageResult _parseTaskResponse(dynamic responseData) {
    if (responseData is! Map) return const _TaskPageResult.empty();
    final code = responseData['code'];
    if (code != 200) return const _TaskPageResult.empty();

    final data = responseData['data'];
    if (data is! Map) return const _TaskPageResult.empty();

    final tasks = data['data'];
    final hasNextPage = data['has_next_page'] == true;
    if (tasks is! List) {
      return _TaskPageResult(items: const [], hasNextPage: hasNextPage);
    }

    final items = <TaskVO>[];
    for (final entry in tasks) {
      final item = _parseTaskItem(entry);
      if (item != null) items.add(item);
    }

    return _TaskPageResult(items: items, hasNextPage: hasNextPage);
  }

  TaskVO? _parseTaskItem(dynamic raw) {
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));

    final id = _stringValue(map, ['id']) ?? '';
    final title = _stringValue(map, ['title']) ?? '';
    final status = _normalizeStatus(_stringValue(map, ['status']) ?? '');
    final createTime =
        _stringValue(map, [
          'createTime',
          'create_time',
          'created_at',
          'createdAt',
        ]) ??
        '';
    final finishTime =
        _stringValue(map, [
          'finishTime',
          'finish_time',
          'finished_at',
          'finishAt',
        ]) ??
        '';
    final type = _stringValue(map, ['type']) ?? '';
    return TaskVO(
      id: id,
      title: title,
      status: status,
      createTime: createTime,
      finishTime: finishTime,
      type: type,
    );
  }

  String? _stringValue(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  String _normalizeStatus(String status) {
    switch (status) {
      case TaskStatus.pending:
      case TaskStatus.running:
      case TaskStatus.success:
      case TaskStatus.failed:
      case TaskStatus.cancelled:
        return status;
      case 'processing':
        return TaskStatus.running;
      case 'done':
      case 'completed':
        return TaskStatus.success;
      case 'error':
        return TaskStatus.failed;
      default:
        return TaskStatus.pending;
    }
  }

  String _formatCreateTime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '--';
    final parsed = _parseServerDateTime(raw);
    if (parsed == null) return trimmed;
    final local = parsed.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  DateTime? _parseServerDateTime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final unixMillis = int.tryParse(trimmed);
    if (unixMillis != null) {
      if (trimmed.length >= 13) {
        return DateTime.fromMillisecondsSinceEpoch(unixMillis, isUtc: true);
      }
      if (trimmed.length == 10) {
        return DateTime.fromMillisecondsSinceEpoch(
          unixMillis * 1000,
          isUtc: true,
        );
      }
    }

    var normalized = trimmed.replaceFirst(' ', 'T');
    normalized = normalized.replaceAll(
      RegExp(r'([+-]\d{2})(\d{2})$'),
      r'$1:$2',
    );
    normalized = normalized.replaceFirstMapped(
      RegExp(r'([+-]\d{2})$'),
      (match) => '${match[1]}:00',
    );

    return DateTime.tryParse(normalized);
  }

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case TaskStatus.pending:
        return Colors.orange;
      case TaskStatus.running:
        return Colors.blue;
      case TaskStatus.success:
        return Colors.green;
      case TaskStatus.failed:
        return Theme.of(context).colorScheme.error;
      case TaskStatus.cancelled:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(BuildContext context, String status) {
    final l10n = context.l10n;
    switch (status) {
      case TaskStatus.pending:
        return l10n.task_status_pending;
      case TaskStatus.running:
        return l10n.task_status_running;
      case TaskStatus.success:
        return l10n.task_status_success;
      case TaskStatus.failed:
        return l10n.task_status_failed;
      case TaskStatus.cancelled:
        return l10n.task_status_cancelled;
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.task_list_title),
        leading: const BackButton(),
      ),
      body: RefreshIndicator(
        displacement: 12,
        edgeOffset: 0,
        onRefresh: _handleRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 32),
                children: [
                  SizedBox(
                    height: constraints.maxHeight,
                    child: Center(
                      child: _isLoading
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text(l10n.task_loading_data),
                              ],
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 88,
                                  height: 88,
                                  decoration: BoxDecoration(
                                    color: Color(0xFFEEEEEE),
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(20),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.task_outlined,
                                    size: 40,
                                    color: Color(0xFF9E9E9E),
                                  ),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  l10n.task_empty,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              );
            }

            final showOverlay = _isRefreshing && _items.isNotEmpty;
            final showLoadMoreFooter =
                _isLoading &&
                _items.isNotEmpty &&
                !_isRefreshing &&
                _hasNextPage;

            return Stack(
              children: [
                ListView.separated(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length + (showLoadMoreFooter ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index >= _items.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }

                    final task = _items[index];
                    final statusColor = _statusColor(context, task.status);
                    final isSuccess = task.status == TaskStatus.success;
                    final canPreviewPdf = isSuccess;
                    return Material(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          if (!isSuccess) {
                            Fluttertoast.showToast(
                              msg: l10n.task_preview_only_success,
                            );
                            return;
                          }
                          context.push(AppRoutes.taskPdfPreview, extra: task);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      task.title.trim().isEmpty
                                          ? l10n.task_unnamed
                                          : task.title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      _statusLabel(context, task.status),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: statusColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      l10n.task_created_time(
                                        _formatCreateTime(task.createTime),
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.grey[600]),
                                    ),
                                  ),
                                  if (canPreviewPdf)
                                    Text(
                                      l10n.task_view_result,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.blue[600]),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (showOverlay)
                  Positioned.fill(
                    child: AbsorbPointer(
                      child: Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.75),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_isRefreshing)
                                const CircularProgressIndicator(),
                              if (!_isRefreshing) const SizedBox(height: 12),
                              Text(l10n.task_loading_data),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TaskPageResult {
  final List<TaskVO> items;
  final bool hasNextPage;

  const _TaskPageResult({required this.items, required this.hasNextPage});

  const _TaskPageResult.empty() : items = const [], hasNextPage = false;
}
