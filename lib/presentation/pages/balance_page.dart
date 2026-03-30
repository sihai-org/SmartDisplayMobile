import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/router/app_router.dart';
import 'balance_mock_data.dart';

class BalancePage extends StatelessWidget {
  const BalancePage({super.key});

  Widget _sectionCard(BuildContext context, {required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: children.length,
        itemBuilder: (context, index) => children[index],
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 0.8,
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey.shade800
              : Colors.grey.shade300,
          indent: MediaQuery.of(context).size.width / 8,
        ),
      ),
    );
  }

  String _formatAmount(BuildContext context, double amount) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final formatter = NumberFormat.currency(
      locale: locale,
      symbol: '¥',
      decimalDigits: 2,
    );
    final prefix = amount >= 0 ? '+' : '-';
    return '$prefix${formatter.format(amount.abs())}';
  }

  String _formatBalance(BuildContext context, double amount) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return NumberFormat.currency(
      locale: locale,
      symbol: '¥',
      decimalDigits: 2,
    ).format(amount);
  }

  String _formatDate(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
  }

  Widget _buildChangeTile(BuildContext context, BalanceChangeItem item) {
    final positive = item.amount >= 0;
    final amountColor = positive ? Colors.green.shade700 : Colors.red.shade400;
    final iconColor = positive ? Colors.green.shade100 : Colors.red.shade100;
    final iconData = positive ? Icons.arrow_upward : Icons.arrow_downward;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: iconColor,
        child: Icon(
          iconData,
          size: 18,
          color: positive ? Colors.green.shade700 : Colors.red.shade400,
        ),
      ),
      title: Text(item.title),
      subtitle: Text(
        _formatDate(item.createdAt),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
      ),
      trailing: Text(
        _formatAmount(context, item.amount),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: amountColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final recentChanges = buildMockBalanceChanges(l10n).take(3).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.balance)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.balance_available,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                Text(
                  _formatBalance(context, mockBalanceAmount),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.balance_mock_hint,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: null,
                    child: Text(l10n.balance_recharge_button),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.balance_recent_changes,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: () => context.push(AppRoutes.balanceBills),
                child: Text(l10n.balance_view_all),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _sectionCard(
            context,
            children: recentChanges
                .map((item) => _buildChangeTile(context, item))
                .toList(),
          ),
        ],
      ),
    );
  }
}
