import 'dart:async';
import '../../core/constants/enum.dart';
import '../../core/log/app_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/models/device_qr_data.dart';
import '../../core/router/app_router.dart';
import '../../core/providers/app_state_provider.dart';
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

  bool _autoStarted = false;

  void _clearAll() {
    ref.read(appStateProvider.notifier).clearScannedData();
    ref.read(bleConnectionProvider.notifier).resetState();
  }
  Future<void> _disconnectAndClearOnUserExit() async {
    await BindingFlowUtils.disconnectAndClearOnUserExit(context, ref);
  }

  _goBackOrHome() {
    if (!mounted) return;
    _clearAll();
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  // 蓝牙连接 + 跳转判断
  Future<void> _autoConnect(DeviceQrData scannedQrData) async {
    try {
      final result = await ref
          .read(bleConnectionProvider.notifier)
          .enableBleConnection(scannedQrData);
      if (!mounted) return;

      // 1) 失败分支：完全由 result 决定
      if (result == BleConnectResult.userMismatch) {
        Fluttertoast.showToast(msg: context.l10n.device_bound_elsewhere);
        _goBackOrHome();
        return;
      }

      if (result == BleConnectResult.failed ||
          result == BleConnectResult.cancelled) {
        Fluttertoast.showToast(msg: context.l10n.connect_failed_retry);
        _goBackOrHome();
        return;
      }

      // 2) 成功分支（success / alreadyConnected）：只读一次 state 拿跳转参数
      Fluttertoast.showToast(msg: context.l10n.connect_success);

      final st = ref.read(bleConnectionProvider);
      final displayId =
          st.bleDeviceData?.displayDeviceId ?? scannedQrData.displayDeviceId;
      final idParam = Uri.encodeComponent(displayId);

      final ns =
          await ref.read(bleConnectionProvider.notifier).checkNetworkStatus();
      if (!mounted) return;

      if (ns?.connected == true) {
        if (st.emptyBound) {
          context.go('${AppRoutes.bindConfirm}?displayDeviceId=$idParam');
        } else {
          context.go('${AppRoutes.home}?displayDeviceId=$idParam');
        }
      } else {
        context
            .go('${AppRoutes.wifiSelection}?scannedDisplayDeviceId=$idParam');
      }
    } catch (e, s) {
      AppLog.instance.error('[DeviceConnectionPage] startConnection error',
          tag: 'Binding', error: e, stackTrace: s);
      if (!mounted) return;
      Fluttertoast.showToast(msg: context.l10n.connect_failed_retry);
      _goBackOrHome();
    }
  }

  @override
  void initState() {
    super.initState();
    AppLog.instance.debug('[DeviceConnectionPage] initState', tag: 'Binding');

    // 进入页面自动连接
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _autoStarted) return;
      _autoStarted = true;

      // 1. 检查扫到的设备
      final scannedQrData = ref.read(appStateProvider).scannedQrData;
      if (scannedQrData == null) {
        AppLog.instance.debug('[DeviceConnectionPage] scannedQrData is null', tag: 'Binding');
        if (!_noDataDialogShown) _showNoDataError();
        return;
      }

      // 2. 自动连接
      AppLog.instance.info(
        '[DeviceConnectionPage] startConnection ${scannedQrData.deviceName} (${scannedQrData.bleDeviceId})',
        tag: 'Binding',
      );
      _autoConnect(scannedQrData);
    });
  }

  @override
  Widget build(BuildContext context) {
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
