/// BLE GATT service and characteristic UUIDs
class BleConstants {
  // Service UUID
  static const String serviceUuid = '0000A100-0000-1000-8000-00805F9B34FB';
  
  // Characteristic UUIDs
  static const String deviceInfoCharUuid = '0000A101-0000-1000-8000-00805F9B34FB';
  static const String wifiScanRequestCharUuid = '0000A102-0000-1000-8000-00805F9B34FB';
  static const String wifiScanResultCharUuid = '0000A103-0000-1000-8000-00805F9B34FB';
  static const String sessionNonceCharUuid = '0000A104-0000-1000-8000-00805F9B34FB';
  static const String secureHandshakeCharUuid = '0000A105-0000-1000-8000-00805F9B34FB';
  // Renamed: Provision_Request -> Wifi_Config_Request (UUID unchanged)
  static const String wifiConfigRequestCharUuid = '0000A106-0000-1000-8000-00805F9B34FB';
  // Renamed: Provision_Status -> Wifi_Config_Status (UUID unchanged)
  static const String wifiConfigStatusCharUuid = '0000A107-0000-1000-8000-00805F9B34FB';
  static const String oobQrInfoCharUuid = '0000A108-0000-1000-8000-00805F9B34FB';
  static const String networkStatusCharUuid = '0000A109-0000-1000-8000-00805F9B34FB';
  static const String updateVersionCharUuid = '0000A10A-0000-1000-8000-00805F9B34FB';
  static const String loginAuthCodeCharUuid =  '0000A10B-0000-1000-8000-00805F9B34FB';
  static const String logoutCharUuid =  '0000A10C-0000-1000-8000-00805F9B34FB';

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
