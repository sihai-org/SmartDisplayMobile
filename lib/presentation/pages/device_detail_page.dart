import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../data/repositories/saved_devices_repository.dart';
import '../../features/device_connection/providers/device_connection_provider.dart' as conn;
import '../../features/device_connection/models/ble_device_data.dart';
import '../../features/device_connection/models/network_status.dart';
import '../../features/qr_scanner/models/device_qr_data.dart';

class DeviceDetailPage extends ConsumerStatefulWidget {
  const DeviceDetailPage({super.key});

  @override
  ConsumerState<DeviceDetailPage> createState() => _DeviceDetailState();
}

class _DeviceDetailState extends ConsumerState<DeviceDetailPage> {
  bool _autoTried = false;

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
    final saved = ref.watch(savedDevicesProvider);
    final connState = ref.watch(conn.deviceConnectionProvider);
    
    // 监听连接状态变化，实现智能重连和智能WiFi处理
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

        _handleSmartReconnect();
      }
    });
    
    // 监听保存设备状态变化，延迟尝试自动连接以避免在build期间修改provider
    ref.listen<SavedDevicesState>(savedDevicesProvider, (previous, current) {
      if (current.loaded && current.lastSelectedId != null && 
          (previous == null || !previous.loaded)) {
        // 延迟执行，避免在build期间修改provider
        Future.delayed(Duration.zero, () {
          if (mounted) {
            _tryAutoConnect();
          }
        });
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartDisplay'),
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.settings),
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            onPressed: () => context.push(AppRoutes.deviceManagement),
            icon: const Icon(Icons.devices),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!saved.loaded || saved.devices.isEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  child: Column(
                    children: [
                      Icon(Icons.wifi_protected_setup, size: 64, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text('欢迎使用大头智显', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text('请扫描显示器上的二维码为显示器配置网络', style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // 显示最近设备卡片
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(AppConstants.defaultPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildStatusIcon(connState.status),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                saved.devices.firstWhere((e)=> e.deviceId==saved.lastSelectedId).deviceName, 
                                style: Theme.of(context).textTheme.titleMedium
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _statusText(connState.status), 
                                style: TextStyle(color: _statusColor(context, connState.status))
                              ),
                            ]),
                          ),
                          _buildActionButtons(connState),
                        ],
                      ),
                      // 显示详细状态信息
                      if (_shouldShowDetailedStatus(connState.status)) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              if (_isConnecting(connState.status))
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _statusColor(context, connState.status),
                                    ),
                                  ),
                                )
                              else
                                Icon(
                                  _getDetailedStatusIcon(connState.status),
                                  size: 16,
                                  color: _statusColor(context, connState.status),
                                ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _getDetailedStatusText(connState.status),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: _statusColor(context, connState.status),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // 显示网络状态或WiFi列表
              if (connState.status == BleDeviceStatus.authenticated) ...[
                const SizedBox(height: 16),
                _buildNetworkSection(context, connState),
              ],
            ],

            const SizedBox(height: 32),

            // 只在没有保存设备时显示主扫描按钮
            if (!saved.loaded || saved.devices.isEmpty)
              ElevatedButton(
                onPressed: () => context.push(AppRoutes.qrScanner),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.qr_code_scanner, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      '扫描二维码配网',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            
            // 动态间距：有设备时减少间距，无设备时增加间距
            if (!saved.loaded || saved.devices.isEmpty)
              const SizedBox(height: 32)
            else
              const SizedBox(height: 16),

            // 添加更多间距，替代Spacer
            const SizedBox(height: 48),

            // Help Section
            Card(
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.defaultPadding),
                child: Column(
                  children: [
                    Icon(
                      Icons.help_outline,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '使用帮助',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '1. 确保显示器已开机并显示二维码\n'
                      '2. 点击"扫描二维码配网"按钮\n'
                      '3. 对准显示器屏幕上的二维码扫描\n'
                      '4. 按照提示完成网络配置',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ],
                ),
              ),
            ),

            // 底部安全区域
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  // 构建状态图标
  Widget _buildStatusIcon(BleDeviceStatus status) {
    switch (status) {
      case BleDeviceStatus.disconnected:
        return Icon(Icons.tv_off, size: 40, color: Colors.grey);
      case BleDeviceStatus.scanning:
      case BleDeviceStatus.connecting:
      case BleDeviceStatus.authenticating:
        return Icon(Icons.tv, size: 40, color: Colors.orange);
      case BleDeviceStatus.connected:
      case BleDeviceStatus.authenticated:
        return Icon(Icons.tv, size: 40, color: Colors.green);
      case BleDeviceStatus.error:
      case BleDeviceStatus.timeout:
        return Icon(Icons.tv_off, size: 40, color: Colors.red);
    }
  }

  // 构建操作按钮
  Widget _buildActionButtons(conn.DeviceConnectionState connState) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (connState.status == BleDeviceStatus.disconnected ||
            connState.status == BleDeviceStatus.error ||
            connState.status == BleDeviceStatus.timeout)
          IconButton(
            onPressed: () {
              _autoTried = false; // 重置标记
              _tryAutoConnect();
            },
            icon: const Icon(Icons.refresh),
            tooltip: '重新连接',
          ),
        IconButton(
          onPressed: () => context.push(AppRoutes.qrScanner),
          icon: const Icon(Icons.qr_code_scanner),
          tooltip: '添加设备',
        ),
      ],
    );
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

  // 构建网络状态或WiFi列表部分
  Widget _buildNetworkSection(BuildContext context, conn.DeviceConnectionState connState) {
    return Card(
      elevation: 1,
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
                  '设备未连接网络，请选择WiFi网络进行配网：',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Text(
                  '无法获取网络状态，显示可用WiFi网络：',
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
                '已连接: ${networkStatus.displaySsid ?? '未知网络'}',
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
                  '频段: ${networkStatus.is5GHz ? '5GHz' : '2.4GHz'}',
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
    if (connState.wifiNetworks.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.wifi_off, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              '未找到WiFi网络',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(conn.deviceConnectionProvider.notifier).requestWifiScan();
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('扫描网络'),
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
          label: const Text('刷新网络列表'),
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
                    wifi.secure ? '请输入WiFi密码:' : 'WiFi密码 (如果是开放网络请留空):',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: isObscured,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: wifi.secure ? '请输入密码' : '如果是开放网络请留空',
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
                        ? '检测到这是安全网络，需要密码'
                        : '检测到这是开放网络，但如果实际需要密码请输入',
                    style: TextStyle(
                      fontSize: 12,
                      color: wifi.secure ? Colors.green[700] : Colors.orange[700],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '信号强度: ${wifi.rssi} dBm',
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
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();

                    // 获取用户输入的密码（允许为空）
                    final password = passwordController.text.trim();

                    // 发送WiFi凭证到TV端
                    await _connectToWifi(wifi.ssid, password, ref);
                  },
                  child: const Text('连接'),
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
          content: Text('正在连接 $ssid...'),
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
            content: Text('WiFi凭证已发送到TV: $ssid'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('发送WiFi凭证失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('连接失败: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
