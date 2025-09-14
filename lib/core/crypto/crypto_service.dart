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

  /// 执行ECDH密钥交换并派生会话密钥
  Future<void> performKeyExchange({
    required List<int> remotePublicKeyBytes,
    required String devicePublicKey, // QR码中的设备公钥，用于验证
  }) async {
    if (_ephemeralKeyPair == null) {
      throw Exception('必须先生成临时密钥对');
    }

    try {
      // 验证远程公钥是否与QR码中的公钥匹配
      final remotePublicKeyHex = _bytesToHex(remotePublicKeyBytes);
      print('🔍 公钥验证调试:');
      print('   QR码公钥: ${devicePublicKey.toLowerCase()}');
      print('   远程公钥: ${remotePublicKeyHex.toLowerCase()}');
      print('   长度对比: ${devicePublicKey.length} vs ${remotePublicKeyHex.length}');

      if (remotePublicKeyHex.toLowerCase() != devicePublicKey.toLowerCase()) {
        // 显示详细差异信息
        int diffCount = 0;
        for (int i = 0; i < devicePublicKey.length && i < remotePublicKeyHex.length; i++) {
          if (devicePublicKey[i].toLowerCase() != remotePublicKeyHex[i].toLowerCase()) {
            if (diffCount < 5) { // 只显示前5个差异
              print('   差异位置$i: "${devicePublicKey[i]}" vs "${remotePublicKeyHex[i]}"');
            }
            diffCount++;
          }
        }
        print('   总计${diffCount}个字符不匹配');
        throw Exception('设备公钥验证失败: 远程公钥与QR码不匹配');
      }
      print('✅ 设备公钥验证通过');

      // 构建远程公钥对象
      final remotePublicKey = SimplePublicKey(
        remotePublicKeyBytes,
        type: KeyPairType.x25519,
      );

      // 执行ECDH计算共享密钥
      final sharedSecretKey = await _x25519.sharedSecretKey(
        keyPair: _ephemeralKeyPair!,
        remotePublicKey: remotePublicKey,
      );
      
      _sharedSecret = await sharedSecretKey.extractBytes();
      print('🤝 ECDH密钥交换完成，共享密钥长度: ${_sharedSecret!.length}');

      // 使用HKDF派生会话密钥
      await _deriveSessionKey();
      
    } catch (e) {
      print('❌ 密钥交换失败: $e');
      rethrow;
    }
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

    // 使用固定的信息字符串来派生会话密钥
    final info = utf8.encode('BLE_SESSION_KEY_V1');
    final salt = List<int>.filled(32, 0); // 零盐值（简化实现）

    final sessionKeyObject = await hkdf.deriveKey(
      secretKey: SecretKey(_sharedSecret!),
      info: info,
      nonce: salt, // cryptography包使用nonce而不是salt参数
    );

    _sessionKey = await sessionKeyObject.extractBytes();
    print('🔑 会话密钥派生完成，长度: ${_sessionKey!.length}');
  }

  /// 加密数据 (AES-256-GCM)
  Future<EncryptedData> encrypt(String plaintext) async {
    if (_sessionKey == null) {
      throw Exception('会话密钥未生成，无法加密');
    }

    try {
      final plaintextBytes = utf8.encode(plaintext);
      final secretKey = SecretKey(_sessionKey!);
      
      // 生成随机nonce (96位/12字节 for GCM)
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
    } catch (e) {
      print('❌ 加密失败: $e');
      rethrow;
    }
  }

  /// 解密数据 (AES-256-GCM)
  Future<String> decrypt(EncryptedData encryptedData) async {
    if (_sessionKey == null) {
      throw Exception('会话密钥未生成，无法解密');
    }

    try {
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
    } catch (e) {
      print('❌ 解密失败: $e');
      rethrow;
    }
  }

  /// 清理密钥材料
  void cleanup() {
    _ephemeralKeyPair = null;
    // 不需要手动清理SensitiveBytes，框架会自动处理
    _sharedSecret = null;
    _sessionKey = null;
    print('🧹 密钥材料已清理');
  }

  /// 获取握手初始化数据 (JSON格式)
  Future<String> getHandshakeInitData() async {
    final publicKey = await getLocalPublicKey();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    final handshakeData = {
      'type': 'handshake_init',
      'public_key': _bytesToHex(publicKey),
      'timestamp': timestamp,
      'version': '1.0',
    };
    
    return jsonEncode(handshakeData);
  }

  /// 解析握手响应数据
  HandshakeResponse parseHandshakeResponse(String jsonData) {
    try {
      final data = jsonDecode(jsonData) as Map<String, dynamic>;
      
      if (data['type'] != 'handshake_response') {
        throw Exception('无效的握手响应类型');
      }
      
      return HandshakeResponse(
        publicKey: _hexToBytes(data['public_key']),
        timestamp: data['timestamp'] ?? 0,
        signature: data['signature'] != null ? _hexToBytes(data['signature']) : null,
      );
    } catch (e) {
      throw Exception('解析握手响应失败: $e');
    }
  }

  // 工具方法
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

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

  /// 序列化为字节数组 (用于BLE传输)
  List<int> toBytes() {
    // 格式: [nonce_len(1)] + [mac_len(1)] + [nonce] + [mac] + [ciphertext]
    final result = <int>[];
    result.add(nonce.length);
    result.add(mac.length);
    result.addAll(nonce);
    result.addAll(mac);
    result.addAll(ciphertext);
    return result;
  }

  /// 从字节数组反序列化
  static EncryptedData fromBytes(List<int> bytes) {
    if (bytes.length < 2) {
      throw Exception('数据太短，无法解析');
    }
    
    final nonceLen = bytes[0];
    final macLen = bytes[1];
    
    if (bytes.length < 2 + nonceLen + macLen) {
      throw Exception('数据长度不足');
    }
    
    final nonce = bytes.sublist(2, 2 + nonceLen);
    final mac = bytes.sublist(2 + nonceLen, 2 + nonceLen + macLen);
    final ciphertext = bytes.sublist(2 + nonceLen + macLen);
    
    return EncryptedData(
      nonce: nonce,
      mac: mac,
      ciphertext: ciphertext,
    );
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