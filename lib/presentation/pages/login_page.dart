import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';

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
    FocusScope.of(context).unfocus(); // 收起键盘

    if (_secondsRemaining > 0 || !_isEmailValid) return;

    final email = _emailController.text.trim();

    setState(() => _isSendingOtp = true);
    Fluttertoast.showToast(msg: "正在发送验证码...");

    try {
      await Supabase.instance.client.auth.signInWithOtp(email: email);

      Fluttertoast.showToast(msg: "验证码已发送到 $email");

      setState(() {
        _otpSent = true;
        _error = null;
      });

      _startCountdown();
    } catch (e) {
      Fluttertoast.showToast(msg: "发送失败: $e");
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isSendingOtp = false);
    }
  }

  /// 验证验证码（登录）
  Future<void> _verifyOtp() async {
    FocusScope.of(context).unfocus(); // 收起键盘

    final email = _emailController.text.trim();
    final otp = _otpController.text.trim();

    setState(() => _isLoading = true);
    Fluttertoast.showToast(msg: "正在登录，请稍候...");

    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.email,
        email: email,
        token: otp,
      );

      if (response.session != null) {
        Fluttertoast.showToast(msg: "登录成功");
        context.go(AppRoutes.home);
      } else {
        Fluttertoast.showToast(msg: "验证码无效，请重试");
      }
    } catch (e) {
      setState(() => _error = e.toString());
      Fluttertoast.showToast(msg: "登录失败: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Google 登录占位
  Future<void> _signInWithGoogle() async {
    Fluttertoast.showToast(msg: "Google 登录入口（暂未实现）");
  }

  @override
  Widget build(BuildContext context) {
    final isCountingDown = _secondsRemaining > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
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
                    Text("邮箱登录",
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 20),

                    // 邮箱输入
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: '邮箱',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (!_isEmailValid && _emailController.text.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4.0),
                        child: Text(
                          '请输入正确的邮箱地址',
                          style: TextStyle(color: Colors.red, fontSize: 12),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // 验证码输入框（发送后显示）
                    if (_otpSent) ...[
                      TextField(
                        controller: _otpController,
                        decoration: const InputDecoration(
                          labelText: '验证码',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                      ),
                      if (!_isOtpValid && _otpController.text.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 4.0),
                          child: Text(
                            '验证码必须是6位数字',
                            style: TextStyle(color: Colors.red, fontSize: 12),
                          ),
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
                          : Text(
                        isCountingDown
                            ? '重新发送 (${_secondsRemaining}s)'
                            : '发送验证码',
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
                            valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                            : const Text('登录'),
                      ),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 10),

                    // Google 登录按钮
                    ElevatedButton.icon(
                      onPressed: _signInWithGoogle,
                      icon: const Icon(Icons.login),
                      label: const Text('使用 Google 登录'),
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
