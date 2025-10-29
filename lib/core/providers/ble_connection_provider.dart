import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:smart_display_mobile/core/providers/secure_channel_manager_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../channel/secure_channel_manager.dart';
import '../constants/ble_constants.dart';
import '../crypto/crypto_service.dart';
import '../ble/ble_device_data.dart';
import '../network/network_status.dart';
import '../ble/ble_service_simple.dart';
import '../ble/reliable_queue.dart';
import 'lifecycle_provider.dart';
import '../models/device_qr_data.dart';
import 'saved_devices_provider.dart';
import 'secure_channel_manager_provider.dart';
import '../utils/data_transformer.dart';

class WifiAp {
  final String ssid;
  final int rssi;
  final bool secure;
  final String? bssid;
  final int? frequency;

  const WifiAp({
    required this.ssid,
    required this.rssi,
    required this.secure,
    this.bssid,
    this.frequency,
  });
}

/// 蓝牙连接状态数据
class BleConnectionState {
  // 蓝牙状态
  final BleDeviceStatus bleDeviceStatus;

  // 蓝牙信息
  final BleDeviceData? bleDeviceData;

  // TODO: 暂未处理
  // 蓝牙报错
  final String? errorMessage;

  final String? provisionStatus;
  final String? lastProvisionDeviceId;
  final String? lastProvisionSsid;
  final List<WifiAp> wifiNetworks;
  final List<String> connectionLogs;
  final NetworkStatus? networkStatus;
  final bool isCheckingNetwork;
  final DateTime? networkStatusUpdatedAt;
  final String? firmwareVersion;
  final String? lastHandshakeErrorCode;
  final String? lastHandshakeErrorMessage;

  // Update check UI state
  final bool isCheckingUpdate;

  const BleConnectionState({
    this.bleDeviceStatus = BleDeviceStatus.disconnected,
    this.bleDeviceData,
    this.errorMessage,
    this.provisionStatus,
    this.lastProvisionDeviceId,
    this.lastProvisionSsid,
    this.wifiNetworks = const [],
    this.connectionLogs = const [],
    this.networkStatus,
    this.isCheckingNetwork = false,
    this.networkStatusUpdatedAt,
    this.firmwareVersion,
    this.lastHandshakeErrorCode,
    this.lastHandshakeErrorMessage,
    this.isCheckingUpdate = false,
  });

  BleConnectionState copyWith({
    BleDeviceStatus? status,
    BleDeviceData? deviceData,
    String? errorMessage,
    String? provisionStatus,
    String? lastProvisionDeviceId,
    String? lastProvisionSsid,
    List<WifiAp>? wifiNetworks,
    List<String>? connectionLogs,
    NetworkStatus? networkStatus,
    bool? isCheckingNetwork,
    DateTime? networkStatusUpdatedAt,
    String? firmwareVersion,
    String? lastHandshakeErrorCode,
    String? lastHandshakeErrorMessage,
    bool? isCheckingUpdate,
  }) {
    return BleConnectionState(
      bleDeviceStatus: status ?? this.bleDeviceStatus,
      bleDeviceData: deviceData ?? this.bleDeviceData,
      errorMessage: errorMessage ?? this.errorMessage,
      provisionStatus: provisionStatus ?? this.provisionStatus,
      lastProvisionDeviceId:
          lastProvisionDeviceId ?? this.lastProvisionDeviceId,
      lastProvisionSsid: lastProvisionSsid ?? this.lastProvisionSsid,
      wifiNetworks: wifiNetworks ?? this.wifiNetworks,
      connectionLogs: connectionLogs ?? this.connectionLogs,
      networkStatus: networkStatus ?? this.networkStatus,
      isCheckingNetwork: isCheckingNetwork ?? this.isCheckingNetwork,
      networkStatusUpdatedAt:
          networkStatusUpdatedAt ?? this.networkStatusUpdatedAt,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      lastHandshakeErrorCode:
          lastHandshakeErrorCode ?? this.lastHandshakeErrorCode,
      lastHandshakeErrorMessage:
          lastHandshakeErrorMessage ?? this.lastHandshakeErrorMessage,
      isCheckingUpdate: isCheckingUpdate ?? this.isCheckingUpdate,
    );
  }
}

