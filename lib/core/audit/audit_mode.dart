class AuditMode {
  // Global switch for local UI testing flow
  static bool enabled = false;

  // A fixed local "mock user" id used for storage scoping.
  static const String auditUserId = 'audit_user_local';

  // A fixed UUID used to tag audit purchases across StoreKit 1/2.
  // StoreKit 2 only persists appAccountToken when the value is a valid UUID.
  static const String auditStoreAccountToken =
      '3F0F7C4E-7D8E-4E6B-9F4C-3B79D2B6C1A1';

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
