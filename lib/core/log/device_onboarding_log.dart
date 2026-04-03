import 'dart:convert';

import 'app_log.dart';

class DeviceOnboardingLog {
  DeviceOnboardingLog._();

  static void info({
    required String event,
    required String result,
    String? displayDeviceId,
    int? versionCode,
    String? firmwareVersion,
    int? durationMs,
    Map<String, Object?> extra = const {},
  }) {
    AppLog.instance.info(
      _message(
        event: event,
        result: result,
        displayDeviceId: displayDeviceId,
        versionCode: versionCode,
        firmwareVersion: firmwareVersion,
        durationMs: durationMs,
        extra: extra,
      ),
      tag: 'Onboarding',
    );
  }

  static void warning({
    required String event,
    required String result,
    String? displayDeviceId,
    int? versionCode,
    String? firmwareVersion,
    int? durationMs,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> extra = const {},
  }) {
    AppLog.instance.warning(
      _message(
        event: event,
        result: result,
        displayDeviceId: displayDeviceId,
        versionCode: versionCode,
        firmwareVersion: firmwareVersion,
        durationMs: durationMs,
        extra: extra,
      ),
      tag: 'Onboarding',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void error({
    required String event,
    required String result,
    String? displayDeviceId,
    int? versionCode,
    String? firmwareVersion,
    int? durationMs,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> extra = const {},
  }) {
    AppLog.instance.error(
      _message(
        event: event,
        result: result,
        displayDeviceId: displayDeviceId,
        versionCode: versionCode,
        firmwareVersion: firmwareVersion,
        durationMs: durationMs,
        extra: extra,
      ),
      tag: 'Onboarding',
      error: error,
      stackTrace: stackTrace,
    );
  }

  static String _message({
    required String event,
    required String result,
    String? displayDeviceId,
    int? versionCode,
    String? firmwareVersion,
    int? durationMs,
    Map<String, Object?> extra = const {},
  }) {
    final payload = <String, Object?>{
      'event': event,
      'result': result,
      if (durationMs != null) 'duration_ms': durationMs,
      if (displayDeviceId != null && displayDeviceId.isNotEmpty)
        'display_device_id': displayDeviceId,
      if (displayDeviceId != null && displayDeviceId.isNotEmpty)
        'version_code': versionCode,
      if (firmwareVersion != null && firmwareVersion.isNotEmpty)
        'firmware_version': firmwareVersion,
    };

    for (final entry in extra.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is String && value.isEmpty) continue;
      payload[entry.key] = value;
    }

    return jsonEncode(payload);
  }
}