/// 蓝牙连接管理器
class BleConnectionNotifier extends StateNotifier<BleConnectionState> {
  BleConnectionNotifier(this._ref) : super(const BleConnectionState()) {
    // 1) 前后台监听（回到前台时尝试确保可信通道）
    _foregroundSub = _ref.listen<bool>(isForegroundProvider, (prev, curr) {
      if (curr == true) handleEnterForeground();
    });

    // 2) 监听 secureChannelManagerProvider 的变更，重绑事件
    _managerSub = _ref.listen(
      secureChannelManagerProvider,
      (prev, curr) => _attachChannelEvents(curr),
    );

    // 3) 初始化也尝试一次（以防 provider 中已经有实例）
    _attachChannelEvents(_ref.read(secureChannelManagerProvider));
  }

  final Ref _ref;

  ProviderSubscription<bool>? _foregroundSub;
  ProviderSubscription<dynamic /*SecureChannelManager*/ >? _managerSub;
  StreamSubscription<Map<String, dynamic>>? _evtSub;

  void _attachChannelEvents(SecureChannelManager manager) {
    // 先取消旧订阅
    _evtSub?.cancel();
    _evtSub = null;

    final stream = manager.events; // 非空/可空看你的定义，下面小心判断
    if (stream == null) {
      _log('事件流不存在（manager还未完成use/握手？）');
      return;
    }

    _evtSub = stream.listen(
      (evt) {
        _log('event $evt');
        switch (evt['type']) {
          case 'status':
            // TODO: status: 'wifi_online' | 'update_updating' | 'update_latest'
            break;
          case 'wifi.result':
            // TODO: status: 'connected'
            break;
          default:
            _log('其他事件: $evt');
        }
      },
      onError: (e, st) {
        _log('事件流错误: $e');
        // 不 cancel；等待 manager 变化重绑
      },
      onDone: () {
        _log('事件流结束');
        // 不在这里重绑，等 provider/manager 变化后再 attach
      },
      cancelOnError: false,
    );
  }

  // Network status read de-dup & throttle
  DateTime? _lastNetworkStatusReadAt;
  Future<NetworkStatus?>? _inflightNetworkStatusRead;

  // 打点
  DateTime? _sessionStart;

  // 配网后轮询
  Future<void>? _postProvisionPoll;

  // 建立蓝牙连接
  Future<bool> enableBleConnection(DeviceQrData qrData) async {
    try {
      await _ref.read(secureChannelManagerProvider).use(qrData);
      return true;
    } catch (_) {
      // TODO state
      return false;
    }
  }

  // 应用进入前台自动连接蓝牙
  Future<void> handleEnterForeground() async {
    if (state.bleDeviceStatus == BleDeviceStatus.authenticated) return;
    final d = state.bleDeviceData;
    if (d != null) {
      try {
        await enableBleConnection(deviceDataToQrData(d));
      } catch (_) {}
    }
  }

  /// 蓝牙建连后自动同步 wifi
  Future<void> handleWifiSmartly() async {
    await checkNetworkStatus();
  }

  /// 扫码连接
  Future<void> startConnection(DeviceQrData qrData) async {
    // Reset per-session caches to avoid stale data from previous device
    _lastNetworkStatusReadAt = null;
    _inflightNetworkStatusRead = null;
    _postProvisionPoll = null;

    try {
      await enableBleConnection(qrData);
    } catch (_) {}
  }

  // 用户发送蓝牙消息 1/2：【简单版】返回成功与否
  Future<bool> sendSimpleBleMsg(String type, dynamic? data) async {
    _log('sendPureBleMsg: $type, $data');
    try {
      final payload = {'type': type};
      if (data != null) {
        payload['data'] = data;
      }
      final resp = await _ref.read(secureChannelManagerProvider).send(payload);
      _log('✅ sendPureBleMsg 成功: type=$type, resp=$resp');
      return resp['ok'] == true || resp['type'] == type;
    } catch (e) {
      _log('❌ sendPureBleMsg 失败: $e');
      return false;
    }
  }

