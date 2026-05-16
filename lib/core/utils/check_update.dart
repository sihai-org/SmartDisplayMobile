import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/l10n_extensions.dart';
import '../log/app_log.dart';
import '../router/app_router.dart';
import '../models/version_update_config.dart';
import '../network/http_timeouts.dart';
import '../providers/version_update_provider.dart';
import '../../presentation/widgets/update_available_dialog.dart';

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
        .timeout(HttpTimeouts.business);

    final currentPath = appRouter.routeInformationProvider.value.uri.path;

    final shouldForceUpdate =
        result?.forceUpdate == true && (result?.storeUrl?.isNotEmpty ?? false);

    if (shouldForceUpdate) {
      if (!_forceUpdateShown && currentPath != AppRoutes.forceUpdate) {
        _forceUpdateShown = true;
        Future.microtask(() {
          appRouter.go(
            AppRoutes.forceUpdate,
            extra: ForceUpdatePayload(
              storeUrl: result!.storeUrl!,
              fallbackDownloadUrl: result.fallbackDownloadUrl,
              releaseNotes: result.releaseNotes,
            ),
          );
        });
        return true;
      }
    } else {
      _forceUpdateShown = false;
      if (currentPath == AppRoutes.forceUpdate) {
        final loggedIn = Supabase.instance.client.auth.currentSession != null;
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

/// 用户主动检查更新：所有分支都给反馈（强更跳转 / 弹普通更新对话框 / toast 已是最新 / toast 失败）。
/// 不复用 [_checkUpdateInFlight] 锁：那把锁是 [checkUpdateOnce] 防重入用的，
/// 这里被它挡住会导致 trailing 转圈闪一下就消失、用户没反馈。UI 层 _checking 已防连点。
Future<void> checkUpdateManually(WidgetRef ref, BuildContext context) async {
  final l10n = context.l10n;
  try {
    ref.invalidate(versionUpdateCheckProvider);

    final result = await ref
        .read(versionUpdateCheckProvider.future)
        .timeout(HttpTimeouts.business);

    if (result == null) {
      Fluttertoast.showToast(msg: l10n.check_update_failed_retry);
      return;
    }

    final hasStoreUrl = result.storeUrl.isNotEmpty;
    if (result.forceUpdate && hasStoreUrl) {
      _forceUpdateShown = true;
      Future.microtask(() {
        appRouter.go(
          AppRoutes.forceUpdate,
          extra: ForceUpdatePayload(
            storeUrl: result.storeUrl,
            fallbackDownloadUrl: result.fallbackDownloadUrl,
            releaseNotes: result.releaseNotes,
          ),
        );
      });
      return;
    }

    if (result.needUpdate && hasStoreUrl) {
      if (!context.mounted) return;
      await showUpdateAvailableDialog(
        context,
        version: result.latestVersionName,
        storeUrl: result.storeUrl,
        releaseNotes: result.releaseNotes,
        fallbackDownloadUrl: result.fallbackDownloadUrl,
      );
      return;
    }

    Fluttertoast.showToast(msg: l10n.already_latest_version);
  } on TimeoutException {
    Fluttertoast.showToast(msg: l10n.check_update_failed_retry);
  } catch (e, st) {
    AppLog.instance.warning(
      'Manual update check failed',
      tag: 'CheckUpdate',
      error: e,
      stackTrace: st,
    );
    Fluttertoast.showToast(msg: l10n.check_update_failed_retry);
  }
}
