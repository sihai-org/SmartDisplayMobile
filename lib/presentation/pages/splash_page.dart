import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/app_router.dart';
import '../../core/deeplink/deep_link_handler.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/l10n/l10n_extensions.dart';
import '../../core/flow/device_entry_coordinator.dart';

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
      Uri? initialUri = await _appLinks!.getInitialLink();
      // 若 AppLinks 未拿到（iOS 自定义 scheme 场景），尝试从原生通道缓存读取
      initialUri ??= DeepLinkHandler.consumeInitialUri();
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

  Future<void> _processDeepLink(Uri uri) async {
    // Delegate to unified coordinator so deep links and QR follow the same flow
    await DeviceEntryCoordinator.handle(context, ref, uri.toString());
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
      // 再次兜底读取 DeepLinkHandler（避免竞态导致先跳 home）
      _incomingUri ??= DeepLinkHandler.consumeInitialUri();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
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
                    // App Logo
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/images/logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      context.l10n.splash_title,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.l10n.splash_subtitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: isDark
                                ? Colors.white.withOpacity(0.7)
                                : Colors.black.withOpacity(0.6),
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
