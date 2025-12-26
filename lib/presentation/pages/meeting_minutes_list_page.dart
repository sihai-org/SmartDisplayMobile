import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
  late final Future<List<MeetingMinutesItem>> _itemsFuture;

  static const List<MeetingMinutesItem> _mockItems = [
    MeetingMinutesItem(
      id: '1',
      title: '项目周会纪要',
      date: '2025-02-12',
      time: '10:30',
      markdown: '''# 项目周会纪要

## 参会人员
- 产品
- 设计
- 开发

## 关键结论
1. 优先完成会议纪要列表页。
2. 下周补齐详情页的数据接口。

## 待办
- [ ] 列表页样式评审
- [ ] 接口联调
''',
    ),
    MeetingMinutesItem(
      id: '2',
      title: '需求评审纪要',
      date: '2025-02-08',
      time: '16:00',
      markdown: '''# 需求评审纪要

## 目标
- 明确版本范围
- 对齐交付节奏

## 决策
- 本期只做基础列表和详情。
- 数据使用 mock。

## 风险
- 详情内容需支持 Markdown 渲染。
''',
    ),
    MeetingMinutesItem(
      id: '3',
      title: '客户反馈整理',
      date: '2025-01-29',
      time: '09:15',
      markdown: '''# 客户反馈整理

## 主要问题
- 列表项信息层级不清晰
- 详情内容可读性一般

## 建议
- 第二行左右对齐日期/时间
- 标题加粗提升层级
''',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _itemsFuture = _fetchMeetingMinutes();
  }

  Future<List<MeetingMinutesItem>> _fetchMeetingMinutes() async {
    if (AuditMode.enabled) {
      return _mockItems;
    }

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'meeting_minutes_get',
        method: HttpMethod.get,
      );
      if (response.status != 200) {
        AppLog.instance.warning(
          '[meeting_minutes_get] non-200: ${response.status} ${response.data}',
          tag: 'Supabase',
        );
        return const [];
      }
      return _parseMeetingMinutes(response.data);
    } on FunctionException catch (error, stackTrace) {
      AppLog.instance.warning(
        '[meeting_minutes_get] status=${error.status}, details=${error.details}',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when fetching meeting minutes',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      return const [];
    }
  }

  List<MeetingMinutesItem> _parseMeetingMinutes(dynamic responseData) {
    final raw = _extractList(responseData);
    if (raw.isEmpty) return const [];

    final items = <MeetingMinutesItem>[];
    for (final entry in raw) {
      final item = _parseMeetingItem(entry);
      if (item != null) items.add(item);
    }
    return items;
  }

  List<dynamic> _extractList(dynamic responseData) {
    if (responseData is List) return responseData;
    if (responseData is Map) {
      final candidates = [
        responseData['data'],
        responseData['list'],
        responseData['items'],
        responseData['records'],
      ];
      for (final candidate in candidates) {
        if (candidate is List) return candidate;
      }
    }
    return const [];
  }

  MeetingMinutesItem? _parseMeetingItem(dynamic raw) {
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));

    final id =
        _stringValue(map, ['id', 'meeting_id', 'meetingId', 'uuid']) ?? '';
    final title =
        _stringValue(map, ['title', 'meeting_title', 'meetingTitle', 'name']) ??
            '';
    var date = _stringValue(map, ['date', 'meeting_date', 'meetingDate']) ?? '';
    var time = _stringValue(map, ['time', 'meeting_time', 'meetingTime']) ?? '';
    final markdown =
        _stringValue(map, ['markdown', 'content', 'detail', 'body']) ?? '';

    if (date.isEmpty || time.isEmpty) {
      final createdAt = _stringValue(
        map,
        ['created_at', 'createdAt', 'created_time', 'createdTime'],
      );
      if (createdAt != null && createdAt.isNotEmpty) {
        final parsed = DateTime.tryParse(createdAt);
        if (parsed != null) {
          date = _formatDate(parsed);
          time = _formatTime(parsed);
        }
      }
    }

    return MeetingMinutesItem(
      id: id,
      title: title,
      date: date,
      time: time,
      markdown: markdown,
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
      body: FutureBuilder<List<MeetingMinutesItem>>(
        future: _itemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(l10n.meeting_minutes_loading),
                ],
              ),
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
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
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return Material(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push(
                    AppRoutes.meetingMinutesDetail,
                    extra: item,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: Theme.of(context).textTheme.titleMedium,
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
              );
            },
          );
        },
      ),
    );
  }
}
