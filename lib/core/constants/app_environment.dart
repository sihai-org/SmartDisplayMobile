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
    switch (stage.value) {
      case AppEnvironmentStage.preRelease:
        return 'http://192.168.2.201:8000';
      case AppEnvironmentStage.production:
        return 'http://192.168.2.201:8000';
    }
  }

  static void toggle() {
    stage.value = isPreRelease
        ? AppEnvironmentStage.production
        : AppEnvironmentStage.preRelease;
  }
}
