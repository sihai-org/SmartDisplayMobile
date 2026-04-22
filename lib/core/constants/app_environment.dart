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

  // Unified API server URL entry point. Can be switched by stage later.
  static String get apiServerUrl {
    return 'https://billing-rtdn.haoyangz.com';
    switch (stage.value) {
      case AppEnvironmentStage.preRelease:
        return 'https://api.smartdisplay.vzngpt.com';
      case AppEnvironmentStage.production:
        return 'https://api.smartdisplay.vzngpt.com';
    }
  }

  static void toggle() {
    stage.value = isPreRelease
        ? AppEnvironmentStage.production
        : AppEnvironmentStage.preRelease;
  }
}
