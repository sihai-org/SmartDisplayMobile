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
import '../../l10n/app_localizations.dart';
import '../../core/constants/ble_constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceDetailPage extends ConsumerStatefulWidget {
  final VoidCallback? onBackToList;
  const DeviceDetailPage({super.key, this.onBackToList});

  @override
  ConsumerState<DeviceDetailPage> createState() => _DeviceDetailState();
}

class _DeviceDetailState extends ConsumerState<DeviceDetailPage> {
  bool _autoTried = false;

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
  }

  void _tryAutoConnect() {
    final saved = ref.read(savedDevicesProvider);
    final connState = ref.read(conn.deviceConnectionProvider);
    
    // 如果已经尝试过连接，或者没有保存的设备，或者当前已经在连接/已连接状态，则不重试
    if (_autoTried || !saved.loaded || saved.lastSelectedId == null) return;
    if (connState.status == BleDeviceStatus.connecting || 
        connState.status == BleDeviceStatus.connected ||
        connState.status == BleDeviceStatus.authenticating ||
        connState.status == BleDeviceStatus.authenticated) return;
    
    SavedDeviceRecord? rec;
    try {
      rec = saved.devices.firstWhere((e) => e.deviceId == saved.lastSelectedId);
    } catch (e) {
      return; // 没找到记录，直接返回
    }
    if (rec.deviceId.isEmpty) return;
    
    _autoTried = true;
    print('[HomePage] 自动连接上次设备: ${rec.deviceName} (${rec.deviceId})');
    
    // 构造最小 QR 数据用于连接
    final qr = DeviceQrData(
      deviceId: rec.deviceId, 
      deviceName: rec.deviceName, 
      bleAddress: rec.lastBleAddress ?? '', 
      publicKey: rec.publicKey
    );
    ref.read(conn.deviceConnectionProvider.notifier).startConnection(qr);
  }
  
  // 智能重连：当连接断开或失败时自动重试
  void _handleSmartReconnect() {
    final saved = ref.read(savedDevicesProvider);
    final connState = ref.read(conn.deviceConnectionProvider);
    
    if (!saved.loaded || saved.lastSelectedId == null) return;
    
    // 只在断开、错误或超时状态下触发重连
    if (connState.status == BleDeviceStatus.disconnected ||
        connState.status == BleDeviceStatus.error ||
        connState.status == BleDeviceStatus.timeout) {
      
      print('[HomePage] 检测到连接问题，5秒后尝试重连...');
      
      // 延迟5秒后重试连接，避免在listener中直接修改provider
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          _autoTried = false; // 重置标记允许重连
          // 再次延迟确保不在build周期中
          Future.delayed(Duration.zero, () {
            if (mounted) {
              _tryAutoConnect();
            }
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final saved = ref.watch(savedDevicesProvider);
    final connState = ref.watch(conn.deviceConnectionProvider);

    // // 监听连接状态变化，实现智能重连和智能WiFi处理
    // ref.listen<conn.DeviceConnectionState>(conn.deviceConnectionProvider, (previous, current) {
    //   if (previous != null && previous.status != current.status) {
    //     print('[HomePage] 连接状态变化: ${previous.status} -> ${current.status}');
    //
    //     // 当设备认证完成时，自动进行智能WiFi处理
    //     if (current.status == BleDeviceStatus.authenticated &&
    //         previous.status != BleDeviceStatus.authenticated) {
    //       print('[HomePage] 设备认证完成，开始智能WiFi处理');
    //       Future.delayed(const Duration(milliseconds: 500), () {
    //         if (mounted) {
    //           ref.read(conn.deviceConnectionProvider.notifier).handleWifiSmartly();
    //         }
    //       });
    //     }
    //
    //     _handleSmartReconnect();
    //   }
    // });
    //
    // // 监听保存设备状态变化，延迟尝试自动连接以避免在build期间修改provider
    // ref.listen<SavedDevicesState>(savedDevicesProvider, (previous, current) {
    //   if (current.loaded && current.lastSelectedId != null &&
    //       (previous == null || !previous.loaded)) {
    //     // 延迟执行，避免在build期间修改provider
    //     Future.delayed(Duration.zero, () {
    //       if (mounted) {
    //         _tryAutoConnect();
    //       }
    //     });
    //   }
    // });
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBackToList != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBackToList,
              )
            : null,
        title: Text(context.l10n.appTitle),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.qrScanner),
            icon: const Icon(Icons.add),
            tooltip: context.l10n.scan_qr,
          ),
          if (saved.loaded && saved.devices.isNotEmpty)
            IconButton(
              onPressed: () => context.push(AppRoutes.deviceManagement),
              icon: const Icon(Icons.list),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!saved.loaded || saved.devices.isEmpty) ...[
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
                final String? firmwareVersion = qrDeviceData?.firmwareVersion;
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
                                    onPressed: _handleCheckUpdate,
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

              // 设备登录
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).cardColor, // 背景颜色
                  foregroundColor:
                      Theme.of(context).colorScheme.primary, // 文字颜色
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
                  _deviceLogin(rec);
                },
                child: const Text("登录设备"),
              ),

              // 设备登出
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).cardColor, // 背景颜色
                  foregroundColor:
                      Theme.of(context).colorScheme.primary, // 文字颜色
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
                  _deviceLogout(rec);
                },
                child: const Text("退出设备"),
              ),
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

  // // 构建状态图标
  // Widget _buildStatusIcon(BleDeviceStatus status) {
  //   switch (status) {
  //     case BleDeviceStatus.disconnected:
  //       return Icon(Icons.tv_off, size: 40, color: Colors.grey);
  //     case BleDeviceStatus.scanning:
  //     case BleDeviceStatus.connecting:
  //     case BleDeviceStatus.authenticating:
  //       return Icon(Icons.tv, size: 40, color: Colors.orange);
  //     case BleDeviceStatus.connected:
  //     case BleDeviceStatus.authenticated:
  //       return Icon(Icons.tv, size: 40, color: Colors.green);
  //     case BleDeviceStatus.error:
  //     case BleDeviceStatus.timeout:
  //       return Icon(Icons.tv_off, size: 40, color: Colors.red);
  //   }
  // }
  //
  // // 构建操作按钮
  // Widget _buildActionButtons(conn.DeviceConnectionState connState) {
  //   final l10n = context.l10n;
  //   return Row(
  //     mainAxisSize: MainAxisSize.min,
  //     children: [
  //       if (connState.status == BleDeviceStatus.disconnected ||
  //           connState.status == BleDeviceStatus.error ||
  //           connState.status == BleDeviceStatus.timeout)
  //         IconButton(
  //           onPressed: () {
  //             _autoTried = false; // 重置标记
  //             _tryAutoConnect();
  //           },
  //           icon: const Icon(Icons.refresh),
  //           tooltip: l10n?.reconnect ?? 'Reconnect',
  //         ),
  //       IconButton(
  //         onPressed: () => context.push(AppRoutes.qrScanner),
  //         icon: const Icon(Icons.qr_code_scanner),
  //         tooltip: l10n?.add_device ?? 'Add Device',
  //       ),
  //     ],
  //   );
  // }

  void _deviceLogin(SavedDeviceRecord device) async {
    Fluttertoast.showToast(msg: "click device login");
    try {
      // 1. 调用 Supabase Edge Function 获取授权码
      final supabase = Supabase.instance.client;
      final response = await supabase.functions.invoke(
        'pairing-otp',
        body: {
          'device_id': device.deviceId,
        },
      );

      if (response.status != 200) {
        throw Exception('获取授权码失败: ${response.data}');
      }

      final email = response.data['email'] as String;
      final otpToken = response.data['token'] as String;
      if (email == null || email == "" || otpToken == null || otpToken == "") {
        throw Exception('返回的授权码为空');
      }

      final command = '{"email":"$email", "otpToken":"$otpToken"}';

      Fluttertoast.showToast(msg: "pairing-otp返回值：$command");

      // 2. 通过 BLE 推送授权码
      final ok = await BleServiceSimple.writeCharacteristic(
        deviceId: device.lastBleAddress!,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.loginAuthCodeCharUuid,
        data: command.codeUnits,
        withResponse: true,
      );

      if (!ok) {
        throw Exception('写入蓝牙特征失败');
      }

      Fluttertoast.showToast(msg: "写入蓝牙特征ok");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登录请求已发送')),
        );
      }
    } catch (e, st) {
      print("❌ _loginDevice 出错: $e\n$st");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('登录失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _deviceLogout(SavedDeviceRecord device) async {
    try {
      // 示例 JSON 指令
      final command = '{"action":"logout"}';
      print(
          "准备写特征，deviceId=${device.lastBleAddress}, serviceUuid=${BleConstants.serviceUuid}");
      final ok = await BleServiceSimple.writeCharacteristic(
        deviceId: device.lastBleAddress!,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.logoutCharUuid,
        data: command.codeUnits,
        withResponse: true,
      );
      print("device_management_page: " + "writeCharacteristic ok=$ok");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已发送退出登录指令')),
        );
      }
    } catch (e, st) {
      print("❌ _deviceLogout 出错: $e\n$st");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送退出登录请求失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _sendCheckUpdate(SavedDeviceRecord device) async {
    try {
      // 示例 JSON 指令
      final command = '{"action":"update_version"}';
      print(
          "准备写特征，deviceId=${device.lastBleAddress}, serviceUuid=${BleConstants.serviceUuid}");
      final ok = await BleServiceSimple.writeCharacteristic(
        deviceId: device.lastBleAddress!,
        serviceUuid: BleConstants.serviceUuid,
        characteristicUuid: BleConstants.updateVersionCharUuid,
        data: command.codeUnits,
        withResponse: true,
      );
      print("device_management_page: " + "writeCharacteristic ok=$ok");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已发送检查更新指令')),
        );
      }
    } catch (e, st) {
      print("❌ _sendCheckUpdate 出错: $e\n$st");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送更新请求失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // 是否显示详细状态
  bool _shouldShowDetailedStatus(BleDeviceStatus status) {
    return status != BleDeviceStatus.authenticated;
  }

  // 是否正在连接
  bool _isConnecting(BleDeviceStatus status) {
    return status == BleDeviceStatus.scanning ||
           status == BleDeviceStatus.connecting ||
           status == BleDeviceStatus.authenticating;
  }

  // 获取详细状态图标
  IconData _getDetailedStatusIcon(BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.disconnected:
        return Icons.info_outline;
      case BleDeviceStatus.connected:
        return Icons.check_circle_outline;
      case BleDeviceStatus.error:
        return Icons.error_outline;
      case BleDeviceStatus.timeout:
        return Icons.timer_off;
      default:
        return Icons.info_outline;
    }
  }

  // 获取详细状态文本
  String _getDetailedStatusText(BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.disconnected:
        return '设备未连接，正在自动重连中...';
      case BleDeviceStatus.scanning:
        return '正在搜索设备...';
      case BleDeviceStatus.connecting:
        return '正在建立连接...';
      case BleDeviceStatus.connected:
        return '连接成功，正在进行认证...';
      case BleDeviceStatus.authenticating:
        return '正在验证设备身份...';
      case BleDeviceStatus.error:
        return '连接失败，5秒后将自动重试';
      case BleDeviceStatus.timeout:
        return '连接超时，5秒后将自动重试';
      case BleDeviceStatus.authenticated:
        return '设备已就绪';
    }
  }

  Future<void> _handleCheckUpdate() async {
    try {
      final ok = await ref
          .read(conn.deviceConnectionProvider.notifier)
          .writeWithTrustedChannel(
            serviceUuid: BleConstants.serviceUuid,
            characteristicUuid: BleConstants.updateVersionCharUuid,
            data: '{}'.codeUnits,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? (context.l10n.check_update) : '检查更新指令发送失败'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新失败: $e')),
      );
    }
  }

  String _statusText(BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.disconnected:
        return '未连接';
      case BleDeviceStatus.scanning:
        return '扫描中...';
      case BleDeviceStatus.connecting:
        return '连接中...';
      case BleDeviceStatus.connected:
        return '已连接';
      case BleDeviceStatus.authenticating:
        return '认证中...';
      case BleDeviceStatus.authenticated:
        return '已就绪';
      case BleDeviceStatus.error:
        return '连接失败';
      case BleDeviceStatus.timeout:
        return '连接超时';
    }
  }

  Color _statusColor(BuildContext context, BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.connected:
      case BleDeviceStatus.authenticated:
        return Colors.green;
      case BleDeviceStatus.connecting:
      case BleDeviceStatus.scanning:
      case BleDeviceStatus.authenticating:
        return Colors.orange;
      case BleDeviceStatus.error:
      case BleDeviceStatus.timeout:
        return Colors.red;
      case BleDeviceStatus.disconnected:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  // 蓝牙卡片
  Widget _buildBLESection(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '蓝牙连接状态',
              style: Theme
                  .of(context)
                  .textTheme
                  .titleMedium,
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
                    onPressed: () {
                      ref.read(conn.deviceConnectionProvider.notifier).checkNetworkStatus();
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('刷新'),
                  ),
                ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.connecting_to(ssid)),
          duration: const Duration(seconds: 2),
        ),
      );

      // 发送WiFi凭证到设备
      final success = await ref
          .read(conn.deviceConnectionProvider.notifier)
          .sendWifiCredentials(ssid, password);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.wifi_credentials_sent(ssid)),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.wifi_credentials_failed),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.connect_failed(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
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
      await ref
          .read(savedDevicesProvider.notifier)
          .removeDevice(device.deviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已删除设备 "${device.deviceName}"'),
            action: SnackBarAction(
              label: '知道了',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除设备失败: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}
