import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/storage_keys.dart';

class WifiCredentialsRepository {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _currentUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  String? _keyForCurrentUser() {
    final uid = _currentUserId();
    if (uid == null || uid.isEmpty) return null;
    return '${StorageKeys.wifiCredentialsBase}_$uid';
    }

  Future<Map<String, String>> loadAll() async {
    final key = _keyForCurrentUser();
    if (key == null) return {};
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v ?? '').toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveAll(Map<String, String> data) async {
    final key = _keyForCurrentUser();
    if (key == null) return;
    await _storage.write(key: key, value: json.encode(data));
  }

  Future<String?> getPassword(String ssid) async {
    if (ssid.isEmpty) return null;
    final all = await loadAll();
    final v = all[ssid];
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> setPassword(String ssid, String password) async {
    if (ssid.isEmpty) return;
    final all = await loadAll();
    if (password.isEmpty) {
      // Empty passwords are not stored to avoid noise for open networks
      all.remove(ssid);
    } else {
      all[ssid] = password;
    }
    await saveAll(all);
  }

  Future<void> delete(String ssid) async {
    final all = await loadAll();
    all.remove(ssid);
    await saveAll(all);
  }
}
