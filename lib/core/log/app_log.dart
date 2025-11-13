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

  void _local(String level, String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    final prefix = tag == null || tag.isEmpty ? level : '$level[$tag]';
    final text = '$prefix $message';
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
        await Sentry.captureMessage(full, level: SentryLevel.warning);
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

