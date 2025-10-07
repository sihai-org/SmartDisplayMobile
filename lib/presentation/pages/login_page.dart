import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/l10n/l10n_extensions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../l10n/app_localizations.dart';

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

  bool _isSendingOtp = false; // 发送验证码按钮 loading
  bool _isLoading = false;    // 登录按钮 loading

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

    setState(() => _isSendingOtp = true);
    Fluttertoast.showToast(msg: l10n!.sending_otp);

    try {
      await Supabase.instance.client.auth.signInWithOtp(email: email);

      Fluttertoast.showToast(msg: l10n.otp_sent_to(email));

      setState(() {
        _otpSent = true;
        _error = null;
      });

      _startCountdown();
    } catch (e) {
      Fluttertoast.showToast(msg: l10n.send_failed(e.toString()));
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isSendingOtp = false);
    }
  }

  /// 验证验证码（登录）
  Future<void> _verifyOtp() async {
    final l10n = context.l10n;
    FocusScope.of(context).unfocus(); // 收起键盘

    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    setState(() => _isLoading = true);
    Fluttertoast.showToast(msg: l10n!.signing_in);

    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: otp,
      );

      if (response.session != null) {
        Fluttertoast.showToast(msg: l10n.login_success);
        context.go(AppRoutes.home);
      } else {
        Fluttertoast.showToast(msg: l10n.otp_invalid);
      }
    } catch (e) {
      setState(() => _error = e.toString());
      Fluttertoast.showToast(msg: l10n.login_failed(e.toString()));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Google 登录占位
  Future<void> _signInWithGoogle() async {
    final l10n = context.l10n;
    Fluttertoast.showToast(msg: l10n!.google_signin_placeholder);
  }

  @override
  Widget build(BuildContext context) {
    final isCountingDown = _secondsRemaining > 0;
    final l10n = context.l10n;
    if (l10n == null) {
      return const Scaffold(body: SizedBox());
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.login_title)),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(), // 点击空白收起键盘
        behavior: HitTestBehavior.translucent,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.email_signin,
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),

                    // 邮箱输入
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: l10n.login_email,
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (!_isEmailValid && _emailController.text.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Text(l10n.email_invalid,
                          style: const TextStyle(color: Colors.red, fontSize: 12),),
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
                        onChanged: (_) => setState(() {}),
                      ),
                      if (!_isOtpValid && _otpController.text.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 4.0),
                          child: Text(l10n.otp_invalid,
                            style: const TextStyle(color: Colors.red, fontSize: 12),),
                        ),
                      const SizedBox(height: 16),
                    ],

                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.red)),
                      ),

                    // 发送验证码按钮
                    ElevatedButton(
                      onPressed: (!_isEmailValid || isCountingDown || _isSendingOtp)
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
                          valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                          : Text(isCountingDown
                              ? (l10n?.resend_in(_secondsRemaining)) ?? 'Resend in ${_secondsRemaining}s'
                              : (l10n?.send_otp ?? 'Send Code')),
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
                            valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                            : Text(l10n?.login_button ?? 'Log in'),
                      ),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 10),

                    // Google 登录按钮
                    ElevatedButton.icon(
                      onPressed: _signInWithGoogle,
                      icon: const Icon(Icons.login),
                      label: Text(l10n?.signin_with_google ?? 'Sign in with Google'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
