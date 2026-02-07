import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:smart_display_mobile/core/constants/enum.dart';

import '../utils/device_fingerprint.dart';
import '../constants/ble_constants.dart';
import '../models/device_qr_data.dart';
import 'ble_service_simple.dart';
import 'ble_scanner.dart';

class BleScannerImpl implements BleScanner {
  StreamSubscription? _sub;
  DateTime? _targetFirstSeenAt;

  @override
  Future<String> findBleDeviceId(
    DeviceQrData qr, {
    Duration timeout = BleConstants.scanTimeout,
  }) async {
    final ok = await BleServiceSimple.ensureBleReady();
    if (!ok) {
      throw StateError(BleConnectResult.notReady.name);
    }

    final c = Completer<String>();
    final timer = Timer(timeout, () async {
      await stop();
      if (!c.isCompleted) c.completeError(TimeoutException(BleConnectResult.scanTimeout.name));
    });

    _targetFirstSeenAt = null;
    final expectedFingerprint = createDeviceFingerprint(qr.bleDeviceId);

    _sub = BleServiceSimple.scanForDevice(timeout: timeout).listen(
      (r) async {
        if (_isTarget(r, expectedFingerprint, qr.deviceName)) {
          final now = DateTime.now();
          _targetFirstSeenAt ??= now;

          final near = r.rssi >= BleConstants.rssiProximityThreshold;
          final overGrace =
              now.difference(_targetFirstSeenAt!) >= BleConstants.scanGrace;
          if (near || overGrace) {
            final addr = Platform.isIOS ? r.deviceId : r.address;
            await stop();
            if (!c.isCompleted) c.complete(addr);
          }
        }
      },
      onError: (e) async {
        await stop();
        if (!c.isCompleted) c.completeError(e);
      },
    );

    try {
      final addr = await c.future;
      return addr;
    } finally {
      timer.cancel();
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    try {
      await BleServiceSimple.stopScan();
    } catch (_) {}
  }

  bool _isTarget(
    SimpleBLEScanResult r,
    Uint8List expectedFingerprint,
    String targetDeviceName,
  ) {
    // 直接复用你现在的指纹/名称匹配
    if (r.manufacturerData != null) {
      if (_containsSublist(r.manufacturerData!, expectedFingerprint)) {
        return true;
      }
    }
    return r.name == targetDeviceName;
  }

  bool _containsSublist(Uint8List data, Uint8List pattern) {
    if (pattern.isEmpty) return true;
    final limit = data.length - pattern.length;
    if (limit < 0) return false;

    for (int i = 0; i <= limit; i++) {
      var matched = true;
      for (int j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        return true;
      }
    }
    return false;
  }
}
