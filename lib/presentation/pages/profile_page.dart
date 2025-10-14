import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/providers/locale_provider.dart';
import '../../core/router/app_router.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  void _showTopToast(BuildContext context, String message) {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: theme.textTheme.bodyMedium),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          right: 16,
        ),
        duration: const Duration(seconds: 2),
        dismissDirection: DismissDirection.up,
        backgroundColor: theme.brightness == Brightness.dark
            ? Colors.grey.shade900
            : Colors.grey.shade100,
        elevation: 2,
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await Supabase.instance.client.auth.signOut();
      context.go(AppRoutes.login);
    } catch (e) {
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.signout_failed(e.toString()))),
      );
    }
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }

  Widget _whiteListSection(BuildContext context, {
    required List<Widget> tiles,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) => tiles[index],
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 0.8,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey.shade800
              : Colors.grey.shade300,
          indent: MediaQuery.of(context).size.width / 8, // 左侧留白
        ),
        itemCount: tiles.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final saved = ref.watch(savedDevicesProvider);
    final locale = ref.watch(localeProvider);
    final devicesCount = saved.devices.length;

    final user = Supabase.instance.client.auth.currentUser;
    final displayName = (user?.userMetadata?['name'] as String?)?.trim();
    final email = user?.email;
    final userLabel = displayName?.isNotEmpty == true
        ? displayName!
        : (email ?? l10n.user_fallback);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profile_title),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.qrScanner),
            icon: const Icon(Icons.add),
            tooltip: l10n.scan_qr,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 顶部：头像 + 用户名 + 设备数量
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 28,
                  child: Icon(Icons.person, size: 28),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userLabel.isEmpty ? l10n.user_fallback : userLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        devicesCount > 0 ? l10n.devices_count(devicesCount) : l10n.empty_saved_devices,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 应用信息
          _sectionHeader(context, l10n.app_info),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _whiteListSection(context,
            tiles: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                title: Text(l10n.app_name),
                trailing: Text(AppConstants.appName, style: Theme.of(context).textTheme.bodyMedium),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                title: Text(l10n.version),
                trailing: Text(AppConstants.appVersion, style: Theme.of(context).textTheme.bodyMedium),
              ),
            ],
            ),
          ),

          // 设置
          _sectionHeader(context, l10n.settings_title),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _whiteListSection(context,
              tiles: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(l10n.language),
                  trailing: Text(
                    locale == null
                        ? l10n.language_system
                        : (locale.languageCode == 'zh' ? l10n.language_zh : 'English'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  ),
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
                          const SimpleDialogOption(
                            onPressed: null,
                            child: SizedBox.shrink(),
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(l10n.bluetooth_settings),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _showTopToast(context, l10n.google_signin_placeholder);
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(l10n.camera_permission),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _showTopToast(context, l10n.google_signin_placeholder);
                  },
                ),
              ],
            ),
          ),

          // 关于
          _sectionHeader(context, l10n.about),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _whiteListSection(context,
              tiles: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(l10n.help),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _showTopToast(context, '${l10n.help} - ${l10n.google_signin_placeholder}');
                  },
                ),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(l10n.feedback),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _showTopToast(context, '${l10n.feedback} - ${l10n.google_signin_placeholder}');
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 退出登录按钮（带二次确认）- 背景与列表一致，圆角一致
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: SizedBox(
              height: 48,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  textStyle: const TextStyle(fontSize: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(l10n.logout_confirm_title),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(l10n.cancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(l10n.logout_confirm_ok),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    await _signOut(context);
                  }
                },
                child: Text(l10n.logout),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
