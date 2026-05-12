import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_display_mobile/core/log/biz_log_tag.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/auth_manager.dart';
import '../log/app_log.dart';
import '../network/http_timeouts.dart';

/// 灰度开关
final grayKeyMapProvider =
    AsyncNotifierProvider<GrayKeyMapNotifier, Map<String, bool>>(
      GrayKeyMapNotifier.new,
    );

class GrayKeyMapNotifier extends AsyncNotifier<Map<String, bool>> {
  static const _tag = 'grayKeyProvider';

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
    state = await AsyncValue.guard(_fetchFromServer);
  }

  void clear() {
    state = const AsyncData(<String, bool>{});
  }

  Future<Map<String, bool>> _fetchFromServer() async {
    AppLog.instance.info(
      '[$_tag] call _fetchFromServer',
      tag: BizLogTag.gray.value,
    );
    try {
      final supabase = Supabase.instance.client;
      await AuthManager.instance.ensureFreshSession();
      final response = await supabase.functions
          .invoke('mobile_gray_key_map_get', method: HttpMethod.get)
          .timeout(HttpTimeouts.business);
      AppLog.instance.info(
        '[$_tag] _fetchFromServer res: status=${response.status} data=${response.data}',
        tag: BizLogTag.gray.value,
      );

      if (response.status != 200) {
        AppLog.instance.warning(
          '[$_tag] _fetchFromServer res non-200: ${response.status} ${response.data}',
          tag: BizLogTag.gray.value,
        );
      }

      final dynamic respData = response.data;
      final dynamic grayKeyMap = (respData is Map) ? respData['data'] : null;

      if (grayKeyMap is! Map) {
        AppLog.instance.warning(
          '[$_tag] _fetchFromServer res invalid type: ${grayKeyMap.runtimeType} $grayKeyMap',
          tag: BizLogTag.gray.value,
        );
        return const <String, bool>{};
      }

      final res = grayKeyMap
          .map((k, v) => MapEntry(k.toString(), v is bool ? v : (v == true)))
          .cast<String, bool>();

      AppLog.instance.info('[$_tag] _fetchFromServer res=$res');
      return res;
    } on TimeoutException catch (e, st) {
      AppLog.instance.warning(
        '[$_tag] _fetchFromServer timeout',
        tag: BizLogTag.gray.value,
        error: e,
        stackTrace: st,
      );
      return const <String, bool>{};
    } catch (e, st) {
      AppLog.instance.error(
        '[$_tag] _fetchFromServer error',
        tag: BizLogTag.gray.value,
        error: e,
        stackTrace: st,
      );
      return const <String, bool>{};
    }
  }
}
