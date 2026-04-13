import 'package:smart_display_mobile/core/models/version_update_config.dart';

import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/log/app_log.dart';

abstract class VersionUpdateRepository {
  Future<VersionUpdateConfig?> getVersionUpdateConfig(PackageInfo packageInfo);
}

class SupabaseVersionUpdateRepository implements VersionUpdateRepository {
  SupabaseVersionUpdateRepository();

  @override
  Future<VersionUpdateConfig?> getVersionUpdateConfig(
    PackageInfo packageInfo,
  ) async {
    try {
      // platform
      final platform = Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
          ? 'android'
          : null;
      // version_code（⚠️ 必须是纯整数）
      final versionCode = int.tryParse(packageInfo.buildNumber) ?? 0;
      // version_name
      final versionName = packageInfo.version;

      final response = await Supabase.instance.client.functions.invoke(
        'mobile_check_update?platform=$platform&version_code=$versionCode&version_name=$versionName',
        method: HttpMethod.get, // 一定要加
      );
      final respData = response.data;

      AppLog.instance.info(
        'mobile_check_update status=${response.status}, data=$respData',
      );

      if (response.status != 200) {
        final respMsg = _responseMessage(respData);
        throw respMsg == null || respMsg.isEmpty
            ? '服务异常（${response.status}）'
            : respMsg;
      }

      final data = respData['data'];
      final storeUrlIos = data['storeUrlIos'] ?? "";
      final storeUrlAndroid = data['storeUrlAndroid'] ?? "";
      final storeUrlAndroidWeb = data['storeUrlAndroidWeb'];
      final storeUrl = Platform.isIOS
          ? storeUrlIos
          : Platform.isAndroid
          ? storeUrlAndroid
          : "";
      final fallbackDownloadUrl = Platform.isAndroid ? storeUrlAndroidWeb : "";
      return VersionUpdateConfig(
        latestVersionName: data['latestVersionName'] ?? "0.0.0",
        latestVersionCode: data['latestVersionCode'] ?? 0,
        needUpdate: data['needUpdate'] ?? false,
        forceUpdate: data['forceUpdate'] ?? false,
        storeUrlIos: storeUrlIos,
        storeUrlAndroid: storeUrlAndroid,
        storeUrlAndroidWeb: storeUrlAndroidWeb,
        storeUrl: storeUrl,
        fallbackDownloadUrl: fallbackDownloadUrl,
      );
    } on FunctionException catch (error, stackTrace) {
      AppLog.instance.warning(
        '[mobile_check_update] status=${error.status}, details=${error.details}',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        'Unexpected error when getVersionUpdateConfig',
        tag: 'Supabase',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  String? _responseMessage(dynamic data) {
    if (data is Map && data['message'] != null) {
      return data['message']?.toString();
    }
    return data?.toString();
  }
}
