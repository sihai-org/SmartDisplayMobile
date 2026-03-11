import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_display_mobile/core/utils/data_transformer.dart';
import 'package:smart_display_mobile/presentation/widgets/device_card.dart';
import '../../core/constants/enum.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/router/app_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../data/repositories/saved_devices_repository.dart';
import '../../core/ble/ble_device_data.dart';
import '../../core/network/network_status.dart';
import '../../core/models/device_qr_data.dart';
import '../../core/log/app_log.dart';
import '../../core/providers/ble_connection_provider.dart' as conn;
import '../../core/providers/device_ble_view_state.dart';
import '../../core/providers/device_unbind_coordinator.dart';
import '../../core/utils/wifi_signal_strength.dart';

class DeviceDetailPage extends ConsumerStatefulWidget {
  final VoidCallback? onBackToList;
  // 可选：指定进入本页时要连接/展示的设备ID
  final String? deviceId;
  const DeviceDetailPage({super.key, this.onBackToList, this.deviceId});

  @override
  ConsumerState<DeviceDetailPage> createState() => _DeviceDetailState();
}

class _DeviceDetailState extends ConsumerState<DeviceDetailPage> {
  bool _paramSelectTried = false; // 仅根据外部传入 deviceId 自动选中一次
  bool _checkingUpdate = false;

  DeviceQrData? _qrFromRecord(SavedDeviceRecord rec) {
    // 允许缺少本地缓存的 BLE 地址：连接流程会在扫描后用发现的地址覆盖。
    // 仅当关键标识缺失时才放弃（如 deviceId/publicKey）。
    if (rec.displayDeviceId.isEmpty || rec.publicKey.isEmpty) {
      Fluttertoast.showToast(msg: context.l10n.missing_ble_params);
      return null;
    }
    final bleAddress = rec.lastBleDeviceId ?? '';
    return DeviceQrData(
      displayDeviceId: rec.displayDeviceId,
      deviceName: rec.deviceName,
      bleDeviceId: bleAddress,
      publicKey: rec.publicKey,
    );
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '-';
    // Simple human-readable format: yyyy-MM-dd HH:mm
    String two(int n) => n.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final m = two(dt.month);
    final d = two(dt.day);
    final hh = two(dt.hour);
    final mm = two(dt.minute);
    return '$y-$m-$d $hh:$mm';
  }

