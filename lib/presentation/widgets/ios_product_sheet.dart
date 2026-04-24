import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/utils/billing_amount_formatter.dart';
import '../../data/repositories/ios_iap_repository.dart';
import 'purchase_ui/purchase_error_block.dart';
import 'purchase_ui/purchase_primary_action.dart';
import 'purchase_ui/purchase_product_selector.dart';
import 'purchase_ui/purchase_sheet.dart';
import 'purchase_ui/purchase_status_banner.dart';
import 'purchase_ui/purchase_ui_models.dart';

enum IosPurchaseStage {
  idle,
  creatingOrder,
  purchasing,
  awaitingResult,
  verifying,
  failure,
}

enum IosPurchaseFailureKind {
  signInRequired,
  storeUnavailable,
  productNotFound,
  cancelled,
  deliveryFailed,
  generic,
}

Future<List<AppleIapProductData>> _noopIosProductReload() async => const [];

Future<void> _noopIosProductPurchase(AppleIapProductData product) async {}

class IosPurchaseSheetState {
  const IosPurchaseSheetState({
    this.stage = IosPurchaseStage.idle,
    this.activeProductId,
    this.failureKind,
  });

  final IosPurchaseStage stage;
  final String? activeProductId;
  final IosPurchaseFailureKind? failureKind;

  bool get isBusy =>
      stage == IosPurchaseStage.creatingOrder ||
      stage == IosPurchaseStage.purchasing ||
      stage == IosPurchaseStage.awaitingResult ||
      stage == IosPurchaseStage.verifying;

  IosPurchaseSheetState copyWith({
    IosPurchaseStage? stage,
    String? activeProductId,
    bool clearActiveProduct = false,
    IosPurchaseFailureKind? failureKind,
    bool clearFailure = false,
  }) {
    return IosPurchaseSheetState(
      stage: stage ?? this.stage,
      activeProductId: clearActiveProduct
          ? null
          : (activeProductId ?? this.activeProductId),
      failureKind: clearFailure ? null : (failureKind ?? this.failureKind),
    );
  }
}

class IosProductSheet extends StatefulWidget {
  const IosProductSheet({
    super.key,
    this.initialProducts = const [],
    this.loadOnOpen = false,
    this.onReload = _noopIosProductReload,
    this.onPurchase = _noopIosProductPurchase,
    this.purchaseStateListenable = const _FixedValueListenable(
      IosPurchaseSheetState(),
    ),
  });

  final List<AppleIapProductData> initialProducts;
  final bool loadOnOpen;
  final Future<List<AppleIapProductData>> Function() onReload;
  final Future<void> Function(AppleIapProductData product) onPurchase;
  final ValueListenable<IosPurchaseSheetState> purchaseStateListenable;

  @override
  State<IosProductSheet> createState() => _IosProductSheetState();
}

