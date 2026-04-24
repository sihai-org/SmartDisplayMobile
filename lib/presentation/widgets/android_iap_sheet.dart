import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/providers/android_iap_provider.dart';
import '../../core/utils/billing_amount_formatter.dart';
import 'purchase_ui/purchase_error_block.dart';
import 'purchase_ui/purchase_primary_action.dart';
import 'purchase_ui/purchase_product_selector.dart';
import 'purchase_ui/purchase_sheet.dart';
import 'purchase_ui/purchase_status_banner.dart';
import 'purchase_ui/purchase_ui_models.dart';

class AndroidIapSheet extends ConsumerStatefulWidget {
  const AndroidIapSheet({super.key});

  @override
  ConsumerState<AndroidIapSheet> createState() => _AndroidIapSheetState();
}

class _AndroidIapSheetState extends ConsumerState<AndroidIapSheet> {
  int _selectedIndex = 0;

  void _setSelectedIndex(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
    });
  }

  void _syncSelectedProduct(AndroidIapState state) {
    if (state.products.isEmpty) {
      if (_selectedIndex != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _selectedIndex = 0;
          });
        });
      }
      return;
    }

    var targetIndex = _selectedIndex.clamp(0, state.products.length - 1);
    final activeProductId = state.activeSession?.productId;
    if (state.isBusy && activeProductId != null) {
      final activeIndex = state.products.indexWhere(
        (item) => item.productId == activeProductId,
      );
      if (activeIndex >= 0) {
        targetIndex = activeIndex;
      }
    }

    if (targetIndex == _selectedIndex) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedIndex = targetIndex;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final state = ref.watch(androidIapProvider);
    final notifier = ref.read(androidIapProvider.notifier);
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final theme = Theme.of(context);
    _syncSelectedProduct(state);
    final showCatalogLoadingOverlay =
        state.stage == AndroidIapStage.loadingCatalog &&
        state.products.isNotEmpty;

    final statusText = switch (state.stage) {
      AndroidIapStage.creatingOrder ||
      AndroidIapStage.purchasing => l10n.billing_purchase_processing,
      AndroidIapStage.awaitingPurchaseResult =>
        l10n.billing_purchase_awaiting_result,
      AndroidIapStage.verifying => l10n.billing_purchase_verifying,
      _ => null,
    };

    final errorText = switch (state.failureKind) {
      AndroidIapFailureKind.unavailable => l10n.billing_purchase_unavailable,
      AndroidIapFailureKind.cancelled => l10n.billing_purchase_cancelled,
      AndroidIapFailureKind.catalogLoadFailed => l10n.billing_load_failed,
      AndroidIapFailureKind.generic => l10n.billing_purchase_failed,
      null => null,
    };
    final selectedIndex = state.products.isEmpty
        ? 0
        : _selectedIndex.clamp(0, state.products.length - 1);
    final selectedOption = state.products.isEmpty
        ? null
        : state.products[selectedIndex];
    final buyButtonText = selectedOption == null
        ? l10n.billing_buy_credits
        : '${selectedOption.priceText} ${l10n.billing_buy_credits}';
    final selectorItems = state.products
        .map(
          (option) => PurchaseUiProductItem(
            id: option.productId,
            title: option.displayName,
            priceText: option.priceText,
          ),
        )
        .toList(growable: false);

    return PurchaseSheet(
      title: l10n.billing_purchase_sheet_title,
      trailing: TextButton.icon(
        onPressed: state.stage == AndroidIapStage.loadingCatalog
            ? null
            : notifier.loadProductCatalog,
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
        ),
        icon: const Icon(Icons.refresh, size: 16),
        label: Text(l10n.refresh, style: const TextStyle(fontSize: 13)),
      ),
      statusBanner: statusText == null
          ? null
          : PurchaseStatusBanner(text: statusText, showProgressIndicator: true),
      errorBanner: errorText == null
          ? null
          : PurchaseErrorBlock(message: errorText),
      bottomAction: state.products.isEmpty
          ? null
          : PurchasePrimaryAction(
              label: buyButtonText,
              isLoading: state.isBusy,
              onPressed: selectedOption == null || state.isBusy
                  ? null
                  : () => notifier.startPurchaseFlow(selectedOption),
            ),
      child:
          state.stage == AndroidIapStage.loadingCatalog &&
              state.products.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.onSurface,
                  ),
                ),
              ),
            )
          : state.products.isEmpty
          ? Padding(
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
          : PurchaseProductSelector(
              items: selectorItems,
              selectedIndex: selectedIndex,
              onSelect: _setSelectedIndex,
              isBusy: state.isBusy,
              showLoadingOverlay: showCatalogLoadingOverlay,
            ),
    );
  }
}
