import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_display_mobile/core/utils/data_transformer.dart';
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
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _trySelectAndConnectByParam());
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
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _trySelectAndConnectByParam());
    }
  }

  // 如果通过 MainPage 传入了 deviceId，尝试选中
  Future<void> _trySelectAndConnectByParam() async {
    // 仅一次
    if (_paramSelectTried) return;
    _paramSelectTried = true;

    AppLog.instance.info("~~~~_trySelectByParamOnce ${widget.deviceId}");

    // 空就保持现状
    final targetId = widget.deviceId;
    if (targetId == null || targetId.isEmpty) return;

    // 尝试选中并连接
    final notifier = ref.read(savedDevicesProvider.notifier);
    final rec = notifier.findById(targetId);
    if (rec!= null) {
      AppLog.instance.info("~~~~_trySelectByParamOnce select ${targetId}");
      await notifier.select(targetId);
      await ref.read(conn.bleConnectionProvider.notifier).enableBleConnection(savedDeviceRecordToQrData(rec));
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
                  minHeight: MediaQuery.of(context).size.height -
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
                        l10n?.no_device_title ?? '暂未添加设备',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: MediaQuery.of(context).size.width *
                            0.6, // 宽度占屏幕 3/5
                        child: Text(
                          l10n?.no_device_subtitle ??
                              '显示器开机后，扫描显示器屏幕上的二维码可添加设备',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
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
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          textStyle:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
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
              Builder(builder: (context) {
                final rec = bleView.currentDevice;
                final String? firmwareVersion = rec.firmwareVersion;
                return Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.defaultPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Image.asset(
                                    'assets/images/device.png',
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.contain,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Builder(builder: (context) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            rec.deviceName,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          // 显示设备ID（替换原来的状态展示）
                                          Text(
                                            '${context.l10n.device_id_label}: ${rec.displayDeviceId}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                        ],
                                      );
                                    }),
                                  ),
                                  // _buildActionButtons(connState),
                                ],
                              ),
                              const Divider(height: 20, color: Colors.grey),
                              const SizedBox(height: 4),
                              // 扩展信息：固件版本与添加时间
                              Row(
                                children: [
                                  Text(
                                    '${context.l10n.firmware_version_label}: ',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      firmwareVersion == null ||
                                              firmwareVersion.isEmpty
                                          ? '-'
                                          : firmwareVersion,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // 仅在蓝牙已连接到当前设备时显示“检查更新”按钮
                                  if (bleView.bleStatus ==
                                      BleDeviceStatus.authenticated) ...[
                                    TextButton(
                                      onPressed: _checkingUpdate
                                          ? null
                                          : () {
                                              _sendCheckUpdate(rec);
                                            },
                                      child: Text(context.l10n.check_update),
                                    ),
                                    if (_checkingUpdate) ...[
                                      const SizedBox(width: 8),
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    '${context.l10n.last_connected_at}: ',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  Text(
                                    _formatDateTime(rec.lastConnectedAt),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 16),
              _buildBLESection(
                context,
                uiStatus: bleView.uiStatus,
                bleOnLoadingForCurrent: bleView.isLoadingForCurrent,
              ),

              // 显示网络状态或WiFi列表
              if (bleView.bleStatus ==
                  BleDeviceStatus.authenticated) ...[
                const SizedBox(height: 16),
                _buildNetworkSection(context, connState),
                // 删除设备按钮
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).cardColor, // 背景颜色
                    foregroundColor:
                        Theme.of(context).colorScheme.error, // 文字颜色
                    elevation: 0, // 阴影高度
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12), // 圆角
                    ),
                  ),
                  onPressed: () {
                    _showDeleteDialog(context, bleView.currentDevice);
                  },
                  child: Text(context.l10n.delete_device),
                )
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

  void _sendCheckUpdate(SavedDeviceRecord device) async {
    if (_checkingUpdate) return; // 简单防抖
    setState(() => _checkingUpdate = true);

    try {
      final notifier = ref.read(conn.bleConnectionProvider.notifier);
      final result = await notifier.requestUpdateCheck();

      if (!mounted) return;
      switch (result) {
        case DeviceUpdateVersionResult.updating:
          Fluttertoast.showToast(msg: context.l10n.update_started);
          break;
        case DeviceUpdateVersionResult.latest:
          Fluttertoast.showToast(msg: context.l10n.already_latest_version);
          break;
        case DeviceUpdateVersionResult.failed:
          Fluttertoast.showToast(msg: context.l10n.check_update_failed_retry);
          break;
      }
    } catch (e) {
      if (mounted) {
        Fluttertoast.showToast(msg: context.l10n.check_update_failed_error(e.toString()));
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
          return Icon(Icons.error_outline, color: Theme.of(context).disabledColor);
      }
    }();

    void handleToggle(bool value) async {
      if (value) {
        // 打开：尝试连接到当前选中设备
        final rec = savedNotifier.getSelectedRec();
        if (rec.displayDeviceId.isEmpty) return;
        final qr = _qrFromRecord(rec);
        if (qr == null) return;
        final res = await ref
            .read(conn.bleConnectionProvider.notifier)
            .enableBleConnection(qr);
        if (!res) {
          Fluttertoast.showToast(msg: context.l10n.connect_failed_move_closer);
          AppLog.instance.error("蓝牙连接失败，请检查手机蓝牙或靠近设备");
        }
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
              onChanged: (!bleOnLoadingForCurrent &&
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
      BuildContext context, conn.BleConnectionState connState) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (connState.networkStatus?.connected == true) ...[
              _buildCurrentNetworkInfo(context, connState.networkStatus!),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      context.push(AppRoutes.wifiSelection);
                    },
                    icon: const Icon(Icons.settings, size: 16),
                    label: Text(context.l10n.manage_network),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    onPressed: connState.isCheckingNetwork
                        ? null
                        : () {
                            ref
                                .read(conn.bleConnectionProvider.notifier)
                                .checkNetworkStatus();
                          },
                    icon: connState.isCheckingNetwork
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(context.l10n.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (connState.networkStatusUpdatedAt != null)
                Text(
                  '${context.l10n.last_updated}: ' + _fmtTime(connState.networkStatusUpdatedAt!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      context.push(AppRoutes.wifiSelection);
                    },
                    icon: const Icon(Icons.settings, size: 16),
                    label: Text(context.l10n.manage_network),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    onPressed: connState.isCheckingNetwork
                        ? null
                        : () {
                            ref
                                .read(conn.bleConnectionProvider.notifier)
                                .checkNetworkStatus();
                          },
                    icon: connState.isCheckingNetwork
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
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
  Widget _buildCurrentNetworkInfo(BuildContext context, NetworkStatus networkStatus) {
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
              Icon(Icons.wifi, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Text(
                '${networkStatus.displaySsid ?? (l10n?.unknown_network ?? 'Unknown')}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _buildSignalBars(networkStatus.signalBars),
            ],
          ),
          if (networkStatus.ip != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.language, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'IP: ${networkStatus.ip}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
          if (networkStatus.frequency != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.router, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  '${l10n?.band ?? 'Band'}: ${networkStatus.is5GHz ? '5GHz' : '2.4GHz'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
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

  // 构建信号强度指示器
  Widget _buildSignalBars(int bars) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(4, (index) {
        return Container(
          width: 3,
          height: 4 + (index * 2),
          margin: const EdgeInsets.only(right: 1),
          decoration: BoxDecoration(
            color: index < bars ? Colors.green : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  void _showDeleteDialog(BuildContext context, SavedDeviceRecord device) {
    bool deleting = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setSBState) {
          return AlertDialog(
            title: Text(ctx.l10n.delete_device),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ctx.l10n.confirm_delete_device),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${ctx.l10n.device_name_label}: ${device.deviceName}',
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${ctx.l10n.device_id_label}: ${device.displayDeviceId}',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  ctx.l10n.delete_consequence_hint,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.error,
                      ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: deleting ? null : () => Navigator.of(ctx).pop(),
                child: Text(ctx.l10n.cancel),
              ),
              FilledButton(
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
                  backgroundColor: Theme.of(ctx).colorScheme.error,
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
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Theme.of(ctx).colorScheme.onPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(ctx.l10n.splash_loading),
                        ],
                      )
                    : Text(ctx.l10n.delete_device),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteDevice(SavedDeviceRecord device) async {
    try {
      final connState = ref.read(conn.bleConnectionProvider);
      if (connState.bleDeviceData?.displayDeviceId == device.displayDeviceId) {
        final bleNotifier = ref.read(conn.bleConnectionProvider.notifier);
        // 1. 蓝牙通知设备删除
        final ok = await bleNotifier.sendDeviceLogout();
        if (!ok && context.mounted) {
          Fluttertoast.showToast(msg: context.l10n.delete_failed);
          return;
        }
        if (context.mounted) {
          Fluttertoast.showToast(msg: context.l10n.delete_success);
        }
        // 2. 断开蓝牙
        await ref.read(conn.bleConnectionProvider.notifier).disconnect();
        final deviceNotifier = ref.read(savedDevicesProvider.notifier);
        // 3. 同步远端状态，确保列表与服务器一致
        await deviceNotifier.syncFromServer();
      } else {
        if (context.mounted) {
          Fluttertoast.showToast(msg: context.l10n.delete_failed);
        }
      }
    } catch (e, st) {
      AppLog.instance.error('❌ _deleteDevice 出错', tag: 'DeviceDetail', error: e, stackTrace: st);
      if (context.mounted) {
        Fluttertoast.showToast(msg: context.l10n.delete_failed);
      }
    }
  }
}
