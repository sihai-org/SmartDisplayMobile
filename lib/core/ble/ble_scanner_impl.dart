import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:collection/collection.dart';

import '../../features/qr_scanner/utils/device_fingerprint.dart';
import '../constants/ble_constants.dart';
import '../models/device_qr_data.dart';
import 'ble_service_simple.dart';
import 'ble_scanner.dart';

class BleScannerImpl implements BleScanner {
  StreamSubscription? _sub;
  DateTime? _targetFirstSeenAt;

  @override
  Future<String> findBleAddress(
      DeviceQrData qr, {
        Duration timeout = const Duration(seconds: 30),
      }) async {
    await BleServiceSimple.stopScan().catchError((_) {});

    final c = Completer<String>();
    final timer = Timer(timeout, () async {
      await stop();
      if (!c.isCompleted) c.completeError(TimeoutException('扫描超时'));
    });

    _targetFirstSeenAt = null;

    _sub = BleServiceSimple
        .scanForDevice(timeout: timeout)
        .listen((r) async {
      if (_isTarget(r, qr.bleDeviceId)) {
        final now = DateTime.now();
        _targetFirstSeenAt ??= now;

        final near = r.rssi >= BleConstants.rssiProximityThreshold;
        final overGrace = now.difference(_targetFirstSeenAt!) >= const Duration(seconds: 2);
        if (near || overGrace) {
          final addr = Platform.isIOS ? r.deviceId : r.address;
          await stop();
          if (!c.isCompleted) c.complete(addr);
        }
      }
    }, onError: (e) async {
      await stop();
      if (!c.isCompleted) c.completeError(e);
    });

    try {
      final addr = await c.future;
      return addr;
    } finally {
      timer.cancel();
    }
  }

  @override
  Future<void> stop() async {
    try { await _sub?.cancel(); } catch (_) {}
    _sub = null;
    try { await BleServiceSimple.stopScan(); } catch (_) {}
  }

  bool _isTarget(SimpleBLEScanResult r, String targetDeviceId) {
    // 直接复用你现在的指纹/名称匹配
    if (r.manufacturerData != null) {
      final expected = createDeviceFingerprint(targetDeviceId);
      if (_containsSublist(r.manufacturerData!, expected)) return true;
    }
    return (r.name == null) ? false : r.name == /* 你的 deviceName */ r.name;
  }

  bool _containsSublist(Uint8List data, Uint8List pattern) {
    for (int i = 0; i <= data.length - pattern.length; i++) {
      if (const ListEquality().equals(data.sublist(i, i + pattern.length), pattern)) {
        return true;
      }
    }
    return false;
  }
}
