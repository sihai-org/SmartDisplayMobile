/// BLE GATT service and characteristic UUIDs
class BleConstants {
  // Service UUID
  static const String serviceUuid = '0000A100-0000-1000-8000-00805F9B34FB';

  // Dual-char design
  static const String rxCharUuid = '0000A111-0000-1000-8000-00805F9B34FB'; // WRITE WITH RESPONSE
  static const String txCharUuid = '0000A112-0000-1000-8000-00805F9B34FB'; // INDICATE only (no READ)
  
  // MTU Configuration
  static const int preferredMtu = 247;
  static const int minMtu = 23;
  static const int maxMtu = 517;
  static const int writeRetryDelayMs = 200;
  // Proximity & backoff
  static const int rssiProximityThreshold = -80;

  // 扫描超时
  static const Duration scanTimeout = Duration(milliseconds: 1200);
  // 扫描容忍期限
  static const Duration scanGrace = Duration(milliseconds: 600);

  // 顶层 UI 调用最多等10秒
  static const Duration kLoadingMaxS = Duration(seconds: 10);

  static const Duration kDisconnectStabilize = Duration(milliseconds: 300);

  static const kStabilizeAfterConnect = Duration(milliseconds: 150); // 原 800
  static const kStabilizeBeforeDiscover = Duration(milliseconds: 150); // 原 800
  static const kStabilizeAfterMtu = Duration(milliseconds: 150); // 原 800

  // Heartbeat (connectivity check / state correction only)
  static const Duration kHeartbeatInterval = Duration(seconds: 6);
  static const Duration kHeartbeatIdleBeforeSend = Duration(seconds: 4);
  static const Duration kHeartbeatTimeout = Duration(milliseconds: 1100);
  static const int kHeartbeatFailThreshold = 2;
}
