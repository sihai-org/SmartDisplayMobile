import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/pages/splash_page.dart';
import '../../presentation/pages/login_page.dart';
import '../../presentation/pages/main_page.dart';
import '../../presentation/pages/qr_scanner_page.dart';
import '../../presentation/pages/device_connection_page.dart';
import '../../presentation/pages/wifi_selection_page.dart';
import '../../presentation/pages/provisioning_page.dart';
import '../../presentation/pages/device_management_page.dart';
import '../../presentation/pages/settings_page.dart';
import '../l10n/l10n_extensions.dart';

/// App routes
class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String qrScanner = '/qr-scanner';
  static const String deviceConnection = '/device-connection';
  static const String wifiSelection = '/wifi-selection';
  static const String provisioning = '/provisioning';
  static const String deviceManagement = '/device-management';
  static const String settings = '/settings';
}

/// Router configuration
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: true,
  routes: [
    // Splash Page
    GoRoute(
      path: AppRoutes.splash,
      name: 'splash',
      builder: (context, state) => const SplashPage(),
    ),

    // Login Page
    GoRoute(
      path: AppRoutes.login,
      name: 'login',
      builder: (context, state) => LoginPage(),
    ),

    // Device Detail Page
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const MainPage(),
    ),

    // QR Scanner Page
    GoRoute(
      path: AppRoutes.qrScanner,
      name: 'qr-scanner',
      builder: (context, state) => const QrScannerPage(),
    ),

    // Device Connection Page
    GoRoute(
      path: AppRoutes.deviceConnection,
      name: 'device-connection',
      builder: (context, state) {
        final deviceId = state.uri.queryParameters['deviceId'] ?? '';
        return DeviceConnectionPage(deviceId: deviceId);
      },
    ),

    // WiFi Selection Page
    GoRoute(
      path: AppRoutes.wifiSelection,
      name: 'wifi-selection',
      builder: (context, state) {
        final deviceId = state.uri.queryParameters['deviceId'] ?? '';
        return WiFiSelectionPage(deviceId: deviceId);
      },
    ),

    // Provisioning Page
    GoRoute(
      path: AppRoutes.provisioning,
      name: 'provisioning',
      builder: (context, state) {
        final deviceId = state.uri.queryParameters['deviceId'] ?? '';
        final ssid = state.uri.queryParameters['ssid'] ?? '';
        return ProvisioningPage(deviceId: deviceId, ssid: ssid);
      },
    ),

    // Device Management Page
    GoRoute(
      path: AppRoutes.deviceManagement,
      name: 'device-management',
      builder: (context, state) => const DeviceManagementPage(),
    ),

    // Settings Page
    GoRoute(
      path: AppRoutes.settings,
      name: 'settings',
      builder: (context, state) => const SettingsPage(),
    ),
  ],

  // Error handling
  errorBuilder: (context, state) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.page_not_found),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.page_not_found,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.page_not_exist(state.uri.toString()),
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.home),
              child: Text(l10n.back_to_home),
            ),
          ],
        ),
      ),
    );
  },
);