class _IosProductSheetState extends State<IosProductSheet> {
  late List<AppleIapProductData> _products;
  bool _isReloading = false;
  bool _hasError = false;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _products = List<AppleIapProductData>.unmodifiable(widget.initialProducts);
    if (widget.loadOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_handleReload());
      });
    }
  }

  Future<void> _handleReload() async {
    setState(() {
      _isReloading = true;
      _hasError = false;
    });

    try {
      final products = await widget.onReload();
      if (!mounted) return;
      setState(() {
        _products = List<AppleIapProductData>.unmodifiable(products);
        _isReloading = false;
        _hasError = false;
        _selectedIndex = _products.isEmpty
            ? 0
            : _selectedIndex.clamp(0, _products.length - 1);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _products = const [];
        _isReloading = false;
        _hasError = true;
        _selectedIndex = 0;
      });
    }
  }

  void _syncSelectedProduct(IosPurchaseSheetState purchaseState) {
    if (_products.isEmpty) {
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

    var targetIndex = _selectedIndex.clamp(0, _products.length - 1);
    final activeProductId = purchaseState.activeProductId;
    if (purchaseState.isBusy && activeProductId != null) {
      final activeIndex = _products.indexWhere(
        (item) => item.productId == activeProductId,
      );
      if (activeIndex >= 0) {
        targetIndex = activeIndex;
      }
    }

    if (targetIndex == _selectedIndex) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedIndex = targetIndex;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<IosPurchaseSheetState>(
      valueListenable: widget.purchaseStateListenable,
      builder: (context, purchaseState, _) {
        final l10n = context.l10n;
        final locale = Localizations.localeOf(context).toLanguageTag();
        final theme = Theme.of(context);
        _syncSelectedProduct(purchaseState);
        final selectedIndex = _products.isEmpty
            ? 0
            : _selectedIndex.clamp(0, _products.length - 1);
        final selectedProduct = _products.isEmpty
            ? null
            : _products[selectedIndex];
        final selectorItems = _products
            .map(
              (product) => PurchaseUiProductItem(
                id: product.productId,
                title: _productTitle(product, l10n.billing_credits_label),
                priceText: _priceText(product),
              ),
            )
            .toList(growable: false);
        final buyButtonText = selectedProduct == null
            ? l10n.billing_buy_credits
            : '${_priceText(selectedProduct)} ${l10n.billing_buy_credits}';
        final statusText = switch (purchaseState.stage) {
          IosPurchaseStage.creatingOrder ||
          IosPurchaseStage.purchasing => l10n.billing_ios_purchase_processing,
          IosPurchaseStage.awaitingResult =>
            l10n.billing_ios_purchase_awaiting_result,
          IosPurchaseStage.verifying => l10n.billing_ios_purchase_verifying,
          _ => null,
        };
        final errorText = switch (purchaseState.failureKind) {
          IosPurchaseFailureKind.signInRequired =>
            l10n.billing_purchase_sign_in_first,
          IosPurchaseFailureKind.storeUnavailable =>
            l10n.billing_ios_purchase_store_unavailable,
          IosPurchaseFailureKind.productNotFound =>
            l10n.billing_ios_purchase_product_not_found,
          IosPurchaseFailureKind.cancelled => l10n.billing_purchase_cancelled,
          IosPurchaseFailureKind.deliveryFailed =>
            l10n.billing_purchase_delivery_failed,
          IosPurchaseFailureKind.generic => l10n.billing_purchase_failed,
          null => _hasError ? l10n.billing_load_failed : null,
        };

        return PurchaseSheet(
          title: l10n.billing_purchase_sheet_title,
          trailing: TextButton.icon(
            onPressed: (_isReloading || purchaseState.isBusy)
                ? null
                : _handleReload,
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
              : PurchaseStatusBanner(
                  text: statusText,
                  showProgressIndicator: true,
                ),
          errorBanner: errorText == null
              ? null
              : PurchaseErrorBlock(
                  message: errorText,
                  actionLabel:
                      _hasError &&
                          purchaseState.failureKind == null &&
                          !_isReloading &&
                          !purchaseState.isBusy
                      ? l10n.billing_purchase_retry
                      : null,
                  onAction:
                      _hasError &&
                          purchaseState.failureKind == null &&
                          !_isReloading &&
                          !purchaseState.isBusy
                      ? _handleReload
                      : null,
                ),
          bottomAction: _products.isEmpty
              ? null
              : PurchasePrimaryAction(
                  label: buyButtonText,
                  onPressed:
                      _isReloading ||
                          purchaseState.isBusy ||
                          selectedProduct == null
                      ? null
                      : () {
                          unawaited(widget.onPurchase(selectedProduct));
                        },
                ),
          child: _isReloading && _products.isEmpty
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
              : _products.isEmpty
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
                  onSelect: (index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  isBusy: _isReloading || purchaseState.isBusy,
                  showLoadingOverlay: _isReloading && _products.isNotEmpty,
                ),
        );
      },
    );
  }

  static String _productTitle(
    AppleIapProductData product,
    String creditsLabel,
  ) {
    final displayName = product.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    return '${_creditText(product.creditAmount)} $creditsLabel';
  }

  static String _priceText(AppleIapProductData product) {
    final displayPrice = product.displayPrice?.trim();
    if (displayPrice != null && displayPrice.isNotEmpty) {
      return displayPrice;
    }
    if (product.amount != null && (product.currency?.isNotEmpty ?? false)) {
      return '${product.currency} ${product.amount}';
    }
    return _creditText(product.creditAmount);
  }

  static String _creditText(double creditAmount) {
    return creditAmount % 1 == 0
        ? creditAmount.toStringAsFixed(0)
        : creditAmount.toStringAsFixed(2);
  }
}

class _FixedValueListenable<T> implements ValueListenable<T> {
  const _FixedValueListenable(this.value);

  @override
  final T value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
