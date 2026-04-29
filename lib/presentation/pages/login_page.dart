import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../core/l10n/l10n_extensions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import '../../core/log/app_log.dart';
import '../../core/log/device_onboarding_log.dart';
import '../../core/log/device_onboarding_events.dart';
import '../../core/providers/package_info_provider.dart';
import '../../data/repositories/user_privacy_repository.dart';

import '../../core/router/app_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/audit_mode_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  static const String _privacyPolicyUrl = 'https://m.vzngpt.com/privacy.html';
  static const String _termsUrl = 'https://m.vzngpt.com/terms.html';

  final UserPrivacyRepository _userPrivacyRepository = UserPrivacyRepository();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;
  bool _hasAgreed = false;
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
    FocusScope.of(context).unfocus(); // 先收起键盘，避免底部 toast 被遮挡
    if (!_hasAgreed) {
      Fluttertoast.showToast(msg: l10n.login_agreement_required);
      return;
    }

    if (_secondsRemaining > 0 || !_isEmailValid) return;

    final email = _emailController.text.trim();

    setState(() {
      _isSendingOtp = true;
      _error = null;
    });
    DeviceOnboardingLog.info(
      event: DeviceOnboardingEvents.authOtpSend,
      result: 'start',
      extra: {'email': email},
    );
    try {
      await Supabase.instance.client.auth.signInWithOtp(email: email);
      DeviceOnboardingLog.info(
        event: DeviceOnboardingEvents.authOtpSend,
        result: 'success',
        extra: {'email': email},
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
        extra: {'email': email, 'error_type': e.runtimeType.toString()},
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

  Future<void> _handleLogoTap() async {
    final now = DateTime.now();
    final auditModeEnabledMessage = context.l10n.audit_mode_enabled;
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
      if (!mounted) return;
      Fluttertoast.showToast(msg: auditModeEnabledMessage);
      // Navigate after mock device is seeded and state loaded
      context.go(AppRoutes.home);
    }
  }

  Future<void> _reportAgreementAcceptance({
    required String accessToken,
    required String locale,
  }) async {
    try {
      final packageInfo = await ref.read(packageInfoProvider.future);
      await _userPrivacyRepository.acceptAgreement(
        accessToken: accessToken,
        locale: locale,
        packageInfo: packageInfo,
      );
    } catch (e, st) {
      final warningPayload = <String, dynamic>{
        'event': 'user_privacy_accept_agreement_failed_after_login',
        'error_type': e.runtimeType.toString(),
        if (e is UserPrivacyRequestException) ...e.requestPayload,
        'error_message': e.toString(),
      };
      AppLog.instance.warning(
        jsonEncode(warningPayload),
        tag: 'UserPrivacyApi',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 验证验证码（登录）
  Future<void> _verifyOtp() async {
    final l10n = context.l10n;
    FocusScope.of(context).unfocus(); // 先收起键盘，避免底部 toast 被遮挡
    if (!_hasAgreed) {
      Fluttertoast.showToast(msg: l10n.login_agreement_required);
      return;
    }

    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    setState(() {
      _isLoading = true;
      _error = null;
    });
    DeviceOnboardingLog.info(
      event: DeviceOnboardingEvents.authOtpVerify,
      result: 'start',
      extra: {'email': email},
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
          extra: {'email': email},
        );
        unawaited(
          _reportAgreementAcceptance(
            accessToken: response.session!.accessToken,
            locale: l10n.localeName,
          ),
        );
        if (!mounted) return;
        Fluttertoast.showToast(msg: l10n.login_success);
        context.go(AppRoutes.home);
      } else {
        DeviceOnboardingLog.warning(
          event: DeviceOnboardingEvents.authOtpVerify,
          result: 'fail',
          extra: {'email': email, 'error_code': 'session_missing'},
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
          'email': email,
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

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                        onTap: _handleLogoTap,
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
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onChanged: (_) => setState(() => _error = null),
                      onSubmitted: (_) {
                        if (_isEmailValid && _isOtpValid && !_isLoading) {
                          _verifyOtp();
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.otp_spam_hint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
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

                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Checkbox(
                        value: _hasAgreed,
                        onChanged: (value) {
                          setState(() => _hasAgreed = value ?? false);
                        },
                      ),
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              l10n.login_agreement_prefix,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            GestureDetector(
                              onTap: () => _openExternalUrl(_privacyPolicyUrl),
                              child: Text(
                                l10n.privacy_policy,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                              ),
                            ),
                            Text(
                              l10n.login_agreement_and,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            GestureDetector(
                              onTap: () => _openExternalUrl(_termsUrl),
                              child: Text(
                                l10n.user_agreement,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
