import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../log/app_log.dart';

/// 灰度开关
final grayKeyMapProvider =
    AsyncNotifierProvider<GrayKeyMapNotifier, Map<String, bool>>(
  GrayKeyMapNotifier.new,
);

class GrayKeyMapNotifier extends AsyncNotifier<Map<String, bool>> {
  static const _tag = 'grayKeyMapProvider';

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
    AppLog.instance.info('[$_tag] fetch');
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.functions.invoke(
        'mobile_gray_key_map_get',
        method: HttpMethod.get,
      );
      AppLog.instance.info(
        '[$_tag] status=${response.status} data=${response.data}',
      );

      if (response.status != 200) {
        AppLog.instance.warning(
          '[GrayKey] edge function mobile_gray_key_map_get non-200: ${response.status} ${response.data}',
          tag: 'Supabase',
        );
      }

      final dynamic respData = response.data;
      final dynamic grayKeyMap = (respData is Map) ? respData['data'] : null;

      if (grayKeyMap is! Map) {
        AppLog.instance.warning(
          '[GrayKey] grayKeyMap invalid type: ${grayKeyMap.runtimeType} $grayKeyMap',
          tag: 'Supabase',
        );
        return const <String, bool>{};
      }

      final res = grayKeyMap
          .map((k, v) => MapEntry(k.toString(), v is bool ? v : (v == true)))
          .cast<String, bool>();

      AppLog.instance.info('[$_tag] res=$res');
      return res;
    } catch (e, st) {
      AppLog.instance.error(
        '[GrayKey] fetch failed',
        tag: 'Supabase',
        error: e,
        stackTrace: st,
      );
      return const <String, bool>{};
    }
  }
}
