// lib/core/secure/secure_channel_manager.dart
import 'dart:async';
import 'package:smart_display_mobile/core/ble/ble_scanner.dart';
import 'package:smart_display_mobile/core/models/device_qr_data.dart';

import 'secure_channel.dart';

typedef SecureChannelFactory = SecureChannel Function(
    String displayDeviceId, String bleDeviceId);

class SecureChannelManager {
  SecureChannelManager(this._factory, this._scanner);

  bool _switching = false;

  final SecureChannelFactory _factory;

  final BleScanner _scanner;

  String? _bleDeviceId; //  标记 channel 的 bleDeviceId
  SecureChannel? _channel;

  /// 将全局通道切换到指定设备；相同设备则复用
  Future<void> use(DeviceQrData qrData) async {
    final targetDisplayDeviceId = qrData.displayDeviceId;
    final targetBleDeviceId = await _scanner.findBleAddress(qrData);
    if (targetBleDeviceId == null) {
      // TODO: 找不到目标设备（扫描失败）
      return;
    }

    if (_bleDeviceId == targetBleDeviceId && _channel != null) {
      // 复用原通道（可选择触发一次 ensure）
      return;
    }
    // 并发保护
    while (_switching) {
      await Future.delayed(const Duration(milliseconds: 60));
    }
    _switching = true;
    try {
      // 先清理旧通道
      await _channel?.dispose();
      _channel = null;

      // 创建新通道
      final ch = _factory(targetDisplayDeviceId, targetBleDeviceId);
      _channel = ch;
      _bleDeviceId = targetBleDeviceId;

      // 连上
      await ch.ensureAuthenticated();
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
    await ch.ensureAuthenticated();
    // 2. 发消息
    return ch.send(msg, timeout: timeout, retries: retries, isFinal: isFinal);
  }

  Future<void> dispose() async {
    await _channel?.dispose();
    _channel = null;
    _bleDeviceId = null;
  }

  SecureChannel _requireChannel() {
    final ch = _channel;
    if (ch == null) {
      throw StateError('SecureChannel 未初始化。请先调用 use(deviceId)');
    }
    return ch;
  }
}
