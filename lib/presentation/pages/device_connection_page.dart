import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../core/router/app_router.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/ble/ble_device_data.dart';
import '../../core/models/device_qr_data.dart';
import '../../core/providers/ble_connection_provider.dart';
import '../../features/qr_scanner/providers/qr_scanner_provider.dart';

class DeviceConnectionPage extends ConsumerStatefulWidget {
  const DeviceConnectionPage({super.key, required this.deviceId});
  
  final String deviceId;

  @override
  ConsumerState<DeviceConnectionPage> createState() => _DeviceConnectionPageState();
}

class _DeviceConnectionPageState extends ConsumerState<DeviceConnectionPage> {

  @override
  void initState() {
    super.initState();
    print('[DeviceConnectionPage] initState');
  }

  bool _autoStarted = false;
  bool _networkCheckStarted = false; // 防重复触发带重试的网络检查，避免监听循环
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoStarted) return;
    final deviceData =
        ref.read(appStateProvider.notifier).getDeviceDataById(widget.deviceId);
    if (deviceData == null) {
      _showNoDataError();
      return;
    }
    // 不能在build生命周期内直接改provider，使用microtask延迟到本帧结束后
    Future.microtask(() {
      // ignore: avoid_print
      print('[DeviceConnectionPage] microtask -> start connect');
      ref.read(bleConnectionProvider.notifier).startConnection(deviceData);
    });
    // ignore: avoid_print
    print(
        '[DeviceConnectionPage] didChangeDependencies scheduled auto start: ${deviceData.deviceName} (${deviceData.bleDeviceId})');
    _autoStarted = true;
  }

  @override
  void dispose() {
    _networkCheckStarted = false;
    super.dispose();
  }

  /// 显示无数据错误
  void _showNoDataError() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误'),
        content: const Text('未找到设备数据，请重新扫描二维码。'),
        actions: [
          TextButton(
            onPressed: () {
              context.go(AppRoutes.qrScanner);
            },
            child: const Text('重新扫描'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(bleConnectionProvider);

    // 返回或手动触发时：若蓝牙已连接且设备不在已保存列表，则强制断开
    Future<void> _maybeDisconnectIfEphemeral() async {
      final conn = ref.read(bleConnectionProvider);
      final devId = conn.bleDeviceData?.displayDeviceId;
      final st = conn.bleDeviceStatus;
      final isBleConnected = st == BleDeviceStatus.connected ||
          st == BleDeviceStatus.authenticating ||
          st == BleDeviceStatus.authenticated;
      if (devId == null || devId.isEmpty || !isBleConnected) return;
      await ref.read(savedDevicesProvider.notifier).load();
      final saved = ref.read(savedDevicesProvider);
      final inList = saved.devices.any((e) => e.displayDeviceId == devId);
      if (!inList) {
        // ignore: avoid_print
        print('[DeviceConnectionPage] 返回且设备不在列表，主动断开BLE: $devId');
        await ref.read(bleConnectionProvider.notifier).disconnect();
        Fluttertoast.showToast(msg: '已断开未绑定设备的蓝牙连接');
      }
    }
    
    // 注册状态监听器，在认证完成时跳转首页
    ref.listen<BleConnectionState>(bleConnectionProvider,
        (previous, current) async {
      if (!mounted) return; // 防止页面销毁后继续处理
      if (previous?.bleDeviceStatus != current.bleDeviceStatus) {
        // ignore: avoid_print
        print(
            '[DeviceConnectionPage] 状态变化: ${previous?.bleDeviceStatus} -> ${current.bleDeviceStatus}');
      }
      // 特殊错误：设备已被其他账号绑定
      if (current.bleDeviceStatus == BleDeviceStatus.error &&
          (
            current.errorMessage == '设备已被其他账号绑定' ||
            (current.errorMessage?.contains('已被其他账号绑定') ?? false) ||
            // 兜底：最近一次握手错误码为 user_mismatch
              (ref.read(bleConnectionProvider).lastHandshakeErrorCode ==
                  'user_mismatch') ||
              // 回退策略：若扫码校验结果表明已被绑定，且在握手阶段失败，也给出相同提示
              (ref.read(appStateProvider).scannedIsBound == true &&
                  (previous?.bleDeviceStatus ==
                          BleDeviceStatus.authenticating ||
                      previous?.bleDeviceStatus ==
                          BleDeviceStatus.connected)))) {
        // Toast 提示并回到扫码前的页面；没有则回到设备详情
        Fluttertoast.showToast(msg: '设备已被其他账号绑定');
        if (mounted) {
          // 清理扫描与连接状态
          ref.read(appStateProvider.notifier).clearScannedDeviceData();
          ref.read(bleConnectionProvider.notifier).resetState();
          ref.read(qrScannerProvider.notifier).reset();
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.home);
          }
        }
        return;
      }
      // 其他连接相关错误：toast 并回退到扫码前页面；没有则回到设备详情
      if (current.bleDeviceStatus == BleDeviceStatus.error ||
          current.bleDeviceStatus == BleDeviceStatus.timeout) {
        final msg = current.errorMessage ?? '连接失败，请重试';
        Fluttertoast.showToast(msg: msg);
        if (mounted) {
          ref.read(appStateProvider.notifier).clearScannedDeviceData();
          ref.read(bleConnectionProvider.notifier).resetState();
          ref.read(qrScannerProvider.notifier).reset();
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.home);
          }
        }
        return;
      }
      if (current.bleDeviceStatus == BleDeviceStatus.authenticated &&
          current.bleDeviceData != null) {
        final d = current.bleDeviceData!;
        print('[DeviceConnectionPage] 🎉 认证完成');

        // 统一在认证后先检查网络（新帧协议由 provider 内部处理）
        if (_networkCheckStarted) return; // 防重复
        _networkCheckStarted = true;

        final app = ref.read(appStateProvider);
        final scanned = app.scannedDeviceData;
        final isSame = scanned?.bleDeviceId == d.displayDeviceId;
        final isUnboundScan = isSame && (app.scannedIsBound == false);

        print('[DeviceConnectionPage] 认证后检查网络状态（带重试）');
        final connected = await _checkNetworkWithRetry(ref);
        final shouldGoWifi = (connected == false) || (isUnboundScan && connected != true);
        if (shouldGoWifi) {
          // 无网优先（或未知但为未绑定新设备）：跳转 Wi‑Fi 配网
          print('[DeviceConnectionPage] 📶 设备离线/未知(未绑定) → 跳转Wi‑Fi配网页面');
          if (mounted) {
            context.go(
                '${AppRoutes.wifiSelection}?deviceId=${Uri.encodeComponent(d.displayDeviceId)}');
          }
          return;
        }

        // 已联网：若未绑定则去绑定页，否则进入首页
        if (isUnboundScan) {
          print('[DeviceConnectionPage] 设备未绑定 → 跳转绑定确认');
          if (mounted) {
            context.go(
                '${AppRoutes.bindConfirm}?deviceId=${Uri.encodeComponent(d.displayDeviceId)}');
          }
          return;
        }

        // 保存并进入首页（设备详情页）
        final qr = DeviceQrData(
          displayDeviceId: d.displayDeviceId,
          deviceName: d.deviceName,
          bleDeviceId: d.bleDeviceId,
          publicKey: d.publicKey,
        );
        print('[DeviceConnectionPage] 保存设备数据: ${d.displayDeviceId}');
        await ref.read(savedDevicesProvider.notifier).selectFromQr(qr);
        print('[DeviceConnectionPage] 选择设备: ${d.displayDeviceId}');
        if (mounted) {
          context.go(AppRoutes.home);
          print('[DeviceConnectionPage] ✅ 已执行跳转首页');
        }
      }
    });

    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          await _maybeDisconnectIfEphemeral();
        }
      },
      child: Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('连接设备'),
        elevation: 0,
        // 使用主题默认的 AppBar 配色，去掉硬编码的蓝色
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            // 返回前进行断开判断（需等待执行完成，避免在导航后错过断开时机）
            await _maybeDisconnectIfEphemeral();
            // 清理状态并返回扫描页面
            ref.read(appStateProvider.notifier).clearScannedDeviceData();
              ref.read(bleConnectionProvider.notifier).resetState();
              ref.read(qrScannerProvider.notifier).reset();
              context.go(AppRoutes.qrScanner);
          },
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48, // 减去padding
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 设备信息卡片
                    _buildDeviceInfoCard(connectionState),
                    
                    const SizedBox(height: 32),
                    
                    // 连接进度
                    _buildConnectionProgress(connectionState),
                    
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  }

  /// 构建设备信息卡片
  Widget _buildDeviceInfoCard(BleConnectionState state) {
    // 从全局状态获取QR扫描的设备数据
    final qrDeviceData = ref.read(appStateProvider.notifier).getDeviceDataById(widget.deviceId);
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.tv,
                    color: Colors.grey,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        qrDeviceData?.deviceName ?? '智能显示器',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${qrDeviceData?.bleDeviceId ?? widget.deviceId}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.info_outline,
                  color: Colors.blue,
                  size: 24,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 带重试的网络状态检查
  /// 返回：true=已联网，false=未联网，null=未知
  Future<bool?> _checkNetworkWithRetry(WidgetRef ref) async {
    const attempts = 2; // 快速判断首跳，避免等待
    const delayMs = 300; // 每次重试间隔（更短）
    bool? last;
    if (!mounted) return null;

    // 只在挂载时读取一次，避免在组件销毁后再次触发 ref.read
    final connNotifier = ref.read(bleConnectionProvider.notifier);
    final swTotal = Stopwatch()..start();
    for (var i = 0; i < attempts; i++) {
      if (!mounted) return last;
      final sw = Stopwatch()..start();
      final ns = await connNotifier.checkNetworkStatus();
      sw.stop();
      // ignore: avoid_print
      print('[DeviceConnectionPage][⏱] network.status attempt ${i + 1}/$attempts: ${sw.elapsedMilliseconds} ms, result=${ns?.connected}');
      if (ns != null) {
        last = ns.connected;
        if (ns.connected == true) return true; // 提前返回
      }
      if (i < attempts - 1) {
        await Future.delayed(const Duration(milliseconds: delayMs));
        if (!mounted) return last;
      }
    }
    swTotal.stop();
    // ignore: avoid_print
    print('[DeviceConnectionPage][⏱] network.status total: ${swTotal.elapsedMilliseconds} ms, final=${last}');
    return last; // 可能为false或null（未知）
  }

  /// 构建连接进度
  Widget _buildConnectionProgress(BleConnectionState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('连接进度',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        _buildProgressSteps(state),
      ],
    );
  }

  /// 构建进度步骤
  Widget _buildProgressSteps(BleConnectionState state) {
    final steps = [
      ('检查权限', BleDeviceStatus.disconnected),
      ('扫描设备', BleDeviceStatus.scanning),
      ('建立连接', BleDeviceStatus.connecting),
      ('设备认证', BleDeviceStatus.authenticating),
      ('连接完成', BleDeviceStatus.authenticated),
    ];

    return Column(
      children: steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;
        final isActive = _getStepIndex(state.bleDeviceStatus) >= index;
        final isCurrent = _getStepIndex(state.bleDeviceStatus) == index;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: isActive
                      ? _getStatusColor(state.bleDeviceStatus)
                      : Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: isActive
                  ? Icon(
                      isCurrent ? Icons.radio_button_checked : Icons.check,
                      color: Colors.white,
                      size: 12,
                    )
                  : null,
              ),
              const SizedBox(width: 12),
              Text(
                step.$1,
                style: TextStyle(
                  fontSize: 14,
                  color: isActive ? Colors.black87 : Colors.grey[500],
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 获取步骤索引
  int _getStepIndex(BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.disconnected:
        return 0;
      case BleDeviceStatus.scanning:
        return 1;
      case BleDeviceStatus.connecting:
        return 2;
      case BleDeviceStatus.connected:
        return 2;
      case BleDeviceStatus.authenticating:
        return 3;
      case BleDeviceStatus.authenticated:
        return 4;
      case BleDeviceStatus.error:
      case BleDeviceStatus.timeout:
        return 0;
    }
  }

  /// 获取状态颜色
  Color _getStatusColor(BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.disconnected:
        return Colors.grey;
      case BleDeviceStatus.scanning:
        return Colors.blue;
      case BleDeviceStatus.connecting:
        return Colors.orange;
      case BleDeviceStatus.connected:
        return Colors.orange;
      case BleDeviceStatus.authenticating:
        return Colors.purple;
      case BleDeviceStatus.authenticated:
        return Colors.green;
      case BleDeviceStatus.error:
        return Colors.red;
      case BleDeviceStatus.timeout:
        return Colors.red;
    }
  }
}
