import 'dart:convert';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../channel/secure_channel_manager_provider.dart';
import '../log/app_log.dart';
import '../models/device_qr_data.dart';
import 'ble_service_simple.dart';

class BleOneClickTestConfig {
  final int stabilityCycles;
  final int stressMessages;
  final Duration connectTimeout;

  const BleOneClickTestConfig({
    this.stabilityCycles = 10,
    this.stressMessages = 50,
    this.connectTimeout = const Duration(seconds: 15),
  });
}

class BleTestStepResult {
  final String name;
  final bool ok;
  final int durationMs;
  final String details;

  const BleTestStepResult({
    required this.name,
    required this.ok,
    required this.durationMs,
    required this.details,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'ok': ok,
        'durationMs': durationMs,
        'details': details,
      };
}

class BleOneClickTestReport {
  final DateTime startedAt;
  final DateTime finishedAt;
  final String targetDisplayDeviceId;
  final String targetDeviceName;
  final String targetQrBleDeviceId;
  final BleStatus bleStatusAtStart;
  final List<BleTestStepResult> functional;
  final List<BleTestStepResult> stability;
  final List<BleTestStepResult> stress;

  const BleOneClickTestReport({
    required this.startedAt,
    required this.finishedAt,
    required this.targetDisplayDeviceId,
    required this.targetDeviceName,
    required this.targetQrBleDeviceId,
    required this.bleStatusAtStart,
    required this.functional,
    required this.stability,
    required this.stress,
  });

  bool get ok =>
      functional.every((e) => e.ok) &&
      stability.every((e) => e.ok) &&
      stress.every((e) => e.ok);

  Map<String, dynamic> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'target': {
          'displayDeviceId': targetDisplayDeviceId,
          'deviceName': targetDeviceName,
          'qrBleDeviceId': targetQrBleDeviceId,
        },
        'bleStatusAtStart': bleStatusAtStart.toString(),
        'ok': ok,
        'functional': functional.map((e) => e.toJson()).toList(),
        'stability': stability.map((e) => e.toJson()).toList(),
        'stress': stress.map((e) => e.toJson()).toList(),
      };

  String toPrettyText() {
    final map = toJson();
    return const JsonEncoder.withIndent('  ').convert(map);
  }
}

class BleOneClickTestRunner {
  BleOneClickTestRunner({
    this.onLog,
  });

  final void Function(String line)? onLog;

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  void _log(String msg) {
    AppLog.instance.debug('[BleOneClickTest] $msg', tag: 'BLE_TEST');
    onLog?.call(msg);
  }

  void _ensureNotCancelled() {
    if (_cancelled) {
      throw StateError('cancelled');
    }
  }

  Future<BleTestStepResult> _step(
    String name,
    Future<String> Function() run,
  ) async {
    final sw = Stopwatch()..start();
    try {
      _ensureNotCancelled();
      _log('▶ $name');
      final details = await run();
      sw.stop();
      _log('✅ $name (${sw.elapsedMilliseconds}ms)');
      return BleTestStepResult(
        name: name,
        ok: true,
        durationMs: sw.elapsedMilliseconds,
        details: details,
      );
    } catch (e) {
      sw.stop();
      final msg = e.toString();
      _log('❌ $name (${sw.elapsedMilliseconds}ms): $msg');
      return BleTestStepResult(
        name: name,
        ok: false,
        durationMs: sw.elapsedMilliseconds,
        details: msg,
      );
    }
  }

