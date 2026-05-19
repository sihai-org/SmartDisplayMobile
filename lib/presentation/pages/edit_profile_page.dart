import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/auth/auth_manager.dart';
import '../../core/constants/app_environment.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/log/app_log.dart';
import '../../core/network/http_timeouts.dart';
import '../../core/providers/user_profile_refresh_provider.dart';
import '../../core/utils/user_display_name_util.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final TextEditingController _usernameController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    final initialUsername = resolveUserDisplayName(user);
    _usernameController = TextEditingController(text: initialUsername);
    _usernameController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (_isSaving) return;
    final l10n = context.l10n;
    final userName = _usernameController.text.trim();
    if (userName.isEmpty) {
      Fluttertoast.showToast(msg: '请输入用户名');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final accessToken = await AuthManager.instance.getFreshAccessToken();
      if (accessToken == null || accessToken.isEmpty) {
        Fluttertoast.showToast(msg: '请先登录');
        return;
      }

      final response = await http
          .post(
            Uri.parse('${AppEnvironment.apiServerUrl}/monitorapp/update_user_info'),
            headers: {
              'Content-Type': 'application/json',
              'X-Access-Token': accessToken,
            },
            body: jsonEncode({'user_name': userName}),
          )
          .timeout(HttpTimeouts.business);

      if (response.statusCode != 200) {
        AppLog.instance.error(
          '[edit_profile] update_user_info http failed '
          'status=${response.statusCode} body=${response.body}',
          tag: 'UserProfile',
        );
        Fluttertoast.showToast(msg: '保存失败，请重试');
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['code'] != 200) {
        final message = decoded is Map ? decoded['message']?.toString() : null;
        AppLog.instance.error(
          '[edit_profile] update_user_info biz failed '
          'code=${decoded is Map ? decoded['code'] : 'invalid_json'} '
          'message=$message body=${response.body}',
          tag: 'UserProfile',
        );
        Fluttertoast.showToast(msg: (message?.isNotEmpty ?? false) ? message! : '保存失败，请重试');
        return;
      }

      // Keep local Supabase auth user in sync so ProfilePage can read latest username
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            'user_name': userName,
            'profile_updated_at': DateTime.now().toUtc().toIso8601String(),
          },
        ),
      );

      // Fallback: if local auth cache is not updated yet, fetch user once.
      final cachedUsername = (Supabase.instance.client.auth.currentUser
              ?.userMetadata?['user_name'] as String?)
          ?.trim();
      if (cachedUsername != userName) {
        await Supabase.instance.client.auth.getUser();
      }

      ref.read(userProfileRefreshProvider.notifier).state++;

      Fluttertoast.showToast(msg: l10n.settings_saved);
    } catch (e, st) {
      AppLog.instance.error(
        '[edit_profile] update_user_info exception',
        tag: 'UserProfile',
        error: e,
        stackTrace: st,
      );
      Fluttertoast.showToast(msg: l10n.network_or_timeout_tip);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: const Text('修改用户信息'),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const Center(
                    child: CircleAvatar(
                      radius: 44,
                      child: Icon(Icons.person, size: 44),
                    ),
                  ),
                  const SizedBox(height: 36),
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: '用户名',
                      hintText: '请输入用户名',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 26),
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _onSave,
                        child: Text(
                          _isSaving ? '保存中...' : '保存',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _LoadingMask(visible: _isSaving, text: '保存中'),
        ],
      ),
    );
  }
}

class _LoadingMask extends StatelessWidget {
  final bool visible;
  final String? text;

  const _LoadingMask({required this.visible, this.text});

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Positioned.fill(
      child: AbsorbPointer(
        absorbing: true,
        child: Container(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: Offset(0, 6),
                  color: Colors.black26,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                if (text != null && text!.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Text(text!, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
