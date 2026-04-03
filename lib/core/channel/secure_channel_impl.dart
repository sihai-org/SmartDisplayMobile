import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:smart_display_mobile/core/constants/enum.dart';
import '../log/app_log.dart';

import '../ble/ble_service_simple.dart';
import '../ble/reliable_queue.dart';
import '../constants/ble_constants.dart';
import '../crypto/crypto_service.dart';
import '../ble/ble_device_data.dart';

import 'secure_channel.dart';

class SecureChannelImpl implements SecureChannel {
  SecureChannelImpl({
    required this.displayDeviceId,
    required this.bleDeviceId,
    required this.devicePublicKeyHex,
    required this.createQueue,
    required this.crypto,
  });

  @override
  final String displayDeviceId;

  @override
  final String bleDeviceId;

  @override
  final String devicePublicKeyHex;

  final ReliableRequestQueue Function(String deviceId) createQueue;
  final CryptoService crypto;

  ReliableRequestQueue? _rq;
  StreamSubscription<Map<String, dynamic>>? _evtSub;
  StreamSubscription<Map<String, dynamic>>? _linkSub;
  final _evtCtrl = StreamController<Map<String, dynamic>>.broadcast();

  bool _authenticated = false;
  bool _preparing = false;
  String? _lastHandshakeStatus;

  bool _disposed = false; // 👈 新增：标记这个实例是否已被释放

  @override
  Stream<Map<String, dynamic>> get events => _evtCtrl.stream;

  @override
  String? get lastHandshakeStatus => _lastHandshakeStatus;

  void _ensureNotDisposed(String phase) {
    if (_disposed) {
      throw StateError('SecureChannel 已释放（$phase）');
    }
  }

