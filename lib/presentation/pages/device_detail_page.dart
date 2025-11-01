import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/result.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/router/app_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/providers/app_state_provider.dart';
import '../../data/repositories/saved_devices_repository.dart';
import '../../core/ble/ble_device_data.dart';
import '../../core/network/network_status.dart';
import '../../core/models/device_qr_data.dart';
import '../../core/providers/ble_connection_provider.dart' as conn;

class DeviceDetailPage extends ConsumerStatefulWidget {
  final VoidCallback? onBackToList;
  // 可选：指定进入本页时要连接/展示的设备ID
  final String? deviceId;
  const DeviceDetailPage({super.key, this.onBackToList, this.deviceId});

  @override
  ConsumerState<DeviceDetailPage> createState() => _DeviceDetailState();
}

class _DeviceDetailState extends ConsumerState<DeviceDetailPage> {
  bool _checkingUpdate = false;

  // 开关的乐观更新覆盖值（null 表示不覆盖）
  bool? _bleSwitchOverride;
  DateTime? _bleSwitchOverrideAt;
  bool _paramConnectTried = false; // 仅根据外部传入 deviceId 自动触发一次
  String? _lastParamDeviceId; // 记录上一次处理过的构造参数 deviceId
  // 使用 ref.listen 绑定到 widget 生命周期，无需手动管理订阅

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
    // 加载已保存设备
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(savedDevicesProvider.notifier).load();
    });
    // 根据外部传入的 deviceId（若有）自动触发连接（只触发一次）
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryConnectByParam());
    // 首次进入设备详情页（本会话）时，若存在选中设备且未连接，自动尝试一次连接
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoConnectSelectedOnce());

    // 保留单一路径：通过参数 deviceId 触发连接（含 didUpdateWidget 变更时）

  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DeviceDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当父组件传入的 deviceId 发生变化时，重新尝试基于参数的自动连接
    final prev = oldWidget.deviceId ?? '';
    final curr = widget.deviceId ?? '';
    if (curr.isNotEmpty && curr != prev) {
      _paramConnectTried = false; // 允许对新的参数再次尝试
      _lastParamDeviceId = curr;
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryConnectByParam());
    }
  }

  // 如果通过 MainPage 传入了 deviceId，则优先使用它进行一次性自动连接
  Future<void> _tryConnectByParam() async {
    if (_paramConnectTried) return;
    final targetId = widget.deviceId;
    if (targetId == null || targetId.isEmpty) return;
    // 同一参数重复进入时避免多次触发
    if (_lastParamDeviceId == targetId) {
      // 已进入过一次但未成功时也允许再次尝试，这里不提前 return
    } else {
      _lastParamDeviceId = targetId;
    }
    var saved = ref.read(savedDevicesProvider);
    // 若尚未加载完成，先等待加载
    if (!saved.loaded) {
      try { await ref.read(savedDevicesProvider.notifier).load(); } catch (_) {}
      saved = ref.read(savedDevicesProvider);
    }
    if (!saved.loaded) return;
    // 查找本地缓存记录
    var rec = saved.devices.firstWhere(
      (e) => e.displayDeviceId == targetId,
      orElse: () => SavedDeviceRecord.empty(),
    );
    // 若本地未找到，尝试从服务器同步一次再查找
    if (rec.displayDeviceId.isEmpty) {
      try {
        await ref.read(savedDevicesProvider.notifier).syncFromServer();
      } catch (_) {}
      final refreshed = ref.read(savedDevicesProvider);
      rec = refreshed.devices.firstWhere(
        (e) => e.displayDeviceId == targetId,
        orElse: () => SavedDeviceRecord.empty(),
      );
      if (rec.displayDeviceId.isEmpty) return;
    }
    _paramConnectTried = true;
    // 将此设备设置为选中（以便后续 UI 与状态一致）
    await ref.read(savedDevicesProvider.notifier).select(rec.displayDeviceId);
    final qr = _qrFromRecord(rec);
    if (qr == null) return;
    await ref.read(conn.bleConnectionProvider.notifier).enableBleConnection(qr);
  }

  // 本会话内在设备详情页只尝试一次：若存在已选中设备且当前未在连接/已连，则自动连接
  Future<void> _tryAutoConnectSelectedOnce() async {
    // 若通过参数触发了特定设备的连接，则不再做兜底自动连接
    if (_paramConnectTried) return;
    // 已在本会话内做过自动连接则跳过
    final appState = ref.read(appStateProvider);
    if (appState.didAutoConnectOnDetailPage) return;

    // 确保已加载设备列表
    final savedNotifier = ref.read(savedDevicesProvider.notifier);
    var saved = ref.read(savedDevicesProvider);
    if (!saved.loaded) {
      try { await savedNotifier.load(); } catch (_) {}
      saved = ref.read(savedDevicesProvider);
    }
    if (!saved.loaded) return;

    // 获取当前选中设备
    final selectedId = saved.lastSelectedId;
    final rec = selectedId == null
        ? const SavedDeviceRecord.empty()
        : saved.devices.firstWhere(
            (e) => e.displayDeviceId == selectedId,
            orElse: () => const SavedDeviceRecord.empty(),
          );
    if (rec.displayDeviceId.isEmpty) return;

    // 避免在已有连接流程中重复触发
    final connState = ref.read(conn.bleConnectionProvider);
    final busy = connState.bleDeviceStatus == BleDeviceStatus.connecting ||
        connState.bleDeviceStatus == BleDeviceStatus.connected ||
        connState.bleDeviceStatus == BleDeviceStatus.authenticating ||
        connState.bleDeviceStatus == BleDeviceStatus.authenticated;
    if (busy) return;

    final qr = _qrFromRecord(rec);
    if (qr == null) return;
    await ref.read(conn.bleConnectionProvider.notifier).enableBleConnection(qr);
    // 标记已执行，防止本会话内重复触发
    ref.read(appStateProvider.notifier).markAutoConnectOnDetailPage();
  }

  // 已移除“自动连接上次设备”和“智能重连”实现

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final saved = ref.watch(savedDevicesProvider);
    final connState = ref.watch(conn.bleConnectionProvider);

    // 移除“自动连接上次设备”的监听逻辑
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
                final rec = saved.devices.firstWhere(
                  (e) => e.displayDeviceId == saved.lastSelectedId,
                  orElse: () => saved.devices.first,
                );
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
                                  TextButton(
                                    onPressed: _checkingUpdate
                                        ? null
                                        : () {
                                          final rec = saved.devices.firstWhere(
                                              (e) =>
                                                  e.displayDeviceId ==
                                                  saved.lastSelectedId,
                                              orElse: () => saved.devices.first,
                                          );
                                          _sendCheckUpdate(rec);
                                        },
                                    child: Text(context.l10n.check_update),
                                  ),
                                  if (_checkingUpdate) ...[
                                    const SizedBox(width: 8),
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
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
              _buildBLESection(context),

              // 显示网络状态或WiFi列表
              if (connState.bleDeviceStatus ==
                  BleDeviceStatus.authenticated) ...[
                const SizedBox(height: 16),
                _buildNetworkSection(context, connState),
              ],

              // 删除设备按钮
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme
                      .of(context)
                      .cardColor, // 背景颜色
                  foregroundColor: Theme
                      .of(context)
                      .colorScheme
                      .error, // 文字颜色
                  elevation: 0, // 阴影高度
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), // 圆角
                  ),
                ),
                onPressed: () {
                  final rec = saved.devices.firstWhere(
                    (e) => e.displayDeviceId == saved.lastSelectedId,
                    orElse: () => saved.devices.first,
                  );
                  _showDeleteDialog(context, rec);
                },
                child: Text(context.l10n.delete_device),
              ),
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
  // 蓝牙卡片
  Widget _buildBLESection(BuildContext context) {
    final connState = ref.watch(conn.bleConnectionProvider);
    final saved = ref.watch(savedDevicesProvider);

    // 当前详情页所展示的目标设备（以最后选中的设备为准）
    final currentId = saved.lastSelectedId;
    final currentRec = (currentId != null)
        ? saved.devices.firstWhere(
            (e) => e.displayDeviceId == currentId,
            orElse: () => SavedDeviceRecord.empty(),
          )
        : SavedDeviceRecord.empty();

    // 只有当 provider 的当前连接设备等于详情页设备时，才采用其真实 BLE 状态；否则视为未连接
    final isThisDeviceActive =
        connState.bleDeviceData?.displayDeviceId.isNotEmpty == true &&
            connState.bleDeviceData?.displayDeviceId ==
                currentRec.displayDeviceId;
    final effectiveStatus = isThisDeviceActive
        ? connState.bleDeviceStatus
        : BleDeviceStatus.disconnected;
    print('[device_detail_page] effectiveStatus=$effectiveStatus');
    // 目标视觉：左侧状态图标 + 文案，右侧开关
    // 三种状态：
    // - 已连接（开关开、勾选图标、蓝色）
    // - 连接中（开关开、扫描图标、蓝色）
    // - 未开启/未连接（开关关、提示图标、灰色）
    bool computedIsOn() {
      switch (effectiveStatus) {
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
      switch (effectiveStatus) {
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
      switch (effectiveStatus) {
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
      // 开关先乐观更新
      setState(() {
        _bleSwitchOverride = value;
        _bleSwitchOverrideAt = DateTime.now();
      });
      if (value) {
        // 打开：尝试连接到当前选中设备
        final id = saved.lastSelectedId;
        if (id == null) return;
        final rec = saved.devices.firstWhere(
          (e) => e.displayDeviceId == id,
          orElse: () => SavedDeviceRecord.empty(),
        );
        if (rec.displayDeviceId.isEmpty) return;
        final qr = _qrFromRecord(rec);
        if (qr == null) return;
        final res = await ref
            .read(conn.bleConnectionProvider.notifier)
            .handleUserEnableBleConnection(qr);
        if (!res) {
          Fluttertoast.showToast(msg: '蓝牙连接失败，请检查手机蓝牙或靠近设备');
        }
      } else {
        // 关闭：主动断开
        await ref
            .read(conn.bleConnectionProvider.notifier)
            .handleUserDisableBleConnection();
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
              onChanged: (saved.loaded && saved.lastSelectedId != null)
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
                      final saved = ref.read(savedDevicesProvider);
                      final id = saved.lastSelectedId;
                      if (id != null && id.isNotEmpty) {
                        context.push('${AppRoutes.wifiSelection}?displayDeviceId=${Uri.encodeComponent(id)}');
                      } else {
                        context.push(AppRoutes.wifiSelection);
                      }
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
                      final saved = ref.read(savedDevicesProvider);
                      final id = saved.lastSelectedId;
                      if (id != null && id.isNotEmpty) {
                        context.push('${AppRoutes.wifiSelection}?displayDeviceId=${Uri.encodeComponent(id)}');
                      } else {
                        context.push(AppRoutes.wifiSelection);
                      }
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.delete_device),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.confirm_delete_device),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${context.l10n.device_name_label}: ${device.deviceName}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${context.l10n.device_id_label}: ${device.displayDeviceId}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.delete_consequence_hint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteDevice(device);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(context.l10n.delete_device),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDevice(SavedDeviceRecord device) async {
    try {
      // 1. 调用 Supabase Edge Function 解绑
      final supabase = Supabase.instance.client;
      final response = await supabase.functions.invoke(
        'account_unbind_device',
        body: {
          'device_id': device.displayDeviceId,
        },
      );

      if (response.status != 200) {
        throw Exception('设备删除失败: ${response.data}');
      }

      Fluttertoast.showToast(msg: context.l10n.delete_success);

      // 同步远端状态，确保列表与服务器一致
      try {
        // Silent refresh after deletion to avoid duplicate toast
        await ref.read(savedDevicesProvider.notifier).syncFromServer();
      } catch (_) {
        // 同步失败不阻塞后续逻辑，保持静默以免打断用户流程
      }

      // 2. 若正在连接该设备，优先通过 BLE 通知 TV 执行本地登出
      final connState = ref.read(conn.bleConnectionProvider);
      if (connState.bleDeviceData?.displayDeviceId == device.displayDeviceId) {
        final notifier = ref.read(conn.bleConnectionProvider.notifier);
        final ok = await notifier.sendDeviceLogout();
        if (!ok) {
          // 不中断后续流程，仅记录日志
          // ignore: avoid_print
          print('⚠️ BLE 登出指令发送失败，继续删除本地记录');
        }
      }

      // 3. 更新本地保存的设备列表（内部会在命中当前连接时断开BLE）
      await ref
          .read(savedDevicesProvider.notifier)
          .removeDevice(device.displayDeviceId);
    } catch (e, st) {
      print("❌ _deleteDevice 出错: $e\n$st");
      Fluttertoast.showToast(msg: context.l10n.delete_failed);
    }
  }
}
