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
  // Stabilization and retries
  static const int postConnectStabilizeDelayMs = 200;
  static const int writeRetryDelayMs = 200;
  // Proximity & backoff
  static const int rssiProximityThreshold = -80;
  static const int reconnectBackoffStartMs = 1000;
  static const int reconnectBackoffMaxMs = 10000;
  
  // Connection Parameters
  static const int connectionIntervalMs = 100;
  static const int connectionLatency = 0;
  static const int supervisionTimeoutMs = 20000;

  static const Duration kDisconnectStabilize = Duration(milliseconds: 500);

  static const kStabilizeAfterConnect = Duration(milliseconds: 250); // 原 800
  static const kStabilizeBeforeDiscover = Duration(milliseconds: 200); // 原 800
  static const kStabilizeAfterMtu = Duration(milliseconds: 200); // 原 800
}
