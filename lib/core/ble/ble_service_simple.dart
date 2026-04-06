import 'dart:async';
import 'dart:io';
import '../log/app_log.dart';
import 'dart:typed_data';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/ble_constants.dart';
import 'ble_device_data.dart';

/// 简化的BLE服务类，用于基本的蓝牙操作（已合并权限与就绪逻辑）
class BleServiceSimple {
  static final FlutterReactiveBle _ble = FlutterReactiveBle();

  static StreamSubscription<DiscoveredDevice>? _scanSubscription;
  static StreamSubscription<ConnectionStateUpdate>?
  _deviceConnectionSubscription;
  static Future<void>? _stopScanInFlight;
  static bool _hasActiveConnection = false;
  static String? _activeDeviceId;

  static bool _isScanning = false;
  static StreamController<SimpleBLEScanResult>? _scanController;

  // 设备去重映射表 - 按设备ID去重
  static final Map<String, SimpleBLEScanResult> _discoveredDevices = {};

  // 每个设备的最近一次打印时间与RSSI，用于节流日志
  static final Map<String, DateTime> _lastLogAt = {};
  static final Map<String, int> _lastLogRssi = {};
  static const Duration _perDeviceLogInterval =
      BleConstants.perDeviceLogInterval;

  // Track negotiated MTU per device for framing without re-requesting MTU each time
  static final Map<String, int> _mtuByDevice = {};
  static final Map<String, List<DiscoveredService>> _servicesByDevice = {};

  // 打点：统一会话起点
  static DateTime? _sessionStart;

  static void _logInfo(String msg) =>
      AppLog.instance.info(msg, tag: 'BLE_SIMPLE');
  static void _logDebug(String msg) =>
      AppLog.instance.debug(msg, tag: 'BLE_SIMPLE');

  static void _logWithTimeInfo(String label) {
    final now = DateTime.now();
    if (_sessionStart != null) {
      final ms = now.difference(_sessionStart!).inMilliseconds;
      _logInfo('⏱ [$ms ms] $label');
    } else {
      _logInfo('⏱ $label');
    }
  }

  static void _logWithTimeDebug(String label) {
    final now = DateTime.now();
    if (_sessionStart != null) {
      final ms = now.difference(_sessionStart!).inMilliseconds;
      _logDebug('⏱ [$ms ms] $label');
    } else {
      _logDebug('⏱ $label');
    }
  }

  // 权限就绪广播（供上层监听）
  static final _permissionStreamController = StreamController<bool>.broadcast();
  static Stream<bool> get permissionStream =>
      _permissionStreamController.stream;

  // Connection/adapter status broadcast for upper layers
  static final _connectionEventController =
      StreamController<Map<String, dynamic>>.broadcast();
  static Stream<Map<String, dynamic>> get connectionEvents =>
      _connectionEventController.stream;
  static bool get hasActiveConnection => _hasActiveConnection;
  static String? get activeDeviceId => _activeDeviceId;

