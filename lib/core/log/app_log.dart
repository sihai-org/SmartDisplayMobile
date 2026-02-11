import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Global logging singleton.
///
/// - debug/info: local log only
/// - warning/error: local log + Sentry report
class AppLog {
  AppLog._internal();
  static final AppLog instance = AppLog._internal();

  void debug(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _local('[DEBUG]', message, tag: tag, error: error, stackTrace: stackTrace);
  }

  void info(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _local('[INFO]', message, tag: tag, error: error, stackTrace: stackTrace);
  }

  void warning(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _local('[WARNING]', message, tag: tag, error: error, stackTrace: stackTrace);
    _reportWarning(message, error: error, stackTrace: stackTrace, tag: tag);
  }

  void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _local('[ERROR]', message, tag: tag, error: error, stackTrace: stackTrace);
    _reportError(message, error: error, stackTrace: stackTrace, tag: tag);
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  String _three(int n) => n.toString().padLeft(3, '0');

  void _local(String level, String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    final now = DateTime.now();
    // 格式化时间：MM-dd HH:mm:ss.SSS
    final time =
        '${_two(now.month)}-${_two(now.day)} '
        '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}.'
        '${_three(now.millisecond)}';

    final prefix = tag == null || tag.isEmpty ? level : '$level[$tag]';
    final text = '$time $prefix $message';
    // Use debugPrint to avoid message truncation issues.
    debugPrint(text);
    if (error != null) {
      debugPrint('$prefix Error: $error');
    }
    if (stackTrace != null) {
      debugPrint('$prefix StackTrace: $stackTrace');
    }
  }

  Future<void> _reportWarning(String message, {Object? error, StackTrace? stackTrace, String? tag}) async {
    try {
      final full = tag == null || tag.isEmpty ? message : '[$tag] $message';
      if (error != null) {
        await Sentry.captureException(error, stackTrace: stackTrace, withScope: (scope) {
          scope.level = SentryLevel.warning;
          scope.setTag('applog.tag', tag ?? '');
        });
      } else {
        await Sentry.captureMessage(full, level: SentryLevel.info);
      }
    } catch (_) {
      // Swallow reporting errors to avoid cascading failures
    }
  }

  Future<void> _reportError(String message, {Object? error, StackTrace? stackTrace, String? tag}) async {
    try {
      final full = tag == null || tag.isEmpty ? message : '[$tag] $message';
      if (error != null) {
        await Sentry.captureException(error, stackTrace: stackTrace, withScope: (scope) {
          scope.level = SentryLevel.error;
          scope.setTag('applog.tag', tag ?? '');
        });
      } else {
        await Sentry.captureMessage(full, level: SentryLevel.error);
      }
    } catch (_) {
      // Swallow reporting errors to avoid cascading failures
    }
  }
}

