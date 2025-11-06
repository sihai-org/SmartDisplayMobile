import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/l10n/l10n_extensions.dart';

class AccountSecurityPage extends ConsumerWidget {
  const AccountSecurityPage({super.key});

  // 占位空函数（实际逻辑待实现）
  void _onDeleteAccountConfirmed(BuildContext context, WidgetRef ref) {
    // TODO: implement delete account flow
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.account_security),
        // 默认带返回按钮，且支持 iOS 手势返回
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(l10n.delete_account),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(l10n.delete_account),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(l10n.cancel),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(l10n.ok),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      _onDeleteAccountConfirmed(context, ref);
                    }
                  },
                );
              },
              separatorBuilder: (context, index) => Divider(
                height: 1,
                thickness: 0.8,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade800
                    : Colors.grey.shade300,
                indent: MediaQuery.of(context).size.width / 8,
              ),
              itemCount: 1,
            ),
          ),
        ],
      ),
    );
  }
}
