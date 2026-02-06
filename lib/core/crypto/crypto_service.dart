import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import '../log/app_log.dart';

/// BLE认证加密服务
/// 实现X25519 ECDH密钥交换 + AES-256-GCM加密
class CryptoService {
  SimpleKeyPair? _ephemeralKeyPair; // 临时密钥对
  List<int>? _ephemeralPublicKey; // 缓存公钥，避免主线程重复提取
  List<int>? _sharedSecret; // 共享密钥
  List<int>? _sessionKey; // 会话密钥
  int? _lastClientTimestamp;
  int _ephemeralKeyGenEpoch = 0; // 防止 cleanup 后旧异步任务回写

  // AES-GCM加密器
  late final AesGcm _aesGcm;

  CryptoService() {
    _aesGcm = AesGcm.with256bits();
  }

  /// 生成临时密钥对
  Future<void> generateEphemeralKeyPair() async {
    final epoch = ++_ephemeralKeyGenEpoch;
    final snapshot = await Isolate.run<_EphemeralKeyPairSnapshot>(
      _generateEphemeralKeyPairSnapshot,
    );
    if (epoch != _ephemeralKeyGenEpoch) return; // 被更新/清理，丢弃旧结果
    _ephemeralKeyPair = SimpleKeyPairData(
      snapshot.privateKey,
      publicKey: SimplePublicKey(snapshot.publicKey, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    _ephemeralPublicKey = snapshot.publicKey;
  }

  /// 获取本地公钥 (32字节)
  Future<List<int>> getLocalPublicKey() async {
    if (_ephemeralKeyPair == null) {
      throw Exception('必须先生成临时密钥对');
    }
    if (_ephemeralPublicKey != null) {
      return _ephemeralPublicKey!;
    }
    final publicKey = await _ephemeralKeyPair!.extractPublicKey();
    _ephemeralPublicKey = publicKey.bytes;
    return _ephemeralPublicKey!;
  }

  /// 执行ECDH密钥交换 + 设备长期公钥认证
  Future<void> performKeyExchange({
    required List<int> remoteEphemeralPubKey, // 握手响应里的设备临时公钥
    required List<int>? signature, // 握手响应里的签名
    required String devicePublicKeyHex, // 二维码里的设备长期公钥（hex）
    required List<int> clientEphemeralPubKey, // 手机端发出的临时公钥
    required int timestamp, // 握手响应里的时间戳
    required int clientTimestamp, // 👈 改成客户端时间戳
  }) async {
    if (_ephemeralKeyPair == null) {
      throw Exception('必须先生成临时密钥对');
    }

    try {
      AppLog.instance.info('🔑 开始执行密钥交换 + 公钥认证', tag: 'Crypto');
      final totalSw = Stopwatch()..start();

      if (signature == null) {
        throw Exception('❌ 缺少公钥签名');
      }

      final extractSw = Stopwatch()..start();
      final keyPairData = await _ephemeralKeyPair!.extract();
      extractSw.stop();

      final workerInput = _KeyExchangeWorkerInput(
        localPrivateKey: keyPairData.bytes,
        clientEphemeralPubKey: clientEphemeralPubKey,
        remoteEphemeralPubKey: remoteEphemeralPubKey,
        signature: signature,
        devicePublicKeyHex: devicePublicKeyHex,
        clientTimestamp: clientTimestamp,
      );
      final isolateSw = Stopwatch()..start();
      final result = await Isolate.run<_KeyExchangeWorkerResult>(
        () => _runKeyExchangeWorker(workerInput),
      );
      isolateSw.stop();
      _sharedSecret = result.sharedSecret;
      _sessionKey = result.sessionKey;
      AppLog.instance.info('✅ 设备公钥签名验证通过', tag: 'Crypto');
      AppLog.instance.debug(
        '🤝 ECDH密钥交换完成，共享密钥长度: ${_sharedSecret!.length}',
        tag: 'Crypto',
      );
      AppLog.instance.debug(
        '🔑 会话密钥派生完成，长度: ${_sessionKey!.length}',
        tag: 'Crypto',
      );
      totalSw.stop();
      AppLog.instance.debug(
        '⏱ performKeyExchange.total(${totalSw.elapsedMilliseconds}ms), '
        'extractLocalKey(${extractSw.elapsedMilliseconds}ms), '
        'isolate.run(${isolateSw.elapsedMilliseconds}ms)',
        tag: 'Crypto',
      );
      AppLog.instance.debug(
        '⏱ performKeyExchange.worker.total(${result.totalMs}ms), '
        'verifySig(${result.verifyMs}ms), '
        'ecdh(${result.ecdhMs}ms), '
        'hkdf(${result.hkdfMs}ms)',
        tag: 'Crypto',
      );
    } catch (e) {
      AppLog.instance.error('❌ performKeyExchange 失败', tag: 'Crypto', error: e);
      rethrow;
    }
  }

  /// 加密数据 (AES-256-GCM)
  Future<EncryptedData> encrypt(String plaintext) async {
    if (_sessionKey == null) {
      throw Exception('会话密钥未生成，无法加密');
    }

    final plaintextBytes = utf8.encode(plaintext);
    final secretKey = SecretKey(_sessionKey!);

    final nonce = _aesGcm.newNonce();

    final secretBox = await _aesGcm.encrypt(
      plaintextBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    return EncryptedData(
      ciphertext: secretBox.cipherText,
      nonce: secretBox.nonce,
      mac: secretBox.mac.bytes,
    );
  }

  /// 解密数据 (AES-256-GCM)
  Future<String> decrypt(EncryptedData encryptedData) async {
    if (_sessionKey == null) {
      throw Exception('会话密钥未生成，无法解密');
    }

    final secretKey = SecretKey(_sessionKey!);

    final secretBox = SecretBox(
      encryptedData.ciphertext,
      nonce: encryptedData.nonce,
      mac: Mac(encryptedData.mac),
    );

    final decryptedBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return utf8.decode(decryptedBytes);
  }

  /// 清理密钥材料
  void cleanup() {
    _ephemeralKeyGenEpoch++; // 使所有在途 keygen 结果失效
    _ephemeralKeyPair = null;
    _ephemeralPublicKey = null;
    _sharedSecret = null;
    _sessionKey = null;
    AppLog.instance.debug('🧹 密钥材料已清理', tag: 'Crypto');
  }

  /// 获取握手初始化数据 (Map格式)
  Future<Map<String, dynamic>> getHandshakeInitData() async {
    final publicKey = await getLocalPublicKey();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    _lastClientTimestamp = timestamp;

    return {
      'type': 'handshake_init',
      'public_key': _bytesToHex(publicKey),
      'timestamp': timestamp,
      'version': '1.0',
    };
  }

  int? get clientTimestamp => _lastClientTimestamp;

  /// 解析握手响应数据
  HandshakeResponse parseHandshakeResponse(String jsonData) {
    final data = jsonDecode(jsonData) as Map<String, dynamic>;
    return parseHandshakeResponseMap(data);
  }

  /// 解析握手响应数据（Map）
  HandshakeResponse parseHandshakeResponseMap(Map<String, dynamic> data) {
    if (data['type'] != 'handshake_response') {
      throw Exception('无效的握手响应类型');
    }
    return HandshakeResponse(
      publicKey: _hexToBytes(data['public_key']),
      timestamp: data['timestamp'] ?? 0,
      signature: data['signature'] != null
          ? _hexToBytes(data['signature'])
          : null,
    );
  }

  // 工具方法
  String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  /// 检查是否已建立安全会话
  bool get hasSecureSession => _sessionKey != null;
}

/// 加密数据结构
class EncryptedData {
  final List<int> ciphertext;
  final List<int> nonce;
  final List<int> mac;

  const EncryptedData({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });

  List<int> toBytes() {
    final result = <int>[];
    result.add(nonce.length);
    result.add(mac.length);
    result.addAll(nonce);
    result.addAll(mac);
    result.addAll(ciphertext);
    return result;
  }

  static EncryptedData fromBytes(List<int> bytes) {
    final nonceLen = bytes[0];
    final macLen = bytes[1];
    final nonce = bytes.sublist(2, 2 + nonceLen);
    final mac = bytes.sublist(2 + nonceLen, 2 + nonceLen + macLen);
    final ciphertext = bytes.sublist(2 + nonceLen + macLen);
    return EncryptedData(nonce: nonce, mac: mac, ciphertext: ciphertext);
  }
}

/// 握手响应数据结构
class HandshakeResponse {
  final List<int> publicKey;
  final int timestamp;
  final List<int>? signature;

  const HandshakeResponse({
    required this.publicKey,
    required this.timestamp,
    this.signature,
  });
}

class _KeyExchangeWorkerInput {
  final List<int> localPrivateKey;
  final List<int> clientEphemeralPubKey;
  final List<int> remoteEphemeralPubKey;
  final List<int> signature;
  final String devicePublicKeyHex;
  final int clientTimestamp;

  const _KeyExchangeWorkerInput({
    required this.localPrivateKey,
    required this.clientEphemeralPubKey,
    required this.remoteEphemeralPubKey,
    required this.signature,
    required this.devicePublicKeyHex,
    required this.clientTimestamp,
  });
}

class _KeyExchangeWorkerResult {
  final List<int> sharedSecret;
  final List<int> sessionKey;
  final int verifyMs;
  final int ecdhMs;
  final int hkdfMs;
  final int totalMs;

  const _KeyExchangeWorkerResult({
    required this.sharedSecret,
    required this.sessionKey,
    required this.verifyMs,
    required this.ecdhMs,
    required this.hkdfMs,
    required this.totalMs,
  });
}

class _EphemeralKeyPairSnapshot {
  final List<int> privateKey;
  final List<int> publicKey;

  const _EphemeralKeyPairSnapshot({
    required this.privateKey,
    required this.publicKey,
  });
}

Future<_EphemeralKeyPairSnapshot> _generateEphemeralKeyPairSnapshot() async {
  final rnd = Random.secure();
  final seed = List<int>.generate(32, (_) => rnd.nextInt(256));
  const x25519 = DartX25519();
  final kp = await x25519.newKeyPairFromSeed(seed);
  final extracted = await kp.extract();
  final pub = await kp.extractPublicKey();
  return _EphemeralKeyPairSnapshot(
    privateKey: extracted.bytes,
    publicKey: pub.bytes,
  );
}

Future<_KeyExchangeWorkerResult> _runKeyExchangeWorker(
  _KeyExchangeWorkerInput input,
) async {
  final totalSw = Stopwatch()..start();
  final verifier = DartEd25519();
  final deviceLongtermPk = SimplePublicKey(
    _hexToBytesWorker(input.devicePublicKeyHex),
    type: KeyPairType.ed25519,
  );
  final message = Uint8List.fromList(
    input.clientEphemeralPubKey + _longToBytesWorker(input.clientTimestamp),
  );
  final verifySw = Stopwatch()..start();
  final ok = await verifier.verify(
    message,
    signature: Signature(input.signature, publicKey: deviceLongtermPk),
  );
  verifySw.stop();
  if (!ok) {
    throw Exception('❌ 设备公钥签名验证失败');
  }

  const x25519 = DartX25519();
  final localKeyPair = SimpleKeyPairData(
    input.localPrivateKey,
    publicKey: SimplePublicKey(
      input.clientEphemeralPubKey,
      type: KeyPairType.x25519,
    ),
    type: KeyPairType.x25519,
  );
  final remoteEphemeralKey = SimplePublicKey(
    input.remoteEphemeralPubKey,
    type: KeyPairType.x25519,
  );
  final ecdhSw = Stopwatch()..start();
  final sharedSecretKey = await x25519.sharedSecretKey(
    keyPair: localKeyPair,
    remotePublicKey: remoteEphemeralKey,
  );
  final sharedSecret = await sharedSecretKey.extractBytes();
  ecdhSw.stop();

  final hkdf = DartHkdf(hmac: Hmac.sha256(), outputLength: 32);
  final hkdfSw = Stopwatch()..start();
  final sessionKeyObject = await hkdf.deriveKey(
    secretKey: SecretKey(sharedSecret),
    info: utf8.encode('BLE_SESSION_KEY_V1'),
    nonce: List<int>.filled(32, 0),
  );
  final sessionKey = await sessionKeyObject.extractBytes();
  hkdfSw.stop();
  totalSw.stop();
  return _KeyExchangeWorkerResult(
    sharedSecret: sharedSecret,
    sessionKey: sessionKey,
    verifyMs: verifySw.elapsedMilliseconds,
    ecdhMs: ecdhSw.elapsedMilliseconds,
    hkdfMs: hkdfSw.elapsedMilliseconds,
    totalMs: totalSw.elapsedMilliseconds,
  );
}

List<int> _longToBytesWorker(int value) {
  final bytes = Uint8List(8);
  bytes[0] = (value >> 56) & 0xFF;
  bytes[1] = (value >> 48) & 0xFF;
  bytes[2] = (value >> 40) & 0xFF;
  bytes[3] = (value >> 32) & 0xFF;
  bytes[4] = (value >> 24) & 0xFF;
  bytes[5] = (value >> 16) & 0xFF;
  bytes[6] = (value >> 8) & 0xFF;
  bytes[7] = value & 0xFF;
  return bytes;
}

List<int> _hexToBytesWorker(String hex) {
  final result = <int>[];
  for (int i = 0; i < hex.length; i += 2) {
    result.add(int.parse(hex.substring(i, i + 2), radix: 16));
  }
  return result;
}