  static Future<bool> waitForDisconnected({
    String? deviceId,
    Duration timeout = BleConstants.waitForDisconnectedTimeout,
  }) async {
    if (!_hasActiveConnection) return true;
    try {
      await _connectionEventController.stream
          .firstWhere((e) {
            if ((e['type'] ?? '').toString() != 'connection') return false;
            if ((e['state'] ?? '').toString() != 'disconnected') return false;
            if (deviceId == null || deviceId.isEmpty) return true;
            final eventDeviceId = (e['deviceId'] ?? '').toString();
            return eventDeviceId.isEmpty || eventDeviceId == deviceId;
          })
          .timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Forward adapter status to upper layers
  static StreamSubscription<BleStatus>? _bleStatusSub;
  static void _ensureBleStatusForwarder() {
    if (_bleStatusSub != null) return;
    _bleStatusSub = _ble.statusStream.listen((status) async {
      try {
        _connectionEventController.add({
          'type': 'ble_status',
          'status': status.toString(),
        });
        if (status == BleStatus.poweredOff) {
          // Stop ongoing BLE work when adapter is off
          try {
            await stopScan();
          } catch (_) {}
          try {
            await disconnect();
          } catch (_) {}
        }
      } catch (_) {}
    });
  }

  // ✅ 统一的“刚就绪”时间戳 & 老安卓定位门槛缓存
  static bool _legacyNeedsLocation = false; // Android < 12 是否需要定位服务开关

  /// 申请更大的 MTU
  static Future<int> requestMtu(String deviceId, int mtu) async {
    final t0 = DateTime.now();
    _logDebug('📏 requestMtu 开始: target=$mtu, device=$deviceId');
    try {
      final negotiatedMtu = await _ble.requestMtu(deviceId: deviceId, mtu: mtu);
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug('requestMtu.done(${elapsed}ms) -> $negotiatedMtu');
      if (negotiatedMtu > 0) {
        _mtuByDevice[deviceId] = negotiatedMtu;
      }
      return negotiatedMtu;
    } catch (e) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug('requestMtu.fail(${elapsed}ms): $e');
      return BleConstants.minMtu; // 默认最小MTU
    }
  }

  static int getNegotiatedMtu(String deviceId) {
    return _mtuByDevice[deviceId] ?? BleConstants.minMtu;
  }

  /// 查询 BLE 当前状态（忽略 unknown）
  static Future<BleStatus> checkBleStatus() async {
    final t0 = DateTime.now();
    _logDebug('🔎 checkBleStatus 开始');
    try {
      final status = await _ble.statusStream
          .firstWhere(
            (s) => s != BleStatus.unknown,
            orElse: () => BleStatus.unknown,
          )
          .timeout(BleConstants.bleStatusCheckTimeout);
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug('checkBleStatus.done(${elapsed}ms) -> $status');
      return status;
    } catch (_) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug('checkBleStatus.error(${elapsed}ms)');
      return BleStatus.unknown;
    }
  }

  static Future<bool> ensureBleReady() async {
    final t0 = DateTime.now();
    _sessionStart ??= t0;
    _logInfo('🚦 ensureBleReady 开始');
    try {
      _ensureBleStatusForwarder();
      final status = await checkBleStatus();
      if (status == BleStatus.unsupported || status == BleStatus.poweredOff) {
        return false;
      }

      if (Platform.isAndroid) {
        final reqs = <Permission>[];
        if (!await Permission.bluetoothScan.isGranted) {
          reqs.add(Permission.bluetoothScan);
        }
        if (!await Permission.bluetoothConnect.isGranted) {
          reqs.add(Permission.bluetoothConnect);
        }
        // 仅在老安卓需要定位权限：
        _legacyNeedsLocation = await _legacyNeedsLocationGate();
        if (_legacyNeedsLocation &&
            !await Permission.locationWhenInUse.isGranted) {
          reqs.add(Permission.locationWhenInUse);
        }
        if (reqs.isNotEmpty) {
          final p0 = DateTime.now();
          final rs = await reqs.request();
          final pElapsed = DateTime.now().difference(p0).inMilliseconds;
          _logWithTimeDebug('permissions.request.done(${pElapsed}ms)');
          if (rs.values.any((s) => !s.isGranted)) {
            _permissionStreamController.add(false);
            return false;
          }
          if (_legacyNeedsLocation) {
            final s0 = DateTime.now();
            final service = await Permission.locationWhenInUse.serviceStatus;
            final sElapsed = DateTime.now().difference(s0).inMilliseconds;
            _logWithTimeDebug(
              'permissions.locationService.checked(${sElapsed}ms) -> $service',
            );
            if (service != ServiceStatus.enabled) {
              _permissionStreamController.add(false);
              return false;
            }
          }
        }
      }

      // 单次等 Ready，失败再兜底再等一次
      Future<BleStatus> waitReady(Duration t) => _ble.statusStream
          .timeout(t, onTimeout: (sink) {})
          .firstWhere(
            (s) => s == BleStatus.ready,
            orElse: () => BleStatus.unknown,
          );

      final w0 = DateTime.now();
      var s = await waitReady(BleConstants.bleReadyWaitTimeout);
      if (s != BleStatus.ready) {
        s = await waitReady(BleConstants.bleReadyWaitTimeout);
      }
      final wElapsed = DateTime.now().difference(w0).inMilliseconds;
      _logWithTimeDebug('status.waitReady.done(${wElapsed}ms) -> $s');

      final ok = (s == BleStatus.ready);
      _permissionStreamController.add(ok);
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeInfo('ensureBleReady.result(${elapsed}ms) -> $ok');
      return ok;
    } catch (_) {
      _permissionStreamController.add(false);
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeInfo('ensureBleReady.error(${elapsed}ms)');
      return false;
    }
  }

