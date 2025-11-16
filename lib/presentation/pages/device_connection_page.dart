import 'dart:async';
import '../../core/log/app_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../core/l10n/l10n_extensions.dart';
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
  bool _navigated = false; // 防止多次 go()

  Future<void> _disconnectIfEphemeral() async {
    final conn = ref.read(bleConnectionProvider);
    final devId = conn.bleDeviceData?.displayDeviceId;
    final st = conn.bleDeviceStatus;
    final isBleConnected = st == BleDeviceStatus.scanning ||
        st == BleDeviceStatus.connecting ||
        st == BleDeviceStatus.connected ||
        st == BleDeviceStatus.authenticating ||
        st == BleDeviceStatus.authenticated;

    if (devId == null || devId.isEmpty || !isBleConnected) return;

    // 设备是否在已保存列表中
    await ref.read(savedDevicesProvider.notifier).load();
    final saved = ref.read(savedDevicesProvider);
    final inList = saved.devices.any((e) => e.displayDeviceId == devId);
    if (!inList) {
      AppLog.instance.info('[DeviceConnectionPage] 离开且设备不在列表，主动断开: $devId', tag: 'Binding');
      try {
        await ref.read(bleConnectionProvider.notifier).disconnect(shouldReset: true);
      } catch (e) {
        AppLog.instance.warning('[DeviceConnectionPage] disconnect error: $e', tag: 'Binding', error: e);
      }
      Fluttertoast.showToast(msg: context.l10n.ble_disconnected_ephemeral);
    }
  }

  void _clearAll() {
    ref.read(appStateProvider.notifier).clearScannedData();
    ref.read(qrScannerProvider.notifier).reset();
    ref.read(bleConnectionProvider.notifier).resetState();
  }

  Future<void> _disconnectAndClearIfNeeded() async {
    AppLog.instance.debug('[DeviceConnectionPage] _disconnectAndClearIfNeeded', tag: 'Binding');
    await _disconnectIfEphemeral();
    _clearAll();
  }

  @override
  void initState() {
    super.initState();
    AppLog.instance.debug('[DeviceConnectionPage] initState', tag: 'Binding');

    // 进入页面自动连接
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // 1. 检查扫到的设备
      final scannedQrData = ref.read(appStateProvider).scannedQrData;
      if (scannedQrData == null) {
        AppLog.instance.debug('[DeviceConnectionPage] scannedQrData is null', tag: 'Binding');
        if (!_noDataDialogShown) _showNoDataError();
        return;
      }

      // 2. 自动连接
      AppLog.instance.info('[DeviceConnectionPage] startConnection ${scannedQrData.deviceName} (${scannedQrData.bleDeviceId}', tag: 'Binding');
      try {
        final ok = await ref
            .read(bleConnectionProvider.notifier)
            .enableBleConnection(scannedQrData);
        if (ok && context.mounted) Fluttertoast.showToast(msg: context.l10n.connect_success);
      } catch (e, s) {
        AppLog.instance.error('[DeviceConnectionPage] startConnection error', tag: 'Binding', error: e, stackTrace: s);
        if (context.mounted) {
          Fluttertoast.showToast(msg: context.l10n.connect_failed_retry);
        }
      }
    });
  }

  void _setupBleStatusListener() {
    ref.listen<BleConnectionState>(
      bleConnectionProvider,
          (previous, current) async {
        if (!mounted) return;

        final prevBleStatus = previous?.bleDeviceStatus;
        final curBleStatus = current.bleDeviceStatus;
        if (curBleStatus != prevBleStatus) {
          AppLog.instance.debug('[DeviceConnectionPage] 蓝牙状态变化 $prevBleStatus -> $curBleStatus', tag: 'Binding');
          if (curBleStatus == BleDeviceStatus.authenticated) {
            if (_navigated) return; // 防抖
            _navigated = true;

            final curDisplayDeviceId = current.bleDeviceData?.displayDeviceId;
            final networkStatus = await ref
                .read(bleConnectionProvider.notifier)
                .checkNetworkStatus();

            if (!mounted) return;
            final idParam = Uri.encodeComponent(curDisplayDeviceId ?? "");

            final curEmptyBound = current.emptyBound;
            AppLog.instance.debug('[DeviceConnectionPage] curDisplayDeviceId=$curDisplayDeviceId, emptyBound=${curEmptyBound}', tag: 'Binding');
            if (networkStatus?.connected == true) {
              // 设备有网
              if (curEmptyBound) {
                // 设备要绑定
                context.go('${AppRoutes.bindConfirm}?displayDeviceId=$idParam');
              } else {
                // 设备已绑定
                context.go('${AppRoutes.home}?displayDeviceId=$idParam');
              }
            } else {
              // 设备无网
              context.go('${AppRoutes.wifiSelection}?scannedDisplayDeviceId=$idParam');
            }
            return;
          }

          if (curBleStatus == BleDeviceStatus.error ||
              curBleStatus == BleDeviceStatus.timeout) {
            // Show specific reason when available (e.g., device already bound elsewhere)
            final code = current.lastErrorCode;
            if (code == 'user_mismatch') {
              Fluttertoast.showToast(msg: context.l10n.device_bound_elsewhere);
            } else {
              Fluttertoast.showToast(msg: context.l10n.connect_failed_move_closer);
            }
            if (!mounted) return;
            _clearAll();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.home);
            }
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 监听蓝牙连接状态
    _setupBleStatusListener();

    final connectionState = ref.watch(bleConnectionProvider);

    return PopScope(
      // 允许系统返回手势/按钮先尝试出栈
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          unawaited(_disconnectAndClearIfNeeded());
        }
      },
      child: Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(context.l10n.connect_device_title),
        elevation: 0,
        // 使用主题默认的 AppBar 配色，去掉硬编码的蓝色
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
              await _disconnectAndClearIfNeeded();
              if (!mounted) return;
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
                      Row(
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
                            context.l10n.ble_connecting,
                            style: const TextStyle(fontSize: 16),
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
    final app = ref.watch(appStateProvider);
    final qrDeviceData = app.scannedQrData;

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
                        qrDeviceData?.deviceName ?? context.l10n.unknown_device,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
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

  /// 显示无数据错误
  void _showNoDataError() {
    _noDataDialogShown = true;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.error_title),
        content: Text(context.l10n.no_device_data_message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (!mounted) return;
              _clearAll();
              context.go(AppRoutes.qrScanner);
            },
            child: Text(context.l10n.rescan),
          ),
        ],
      ),
    );
  }
}
