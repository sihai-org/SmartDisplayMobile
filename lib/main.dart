import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers/app_state_provider.dart';
import 'core/providers/ble_connection_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/constants/app_constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/providers/locale_provider.dart';
import 'l10n/app_localizations.dart';
import 'core/deeplink/deep_link_handler.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'core/l10n/l10n_extensions.dart';
import 'core/providers/lifecycle_provider.dart';
import 'core/providers/saved_devices_provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 如果你要清 SharedPreferences
import 'package:sentry_flutter/sentry_flutter.dart';
import 'core/log/app_log.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 使用 Sentry 进行全局错误上报与性能监控
  await dotenv.load();
  await SentryFlutter.init((options) {
    options.dsn = dotenv.env['SENTRY_DSN'];
    options.environment = dotenv.env['SENTRY_ENV'] ?? 'development';
    options.tracesSampleRate = 0.2; // 根据需要调整采样率
    options.profilesSampleRate = 0.2; // CPU/内存性能分析采样率
    options.enableAutoSessionTracking = true;
    options.attachStacktrace = true;
    options.reportPackages = true;
    options.sendDefaultPii = false; // 如需上报用户信息，登录后在 scope 中设置
    options.debug = !kReleaseMode; // 调试模式下打印 SDK 日志
  }, appRunner: () async {
    // 在 app 启动前做初始化，以便 Sentry 能记录到潜在错误
    await Supabase.initialize(
      url: 'https://udrksmcgdqztosaouxwm.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVkcmtzbWNnZHF6dG9zYW91eHdtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg2MDIxMjMsImV4cCI6MjA3NDE3ODEyM30.zTi71CQrNfRf7pvSx_XmO1Em0YBpHiKEFgN2aNdtxyE',
    );

    // Initialize iOS deep link channel and fetch any initial link
    await DeepLinkHandler.init();

    // Set preferred orientations
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Set system UI overlay style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    runApp(const ProviderScope(child: SmartDisplayApp()));
  });
}

class SmartDisplayApp extends ConsumerStatefulWidget {
  const SmartDisplayApp({super.key});

  @override
  ConsumerState<SmartDisplayApp> createState() => _SmartDisplayAppState();
}

class _SmartDisplayAppState extends ConsumerState<SmartDisplayApp> {
  StreamSubscription<AuthState>? _authSub;

  bool _isCleaningUp = false; // 防止重复清理

  /// 所有登出后的清理都放这里
  Future<void> _performGlobalCleanup() async {
    AppLog.instance.info('_performGlobalCleanup start', tag: 'App');

    // 1. 蓝牙断连
    final connNotifier = ref.read(bleConnectionProvider.notifier);
    await connNotifier.disconnect();

    // 2. 失效 Riverpod 的状态（把内存里的缓存都打掉）
    ref.invalidate(savedDevicesProvider);
    ref.invalidate(isForegroundProvider);
    ref.invalidate(appStateProvider);
    ref.invalidate(bleConnectionProvider);

    // 3) 清理本地缓存/偏好（按你的项目来定）
    try {
      final prefs = await SharedPreferences.getInstance();
      // 举例：如果你把设备列表、本地 flags 持久化了，就删掉或重置
      // await prefs.remove('saved_devices');
      // await prefs.clear(); // 如果你想一把全清
    } catch (_) {}

    // 4) 解绑/停止其它前台监听（如有）
    try {
      // 比如：DeepLinkHandler 有 dispose 能力就调用
      // await DeepLinkHandler.dispose();
    } catch (_) {}

    AppLog.instance.info('_performGlobalCleanup end', tag: 'App');
  }

  @override
  void initState() {
    super.initState();
    // Listen to Supabase auth state changes
    _authSub =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      if (event == AuthChangeEvent.signedOut) {
        // 清空 Sentry 用户信息
        await Sentry.configureScope((scope) async {
          scope.setUser(null);
          await scope.clearBreadcrumbs();
        });
        if (!mounted || _isCleaningUp) return;
        _isCleaningUp = true;
        try {
          // **关键：先清理**
          await _performGlobalCleanup();
        } finally {
          // 再提示 + 跳转
          if (mounted) {
            Fluttertoast.showToast(msg: context.l10n.login_expired);
            appRouter.go(AppRoutes.login);
          }
          _isCleaningUp = false;
        }
      } else if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.tokenRefreshed) {
        // After sign-in or token refresh, sync devices from server
        if (!mounted) return;
        // 设置 Sentry 用户上下文（仅在你愿意上报用户信息时）
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          await Sentry.configureScope((scope) {
            scope.setUser(SentryUser(id: user.id, email: user.email));
          });
        }
        // Silent sync on auth events (default is silent)
        Future.microtask(() => ref
            .read(savedDevicesProvider.notifier)
            .syncFromServer());
      }
    });

    // Initial local load + sync on first frame（仅在已登录时）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && mounted) {
        ref
            .read(savedDevicesProvider.notifier)
            .syncFromServer(allowToast: true);
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    // Sync devices when app becomes visible (foreground). Keeping it in build
    // satisfies Riverpod's requirement for ref.listen in Consumer widgets.
    ref.listen<bool>(isForegroundProvider, (prev, curr) {
      if (prev == false && curr == true) {
        Future.microtask(() =>
            ref.read(savedDevicesProvider.notifier).syncFromServer(allowToast: true));
      }
    });
    return MaterialApp.router(
      // Title may be localized by platform; keep constant for now
      title: AppConstants.appName,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      // Localization
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
