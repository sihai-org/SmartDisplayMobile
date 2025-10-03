import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppLifecycleStateNotifier extends StateNotifier<bool>
    with WidgetsBindingObserver {
  AppLifecycleStateNotifier() : super(true) {
    WidgetsBinding.instance.addObserver(this);
    // Initialize foreground based on current state if available
    final current = WidgetsBinding.instance.lifecycleState;
    state = current == null || current == AppLifecycleState.resumed;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    state = appState == AppLifecycleState.resumed;
  }

  // Keep class minimal; use default mixin implementations.

  @override
  // Some SDKs don't export AppExitResponse; omit override.

  @override
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async => false;

  @override
  // Some SDKs don't export PredictiveBackEvent; omit predictive back overrides.

  @override
  // see above

  @override
  // see above

  @override
  // see above

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final isForegroundProvider =
    StateNotifierProvider<AppLifecycleStateNotifier, bool>((ref) {
  final notifier = AppLifecycleStateNotifier();
  ref.onDispose(() => notifier.dispose());
  return notifier;
});
