import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:smart_display_mobile/core/l10n/l10n_extensions.dart';
import 'package:smart_display_mobile/core/models/meeting_minutes_item.dart';

class MeetingMinutesDetailPage extends StatelessWidget {
  const MeetingMinutesDetailPage({super.key, required this.item});

  final MeetingMinutesItem? item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final content = item?.markdown.trim();
    final itemTitle = item?.title.trim() ?? '';
    final displayTitle =
        itemTitle.isNotEmpty ? itemTitle : l10n.meeting_minutes_detail;

    final emptyTitleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.grey[700],
          fontWeight: FontWeight.w600,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(displayTitle),
        leading: const BackButton(),
      ),
      body: content == null || content.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
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
                      l10n.meeting_minutes_detail_empty,
                      style: emptyTitleStyle,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : Markdown(
              data: content,
              padding: const EdgeInsets.all(16),
            ),
    );
  }
}
