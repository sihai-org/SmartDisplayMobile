import 'package:flutter/material.dart';

import 'purchase_product_card.dart';
import 'purchase_ui_models.dart';

class PurchaseProductSelector extends StatefulWidget {
  const PurchaseProductSelector({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    this.isBusy = false,
    this.showLoadingOverlay = false,
  });

  final List<PurchaseUiProductItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool isBusy;
  final bool showLoadingOverlay;

  @override
  State<PurchaseProductSelector> createState() =>
      _PurchaseProductSelectorState();
}

class _PurchaseProductSelectorState extends State<PurchaseProductSelector> {
  static const double _cardWidth = 158;
  static const double _cardHeight = 208;
  static const double _cardHorizontalPadding = 6;

  late PageController _pageController;
  double _pageViewportFraction = 1;
  int _currentPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentPageIndex = widget.selectedIndex;
    _pageController = PageController(
      initialPage: widget.selectedIndex,
      viewportFraction: _pageViewportFraction,
    );
  }

  @override
  void didUpdateWidget(covariant PurchaseProductSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.isEmpty) {
      if (_currentPageIndex != 0) {
        setState(() {
          _currentPageIndex = 0;
        });
      }
      return;
    }

    final clampedIndex = widget.selectedIndex.clamp(0, widget.items.length - 1);
    if (clampedIndex == _currentPageIndex) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.animateToPage(
        clampedIndex,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      setState(() {
        _currentPageIndex = clampedIndex;
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final selectedIndex = widget.selectedIndex.clamp(
      0,
      widget.items.length - 1,
    );

    return AbsorbPointer(
      absorbing: widget.isBusy || widget.showLoadingOverlay,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _syncPageViewportFraction(constraints.maxWidth);
          return Stack(
            children: [
              SizedBox(
                height: _cardHeight,
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.items.length,
                  onPageChanged: (index) {
                    if (_currentPageIndex == index) return;
                    setState(() {
                      _currentPageIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    final isSelected = index == selectedIndex;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _cardHorizontalPadding,
                      ),
                      child: Center(
                        child: SizedBox(
                          width: _cardWidth,
                          height: _cardHeight,
                          child: PurchaseProductCard(
                            item: item,
                            isSelected: isSelected,
                            onTap: () {
                              widget.onSelect(index);
                              if (index != _currentPageIndex) {
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
              if (widget.showLoadingOverlay)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.72),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
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
    );
  }
}