  @override
  void initState() {
    super.initState();
    // 根据param选中（仅一次）
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _trySelectAndConnectByParam(),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DeviceDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当父组件传入的 deviceId 发生变化时，尝试选中
    final prev = oldWidget.deviceId ?? '';
    final curr = widget.deviceId ?? '';
    if (curr.isNotEmpty && curr != prev) {
      _paramSelectTried = false; // 允许对新的参数再次尝试
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _trySelectAndConnectByParam(),
      );
    }
  }

  // 如果通过 MainPage 传入了 deviceId，尝试选中
  Future<void> _trySelectAndConnectByParam() async {
    // 仅一次
    if (_paramSelectTried) return;
    _paramSelectTried = true;

    AppLog.instance.info(
      "[ble_connection_provider] trySelectByParamOnce ${widget.deviceId}",
    );

    // 空就保持现状
    final targetId = widget.deviceId;
    if (targetId == null || targetId.isEmpty) return;

    // 尝试选中并连接
    final notifier = ref.read(savedDevicesProvider.notifier);
    final rec = notifier.findById(targetId);
    if (rec != null) {
      AppLog.instance.info(
        "[ble_connection_provider] trySelectByParamOnce select ${targetId}",
      );
      await notifier.select(targetId);
      final result = await ref
          .read(conn.bleConnectionProvider.notifier)
          .enableBleConnection(savedDeviceRecordToQrData(rec));
      _safelyToastConnectRes(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final savedNotifier = ref.read(savedDevicesProvider.notifier);
    final saved = ref.watch(savedDevicesProvider);
    final connState = ref.watch(conn.bleConnectionProvider);

    // 针对“当前详情设备”的 BLE 状态（避免被其他设备的全局状态干扰）
    final bleView = buildDeviceBleViewStateForCurrent(savedNotifier, connState);

    return Scaffold(
      appBar: AppBar(
        leading: widget.onBackToList != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBackToList,
              )
            : null,
        title: Text(context.l10n.current_device),
        actions: [
          if (saved.loaded && saved.devices.isNotEmpty)
            IconButton(
              onPressed: () => context.push(AppRoutes.deviceManagement),
              icon: const Icon(Icons.list),
            ),
          IconButton(
            onPressed: () => context.push(AppRoutes.qrScanner),
            icon: const Icon(Icons.add),
            tooltip: context.l10n.scan_qr,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (saved.devices.isEmpty) ...[
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      kToolbarHeight -
                      AppConstants.defaultPadding * 2 -
                      MediaQuery.of(context).padding.bottom,
                ),
                child: Align(
                  alignment: Alignment(0, -0.3), // 0 是中间，-1 顶部，+1 底部。-0.3 稍微上移,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/no_device.png',
                        width: 160,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 40),
                      Text(
                        l10n.no_device_title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width:
                            MediaQuery.of(context).size.width *
                            0.6, // 宽度占屏幕 3/5
                        child: Text(
                          l10n.no_device_subtitle,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // 👇 扫码按钮
                      ElevatedButton.icon(
                        onPressed: () => context.push(AppRoutes.qrScanner),
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: Text(context.l10n.scan_qr_add_device),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          textStyle: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // 选择要展示的设备及其扩展信息
              Builder(
                builder: (context) {
                  final rec = bleView.currentDevice;
                  final versionSlot = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 仅在蓝牙已连接到当前设备时显示“检查更新”按钮
                      if (bleView.bleStatus ==
                          BleDeviceStatus.authenticated) ...[
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: Theme.of(context).textTheme.bodyMedium,
                            overlayColor: Colors.transparent,
                          ),
                          onPressed: _checkingUpdate
                              ? null
                              : () {
                                  _sendCheckUpdate(rec);
                                },
                          child: Text(context.l10n.check_update),
                        ),
                        if (_checkingUpdate) ...[
                          const SizedBox(width: 6),
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        ],
                      ],
                    ],
                  );

                  return Stack(
                    children: [
                      DeviceCard(
                        name: rec.deviceName,
                        id: rec.displayDeviceId,
                        version: rec.firmwareVersion,
                        lastConnectedAt: rec.lastConnectedAt,
                        versionSlot: versionSlot,
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 16),
              _buildBLESection(
                context,
                uiStatus: bleView.uiStatus,
                bleOnLoadingForCurrent: bleView.isLoadingForCurrent,
              ),

              // 显示网络状态或WiFi列表
              if (bleView.bleStatus == BleDeviceStatus.authenticated) ...[
                const SizedBox(height: 16),
                _buildNetworkSection(context, connState),
                // 删除设备按钮
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).cardColor, // 背景颜色
                    foregroundColor: Theme.of(
                      context,
                    ).colorScheme.error, // 文字颜色
                    elevation: 0, // 阴影高度
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12), // 圆角
                    ),
                  ),
                  onPressed: () {
                    _showDeleteDialog(context, bleView.currentDevice);
                  },
                  child: Text(context.l10n.delete_device),
                ),
              ],
            ],

            const SizedBox(height: 32),

            // 底部安全区域
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  void _safelyToastConnectRes(BleConnectResult res) {
    if (!mounted) return;
    switch (res) {
      case BleConnectResult.success:
      case BleConnectResult.alreadyConnected:
      case BleConnectResult.cancelled:
        // 成功或被新会话覆盖的旧请求，都无需在此处提示
        break;
      case BleConnectResult.userMismatch:
        Fluttertoast.showToast(msg: context.l10n.device_bound_elsewhere);
        AppLog.instance.info("ble: 用户不匹配");
        break;
      case BleConnectResult.failed:
        Fluttertoast.showToast(msg: context.l10n.connect_failed_retry);
        AppLog.instance.info("ble: 连接失败");
        break;
      case BleConnectResult.timeout:
        Fluttertoast.showToast(
          msg: context.l10n.ble_connect_timeout_relaunch_toast,
        );
        AppLog.instance.error("[device_detail_page] ble: 连接超时（提示重启App）");
        break;
      case BleConnectResult.scanTimeout:
        Fluttertoast.showToast(
          msg: context.l10n.ble_scan_timeout_device_not_found,
        );
        AppLog.instance.info("ble: 扫描超时");
        break;
      case BleConnectResult.notReady:
        Fluttertoast.showToast(
          msg: context.l10n.ble_not_ready_enable_bluetooth_check_permission,
        );
        AppLog.instance.info("ble: 蓝牙未就绪");
        break;
    }
  }

  void _safelyToastDeviceUpdateCheckRes(DeviceUpdateVersionResult res) {
    if (!mounted) return;
    switch (res) {
      case DeviceUpdateVersionResult.updating:
        Fluttertoast.showToast(msg: context.l10n.update_started);
        break;
      case DeviceUpdateVersionResult.alreadyInFlight:
        Fluttertoast.showToast(msg: context.l10n.update_in_progress);
        break;
      case DeviceUpdateVersionResult.latest:
        Fluttertoast.showToast(msg: context.l10n.already_latest_version);
        break;
      case DeviceUpdateVersionResult.optionalUpdate:
        Fluttertoast.showToast(msg: context.l10n.optional_update_available);
        break;
      case DeviceUpdateVersionResult.throttled:
        Fluttertoast.showToast(msg: context.l10n.update_throttled_retry);
        break;
      case DeviceUpdateVersionResult.rejectedLowStorage:
        Fluttertoast.showToast(msg: context.l10n.update_low_storage_retry);
        break;
      case DeviceUpdateVersionResult.failed:
        Fluttertoast.showToast(msg: context.l10n.check_update_failed_retry);
        break;
    }
  }

  void _sendCheckUpdate(SavedDeviceRecord device) async {
    if (_checkingUpdate) return; // 简单防抖
    setState(() => _checkingUpdate = true);

    try {
      final notifier = ref.read(conn.bleConnectionProvider.notifier);
      final result = await notifier.requestUpdateCheck();
      _safelyToastDeviceUpdateCheckRes(result);
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(msg: context.l10n.check_update_failed_retry);
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  // 蓝牙卡片（所有状态统一在 build() 中按当前设备计算，这里只负责展示）
  Widget _buildBLESection(
    BuildContext context, {
    required BleDeviceStatus uiStatus,
    required bool bleOnLoadingForCurrent,
  }) {
    final saved = ref.watch(savedDevicesProvider);
    final savedNotifier = ref.read(savedDevicesProvider.notifier);

    // 目标视觉：左侧状态图标 + 文案，右侧开关
    // 三种状态：
    // - 已连接（开关开、勾选图标、蓝色）
    // - 连接中（开关开、扫描图标、蓝色）
    // - 未开启/未连接（开关关、提示图标、灰色）
    bool computedIsOn() {
      switch (uiStatus) {
        case BleDeviceStatus.scanning:
        case BleDeviceStatus.connecting:
        case BleDeviceStatus.connected:
        case BleDeviceStatus.authenticating:
        case BleDeviceStatus.authenticated:
          return true;
        case BleDeviceStatus.error:
        case BleDeviceStatus.timeout:
        case BleDeviceStatus.disconnected:
        default:
          return false;
      }
    }

    final titleText = () {
      switch (uiStatus) {
        case BleDeviceStatus.authenticated:
        case BleDeviceStatus.connected:
          return context.l10n.ble_connected_text;
        case BleDeviceStatus.scanning:
        case BleDeviceStatus.connecting:
        case BleDeviceStatus.authenticating:
          return context.l10n.ble_connecting_text;
        case BleDeviceStatus.error:
        case BleDeviceStatus.timeout:
        case BleDeviceStatus.disconnected:
        default:
          return context.l10n.ble_disconnected_text;
      }
    }();

    final leadingIcon = () {
      switch (uiStatus) {
        case BleDeviceStatus.authenticated:
        case BleDeviceStatus.connected:
          return const Icon(Icons.check_circle, color: Colors.blue);
        case BleDeviceStatus.scanning:
        case BleDeviceStatus.connecting:
        case BleDeviceStatus.authenticating:
          return const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          );
        case BleDeviceStatus.error:
        case BleDeviceStatus.timeout:
        case BleDeviceStatus.disconnected:
        default:
          return Icon(
            Icons.error_outline,
            color: Theme.of(context).disabledColor,
          );
      }
    }();

    void handleToggle(bool value) async {
      if (value) {
        // 打开：尝试连接到当前选中设备
        final rec = savedNotifier.getSelectedRec();
        if (rec.displayDeviceId.isEmpty) return;
        final qr = _qrFromRecord(rec);
        if (qr == null) return;
        final result = await ref
            .read(conn.bleConnectionProvider.notifier)
            .enableBleConnection(qr);
        _safelyToastConnectRes(result);
      } else {
        // 关闭：主动断开
        await ref
            .read(conn.bleConnectionProvider.notifier)
            .disconnect(shouldReset: false);
      }
    }

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.defaultPadding,
          vertical: AppConstants.defaultPadding,
        ),
        child: Row(
          children: [
            leadingIcon,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                titleText,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Switch(
              value: computedIsOn(),
              onChanged:
                  (!bleOnLoadingForCurrent &&
                      saved.loaded &&
                      saved.lastSelectedId != null)
                  ? handleToggle
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // 构建网络状态或WiFi列表部分
  Widget _buildNetworkSection(
    BuildContext context,
    conn.BleConnectionState connState,
  ) {
    final textButtonStyle = TextButton.styleFrom(
      padding: EdgeInsets.zero, // 去掉默认 padding
      minimumSize: Size.zero, // 可选：去掉最小尺寸限制
      tapTargetSize: MaterialTapTargetSize.shrinkWrap, // 可选：缩小点击区域
      overlayColor: Colors.transparent, // 关键
    );
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (connState.isCheckingNetwork &&
                connState.networkStatus == null) ...[
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.network_status_loading,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ] else if (connState.networkStatus?.connected == true) ...[
              _buildCurrentNetworkInfo(context, connState.networkStatus!),
              const SizedBox(height: 18),
              if (connState.networkStatusUpdatedAt != null)
                Text(
                  '${context.l10n.last_updated}: ' +
                      _fmtTime(connState.networkStatusUpdatedAt!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      context.push(AppRoutes.wifiSelection);
                    },
                    style: textButtonStyle,
                    icon: const Icon(Icons.settings, size: 16),
                    label: Text(context.l10n.manage_network),
                  ),
                  const SizedBox(width: 16),
                  TextButton.icon(
                    onPressed: connState.isCheckingNetwork
                        ? null
                        : () {
                            ref
                                .read(conn.bleConnectionProvider.notifier)
                                .checkNetworkStatus();
                          },
                    style: textButtonStyle,
                    icon: connState.isCheckingNetwork
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(context.l10n.refresh),
                  ),
                ],
              ),
            ]
            // 未连网或检查失败：提示“无网络”。“管理网络”前往配网，“刷新”仅刷新网络状态
            else ...[
              Row(
                children: [
                  Icon(
                    Icons.error,
                    size: 24,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.network_not_connected,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      context.push(AppRoutes.wifiSelection);
                    },
                    style: textButtonStyle,
                    icon: const Icon(Icons.settings, size: 16),
                    label: Text(context.l10n.manage_network),
                  ),
                  const SizedBox(width: 16),
                  TextButton.icon(
                    onPressed: connState.isCheckingNetwork
                        ? null
                        : () {
                            ref
                                .read(conn.bleConnectionProvider.notifier)
                                .checkNetworkStatus();
                          },
                    style: textButtonStyle,
                    icon: connState.isCheckingNetwork
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(context.l10n.refresh),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // 构建当前网络信息
  Widget _buildCurrentNetworkInfo(
    BuildContext context,
    NetworkStatus networkStatus,
  ) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                wifiSignalIconFromRssiDbm(networkStatus.rawRssi),
                color: Colors.green,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '${networkStatus.displaySsid ?? l10n.unknown_network}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
            ],
          ),
          if (networkStatus.rawRssi != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                wifiSignalStrengthLabel(l10n, networkStatus.rawRssi),
                l10n.wifi_rssi_dbm_label(networkStatus.rawRssi!),
              ].join(' · '),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.green.shade700),
            ),
          ],
        ],
      ),
    );
  }

  String _fmtTime(DateTime t) {
    final lt = t.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(lt.hour)}:${two(lt.minute)}:${two(lt.second)}';
  }

  void _showDeleteDialog(BuildContext context, SavedDeviceRecord device) {
    bool deleting = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setSBState) {
          final theme = Theme.of(ctx);
          final colorScheme = theme.colorScheme;

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ctx.l10n.confirm_delete_device,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ctx.l10n.delete_consequence_hint,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: deleting
                              ? null
                              : () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(ctx.l10n.cancel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: deleting
                              ? null
                              : () async {
                                  setSBState(() => deleting = true);
                                  try {
                                    await _deleteDevice(device);
                                  } finally {
                                    if (ctx.mounted) Navigator.of(ctx).pop();
                                  }
                                },
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: colorScheme.error,
                            foregroundColor: colorScheme.onError,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: deleting
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              colorScheme.onError,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(ctx.l10n.unbind_action),
                                  ],
                                )
                              : Text(ctx.l10n.unbind_action),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _deleteDevice(SavedDeviceRecord device) async {
    final l10n = context.l10n;
    try {
      final ok = await ref
          .read(deviceUnbindCoordinatorProvider)
          .unbindDevice(device);
      if (!ok) {
        if (mounted) {
          Fluttertoast.showToast(msg: l10n.delete_failed);
        }
        return;
      }

      if (mounted) {
        Fluttertoast.showToast(msg: l10n.delete_success);
      }
    } catch (e, st) {
      AppLog.instance.error(
        '❌ _deleteDevice 出错',
        tag: 'DeviceDetail',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        Fluttertoast.showToast(msg: l10n.delete_failed);
      }
    }
  }
}
