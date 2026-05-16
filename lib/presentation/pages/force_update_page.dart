import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/theme/app_theme.dart';

/// Full-screen force-update gate. Non-dismissible; only "Update Now" opens store.
/// On Android, optional [fallbackDownloadUrl] shows "通过网页下载" to open browser download page.
class ForceUpdatePage extends StatelessWidget {
  const ForceUpdatePage({
    super.key,
    required this.storeUrl,
    this.fallbackDownloadUrl,
    this.releaseNotes,
  });

  final String storeUrl;
  final String? fallbackDownloadUrl;
  final String? releaseNotes;

  Future<void> _openUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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

    final buttonLabel = Platform.isIOS
        ? l10n.force_update_button_app_store
        : Platform.isAndroid
        ? l10n.force_update_button_play_store
        : l10n.force_update_button;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Image.asset(
                                'assets/images/logo.png',
                                width: 120,
                                height: 120,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              l10n.force_update_title,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: textColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            if (hasNotes) ...[
                              const SizedBox(height: 24),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.black.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  notes,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: subColor,
                                        height: 1.5,
                                      ),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 16),
                              Text(
                                l10n.force_update_message,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(color: subColor),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _openUrl(storeUrl),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(buttonLabel),
                ),
              ),
              if (hasFallback) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _openUrl(fallbackDownloadUrl!),
                  child: Text(l10n.force_update_download_via_web),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
