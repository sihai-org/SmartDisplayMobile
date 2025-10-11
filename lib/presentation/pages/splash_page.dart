import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/app_router.dart';
import '../../core/providers/app_state_provider.dart';
import '../../features/qr_scanner/utils/qr_data_parser.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/l10n_extensions.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  StreamSubscription<Uri>? _linkSub;
  Uri? _incomingUri;
  AppLinks? _appLinks;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();

    // 监听深度链接
    _initAppLinks();

    // 延迟导航，确保动画可见
    WidgetsBinding.instance.addPostFrameCallback((_) => _navigateNext());
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _animationController.forward();
  }

  Future<void> _initAppLinks() async {
    try {
      _appLinks = AppLinks();

      // Initial link
      final initialUri = await _appLinks!.getInitialLink();
      if (initialUri != null) {
        setState(() {
          _incomingUri = initialUri;
        });
      }

      // Stream subscription
      _linkSub = _appLinks!.uriLinkStream.listen((uri) {
        setState(() {
          _incomingUri = uri;
        });
        // If already authenticated and received a link while running, process immediately
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null && mounted) {
          _processDeepLink(uri);
        }
      });
    } catch (e) {
      // Ignore link errors; proceed normally
    }
  }

  void _processDeepLink(Uri uri) {
    // 统一解析 URL（与扫码一致）。成功则自动连接，失败跳结果页。
    try {
      final deviceData = QrDataParser.fromQrContent(uri.toString());
      ref.read(appStateProvider.notifier).setScannedDeviceData(deviceData);
      context.go('${AppRoutes.deviceConnection}?deviceId=${deviceData.deviceId}');
    } catch (e) {
      final raw = Uri.encodeComponent(uri.toString());
      context.go('${AppRoutes.qrCodeResult}?text=$raw');
    }
  }

  Future<void> _navigateNext() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (!mounted) return;

      // 先判断登录状态
      if (session == null) {
        context.go(AppRoutes.login);
        return;
      }

      // 已登录 → 若存在深链则处理，否则默认首页
      if (_incomingUri != null) {
        _processDeepLink(_incomingUri!);
      } else {
        context.go(AppRoutes.home);
      }
    } catch (_) {
      if (mounted) context.go(AppRoutes.login);
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App Icon
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.wifi_protected_setup,
                        size: 64,
                        color: Color(0xFF2196F3),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // App Name
                    Text(
                      AppConstants.appName,
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 16),

                    // App Description
                    Text(
                      context.l10n.appTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white.withOpacity(0.9),
                          ),
                    ),
                    const SizedBox(height: 48),

                    // Loading Indicator
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withOpacity(0.8),
                        ),
                        strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.splash_loading,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withOpacity(0.9),
                          ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
