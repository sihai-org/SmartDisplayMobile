import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global providers that can be used throughout the app

/// Logger provider for debugging
final loggerProvider = Provider<Logger>((ref) => Logger());

/// Simple logger implementation
class Logger {
  void debug(String message, [Object? error, StackTrace? stackTrace]) {
    // ignore: avoid_print
    print('[DEBUG] $message');
    // ignore: avoid_print
    if (error != null) print('[DEBUG] Error: $error');
    // ignore: avoid_print
    if (stackTrace != null) print('[DEBUG] StackTrace: $stackTrace');
  }
  
  void info(String message, [Object? error, StackTrace? stackTrace]) {
    // ignore: avoid_print
    print('[INFO] $message');
    // ignore: avoid_print
    if (error != null) print('[INFO] Error: $error');
    // ignore: avoid_print
    if (stackTrace != null) print('[INFO] StackTrace: $stackTrace');
  }
  
  void warning(String message, [Object? error, StackTrace? stackTrace]) {
    // ignore: avoid_print
    print('[WARNING] $message');
    // ignore: avoid_print
    if (error != null) print('[WARNING] Error: $error');
    // ignore: avoid_print
    if (stackTrace != null) print('[WARNING] StackTrace: $stackTrace');
  }
  
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    // ignore: avoid_print
    print('[ERROR] $message');
    // ignore: avoid_print
    if (error != null) print('[ERROR] Error: $error');
    // ignore: avoid_print
    if (stackTrace != null) print('[ERROR] StackTrace: $stackTrace');
  }
}