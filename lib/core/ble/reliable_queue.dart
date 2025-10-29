import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../constants/ble_constants.dart';
import 'ble_service_simple.dart';
import 'frame_codec.dart';

class ReliableRequestQueue {
  final String deviceId;
  final String serviceUuid;
  final String rxUuid;
  final String txUuid;
  final FlutterReactiveBle _ble;
  final _eventsController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _eventsController.stream;

  StreamSubscription<List<int>>? _sub;
  final FrameDecoder _decoder = FrameDecoder();
  int _nextReqId = 1;

  // Optional crypto handlers installed after handshake
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? _wrapEncrypt;
  Future<Map<String, dynamic>> Function(Map<String, dynamic>)? _unwrapDecrypt;

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
    ).listen((evt) async {
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
        final decoded = _decoder.addPacket(Uint8List.fromList(evt));
        if (decoded != null) {
          // Work with a guaranteed non-null map inside this block
          Map<String, dynamic> msg = decoded;
          // If post-handshake, require encrypted envelope for non-handshake messages
          if (_unwrapDecrypt != null) {
            try {
              final t = (msg['type'] ?? '').toString();
              if (t == 'handshake_response') {
                // handshake_response is allowed in plain during handshake phase (handlers not installed then)
                // but in case we still see it here, just pass through
              } else if (t == 'enc') {
                msg = await _unwrapDecrypt!(msg);
              } else {
                // Post-handshake plaintext is not allowed
                final reqIdFromHeader = msg['hReqId'] as int?;
                msg = {
                  'type': 'error',
                  'ok': false,
                  'error': {
                    'code': 'require_encrypted',
                    'message': 'use encrypted envelope {type: "enc"}'
                  },
                  if (reqIdFromHeader != null) 'hReqId': reqIdFromHeader,
                  if (reqIdFromHeader != null) 'reqId': reqIdFromHeader,
                };
              }
            } catch (e) {
              // Decrypt failed: surface as error to the pending request
              final reqIdFromHeader = msg['hReqId'] as int?;
              msg = {
                'type': 'error',
                'ok': false,
                'error': {
                  'code': 'decrypt_failed',
                  'message': e.toString(),
                },
                if (reqIdFromHeader != null) 'hReqId': reqIdFromHeader,
                if (reqIdFromHeader != null) 'reqId': reqIdFromHeader,
              };
            }
          }
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
          } else {
            // Unsolicited or no matching in-flight request: publish as push event
            _eventsController.add(msg);
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
    // Use negotiated MTU if available; fallback to safe minimum
    final mtu = BleServiceSimple.getNegotiatedMtu(deviceId);
    final encoder = FrameEncoder(mtu);
    final reqId = (_nextReqId++ & 0xFFFF);
    // Apply encryption wrapper if installed and not handshake
    Map<String, dynamic> payload = json;
    if (_wrapEncrypt != null) {
      final t = (json['type'] ?? '').toString();
      if (t != 'handshake_init') {
        // Post-handshake: enforce encryption; if wrapper fails, do not fall back to plain
        payload = await _wrapEncrypt!(json);
      }
    }
    final frames = encoder.encodeJson(reqId, payload);
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

  void setCryptoHandlers({
    required Future<Map<String, dynamic>> Function(Map<String, dynamic>) encrypt,
    required Future<Map<String, dynamic>> Function(Map<String, dynamic>) decrypt,
  }) {
    _wrapEncrypt = encrypt;
    _unwrapDecrypt = decrypt;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _inflight.clear();
    await _eventsController.close();
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
