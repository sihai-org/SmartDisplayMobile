// lib/core/secure/secure_providers_single.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'secure_channel_manager.dart';
import 'secure_channel_impl.dart';
import '../ble/ble_scanner.dart';
import '../ble/ble_scanner_impl.dart';
import '../ble/reliable_queue.dart';
import '../crypto/crypto_service.dart';
import '../providers/audit_mode_provider.dart';
import '../ble/ble_scanner_mock.dart';
import 'mock_secure_channel.dart';

// 工厂：如何创建单个通道
final _secureChannelFactoryProvider = Provider<SecureChannelFactory>((ref) {
  // React to audit mode toggle
  final audit = ref.watch(auditModeProvider).enabled;
  if (audit) {
    return (String displayDeviceId, String bleDeviceId, String devicePublicKeyHex) =>
        MockSecureChannel(
          displayDeviceId: displayDeviceId,
          bleDeviceId: bleDeviceId,
          devicePublicKeyHex: devicePublicKeyHex,
        );
  }
  return (String displayDeviceId, String bleDeviceId, String devicePublicKeyHex) =>
      SecureChannelImpl(
        displayDeviceId: displayDeviceId,
        bleDeviceId: bleDeviceId,
        devicePublicKeyHex: devicePublicKeyHex,
        createQueue: (id) => ReliableRequestQueue(deviceId: id),
        crypto: CryptoService(),
      );
});

final _bleScannerProvider = Provider<BleScanner>((ref) {
  // React to audit mode toggle
  final audit = ref.watch(auditModeProvider).enabled;
  if (audit) {
    final scanner = BleScannerMock();
    ref.onDispose(() => scanner.stop());
    return scanner;
  }
  final scanner = BleScannerImpl();
  ref.onDispose(() => scanner.stop());
  return scanner;
});

// 扫描→建连→握手
final secureChannelManagerProvider = Provider<SecureChannelManager>((ref) {
  // Watch dependencies so toggling audit mode reconstructs the manager
  final factory = ref.watch(_secureChannelFactoryProvider);
  final scanner = ref.watch(_bleScannerProvider);
  final mgr = SecureChannelManager(factory, scanner); // 构造函数加上 scanner
  ref.onDispose(() => (mgr as SecureChannelManager).dispose());
  return mgr;
});
