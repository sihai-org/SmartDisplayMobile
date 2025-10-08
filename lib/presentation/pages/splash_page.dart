import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// import 'package:uni_links/uni_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/router/app_router.dart';
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

  // StreamSubscription? _sub;
  // String? _deepLinkPath;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();

    // 监听深度链接（已禁用）
    // _handleInitialUri();
    // _sub = uriLinkStream.listen((Uri? uri) {
    //   if (uri != null) {
    //     setState(() {
    //       _deepLinkPath = _canonicalPathFromUri(uri); // e.g., /home
    //     });
    //   }
    // });

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

  // Future<void> _handleInitialUri() async {
  //   try {
  //     final initialUri = await getInitialUri();
  //     if (initialUri != null) {
  //       setState(() {
  //         _deepLinkPath = _canonicalPathFromUri(initialUri);
  //       });
  //     }
  //   } catch (e) {
  //     print('Failed to get initial uri: $e');
  //   }
  // }

  // Map incoming URI to a canonical internal path like '/home'.
  // Supports:
  //  - App Links:  https://datou.com/home  (path: /home)
  //  - Legacy scheme: smartdisplaymobile://home (host=home, path='')
  //  - Legacy scheme: smartdisplaymobile:/home  (path: /home)
  // String? _canonicalPathFromUri(Uri uri) {
  //   if (uri.path.isNotEmpty) {
  //     return uri.path; // e.g., /home, /device/123
  //   }
  //   // Handle legacy scheme form where host encodes the target.
  //   if (uri.host.isNotEmpty && uri.scheme != 'http' && uri.scheme != 'https') {
  //     return '/${uri.host}';
  //   }
  //   return null;
  // }

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

      // 已登录 → 默认跳主页
      String targetRoute = AppRoutes.home;

      // 如果存在深度链接路径，则覆盖默认主页（已禁用）
      // if (_deepLinkPath != null) {
      //   switch (_deepLinkPath) {
      //     case '/home':
      //       targetRoute = AppRoutes.home;
      //       break;
      //     // 其他路径可继续扩展
      //   }
      // }

      context.go(targetRoute);
    } catch (_) {
      if (mounted) context.go(AppRoutes.login);
    }
  }

  @override
  void dispose() {
    // _sub?.cancel();
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
