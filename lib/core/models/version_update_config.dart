/// Remote config for app force-update (Supabase / mock).
class VersionUpdateConfig {
  const VersionUpdateConfig({
    required this.latestVersionName,
    required this.latestVersionCode,
    required this.needUpdate,
    required this.forceUpdate,
    required this.storeUrlIos,
    required this.storeUrlAndroid,
    required this.storeUrlAndroidWeb,
    required this.storeUrl,
    this.fallbackDownloadUrl,
  });

  // 服务端数据
  final String latestVersionName;
  final int latestVersionCode;
  final bool needUpdate;
  final bool forceUpdate;
  final String storeUrlIos;
  final String storeUrlAndroid;
  final String storeUrlAndroidWeb;

  // 客户端额外数据
  final String storeUrl;
  final String? fallbackDownloadUrl;
}

class ForceUpdatePayload {
  final String storeUrl;
  final String? fallbackDownloadUrl;

  const ForceUpdatePayload({
    required this.storeUrl,
    this.fallbackDownloadUrl,
  });
}
