import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_display_mobile/core/models/version_update_config.dart';
import 'package:smart_display_mobile/data/repositories/version_update_repository.dart';

import 'locale_provider.dart';
import 'package_info_provider.dart';

final versionUpdateRepositoryProvider = Provider<VersionUpdateRepository>((
  ref,
) {
  return SupabaseVersionUpdateRepository();
});

String _resolveLang(Locale? locale) {
  final code = locale?.languageCode ??
      PlatformDispatcher.instance.locale.languageCode;
  return code == 'zh' ? 'zh' : 'en';
}

/// One-shot check: current app version vs remote config. Cached per app session.
final versionUpdateCheckProvider = FutureProvider<VersionUpdateConfig?>((
  ref,
) async {
  final repo = ref.read(versionUpdateRepositoryProvider);
  final packageInfo = await ref.read(packageInfoProvider.future);
  if (packageInfo == null) {
    return null;
  }
  final lang = _resolveLang(ref.read(localeProvider));
  try {
    final config = await repo.getVersionUpdateConfig(packageInfo, lang: lang);
    return config;
  } catch (_) {
    return null;
  }
});
