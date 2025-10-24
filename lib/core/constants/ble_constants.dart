/// BLE GATT service and characteristic UUIDs
class BleConstants {
  // Service UUID
  static const String serviceUuid = '0000A100-0000-1000-8000-00805F9B34FB';
  
  // Legacy multi-characteristic UUIDs removed. Keep logical IDs for higher-level mapping.
  static const String updateVersionCharUuid = '0000A10A-0000-1000-8000-00805F9B34FB';
  static const String loginAuthCodeCharUuid =  '0000A10B-0000-1000-8000-00805F9B34FB';
  static const String logoutCharUuid =  '0000A10C-0000-1000-8000-00805F9B34FB';

  // Dual-char design
  static const String rxCharUuid = '0000A111-0000-1000-8000-00805F9B34FB'; // WRITE WITH RESPONSE
  static const String txCharUuid = '0000A112-0000-1000-8000-00805F9B34FB'; // INDICATE only (no READ)

  // Device Advertisement
  static const String deviceNamePrefix = 'AI-TV-';
  static const int advertisementTimeoutMs = 30000; // 30 seconds
  
  // MTU Configuration
  static const int preferredMtu = 247;
  static const int minMtu = 23;
  static const int maxMtu = 517;
  // Stabilization and retries
  static const int postConnectStabilizeDelayMs = 200;
  static const int writeRetryDelayMs = 200;
  // Proximity & backoff
  static const int rssiProximityThreshold = -75;
  static const int reconnectBackoffStartMs = 1000;
  static const int reconnectBackoffMaxMs = 10000;
  
  // Connection Parameters
  static const int connectionIntervalMs = 100;
  static const int connectionLatency = 0;
  static const int supervisionTimeoutMs = 20000;
}
