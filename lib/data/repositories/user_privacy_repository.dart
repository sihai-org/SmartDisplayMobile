import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/constants/app_environment.dart';
import '../../core/constants/user_privacy_constants.dart';
import '../../core/log/app_log.dart';

class UserPrivacyRepository {
  Future<void> acceptAgreement({
    required String accessToken,
    required String locale,
    PackageInfo? packageInfo,
  }) async {
    final deviceMetadata = await _getDeviceMetadata();
    final trimmedLocale = locale.trim();
    final trimmedVersion = packageInfo?.version.trim() ?? '';
    final trimmedBuildNumber = packageInfo?.buildNumber.trim() ?? '';
    final appVersion = trimmedVersion.isEmpty
        ? null
        : trimmedBuildNumber.isEmpty
        ? trimmedVersion
        : '$trimmedVersion+$trimmedBuildNumber';
    final requestPayload = <String, dynamic>{
      'privacy_version': UserPrivacyConstants.privacyVersion,
      'terms_version': UserPrivacyConstants.termsVersion,
      'source': UserPrivacyConstants.sourceMobileLogin,
      'app_version': appVersion,
      'platform': _platformName,
      'locale': trimmedLocale.isEmpty ? null : trimmedLocale,
      'device_model': deviceMetadata.model,
      'device_info': deviceMetadata.info,
    };
    AppLog.instance.info(
      '[user_privacy_accept_agreement] start platform=${requestPayload['platform']}, locale=${requestPayload['locale']}, app_version=${requestPayload['app_version']}, source=${requestPayload['source']}',
      tag: 'UserPrivacyApi',
    );
    final response = await http
        .post(
          Uri.parse(
            '${AppEnvironment.apiServerUrl}/user_privacy/accept_agreement',
          ),
          headers: {
            'Content-Type': 'application/json',
            'X-Access-Token': accessToken,
          },
          body: jsonEncode(requestPayload),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw UserPrivacyRequestException(
        'HTTP ${response.statusCode}: ${response.body}',
        requestPayload: requestPayload,
      );
    }

    final body = response.body.trim();
    if (body.isEmpty) {
      AppLog.instance.info(
        '[user_privacy_accept_agreement] success with empty body',
        tag: 'UserPrivacyApi',
      );
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      AppLog.instance.info(
        '[user_privacy_accept_agreement] success with non-JSON body',
        tag: 'UserPrivacyApi',
      );
      return;
    }

    if (decoded is Map && decoded['code'] != null && decoded['code'] != 200) {
      throw UserPrivacyRequestException(
        'API code ${decoded['code']}: ${decoded['message'] ?? body}',
        requestPayload: requestPayload,
      );
    }

    AppLog.instance.info(
      '[user_privacy_accept_agreement] success locale=$locale',
      tag: 'UserPrivacyApi',
    );
  }

  String? get _platformName {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return null;
  }

  Future<_DeviceMetadata> _getDeviceMetadata() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final model = _joinNonEmpty([info.manufacturer, info.model], ' ');
        final detail = _joinNonEmpty([
          'manufacturer=${info.manufacturer}',
          'brand=${info.brand}',
          'model=${info.model}',
          'device=${info.device}',
          'product=${info.product}',
          'sdk=${info.version.sdkInt}',
          'release=${info.version.release}',
        ], '; ');
        return _DeviceMetadata(model: model, info: detail);
      }

      if (Platform.isIOS) {
        final info = await plugin.iosInfo;
        final model = _firstNonEmpty([info.modelName, info.model]);
        final detail = _joinNonEmpty([
          'modelName=${info.modelName}',
          'model=${info.model}',
          'machine=${info.utsname.machine}',
          'systemVersion=${info.systemVersion}',
        ], '; ');
        return _DeviceMetadata(model: model, info: detail);
      }
    } catch (error, stackTrace) {
      AppLog.instance.warning(
        '[user_privacy_accept_agreement] failed to load device metadata',
        tag: 'UserPrivacyApi',
        error: error,
        stackTrace: stackTrace,
      );
    }

    return const _DeviceMetadata();
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  String? _joinNonEmpty(List<String?> values, String separator) {
    final parts = values
        .map((value) => value?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    return parts.join(separator);
  }
}

class UserPrivacyRequestException implements Exception {
  const UserPrivacyRequestException(
    this.message, {
    required this.requestPayload,
  });

  final String message;
  final Map<String, dynamic> requestPayload;

  @override
  String toString() => message;
}

class _DeviceMetadata {
  const _DeviceMetadata({this.model, this.info});

  final String? model;
  final String? info;
}
