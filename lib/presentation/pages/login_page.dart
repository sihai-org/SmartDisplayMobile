import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../core/l10n/l10n_extensions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import '../../core/log/app_log.dart';
import '../../core/log/device_onboarding_log.dart';
import '../../core/log/device_onboarding_events.dart';

import '../../core/router/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/audit_mode_provider.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;
  String? _error;

  int _secondsRemaining = 0;
  Timer? _timer;

  // Audit trigger: 5 taps in 3 seconds
  int _logoTapCount = 0;
  DateTime? _firstTapAt;

  bool _isSendingOtp = false; // 发送验证码按钮 loading
  bool _isLoading = false; // 登录按钮 loading

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  /// 简单邮箱合法性校验
  bool get _isEmailValid {
    final email = _emailController.text.trim();
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    return emailRegex.hasMatch(email);
  }

  /// 验证码合法性校验（6 位数字）
  bool get _isOtpValid {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) return false;
    final otpRegex = RegExp(r'^\d{6}$');
    return otpRegex.hasMatch(otp);
  }

  /// 启动倒计时
  void _startCountdown() {
    setState(() {
      _secondsRemaining = 60;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
        setState(() {
          _secondsRemaining = 0;
        });
      }
    });
  }

  /// 发送验证码
  Future<void> _sendOtp() async {
    final l10n = context.l10n;
    FocusScope.of(context).unfocus(); // 收起键盘

    if (_secondsRemaining > 0 || !_isEmailValid) return;

    final email = _emailController.text.trim();

    setState(() {
      _isSendingOtp = true;
      _error = null;
    });
    DeviceOnboardingLog.info(
      event: DeviceOnboardingEvents.authOtpSend,
      result: 'start',
    );
    try {
      await Supabase.instance.client.auth.signInWithOtp(email: email);
      DeviceOnboardingLog.info(
        event: DeviceOnboardingEvents.authOtpSend,
        result: 'success',
      );

      Fluttertoast.showToast(msg: l10n.otp_sent_to(email));

      setState(() {
        _otpSent = true;
        _error = null;
      });

      _startCountdown();
    } catch (e, st) {
      DeviceOnboardingLog.error(
        event: DeviceOnboardingEvents.authOtpSend,
        result: 'fail',
        error: e,
        stackTrace: st,
        extra: {'error_type': e.runtimeType.toString()},
      );
      AppLog.instance.error(
        '[signInWithOtp] failed',
        tag: 'Supabase',
        error: e,
        stackTrace: st,
      );
      setState(() => _error = l10n.login_failed_generic);
    } finally {
      setState(() => _isSendingOtp = false);
    }
  }

  Future<void> _handleLogoTap(BuildContext context) async {
    final now = DateTime.now();
    if (_firstTapAt == null ||
        now.difference(_firstTapAt!) > const Duration(seconds: 3)) {
      _firstTapAt = now;
      _logoTapCount = 1;
      return;
    }
    _logoTapCount += 1;
    if (_logoTapCount >= 5) {
      // Enter audit mode via provider (handles seeding + state refresh)
      try {
        final container = ProviderScope.containerOf(context, listen: false);
        await container.read(auditModeProvider.notifier).enable();
      } catch (_) {}
      Fluttertoast.showToast(msg: context.l10n.audit_mode_enabled);
      // Navigate after mock device is seeded and state loaded
      if (context.mounted) {
        context.go(AppRoutes.home);
      }
    }
  }

  /// 验证验证码（登录）
  Future<void> _verifyOtp() async {
    final l10n = context.l10n;
    FocusScope.of(context).unfocus(); // 收起键盘

    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    setState(() {
      _isLoading = true;
      _error = null;
    });
    DeviceOnboardingLog.info(
      event: DeviceOnboardingEvents.authOtpVerify,
      result: 'start',
    );
    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: otp,
      );

      if (response.session != null) {
        DeviceOnboardingLog.info(
          event: DeviceOnboardingEvents.authOtpVerify,
          result: 'success',
        );
        Fluttertoast.showToast(msg: l10n.login_success);
        context.go(AppRoutes.home);
      } else {
        DeviceOnboardingLog.warning(
          event: DeviceOnboardingEvents.authOtpVerify,
          result: 'fail',
          extra: const {'error_code': 'session_missing'},
        );
        Fluttertoast.showToast(msg: l10n.otp_invalid);
      }
    } catch (e, st) {
      final errorCode = e is AuthApiException ? e.code : null;
      DeviceOnboardingLog.error(
        event: DeviceOnboardingEvents.authOtpVerify,
        result: 'fail',
        error: e,
        stackTrace: st,
        extra: {
          'error_type': e.runtimeType.toString(),
          if (errorCode != null && errorCode.isNotEmpty)
            'error_code': errorCode,
        },
      );
      AppLog.instance.error(
        '[verifyOTP] failed',
        tag: 'Supabase',
        error: e,
        stackTrace: st,
      );
      final errorMessage = _mapVerifyOtpError(e, l10n);
      setState(() => _error = errorMessage);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _mapVerifyOtpError(Object error, AppLocalizations l10n) {
    if (error is AuthApiException) {
      switch (error.code) {
        case 'otp_expired':
          return l10n.login_failed_otp_expired;
        case 'over_request_rate_limit':
        case 'over_email_send_rate_limit':
          return l10n.login_failed_rate_limited;
        case 'validation_failed':
          return l10n.login_failed_otp_invalid;
      }
    }

    return l10n.login_failed_generic;
  }

  @override
  Widget build(BuildContext context) {
    final isCountingDown = _secondsRemaining > 0;
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(), // 点击空白收起键盘
        behavior: HitTestBehavior.translucent,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App Logo
                  Center(
                    child: SizedBox(
                      width: 96,
                      height: 96,
                      child: GestureDetector(
                        onTap: () => _handleLogoTap(context),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.email_signin,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // 邮箱输入
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: l10n.login_email,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setState(() => _error = null),
                  ),

                  const SizedBox(height: 16),

                  // 验证码输入框（发送后显示）
                  if (_otpSent) ...[
                    TextField(
                      controller: _otpController,
                      decoration: InputDecoration(
                        labelText: l10n.otp_code,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() => _error = null),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),

                  // 发送验证码按钮
                  ElevatedButton(
                    onPressed:
                        (!_isEmailValid || isCountingDown || _isSendingOtp)
                        ? null
                        : _sendOtp,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: _isSendingOtp
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            isCountingDown
                                ? l10n.resend_in(_secondsRemaining)
                                : l10n.send_otp,
                          ),
                  ),

                  const SizedBox(height: 12),

                  // 登录按钮（发送过验证码才显示）
                  if (_otpSent)
                    ElevatedButton(
                      onPressed: (!_isEmailValid || !_isOtpValid || _isLoading)
                          ? null
                          : _verifyOtp,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(l10n.login_button),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