  // 老安卓门槛判断：用“是否具备 bluetoothScan 权限常量”近似判断系统代际。
  static Future<bool> _legacyNeedsLocationGate() async {
    if (!Platform.isAndroid) return false;
    try {
      final hasScan = await Permission.bluetoothScan.isGranted;
      return !hasScan; // 没有 scan 权限 → 旧系统 → 需要定位服务开关
    } catch (_) {
      return true; // 保守处理
    }
  }

  static Stream<SimpleBLEScanResult> scanForDevice({
    // required String targetDeviceId,
    required Duration timeout,
  }) {
    _scanController?.close();
    _scanController = StreamController<SimpleBLEScanResult>.broadcast();
    _sessionStart ??= DateTime.now();
    _startScanningProcess(timeout);
    return _scanController!.stream;
  }

  static void _startScanningProcess(Duration timeout) async {
    final t0 = DateTime.now();
    _logInfo('🔎 开始扫描, timeout=${timeout.inSeconds}s');
    try {
      await stopScan(); // 确保冷启动
      _discoveredDevices.clear();
      _isScanning = true;

      var firstFound = false;
      _scanSubscription = _ble
          .scanForDevices(
            withServices: [],
            scanMode: ScanMode.lowLatency,
            requireLocationServicesEnabled:
                _legacyNeedsLocation, // Android<12 仍保留
          )
          .listen(
            (device) {
              if (!_isScanning) return;
              final result = SimpleBLEScanResult.fromDiscoveredDevice(device);
              _discoveredDevices[result.deviceId] = result;
              _scanController?.add(result);
              if (!firstFound) {
                firstFound = true;
                final elapsed = DateTime.now().difference(t0).inMilliseconds;
                _logWithTimeInfo(
                  'scan.firstResult(${elapsed}ms): id=${result.deviceId}, rssi=${result.rssi}',
                );
              }
              _throttledLog(result); // 你的节流日志函数保留即可
            },
            onError: (e) {
              _scanController?.addError(e); // ❌ 不做重扫预算
              _isScanning = false;
              _scanController?.close();
              final elapsed = DateTime.now().difference(t0).inMilliseconds;
              _logWithTimeInfo('scan.error(${elapsed}ms): $e');
            },
            onDone: () {
              _isScanning = false;
              _scanController?.close();
              final elapsed = DateTime.now().difference(t0).inMilliseconds;
              _logWithTimeInfo('scan.done(${elapsed}ms)');
            },
          );

      // 超时停止（单次）
      Timer(timeout, () async {
        if (_isScanning) await stopScan();
      });
    } catch (e) {
      _isScanning = false;
      _scanController?.addError(e);
      _scanController?.close();
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeInfo('scan.exception(${elapsed}ms): $e');
    }
  }

  static Future<void> stopScan() async {
    if (_stopScanInFlight != null) {
      _logDebug('⏹️ stopScan 复用进行中的请求');
      return _stopScanInFlight!;
    }

    final op = () async {
      final t0 = DateTime.now();
      _logDebug('⏹️ stopScan 开始');
      if (!_isScanning && _scanSubscription == null) {
        return;
      }
      _isScanning = false;
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      if (_scanController != null && !_scanController!.isClosed) {
        await _scanController?.close();
      }
      _scanController = null;
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug('stopScan.done(${elapsed}ms)');
    }();

    _stopScanInFlight = op;
    try {
      await op;
    } finally {
      _stopScanInFlight = null;
    }
  }

