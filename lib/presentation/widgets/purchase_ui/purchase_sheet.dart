import 'package:flutter/material.dart';

class PurchaseSheet extends StatelessWidget {
  const PurchaseSheet({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.statusBanner,
    this.errorBanner,
    this.bottomAction,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final Widget? statusBanner;
  final Widget? errorBanner;
  final Widget? bottomAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
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
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if (statusBanner != null) ...[
              const SizedBox(height: 12),
              statusBanner!,
            ],
            if (errorBanner != null) ...[
              const SizedBox(height: 12),
              errorBanner!,
            ],
            const SizedBox(height: 16),
            child,
            if (bottomAction != null) ...[
              const SizedBox(height: 18),
              bottomAction!,
            ],
          ],
        ),
      ),
    );
  }
}
