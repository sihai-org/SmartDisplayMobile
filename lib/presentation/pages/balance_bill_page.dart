import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/log/app_log.dart';
import '../../core/utils/billing_amount_formatter.dart';
import '../../data/repositories/billing_repository.dart';

class BalanceBillsArgs {
  const BalanceBillsArgs({
    this.initialItems = const [],
    this.nextPage = 1,
    this.hasNextPage = true,
    this.hasInitialized = false,
  });

  final List<BillingLedgerItem> initialItems;
  final int nextPage;
  final bool hasNextPage;
  final bool hasInitialized;
}

class BalanceBillPage extends StatefulWidget {
  const BalanceBillPage({super.key, this.args});

  final BalanceBillsArgs? args;

  @override
  State<BalanceBillPage> createState() => _BalanceBillPageState();
}

class _BalanceBillPageState extends State<BalanceBillPage> {
  final BillingRepository _billingRepository = BillingRepository();
  final ScrollController _scrollController = ScrollController();

  late List<BillingLedgerItem> _items;
  late int _nextPage;
  late bool _hasNextPage;
  late bool _hasInitialized;

  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    final args = widget.args;
    _items = List<BillingLedgerItem>.from(args?.initialItems ?? const []);
    _nextPage = args?.nextPage ?? 1;
    _hasNextPage = args?.hasNextPage ?? true;
    _hasInitialized = args?.hasInitialized ?? false;
    _scrollController.addListener(_onScroll);

    if (!_hasInitialized) {
      _loadFirstPage();
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    if (_isLoading) return;
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _nextPage = 1;
        _hasNextPage = true;
        _hasInitialized = true;
        _hasError = true;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _items = const [];
      _nextPage = 1;
      _hasNextPage = true;
      _hasError = false;
      _isLoading = true;
    });

    try {
      final ledger = await _billingRepository.fetchLedger(
        accessToken: accessToken,
        page: 1,
        pageSize: billingLedgerPageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = ledger.items;
        _nextPage = ledger.page + 1;
        _hasNextPage = _items.length < ledger.total;
        _hasInitialized = true;
        _hasError = false;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when fetching billing ledger first page',
        tag: 'BillingApi',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _items = const [];
        _nextPage = 1;
        _hasNextPage = true;
        _hasInitialized = true;
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasNextPage) return;
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      if (!mounted) return;
      setState(() {
        _hasError = _items.isEmpty;
      });
      return;
    }

    setState(() {
      _hasError = false;
      _isLoading = true;
    });

    try {
      final ledger = await _billingRepository.fetchLedger(
        accessToken: accessToken,
        page: _nextPage,
        pageSize: billingLedgerPageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...ledger.items];
        _nextPage = ledger.page + 1;
        _hasNextPage = _items.length < ledger.total;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      AppLog.instance.error(
        'Unexpected error when loading more billing ledger items: page=$_nextPage, current_items=${_items.length}',
        tag: 'BillingApi',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _hasError = _items.isEmpty;
        _isLoading = false;
      });
      Fluttertoast.showToast(msg: context.l10n.billing_load_failed);
    }
  }

  void _onScroll() {
    if (_isLoading || !_hasNextPage) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMore();
    }
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
          indent: MediaQuery.of(context).size.width / 8,
        ),
      ),
    );
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

  String _statusText(BuildContext context) {
    final l10n = context.l10n;
    if (_isLoading && _items.isEmpty) return l10n.loading;
    if (_hasError && _items.isEmpty) return l10n.billing_load_failed;
    return l10n.billing_recent_activity_empty;
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
    final amountColor = positive ? Colors.green.shade700 : Colors.red.shade400;
    final iconColor = positive ? Colors.green.shade100 : Colors.red.shade100;
    final iconData = positive ? Icons.arrow_upward : Icons.arrow_downward;
    final occurredAtText = _formatOccurredAt(context, item.occurredAt);

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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
    final l10n = context.l10n;
    final changeWidgets = _items.isNotEmpty
        ? _items.map((item) => _buildChangeTile(context, item)).toList()
        : [_buildStatusTile(context, _statusText(context))];

    if (_isLoading && _items.isNotEmpty) {
      changeWidgets.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.billing_transactions_title)),
      body: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        removeBottom: true,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [_sectionCard(context, children: changeWidgets)],
        ),
      ),
    );
  }
}
