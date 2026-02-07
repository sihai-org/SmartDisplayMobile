enum DeviceUpdateVersionResult {
  updating,        // 正在更新（ACCEPTED）
  alreadyInFlight, // 已有更新流程在跑
  latest,          // 无需更新
  optionalUpdate,  // 可选更新
  throttled,       // 被限流 / 距离上次太近
  rejectedLowStorage, // 存储空间不足
  failed,           // 检查失败/异常
}

/// BLE 连接结果（区分成功 / 失败 / 竞态取消等场景）
enum BleConnectResult {
  success,
  alreadyConnected,
  cancelled,
  userMismatch,
  failed,
  timeout, // 👈 新增：连接超时
  scanTimeout, // 扫描超时（提示：设备不在附近）
  notReady, // BLE 未就绪（提示：开启蓝牙、设置权限）
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
