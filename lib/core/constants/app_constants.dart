/// Application-wide constants
class AppConstants {
  // App Info
  static const String appName = 'SmartDisplay Mobile';
  static const String appVersion = '1.0.0';
  
  // BLE Configuration
  static const String bleServiceUuid = '0000A100-0000-1000-8000-00805F9B34FB';
  static const int bleScanTimeoutSeconds = 10;
  static const int bleConnectionTimeoutSeconds = 15;
  static const int bleMaxRetryAttempts = 3;
  
  // QR Code Configuration
  static const String qrProtocolPrefix = 'aidisplay:';
  static const String qrProtocolVersion = '1';
  static const String qrExpectedProtocol = '$qrProtocolPrefix$qrProtocolVersion';
  
  // Crypto Configuration
  static const String kdfInfo = 'aidisplay-provision';
  static const int aesGcmNonceLength = 12;
  static const int aesGcmTagLength = 16;
  static const int sessionKeyLength = 32;
  
  // Network Configuration
  static const int wifiScanTimeoutSeconds = 15;
  static const int provisionTimeoutSeconds = 60;
  static const List<String> supportedBands = ['2.4G', '5G', 'auto'];
  
  // UI Configuration
  static const int defaultAnimationDurationMs = 300;
  static const double defaultPadding = 16.0;
  static const double defaultBorderRadius = 12.0;
  
  // Storage Keys
  static const String keyDeviceList = 'configured_devices';
  static const String keyLastConnectedDevice = 'last_connected_device';
  static const String keyAppSettings = 'app_settings';
  
  // Debug and Testing Configuration
  static const bool isDebugMode = true; // Set to false for production
  static const bool enableMockData = false; // Enable mock data for testing
  static const bool skipBleScanning = false; // Skip real BLE scanning for debugging
  static const bool skipPermissionCheck = false; // Skip permission check for development
}