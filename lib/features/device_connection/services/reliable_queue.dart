import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../../../core/constants/ble_constants.dart';
import 'ble_service_simple.dart';
import 'frame_codec.dart';

class ReliableRequestQueue {
  final String deviceId;
  final String serviceUuid;
  final String rxUuid;
  final String txUuid;
  final FlutterReactiveBle _ble;

  StreamSubscription<List<int>>? _sub;
  final FrameDecoder _decoder = FrameDecoder();
  int _nextReqId = 1;

  ReliableRequestQueue({
    required this.deviceId,
    this.serviceUuid = BleConstants.serviceUuid,
    this.rxUuid = BleConstants.rxCharUuid,
    this.txUuid = BleConstants.txCharUuid,
    FlutterReactiveBle? ble,
  }) : _ble = ble ?? FlutterReactiveBle();

  Future<void> prepare() async {
    await BleServiceSimple.ensureGattReady(deviceId);
    await BleServiceSimple.hasRxTx(deviceId: deviceId, serviceUuid: serviceUuid, rxUuid: rxUuid, txUuid: txUuid);
    _sub?.cancel();
    _sub = BleServiceSimple.subscribeToIndications(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      txCharacteristicUuid: txUuid,
    ).listen((evt) {
      try {
        // Log each incoming fragment with parsed header for debugging
        if (evt.isNotEmpty && evt.length >= 10) {
          int u8(int i) => evt[i] & 0xFF;
          int u16(int i) => ((evt[i] & 0xFF) << 8) | (evt[i + 1] & 0xFF);
          final ver = u8(0);
          final flags = u8(1);
          final reqId = u16(2);
          final total = u16(4);
          final index = u16(6);
          final payloadLen = u16(8);
          _log('RX frag ver=$ver flags=$flags req=$reqId ${index + 1}/$total len=${evt.length} payload=$payloadLen');
        } else {
          _log('RX frag len=${evt.length}');
        }
        final msg = _decoder.addPacket(Uint8List.fromList(evt));
        if (msg != null) {
          // Robustly extract reqId (support int or numeric string); fallback to header reqId
          int? reqId;
          final v = msg['reqId'];
          if (v is int) {
            reqId = v;
          } else if (v is String) {
            final p = int.tryParse(v);
            if (p != null) reqId = p;
          }
          reqId ??= msg['hReqId'] as int?;
          _log('RX msg type=${msg['type']} reqId=$reqId');

          _Pending? pending;
          if (reqId != null) {
            pending = _inflight[reqId];
          } else if (_inflight.length == 1) {
            // Fallback: if only one inflight, attribute to it
            pending = _inflight.values.first;
          }
          if (pending != null && !pending.completer.isCompleted) {
            final done = pending.isFinal == null ? true : pending.isFinal!(msg);
            if (done) {
              if (reqId != null) _inflight.remove(reqId);
              pending.completer.complete(msg);
            }
            // else: keep waiting for the final message for this reqId
          }
        }
      } catch (e) {
        _log('Decoder/dispatch error: $e');
      }
    }, onError: (Object e, StackTrace st) {
      // Do not crash app on characteristic update errors; just log and continue
      _log('Subscribe error: $e');
    });

    // Give CCCD enable a brief settle time before first write
    await Future.delayed(const Duration(milliseconds: 300));
  }

  final Map<int, _Pending> _inflight = {};

  Future<Map<String, dynamic>> send(
    Map<String, dynamic> json, {
    Duration timeout = const Duration(seconds: 5),
    int retries = 2,
    bool Function(Map<String, dynamic>)? isFinal,
  }) async {
    final mtu = await _ble.requestMtu(deviceId: deviceId, mtu: BleConstants.preferredMtu).catchError((_) => BleConstants.minMtu);
    final encoder = FrameEncoder(mtu);
    final reqId = (_nextReqId++ & 0xFFFF);
    final frames = encoder.encodeJson(reqId, json);
    final completer = Completer<Map<String, dynamic>>();
    _inflight[reqId] = _Pending(completer, isFinal);

    int attempt = 0;
    while (attempt <= retries && !completer.isCompleted) {
      attempt += 1;
      _log('TX send reqId=$reqId attempt=$attempt frames=${frames.length}');
      // 逐片写入 RX（withResponse）
      bool okAll = true;
      for (final pkt in frames) {
        final ok = await BleServiceSimple.writeCharacteristic(
          deviceId: deviceId,
          serviceUuid: serviceUuid,
          characteristicUuid: rxUuid,
          data: pkt,
          withResponse: true,
        );
        if (!ok) { okAll = false; break; }
        await Future.delayed(Duration(milliseconds: 10));
      }
      if (!okAll) {
        await Future.delayed(Duration(milliseconds: 120));
        continue;
      }
      try {
        final resp = await completer.future.timeout(timeout);
        resp['reqId'] = reqId;
        return resp;
      } catch (_) {
        _log('Timeout waiting for resp reqId=$reqId after ${timeout.inMilliseconds}ms');
        if (attempt > retries) rethrow;
      }
    }
    throw TimeoutException('BLE request timeout');
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _inflight.clear();
  }
}

class _Pending {
  final Completer<Map<String, dynamic>> completer;
  final bool Function(Map<String, dynamic>)? isFinal;
  _Pending(this.completer, this.isFinal);
}

void _log(Object msg) {
  // minimal logging util to avoid importing app logger here
  // ignore: avoid_print
  print('[RQ] $msg');
}
