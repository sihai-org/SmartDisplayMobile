import 'dart:convert';

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_display_mobile/core/audit/audit_mode.dart';
import 'package:smart_display_mobile/core/l10n/l10n_extensions.dart';
import 'package:smart_display_mobile/core/log/app_log.dart';
import 'package:smart_display_mobile/core/models/meeting_minutes_item.dart';
import 'package:smart_display_mobile/core/router/app_router.dart';

class MeetingMinutesListPage extends StatefulWidget {
  const MeetingMinutesListPage({super.key});

  @override
  State<MeetingMinutesListPage> createState() => _MeetingMinutesListPageState();
}

class _MeetingMinutesListPageState extends State<MeetingMinutesListPage> {
  static const int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();
  final List<MeetingMinutesItem> _items = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _hasNextPage = true;
  int _page = 1;

  List<MeetingMinutesItem> _buildMockItems(AppLocalizations l10n) {
    return [
      MeetingMinutesItem(
        id: '1',
        title: l10n.meeting_minutes_mock_title_1,
        date: '2025-02-12',
        time: '10:30',
        markdown: l10n.meeting_minutes_mock_content_1,
        taskStatus: MeetingMinutesTaskStatus.extractedContent,
      ),
      MeetingMinutesItem(
        id: '2',
        title: l10n.meeting_minutes_mock_title_2,
        date: '2025-02-08',
        time: '16:00',
        markdown: l10n.meeting_minutes_mock_content_2,
        taskStatus: MeetingMinutesTaskStatus.extractedContent,
      ),
      MeetingMinutesItem(
        id: '3',
        title: l10n.meeting_minutes_mock_title_3,
        date: '2025-01-29',
        time: '09:15',
        markdown: l10n.meeting_minutes_mock_content_3,
        taskStatus: MeetingMinutesTaskStatus.extractedContent,
      ),
    ];
  }

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

    if (AuditMode.enabled) {
      final l10n = context.l10n;
      setState(() {
        _items
          ..clear()
          ..addAll(_buildMockItems(l10n));
        _hasNextPage = false;
        _isLoading = false;
      });
      return;
    }

    try {
      final result = await _fetchMeetingMinutesPage(
        page: _page,
        pageSize: _pageSize,
      );
      setState(() {
        if (reset) {
          _items
            ..clear()
            ..addAll(result.items); // ✅ 这里才清空 + 替换
        } else {
          _items.addAll(result.items);
        }

        _hasNextPage = result.hasNextPage;
        _page = _page + 1;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when fetching meeting minutes',
        tag: 'MeetingMinutesApi',
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

  Future<_MeetingMinutesPageResult> _fetchMeetingMinutesPage({
    required int page,
    required int pageSize,
  }) async {
    try {
      final accessToken =
          Supabase.instance.client.auth.currentSession?.accessToken;
      final response = await http.post(
        Uri.parse(
            'https://api.smartdisplay.vzngpt.com/meeting/query_meeting_task'),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null && accessToken.isNotEmpty)
            'accessToken': accessToken,
        },
        body: jsonEncode({
          'page': page,
          'page_size': pageSize,
        }),
      );
      if (response.statusCode != 200) {
        AppLog.instance.warning(
          '[meeting_minutes_get] non-200: ${response.statusCode} ${response.body}',
          tag: 'MeetingMinutesApi',
        );
        return const _MeetingMinutesPageResult.empty();
      }
      final decoded = jsonDecode(response.body);
      return _parseMeetingMinutesResponse(decoded);
    } catch (_) {
      rethrow;
    }
  }

  _MeetingMinutesPageResult _parseMeetingMinutesResponse(dynamic responseData) {
    if (responseData is! Map) return const _MeetingMinutesPageResult.empty();
    final code = responseData['code'];
    if (code != 200) return const _MeetingMinutesPageResult.empty();

    final data = responseData['data'];
    if (data is! Map) return const _MeetingMinutesPageResult.empty();
    final list = data['data'];
    final hasNextPage = data['has_next_page'] == true;
    if (list is! List) {
      return _MeetingMinutesPageResult(
        items: const [],
        hasNextPage: hasNextPage,
      );
    }

    final items = <MeetingMinutesItem>[];
    for (final entry in list) {
      final item = _parseMeetingItem(entry);
      if (item != null) items.add(item);
    }
    return _MeetingMinutesPageResult(
      items: items,
      hasNextPage: hasNextPage,
    );
  }

  MeetingMinutesItem? _parseMeetingItem(dynamic raw) {
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));

