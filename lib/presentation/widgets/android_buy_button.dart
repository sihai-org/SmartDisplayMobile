import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/providers/android_iap_provider.dart';
import 'android_iap_sheet.dart';
import 'purchase_ui/purchase_entry_button.dart';

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
        Fluttertoast.showToast(msg: context.l10n.billing_purchase_success);
      }
    });

    final purchaseState = ref.watch(androidIapProvider);
    return Center(
      child: PurchaseEntryButton(
        label: context.l10n.billing_buy_credits,
        onPressed: purchaseState.isBusy ? null : _openAndroidIapSheet,
      ),
    );
  }
}
