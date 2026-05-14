import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/storage_keys.dart';

const _storage = FlutterSecureStorage();

/// 启动时从本地存储读取已保存的语言偏好。
/// 仅识别支持的 languageCode（`en` / `zh`）。
Future<Locale?> loadSavedLocale() async {
  try {
    final code = await _storage.read(key: StorageKeys.localePreference);
    if (code == null || code.isEmpty) return null;
    if (code == 'zh' || code == 'en') return Locale(code);
    return null;
  } catch (_) {
    return null;
  }
}

class LocaleNotifier extends Notifier<Locale?> {
  LocaleNotifier(this._initial);

  final Locale? _initial;

  @override
  Locale? build() => _initial;

  Future<void> setLocale(Locale? locale) async {
    state = locale;
    try {
      if (locale == null) {
        await _storage.delete(key: StorageKeys.localePreference);
      } else {
        await _storage.write(
          key: StorageKeys.localePreference,
          value: locale.languageCode,
        );
      }
    } catch (_) {
      // 写入失败不影响内存中的状态切换
    }
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale?>(
  () => LocaleNotifier(null),
);
