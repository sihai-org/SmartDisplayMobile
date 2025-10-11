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

class SmartDisplayApp extends ConsumerWidget {
  const SmartDisplayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
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
