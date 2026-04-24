import 'package:flutter/material.dart';

import '../../../core/theme/purchase_button_style.dart';
import 'purchase_ui_models.dart';

class PurchaseProductCard extends StatelessWidget {
  const PurchaseProductCard({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final PurchaseUiProductItem item;
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
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    children: _buildPriceSpans(
                      item.priceText,
                      baseStyle: priceBaseStyle,
                      numberStyle: priceNumberStyle,
                    ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (item.remark != null && item.remark!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    item.remark!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ]
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