  // 用户发送蓝牙消息 2/2：【复杂版】返回 data，调用处自己 catch
  Future<dynamic> sendBleMsg(
    String type,
    dynamic? data, {
    Duration? timeout,
    int retries = 0,
    bool Function(Map<String, dynamic>)? isFinal,
  }) async {
    _log('sendBleMsg: $type, $data');
    final payload = {'type': type};
    if (data != null) {
      payload['data'] = data;
    }
    final resp = await _ref
        .read(secureChannelManagerProvider)
        .send(payload, timeout: timeout, retries: retries, isFinal: isFinal);
    _log('✅ sendBleMsg 成功: type=$type, resp=$resp');
    return resp['data'];
  }

  // 绑定
  Future<bool> sendDeviceLoginCode(String email, String code) async {
    return await sendSimpleBleMsg(
        'login.auth', {'email': email, 'otpToken': code});
  }

  // 解绑
  Future<bool> sendDeviceLogout() async {
    return await sendSimpleBleMsg('logout', null);
  }

  // 可用 wifi
  Future<bool> requestWifiScan() async {
    try {
      _log('⏳ 开始扫描附近Wi-Fi...');
      final data = await sendBleMsg(
        'wifi.scan',
        null,
        timeout: const Duration(seconds: 3),
        retries: 0,
      );
      if (data is List) {
        final networks = data
            .map((e) => WifiAp(
                  ssid: (e['ssid'] ?? '').toString(),
                  rssi: int.tryParse((e['rssi'] ?? '0').toString()) ?? 0,
                  secure: (e['secure'] == true),
                  bssid: e['bssid']?.toString(),
                  frequency: int.tryParse((e['frequency'] ?? '').toString()),
                ))
            .toList();
        state = state.copyWith(wifiNetworks: networks);
        _log('📶 Wi-Fi 扫描完成，发现 ${networks.length} 个网络');
      }
      return true;
    } catch (e) {
      _log('❌ wifi.scan 失败: $e');
      return false;
    }
  }

  // 配网（并轮询网络连接状态）
  Future<bool> sendProvisionRequest({
    required String ssid,
    required String password,
  }) async {
    try {
      final currId = state.bleDeviceData!.displayDeviceId;
      state = state.copyWith(
        provisionStatus: 'provisioning',
        lastProvisionDeviceId: currId,
        lastProvisionSsid: ssid,
      );
      final ok = await sendSimpleBleMsg(
          'wifi.config', {'ssid': ssid, 'password': password});
      if (!ok) state = state.copyWith(provisionStatus: 'failed');
      _kickoffPostProvisionPolling();
      return ok;
    } catch (e) {
      _log('❌ wifi.config 失败: $e');
      state = state.copyWith(provisionStatus: 'failed');
      return false;
    }
  }

