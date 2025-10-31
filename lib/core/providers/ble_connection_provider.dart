import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_display_mobile/core/channel/secure_channel_manager_provider.dart';

import '../channel/secure_channel_manager.dart';
import '../ble/ble_device_data.dart';
import '../constants/result.dart';
import '../network/network_status.dart';
import 'lifecycle_provider.dart';
import '../models/device_qr_data.dart';
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

/// 蓝牙连接相关数据
class BleConnectionState {
  /// 蓝牙
  final BleDeviceStatus bleDeviceStatus;
  final BleDeviceData? bleDeviceData;
  final String? lastHandshakeErrorCode;
  final String? lastHandshakeErrorMessage;
  final int authRev;

  /// 配网
  final String? provisionStatus;
  final String? lastProvisionDeviceId;
  final String? lastProvisionSsid;
  final List<WifiAp> wifiNetworks;
  final NetworkStatus? networkStatus;
  final bool isCheckingNetwork;
  final DateTime? networkStatusUpdatedAt;
  /// 版本
  final String? firmwareVersion;

  const BleConnectionState({
    this.bleDeviceStatus = BleDeviceStatus.disconnected,
    this.bleDeviceData,
    this.lastHandshakeErrorCode,
    this.lastHandshakeErrorMessage,
    this.authRev = 0,
    this.provisionStatus,
    this.lastProvisionDeviceId,
    this.lastProvisionSsid,
    this.wifiNetworks = const [],
    this.networkStatus,
    this.isCheckingNetwork = false,
    this.networkStatusUpdatedAt,
    this.firmwareVersion,
  });

