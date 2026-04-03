// lib/core/secure/secure_channel_manager.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../log/app_log.dart';
import 'package:smart_display_mobile/core/ble/ble_scanner.dart';
import 'package:smart_display_mobile/core/constants/ble_constants.dart';
import 'package:smart_display_mobile/core/models/device_qr_data.dart';

import 'secure_channel.dart';

class _CancelledError implements Exception {
  @override
  String toString() => 'SecureChannelManager: cancelled by newer generation';
}

typedef SecureChannelFactory =
    SecureChannel Function(
      String displayDeviceId,
      String bleDeviceId,
      String devicePublicKeyHex,
    );

class SecureChannelManager {
  SecureChannelManager(this._factory, this._scanner);

  // user id should be read at call time to avoid stale cache

  bool _switching = false;

  int _gen = 0; // ✅ manager 自己的“代数”

  final SecureChannelFactory _factory;

  final BleScanner _scanner;

  String? _bleDeviceId; //  标记 channel 的 bleDeviceId
  SecureChannel? _channel;
  SecureChannel? _creatingChannel; // 正在 ensureAuthenticated 中的临时 channel

  StreamSubscription<Map<String, dynamic>>? _channelEvtSub;
  String? _lastHandshakeStatus;

  void _checkGen(int ticket) {
    if (ticket != _gen) {
      throw _CancelledError();
    }
  }

  Future<void> clearScannerAndChannel() async {
    _gen++; // ✅ 所有旧 ticket 全部失效

    try {
      await _scanner.stop();
    } catch (_) {}

    try {
      await _channelEvtSub?.cancel();
    } catch (_) {}
    _channelEvtSub = null;

    try {
      await _creatingChannel?.dispose();
    } catch (_) {}
    _creatingChannel = null;

    try {
      await _channel?.dispose();
    } catch (_) {}
    _channel = null;

    _bleDeviceId = null;
    _lastHandshakeStatus = null;
  }

  /// 将全局通道切换到指定设备；相同设备则复用
  Future<bool> use(DeviceQrData qrData) async {
    final targetDisplayDeviceId = qrData.displayDeviceId;
    final targetDevicePublicKeyHex = qrData.publicKey;

    // 为这次 use() 分配一个 generation ticket
    final int ticket = ++_gen; // ✅

    // 并发保护（从这里开始包含复用与新建逻辑）
    while (_switching) {
      await Future.delayed(BleConstants.scanSwitchWait);
    }
    _switching = true;
    try {
      _checkGen(ticket); // ✅ 进来先确认自己没过期

      // final start = DateTime.now();

      final String targetBleDeviceId = await _scanner.findBleDeviceId(qrData);

      // final end = DateTime.now();
      // AppLog.instance.info('~~~~~~~执行耗时: ${end.difference(start).inMilliseconds} ms');

      _checkGen(ticket); // ✅

      // 同设备尝试复用，但必须确保已认证
      if (_bleDeviceId == targetBleDeviceId && _channel != null) {
        final currentUserId =
            Supabase.instance.client.auth.currentUser?.id ?? "";
        try {
          await _channel!.ensureAuthenticated(currentUserId);
          _checkGen(ticket); // ✅

          return true; // 确认已认证才复用
        } catch (_) {
          await clearScannerAndChannel(); // 复用失败，清理后走新建
          _checkGen(ticket); // 通常这里已经抛 Cancel 了
        }
      }

      // 创建新通道
      final ch = _factory(
        targetDisplayDeviceId,
        targetBleDeviceId,
        targetDevicePublicKeyHex,
      );
      _creatingChannel = ch; // 标记为正在创建，确保失败时能 dispose
      // 连上（读取最新 userId，避免缓存过期）
      final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? "";
      await ch.ensureAuthenticated(currentUserId); // 🔐 可能花比较久
      _checkGen(ticket); // ✅ 如果中途有人 dispose，我就直接抛 Cancel

      // 读取握手阶段状态（例如 empty_bound）
      try {
        _lastHandshakeStatus = ch.lastHandshakeStatus;
      } catch (_) {
        _lastHandshakeStatus = null;
      }

      // 赋值前先解绑旧监听（保证一致性）
      try {
        await _channelEvtSub?.cancel();
      } catch (_) {}
      _channelEvtSub = null;
      _checkGen(ticket); // ✅ 防止在 await cancel 期间被 dispose 后仍写回 channel

      _bleDeviceId = targetBleDeviceId;
      _channel = ch;
      _creatingChannel = null;
      // 监听断开/蓝牙关闭，立刻清理引用
      _channelEvtSub = ch.events.listen((e) async {
        AppLog.instance.info(
          "=============收到设备推送事件 ${e.toString()}",
          tag: 'Channel',
        );
        final t = (e['type'] ?? '').toString();
        if (t == 'status') {
          final v = (e['value'] ?? '').toString();
          if (v == 'disconnected' || v == 'ble_powered_off') {
            try {
              await clearScannerAndChannel();
            } catch (_) {}
          }
        }
      });
      _checkGen(ticket); // ✅ 最后再确认一次
      return true;
    } on _CancelledError {
      // 表示这次 use 在过程中被“换代”了（比如上层调用了 dispose）
      try {
        await _creatingChannel?.dispose();
      } catch (_) {}
      _creatingChannel = null;
      return false; // 让上层当成 cancelled 用
    } catch (e) {
      try {
        await clearScannerAndChannel();
      } catch (_) {}
      rethrow;
    } finally {
      _switching = false;
    }
  }

  Stream<Map<String, dynamic>>? get events => _channel?.events;

  /// 最近一次 use()/握手阶段得到的状态（例如：'empty_bound'），否则为 null
  String? get lastHandshakeStatus => _lastHandshakeStatus;

  Future<Map<String, dynamic>> send(
    Map<String, dynamic> msg, {
    Duration? timeout,
    int retries = 0,
    bool Function(Map<String, dynamic>)? isFinal,
  }) async {
    final int ticket = _gen; // 记录发消息时的代数

    final ch = _requireChannel();
    // 1. 确保连接
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? "";
    await ch.ensureAuthenticated(currentUserId);
    _checkGen(ticket); // 中途被 clear/dispose 就直接抛 _CancelledError

    // 2. 发消息
    return ch.send(
      msg,
      timeout: timeout,
      retries: retries,
      isFinal: isFinal,
    );
  }

  /// Send a message only if the current channel is already authenticated/ready.
  /// This method intentionally DOES NOT call ensureAuthenticated(), so it won't trigger reconnection.
  /// Useful for connectivity heartbeat without affecting existing flows.
  Future<Map<String, dynamic>> sendIfReady(
    Map<String, dynamic> msg, {
    Duration? timeout,
    int retries = 0,
    bool Function(Map<String, dynamic>)? isFinal,
  }) async {
    final int ticket = _gen;
    final ch = _requireChannel();
    final resp = await ch.send(
      msg,
      timeout: timeout,
      retries: retries,
      isFinal: isFinal,
    );
    _checkGen(ticket);
    return resp;
  }

  Future<void> dispose() async {
    try {
      await clearScannerAndChannel();
    } catch (_) {}
  }

  SecureChannel _requireChannel() {
    final ch = _channel;
    if (ch == null) {
      throw StateError('SecureChannel 未初始化。请先调用 use(deviceId)');
    }
    return ch;
  }
}
