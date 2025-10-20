import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://udrksmcgdqztosaouxwm.supabase.co', // 你的 Supabase 项目 URL
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVkcmtzbWNnZHF6dG9zYW91eHdtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTg2MDIxMjMsImV4cCI6MjA3NDE3ODEyM30.zTi71CQrNfRf7pvSx_XmO1Em0YBpHiKEFgN2aNdtxyE',                   // 项目的 anon 公钥
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
}

class SmartDisplayApp extends ConsumerStatefulWidget {
  const SmartDisplayApp({super.key});

  @override
  ConsumerState<SmartDisplayApp> createState() => _SmartDisplayAppState();
}

class _SmartDisplayAppState extends ConsumerState<SmartDisplayApp> {
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    // Listen to Supabase auth state changes
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedOut) {
        if (!mounted) return;
        // Show localized toast and navigate to login
        Fluttertoast.showToast(msg: context.l10n.login_expired);
        appRouter.go(AppRoutes.login);
      } else if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.tokenRefreshed) {
        // After sign-in or token refresh, sync devices from server
        if (!mounted) return;
        Future.microtask(() =>
            ref.read(savedDevicesProvider.notifier).syncFromServer());
      }
    });

    // Initial sync on first frame if already signed in
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && mounted) {
        ref.read(savedDevicesProvider.notifier).syncFromServer();
      }
    });

    // moved: foreground listen should be in build for Consumer widgets
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
    ref.listen<bool>(isForegroundProvider, (prev, isFg) {
      if (isFg == true) {
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
