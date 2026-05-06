import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:smart_display_mobile/core/auth/auth_manager.dart';
import 'package:smart_display_mobile/core/theme/purchase_button_style.dart';
import '../../core/audit/audit_mode.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/log/app_log.dart';
import '../../core/providers/audit_billing_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/billing_amount_formatter.dart';
import '../../data/repositories/billing_repository.dart';
import 'balance_bill_page.dart';
import '../widgets/android_buy_button.dart';
import '../widgets/ios_buy_button.dart';

class BalancePage extends ConsumerStatefulWidget {
  const BalancePage({super.key});

  @override
  ConsumerState<BalancePage> createState() => _BalancePageState();
}

class _BalancePageState extends ConsumerState<BalancePage> {
  final BillingRepository _billingRepository = BillingRepository();

  BillingBalanceData? _balance;
  List<BillingLedgerItem> _ledgerItems = const [];

  bool _isBalanceLoading = true;
  bool _hasBalanceError = false;
  bool _isLedgerLoading = true;
  bool _hasLedgerError = false;
  bool _ledgerInitialized = false;
  int _ledgerNextPage = 1;
  bool _ledgerHasNextPage = true;

  bool get _isAuditMode => AuditMode.enabled;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (_isAuditMode) {
      final auditBilling = ref.read(auditBillingProvider);
      if (!mounted) return;
      setState(() {
        _balance = auditBilling.balance;
        _ledgerItems = auditBilling.ledgerItems;
        _isBalanceLoading = false;
        _hasBalanceError = false;
        _isLedgerLoading = false;
        _hasLedgerError = false;
        _ledgerInitialized = true;
        _ledgerNextPage = 1;
        _ledgerHasNextPage = false;
      });
      return;
    }

