import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/providers/android_iap_provider.dart';
import '../../core/theme/purchase_button_style.dart';
import 'android_iap_sheet.dart';

class AndroidBuyButton extends ConsumerStatefulWidget {
  const AndroidBuyButton({super.key, this.onPurchaseSuccess});

  final Future<void> Function()? onPurchaseSuccess;

  @override
  ConsumerState<AndroidBuyButton> createState() => _AndroidBuyButtonState();
}

class _AndroidBuyButtonState extends ConsumerState<AndroidBuyButton> {
  bool _isPurchaseSheetVisible = false;

  Future<void> _openAndroidIapSheet() async {
    unawaited(ref.read(androidIapProvider.notifier).loadProductCatalog());
    setState(() {
      _isPurchaseSheetVisible = true;
    });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => const AndroidIapSheet(),
    );

    if (!mounted) return;
    setState(() {
      _isPurchaseSheetVisible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AndroidIapState>(androidIapProvider, (previous, next) {
      if (previous?.successTick != next.successTick && next.successTick > 0) {
        if (_isPurchaseSheetVisible && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        unawaited(widget.onPurchaseSuccess?.call());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.billing_purchase_success)),
        );
      }
    });

    final purchaseState = ref.watch(androidIapProvider);
    return Center(
      child: FilledButton(
        onPressed: purchaseState.isBusy ? null : _openAndroidIapSheet,
        style: PurchaseButtonStyle.invertedFilledButtonStyle(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
          shape: const StadiumBorder(),
        ),
        child: Text(context.l10n.billing_buy_credits),
      ),
    );
  }
}
