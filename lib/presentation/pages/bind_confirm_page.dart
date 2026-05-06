import 'dart:async';
import 'dart:io';
import '../../core/log/app_log.dart';
import '../../core/log/device_onboarding_log.dart';
import '../../core/log/device_onboarding_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../core/router/app_router.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../core/providers/ble_connection_provider.dart';
import '../../core/providers/bind_success_coordinator.dart';
import '../../core/errors/exceptions.dart';
import '../../core/constants/enum.dart';
import '../../core/models/device_qr_data.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/audit/audit_mode.dart';
import '../../core/auth/auth_manager.dart';
import '../../core/ble/reliable_queue.dart';
import '../../data/repositories/saved_devices_repository.dart';
import '../../core/utils/binding_flow_utils.dart';
import '../../l10n/app_localizations.dart';

class BindConfirmPage extends ConsumerStatefulWidget {
  const BindConfirmPage({super.key, required this.displayDeviceId});

  final String displayDeviceId;

  @override
  ConsumerState<BindConfirmPage> createState() => _BindConfirmPageState();
}

enum BindResult { success, fail }

class _BindConfirmPageState extends ConsumerState<BindConfirmPage> {
  bool _sending = false; // 按钮loading
  Future<void> _disconnectAndClearOnUserExit() async {
    await BindingFlowUtils.disconnectAndClearOnUserExit(context, ref);
  }

  void _showToastIfMounted(
    String Function(AppLocalizations l10n) messageBuilder,
  ) {
    if (!mounted) return;
    Fluttertoast.showToast(msg: messageBuilder(context.l10n));
  }

  @override
  void initState() {
    super.initState();
  }

