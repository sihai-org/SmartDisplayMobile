import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/billing_repository.dart';

const String auditBillingNoticeText =
    'App Review mode: credits shown here are local only and are not synced to the server.';

class AuditBillingState {
  const AuditBillingState({
    this.availableBalance = 0,
    this.ledgerItems = const [],
    this.processedPurchaseKeys = const {},
  });

  final double availableBalance;
  final List<BillingLedgerItem> ledgerItems;
  final Set<String> processedPurchaseKeys;

  BillingBalanceData get balance => BillingBalanceData(
    availableBalance: availableBalance,
    totalConsumed: 0,
    totalExpired: 0,
  );

  AuditBillingState copyWith({
    double? availableBalance,
    List<BillingLedgerItem>? ledgerItems,
    Set<String>? processedPurchaseKeys,
  }) {
    return AuditBillingState(
      availableBalance: availableBalance ?? this.availableBalance,
      ledgerItems: ledgerItems ?? this.ledgerItems,
      processedPurchaseKeys:
          processedPurchaseKeys ?? this.processedPurchaseKeys,
    );
  }
}

class AuditBillingNotifier extends StateNotifier<AuditBillingState> {
  AuditBillingNotifier() : super(const AuditBillingState());

  void reset() {
    state = const AuditBillingState();
  }

  bool hasProcessedPurchase(String purchaseKey) {
    return state.processedPurchaseKeys.contains(purchaseKey);
  }

  void recordReviewPurchase({
    required String purchaseKey,
    required String productName,
    required double credits,
    DateTime? occurredAt,
  }) {
    if (credits <= 0 || hasProcessedPurchase(purchaseKey)) {
      return;
    }

    final nextBalance = state.availableBalance + credits;
    final entry = BillingLedgerItem(
      displayText: 'App Review credit: $productName (local only)',
      amount: credits,
      totalCredit: nextBalance,
      occurredAt: occurredAt ?? DateTime.now(),
    );

    state = state.copyWith(
      availableBalance: nextBalance,
      ledgerItems: [entry, ...state.ledgerItems],
      processedPurchaseKeys: {...state.processedPurchaseKeys, purchaseKey},
    );
  }
}

final auditBillingProvider =
    StateNotifierProvider<AuditBillingNotifier, AuditBillingState>((ref) {
      return AuditBillingNotifier();
    });