  // 放在 BleServiceSimple 类内部的任意位置（比如 stopScan() 下面）
  static void _throttledLog(SimpleBLEScanResult r) {
    final now = DateTime.now();
    final lastAt = _lastLogAt[r.deviceId];
    final lastRssi = _lastLogRssi[r.deviceId];

    final hasLast = lastAt != null && lastRssi != null;
    final rssiChanged = lastRssi == null || (r.rssi - lastRssi).abs() >= 5;
    final timeOk =
        lastAt == null || now.difference(lastAt) >= _perDeviceLogInterval;

    // 首次看到这个设备：直接打
    // 之后：必须时间到了 && rssi 变化够大才打
    if (!hasLast || (timeOk && rssiChanged)) {
      _lastLogAt[r.deviceId] = now;
      _lastLogRssi[r.deviceId] = r.rssi;

      // 这里按需打印你想看的字段
      AppLog.instance.debug('🔍 发现设备: ${r.name}', tag: 'BLE_SIMPLE');
      AppLog.instance.debug(
        '  id=${r.deviceId}, rssi=${r.rssi}',
        tag: 'BLE_SIMPLE',
      );
      AppLog.instance.debug(
        '  serviceUuids=${r.serviceUuids}',
        tag: 'BLE_SIMPLE',
      );
      AppLog.instance.debug(
        '  manufacturerData=${r.manufacturerData}',
        tag: 'BLE_SIMPLE',
      );
    }
  }

  // ========= UUID 辅助函数开始 =========

  // 标准 BLE Base UUID: 0000xxxx-0000-1000-8000-00805f9b34fb
  static bool _isBaseBle128(String s) {
    s = s.toLowerCase();
    return s.endsWith('-0000-1000-8000-00805f9b34fb') && s.length == 36;
  }

  // 从标准 Base UUID 里提取 16-bit 部分:
  // 0000a100-0000-1000-8000-00805f9b34fb -> a100
  static String _extract16(String s) {
    final head = s.split('-').first; // 0000a100
    return head.substring(head.length - 4);
  }

  static bool _isShort16(String s) {
    s = s.toLowerCase();
    return s.length == 4 && RegExp(r'^[0-9a-f]{4}$').hasMatch(s);
  }

  /// 宽松 UUID 比较:
  /// - 完全一样 => 相等
  /// - 都是 BLE Base UUID => 比较 16-bit
  /// - 一边 Base UUID, 一边短 16-bit => 比较 16-bit
  /// - 其他情况 => 要求完整字符串相等
  static bool _uuidEqualsLoose(String a, String b) {
    a = a.toLowerCase();
    b = b.toLowerCase();

    if (a == b) return true;

    final aBase = _isBaseBle128(a);
    final bBase = _isBaseBle128(b);
    final aShort = _isShort16(a);
    final bShort = _isShort16(b);

    // 两边都是 Base UUID
    if (aBase && bBase) {
      return _extract16(a) == _extract16(b);
    }

    // Base UUID vs 16-bit
    if (aBase && bShort) {
      return _extract16(a) == b;
    }
    if (bBase && aShort) {
      return _extract16(b) == a;
    }

    // 其他情况：只能完全一样才算
    return false;
  }

  // ========= UUID 辅助函数结束 =========

