import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../core/l10n/l10n_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/providers/app_state_provider.dart';
import '../../data/repositories/saved_devices_repository.dart';
import '../../features/device_connection/providers/device_connection_provider.dart' as conn;
import '../../features/device_connection/models/ble_device_data.dart';
import '../../features/device_connection/models/network_status.dart';
import '../../features/device_connection/services/ble_service_simple.dart';
import '../../features/qr_scanner/models/device_qr_data.dart';
import '../../core/constants/ble_constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceDetailPage extends ConsumerStatefulWidget {
  final VoidCallback? onBackToList;
  // 可选：指定进入本页时要连接/展示的设备ID
  final String? deviceId;
  const DeviceDetailPage({super.key, this.onBackToList, this.deviceId});

  @override
  ConsumerState<DeviceDetailPage> createState() => _DeviceDetailState();
}

class _DeviceDetailState extends ConsumerState<DeviceDetailPage> {
  // 开关的乐观更新覆盖值（null 表示不覆盖）
  bool? _bleSwitchOverride;
  DateTime? _bleSwitchOverrideAt;
  bool _paramConnectTried = false; // 仅根据外部传入 deviceId 自动触发一次
  // 使用 ref.listen 绑定到 widget 生命周期，无需手动管理订阅

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
  }

  @override
  void dispose() {
    super.dispose();
  }

  // 如果通过 MainPage 传入了 deviceId，则优先使用它进行一次性自动连接
  Future<void> _tryConnectByParam() async {
    if (_paramConnectTried) return;
    final targetId = widget.deviceId;
    if (targetId == null || targetId.isEmpty) return;
    final saved = ref.read(savedDevicesProvider);
    // 若尚未加载完成，先等待加载
    if (!saved.loaded) {
      try { await ref.read(savedDevicesProvider.notifier).load(); } catch (_) {}
    }
    final current = ref.read(savedDevicesProvider);
    if (!current.loaded) return;
    final rec = current.devices.firstWhere(
      (e) => e.deviceId == targetId,
      orElse: () => SavedDeviceRecord.empty(),
    );
    if (rec.deviceId.isEmpty) return;
    _paramConnectTried = true;
    // 将此设备设置为选中（以便后续 UI 与状态一致）
    await ref.read(savedDevicesProvider.notifier).select(rec.deviceId);
    // 构造最小二维码数据并触发连接
    final qr = DeviceQrData(
      deviceId: rec.deviceId,
      deviceName: rec.deviceName,
      bleAddress: rec.lastBleAddress ?? '',
      publicKey: rec.publicKey,
    );
    await ref.read(conn.deviceConnectionProvider.notifier).startConnection(qr);
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
            (e) => e.deviceId == selectedId,
            orElse: () => const SavedDeviceRecord.empty(),
          );
    if (rec.deviceId.isEmpty) return;

    // 避免在已有连接流程中重复触发
    final connState = ref.read(conn.deviceConnectionProvider);
    final busy = connState.status == BleDeviceStatus.connecting ||
        connState.status == BleDeviceStatus.connected ||
        connState.status == BleDeviceStatus.authenticating ||
        connState.status == BleDeviceStatus.authenticated;
    if (busy) return;

    // 构造最小二维码数据并触发连接
    final qr = DeviceQrData(
      deviceId: rec.deviceId,
      deviceName: rec.deviceName,
      bleAddress: rec.lastBleAddress ?? '',
      publicKey: rec.publicKey,
    );
    await ref.read(conn.deviceConnectionProvider.notifier).startConnection(qr);
    // 标记已执行，防止本会话内重复触发
    ref.read(appStateProvider.notifier).markAutoConnectOnDetailPage();
  }

  // 已移除“自动连接上次设备”和“智能重连”实现

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final saved = ref.watch(savedDevicesProvider);
    final connState = ref.watch(conn.deviceConnectionProvider);

    // login_success 同步逻辑已下沉至 deviceConnectionProvider，页面无需再监听处理

    // 监听连接状态变化，仅处理智能WiFi（不再做智能重连）
    ref.listen<conn.DeviceConnectionState>(conn.deviceConnectionProvider, (previous, current) {
      if (previous != null && previous.status != current.status) {
        print('[HomePage] 连接状态变化: ${previous.status} -> ${current.status}');

        // 当设备认证完成时，自动进行智能WiFi处理
        if (current.status == BleDeviceStatus.authenticated &&
            previous.status != BleDeviceStatus.authenticated) {
          print('[HomePage] 设备认证完成，开始智能WiFi处理');
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              ref.read(conn.deviceConnectionProvider.notifier).handleWifiSmartly();
            }
          });
        }

        // 不再自动重连
      }
    });

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
                        label: const Text('扫码添加设备'),
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
                  (e) => e.deviceId == saved.lastSelectedId,
                  orElse: () => saved.devices.first,
                );
                final qrDeviceData = ref
                    .read(appStateProvider.notifier)
                    .getDeviceDataById(rec.deviceId);
                final connState = ref.read(conn.deviceConnectionProvider);
                final String? firmwareVersion =
                    (connState.firmwareVersion != null && connState.firmwareVersion!.isNotEmpty)
                        ? connState.firmwareVersion
                        : qrDeviceData?.firmwareVersion;
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
                                            'ID: ${rec.deviceId}',
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
                                    '固件版本: ',
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
                                    onPressed: () {
                                      final rec = saved.devices.firstWhere(
                                            (e) => e.deviceId == saved.lastSelectedId,
                                        orElse: () => saved.devices.first,
                                      );
                                      _sendCheckUpdate(rec);
                                    },
                                    child: Text(context.l10n.check_update),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    '添加时间: ',
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
              if (connState.status == BleDeviceStatus.authenticated) ...[
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
                    (e) => e.deviceId == saved.lastSelectedId,
                    orElse: () => saved.devices.first,
                  );
                  _showDeleteDialog(context, rec);
                },
                child: const Text("删除设备"),
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
    try {
      // 通过连接管理器加密发送（携带 deviceId）
      final container = ProviderScope.containerOf(context, listen: false);
      final notifier = container.read(conn.deviceConnectionProvider.notifier);
      final ok = await notifier.writeEncryptedJson(
        characteristicUuid: BleConstants.updateVersionCharUuid,
        json: {
          'deviceId': device.deviceId,
          'userId': notifier.currentUserId(),
          'action': 'update_version',
        },
      );
      print("device_management_page: " + "writeCharacteristic ok=$ok");

      if (mounted) {
        Fluttertoast.showToast(msg: '已发送检查更新指令');
      }
    } catch (e, st) {
      print("❌ _sendCheckUpdate 出错: $e\n$st");
      if (mounted) {
        Fluttertoast.showToast(msg: '发送更新请求失败: $e');
      }
    }
  }

  // 蓝牙卡片
  Widget _buildBLESection(BuildContext context) {
    final connState = ref.watch(conn.deviceConnectionProvider);
    final saved = ref.watch(savedDevicesProvider);

    // 当前详情页所展示的目标设备（以最后选中的设备为准）
    final currentId = saved.lastSelectedId;
    final currentRec = (currentId != null)
        ? saved.devices.firstWhere(
            (e) => e.deviceId == currentId,
            orElse: () => SavedDeviceRecord.empty(),
          )
        : SavedDeviceRecord.empty();

    // 只有当 provider 的当前连接设备等于详情页设备时，才采用其真实 BLE 状态；否则视为未连接
    final isThisDeviceActive =
        connState.deviceData?.deviceId.isNotEmpty == true &&
        connState.deviceData?.deviceId == currentRec.deviceId;
    final effectiveStatus = isThisDeviceActive ? connState.status : BleDeviceStatus.disconnected;

    Widget statusRow({required Widget leading, required String text, List<Widget> trailing = const []}) {
      return Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          ...trailing,
        ],
      );
    }

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

    // 如果存在乐观覆盖且未超时，则优先使用
    bool isOn = computedIsOn();
    if (_bleSwitchOverride != null) {
      final now = DateTime.now();
      final ts = _bleSwitchOverrideAt;
      final notExpired = ts != null && now.difference(ts) < const Duration(seconds: 5);
      // 当状态尚未稳定（如 scanning/connecting/authenticating）时允许覆盖；
      // 或在覆盖未过期时继续显示覆盖值。
      if (notExpired) {
        isOn = _bleSwitchOverride!;
      } else {
        // 覆盖过期，清理
        _bleSwitchOverride = null;
        _bleSwitchOverrideAt = null;
      }
    }

    final titleText = () {
      switch (effectiveStatus) {
        case BleDeviceStatus.authenticated:
        case BleDeviceStatus.connected:
          return '蓝牙已连接';
        case BleDeviceStatus.scanning:
        case BleDeviceStatus.connecting:
        case BleDeviceStatus.authenticating:
          return '蓝牙连接中';
        case BleDeviceStatus.error:
        case BleDeviceStatus.timeout:
        case BleDeviceStatus.disconnected:
        default:
          return '蓝牙未连接';
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
          (e) => e.deviceId == id,
          orElse: () => SavedDeviceRecord.empty(),
        );
        if (rec.deviceId.isEmpty) return;
        final qr = DeviceQrData(
          deviceId: rec.deviceId,
          deviceName: rec.deviceName,
          bleAddress: rec.lastBleAddress ?? '',
          publicKey: rec.publicKey,
        );
        await ref.read(conn.deviceConnectionProvider.notifier).startConnection(qr);
      } else {
        // 关闭：主动断开
        await ref.read(conn.deviceConnectionProvider.notifier).disconnect();
      }
      // 操作完成后，等待 provider 状态回传来纠正；这里不立即清除覆盖，交由上方过期逻辑处理
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
              value: isOn,
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
  Widget _buildNetworkSection(BuildContext context, conn.DeviceConnectionState connState) {
    final l10n = context.l10n;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '网络状态',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),

            // 检查网络状态中
            if (connState.isCheckingNetwork) ...[
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '正在检查网络状态...',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ]
            // 显示当前网络状态 (已连网)
            else if (connState.networkStatus?.connected == true) ...[
              _buildCurrentNetworkInfo(context, connState.networkStatus!),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => context.push(AppRoutes.wifiSelection),
                    icon: const Icon(Icons.settings, size: 16),
                    label: const Text('管理网络'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: connState.isCheckingNetwork
                        ? null
                        : () {
                            ref.read(conn.deviceConnectionProvider.notifier).checkNetworkStatus();
                          },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('刷新'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (connState.networkStatusUpdatedAt != null)
                Text(
                  '上次更新: ' + _fmtTime(connState.networkStatusUpdatedAt!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
            ]
            // 显示WiFi列表 (未连网或检查失败)
            else ...[
              if (connState.networkStatus?.connected == false)
                Text(
                  l10n?.wifi_not_connected ?? 'Device not connected to network. Select a Wi‑Fi to provision:',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Text(
                  l10n?.wifi_status_unknown ?? 'Unable to get network status. Showing available Wi‑Fi networks:',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 12),
              _buildWifiList(context, connState),
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
                '${l10n?.connected ?? 'Connected'}: ${networkStatus.displaySsid ?? (l10n?.unknown_network ?? 'Unknown')}',
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

  // 构建WiFi列表
  Widget _buildWifiList(BuildContext context, conn.DeviceConnectionState connState) {
    final l10n = context.l10n;
    if (connState.wifiNetworks.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.wifi_off, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              l10n?.no_wifi_found ?? 'No Wi‑Fi networks found',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(conn.deviceConnectionProvider.notifier).requestWifiScan();
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n?.scan_networks ?? 'Scan Networks'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // WiFi网络列表 - 限制最大高度避免溢出
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300), // 限制最大高度
          child: ListView.separated(
            shrinkWrap: true,
            physics: const AlwaysScrollableScrollPhysics(), // 如果内容超过300高度则允许滚动
            itemCount: connState.wifiNetworks.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
            final wifi = connState.wifiNetworks[index];
            return ListTile(
              leading: Icon(
                wifi.secure ? Icons.wifi_lock : Icons.wifi,
                color: _getWifiSignalColor(wifi.rssi),
              ),
              title: Text(wifi.ssid),
              subtitle: Text('${wifi.rssi} dBm'),
              trailing: _buildSignalBars(_getSignalBars(wifi.rssi)),
              onTap: () {
                // 弹窗输入WiFi密码
                _showWifiPasswordDialog(context, wifi, ref);
              },
            );
            },
          ),
        ),
        const SizedBox(height: 12),
        // 刷新按钮
        TextButton.icon(
          onPressed: () {
            ref.read(conn.deviceConnectionProvider.notifier).requestWifiScan();
          },
          icon: const Icon(Icons.refresh, size: 16),
          label: Text(l10n?.refresh_networks ?? 'Refresh Networks'),
        ),
      ],
    );
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

  // 获取WiFi信号颜色
  Color _getWifiSignalColor(int rssi) {
    if (rssi >= -50) return Colors.green;
    if (rssi >= -60) return Colors.orange;
    return Colors.red;
  }

  // 获取信号强度条数
  int _getSignalBars(int rssi) {
    if (rssi >= -50) return 4;
    if (rssi >= -60) return 3;
    if (rssi >= -70) return 2;
    return 1;
  }

  // 显示WiFi密码输入弹窗
  void _showWifiPasswordDialog(BuildContext context, conn.WifiAp wifi, WidgetRef ref) {
    final l10n = context.l10n;
    final TextEditingController passwordController = TextEditingController();
    bool isObscured = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    wifi.secure ? Icons.wifi_lock : Icons.wifi,
                    color: _getWifiSignalColor(wifi.rssi),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      wifi.ssid,
                      style: const TextStyle(fontSize: 18),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wifi.secure ? (l10n?.enter_wifi_password ?? 'Enter Wi‑Fi password:') : (l10n?.wifi_password_optional ?? 'Wi‑Fi password (leave empty for open network):'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: isObscured,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: wifi.secure ? (l10n?.enter_password ?? 'Enter password') : (l10n?.leave_empty_if_open ?? 'Leave empty if open'),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isObscured ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            isObscured = !isObscured;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    wifi.secure
                        ? (l10n?.secure_network_need_password ?? 'Secure network detected; password required')
                        : (l10n?.open_network_may_need_password ?? 'Open network detected; enter password if required'),
                    style: TextStyle(
                      fontSize: 12,
                      color: wifi.secure ? Colors.green[700] : Colors.orange[700],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${l10n?.signal_strength ?? 'Signal strength'}: ${wifi.rssi} dBm',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(l10n?.cancel ?? 'Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();

                    // 获取用户输入的密码（允许为空）
                    final password = passwordController.text.trim();

                    // 发送WiFi凭证到TV端
                    await _connectToWifi(wifi.ssid, password, ref);
                  },
                  child: Text(l10n?.connect ?? 'Connect'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 连接WiFi的方法
  Future<void> _connectToWifi(String ssid, String password, WidgetRef ref) async {
    try {
      // 显示连接中状态
      Fluttertoast.showToast(msg: context.l10n.connecting_to(ssid));

      // 发送WiFi凭证到设备
      final success = await ref
          .read(conn.deviceConnectionProvider.notifier)
          .sendWifiCredentials(ssid, password);

      if (success) {
        Fluttertoast.showToast(msg: context.l10n.wifi_credentials_sent(ssid));
      } else {
        Fluttertoast.showToast(msg: context.l10n.wifi_credentials_failed);
      }
    } catch (e) {
      Fluttertoast.showToast(msg: context.l10n.connect_failed(e.toString()));
    }
  }

  void _showDeleteDialog(BuildContext context, SavedDeviceRecord device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除设备'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('确定要删除以下设备吗？'),
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
                    '设备名称: ${device.deviceName}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${device.deviceId}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '删除后将无法自动连接到此设备，需要重新扫描二维码添加。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteDevice(device);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
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
          'device_id': device.deviceId,
        },
      );

      if (response.status != 200) {
        throw Exception('设备删除失败: ${response.data}');
      }

      Fluttertoast.showToast(msg: "设备删除成功");

      // 同步远端状态，确保列表与服务器一致
      try {
        // Silent refresh after deletion to avoid duplicate toast
        await ref.read(savedDevicesProvider.notifier).syncFromServer();
      } catch (_) {
        // 同步失败不阻塞后续逻辑，保持静默以免打断用户流程
      }

      // 2. 若正在连接该设备，优先通过 BLE 通知 TV 执行本地登出
      final connState = ref.read(conn.deviceConnectionProvider);
      if (connState.deviceData?.deviceId == device.deviceId) {
        final notifier = ref.read(conn.deviceConnectionProvider.notifier);
        final ok = await notifier.sendDeviceLogout();
        if (!ok) {
          // 不中断后续流程，仅记录日志
          // ignore: avoid_print
          print('⚠️ BLE 登出指令发送失败，继续删除本地记录');
        }
      }

      // 3. 更新本地保存的设备列表（内部会在命中当前连接时断开BLE）
      await ref.read(savedDevicesProvider.notifier).removeDevice(device.deviceId);
    } catch (e, st) {
      print("❌ _deleteDevice 出错: $e\n$st");
      Fluttertoast.showToast(msg: "设备删除失败");
    }
  }
}
