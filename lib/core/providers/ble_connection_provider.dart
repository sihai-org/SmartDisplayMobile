import 'dart:async';
import 'package:smart_display_mobile/core/utils/device_update_result.dart';

import '../log/app_log.dart';
import '../log/device_onboarding_log.dart';
import '../log/device_onboarding_events.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_display_mobile/core/channel/secure_channel_manager_provider.dart';

import '../channel/secure_channel_manager.dart';
import '../ble/reliable_queue.dart';
import '../ble/ble_device_data.dart';
import '../constants/enum.dart';
import '../constants/ble_constants.dart';
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
  final bool enableBleConnectionLoading;
  final bool emptyBound; // 握手后设备同步自身状态

  /// wifi
  final List<WifiAp> wifiNetworks; // TODO: 可以放 wifi_selection_page 内部
  final bool isScanningWifi;
  final DateTime? wifiScanUpdatedAt;
  final bool isCheckingNetwork; // TODO: 可以放 device_detail_page 内部
  final NetworkStatus? networkStatus; // TODO: 可以放 device_detail_page 内部
  final DateTime? networkStatusUpdatedAt; // TODO: 可以放 device_detail_page 内部

  const BleConnectionState({
    this.bleDeviceData,
    this.bleDeviceStatus = BleDeviceStatus.disconnected,
    this.enableBleConnectionLoading = false,
    this.emptyBound = false,
    this.wifiNetworks = const [],
    this.networkStatus,
    this.isScanningWifi = false,
    this.wifiScanUpdatedAt,
    this.isCheckingNetwork = false,
    this.networkStatusUpdatedAt,
  });

  BleConnectionState copyWith({
    BleDeviceData? bleDeviceData,
    BleDeviceStatus? bleDeviceStatus,
    bool? enableBleConnectionLoading,
    bool? emptyBound,
    String? errorMessage,
    String? provisionStatus,
    String? lastProvisionDeviceId,
    String? lastProvisionSsid,
    List<WifiAp>? wifiNetworks,
    NetworkStatus? networkStatus,
    bool? isScanningWifi,
    DateTime? wifiScanUpdatedAt,
    bool? isCheckingNetwork,
    DateTime? networkStatusUpdatedAt,
  }) {
    return BleConnectionState(
      bleDeviceData: bleDeviceData ?? this.bleDeviceData,
      bleDeviceStatus: bleDeviceStatus ?? this.bleDeviceStatus,
      enableBleConnectionLoading:
          enableBleConnectionLoading ?? this.enableBleConnectionLoading,
      emptyBound: emptyBound ?? this.emptyBound,
      wifiNetworks: wifiNetworks ?? this.wifiNetworks,
      networkStatus: networkStatus ?? this.networkStatus,
      isScanningWifi: isScanningWifi ?? this.isScanningWifi,
      wifiScanUpdatedAt: wifiScanUpdatedAt ?? this.wifiScanUpdatedAt,
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
      if (prev == false && curr == true) {
        // 先不自动连接了
      }
    });

    // 2) 只在 manager 实例变化时尝试重绑
    _managerSub = _ref.listen(secureChannelManagerProvider, (prev, curr) {
      if (!identical(prev, curr)) {
        _attachChannelEvents(curr);
      }
    });

    // 3) 心跳：仅用于“状态纠偏”，不触发重连；失败达到阈值则走现有断开清理链路
    _heartbeatTimer = Timer.periodic(
      BleConstants.kHeartbeatTickInterval,
      (_) => _tickHeartbeat(),
    );
  }

  final Ref _ref;
  int _sessionCount = 0;

  ProviderSubscription<bool>? _foregroundSub;
  ProviderSubscription<dynamic /*SecureChannelManager*/>? _managerSub;
  StreamSubscription<Map<String, dynamic>>? _evtSub;
  Stream<Map<String, dynamic>>? _boundStream; // 记住当前已绑定的事件流

  Timer? _heartbeatTimer;
  int _activeOps = 0;
  DateTime? _lastActivityAt;
  DateTime? _lastHeartbeatAt;
  int _heartbeatFailures = 0;
  int _heartbeatSeq = 0;

  bool get _isMounted => mounted;

  void _setStateSafely(BleConnectionState next, {String? reason}) {
    if (!_isMounted) {
      if (reason != null) {
        _log('忽略 dispose 后的状态更新: $reason');
      }
      return;
    }
    super.state = next;
  }

  void _updateStateSafely(
    BleConnectionState Function(BleConnectionState current) update, {
    String? reason,
  }) {
    if (!_isMounted) {
      if (reason != null) {
        _log('忽略 dispose 后的状态更新: $reason');
      }
      return;
    }
    super.state = update(super.state);
  }

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
    if (!_isMounted) return;
    _log('=============[_handleChannelEvent] event $evt');
    switch (evt['type']) {
      case 'status':
        final v = (evt['value'] ?? '').toString();
        if (v == 'disconnected' || v == 'ble_powered_off') {
          state = state.copyWith(bleDeviceStatus: BleDeviceStatus.disconnected);
          // 确保彻底中止扫描/连接，防止 UI 退出后仍继续连接
          // try { _ref.read(secureChannelManagerProvider).dispose(); } catch (_) {}
        }
        break;
      default:
        _log('其他事件: $evt');
    }
  }

  bool _shouldHeartbeatNow(DateTime now) {
    if (state.bleDeviceStatus != BleDeviceStatus.authenticated) return false;
    if (state.enableBleConnectionLoading) return false;
    if (state.isScanningWifi) return false;
    if (state.isCheckingNetwork) return false;
    if (_activeOps != 0) return false;

    final lastAct = _lastActivityAt;
    if (lastAct != null &&
        now.difference(lastAct) < BleConstants.kHeartbeatIdleBeforeSend) {
      return false;
    }
    final lastHb = _lastHeartbeatAt;
    if (lastHb != null &&
        now.difference(lastHb) < BleConstants.kHeartbeatInterval) {
      return false;
    }
    return true;
  }

  Future<void> _tickHeartbeat() async {
    final now = DateTime.now();
    if (!_shouldHeartbeatNow(now)) return;

    final int session = _sessionCount;
    _activeOps++;
    _lastHeartbeatAt = now;
    _heartbeatSeq += 1;
    _log('心跳开始(#$_heartbeatSeq) device.info');
    try {
      // 使用现有 device.info 作为联通检测，但不更新业务状态，也不触发 ensure/reconnect
      await _ref
          .read(secureChannelManagerProvider)
          .sendIfReady(
            {'type': 'device.info', 'data': null},
            timeout: BleConstants.kHeartbeatTimeout,
            retries: 0,
          );
      if (session != _sessionCount) return;
      if (_heartbeatFailures > 0 || (_heartbeatSeq % 10 == 0)) {
        _log('心跳成功(#$_heartbeatSeq)');
      }
      _heartbeatFailures = 0;
    } catch (e) {
      if (session != _sessionCount) return;
      _heartbeatFailures += 1;
      _log(
        '心跳失败($_heartbeatFailures/${BleConstants.kHeartbeatFailThreshold}): $e',
      );
      if (_heartbeatFailures >= BleConstants.kHeartbeatFailThreshold) {
        _heartbeatFailures = 0;
        _log('心跳判定失联：执行断开清理（等价用户手动断开）');
        await disconnect(shouldReset: true);
      }
    } finally {
      _activeOps--;
    }
  }

  // 打点
  DateTime? _sessionStart;

  // 每次蓝牙连接后自动同步设备信息
  DateTime? _lastSyncAt;

  final Duration _minSyncGap = BleConstants.minSyncGap;

  String? _currentFirmwareVersion([String? displayDeviceId]) {
    final id = displayDeviceId ?? state.bleDeviceData?.displayDeviceId;
    if (id == null || id.isEmpty) return null;
    return _ref
        .read(savedDevicesProvider.notifier)
        .findById(id)
        ?.firmwareVersion;
  }

  @override
  set state(BleConnectionState next) {
    _setStateSafely(next, reason: 'direct state assignment');
  }

  /// 针对指定设备开启一个全新的 BLE 会话。
  /// 这里是唯一允许修改 bleDeviceData 的入口，保证：
  /// - bleDeviceData 与其余会话相关字段（状态 / loading / 错误 / 网络信息）保持原子一致
  /// - 不会出现“新设备 + 旧状态”的组合
  void _startSessionStateForDevice(DeviceQrData qrData) {
    final d = qrDataToDeviceData(qrData);
    state = BleConnectionState(
      // 会话设备
      bleDeviceData: d,
      // 新会话从“连接中”开始
      bleDeviceStatus: BleDeviceStatus.connecting,
      enableBleConnectionLoading: true,
      emptyBound: false,
      wifiNetworks: const [],
      isScanningWifi: false,
      wifiScanUpdatedAt: null,
      networkStatus: null,
      isCheckingNetwork: false,
      networkStatusUpdatedAt: null,
    );
  }

  void _syncWhenAuthed({required String reason}) {
    _log('call _syncWhenAuthed');
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
      final saved = _ref.read(savedDevicesProvider);
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
      _updateStateSafely(
        (current) => current.copyWith(isCheckingNetwork: true),
        reason: 'syncDeviceInfo.start',
      );
      final info = await sendBleMsg('device.info', null, retries: 0);
      if (!_isMounted) return;
      if (info is Map<String, dynamic>) {
        // 更新网络状态到连接状态
        _updateStateSafely(
          (current) => current.copyWith(
            networkStatus: NetworkStatus.fromJson(info['network']),
            networkStatusUpdatedAt: DateTime.now(),
          ),
          reason: 'syncDeviceInfo.networkStatus',
        );

        // 通过 SavedDevicesNotifier 更新固件版本与上次连接时间（仅本地与内存）
        final deviceId = state.bleDeviceData?.displayDeviceId;
        final fw = info['firmwareVersion']?.toString();
        if (deviceId != null && deviceId.isNotEmpty) {
          try {
            await _ref
                .read(savedDevicesProvider.notifier)
                .updateFields(
                  displayDeviceId: deviceId,
                  firmwareVersion: fw,
                  lastConnectedAt: DateTime.now(),
                );
          } catch (e) {
            _log(
              '更新 firmwareVersion/lastConnectedAt 到 SavedDevicesNotifier 失败: $e',
            );
          }
        }
      }
      _log('syncDeviceInfo 完成');
    } catch (e) {
      _log('syncDeviceInfo 失败: $e');
    } finally {
      _updateStateSafely(
        (current) => current.copyWith(isCheckingNetwork: false),
        reason: 'syncDeviceInfo.finally',
      );
    }
  }

  // TODO: 目前 send 没有 ensure
  // 建立蓝牙连接
  Future<BleConnectResult> enableBleConnection(DeviceQrData qrData) async {
    /// 1. 检查当前（已连上啥也不做）
    if (state.bleDeviceData != null &&
        state.bleDeviceData!.displayDeviceId == qrData.displayDeviceId &&
        state.bleDeviceStatus == BleDeviceStatus.authenticated) {
      AppLog.instance.info(
        "[ble_connection_provider] enableBleConnection already connected",
      );
      return BleConnectResult.alreadyConnected;
    }

    /// --- 会话计数（race condition）---
    final int session = ++_sessionCount;

    // 若尚未开始会话，设置一个基准时间用于统一打点
    final t0 = DateTime.now();
    _sessionStart ??= t0;
    _log('🔌 enableBleConnection 开始');
    DeviceOnboardingLog.info(
      event: DeviceOnboardingEvents.bleConnect,
      result: 'start',
      displayDeviceId: qrData.displayDeviceId,
      firmwareVersion: _currentFirmwareVersion(qrData.displayDeviceId),
    );

    /// 2. 断开连接
    try {
      await _ref.read(secureChannelManagerProvider).dispose();
    } catch (_) {}

    /// --- 已取消 ---
    if (session != _sessionCount) {
      return BleConnectResult.cancelled;
    }

    /// 3. 重置 UI state
    _startSessionStateForDevice(qrData);
    bool isTimeout = false;
    try {
      /// 4. 建连
      final mgr = _ref.read(secureChannelManagerProvider);
      _activeOps++;
      final bool ok;
      try {
        ok = await mgr
            .use(qrData)
            .timeout(
              BleConstants.kLoadingMaxS,
              onTimeout: () async {
                isTimeout = true;
                _log(
                  '---------⏰ mgr.use 超时(${BleConstants.kLoadingMaxS}s)，dispose 中止连接',
                );
                AppLog.instance.error(
                  "[ble_connection_provider] mgr.use 超时(${BleConstants.kLoadingMaxS}s)，dispose 中止连接",
                );
                try {
                  await mgr.dispose(); // ✅ 中止底层连接/扫描，不改变 session
                } catch (_) {}

                // 可选：把 UI 状态拉回断开（不 reset，不影响 session）
                if (_isMounted && session == _sessionCount) {
                  _updateStateSafely(
                    (current) => current.copyWith(
                      bleDeviceStatus: BleDeviceStatus.disconnected,
                    ),
                    reason: 'enableBleConnection.timeout',
                  );
                }
                return false; // 让 ok=false -> BleConnectResult.failed
              },
            );
      } finally {
        _activeOps--;
      }

      /// --- 已取消 ---
      if (session != _sessionCount) {
        return BleConnectResult.cancelled;
      }

      if (isTimeout) {
        return BleConnectResult.timeout;
      }

      if (!ok) {
        return BleConnectResult.failed;
      }

      /// 5. 握手状态
      final hs = mgr.lastHandshakeStatus;
      AppLog.instance.debug('handshakeStatus=$hs', tag: 'BLE');
      bool treatAsEmptyBound = hs == 'empty_bound';
      DeviceOnboardingLog.info(
        event: DeviceOnboardingEvents.bleHandshake,
        result: treatAsEmptyBound ? 'empty_bound' : 'success',
        durationMs: DateTime.now().difference(t0).inMilliseconds,
        displayDeviceId: qrData.displayDeviceId,
        firmwareVersion: _currentFirmwareVersion(qrData.displayDeviceId),
      );
      _updateStateSafely(
        (current) => current.copyWith(emptyBound: treatAsEmptyBound),
        reason: 'enableBleConnection.handshake',
      );

      /// 6. 绑定事件流
      _attachChannelEvents(mgr);

      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('enableBleConnection.success(${elapsed}ms)');
      DeviceOnboardingLog.info(
        event: DeviceOnboardingEvents.bleConnect,
        result: 'success',
        durationMs: elapsed,
        displayDeviceId: qrData.displayDeviceId,
        firmwareVersion: _currentFirmwareVersion(qrData.displayDeviceId),
      );

      /// 7. 更新 UI state
      _updateStateSafely(
        (current) =>
            current.copyWith(bleDeviceStatus: BleDeviceStatus.authenticated),
        reason: 'enableBleConnection.authenticated',
      );
      _lastActivityAt = DateTime.now();

      /// 8. 连接成功时，sync 一次
      _syncWhenAuthed(reason: 'enableBleConnection-authenticated');

      /// 9. 返回结果
      return BleConnectResult.success;
    } catch (e) {
      AppLog.instance.error(
        'enableBleConnection failed $session, $_sessionCount',
        error: e,
      );
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTime('enableBleConnection.fail(${elapsed}ms): $e');

      BleConnectResult result = BleConnectResult.failed;
      if (_isMounted && session == _sessionCount) {
        if (e is UserMismatchException) {
          _updateStateSafely(
            (current) =>
                current.copyWith(bleDeviceStatus: BleDeviceStatus.error),
            reason: 'enableBleConnection.userMismatch',
          );
          result = BleConnectResult.userMismatch;
        } else {
          _updateStateSafely(
            (current) =>
                current.copyWith(bleDeviceStatus: BleDeviceStatus.error),
            reason: 'enableBleConnection.error',
          );
          if (e is TimeoutException &&
              e.message == BleConnectResult.scanTimeout.name) {
            result = BleConnectResult.scanTimeout;
          } else if (e is StateError &&
              e.message == BleConnectResult.notReady.name) {
            result = BleConnectResult.notReady;
          }
        }
      }
      DeviceOnboardingLog.error(
        event: DeviceOnboardingEvents.bleConnect,
        result: result.name,
        durationMs: elapsed,
        displayDeviceId: qrData.displayDeviceId,
        firmwareVersion: _currentFirmwareVersion(qrData.displayDeviceId),
        error: e,
        extra: {'error_type': e.runtimeType.toString(), 'session': session},
      );
      return result;
    } finally {
      if (_isMounted && session == _sessionCount) {
        _updateStateSafely(
          (current) => current.copyWith(enableBleConnectionLoading: false),
          reason: 'enableBleConnection.finally',
        );
      }
    }
  }

  // 用户发送蓝牙消息 1/2：【简单版】返回成功与否
  Future<bool> sendSimpleBleMsg(
    String type,
    dynamic data, {
    Duration? timeout,
  }) async {
    _log('sendPureBleMsg: $type, $data');
    _activeOps++;
    _lastActivityAt = DateTime.now();
    try {
      final resp = await _ref.read(secureChannelManagerProvider).send({
        'type': type,
        'data': data,
      }, timeout: timeout);
      _log('✅ sendPureBleMsg 成功: type=$type, resp=$resp');
      return resp['ok'] == true;
    } catch (e) {
      _log('❌ sendPureBleMsg 失败: $e');
      return false;
    } finally {
      _activeOps--;
    }
  }

  // 用户发送蓝牙消息 2/2：【复杂版】返回 data，调用处自己 catch
  Future<dynamic> sendBleMsg(
    String type,
    dynamic data, {
    int retries = 0,
    bool Function(Map<String, dynamic>)? isFinal,
  }) async {
    _log('sendBleMsg: $type, $data');
    _activeOps++;
    _lastActivityAt = DateTime.now();
    try {
      final resp = await _ref
          .read(secureChannelManagerProvider)
          .send(
            {'type': type, 'data': data},
            retries: retries,
            isFinal: isFinal,
          );
      _log('✅ sendBleMsg 成功: type=$type, resp=$resp');
      return resp['data'];
    } finally {
      _activeOps--;
    }
  }

  // 用户发送蓝牙消息 3/3：【完整响应】返回完整 resp，调用处自己处理 ok/error
  Future<Map<String, dynamic>> sendBleResp(
    String type,
    dynamic data, {
    int retries = 0,
    bool Function(Map<String, dynamic>)? isFinal,
  }) async {
    _log('sendBleResp: $type, $data');
    _activeOps++;
    _lastActivityAt = DateTime.now();
    try {
      final resp = await _ref
          .read(secureChannelManagerProvider)
          .send(
            {'type': type, 'data': data},
            retries: retries,
            isFinal: isFinal,
          );
      _log('✅ sendBleResp 成功: type=$type, resp=$resp');
      return resp;
    } finally {
      _activeOps--;
    }
  }

  // 绑定
  Future<bool> sendDeviceLoginCode(String email, String code) async {
    _log('sendDeviceLoginCode email=$email');
    final displayDeviceId = state.bleDeviceData?.displayDeviceId;
    final firmwareVersion = _currentFirmwareVersion();
    DeviceOnboardingLog.info(
      event: DeviceOnboardingEvents.bindDeviceAuth,
      result: 'start',
      displayDeviceId: displayDeviceId,
      firmwareVersion: firmwareVersion,
    );
    final ok = await sendSimpleBleMsg('login.auth', {
      'email': email,
      'otpToken': code,
    }, timeout: BleConstants.bindLoginTimeout);
    DeviceOnboardingLog.info(
      event: DeviceOnboardingEvents.bindDeviceAuth,
      result: ok ? 'success' : 'fail',
      displayDeviceId: displayDeviceId,
      firmwareVersion: firmwareVersion,
    );
    return ok;
  }

  // 解绑
  Future<bool> sendDeviceLogout() async {
    return await sendSimpleBleMsg('logout', null);
  }

  // 可用 wifi
  Future<bool> requestWifiScan() async {
    if (state.isScanningWifi) {
      _log('跳过 wifi.scan：已有扫描进行中');
      return false;
    }

    DeviceOnboardingLog.info(
      event: DeviceOnboardingEvents.wifiScan,
      result: 'start',
      displayDeviceId: state.bleDeviceData?.displayDeviceId,
      firmwareVersion: _currentFirmwareVersion(),
    );
    _updateStateSafely(
      (current) => current.copyWith(isScanningWifi: true),
      reason: 'requestWifiScan.start',
    );
    try {
      _log('⏳ 开始扫描附近Wi-Fi...');
      final data = await sendBleMsg('wifi.scan', null, retries: 0);
      if (!_isMounted) return false;
      if (data is List) {
        final networks = data
            .map(
              (e) => WifiAp(
                ssid: (e['ssid'] ?? '').toString(),
                rssi: int.tryParse((e['rawRssi'] ?? '0').toString()) ?? 0,
                secure: (e['secure'] == true),
                bssid: e['bssid']?.toString(),
                frequency: int.tryParse((e['frequency'] ?? '').toString()),
              ),
            )
            .toList();
        _updateStateSafely(
          (current) => current.copyWith(
            wifiNetworks: networks,
            wifiScanUpdatedAt: DateTime.now(),
          ),
          reason: 'requestWifiScan.success',
        );
        DeviceOnboardingLog.info(
          event: DeviceOnboardingEvents.wifiScan,
          result: 'success',
          displayDeviceId: state.bleDeviceData?.displayDeviceId,
          firmwareVersion: _currentFirmwareVersion(),
          extra: {'network_count': networks.length},
        );
        _log('📶 Wi-Fi 扫描完成，发现 ${networks.length} 个网络');
      }
      return true;
    } catch (e) {
      DeviceOnboardingLog.error(
        event: DeviceOnboardingEvents.wifiScan,
        result: 'fail',
        displayDeviceId: state.bleDeviceData?.displayDeviceId,
        firmwareVersion: _currentFirmwareVersion(),
        error: e,
        extra: {'error_type': e.runtimeType.toString()},
      );
      _log('❌ wifi.scan 失败: $e');
      return false;
    } finally {
      _updateStateSafely(
        (current) => current.copyWith(isScanningWifi: false),
        reason: 'requestWifiScan.finally',
      );
    }
  }

  // 配网：等待同一通道的最终 wifi.config 响应（设备端直接回最终结果）
  Future<bool> sendWifiConfig(String ssid, String password) async {
    _log('sendWifiConfig: ssid=$ssid');
    final displayDeviceId = state.bleDeviceData?.displayDeviceId;
    final firmwareVersion = _currentFirmwareVersion();
    DeviceOnboardingLog.info(
      event: DeviceOnboardingEvents.wifiConfig,
      result: 'start',
      displayDeviceId: displayDeviceId,
      firmwareVersion: firmwareVersion,
    );
    try {
      final data = await sendBleMsg('wifi.config', {
        'ssid': ssid,
        'password': password,
      });
      // 成功时设备返回 data: {status: 'connected'}
      if (data is Map<String, dynamic>) {
        final s = data['status']?.toString();
        final ok = s == 'connected';
        if (ok) {
          _updateStateSafely(
            (current) => current.copyWith(
              networkStatus: NetworkStatus(
                connected: true,
                ssid: ssid,
                rawRssi: null,
              ),
              networkStatusUpdatedAt: DateTime.now(),
              isCheckingNetwork: false,
            ),
            reason: 'sendWifiConfig.success',
          );
        }
        DeviceOnboardingLog.info(
          event: DeviceOnboardingEvents.wifiConfig,
          result: ok ? 'success' : 'fail',
          displayDeviceId: displayDeviceId,
          firmwareVersion: firmwareVersion,
          extra: {if (s != null && s.isNotEmpty) 'device_status': s},
        );
        return ok;
      }
      DeviceOnboardingLog.warning(
        event: DeviceOnboardingEvents.wifiConfig,
        result: 'fail',
        displayDeviceId: displayDeviceId,
        firmwareVersion: firmwareVersion,
        extra: const {'error_code': 'unexpected_response'},
      );
      return false;
    } catch (e) {
      DeviceOnboardingLog.error(
        event: DeviceOnboardingEvents.wifiConfig,
        result: 'fail',
        displayDeviceId: displayDeviceId,
        firmwareVersion: firmwareVersion,
        error: e,
        extra: {'error_type': e.runtimeType.toString()},
      );
      _log('❌ sendWifiConfig failed: $e');
      return false;
    }
  }

  // 网络状态
  Future<NetworkStatus?> checkNetworkStatus() async {
    if (state.isCheckingNetwork) return null;

    try {
      _updateStateSafely(
        (current) => current.copyWith(isCheckingNetwork: true),
        reason: 'checkNetworkStatus.start',
      );
      final data = await sendBleMsg('network.status', null, retries: 0);
      if (!_isMounted) return null;
      if (data is Map<String, dynamic>) {
        final ns = NetworkStatus.fromJson(data);
        _updateStateSafely(
          (current) => current.copyWith(
            networkStatus: ns,
            networkStatusUpdatedAt: DateTime.now(),
          ),
          reason: 'checkNetworkStatus.success',
        );
        return ns;
      }
      return null;
    } catch (e) {
      return null;
    } finally {
      _updateStateSafely(
        (current) => current.copyWith(isCheckingNetwork: false),
        reason: 'checkNetworkStatus.finally',
      );
    }
  }

  /// 版本更新（先尝试v2，不兼容再回退v1）
  Future<DeviceUpdateVersionResult> requestUpdateCheck() async {
    final v2 = await _requestUpdateCheckV2();
    if (v2 != null) return v2;
    return await _requestUpdateCheckV1();
  }

  Future<DeviceUpdateVersionResult?> _requestUpdateCheckV2() async {
    try {
      final resp = await sendBleResp('update.version2', null, retries: 0);

      if (resp['ok'] == true) {
        return parseDeviceUpdateResultV2(resp['data']);
      }

      final err = resp['error'];
      final code = (err is Map) ? err['code']?.toString() : null;
      if (code == 'unknown_type') {
        return null; // fallback v1
      }
      return DeviceUpdateVersionResult.failed;
    } catch (_) {
      return DeviceUpdateVersionResult.failed;
    }
  }

  Future<DeviceUpdateVersionResult> _requestUpdateCheckV1() async {
    try {
      final resp = await sendBleResp('update.version', null, retries: 0);
      if (resp['ok'] == true) {
        return parseDeviceUpdateResult(resp['data']);
      }
      _log('update.version ok=false: ${resp['error'] ?? resp}');
      return DeviceUpdateVersionResult.failed;
    } catch (_) {
      return DeviceUpdateVersionResult.failed;
    }
  }

  /// bind 成功且已 syncFromServer 后调用：补一次 device.info 同步
  void syncDeviceInfoAfterBind() {
    if (state.bleDeviceStatus != BleDeviceStatus.authenticated) {
      _log('跳过 syncDeviceInfoAfterBind：未 authenticated');
      return;
    }
    _syncWhenAuthed(reason: 'bind-success');
  }

  void _log(String msg) => AppLog.instance.debug(msg, tag: 'BLE');

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
    /// --- 会话计数 ---
    final int session = ++_sessionCount;
    await _ref.read(secureChannelManagerProvider).dispose();
    if (!_isMounted || session != _sessionCount) {
      return;
    }
    _heartbeatFailures = 0;
    if (shouldReset) {
      resetState();
    } else {
      state = state.copyWith(bleDeviceStatus: BleDeviceStatus.disconnected);
    }
  }

  void resetState() {
    // 重置状态时，同样提升会话计数，确保旧会话不再更新状态
    _sessionCount++;
    _sessionStart = null;
    state = const BleConnectionState();
  }

  @override
  void dispose() {
    _evtSub?.cancel();
    _managerSub?.close();
    _foregroundSub?.close();
    _heartbeatTimer?.cancel();
    super.dispose();
  }
}

final bleConnectionProvider =
    StateNotifierProvider<BleConnectionNotifier, BleConnectionState>((ref) {
      return BleConnectionNotifier(ref);
    });
