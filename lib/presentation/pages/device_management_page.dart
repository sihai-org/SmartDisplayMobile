import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/ble_constants.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/router/app_router.dart';
import '../../data/repositories/saved_devices_repository.dart';
import '../../features/device_connection/services/ble_service_simple.dart';

class DeviceManagementPage extends ConsumerStatefulWidget {
  final void Function(String deviceId)? onDeviceTapped;
  const DeviceManagementPage({super.key, this.onDeviceTapped});

  @override
  ConsumerState<DeviceManagementPage> createState() =>
      _DeviceManagementPageState();
}

class _DeviceManagementPageState extends ConsumerState<DeviceManagementPage> {
  @override
  void initState() {
    super.initState();
    // 确保加载最新的设备列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(savedDevicesProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final savedDevicesState = ref.watch(savedDevicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.device_management),
        elevation: 1,
        actions: [
          IconButton(
            onPressed: () => _addNewDevice(),
            icon: const Icon(Icons.add),
            tooltip: context.l10n.scan_qr,
          ),
        ],
      ),
      body: savedDevicesState.loaded
          ? _buildDeviceList(context, savedDevicesState)
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildDeviceList(BuildContext context, SavedDevicesState state) {
    if (state.devices.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppConstants.defaultPadding),
      itemCount: state.devices.length,
      itemBuilder: (context, index) {
        final device = state.devices[index];
        final isSelected = device.deviceId == state.lastSelectedId;

        return Card(
          elevation: isSelected ? 4 : 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Image.asset(
              'assets/images/device.png',
              width: 56,
              height: 56,
              fit: BoxFit.contain,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    device.deviceName.isNotEmpty ? device.deviceName : context.l10n.unknown_device,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      {if (!isSelected) _selectDevice(device.deviceId)},
                  icon: Icon(
                    isSelected ? Icons.task_alt : Icons.radio_button_unchecked,
                  ),
                  color: isSelected ? Colors.green : Colors.grey,
                  tooltip: isSelected ? null : context.l10n.set_current_device,
                ),
              ],
            ),
            onTap: () async {
              await ref
                  .read(savedDevicesProvider.notifier)
                  .select(device.deviceId);
              if (mounted) {
                widget.onDeviceTapped?.call(device.deviceId);
              }
            },
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  '${context.l10n.device_id_label}: ${device.deviceId}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
                if (device.lastBleAddress != null)
                  Text(
                    '${context.l10n.ble_label}: ${device.lastBleAddress}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                if (device.lastConnectedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${context.l10n.last_connected_at}: ${_formatDateTime(device.lastConnectedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices_other,
              size: 80,
              color: Theme.of(context).colorScheme.surfaceVariant,
            ),
            const SizedBox(height: 24),
            Text(
              context.l10n.empty_saved_devices,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.empty_hint_add_by_scan,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _addNewDevice(),
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(context.l10n.scan_qr_add_device),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addNewDevice() {
    context.go(AppRoutes.qrScanner);
  }

  void _selectDevice(String deviceId) async {
    try {
      await ref.read(savedDevicesProvider.notifier).select(deviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.device_switched),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.switch_device_failed(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

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

  void _showDeleteDialog(BuildContext context, SavedDeviceRecord device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除设备'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('确定要删除以下设备吗？'),
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

  void _deleteDevice(SavedDeviceRecord device) async {
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

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}小时前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}
