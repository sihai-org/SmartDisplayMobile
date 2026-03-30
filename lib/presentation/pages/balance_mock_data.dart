import '../../l10n/app_localizations.dart';

class BalanceChangeItem {
  const BalanceChangeItem({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.amount,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final double amount;
}

const double mockBalanceAmount = 1287.0;

List<BalanceChangeItem> buildMockBalanceChanges(AppLocalizations l10n) {
  return [
    BalanceChangeItem(
      id: 'balance-001',
      title: l10n.balance_change_top_up,
      createdAt: DateTime(2026, 3, 30, 9, 20),
      amount: 2000,
    ),
    BalanceChangeItem(
      id: 'balance-002',
      title: l10n.balance_change_plan_purchase,
      createdAt: DateTime(2026, 3, 29, 18, 5),
      amount: -499,
    ),
    BalanceChangeItem(
      id: 'balance-003',
      title: l10n.balance_change_bonus,
      createdAt: DateTime(2026, 3, 29, 10, 16),
      amount: 88,
    ),
    BalanceChangeItem(
      id: 'balance-004',
      title: l10n.balance_change_plan_purchase,
      createdAt: DateTime(2026, 3, 28, 21, 40),
      amount: -299,
    ),
    BalanceChangeItem(
      id: 'balance-005',
      title: l10n.balance_change_adjustment,
      createdAt: DateTime(2026, 3, 28, 13, 5),
      amount: 120,
    ),
    BalanceChangeItem(
      id: 'balance-006',
      title: l10n.balance_change_refund,
      createdAt: DateTime(2026, 3, 27, 19, 20),
      amount: 56,
    ),
    BalanceChangeItem(
      id: 'balance-007',
      title: l10n.balance_change_plan_purchase,
      createdAt: DateTime(2026, 3, 26, 11, 50),
      amount: -49,
    ),
    BalanceChangeItem(
      id: 'balance-008',
      title: l10n.balance_change_plan_purchase,
      createdAt: DateTime(2026, 3, 25, 8, 30),
      amount: -130,
    ),
  ];
}
