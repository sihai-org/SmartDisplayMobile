import 'package:flutter/foundation.dart';

enum AppEnvironmentStage {
  production,
  preRelease,
}

class AppEnvironment {
  static final ValueNotifier<AppEnvironmentStage> stage =
      ValueNotifier(AppEnvironmentStage.production);

  static bool get isPreRelease => stage.value == AppEnvironmentStage.preRelease;

  static String get label => isPreRelease ? '预发' : '线上';

  static void toggle() {
    stage.value = isPreRelease
        ? AppEnvironmentStage.production
        : AppEnvironmentStage.preRelease;
  }
}