  /// 连接设备（内置一次 GATT 135 自愈重试）
  /// [attempt] 用于内部递归时标记第几次尝试，外部调用不要传
  static Future<BleDeviceData?> connectToDevice({
    required BleDeviceData bleDeviceData,
    int attempt = 1,
  }) async {
    final t0 = DateTime.now();
    _sessionStart ??= t0;
    _logInfo(
      '🔗 connectToDevice 开始: id=${bleDeviceData.bleDeviceId}, timeout=${BleConstants.connectToServiceTimeout}s',
    );

    bool sawGatt135 = false; // 👈 这一轮有没有遇到 135

    try {
      if (_isScanning || _scanSubscription != null) {
        await stopScan();
      }

      final connectionStream = _ble.connectToDevice(
        id: bleDeviceData.bleDeviceId,
        connectionTimeout: BleConstants.connectToServiceTimeout,
      );

      final completer = Completer<BleDeviceData?>();

      // ▼ 可取消的超时定时器 & 完成函数
      late final Timer timer;
      void completeOnce(BleDeviceData? v) {
        if (!completer.isCompleted) {
          timer.cancel(); // 1) 先取消超时
          completer.complete(v); // 2) 再完成
        }
      }
      // ▲

      await _deviceConnectionSubscription?.cancel();
      _deviceConnectionSubscription = connectionStream.listen(
        (update) async {
          // Minimal connection state logging to aid field debugging
          // ignore: avoid_print
          _logDebug(
            'connection.update state=${update.connectionState} device=${update.deviceId} failure=${update.failure}',
          );

          // 👇 这里解析一下 failure 里有没有 135
          final failureStr = update.failure?.toString() ?? '';
          if (failureStr.contains('status 135') ||
              failureStr.contains('GATT_ILLEGAL_PARAMETER')) {
            sawGatt135 = true;
          }

          switch (update.connectionState) {
            case DeviceConnectionState.connected:
              _hasActiveConnection = true;
              _activeDeviceId = update.deviceId;
              final connectedAtMs = DateTime.now()
                  .difference(t0)
                  .inMilliseconds;
              _logWithTimeInfo(
                'connect.connected(${connectedAtMs}ms), stabilize=${BleConstants.kStabilizeAfterConnect.inMilliseconds}ms',
              );
              await Future.delayed(BleConstants.kStabilizeAfterConnect);
              completeOnce(
                bleDeviceData.copyWith(
                  status: BleDeviceStatus.connected,
                  connectedAt: DateTime.now(),
                ),
              );
              // Broadcast connection event
              try {
                _connectionEventController.add({
                  'type': 'connection',
                  'state': 'connected',
                  'deviceId': update.deviceId,
                });
              } catch (_) {}
              break;
            case DeviceConnectionState.disconnected:
              _hasActiveConnection = false;
              if (_activeDeviceId == update.deviceId) {
                _activeDeviceId = null;
              }
              final elapsed = DateTime.now().difference(t0).inMilliseconds;
              _logWithTimeInfo(
                'connect.disconnected(${elapsed}ms) failure=${update.failure?.toString()}',
              );
              completeOnce(null);
              // Broadcast disconnection event
              try {
                _connectionEventController.add({
                  'type': 'connection',
                  'state': 'disconnected',
                  'deviceId': update.deviceId,
                  'failure': update.failure?.toString(),
                });
              } catch (_) {}
              break;
            default:
              break;
          }
        },
        onError: (_) {
          _hasActiveConnection = false;
          if (_activeDeviceId == bleDeviceData.bleDeviceId) {
            _activeDeviceId = null;
          }
          // ignore: avoid_print
          final elapsed = DateTime.now().difference(t0).inMilliseconds;
          _logWithTimeInfo('connect.stream.error(${elapsed}ms)');
          completeOnce(null);
          try {
            _connectionEventController.add({
              'type': 'connection',
              'state': 'error',
              'deviceId': bleDeviceData.bleDeviceId,
            });
          } catch (_) {}
        },
      );

      // ▼ 超时兜底（会在 completeOnce 里被 cancel）
      timer = Timer(
        BleConstants.connectToServiceTimeout,
        () => completeOnce(null),
      );
      // ▲

      final res = await completer.future;
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeInfo('connect.complete(${elapsed}ms) -> ${res != null}');
      // TODO: 如果连接超时，可以重试一次？看下状态清理问题

      // ⚠️ 关键逻辑：这一轮没连上 + 确认是 135 → 认为是“残留连接”，做一次彻底冷却 + 重试
      if (res == null && sawGatt135 && attempt == 1) {
        _logInfo('⚠️ 本轮连接失败且检测到 GATT 135，执行一次冷却重试');
        try {
          await disconnect(); // 把所有 subscription / state 清理掉
        } catch (_) {}
        // 冷却时间可以视设备情况调整，1~2 秒比较常见
        await Future.delayed(BleConstants.connectGatt135Cooldown);
        return connectToDevice(bleDeviceData: bleDeviceData, attempt: 2);
      }

      return res;
    } catch (_) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeInfo('connect.exception(${elapsed}ms)');
      return null;
    }
  }

  /// 断开连接
  static Future<void> disconnect() async {
    final t0 = DateTime.now();
    _logInfo('🔌 disconnect 开始');
    final prevActiveDeviceId = _activeDeviceId;
    await stopScan();
    await _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = null;
    _hasActiveConnection = false;
    _activeDeviceId = null;
    if (prevActiveDeviceId != null) {
      _mtuByDevice.remove(prevActiveDeviceId);
      _servicesByDevice.remove(prevActiveDeviceId);
    }

    // ✅ 仅保留这一处固定等待
    await Future.delayed(BleConstants.kDisconnectStabilize);

    // 清状态（避免下一轮粘连）
    _discoveredDevices.clear();
    _lastLogAt.clear();
    _lastLogRssi.clear();
    final elapsed = DateTime.now().difference(t0).inMilliseconds;
    _logWithTimeInfo('disconnect.done(${elapsed}ms)');
    // Also broadcast a disconnected state for upper layers
    try {
      _connectionEventController.add({
        'type': 'connection',
        'state': 'disconnected',
        if (prevActiveDeviceId != null) 'deviceId': prevActiveDeviceId,
      });
    } catch (_) {}
  }

  /// 读特征
  static Future<List<int>?> readCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    final t0 = DateTime.now();
    _logDebug(
      '📖 readCharacteristic 开始: service=$serviceUuid, char=$characteristicUuid',
    );
    try {
      final q = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(characteristicUuid),
      );
      final data = await _ble.readCharacteristic(q);
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug(
        'readCharacteristic.done(${elapsed}ms), len=${data.length}',
      );
      return data;
    } catch (e) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug('readCharacteristic.fail(${elapsed}ms): $e');
      return null;
    }
  }

  /// 主动触发服务发现，确保 GATT 就绪（尤其 Android）
  static Future<bool> discoverServices(String deviceId) async {
    final t0 = DateTime.now();
    _logDebug('🧭 discoverServices 开始: device=$deviceId');
    try {
      final services = await _ble.discoverServices(deviceId);
      if (services.isNotEmpty) {
        _servicesByDevice[deviceId] = services;
      }
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug(
        'discoverServices.done(${elapsed}ms), count=${services.length}',
      );
      return services.isNotEmpty;
    } catch (e) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug('discoverServices.fail(${elapsed}ms): $e');
      return false;
    }
  }

  /// 检查是否存在指定的 Service/Characteristic
  static Future<bool> hasCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    final t0 = DateTime.now();
    _logDebug(
      '🔎 hasCharacteristic 开始: svc=$serviceUuid, char=$characteristicUuid',
    );
    try {
      final services = await _ble.discoverServices(deviceId);
      _logDebug('hasCharacteristic.services=${services.length}');
      final targetService = services.firstWhere(
        (s) =>
            s.serviceId.toString().toLowerCase() == serviceUuid.toLowerCase(),
        orElse: () => DiscoveredService(
          serviceId: Uuid.parse('00000000-0000-0000-0000-000000000000'),
          serviceInstanceId: '',
          characteristicIds: const [],
          characteristics: const [],
          includedServices: const [],
        ),
      );
      if (targetService.characteristicIds.isEmpty) {
        final elapsed = DateTime.now().difference(t0).inMilliseconds;
        _logWithTimeDebug('hasCharacteristic.noService(${elapsed}ms)');
        return false;
      }
      final found = targetService.characteristicIds.any(
        (c) => c.toString().toLowerCase() == characteristicUuid.toLowerCase(),
      );
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug('hasCharacteristic.result(${elapsed}ms) -> $found');
      return found;
    } catch (e) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug('hasCharacteristic.fail(${elapsed}ms): $e');
      return false;
    }
  }

  /// 确保 GATT 就绪：稳定延时 -> 服务发现 -> MTU 协商 -> 再次稳定
  static Future<bool> ensureGattReady(String deviceId) async {
    final t0 = DateTime.now();
    _logDebug('🛠 ensureGattReady 开始: device=$deviceId');
    // Allow connection to fully settle before first discovery
    await Future.delayed(BleConstants.kStabilizeBeforeDiscover);
    _logWithTimeDebug(
      'ensureGattReady.stabilize1(${BleConstants.kStabilizeBeforeDiscover.inMilliseconds}ms)',
    );

    // Retry service discovery once to mitigate transient 133/135
    final d0 = DateTime.now();
    bool ok = await discoverServices(deviceId);
    _logWithTimeDebug(
      'ensureGattReady.discover.attempt1(${DateTime.now().difference(d0).inMilliseconds}ms) -> $ok',
    );
    if (!ok) {
      await Future.delayed(BleConstants.discoverRetryDelay);
      final d1 = DateTime.now();
      ok = await discoverServices(deviceId);
      _logWithTimeDebug(
        'ensureGattReady.discover.attempt2(${DateTime.now().difference(d1).inMilliseconds}ms) -> $ok',
      );
    }

    if (!ok) return false;

    // Request MTU once per connection; cache result for framing
    final m0 = DateTime.now();
    if (Platform.isAndroid) {
      try {
        final mtu = await requestMtu(deviceId, BleConstants.preferredMtu);
        if (mtu > 0) {
          _mtuByDevice[deviceId] = mtu;
        }
        _logWithTimeDebug(
          'ensureGattReady.mtu(${DateTime.now().difference(m0).inMilliseconds}ms) -> ${_mtuByDevice[deviceId]} android',
        );
      } catch (_) {}
    } else {
      _mtuByDevice[deviceId] = BleConstants.iosWithResponseCapMtu;
      _logWithTimeDebug(
        'ensureGattReady.mtu(${DateTime.now().difference(m0).inMilliseconds}ms) -> ${_mtuByDevice[deviceId]} ios',
      );
    }

    await Future.delayed(BleConstants.kStabilizeAfterMtu);
    _logWithTimeDebug(
      'ensureGattReady.stabilize2(${BleConstants.kStabilizeAfterMtu.inMilliseconds}ms)',
    );
    _logWithTimeDebug(
      'ensureGattReady.done(${DateTime.now().difference(t0).inMilliseconds}ms)',
    );
    return ok;
  }

  /// 写特征
  static Future<bool> writeCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
    required List<int> data,
    bool withResponse = true,
  }) async {
    final t0 = DateTime.now();
    _logDebug(
      '✍️ writeCharacteristic 开始: svc=$serviceUuid, char=$characteristicUuid, len=${data.length}, withResp=$withResponse',
    );
    final q = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(characteristicUuid),
    );
    try {
      if (withResponse) {
        await _ble.writeCharacteristicWithResponse(q, value: data);
      } else {
        await _ble.writeCharacteristicWithoutResponse(q, value: data);
      }
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug('writeCharacteristic.done(${elapsed}ms)');
      return true;
    } catch (e) {
      final firstElapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug('writeCharacteristic.fail1(${firstElapsed}ms): $e');
      try {
        await Future.delayed(BleConstants.writeRetryDelay);
        if (withResponse) {
          await _ble.writeCharacteristicWithResponse(q, value: data);
        } else {
          await _ble.writeCharacteristicWithoutResponse(q, value: data);
        }
        final retryElapsed = DateTime.now().difference(t0).inMilliseconds;
        _logWithTimeDebug('writeCharacteristic.retry.done(${retryElapsed}ms)');
        return true;
      } catch (e2) {
        final elapsed = DateTime.now().difference(t0).inMilliseconds;
        _logWithTimeDebug('writeCharacteristic.retry.fail(${elapsed}ms): $e2');
        return false;
      }
    }
  }

  /// 订阅特征
  static Stream<List<int>> subscribeToCharacteristic({
    required String deviceId,
    required String serviceUuid,
    required String characteristicUuid,
  }) {
    _logDebug(
      '📡 subscribeToCharacteristic: svc=$serviceUuid, char=$characteristicUuid',
    );
    final q = QualifiedCharacteristic(
      deviceId: deviceId,
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(characteristicUuid),
    );
    return _ble.subscribeToCharacteristic(q);
  }

  /// 订阅 TX(indicate) 的语义包装
  static Stream<List<int>> subscribeToIndications({
    required String deviceId,
    required String serviceUuid,
    required String txCharacteristicUuid,
  }) {
    _logDebug(
      '📡 subscribeToIndications: svc=$serviceUuid, tx=$txCharacteristicUuid',
    );
    return subscribeToCharacteristic(
      deviceId: deviceId,
      serviceUuid: serviceUuid,
      characteristicUuid: txCharacteristicUuid,
    );
  }

  /// 发现并校验 RX/TX 是否存在
  static Future<bool> hasRxTx({
    required String deviceId,
    required String serviceUuid,
    required String rxUuid,
    required String txUuid,
  }) async {
    final t0 = DateTime.now();
    _logDebug('🔎 hasRxTx 开始: svc=$serviceUuid, rx=$rxUuid, tx=$txUuid');
    try {
      var services = _servicesByDevice[deviceId];
      if (services == null || services.isEmpty) {
        final ok = await discoverServices(deviceId);
        if (!ok) {
          final elapsed = DateTime.now().difference(t0).inMilliseconds;
          _logWithTimeDebug(
            'hasRxTx.result(${elapsed}ms) -> false (discover fail)',
          );
          return false;
        }
        services = _servicesByDevice[deviceId];
      }
      services ??= const <DiscoveredService>[];

      // 调试用：打印出来看设备实际暴露的服务
      _logDebug('[ble_connection_provider] services=$services');

      // 1. 先找到匹配的 service
      DiscoveredService? s;
      for (final svc in services) {
        final sid = svc.serviceId.toString();
        if (_uuidEqualsLoose(sid, serviceUuid)) {
          s = svc;
          break;
        }
      }

      if (s == null) {
        _logDebug('hasRxTx: service not found on device');
        final elapsed = DateTime.now().difference(t0).inMilliseconds;
        _logWithTimeDebug('hasRxTx.result(${elapsed}ms) -> false (no service)');
        return false;
      }

      // 2. 在该 service 下查 RX/TX 特征
      bool hasRx = false;
      bool hasTx = false;

      for (final c in s.characteristics) {
        final cid = c.characteristicId.toString();
        if (_uuidEqualsLoose(cid, rxUuid)) {
          hasRx = true;
        }
        if (_uuidEqualsLoose(cid, txUuid)) {
          hasTx = true;
        }
      }

      final ok = hasRx && hasTx;
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug(
        'hasRxTx.result(${elapsed}ms) -> $ok (hasRx=$hasRx, hasTx=$hasTx)',
      );
      return ok;
    } catch (e) {
      final elapsed = DateTime.now().difference(t0).inMilliseconds;
      _logWithTimeDebug('hasRxTx.fail(${elapsed}ms): $e');
      return false;
    }
  }

  /// 清理
  static void dispose() {
    _logInfo('🧹 dispose');
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _deviceConnectionSubscription?.cancel();
    _deviceConnectionSubscription = null;
    _scanController?.close();
    _scanController = null;
    try {
      _bleStatusSub?.cancel();
    } catch (_) {}
    _bleStatusSub = null;
    try {
      _connectionEventController.close();
    } catch (_) {}
    _discoveredDevices.clear();
    _isScanning = false;
    _hasActiveConnection = false;
    _activeDeviceId = null;
    _mtuByDevice.clear();
    _servicesByDevice.clear();
    _sessionStart = null;
  }
}

