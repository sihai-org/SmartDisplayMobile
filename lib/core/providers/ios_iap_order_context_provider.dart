import 'package:flutter_riverpod/flutter_riverpod.dart';

class IosIapOrderContext {
  const IosIapOrderContext({
    required this.packageCode,
    required this.productId,
    this.orderId,
  });

  final String packageCode;
  final String productId;
  final String? orderId;
}

class IosIapOrderContextNotifier extends StateNotifier<IosIapOrderContext?> {
  IosIapOrderContextNotifier() : super(null);

  void setContext({
    required String packageCode,
    required String productId,
    String? orderId,
  }) {
    state = IosIapOrderContext(
      packageCode: packageCode,
      productId: productId,
      orderId: orderId,
    );
  }

  void clear() {
    state = null;
  }
}

final iosIapOrderContextProvider =
    StateNotifierProvider<IosIapOrderContextNotifier, IosIapOrderContext?>(
      (ref) => IosIapOrderContextNotifier(),
    );
