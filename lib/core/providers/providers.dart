import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../log/app_log.dart';

/// Global providers that can be used throughout the app

/// Logger provider for debugging
final loggerProvider = Provider<Logger>((ref) => Logger());

/// Simple logger implementation
class Logger {
  void debug(String message, [Object? error, StackTrace? stackTrace]) =>
      AppLog.instance.debug(message, error: error, stackTrace: stackTrace);

  void info(String message, [Object? error, StackTrace? stackTrace]) =>
      AppLog.instance.info(message, error: error, stackTrace: stackTrace);

  void warning(String message, [Object? error, StackTrace? stackTrace]) =>
      AppLog.instance.warning(message, error: error, stackTrace: stackTrace);

  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      AppLog.instance.error(message, error: error, stackTrace: stackTrace);
}
