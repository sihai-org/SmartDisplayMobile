import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// BLE认证加密服务
/// 实现X25519 ECDH密钥交换 + AES-256-GCM加密
class CryptoService {
  // X25519密钥对
  late final X25519 _x25519;
  SimpleKeyPair? _ephemeralKeyPair; // 临时密钥对
  List<int>? _sharedSecret; // 共享密钥
  List<int>? _sessionKey; // 会话密钥
  int? _lastClientTimestamp;

  // AES-GCM加密器
  late final AesGcm _aesGcm;

  CryptoService() {
    _x25519 = X25519();
    _aesGcm = AesGcm.with256bits();
  }

  /// 生成临时密钥对
  Future<void> generateEphemeralKeyPair() async {
    _ephemeralKeyPair = await _x25519.newKeyPair();
    print('🔐 生成临时密钥对完成');
  }

  /// 获取本地公钥 (32字节)
  Future<List<int>> getLocalPublicKey() async {
    if (_ephemeralKeyPair == null) {
      throw Exception('必须先生成临时密钥对');
    }
    final publicKey = await _ephemeralKeyPair!.extractPublicKey();
    return publicKey.bytes;
  }

  /// 执行ECDH密钥交换 + 设备长期公钥认证
  Future<void> performKeyExchange({
    required List<int> remoteEphemeralPubKey,   // 握手响应里的设备临时公钥
    required List<int>? signature,              // 握手响应里的签名
    required String devicePublicKeyHex,         // 二维码里的设备长期公钥（hex）
    required List<int> clientEphemeralPubKey,   // 手机端发出的临时公钥
    required int timestamp,                     // 握手响应里的时间戳
    required int clientTimestamp,   // 👈 改成客户端时间戳
  }) async {
    if (_ephemeralKeyPair == null) {
      throw Exception('必须先生成临时密钥对');
    }

    try {
      print('🔑 开始执行密钥交换 + 公钥认证');

      // 1. 验证设备长期公钥签名
      final deviceLongtermPk = SimplePublicKey(
        _hexToBytes(devicePublicKeyHex),
        type: KeyPairType.ed25519,
      );

      final verifier = Ed25519();
      final message = Uint8List.fromList(
          clientEphemeralPubKey + _longToBytes(clientTimestamp)  // 👈 用自己发出去的时间戳
      );

      if (signature == null) {
        throw Exception('❌ 缺少公钥签名');
      }

      final ok = await verifier.verify(
        message,
        signature: Signature(signature, publicKey: deviceLongtermPk),
      );

      if (!ok) {
        throw Exception('❌ 设备公钥签名验证失败');
      }
      print('✅ 设备公钥签名验证通过');

      // 2. 构建远程 ephemeral 公钥
      final remoteEphemeralKey = SimplePublicKey(
        remoteEphemeralPubKey,
        type: KeyPairType.x25519,
      );

      // 3. 执行 ECDH
      final sharedSecretKey = await _x25519.sharedSecretKey(
        keyPair: _ephemeralKeyPair!,
        remotePublicKey: remoteEphemeralKey,
      );
      _sharedSecret = await sharedSecretKey.extractBytes();
      print('🤝 ECDH密钥交换完成，共享密钥长度: ${_sharedSecret!.length}');

      // 4. 派生会话密钥
      await _deriveSessionKey();
    } catch (e) {
      print('❌ performKeyExchange 失败: $e');
      rethrow;
    }
  }

  /// 辅助：int → 8字节数组 (big endian)
  List<int> _longToBytes(int value) {
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

  /// 使用HKDF派生会话密钥
  Future<void> _deriveSessionKey() async {
    if (_sharedSecret == null) {
      throw Exception('共享密钥未生成');
    }

    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32, // 256位密钥
    );

    final info = utf8.encode('BLE_SESSION_KEY_V1');
    final salt = List<int>.filled(32, 0); // 零盐值

    final sessionKeyObject = await hkdf.deriveKey(
      secretKey: SecretKey(_sharedSecret!),
      info: info,
      nonce: salt,
    );

    _sessionKey = await sessionKeyObject.extractBytes();
    print('🔑 会话密钥派生完成，长度: ${_sessionKey!.length}');
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
    _ephemeralKeyPair = null;
    _sharedSecret = null;
    _sessionKey = null;
    print('🧹 密钥材料已清理');
  }

  /// 获取握手初始化数据 (JSON格式)
  Future<String> getHandshakeInitData() async {
    final publicKey = await getLocalPublicKey();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    _lastClientTimestamp = timestamp;

    final handshakeData = {
      'type': 'handshake_init',
      'public_key': _bytesToHex(publicKey),
      'timestamp': timestamp,
      'version': '1.0',
    };

    return jsonEncode(handshakeData);
  }

  int? get clientTimestamp => _lastClientTimestamp;

  /// 解析握手响应数据
  HandshakeResponse parseHandshakeResponse(String jsonData) {
    final data = jsonDecode(jsonData) as Map<String, dynamic>;
    if (data['type'] != 'handshake_response') {
      throw Exception('无效的握手响应类型');
    }
    return HandshakeResponse(
      publicKey: _hexToBytes(data['public_key']),
      timestamp: data['timestamp'] ?? 0,
      signature: data['signature'] != null ? _hexToBytes(data['signature']) : null,
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
