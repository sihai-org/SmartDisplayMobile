class AuditMode {
  // Global switch for local UI testing flow
  static bool enabled = false;

  // A fixed local "mock user" id used for storage scoping
  static const String auditUserId = 'audit_user_local';

  // Mock device payload used across the flow
  static const String mockDisplayDeviceId = 'SP-D-LOCAL-001';
  static const String mockBleDeviceId = 'BLE-MOCK-001';
  static const String mockDeviceName = 'Local Mock Display';
  static const String mockPublicKeyHex =
      '04a1b2c3d4e5f60789abcdef0123456789abcdef0123456789abcdef01234567';

  static void enable() {
    enabled = true;
  }

  static void disable() {
    enabled = false;
  }
}

