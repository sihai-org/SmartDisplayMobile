import 'package:flutter/material.dart';

import '../../../core/theme/purchase_button_style.dart';

class PurchasePrimaryAction extends StatelessWidget {
  const PurchasePrimaryAction({
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
      width: double.infinity,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: PurchaseButtonStyle.filledButtonStyle(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        PurchaseButtonStyle.lightColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(label),
                ],
              )
            : Text(label),
      ),
    );
  }
}
