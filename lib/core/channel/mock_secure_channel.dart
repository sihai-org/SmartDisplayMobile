import 'dart:async';
import '../audit/audit_mode.dart';
import 'secure_channel.dart';

class MockSecureChannel implements SecureChannel {
  MockSecureChannel({
    required this.displayDeviceId,
    required this.bleDeviceId,
    required this.devicePublicKeyHex,
  });

  @override
  final String displayDeviceId;

  @override
  final String bleDeviceId;

  @override
  final String devicePublicKeyHex;

  final _evtCtrl = StreamController<Map<String, dynamic>>.broadcast();

  String? _lastHs;

  @override
  String? get lastHandshakeStatus => _lastHs;

  @override
  Stream<Map<String, dynamic>> get events => _evtCtrl.stream;

  @override
  Future<void> ensureAuthenticated(String userId) async {
    // Simulate successful handshake but with 'empty_bound' state
    // so that the app flows as if the device has no binding info.
    _lastHs = 'empty_bound';
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  @override
  Future<Map<String, dynamic>> send(
    Map<String, dynamic> msg, {
    Duration? timeout,
    int retries = 0,
    bool Function(Map<String, dynamic>)? isFinal,
  }) async {
    final type = (msg['type'] ?? '').toString();
    switch (type) {
      case 'device.info':
        return {
          'ok': true,
          'data': {
            'network': {
              'connected': true,
              'ssid': 'MockWiFi',
              'ip': '192.168.1.2',
              'signal': -55,
              'frequency': 2412,
            },
            'firmwareVersion': '1.0.0',
          }
        };
      case 'wifi.scan':
        return {
          'ok': true,
          'data': [
            {'ssid': 'MockWiFi', 'rssi': -50, 'secure': true},
            {'ssid': 'Cafe_Free', 'rssi': -70, 'secure': false},
          ]
        };
      case 'wifi.config':
        return {
          'ok': true,
          'data': {'status': 'connected'}
        };
      case 'network.status':
        return {
          'ok': true,
          'data': {
            'connected': true,
            'ssid': 'MockWiFi',
            'ip': '192.168.1.2',
            'signal': -55,
            'frequency': 2412,
          }
        };
      case 'login.auth':
        return {'ok': true, 'data': {}};
      case 'logout':
        return {'ok': true, 'data': {}};
      case 'update.version':
        return {'ok': true, 'data': 'update_latest'};
      default:
        return {'ok': true, 'data': {}};
    }
  }

  @override
  Future<void> dispose() async {
    await _evtCtrl.close();
  }
}