    final accessToken = await AuthManager.instance.getFreshAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      if (!mounted) return;
      setState(() {
        _balance = null;
        _ledgerItems = const [];
        _isBalanceLoading = false;
        _isLedgerLoading = false;
        _hasBalanceError = true;
        _hasLedgerError = true;
        _ledgerInitialized = false;
        _ledgerNextPage = 1;
        _ledgerHasNextPage = true;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _balance = null;
        _ledgerItems = const [];
        _isBalanceLoading = true;
        _isLedgerLoading = true;
        _hasBalanceError = false;
        _hasLedgerError = false;
        _ledgerInitialized = false;
        _ledgerNextPage = 1;
        _ledgerHasNextPage = true;
      });
    }

    BillingBalanceData? balance;
    List<BillingLedgerItem> ledgerItems = const [];
    var hasBalanceError = false;
    var hasLedgerError = false;
    var ledgerNextPage = 1;
    var ledgerHasNextPage = true;
    var ledgerInitialized = false;

    try {
      balance = await _billingRepository.fetchBalance(accessToken: accessToken);
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when fetching billing balance',
        tag: 'BillingApi',
        error: error,
        stackTrace: stackTrace,
      );
      hasBalanceError = true;
    }

    try {
      final ledger = await _billingRepository.fetchLedger(
        accessToken: accessToken,
        page: 1,
        pageSize: billingLedgerPageSize,
      );
      ledgerItems = ledger.items;
      ledgerNextPage = ledger.page + 1;
      ledgerHasNextPage = ledgerItems.length < ledger.total;
      ledgerInitialized = true;
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when fetching billing ledger first page',
        tag: 'BillingApi',
        error: error,
        stackTrace: stackTrace,
      );
      hasLedgerError = true;
      ledgerInitialized = true;
      ledgerHasNextPage = true;
      ledgerNextPage = 1;
    }

    if (!mounted) return;
    setState(() {
      _balance = balance;
      _ledgerItems = ledgerItems;
      _isBalanceLoading = false;
      _isLedgerLoading = false;
      _hasBalanceError = hasBalanceError;
      _hasLedgerError = hasLedgerError;
      _ledgerInitialized = ledgerInitialized;
      _ledgerNextPage = ledgerNextPage;
      _ledgerHasNextPage = ledgerHasNextPage;
    });
  }

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
          indent: 16,
          endIndent: 16,
        ),
      ),
    );
  }

  String _formatCredits(BuildContext context, double amount) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return formatBillingAmount(locale: locale, amount: amount);
  }

  String _formatCreditDelta(BuildContext context, double amount) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return formatBillingDeltaAmount(locale: locale, amount: amount);
  }

  String? _formatOccurredAt(BuildContext context, DateTime? dateTime) {
    if (dateTime == null) return null;
    final locale = Localizations.localeOf(context).toLanguageTag();
    return DateFormat('yyyy-MM-dd HH:mm', locale).format(dateTime.toLocal());
  }

  String _balanceStatusText(BuildContext context) {
    final l10n = context.l10n;
    if (_isBalanceLoading) return l10n.loading;
    if (_hasBalanceError) return l10n.billing_load_failed;
    return '';
  }

  Widget _buildStatusTile(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
      ),
    );
  }

  Widget _buildChangeTile(BuildContext context, BillingLedgerItem item) {
    final amount = item.displayValue;
    final positive = amount >= 0;
    final theme = Theme.of(context);
    final titleColor =
        theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onSurface;
    final amountColor = positive
        ? PurchaseButtonStyle.heavyLightColor
        : titleColor;
    final occurredAtText = _formatOccurredAt(context, item.occurredAt);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        item.displayText,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: occurredAtText == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                occurredAtText,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
            ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatCreditDelta(context, amount),
            style: theme.textTheme.titleSmall?.copyWith(
              color: amountColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            context.l10n.billing_credits_label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auditBilling = ref.watch(auditBillingProvider);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final balanceStatusText = _balanceStatusText(context);
    final balance = _isAuditMode ? auditBilling.balance : _balance;
    final ledgerItems = _isAuditMode ? auditBilling.ledgerItems : _ledgerItems;
    final recentChanges = ledgerItems.take(3).toList();
    final showBalanceValue =
        _isAuditMode || (!_isBalanceLoading && balance != null);
    final showLedgerLoading = _isAuditMode ? false : _isLedgerLoading;
    final showViewAllButton = !showLedgerLoading && recentChanges.isNotEmpty;
    final showLedgerError =
        !showLedgerLoading && recentChanges.isEmpty && _hasLedgerError;
    final recentChangeWidgets = showLedgerLoading
        ? [_buildStatusTile(context, l10n.loading)]
        : showLedgerError
        ? [_buildStatusTile(context, l10n.billing_load_failed)]
        : recentChanges.isNotEmpty
        ? recentChanges.map((item) => _buildChangeTile(context, item)).toList()
        : [_buildStatusTile(context, l10n.billing_recent_activity_empty)];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.billing_title)),
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    l10n.billing_available_credits,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  ),
                  if (showBalanceValue) ...[
                    const SizedBox(height: 12),
                    Text(
                      balance == null
                          ? '--'
                          : _formatCredits(context, balance.availableBalance),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (_isAuditMode) ...[
                    const SizedBox(height: 8),
                    Text(
                      auditBillingNoticeText,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                  if (balanceStatusText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      balanceStatusText,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                  if (Platform.isIOS) ...[
                    const SizedBox(height: 16),
                    IosBuyButton(onPurchaseSuccess: _loadData),
                  ] else if (Platform.isAndroid) ...[
                    const SizedBox(height: 16),
                    AndroidBuyButton(onPurchaseSuccess: _loadData),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.billing_recent_activity,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (showViewAllButton)
                  TextButton(
                    onPressed: () {
                      final args = BalanceBillsArgs(
                        initialItems: List<BillingLedgerItem>.unmodifiable(
                          ledgerItems,
                        ),
                        nextPage: _ledgerNextPage,
                        hasNextPage: _ledgerHasNextPage,
                        hasInitialized: _ledgerInitialized,
                      );
                      context.push(AppRoutes.balanceBills, extra: args);
                    },
                    style: TextButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 16,
                      ),
                      minimumSize: const Size(0, 32),
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                      overlayColor: Colors.transparent,
                      splashFactory: NoSplash.splashFactory,
                    ),
                    child: Text(
                      l10n.billing_view_all,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _sectionCard(context, children: recentChangeWidgets),
          ],
        ),
      ),
    );
  }
}
