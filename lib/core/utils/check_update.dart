import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../router/app_router.dart';
import '../models/version_update_config.dart';
import '../providers/version_update_provider.dart';

bool _checkUpdateInFlight = false;
bool _forceUpdateShown = false;

// 返回本次进入强制更新
Future<bool> checkUpdateOnce(WidgetRef ref) async {
  if (_checkUpdateInFlight) return false;
  _checkUpdateInFlight = true;

  try {
    ref.invalidate(versionUpdateCheckProvider);

    // 兜底超时：10秒
    final result = await ref
        .read(versionUpdateCheckProvider.future)
        .timeout(const Duration(seconds: 10));

    final currentPath =
        appRouter.routeInformationProvider.value.uri.path;

    final shouldForceUpdate =
        result?.forceUpdate == true &&
            (result?.storeUrl?.isNotEmpty ?? false);

    if (shouldForceUpdate) {
      if (!_forceUpdateShown && currentPath != AppRoutes.forceUpdate) {
        _forceUpdateShown = true;
        Future.microtask(() {
          appRouter.go(
            AppRoutes.forceUpdate,
            extra: ForceUpdatePayload(
              storeUrl: result!.storeUrl!,
              fallbackDownloadUrl: result.fallbackDownloadUrl,
            ),
          );
        });
        return true;
      }
    } else {
      _forceUpdateShown = false;
      if (currentPath == AppRoutes.forceUpdate) {
        final loggedIn =
            Supabase.instance.client.auth.currentSession != null;
        Future.microtask(() {
          appRouter.go(loggedIn ? AppRoutes.home : AppRoutes.login);
        });
      }
    }
  } on TimeoutException {
    // timeout -> 放行，不拦启动/不打断前台
  } catch (_) {
    // swallow
  } finally {
    _checkUpdateInFlight = false;
  }
  return false;
}
