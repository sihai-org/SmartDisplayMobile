import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/providers/android_iap_provider.dart';
import '../../core/theme/purchase_button_style.dart';
import '../../core/utils/billing_amount_formatter.dart';

class AndroidIapSheet extends ConsumerStatefulWidget {
  const AndroidIapSheet({super.key});

  @override
  ConsumerState<AndroidIapSheet> createState() => _AndroidIapSheetState();
}

class _AndroidIapSheetState extends ConsumerState<AndroidIapSheet> {
  static const double _cardWidth = 140;
  static const double _cardHeight = 180;
  static const double _cardHorizontalPadding = 6;

  late PageController _pageController;
  double _pageViewportFraction = 1;
  int _currentPageIndex = 0;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: _pageViewportFraction);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _setSelectedIndex(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
    });
  }

  void _setCurrentPageIndex(int index) {
    if (_currentPageIndex == index) return;
    setState(() {
      _currentPageIndex = index;
    });
  }

  void _animateToPage(int index) {
    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _syncPageViewportFraction(double availableWidth) {
    final nextViewportFraction =
        ((_cardWidth + (_cardHorizontalPadding * 2)) / availableWidth).clamp(
          0.0,
          1.0,
        );
    if ((nextViewportFraction - _pageViewportFraction).abs() < 0.001) return;

    final previousController = _pageController;
    final initialPage = previousController.hasClients
        ? (previousController.page?.round() ?? _currentPageIndex)
        : _currentPageIndex;

    _pageViewportFraction = nextViewportFraction;
    _pageController = PageController(
      initialPage: initialPage,
      viewportFraction: _pageViewportFraction,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      previousController.dispose();
    });
  }

  void _syncSelectedProduct(AndroidIapState state) {
    if (state.products.isEmpty) {
      if (_selectedIndex != 0 || _currentPageIndex != 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _selectedIndex = 0;
            _currentPageIndex = 0;
          });
        });
      }
      return;
    }

    var targetIndex = _selectedIndex.clamp(0, state.products.length - 1);
    var targetPageIndex = _currentPageIndex.clamp(0, state.products.length - 1);
    final activeProductId = state.activeSession?.productId;
    if (state.isBusy && activeProductId != null) {
      final activeIndex = state.products.indexWhere(
        (item) => item.productId == activeProductId,
      );
      if (activeIndex >= 0) {
        targetIndex = activeIndex;
        targetPageIndex = activeIndex;
      }
    }

    if (targetIndex == _selectedIndex && targetPageIndex == _currentPageIndex) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedIndex = targetIndex;
        _currentPageIndex = targetPageIndex;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetPageIndex);
      }
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
    final currentPageIndex = state.products.isEmpty
        ? 0
        : _currentPageIndex.clamp(0, state.products.length - 1);
    final selectedIndex = state.products.isEmpty
        ? 0
        : _selectedIndex.clamp(0, state.products.length - 1);
    final selectedOption = state.products.isEmpty
        ? null
        : state.products[selectedIndex];
    final buyButtonText = selectedOption == null
        ? l10n.billing_buy_credits
        : '${selectedOption.priceText} ${l10n.billing_buy_credits}';

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.billing_purchase_sheet_title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
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
                  label: Text(
                    l10n.refresh,
                    style: const TextStyle(fontSize: 13),
                  ),
                )
              ],
            ),
            if (statusText != null) ...[
              const SizedBox(height: 12),
              _InfoBanner(
                icon: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                text: statusText,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ],
            if (errorText != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (state.stage == AndroidIapStage.loadingCatalog &&
                state.products.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.onSurface,
                    ),
                  ),
                ),
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
              AbsorbPointer(
                absorbing: showCatalogLoadingOverlay,
                child: AbsorbPointer(
                  absorbing: state.isBusy,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          _syncPageViewportFraction(constraints.maxWidth);
                          return Stack(
                            children: [
                              SizedBox(
                                height: _cardHeight,
                                child: PageView.builder(
                                  controller: _pageController,
                                  itemCount: state.products.length,
                                  onPageChanged: _setCurrentPageIndex,
                                  itemBuilder: (context, index) {
                                    final option = state.products[index];
                                    final isSelected = index == selectedIndex;
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: _cardHorizontalPadding,
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: _cardWidth,
                                          height: _cardHeight,
                                          child: _ProductCard(
                                            option: option,
                                            locale: locale,
                                            creditsLabel:
                                                l10n.billing_credits_label,
                                            isSelected: isSelected,
                                            onTap: () {
                                              _setSelectedIndex(index);
                                              if (index != currentPageIndex) {
                                                _animateToPage(index);
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              if (showCatalogLoadingOverlay)
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surface
                                          .withValues(alpha: 0.72),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              theme.colorScheme.onSurface,
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: selectedOption == null || state.isBusy
                              ? null
                              : () =>
                                    notifier.startPurchaseFlow(selectedOption),
                          style: PurchaseButtonStyle.filledButtonStyle(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(buyButtonText),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.option,
    required this.locale,
    required this.creditsLabel,
    required this.isSelected,
    required this.onTap,
  });

  final AndroidIapProductOption option;
  final String locale;
  final String creditsLabel;
  final bool isSelected;
  final VoidCallback onTap;

  static const Color _defaultBackgroundColor = Color(0xFFF3F4F6);
  static final RegExp _priceNumberPattern = RegExp(r'\d+(?:[.,]\d+)*');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceBaseStyle = theme.textTheme.titleLarge?.copyWith(
      fontSize: (theme.textTheme.titleLarge?.fontSize ?? 22) - 2,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.3,
      height: 1,
      color: PurchaseButtonStyle.darkColor,
    );
    final priceNumberStyle = priceBaseStyle?.copyWith(
      fontSize: (priceBaseStyle.fontSize ?? 22) + 16,
      height: 1,
      fontWeight: FontWeight.w800,
      color: PurchaseButtonStyle.darkColor,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isSelected
            ? PurchaseButtonStyle.lightColor
            : _defaultBackgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          hoverColor: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  option.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: PurchaseButtonStyle.darkColor,
                  ),
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    children: _buildPriceSpans(
                      option.priceText,
                      baseStyle: priceBaseStyle,
                      numberStyle: priceNumberStyle,
                    ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatBillingCreditAmount(locale: locale, amount: option.creditAmount)} $creditsLabel',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _buildPriceSpans(
    String priceText, {
    TextStyle? baseStyle,
    TextStyle? numberStyle,
  }) {
    final matches = _priceNumberPattern.allMatches(priceText).toList();
    if (matches.isEmpty) {
      return [TextSpan(text: priceText, style: baseStyle)];
    }

    final spans = <InlineSpan>[];
    var currentIndex = 0;
    for (final match in matches) {
      if (match.start > currentIndex) {
        final leadingText = priceText.substring(currentIndex, match.start);
        spans.add(TextSpan(text: leadingText.trimRight(), style: baseStyle));
        if (leadingText.trim().isNotEmpty) {
          spans.add(const WidgetSpan(child: SizedBox(width: 4)));
        }
      }
      spans.add(
        TextSpan(
          text: priceText.substring(match.start, match.end),
          style: numberStyle,
        ),
      );
      currentIndex = match.end;
    }

    if (currentIndex < priceText.length) {
      spans.add(
        TextSpan(text: priceText.substring(currentIndex), style: baseStyle),
      );
    }
    return spans;
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
