import 'package:flutter/material.dart';
import '../../core/l10n/l10n_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/locale_provider.dart';
import '../../l10n/app_localizations.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final locale = ref.watch(localeProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings_title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        children: [
          // App Info Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.app_info,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: Icon(Icons.info),
                    title: Text(l10n.app_name),
                    subtitle: const Text(AppConstants.appName),
                    contentPadding: EdgeInsets.zero,
                  ),
                  ListTile(
                    leading: Icon(Icons.tag),
                    title: Text(l10n.version),
                    subtitle: const Text(AppConstants.appVersion),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Settings Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settings_title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  // Language selector
                  ListTile(
                    leading: const Icon(Icons.language),
                    title: Text(l10n.language),
                    subtitle: Text(
                      locale == null
                          ? l10n.language_system
                          : (locale.languageCode == 'zh'
                              ? l10n.language_zh
                              : 'English'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () async {
                      final picked = await showDialog<Locale?>(
                        context: context,
                        builder: (context) => SimpleDialog(
                          title: Text(l10n.language),
                          children: [
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(context, null),
                              child: Text(l10n.language_system),
                            ),
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(context, const Locale('en')),
                              child: const Text('English'),
                            ),
                            SimpleDialogOption(
                              onPressed: () => Navigator.pop(context, const Locale('zh')),
                              child: Text(l10n.language_zh),
                            ),
                          ],
                        ),
                      );
                      if (picked != null || locale != null) {
                        ref.read(localeProvider.notifier).state = picked;
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(l10n.bluetooth_settings),
                    subtitle: Text(l10n.manage_bluetooth),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      // TODO: Navigate to Bluetooth settings
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.camera_alt),
                    title: Text(l10n.camera_permission),
                    subtitle: Text(l10n.manage_qr_permission),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      // TODO: Navigate to camera permissions
                    },
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // About Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.about,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.help),
                    title: Text(l10n.help),
                    subtitle: Text(l10n.help_desc),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      // TODO: Navigate to help page
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.bug_report),
                    title: Text(l10n.feedback),
                    subtitle: Text(l10n.feedback_desc),
                    trailing: const Icon(Icons.chevron_right),
                    contentPadding: EdgeInsets.zero,
                    onTap: () {
                      // TODO: Navigate to feedback page
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
