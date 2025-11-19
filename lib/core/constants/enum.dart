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
