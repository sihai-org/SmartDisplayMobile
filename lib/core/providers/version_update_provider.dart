import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_display_mobile/core/models/version_update_config.dart';
import 'package:smart_display_mobile/data/repositories/version_update_repository.dart';

final versionUpdateRepositoryProvider = Provider<VersionUpdateRepository>((ref) {
  return SupabaseVersionUpdateRepository();
});

/// One-shot check: current app version vs remote config. Cached per app session.
final versionUpdateCheckProvider = FutureProvider<VersionUpdateConfig?>((ref) async {
  final repo = ref.read(versionUpdateRepositoryProvider);
  try {
    final config = await repo.getVersionUpdateConfig();
    return config;
  } catch (_) {
    return null;
  }
});
