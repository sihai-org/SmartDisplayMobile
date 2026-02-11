/// BLE GATT service and characteristic UUIDs
class BleConstants {
  // Service UUID
  static const String serviceUuid = '0000A100-0000-1000-8000-00805F9B34FB';

  // Dual-char design
  static const String rxCharUuid =
      '0000A111-0000-1000-8000-00805F9B34FB'; // WRITE WITH RESPONSE
  static const String txCharUuid =
      '0000A112-0000-1000-8000-00805F9B34FB'; // INDICATE only (no READ)

  // MTU Configuration
  static const int preferredMtu = 247;
  static const int minMtu = 23;
  // iOS (withResponse) emergency cap: 180 payload
  static const int iosWithResponseCapMtu = 183; // 180 + 3
  static const Duration writeRetryDelay = Duration(milliseconds: 200);
  static const Duration perDeviceLogInterval = Duration(seconds: 3);
  // Proximity & backoff
  static const int rssiProximityThreshold = -80;

  // 1. 扫描超时
  static const Duration scanTimeout = Duration(seconds: 3);
  // 扫描容忍期限
  static const Duration scanGrace = Duration(milliseconds: 600);
  static const Duration scanSwitchWait = Duration(milliseconds: 60);
  // 2. 连接超时
  static const Duration connectToServiceTimeout = Duration(seconds: 6);
  static const Duration waitForDisconnectedTimeout = Duration(seconds: 2);
  static const Duration connectGatt135Cooldown = Duration(seconds: 2);
  static const Duration connectPostDisconnectDelay = Duration(
    milliseconds: 200,
  );
  static const Duration connectPostDisconnectFallbackDelay = Duration(
    milliseconds: 300,
  );
  // 3. 写超时
  static const Duration reliableQueueSendTimeout = Duration(seconds: 10);
  static const Duration reliableQueueInterFrameDelay = Duration(
    milliseconds: 10,
  );
  static const Duration reliableQueueRetryBackoff = Duration(milliseconds: 120);
  static const Duration reliableQueueFirstSendExtraBackoff = Duration(
    milliseconds: 180,
  );
  // @important 蓝牙连接 UI 最多等10秒
  static const Duration kLoadingMaxS = Duration(seconds: 10);

  static const Duration kDisconnectStabilize = Duration(milliseconds: 300);
  static const Duration bleStatusCheckTimeout = Duration(seconds: 5);
  static const Duration bleReadyWaitTimeout = Duration(seconds: 2);
  static const Duration discoverRetryDelay = Duration(milliseconds: 600);
  static const Duration prepareSpinWait = Duration(milliseconds: 80);
  static const Duration keyGenWarnDelay = Duration(seconds: 3);
  static const Duration keyGenErrorDelay = Duration(seconds: 15);

  static const kStabilizeAfterConnect = Duration(milliseconds: 150); // 原 800
  static const kStabilizeBeforeDiscover = Duration(milliseconds: 150); // 原 800
  static const kStabilizeAfterMtu = Duration(milliseconds: 150); // 原 800

  // Heartbeat (connectivity check / state correction only)
  static const Duration kHeartbeatTickInterval = Duration(seconds: 2);
  static const Duration kHeartbeatInterval = Duration(seconds: 6);
  static const Duration kHeartbeatIdleBeforeSend = Duration(seconds: 4);
  static const Duration kHeartbeatTimeout = Duration(milliseconds: 1100);
  static const int kHeartbeatFailThreshold = 2;

  // Sync
  static const Duration minSyncGap = Duration(seconds: 1);
}
