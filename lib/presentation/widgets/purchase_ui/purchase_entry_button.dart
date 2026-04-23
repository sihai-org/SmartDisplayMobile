import 'package:flutter/material.dart';

import '../../../core/theme/purchase_button_style.dart';

class PurchaseEntryButton extends StatelessWidget {
  const PurchaseEntryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: PurchaseButtonStyle.invertedFilledButtonStyle(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          shape: const StadiumBorder(),
        ),
        child: Text(label),
      ),
    );
  }
}
