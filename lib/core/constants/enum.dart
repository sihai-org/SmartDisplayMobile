enum DeviceUpdateVersionResult { updating, latest, failed }

/// BLE 连接结果（区分成功 / 失败 / 竞态取消等场景）
enum BleConnectResult {
  success,
  alreadyConnected,
  cancelled,
  userMismatch,
  failed,
}

enum CheckBoundRes {
  isOwner,
  isBound,
  notBound,
}

enum ProvisionStatus {
  idle,
  provisioning,
  success,
  failure,
}

enum WallpaperType {
  defaultWallpaper('default'),
  custom('custom');

  final String value;

  const WallpaperType(this.value);

  static WallpaperType fromString(String? value) {
    return WallpaperType.values.firstWhere(
          (e) => e.value == value,
      orElse: () => WallpaperType.defaultWallpaper,
    );
  }
}

enum LayoutType {
  defaultLayout('default'),
  frame('frame');

  final String value;

  const LayoutType(this.value);

  static LayoutType fromString(String? value) {
    return LayoutType.values.firstWhere(
          (e) => e.value == value,
      orElse: () => LayoutType.defaultLayout,
    );
  }
}
