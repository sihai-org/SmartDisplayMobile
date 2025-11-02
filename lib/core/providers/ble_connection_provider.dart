import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_display_mobile/core/channel/secure_channel_manager_provider.dart';
import 'package:smart_display_mobile/core/providers/app_state_provider.dart';

import '../channel/secure_channel_manager.dart';
import '../ble/ble_device_data.dart';
import '../constants/enum.dart';
import '../network/network_status.dart';
import 'lifecycle_provider.dart';
import '../models/device_qr_data.dart';
import 'saved_devices_provider.dart';
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

/// 当前（绑定中 or 已绑定）设备的相关数据
class BleConnectionState {
  /// 蓝牙
  final BleDeviceData? bleDeviceData;
  final BleDeviceStatus bleDeviceStatus;

  /// wifi
  final List<WifiAp> wifiNetworks; // TODO: 可以放 wifi_selection_page 内部
  final bool isCheckingNetwork; // TODO: 可以放 device_detail_page 内部
  final NetworkStatus? networkStatus; // TODO: 可以放 device_detail_page 内部
  final DateTime? networkStatusUpdatedAt; // TODO: 可以放 device_detail_page 内部

  const BleConnectionState({
    this.bleDeviceData,
    this.bleDeviceStatus = BleDeviceStatus.disconnected,
    this.wifiNetworks = const [],
    this.networkStatus,
    this.isCheckingNetwork = false,
    this.networkStatusUpdatedAt,
  });

