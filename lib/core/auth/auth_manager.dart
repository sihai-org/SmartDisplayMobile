import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:synchronized/synchronized.dart';

import '../log/app_log.dart';
import '../log/biz_log_tag.dart';

class AuthManager {
  AuthManager._();

  static final AuthManager instance = AuthManager._();

  static const Duration refreshThreshold = Duration(minutes: 5);

  final Lock _refreshLock = Lock();

  GoTrueClient get _supabaseAuth => Supabase.instance.client.auth;

  Future<String?> getFreshAccessToken() async {
    try {
      final session = await ensureFreshSession();
      final accessToken = session?.accessToken;

      if (accessToken == null || accessToken.isEmpty) {
        return null;
      }

      return accessToken;
    } catch (_) {
      return null;
    }
  }

  Future<Session?> ensureFreshSession() async {
    final session = _supabaseAuth.currentSession;

    if (session == null || !_shouldRefresh(session)) {
      return session;
    }

    return _refreshLock.synchronized(() async {
      final latest = _supabaseAuth.currentSession;

      if (latest == null || !_shouldRefresh(latest)) {
        return latest;
      }

      try {
        AppLog.instance.info(
          jsonEncode({
            'event': 'refresh_session_start',
            'expires_at': latest.expiresAt,
            'expires_in_sec': _expiresInSeconds(latest),
            'threshold_sec': refreshThreshold.inSeconds,
          }),
          tag: BizLogTag.auth.tag,
        );

        final response = await _supabaseAuth.refreshSession();
        final refreshed = response.session ?? _supabaseAuth.currentSession;

        AppLog.instance.info(
          jsonEncode({
            'event': 'refresh_session_success',
            'has_response_session': response.session != null,
            'expires_at': refreshed?.expiresAt,
            'expires_in_sec': refreshed == null
                ? null
                : _expiresInSeconds(refreshed),
          }),
          tag: BizLogTag.auth.tag,
        );

        return refreshed;
      } catch (error, stackTrace) {
        final current = _supabaseAuth.currentSession;
        final fallbackToCurrent = current != null && !_isExpired(current);

        AppLog.instance.error(
          jsonEncode({
            'event': 'refresh_session_failed',
            'has_current_session': current != null,
            'current_expired': current == null ? null : _isExpired(current),
            'fallback_to_current': fallbackToCurrent,
            'current_expires_at': current?.expiresAt,
            'current_expires_in_sec': current == null
                ? null
                : _expiresInSeconds(current),
          }),
          tag: BizLogTag.auth.tag,
          error: error,
          stackTrace: stackTrace,
        );

        if (fallbackToCurrent) {
          return current;
        }

        rethrow;
      }
    });
  }

  bool _shouldRefresh(Session session) {
    final expiresAt = session.expiresAt;
    if (expiresAt == null) {
      return false;
    }

    final now = DateTime.now();
    final expiresAtTime = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);

    return !expiresAtTime.isAfter(now.add(refreshThreshold));
  }

  bool _isExpired(Session session) {
    final expiresAt = session.expiresAt;
    if (expiresAt == null) {
      return false;
    }

    final now = DateTime.now();
    final expiresAtTime = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);

    return !expiresAtTime.isAfter(now);
  }

  int? _expiresInSeconds(Session session) {
    final expiresAt = session.expiresAt;
    if (expiresAt == null) {
      return null;
    }

    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return expiresAt - nowSec;
  }
}