  Future<BleOneClickTestReport> run({
    required WidgetRef ref,
    required DeviceQrData target,
    BleOneClickTestConfig config = const BleOneClickTestConfig(),
  }) async {
    _cancelled = false;
    final startedAt = DateTime.now();

    final bleStatusAtStart = await BleServiceSimple.checkBleStatus();

    final functional = <BleTestStepResult>[];
    final stability = <BleTestStepResult>[];
    final stress = <BleTestStepResult>[];

    final mgr = ref.read(secureChannelManagerProvider);

    Future<Map<String, dynamic>> send(
      String type, {
      Duration timeout = const Duration(seconds: 3),
      int retries = 0,
    }) async {
      _ensureNotCancelled();
      return mgr.send(
        {'type': type, 'data': null},
        timeout: timeout,
        retries: retries,
      );
    }

    // -------- Functional --------
    functional.add(
      await _step('BLE ready', () async {
        final ok = await BleServiceSimple.ensureBleReady();
        if (!ok) {
          throw StateError('BLE not ready (adapter off / permission denied)');
        }
        return 'ok';
      }),
    );

    functional.add(
      await _step('Connect + handshake', () async {
        await mgr.dispose();
        final ok = await mgr.use(target);
        if (!ok) throw StateError('use() cancelled');
        final hs = mgr.lastHandshakeStatus ?? 'null';
        return 'handshakeStatus=$hs';
      }),
    );

    functional.add(
      await _step('Business: device.info', () async {
        final resp = await send('device.info', timeout: const Duration(seconds: 3));
        final ok = resp['ok'] == true;
        if (!ok) throw StateError('resp.ok != true: $resp');
        final data = resp['data'];
        if (data is! Map) throw StateError('unexpected data: $data');
        return 'keys=${data.keys.toList()}';
      }),
    );

    functional.add(
      await _step('Business: network.status', () async {
        final resp = await send('network.status',
            timeout: const Duration(milliseconds: 1200));
        final ok = resp['ok'] == true;
        if (!ok) throw StateError('resp.ok != true: $resp');
        return 'ok';
      }),
    );

    functional.add(
      await _step('Business: wifi.scan', () async {
        final resp = await send('wifi.scan', timeout: const Duration(seconds: 3));
        final ok = resp['ok'] == true;
        if (!ok) throw StateError('resp.ok != true: $resp');
        final data = resp['data'];
        if (data is List) return 'networks=${data.length}';
        return 'dataType=${data.runtimeType}';
      }),
    );

    // -------- Stability --------
    final stabilityOk = <bool>[];
    final connectMs = <int>[];
    for (var i = 0; i < config.stabilityCycles; i++) {
      if (_cancelled) break;
      final cycle = i + 1;
      final sw = Stopwatch()..start();
      final step = await _step('Stability cycle $cycle/${config.stabilityCycles}',
          () async {
        await mgr.dispose();
        final ok = await mgr.use(target);
        if (!ok) throw StateError('use() cancelled');
        final resp = await send('network.status',
            timeout: const Duration(milliseconds: 1200));
        if (resp['ok'] != true) throw StateError('resp.ok != true');
        return 'ok';
      });
      sw.stop();
      stabilityOk.add(step.ok);
      connectMs.add(sw.elapsedMilliseconds);
      stability.add(step);
    }
    if (stability.isEmpty) {
      stability.add(const BleTestStepResult(
          name: 'Stability skipped', ok: false, durationMs: 0, details: 'cancelled'));
    } else {
      final pass = stabilityOk.where((e) => e).length;
      final avg = connectMs.isEmpty
          ? 0
          : (connectMs.reduce((a, b) => a + b) / connectMs.length).round();
      stability.add(BleTestStepResult(
        name: 'Stability summary',
        ok: pass == stabilityOk.length,
        durationMs: 0,
        details: 'pass=$pass/${stabilityOk.length}, avgCycleMs=$avg',
      ));
    }

    // -------- Stress --------
    final latencies = <int>[];
    var stressPass = 0;
    var stressFail = 0;
    stress.add(
      await _step('Stress: connect once', () async {
        await mgr.dispose();
        final ok = await mgr.use(target);
        if (!ok) throw StateError('use() cancelled');
        return 'ok';
      }),
    );
    for (var i = 0; i < config.stressMessages; i++) {
      if (_cancelled) break;
      final sw = Stopwatch()..start();
      try {
        final resp = await send(
          'network.status',
          timeout: const Duration(milliseconds: 1200),
          retries: 0,
        );
        final ok = resp['ok'] == true;
        if (!ok) throw StateError('resp.ok != true');
        stressPass += 1;
        sw.stop();
        latencies.add(sw.elapsedMilliseconds);
      } catch (_) {
        stressFail += 1;
        sw.stop();
        latencies.add(sw.elapsedMilliseconds);
      }
    }

    latencies.sort();
    int pct(int p) {
      if (latencies.isEmpty) return 0;
      final idx = ((latencies.length - 1) * p / 100).round();
      return latencies[idx.clamp(0, latencies.length - 1)];
    }

    stress.add(BleTestStepResult(
      name: 'Stress summary',
      ok: stressFail == 0 && !_cancelled,
      durationMs: 0,
      details:
          'pass=$stressPass/${config.stressMessages}, fail=$stressFail, p50=${pct(50)}ms, p95=${pct(95)}ms',
    ));

    // Cleanup
    try {
      await mgr.dispose();
    } catch (_) {}

    final finishedAt = DateTime.now();
    return BleOneClickTestReport(
      startedAt: startedAt,
      finishedAt: finishedAt,
      targetDisplayDeviceId: target.displayDeviceId,
      targetDeviceName: target.deviceName,
      targetQrBleDeviceId: target.bleDeviceId,
      bleStatusAtStart: bleStatusAtStart,
      functional: functional,
      stability: stability,
      stress: stress,
    );
  }
}
