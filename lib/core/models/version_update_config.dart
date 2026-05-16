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
    this.releaseNotes,
  });

  // 服务端数据
  final String latestVersionName;
  final int latestVersionCode;
  final bool needUpdate;
  final bool forceUpdate;
  final String storeUrlIos;
  final String storeUrlAndroid;
  final String storeUrlAndroidWeb;
  final String? releaseNotes;

  // 客户端额外数据
  final String storeUrl;
  final String? fallbackDownloadUrl;
}

class ForceUpdatePayload {
  final String storeUrl;
  final String? fallbackDownloadUrl;
  final String? releaseNotes;

  const ForceUpdatePayload({
    required this.storeUrl,
    this.fallbackDownloadUrl,
    this.releaseNotes,
  });
}
