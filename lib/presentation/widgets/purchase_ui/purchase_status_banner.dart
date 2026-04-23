import 'package:flutter/material.dart';

class PurchaseStatusBanner extends StatelessWidget {
  const PurchaseStatusBanner({
    super.key,
    required this.text,
    this.leading,
    this.backgroundColor,
    this.showProgressIndicator = false,
  });

  final String text;
  final Widget? leading;
  final Color? backgroundColor;
  final bool showProgressIndicator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget? resolvedLeading = leading;
    if (resolvedLeading == null && showProgressIndicator) {
      resolvedLeading = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            theme.colorScheme.onSurface,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (resolvedLeading != null) ...[
            resolvedLeading,
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
