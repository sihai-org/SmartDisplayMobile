import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../router/app_router.dart';
import '../models/version_update_config.dart';
import '../providers/version_update_provider.dart';

bool _checkUpdateInFlight = false;

// 返回本次进入强制更新
Future<bool> checkUpdateOnce(WidgetRef ref) async {
  if (_checkUpdateInFlight) return false;
  _checkUpdateInFlight = true;

  try {
    ref.invalidate(versionUpdateCheckProvider);
    final result = await ref.read(versionUpdateCheckProvider.future);

    final currentPath =
        appRouter.routeInformationProvider.value.uri.path;

    final shouldForceUpdate =
        result?.forceUpdate == true &&
            (result?.storeUrl?.isNotEmpty ?? false);

    if (shouldForceUpdate) {
      if (currentPath != AppRoutes.forceUpdate) {
        appRouter.go(
          AppRoutes.forceUpdate,
          extra: ForceUpdatePayload(
            storeUrl: result!.storeUrl!,
            fallbackDownloadUrl: result.fallbackDownloadUrl,
          ),
        );
        return true;
      }
    } else {
      if (currentPath == AppRoutes.forceUpdate) {
        final loggedIn =
            Supabase.instance.client.auth.currentSession != null;
        appRouter.go(loggedIn ? AppRoutes.home : AppRoutes.login);
      }
    }
  } catch (_) {
    // swallow
  } finally {
    _checkUpdateInFlight = false;
  }
  return false;
}
