import 'dart:async';
import '../../core/constants/enum.dart';
import '../../core/log/app_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/router/app_router.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/ble/ble_device_data.dart';
import '../../core/providers/ble_connection_provider.dart';
import '../../core/utils/binding_flow_utils.dart';

class DeviceConnectionPage extends ConsumerStatefulWidget {
  const DeviceConnectionPage({super.key, required this.displayDeviceId});
  
  final String displayDeviceId;

  @override
  ConsumerState<DeviceConnectionPage> createState() => _DeviceConnectionPageState();
}

class _DeviceConnectionPageState extends ConsumerState<DeviceConnectionPage> {
  bool _noDataDialogShown = false;
  bool _navigated = false; // 防止多次 go()

  void _clearAll() {
    ref.read(appStateProvider.notifier).clearScannedData();
    ref.read(bleConnectionProvider.notifier).resetState();
  }
  Future<void> _disconnectAndClearOnUserExit() async {
    await BindingFlowUtils.disconnectAndClearOnUserExit(context, ref);
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
        final result = await ref
            .read(bleConnectionProvider.notifier)
            .enableBleConnection(scannedQrData);
        if (!mounted) return;
        if (result == BleConnectResult.success ||
            result == BleConnectResult.alreadyConnected) {
          Fluttertoast.showToast(msg: context.l10n.connect_success);
        }
      } catch (e, s) {
        AppLog.instance.error('[DeviceConnectionPage] startConnection error', tag: 'Binding', error: e, stackTrace: s);
        if (mounted) {
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

        // 仅处理当前页面目标设备的状态变化，避免其他设备的旧会话干扰
        final curDeviceId = current.bleDeviceData?.displayDeviceId ?? '';
        if (widget.displayDeviceId.isNotEmpty &&
            curDeviceId.isNotEmpty &&
            curDeviceId != widget.displayDeviceId) {
          return;
        }

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
          unawaited(_disconnectAndClearOnUserExit());
        }
      },
      child: Scaffold(
      // Use themed background to support dark mode
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(context.l10n.connect_device_title),
        elevation: 0,
        // 使用主题默认的 AppBar 配色，去掉硬编码的蓝色
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
              await _disconnectAndClearOnUserExit();
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
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            context.l10n.ble_connecting,
                            style: Theme.of(context).textTheme.bodyMedium,
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

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
                    color: colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.tv,
                    color: colorScheme.onSurfaceVariant,
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
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.info_outline,
                  color: colorScheme.primary,
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
