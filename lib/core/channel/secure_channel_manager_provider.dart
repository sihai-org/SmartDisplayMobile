// lib/core/secure/secure_providers_single.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'secure_channel_manager.dart';
import 'secure_channel_impl.dart';
import '../ble/ble_scanner.dart';
import '../ble/ble_scanner_impl.dart';
import '../ble/reliable_queue.dart';
import '../crypto/crypto_service.dart';

// 工厂：如何创建单个通道
final secureChannelFactoryProvider = Provider<SecureChannelFactory>((ref) {
  return (String displayDeviceId, String bleDeviceId, String devicePublicKeyHex) =>
      SecureChannelImpl(
        displayDeviceId: displayDeviceId,
        bleDeviceId: bleDeviceId,
        devicePublicKeyHex: devicePublicKeyHex,
        createQueue: (id) => ReliableRequestQueue(deviceId: id),
    crypto: CryptoService(),
  );
});

final bleScannerProvider = Provider<BleScanner>((ref) {
  final scanner = BleScannerImpl();
  ref.onDispose(() => scanner.stop());
  return scanner;
});

// 扫描→建连→握手
final secureChannelManagerProvider = Provider<SecureChannelManager>((ref) {
  final factory = ref.read(secureChannelFactoryProvider);
  final scanner = ref.read(bleScannerProvider);
  final mgr = SecureChannelManager(factory, scanner); // 构造函数加上 scanner
  ref.onDispose(() => (mgr as SecureChannelManager).dispose());
  return mgr;
});