  @override
  Future<void> ensureAuthenticated(String userId) async {
    _ensureNotDisposed('ensureAuthenticated-入口');

    if (_authenticated) return;
    if (_preparing) {
      // 等待并发的首次准备完成
      while (_preparing && !_authenticated && !_disposed) {
        await Future.delayed(BleConstants.prepareSpinWait);
      }
      if (_authenticated) return;
    }

    Future<void>? keyGenFuture;
    Future<void>? keyGenSettled;

    _preparing = true;
    try {
      _ensureNotDisposed('准备阶段前');

      // 1) 仅在检测到活跃 GATT 时断开，避免无条件重置蓝牙栈状态
      if (BleServiceSimple.hasActiveConnection) {
        final previousDeviceId = BleServiceSimple.activeDeviceId;
        AppLog.instance.info(
          'active gatt exists, disconnect first: active=$previousDeviceId target=$bleDeviceId',
          tag: 'Channel',
        );
        final waitDisconnected = BleServiceSimple.waitForDisconnected(
          deviceId: previousDeviceId,
          timeout: BleConstants.waitForDisconnectedTimeout,
        );
        await BleServiceSimple.disconnect();
        final gotDisconnected = await waitDisconnected;
        if (!gotDisconnected) {
          await Future.delayed(BleConstants.connectPostDisconnectFallbackDelay);
        } else {
          await Future.delayed(BleConstants.connectPostDisconnectDelay);
        }
      }

      // 2) BLE 就绪
      _ensureNotDisposed('disconnect 之后');
      final ok = await BleServiceSimple.ensureBleReady();
      if (!ok) {
        throw StateError(BleConnectResult.notReady.name);
      }

      // 3) 连接 + GATT
      _ensureNotDisposed('ensureBleReady 之后');
      keyGenFuture = crypto.generateEphemeralKeyPair();
      final keyGenSw = Stopwatch()..start();
      var keyGenCompleted = false;
      final mode = kReleaseMode
          ? 'release'
          : (kProfileMode ? 'profile' : 'debug');
      AppLog.instance.debug(
        'keyGenFuture created (mode=$mode, isolate=${Isolate.current.hashCode})',
        tag: 'Channel',
      );
      keyGenFuture.whenComplete(() {
        keyGenCompleted = true;
        keyGenSw.stop();
        AppLog.instance.debug(
          'keyGenFuture completed in ${keyGenSw.elapsedMilliseconds}ms (mode=$mode, isolate=${Isolate.current.hashCode})',
          tag: 'Channel',
        );
      });
      unawaited(
        Future<void>.delayed(BleConstants.keyGenWarnDelay, () {
          if (!keyGenCompleted) {
            AppLog.instance.warning(
              'keyGenFuture still pending after ${keyGenSw.elapsedMilliseconds}ms (mode=$mode, isolate=${Isolate.current.hashCode})',
              tag: 'Channel',
            );
          }
        }),
      );
      unawaited(
        Future<void>.delayed(BleConstants.keyGenErrorDelay, () {
          if (!keyGenCompleted) {
            AppLog.instance.error(
              'keyGenFuture still pending after ${keyGenSw.elapsedMilliseconds}ms (mode=$mode, isolate=${Isolate.current.hashCode})',
              tag: 'Channel',
              error: StateError('keyGenFuture appears stuck'),
              stackTrace: StackTrace.current,
            );
          }
        }),
      );
      // 收敛异常路径：即便中途失败未 await keyGenFuture，也不会出现未捕获异步错误
      keyGenSettled = keyGenFuture.catchError((e, st) {
        AppLog.instance.error(
          'keyGenFuture failed before await',
          tag: 'Channel',
          error: e,
          stackTrace: st,
        );
      });
      final data = await BleServiceSimple.connectToDevice(
        bleDeviceData: BleDeviceData(
          displayDeviceId: displayDeviceId,
          bleDeviceId: bleDeviceId,
          deviceName: '', // 可选：不需要用于连接
          publicKey: devicePublicKeyHex,
          status: BleDeviceStatus.connecting,
        ),
      );
      if (data == null) throw StateError('连接失败');

      final ready = await BleServiceSimple.ensureGattReady(data.bleDeviceId);
      if (!ready) throw StateError('GATT 未就绪');

      // 4) 双特征检查
      final hasDual = await BleServiceSimple.hasRxTx(
        deviceId: data.bleDeviceId,
        serviceUuid: BleConstants.serviceUuid,
        rxUuid: BleConstants.rxCharUuid,
        txUuid: BleConstants.txCharUuid,
      );
      if (!hasDual) throw StateError('设备不支持双特征通道');

      // 5) 准备可靠队列
      _ensureNotDisposed('connectToDevice + ensureGattReady + hasRxTx 之后');
      AppLog.instance.debug("[ble_connection_provider] call _rq?.dispose()");
      await _rq?.dispose();
      AppLog.instance.debug("[ble_connection_provider] call createQueue()");
      _rq = createQueue(data.bleDeviceId);
      AppLog.instance.debug("[ble_connection_provider] call _rq!.prepare()");
      await _rq!.prepare();

      // 6) 应用层握手（示例：与你现有逻辑一致）
      _ensureNotDisposed('队列准备完成');
      AppLog.instance.debug("[ble_connection_provider] call keyGenFuture");
      AppLog.instance.debug(
        'await keyGenFuture... (mode=$mode, isolate=${Isolate.current.hashCode})',
        tag: 'Channel',
      );
      await keyGenFuture;
      AppLog.instance.info(
        "[ble_connection_provider] call getHandshakeInitData",
      );
      final initObj = await crypto.getHandshakeInitData();
      if (userId.isNotEmpty) {
        initObj['userId'] = userId;
      }
      AppLog.instance.info(
        "[ble_connection_provider] handshake_init userId=${userId}",
      );
      final resp = await _rq!.send(
        initObj,
        retries: 1,
        isFinal: (m) => (m['type']?.toString() == 'handshake_response'),
      );

      // 记录设备在握手响应中返回的状态（例如：empty_bound）
      try {
        final st = resp['status'];
        if (st != null) {
          _lastHandshakeStatus = st.toString();
        } else {
          _lastHandshakeStatus = null;
        }
      } catch (_) {
        _lastHandshakeStatus = null;
      }

      AppLog.instance.info(
        "[ble_connection_provider] 握手完成（resp 收到） _lastHandshakeStatus=${_lastHandshakeStatus}",
      );
      _ensureNotDisposed('握手完成（resp 收到）');
      final parsed = crypto.parseHandshakeResponseMap(resp);
      final localPub = await crypto.getLocalPublicKey();
      await crypto.performKeyExchange(
        remoteEphemeralPubKey: parsed.publicKey,
        signature: parsed.signature,
        devicePublicKeyHex: data.publicKey,
        clientEphemeralPubKey: localPub,
        timestamp: parsed.timestamp,
        clientTimestamp: crypto.clientTimestamp!,
      );

      // 7) 安装加解密处理器
      _ensureNotDisposed('密钥交换完成');
      _rq!.setCryptoHandlers(
        encrypt: (Map<String, dynamic> plain) async {
          final text = jsonEncode(plain);
          final enc = await crypto.encrypt(text);
          final b64 = base64Encode(Uint8List.fromList(enc.toBytes()));
          return {'type': 'enc', 'data': b64};
        },
        decrypt: (Map<String, dynamic> msg) async {
          if (msg['type'] == 'enc' && msg['data'] is String) {
            final raw = base64Decode(msg['data'] as String);
            final ed = EncryptedData.fromBytes(raw);
            final plain = await crypto.decrypt(ed);
            final obj = jsonDecode(plain) as Map<String, dynamic>;
            // 透传 reqId/hReqId，保持调用方兼容
            final hReqId = msg['hReqId'];
            if (hReqId != null) obj['hReqId'] = hReqId;
            obj['reqId'] = obj['reqId'] ?? msg['reqId'] ?? hReqId;
            return obj;
          }
          return msg;
        },
      );

      // 8) 订阅事件，转给全局 stream
      await _evtSub?.cancel();
      _evtSub = _rq!.events.listen(_evtCtrl.add);

      // Forward low-level connection and adapter status to upper layer
      await _linkSub?.cancel();
      _linkSub = BleServiceSimple.connectionEvents.listen((e) async {
        AppLog.instance.info(
          "[SecureChannelImpl] e=${e.toString()}",
          tag: 'Channel',
        );
        final t = (e['type'] ?? '').toString();
        if (t == 'connection') {
          final st = (e['state'] ?? '').toString();
          if (st == 'disconnected' || st == 'error') {
            // Mark channel not authenticated and surface status
            _authenticated = false;
            try {
              await _rq?.dispose();
            } catch (_) {}
            _evtCtrl.add({'type': 'status', 'value': 'disconnected'});
          }
        } else if (t == 'ble_status') {
          final s = (e['status'] ?? '').toString();
          if (s.contains('poweredOff')) {
            _authenticated = false;
            try {
              await _rq?.dispose();
            } catch (_) {}
            _evtCtrl.add({'type': 'status', 'value': 'ble_powered_off'});
          }
        }
      });

      _authenticated = true;
    } catch (e) {
      if (keyGenSettled != null) {
        await keyGenSettled;
      }
      rethrow;
    } finally {
      _preparing = false;
    }
  }

  @override
  Future<Map<String, dynamic>> send(
    Map<String, dynamic> msg, {
    Duration? timeout,
    int retries = 0,
    bool Function(Map<String, dynamic>)? isFinal,
  }) async {
    _ensureNotDisposed('send');
    if (!_authenticated || _rq == null) {
      throw StateError('SecureChannel 未就绪（未认证或队列未初始化）');
    }
    return _rq!.send(
      msg,
      timeout: timeout ?? BleConstants.reliableQueueSendTimeout,
      retries: retries,
      isFinal: isFinal,
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true; // 👈 先打上“已释放”标记
    await _evtSub?.cancel();
    await _linkSub?.cancel();
    await _rq?.dispose();
    _evtCtrl.close();
    _rq = null;
    _authenticated = false;
    await BleServiceSimple.disconnect();
    crypto.cleanup();
    _lastHandshakeStatus = null;
  }
}
