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
import '../../core/providers/ble_connection_provider.dart';
import '../../features/qr_scanner/providers/qr_scanner_provider.dart';

class DeviceConnectionPage extends ConsumerStatefulWidget {
  const DeviceConnectionPage({super.key, required this.displayDeviceId});
  
  final String displayDeviceId;

  @override
  ConsumerState<DeviceConnectionPage> createState() => _DeviceConnectionPageState();
}

class _DeviceConnectionPageState extends ConsumerState<DeviceConnectionPage> {
  bool _noDataDialogShown = false;

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
      _clear();
      Fluttertoast.showToast(msg: '已断开未绑定设备的蓝牙连接');
    }
  }

  @override
  void initState() {
    super.initState();
    print('[DeviceConnectionPage] initState');

    // 进入页面自动连接
    // 延后到首帧后触发，避免在 build 同帧里改 provider
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final deviceData = ref
          .read(appStateProvider.notifier)
          .getDeviceDataById(widget.displayDeviceId);
      if (deviceData == null) {
        if (!_noDataDialogShown) _showNoDataError();
        return;
      }

      // ignore: avoid_print
      print(
          '[DeviceConnectionPage] start connect -> ${deviceData.deviceName} (${deviceData.bleDeviceId})');

      try {
        final ok = await ref
            .read(bleConnectionProvider.notifier)
            .startConnection(deviceData);
        if (ok) Fluttertoast.showToast(msg: "连接成功");
      } catch (e, s) {
        // ignore: avoid_print
        print('[DeviceConnectionPage] startConnection error: $e\n$s');
        Fluttertoast.showToast(msg: '连接失败，请重试');
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final deviceData =
        ref.read(appStateProvider.notifier).getDeviceDataById(widget.displayDeviceId);
    if (deviceData == null) {
      // 在首帧后再弹窗，避免在build阶段触发导航造成 _debugLocked 断言
      if (!_noDataDialogShown) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _noDataDialogShown) return;
          _showNoDataError();
        });
      }
      return;
    }
  }

  void _clear() {
    ref.read(appStateProvider.notifier).clearScannedDeviceData();
    ref.read(bleConnectionProvider.notifier).resetState();
    ref.read(qrScannerProvider.notifier).reset();
  }

  void _clearAndBackToEntry() {
    _clear();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  void _listenToBleConnectionState() {
    ref.listen<BleConnectionState>(
      bleConnectionProvider,
          (previous, current) async {
        if (!mounted) return;

        final prev = previous?.bleDeviceStatus;
        final cur = current.bleDeviceStatus;
        if (cur != prev) {
          // ignore: avoid_print
          print('[DeviceConnectionPage] 蓝牙状态变化 $prev -> $cur');
          if (cur == BleDeviceStatus.authenticated) {
            final curDisplayDeviceId = current.bleDeviceData?.displayDeviceId;
            final networkStatus = await ref
                .read(bleConnectionProvider.notifier)
                .checkNetworkStatus();

            if (!mounted) return;
            final idParam = Uri.encodeComponent(curDisplayDeviceId ?? "");

            print('[device_connection_page] curDisplayDeviceId=$curDisplayDeviceId');
            if (networkStatus?.connected == true) {
              context.go('${AppRoutes.bindConfirm}?displayDeviceId=$idParam');
            } else {
              context.go('${AppRoutes.wifiSelection}?displayDeviceId=$idParam');
            }
            return;
          }

          if (cur == BleDeviceStatus.error || cur == BleDeviceStatus.timeout) {
            final code = ref.read(bleConnectionProvider).lastHandshakeErrorCode;
            Fluttertoast.showToast(
                msg: code == 'user_mismatch' ? '设备已被其他账号绑定' : '连接失败，请靠近重试');

            if (!mounted) return;
            _clearAndBackToEntry();
          }
        }
      },
    );
  }

  /// 显示无数据错误
  void _showNoDataError() {
    _noDataDialogShown = true;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误'),
        content: const Text('未找到设备数据，请重新扫描二维码。'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (!mounted) return;
              _clear();
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
    _listenToBleConnectionState();

    final connectionState = ref.watch(bleConnectionProvider);

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
              _clear();
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
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            "蓝牙连接中...",
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),

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
    final qrDeviceData = ref.read(appStateProvider.notifier).getDeviceDataById(widget.displayDeviceId);
    
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
                        'ID: ${qrDeviceData?.bleDeviceId ?? widget.displayDeviceId}',
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

  @override
  void dispose() {
    // 可选兜底：避免页面异常离开时留下未绑定连接
    // 这里注意：不要阻塞 dispose，可 fire-and-forget
    () async {
      try {
        await _maybeDisconnectIfEphemeral();
      } catch (_) {}
    }();
    super.dispose();
  }
}
