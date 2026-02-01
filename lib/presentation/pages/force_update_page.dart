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
  });

  final String storeUrl;
  final String? fallbackDownloadUrl;

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

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
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
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.force_update_message,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: subColor,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _openUrl(storeUrl),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(l10n.force_update_button),
                ),
              ),
              if (fallbackDownloadUrl != null &&
                  fallbackDownloadUrl!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
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
