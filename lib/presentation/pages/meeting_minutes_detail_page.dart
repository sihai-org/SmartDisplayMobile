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

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.meeting_minutes_detail),
        leading: const BackButton(),
      ),
      body: content == null || content.isEmpty
          ? Center(child: Text(l10n.meeting_minutes_detail_empty))
          : Markdown(
              data: content,
              padding: const EdgeInsets.all(16),
            ),
    );
  }
}
