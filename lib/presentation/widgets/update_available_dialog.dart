import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/theme/app_theme.dart';

/// Dismissible update prompt for non-forced updates.
/// On Android, shows an extra "通过网页下载" entry when [fallbackDownloadUrl] is set.
Future<void> showUpdateAvailableDialog(
  BuildContext context, {
  required String version,
  required String storeUrl,
  String? releaseNotes,
  String? fallbackDownloadUrl,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _UpdateAvailableDialog(
      version: version,
      storeUrl: storeUrl,
      releaseNotes: releaseNotes,
      fallbackDownloadUrl: fallbackDownloadUrl,
    ),
  );
}

class _UpdateAvailableDialog extends StatelessWidget {
  const _UpdateAvailableDialog({
    required this.version,
    required this.storeUrl,
    this.releaseNotes,
    this.fallbackDownloadUrl,
  });

  final String version;
  final String storeUrl;
  final String? releaseNotes;
  final String? fallbackDownloadUrl;

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppTheme.textPrimaryColor;
    final subColor = isDark ? Colors.white70 : AppTheme.textSecondaryColor;

    final notes = releaseNotes?.trim();
    final hasNotes = notes != null && notes.isNotEmpty;
    final hasFallback =
        fallbackDownloadUrl != null && fallbackDownloadUrl!.trim().isNotEmpty;
    final showWebFallback = Platform.isAndroid && hasFallback;

    final maxNotesHeight = MediaQuery.of(context).size.height * 0.3;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.new_version_available(version),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxNotesHeight),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    hasNotes ? notes : l10n.update_generic_message,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: subColor,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openUrl(storeUrl);
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(l10n.update_now),
              ),
            ),
            if (showWebFallback)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openUrl(fallbackDownloadUrl!);
                },
                child: Text(l10n.force_update_download_via_web),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.update_later),
            ),
          ],
        ),
      ),
    );
  }
}
