import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n/l10n_extensions.dart';
import 'balance_mock_data.dart';

class BalanceBillPage extends StatelessWidget {
  const BalanceBillPage({super.key});

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

  String _formatDate(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
  }

  Widget _buildChangeTile(BuildContext context, BalanceChangeItem item) {
    final positive = item.amount >= 0;
    final amountColor = positive ? Colors.green.shade700 : Colors.red.shade400;
    final iconColor = positive ? Colors.green.shade100 : Colors.red.shade100;
    final iconData = positive ? Icons.arrow_downward : Icons.arrow_upward;

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
    final changes = buildMockBalanceChanges(l10n);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.balance_bills_title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l10n.balance_mock_hint,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
          ),
          _sectionCard(
            context,
            children: changes
                .map((item) => _buildChangeTile(context, item))
                .toList(),
          ),
        ],
      ),
    );
  }
}
