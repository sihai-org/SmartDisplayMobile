import 'dart:async';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../router/app_router.dart';
// Note: actual deep link handling unified in SplashPage via AppLinks.

class DeepLinkHandler {
  static const MethodChannel _channel = MethodChannel('smart_display/deep_link');
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Listen for live links
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final url = args['url'] as String?;
        if (url != null) {
          _handleUrl(url);
        }
      }
    });

    // Fetch initial link if any
    try {
      final initial = await _channel.invokeMethod<String>('getInitialLink');
      if (initial != null) {
        _handleUrl(initial);
      }
    } catch (_) {
      // no-op: channel may not be available on non-iOS platforms
    }
  }

  static void _handleUrl(String url) {
    // 已统一在 SplashPage 中处理（可解析为设备信息则自动连接，否则到结果页）。
    // 这里避免重复导航，直接交给 AppLinks 流程。
    // 为确保不丢失链接，仍然将链接推到当前路由（Splash 会读取 initialLink）。
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    // 导航到当前路径等价触发，实际逻辑在 Splash 中执行
    appRouter.go('/');
  }
}
