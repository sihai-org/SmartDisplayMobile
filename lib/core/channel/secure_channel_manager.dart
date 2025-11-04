// lib/core/secure/secure_channel_manager.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_display_mobile/core/ble/ble_scanner.dart';
import 'package:smart_display_mobile/core/models/device_qr_data.dart';

import 'secure_channel.dart';

typedef SecureChannelFactory = SecureChannel Function(
    String displayDeviceId, String bleDeviceId, String devicePublicKeyHex);

class SecureChannelManager {
  SecureChannelManager(this._factory, this._scanner);

  // user id should be read at call time to avoid stale cache

  bool _switching = false;

  final SecureChannelFactory _factory;

  final BleScanner _scanner;

  String? _bleDeviceId; //  标记 channel 的 bleDeviceId
  SecureChannel? _channel;
  StreamSubscription<Map<String, dynamic>>? _channelEvtSub;

  Future<void> clearScannerAndChannel() async {
    try {
      await _scanner?.stop();
    } catch (_) {}
    try {
      await _channelEvtSub?.cancel();
    } catch (_) {}
    _channelEvtSub = null;
    try {
      await _channel?.dispose();
    } catch (_) {}
    _channel = null;
    _bleDeviceId = null;
  }

  /// 将全局通道切换到指定设备；相同设备则复用
  Future<bool> use(DeviceQrData qrData) async {
    final targetDisplayDeviceId = qrData.displayDeviceId;
    final targetDevicePublicKeyHex = qrData.publicKey;

    // 并发保护（从这里开始包含复用与新建逻辑）
    while (_switching) {
      await Future.delayed(const Duration(milliseconds: 60));
    }
    _switching = true;
    SecureChannel? creating; // 记录正在创建但尚未绑定到 _channel 的实例，失败时及时释放
    try {
      final String targetBleDeviceId = await _scanner.findBleDeviceId(qrData);
      // 同设备尝试复用，但必须确保已认证
      if (_bleDeviceId == targetBleDeviceId && _channel != null) {
        final currentUserId =
            Supabase.instance.client.auth.currentUser?.id ?? "";
        try {
          await _channel!.ensureAuthenticated(currentUserId);
          return true; // 确认已认证才复用
        } catch (_) {
          await clearScannerAndChannel(); // 复用失败，清理后走新建
        }
      }

      // 创建新通道
      final ch = _factory(
          targetDisplayDeviceId, targetBleDeviceId, targetDevicePublicKeyHex);
      creating = ch; // 标记为正在创建，确保失败时能 dispose
      // 连上（读取最新 userId，避免缓存过期）
      final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? "";
      await ch.ensureAuthenticated(currentUserId);

      // 赋值前先解绑旧监听（保证一致性）
      try {
        await _channelEvtSub?.cancel();
      } catch (_) {}
      _channelEvtSub = null;

      _bleDeviceId = targetBleDeviceId;
      _channel = ch;
      // 监听断开/蓝牙关闭，立刻清理引用
      _channelEvtSub = ch.events.listen((e) async {
        print("=============设备测推送事件 ${e.toString()}");
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

      return true;
    } catch (e) {
      // 将异常交由调用方处理（由上层 provider 映射错误码/文案），并清理引用
      try {
        // 若在 ensureAuthenticated 期间失败（例如 user_mismatch），
        // creating 还未赋值到 _channel，需要主动释放以立刻断开 BLE
        await creating?.dispose();
      } catch (_) {}
      try {
        await clearScannerAndChannel();
      } catch (_) {}
      rethrow;
    } finally {
      _switching = false;
    }
  }

  Stream<Map<String, dynamic>>? get events => _channel?.events;

  Future<Map<String, dynamic>> send(
    Map<String, dynamic> msg, {
    Duration? timeout,
    int retries = 0,
    bool Function(Map<String, dynamic>)? isFinal,
  }) async {
    final ch = _requireChannel();
    // 1. 确保连接
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? "";
    await ch.ensureAuthenticated(currentUserId);
    // 2. 发消息
    return ch.send(msg, timeout: timeout, retries: retries, isFinal: isFinal);
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