  void _kickoffPostProvisionPolling() {
    if (_postProvisionPoll != null) return;
    _postProvisionPoll = () async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      var delay = const Duration(milliseconds: 800);
      while (DateTime.now().isBefore(deadline)) {
        final ns = await _doReadNetworkStatus();
        if (ns?.connected == true) break;
        await Future.delayed(delay);
        final nextMs = (delay.inMilliseconds * 1.5).toInt();
        delay = Duration(milliseconds: nextMs > 3000 ? 3000 : nextMs);
      }
      if (state.provisionStatus == 'provisioning') {
        state = state.copyWith(
          provisionStatus: 'wifi_offline',
          lastProvisionDeviceId: state.bleDeviceData?.displayDeviceId ??
              state.lastProvisionDeviceId,
        );
      }
      _postProvisionPoll = null;
    }();
  }

  // 网络状态（节流 + 并发保护）
  Future<NetworkStatus?> checkNetworkStatus() async {
    final now = DateTime.now();
    // 防抖
    if (_lastNetworkStatusReadAt != null &&
        now.difference(_lastNetworkStatusReadAt!) <
            const Duration(milliseconds: 400)) {
      return state.networkStatus;
    }
    // 并发保护
    if (_inflightNetworkStatusRead != null) {
      return _inflightNetworkStatusRead;
    }
    state = state.copyWith(isCheckingNetwork: true);
    _lastNetworkStatusReadAt = now;
    final future = _doReadNetworkStatus();
    _inflightNetworkStatusRead = future;
    final res = await future;
    _inflightNetworkStatusRead = null;
    state = state.copyWith(isCheckingNetwork: false);
    return res;
  }

  Future<NetworkStatus?> _doReadNetworkStatus() async {
    try {
      final t0 = DateTime.now();
      final data = await sendBleMsg(
        'network.status',
        null,
        timeout: const Duration(milliseconds: 1200),
        retries: 0,
      );
      _logWithTime(
          'network.status.rq.done(${DateTime.now().difference(t0).inMilliseconds}ms)');
      if (data is Map<String, dynamic>) {
        final ns = NetworkStatus.fromJson(data);
        state = state.copyWith(
            networkStatus: ns, networkStatusUpdatedAt: DateTime.now());
        if (state.provisionStatus == 'provisioning' && ns.connected) {
          final reqSsid = state.lastProvisionSsid?.trim();
          final currSsid = ns.displaySsid?.trim() ?? ns.ssid?.trim();
          final ssidMatches = reqSsid != null &&
              reqSsid.isNotEmpty &&
              currSsid != null &&
              currSsid.isNotEmpty &&
              currSsid == reqSsid;
          if (ssidMatches) {
            state = state.copyWith(
              provisionStatus: 'wifi_online',
              lastProvisionDeviceId: state.bleDeviceData?.displayDeviceId ??
                  state.lastProvisionDeviceId,
            );
          }
        }
        return ns;
      }
      return null;
    } catch (e) {
      _logWithTime('network.status.error(${e.runtimeType})');
      return null;
    }
  }

  /// 版本更新（参考 requestWifiScan 的通道确保逻辑）
  Future<bool> requestUpdateCheck() async {
    try {
      // 1) 立即进入“检查更新中”以显示 loading（包含后续连接/握手时间）
      state = state.copyWith(isCheckingUpdate: true);

      // 3) 发送检查更新指令；设备将通过事件推送 update_updating / update_latest 来结束 loading
      final ok = await sendSimpleBleMsg('update.version', null);
      if (!ok) {
        // 若请求未被设备接受，及时结束 loading
        state = state.copyWith(isCheckingUpdate: false);
      }
      return ok;
    } catch (e) {
      _log('❌ update.version 失败: $e');
      // 异常时及时结束 loading
      state = state.copyWith(isCheckingUpdate: false);
      return false;
    }
  }

  static const int _maxConnectionLogs = 200;

  void _log(String msg) {
    final now = DateTime.now().toIso8601String();
    final nextLogs = [...state.connectionLogs, "[$now] $msg"];
    final trimmedLogs = nextLogs.length > _maxConnectionLogs
        ? nextLogs.sublist(nextLogs.length - _maxConnectionLogs)
        : nextLogs;
    state = state.copyWith(connectionLogs: trimmedLogs);
    developer.log(msg, name: 'BLE');
  }

  void _logWithTime(String label) {
    final now = DateTime.now();
    if (_sessionStart != null) {
      final ms = now.difference(_sessionStart!).inMilliseconds;
      _log('⏱ [$ms ms] $label');
    } else {
      _log('⏱ $label');
    }
  }

  /// 断开 BLE、清理会话与加密器，并重置为 disconnected
  Future<void> disconnect({shouldReset = true}) async {
    await _ref.read(secureChannelManagerProvider).dispose();
    if (shouldReset) {
      resetState();
    } else {
      state = state.copyWith(status: BleDeviceStatus.disconnected);
    }
  }

  void resetState() {
    // Clear per-session caches/state
    _lastNetworkStatusReadAt = null;
    _inflightNetworkStatusRead = null;
    _postProvisionPoll = null;
    _sessionStart = null;
    state = const BleConnectionState();
  }

  @override
  void dispose() {
    _evtSub?.cancel();
    _managerSub?.close();
    _foregroundSub?.close();
    super.dispose();
  }
}

final bleConnectionProvider =
    StateNotifierProvider<BleConnectionNotifier, BleConnectionState>((ref) {
  final notifier = BleConnectionNotifier(ref);
  ref.onDispose(() => notifier.dispose());
  return notifier;
});