/// 扫描结果模型
class SimpleBLEScanResult {
  final String deviceId;
  final String name;
  final String address;
  final int rssi;
  final DateTime timestamp;
  final List<String> serviceUuids;
  final Map<String, List<int>>? serviceData;
  final Uint8List? manufacturerData;
  final List<int>? rawAdvertisementData;
  final bool connectable;

  SimpleBLEScanResult({
    required this.deviceId,
    required this.name,
    required this.address,
    required this.rssi,
    required this.timestamp,
    this.serviceUuids = const [],
    this.serviceData,
    this.manufacturerData,
    this.rawAdvertisementData,
    this.connectable = true,
  });

  static SimpleBLEScanResult fromDiscoveredDevice(DiscoveredDevice device) {
    return SimpleBLEScanResult(
      deviceId: device.id,
      name: device.name.isNotEmpty ? device.name : 'Unknown Device',
      address: device.id,
      rssi: device.rssi,
      timestamp: DateTime.now(),
      serviceUuids: device.serviceUuids.map((u) => u.toString()).toList(),
      serviceData: device.serviceData.map((k, v) => MapEntry(k.toString(), v)),
      manufacturerData: device.manufacturerData.isNotEmpty
          ? device.manufacturerData
          : null,
      connectable: device.connectable == Connectable.available,
    );
  }
}
