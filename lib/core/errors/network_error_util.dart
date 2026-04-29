import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

// 仅用于 HTTP / Supabase / Edge Function 请求
class NetworkErrorUtil {
  const NetworkErrorUtil._();

  static bool isTimeout(Object? error) {
    if (error is TimeoutException) return true;

    final message = _message(error);
    return message.contains('timeout') ||
        message.contains('timed out') ||
        message.contains('connection timed out');
  }

  static bool isNetworkError(Object? error) {
    if (error is SocketException) return true;
    if (error is HttpException) return true;
    if (error is HandshakeException) return true;

    // Supabase Auth 会把底层 SocketException / ClientException
    // 包装成 AuthRetryableFetchException。
    if (error is AuthRetryableFetchException) return true;

    final message = _message(error);

    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('no address associated with hostname') ||
        message.contains('network is unreachable') ||
        message.contains('no route to host') ||
        message.contains('connection refused') ||
        message.contains('connection reset') ||
        message.contains('connection closed') ||
        message.contains('connection abort') ||
        message.contains('clientexception') ||
        message.contains('xmlhttprequest error') ||
        message.contains('handshakeexception');
  }

  static bool isNetworkOrTimeout(Object? error) {
    return isNetworkError(error) || isTimeout(error);
  }

  static String _message(Object? error) {
    return error?.toString().toLowerCase() ?? '';
  }
}