  Future<void> handleClickBind(DeviceQrData scanned) async {
    if (_sending) return;
    setState(() => _sending = true);
    final firmwareVersion = ref
        .read(savedDevicesProvider.notifier)
        .findById(scanned.displayDeviceId)
        ?.firmwareVersion;
    DeviceOnboardingLog.info(
      event: DeviceOnboardingEvents.bind,
      result: 'start',
      displayDeviceId: scanned.displayDeviceId,
      versionCode: scanned.versionCode,
      firmwareVersion: firmwareVersion,
    );

    try {
      final result = await _bindViaOtp(ref, scanned);
      if (!mounted) return;
      if (result == BindResult.success) {
        DeviceOnboardingLog.info(
          event: DeviceOnboardingEvents.bind,
          result: 'success',
          displayDeviceId: scanned.displayDeviceId,
          versionCode: scanned.versionCode,
          firmwareVersion: firmwareVersion,
        );
        await ref.read(bindSuccessCoordinatorProvider).onBindSuccess(scanned);
        if (!mounted) return;

        context.go(
          '${AppRoutes.home}?displayDeviceId=${Uri.encodeComponent(scanned.displayDeviceId)}',
        );
      } else {
        DeviceOnboardingLog.warning(
          event: DeviceOnboardingEvents.bind,
          result: 'fail',
          displayDeviceId: scanned.displayDeviceId,
          versionCode: scanned.versionCode,
          firmwareVersion: firmwareVersion,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  // 返回时：若当前设备不在设备列表且蓝牙已连接，则断开
  Future<void> _maybeDisconnectIfEphemeral() async {
    await _disconnectAndClearOnUserExit();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final app = ref.watch(appStateProvider);
    final scanned = app.scannedQrData;
    final same = scanned?.displayDeviceId == widget.displayDeviceId;

    AppLog.instance.info(
      '[bind_confirm_page] scanned=$scanned, displayDeviceId=${widget.displayDeviceId}',
      tag: 'Binding',
    );

    // 如果没有扫描数据，提示返回扫码
    if (!same || scanned == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.bind_device_title)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.no_device_info_message),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoutes.qrScanner),
                child: Text(context.l10n.back_to_scan),
              ),
            ],
          ),
        ),
      );
    }

    return PopScope(
      // 允许系统返回手势/按钮先尝试出栈
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          unawaited(_disconnectAndClearOnUserExit());
        }
        if (context.mounted) context.go(AppRoutes.qrScanner);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.confirm_binding_title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _disconnectAndClearOnUserExit();
              if (!context.mounted) return;
              context.go(AppRoutes.qrScanner);
            },
          ),
        ),
        body: Padding(
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
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.tv, color: Colors.grey),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      scanned.deviceName,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(context.l10n.confirm_binding_question),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await _maybeDisconnectIfEphemeral();
                        // 清理扫描与连接状态，返回扫码页后重新初始化
                        ref.read(appStateProvider.notifier).clearScannedData();
                        ref.read(bleConnectionProvider.notifier).resetState();
                        if (!context.mounted) return;
                        context.go(AppRoutes.qrScanner);
                      },
                      child: Text(context.l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _sending
                          ? null
                          : () => handleClickBind(scanned),
                      child: _sending
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(context.l10n.bind_button),
                              ],
                            )
                          : Text(context.l10n.bind_button),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildWifiHelpText(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWifiHelpText(BuildContext context) {
    final theme = Theme.of(context);
    final helpStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    void route() {
      final idParam = Uri.encodeComponent(widget.displayDeviceId);
      context.push(
        '${AppRoutes.wifiSelection}?scannedDisplayDeviceId=$idParam&returnToBindConfirm=1',
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: route,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.bind_wifi_help_text, style: helpStyle),
              Icon(
                Icons.chevron_right,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<BindResult> _bindViaOtp(WidgetRef ref, DeviceQrData device) async {
    final firmwareVersion = ref
        .read(savedDevicesProvider.notifier)
        .findById(device.displayDeviceId)
        ?.firmwareVersion;
    const functionName = 'pairing-otp';
    late final String email;
    late final String otpToken;
    try {
      // In audit mode, fully mock binding flow: skip network OTP, send mock login,
      // then persist device locally so later syncFromServer() sees it.
      if (AuditMode.enabled) {
        final notifier = ref.read(bleConnectionProvider.notifier);
        await notifier.sendDeviceLoginCode('audit@example.com', '000000');
        try {
          final repo = SavedDevicesRepository();
          await repo.selectFromQr(device);
        } catch (_) {}
        _showToastIfMounted((l10n) => l10n.bind_success);
        return BindResult.success;
      }

      final supabase = Supabase.instance.client;
      await AuthManager.instance.ensureFreshSession();
      final response = await supabase.functions.invoke(
        functionName,
        body: {'device_id': device.displayDeviceId},
      );
      if (response.status != 200) {
        DeviceOnboardingLog.warning(
          event: DeviceOnboardingEvents.bindServerOtp,
          result: 'fail',
          displayDeviceId: device.displayDeviceId,
          versionCode: device.versionCode,
          firmwareVersion: firmwareVersion,
          extra: {'status_code': response.status},
        );
        AppLog.instance.warning(
          '[bindViaOtp] edge function pairing-otp non-200: ${response.status} ${response.data}',
          tag: 'Supabase',
        );
        _showToastIfMounted((l10n) => l10n.bind_failed);
        return BindResult.fail;
      }
      final data = response.data as Map;
      email = (data['email'] ?? '') as String;
      otpToken = (data['token'] ?? '') as String;
      if (email.isNotEmpty && otpToken.isNotEmpty) {
        DeviceOnboardingLog.info(
          event: DeviceOnboardingEvents.bindServerOtp,
          result: 'success',
          displayDeviceId: device.displayDeviceId,
          versionCode: device.versionCode,
          firmwareVersion: firmwareVersion,
        );
      }
      if (email.isEmpty || otpToken.isEmpty) {
        DeviceOnboardingLog.warning(
          event: DeviceOnboardingEvents.bindServerOtp,
          result: 'fail',
          displayDeviceId: device.displayDeviceId,
          versionCode: device.versionCode,
          firmwareVersion: firmwareVersion,
          extra: const {'error_code': 'missing_email_or_token'},
        );
        _showToastIfMounted((l10n) => l10n.bind_failed);
        return BindResult.fail;
      }
    } on SocketException catch (e, st) {
      DeviceOnboardingLog.error(
        event: DeviceOnboardingEvents.bindServerOtp,
        result: 'fail',
        displayDeviceId: device.displayDeviceId,
        versionCode: device.versionCode,
        firmwareVersion: firmwareVersion,
        error: e,
        stackTrace: st,
        extra: {
          'error_type': e.runtimeType.toString(),
          'error_message': e.message,
          'function_name': functionName,
          'socket_address': e.address?.host,
          'socket_port': e.port,
          'has_session': Supabase.instance.client.auth.currentSession != null,
        },
      );
      AppLog.instance.error(
        '[bindViaOtp] socket exception during $functionName',
        tag: 'Supabase',
        error: e,
        stackTrace: st,
      );
      _showToastIfMounted((l10n) => l10n.bind_mobile_network_error);
      return BindResult.fail;
    } catch (e, st) {
      DeviceOnboardingLog.error(
        event: DeviceOnboardingEvents.bindServerOtp,
        result: 'fail',
        displayDeviceId: device.displayDeviceId,
        versionCode: device.versionCode,
        firmwareVersion: firmwareVersion,
        error: e,
        stackTrace: st,
        extra: {
          'error_type': e.runtimeType.toString(),
          'error_message': e.toString(),
          'function_name': functionName,
          'has_session': Supabase.instance.client.auth.currentSession != null,
        },
      );
      AppLog.instance.error(
        '[bindViaOtp] exception during pairing-otp + sendDeviceLoginCode',
        tag: 'Supabase',
        error: e,
        stackTrace: st,
      );
      _showToastIfMounted((l10n) => l10n.bind_failed);
      return BindResult.fail;
    }

    try {
      // 构造负载并通过连接管理器进行加密发送
      final notifier = ref.read(bleConnectionProvider.notifier);
      await notifier.sendDeviceLoginCode(email, otpToken);
      AppLog.instance.info(
        '[bindViaOtp] sendDeviceLoginCode success, displayDeviceId=${device.displayDeviceId}',
        tag: 'Binding',
      );
      _showToastIfMounted((l10n) => l10n.bind_success);
      return BindResult.success;
    } on UserMismatchException {
      _showToastIfMounted((l10n) => l10n.device_bound_elsewhere);
      return BindResult.fail;
    } on TimeoutException {
      _showToastIfMounted((l10n) => l10n.bind_timeout_check_network_and_retry);
      return BindResult.fail;
    } on BleException catch (e) {
      final details = e.details;
      final type = details?['type']?.toString();
      final resp = details?['resp'];
      final data = resp is Map ? resp['data'] : null;
      final isDeviceLoginFailed =
          type == 'login.auth' &&
          data is Map &&
          data['status']?.toString() == 'login_failed';
      if (isDeviceLoginFailed) {
        _showToastIfMounted((l10n) => l10n.bind_device_network_timeout);
      } else if (e.code == BleErrorCode.notReady.name) {
        _showToastIfMounted(
          (l10n) => l10n.ble_not_ready_enable_bluetooth_check_permission,
        );
      } else {
        _showToastIfMounted((l10n) => l10n.ble_disconnected_rescan_bind);
      }
      return BindResult.fail;
    } catch (e, st) {
      AppLog.instance.error(
        '[bindViaOtp] unexpected exception during sendDeviceLoginCode',
        tag: 'Binding',
        error: e,
        stackTrace: st,
      );
      _showToastIfMounted((l10n) => l10n.bind_failed);
      return BindResult.fail;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
