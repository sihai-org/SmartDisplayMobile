import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:smart_display_mobile/core/l10n/l10n_extensions.dart';
import 'package:smart_display_mobile/core/models/meeting_minutes_item.dart';
import 'package:smart_display_mobile/core/services/meeting_file_service.dart';

class MeetingMinutesDetailPage extends StatefulWidget {
  const MeetingMinutesDetailPage({super.key, required this.item});

  final MeetingMinutesItem? item;

  @override
  State<MeetingMinutesDetailPage> createState() =>
      _MeetingMinutesDetailPageState();
}

class _MeetingMinutesDetailPageState extends State<MeetingMinutesDetailPage> {
  bool _isSharing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final item = widget.item;
    final content = item?.markdown.trim();
    final itemTitle = item?.title.trim() ?? '';
    final displayTitle =
        itemTitle.isNotEmpty ? itemTitle : l10n.meeting_minutes_detail;
    final hasContent = content != null && content.isNotEmpty;

    final emptyTitleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.grey[700],
          fontWeight: FontWeight.w600,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(displayTitle),
        leading: const BackButton(),
        actions: [
          if (hasContent && item != null)
            TextButton(
              onPressed: _isSharing ? null : () => _share(item),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: _isSharing
                        ? const Padding(
                            padding: EdgeInsets.all(6),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.share, size: 24),
                  ),
                  const SizedBox(width: 2),
                  Text(l10n.meeting_minutes_share),
                ],
              ),
            ),
        ],
      ),
      body: !hasContent
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
              selectable: true,
              softLineBreak: true,
              extensionSet: md.ExtensionSet.gitHubFlavored,
            ),
    );
  }

  Future<void> _share(MeetingMinutesItem item) async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      await MeetingFileService.shareMeetingPdf(context, item);
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }
}
