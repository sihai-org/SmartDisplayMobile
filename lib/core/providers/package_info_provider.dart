import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../log/app_log.dart';

final packageInfoProvider = FutureProvider<PackageInfo?>((ref) async {
  try {
    return await PackageInfo.fromPlatform();
  } catch (error, stackTrace) {
    AppLog.instance.warning(
      '[package_info_provider] failed to load package info',
      tag: 'AppInfo',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
});
