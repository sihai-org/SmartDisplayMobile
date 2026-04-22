import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/providers/billing_purchase_provider.dart';
import '../../core/utils/billing_amount_formatter.dart';

class BillingPurchaseSheet extends ConsumerWidget {
  const BillingPurchaseSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(billingPurchaseProvider);
    final notifier = ref.read(billingPurchaseProvider.notifier);
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);

    final statusText = switch (state.stage) {
      BillingPurchaseStage.loadingCatalog => l10n.billing_purchase_loading,
      BillingPurchaseStage.creatingOrder ||
      BillingPurchaseStage.purchasing => l10n.billing_purchase_processing,
      BillingPurchaseStage.verifying => l10n.billing_purchase_verifying,
      _ => null,
    };

    final errorText = switch (state.failureKind) {
      BillingPurchaseFailureKind.unavailable =>
        l10n.billing_purchase_unavailable,
      BillingPurchaseFailureKind.cancelled => l10n.billing_purchase_cancelled,
      BillingPurchaseFailureKind.generic => l10n.billing_purchase_failed,
      null => null,
    };

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.billing_purchase_sheet_title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (statusText != null) ...[
              const SizedBox(height: 12),
              _InfoBanner(
                icon: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                text: statusText,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ],
            if (errorText != null) ...[
              const SizedBox(height: 12),
              _InfoBanner(
                icon: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                  size: 20,
                ),
                text: errorText,
                backgroundColor: theme.colorScheme.errorContainer.withValues(
                  alpha: 0.6,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (state.stage == BillingPurchaseStage.loadingCatalog &&
                state.products.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.products.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    l10n.billing_products_empty,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: state.products.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final option = state.products[index];
                    final isActive =
                        state.activeSession?.productId == option.productId &&
                        state.isBusy;
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: state.isBusy
                          ? null
                          : () => notifier.beginPurchase(option),
                      child: Ink(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.dividerColor,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    option.displayName,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${formatBillingAmount(locale: locale, amount: option.creditAmount)} ${l10n.billing_credits_label}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (option.description != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      option.description!,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: Colors.grey[600]),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  option.priceText,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FilledButton(
                                  onPressed: state.isBusy
                                      ? null
                                      : () => notifier.beginPurchase(option),
                                  child: Text(l10n.billing_buy_credits),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: state.stage == BillingPurchaseStage.loadingCatalog
                    ? null
                    : notifier.loadCatalog,
                child: Text(l10n.billing_purchase_retry),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.text,
    required this.backgroundColor,
  });

  final Widget icon;
  final String text;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
