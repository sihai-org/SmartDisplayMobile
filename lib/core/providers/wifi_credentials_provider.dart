import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_display_mobile/data/repositories/wifi_credentials_repository.dart';

class WifiCredentialsState {
  final Map<String, String> creds;
  final bool loaded;
  const WifiCredentialsState({this.creds = const {}, this.loaded = false});

  WifiCredentialsState copyWith({Map<String, String>? creds, bool? loaded}) =>
      WifiCredentialsState(creds: creds ?? this.creds, loaded: loaded ?? this.loaded);
}

class WifiCredentialsNotifier extends StateNotifier<WifiCredentialsState> {
  WifiCredentialsNotifier(this._repo) : super(const WifiCredentialsState());
  final WifiCredentialsRepository _repo;

  Future<void> load() async {
    final all = await _repo.loadAll();
    state = WifiCredentialsState(creds: all, loaded: true);
  }

  String? getPasswordSync(String ssid) {
    if (ssid.isEmpty) return null;
    return state.creds[ssid];
  }

  Future<String?> getPassword(String ssid) async {
    if (!state.loaded) await load();
    return getPasswordSync(ssid);
  }

  Future<void> setPassword(String ssid, String password) async {
    await _repo.setPassword(ssid, password);
    final updated = Map<String, String>.from(state.creds);
    if (password.isEmpty) {
      updated.remove(ssid);
    } else {
      updated[ssid] = password;
    }
    state = state.copyWith(creds: updated, loaded: true);
  }

  Future<void> delete(String ssid) async {
    await _repo.delete(ssid);
    final updated = Map<String, String>.from(state.creds);
    updated.remove(ssid);
    state = state.copyWith(creds: updated, loaded: true);
  }
}

final wifiCredentialsProvider = StateNotifierProvider<WifiCredentialsNotifier, WifiCredentialsState>((ref) {
  return WifiCredentialsNotifier(WifiCredentialsRepository());
});

