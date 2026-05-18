import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:smart_display_mobile/core/log/biz_log_tag.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_manager.dart';
import '../constants/app_environment.dart';
import '../log/app_log.dart';
import '../network/http_timeouts.dart';

const _tag = 'grayKeyProvider';

/// 用户维度灰度
final grayKeyMapProvider =
    AsyncNotifierProvider<GrayKeyMapNotifier, Map<String, bool>>(
      GrayKeyMapNotifier.new,
    );

class GrayKeyMapNotifier extends AsyncNotifier<Map<String, bool>> {
  @override
  Future<Map<String, bool>> build() async {
    ref.keepAlive();
    return const <String, bool>{};
  }

  Future<void> refreshIfLoggedIn() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      clear();
      return;
    }
    await refresh();
  }

  Future<void> refresh() async {
    final previous = state;
    state = const AsyncLoading<Map<String, bool>>().copyWithPrevious(previous);
    state = await AsyncValue.guard(
      () => _fetchGrayKeyMap(sourceType: 'mobile'),
    );
  }

  void clear() {
    state = const AsyncData(<String, bool>{});
  }
}

/// 设备维度灰度（按 deviceId 查）
final deviceGrayKeyMapProvider = FutureProvider.autoDispose
    .family<Map<String, bool>, String>((ref, deviceId) async {
      return _fetchGrayKeyMap(sourceType: 'device', deviceId: deviceId);
    });

Future<Map<String, bool>> _fetchGrayKeyMap({
  required String sourceType,
  String? deviceId,
}) async {
  AppLog.instance.info(
    '[$_tag] call _fetchGrayKeyMap sourceType=$sourceType deviceId=$deviceId',
    tag: BizLogTag.gray.value,
  );
  try {
    final accessToken = await AuthManager.instance.getFreshAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      AppLog.instance.warning(
        '[$_tag] _fetchGrayKeyMap skip: no access token',
        tag: BizLogTag.gray.value,
      );
      return const <String, bool>{};
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-Access-Token': accessToken,
    };
    if (deviceId != null && deviceId.isNotEmpty) {
      headers['X-Device-Id'] = deviceId;
    }

    final response = await http
        .post(
          Uri.parse(
            '${AppEnvironment.apiServerUrl}/feature_flag/all_grayed_feature_flags',
          ),
          headers: headers,
          body: jsonEncode(<String, dynamic>{'source_type': sourceType}),
        )
        .timeout(HttpTimeouts.business);

    AppLog.instance.info(
      '[$_tag] _fetchGrayKeyMap res: status=${response.statusCode} body=${response.body}',
      tag: BizLogTag.gray.value,
    );

    if (response.statusCode != 200) {
      AppLog.instance.warning(
        '[$_tag] _fetchGrayKeyMap res non-200: ${response.statusCode} ${response.body}',
        tag: BizLogTag.gray.value,
      );
      return const <String, bool>{};
    }

    final body = response.body.trim();
    final dynamic decoded = body.isEmpty ? null : jsonDecode(body);
    final dynamic data = (decoded is Map) ? decoded['data'] : null;

    if (data is! Map) {
      AppLog.instance.warning(
        '[$_tag] _fetchGrayKeyMap res invalid data: ${data.runtimeType} $data',
        tag: BizLogTag.gray.value,
      );
      return const <String, bool>{};
    }

    final res = <String, bool>{};
    data.forEach((key, value) {
      if (value is Map && value['open'] == true) {
        res[key.toString()] = true;
      }
    });

    AppLog.instance.info('[$_tag] _fetchGrayKeyMap res=$res');
    return res;
  } on TimeoutException catch (e, st) {
    AppLog.instance.warning(
      '[$_tag] _fetchGrayKeyMap timeout',
      tag: BizLogTag.gray.value,
      error: e,
      stackTrace: st,
    );
    return const <String, bool>{};
  } catch (e, st) {
    AppLog.instance.error(
      '[$_tag] _fetchGrayKeyMap error',
      tag: BizLogTag.gray.value,
      error: e,
      stackTrace: st,
    );
    return const <String, bool>{};
  }
}