    final id = _stringValue(map, ['id']) ?? '';
    final title = _stringValue(map, ['title']) ?? '';
    final taskStatus = _stringValue(map, ['task_status']) ?? '';
    var date = '';
    var time = '';
    final markdown = _stringValue(map, ['ai_summary_content']) ?? '';

    if (date.isEmpty || time.isEmpty) {
      final createdAt = _stringValue(map, ['created_at']);
      if (createdAt != null && createdAt.isNotEmpty) {
        final parsed = _parseServerDateTime(createdAt);
        if (parsed != null) {
          final localTime = parsed.toLocal();
          date = _formatDate(localTime);
          time = _formatTime(localTime);
        }
      }
    }

    return MeetingMinutesItem(
      id: id,
      title: title,
      date: date,
      time: time,
      markdown: markdown,
      taskStatus: taskStatus,
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

  String _displayTitleForStatus(
    AppLocalizations l10n,
    String taskStatus,
    String baseTitle,
  ) {
    if (taskStatus == MeetingMinutesTaskStatus.extractedContent) {
      return baseTitle;
    }
    if (MeetingMinutesTaskStatus.isFailed(taskStatus)) {
      return l10n.meeting_minutes_failed;
    }
    return l10n.meeting_minutes_generating;
  }

  String _formatDate(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  DateTime? _parseServerDateTime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final sanitized = trimmed.replaceFirst(' ', 'T');
    final normalized = sanitized.replaceFirstMapped(
      RegExp(r'([+-]\d{2})$'),
      (match) => '${match[1]}:00',
    );
    return DateTime.tryParse(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.grey[600],
        );
    final emptyTitleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.grey[700],
          fontWeight: FontWeight.w600,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.meeting_minutes_list),
        leading: const BackButton(),
      ),
      body: _buildBody(
        l10n,
        textStyle,
        emptyTitleStyle,
      ),
    );
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

  Widget _buildBody(
    AppLocalizations l10n,
    TextStyle? textStyle,
    TextStyle? emptyTitleStyle,
  ) {
    return RefreshIndicator(
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
                              if (!_isRefreshing)
                                const CircularProgressIndicator(),
                              if (!_isRefreshing) const SizedBox(height: 12),
                              Text(l10n.meeting_minutes_loading),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  Icons.notes_outlined,
                                  size: 40,
                                  color: Colors.grey[500],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                l10n.meeting_minutes_empty,
                                style: emptyTitleStyle,
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
              _isLoading && _items.isNotEmpty && !_isRefreshing && _hasNextPage;

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
                  final item = _items[index];
                  final baseTitle = item.title.trim().isEmpty
                      ? l10n.meeting_minutes
                      : item.title;
                  final isEnabled = item.isExtractedContent;
                  final displayTitle = _displayTitleForStatus(
                    l10n,
                    item.taskStatus,
                    baseTitle,
                  );
                  final titleStyle =
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: isEnabled ? null : Colors.grey[500],
                          );
                  return Material(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: isEnabled
                          ? () => context.push(
                                AppRoutes.meetingMinutesDetail,
                                extra: item,
                              )
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Opacity(
                          opacity: isEnabled ? 1 : 0.5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayTitle,
                                style: titleStyle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(item.date, style: textStyle),
                                  const Spacer(),
                                  Text(item.time, style: textStyle),
                                ],
                              ),
                            ],
                          ),
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
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withOpacity(0.75),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!_isRefreshing)
                              const CircularProgressIndicator(),
                            if (!_isRefreshing) const SizedBox(height: 12),
                            Text(l10n.meeting_minutes_loading),
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
    );
  }
}

class _MeetingMinutesPageResult {
  final List<MeetingMinutesItem> items;
  final bool hasNextPage;

  const _MeetingMinutesPageResult({
    required this.items,
    required this.hasNextPage,
  });

  const _MeetingMinutesPageResult.empty()
      : items = const [],
        hasNextPage = false;
}