  BleConnectionState copyWith({
    BleDeviceStatus? bleDeviceStatus,
    BleDeviceData? bleDeviceData,
    String? lastHandshakeErrorCode,
    String? lastHandshakeErrorMessage,
    int? authRev,
    String? errorMessage,
    String? provisionStatus,
    String? lastProvisionDeviceId,
    String? lastProvisionSsid,
    List<WifiAp>? wifiNetworks,
    NetworkStatus? networkStatus,
    bool? isCheckingNetwork,
    DateTime? networkStatusUpdatedAt,
    String? firmwareVersion,
  }) {
    return BleConnectionState(
      bleDeviceStatus: bleDeviceStatus ?? this.bleDeviceStatus,
      bleDeviceData: bleDeviceData ?? this.bleDeviceData,
      lastHandshakeErrorCode:
          lastHandshakeErrorCode ?? this.lastHandshakeErrorCode,
      lastHandshakeErrorMessage:
          lastHandshakeErrorMessage ?? this.lastHandshakeErrorMessage,
      authRev: authRev ?? this.authRev,
      provisionStatus: provisionStatus ?? this.provisionStatus,
      lastProvisionDeviceId:
          lastProvisionDeviceId ?? this.lastProvisionDeviceId,
      lastProvisionSsid: lastProvisionSsid ?? this.lastProvisionSsid,
      wifiNetworks: wifiNetworks ?? this.wifiNetworks,
      networkStatus: networkStatus ?? this.networkStatus,
      isCheckingNetwork: isCheckingNetwork ?? this.isCheckingNetwork,
      networkStatusUpdatedAt:
          networkStatusUpdatedAt ?? this.networkStatusUpdatedAt,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
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
            // TODO
            break;
          case 'wifi.result':
            // TODO: status: 'connected'
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

  // 每次蓝牙连接后自动同步设备信息
  DateTime? _lastSyncAt;

  Duration _minSyncGap = Duration(seconds: 1);

  @override
  set state(BleConnectionState next) {
    final prev = super.state;
    super.state = next;

    _onStateChanged(prev, next);
  }

  void _onStateChanged(BleConnectionState prev, BleConnectionState next) {
    final wasAuthed = prev.bleDeviceStatus == BleDeviceStatus.authenticated;
    final nowAuthed = next.bleDeviceStatus == BleDeviceStatus.authenticated;
    // 兜底：非 auth -> auth 过渡触发
    if (!wasAuthed && nowAuthed) {
      _syncWhenAuthed(reason: 'state-transition');
    }
  }

  void _syncWhenAuthed({required String reason}) {
    final now = DateTime.now();
    if (_lastSyncAt != null && now.difference(_lastSyncAt!) < _minSyncGap) {
      _log('syncDeviceInfo 被合并（$reason）');
      return;
    }
    _lastSyncAt = now;
    _log('触发 syncDeviceInfo（$reason）');
    _syncDeviceInfo().catchError((e, st) => _log('sync 异常: $e'));
  }

  Future<void> _syncDeviceInfo() async {
    _log('开始 syncDeviceInfo');
    try {
      final info = await sendBleMsg(
        'device.info',
        null,
        timeout: const Duration(seconds: 3),
        retries: 0,
      );
      if (info is Map<String, dynamic>) {
        state = state.copyWith(
          firmwareVersion: info['firmwareVersion'],
          networkStatus: NetworkStatus.fromJson(info['network']),
          networkStatusUpdatedAt: DateTime.now(),
        );
      }
      _log('syncDeviceInfo 完成');
    } catch (e) {
      _log('syncDeviceInfo 失败: $e');
    }
  }

  // 建立蓝牙连接
  Future<bool> enableBleConnection(DeviceQrData qrData) async {
    final t0 = DateTime.now();
    // 若尚未开始会话，设置一个基准时间用于统一打点
    _sessionStart ??= t0;
    _log('🔌 enableBleConnection 开始');
    try {
      await _ref.read(secureChannelManagerProvider).use(qrData);
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('enableBleConnection.success(${elapsed}ms)');
      state = state.copyWith(
          bleDeviceStatus: BleDeviceStatus.authenticated,
          bleDeviceData: qrDataToDeviceData(qrData));
      return true;
    } catch (e) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('enableBleConnection.fail(${elapsed}ms): $e');
      state = state.copyWith(
        bleDeviceStatus: BleDeviceStatus.error,
      );
      return false;
    }
  }

  Future<bool> handleUserEnableBleConnection(DeviceQrData qrData) async {
    state = state.copyWith(
        bleDeviceStatus: BleDeviceStatus.scanning
    );
    return await enableBleConnection(qrData);
  }

  Future<void> handleUserDisableBleConnection() async {
    disconnect(shouldReset: false);
  }

  // 应用进入前台自动连接蓝牙
  Future<void> handleEnterForeground() async {
    if (state.bleDeviceStatus == BleDeviceStatus.authenticated) return;
    final d = state.bleDeviceData;
    if (d != null) {
      try {
        state = state.copyWith(
            bleDeviceStatus: BleDeviceStatus.scanning
        );
        await enableBleConnection(deviceDataToQrData(d));
      } catch (_) {}
    }
  }

  // /// 蓝牙建连后自动同步 wifi
  // Future<void> handleWifiSmartly() async {
  //   await checkNetworkStatus();
  // }

  /// 扫码连接
  Future<bool> startConnection(DeviceQrData qrData) async {
    // Reset per-session caches to avoid stale data from previous device
    _lastNetworkStatusReadAt = null;
    _inflightNetworkStatusRead = null;
    _postProvisionPoll = null;

    return await enableBleConnection(qrData);
  }

  // 用户发送蓝牙消息 1/2：【简单版】返回成功与否
  Future<bool> sendSimpleBleMsg(String type, dynamic? data) async {
    _log('sendPureBleMsg: $type, $data');
    try {
      final resp = await _ref
          .read(secureChannelManagerProvider)
          .send({'type': type, 'data': data});
      _log('✅ sendPureBleMsg 成功: type=$type, resp=$resp');
      return resp['ok'] == true;
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
    final resp = await _ref
        .read(secureChannelManagerProvider).send(
        {'type': type, 'data': data},
        timeout: timeout, retries: retries, isFinal: isFinal);
    _log('✅ sendBleMsg 成功: type=$type, resp=$resp');
    return resp['data'];
  }

  // 绑定
  Future<bool> sendDeviceLoginCode(String email, String code) async {
    _log('sendDeviceLoginCode email=$email');
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
  Future<DeviceUpdateVersionResult> requestUpdateCheck() async {
    try {
      final res = await sendBleMsg(
        'update.version',
        null,
        timeout: const Duration(seconds: 5),
        retries: 0,
      );
      final s = (res is String) ? res : res?.toString();
      _log('🔗 更新结果: $s');
      if (s == 'update_updating') return DeviceUpdateVersionResult.updating;
      if (s == 'update_latest') return DeviceUpdateVersionResult.latest;
      return DeviceUpdateVersionResult.failed;
    } catch (e) {
      _log('❌ update.version 失败: $e');
      // 异常时及时结束 loading
      return DeviceUpdateVersionResult.failed;
    }
  }

  void _log(String msg) {
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
      state = state.copyWith(bleDeviceStatus: BleDeviceStatus.disconnected);
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