  BleConnectionState copyWith({
    BleDeviceData? bleDeviceData,
    BleDeviceStatus? bleDeviceStatus,
    String? errorMessage,
    String? provisionStatus,
    String? lastProvisionDeviceId,
    String? lastProvisionSsid,
    List<WifiAp>? wifiNetworks,
    NetworkStatus? networkStatus,
    bool? isCheckingNetwork,
    DateTime? networkStatusUpdatedAt,
  }) {
    return BleConnectionState(
      bleDeviceData: bleDeviceData ?? this.bleDeviceData,
      bleDeviceStatus: bleDeviceStatus ?? this.bleDeviceStatus,
      wifiNetworks: wifiNetworks ?? this.wifiNetworks,
      networkStatus: networkStatus ?? this.networkStatus,
      isCheckingNetwork: isCheckingNetwork ?? this.isCheckingNetwork,
      networkStatusUpdatedAt:
          networkStatusUpdatedAt ?? this.networkStatusUpdatedAt,
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

    // 2) 只在 manager 实例变化时尝试重绑
    _managerSub = _ref.listen(
      secureChannelManagerProvider,
      (prev, curr) {
        if (!identical(prev, curr)) {
          _attachChannelEvents(curr);
        }
      },
    );
  }

  final Ref _ref;

  ProviderSubscription<bool>? _foregroundSub;
  ProviderSubscription<dynamic /*SecureChannelManager*/ >? _managerSub;
  StreamSubscription<Map<String, dynamic>>? _evtSub;
  Stream<Map<String, dynamic>>? _boundStream; // 记住当前已绑定的事件流

  void _attachChannelEvents(SecureChannelManager manager) {
    final stream = manager.events;

    // 如果新的 manager 没有事件流：取消旧订阅并清空绑定引用
    if (stream == null) {
      _evtSub?.cancel();
      _evtSub = null;
      _boundStream = null;
      _log('事件流不存在（等待 manager 完成 use/握手后由 provider 通知再绑定）');
      return;
    }

    // 同一条流就不重复 listen
    if (identical(stream, _boundStream)) {
      _log('重复的事件流，跳过重绑');
      return;
    }

    // 切换到新流
    _evtSub?.cancel();
    _boundStream = stream;
    _evtSub = stream.listen(
      _handleChannelEvent,
      onError: (e, st) => _log('事件流错误: $e'),
      onDone: () => _log('事件流结束'),
      cancelOnError: false,
    );

    _log('已绑定新的事件流');
  }

  void _handleChannelEvent(Map<String, dynamic> evt) {
    _log('event $evt');
    switch (evt['type']) {
      case 'status':
        final v = (evt['value'] ?? '').toString();
        if (v == 'disconnected' || v == 'ble_powered_off') {
          state = state.copyWith(bleDeviceStatus: BleDeviceStatus.disconnected);
        }
        break;
      default:
        _log('其他事件: $evt');
    }
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
    // 当前选中设备非 auth -> auth：主动同步设备信息
    final nowDisplayDeviceId = next.bleDeviceData?.displayDeviceId;
    final selectedDisplayDeviceId =
        _ref.read(savedDevicesProvider).lastSelectedId;
    final nowSelected = nowDisplayDeviceId != null &&
        nowDisplayDeviceId == selectedDisplayDeviceId;
    final wasAuthed = prev.bleDeviceStatus == BleDeviceStatus.authenticated;
    final nowAuthed = next.bleDeviceStatus == BleDeviceStatus.authenticated;
    if (nowSelected && !wasAuthed && nowAuthed) {
      _syncSelectedWhenAuthed(reason: 'state-transition');
    }
  }

  void _syncSelectedWhenAuthed({required String reason}) {
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
    // 仅当当前设备存在于“设备列表”中时才进行同步（避免与绑定前扫码流程冲突）
    try {
      final deviceId = state.bleDeviceData?.displayDeviceId;
      if (deviceId == null || deviceId.isEmpty) {
        _log('跳过 sync：无有效的设备ID');
        return;
      }
      // 使用 savedDevicesProvider 的内存状态（必要时加载本地缓存）
      final savedNotifier = _ref.read(savedDevicesProvider.notifier);
      var saved = _ref.read(savedDevicesProvider);
      if (!saved.loaded) {
        try { await savedNotifier.load(); } catch (_) {}
        saved = _ref.read(savedDevicesProvider);
      }
      final inList = saved.devices.any((e) => e.displayDeviceId == deviceId);
      if (!inList) {
        _log('跳过 sync：设备不在设备列表中（$deviceId）');
        return;
      }
    } catch (e) {
      // 若本地校验异常，为安全起见不继续同步
      _log('本地设备校验异常，跳过 sync：$e');
      return;
    }
    try {
      final info = await sendBleMsg(
        'device.info',
        null,
        timeout: const Duration(seconds: 3),
        retries: 0,
      );
      if (info is Map<String, dynamic>) {
        // 更新网络状态到连接状态
        state = state.copyWith(
          networkStatus: NetworkStatus.fromJson(info['network']),
          networkStatusUpdatedAt: DateTime.now(),
        );

        // 通过 SavedDevicesNotifier 更新固件版本（仅本地与内存）
        final deviceId = state.bleDeviceData?.displayDeviceId;
        final fw = info['firmwareVersion']?.toString();
        if (deviceId != null && deviceId.isNotEmpty && fw != null) {
          try {
            await _ref
                .read(savedDevicesProvider.notifier)
                .updateFields(displayDeviceId: deviceId, firmwareVersion: fw);
          } catch (e) {
            _log('更新 firmwareVersion 到 SavedDevicesNotifier 失败: $e');
          }
        }
      }
      _log('syncDeviceInfo 完成');
    } catch (e) {
      _log('syncDeviceInfo 失败: $e');
    }
  }

  // TODO: 目前 send 没有 ensure
  // 建立蓝牙连接
  Future<bool> enableBleConnection(DeviceQrData qrData) async {
    final t0 = DateTime.now();
    // 若尚未开始会话，设置一个基准时间用于统一打点
    _sessionStart ??= t0;
    _log('🔌 enableBleConnection 开始');
    try {
      final useRes = await _ref.read(secureChannelManagerProvider).use(qrData);
      if (!useRes) {
        state = state.copyWith(
          bleDeviceStatus: BleDeviceStatus.error,
        );
        return useRes;
      }
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('enableBleConnection.success(${elapsed}ms)');
      state = state.copyWith(
        bleDeviceData: qrDataToDeviceData(qrData),
        bleDeviceStatus: BleDeviceStatus.authenticated,
      );
      return true;
    } catch (e) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('enableBleConnection.fail(${elapsed}ms): $e');
      state = state.copyWith(
        bleDeviceData: qrDataToDeviceData(qrData),
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

  // 配网：等待同一通道的最终 wifi.config 响应（设备端直接回最终结果）
  Future<bool> sendWifiConfig(String ssid, String password) async {
    _log('sendWifiConfig: ssid=$ssid');
    try {
      final data = await sendBleMsg(
        'wifi.config',
        {'ssid': ssid, 'password': password},
        timeout: const Duration(seconds: 10),
      );
      // 成功时设备返回 data: {status: 'connected'}
      if (data is Map<String, dynamic>) {
        final s = data['status']?.toString();
        return s == 'connected';
      }
      return false;
    } catch (e) {
      _log('❌ sendWifiConfig failed: $e');
      return false;
    }
  }

  // 网络状态
  Future<NetworkStatus?> checkNetworkStatus() async {
    if (state.isCheckingNetwork) return null;

    try {
      final data = await sendBleMsg(
        'network.status',
        null,
        timeout: const Duration(milliseconds: 1200),
        retries: 0,
      );
      if (data is Map<String, dynamic>) {
        final ns = NetworkStatus.fromJson(data);
        state = state.copyWith(
          networkStatus: ns,
          networkStatusUpdatedAt: DateTime.now(),
        );
        return ns;
      }
      return null;
    } catch (e) {
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
