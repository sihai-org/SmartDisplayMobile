import 'package:flutter_test/flutter_test.dart';
import '../lib/core/crypto/crypto_service.dart';

void main() {
  group('加密服务测试', () {
    late CryptoService aliceCrypto;
    late CryptoService bobCrypto;

    setUp(() {
      aliceCrypto = CryptoService();
      bobCrypto = CryptoService();
    });

    tearDown(() {
      aliceCrypto.cleanup();
      bobCrypto.cleanup();
    });

    test('X25519密钥交换测试', () async {
      print('🧪 开始X25519密钥交换测试');

      // 1. 双方生成密钥对
      await aliceCrypto.generateEphemeralKeyPair();
      await bobCrypto.generateEphemeralKeyPair();
      
      final alicePublicKey = await aliceCrypto.getLocalPublicKey();
      final bobPublicKey = await bobCrypto.getLocalPublicKey();
      
      print('✅ Alice公钥: ${alicePublicKey.length}字节');
      print('✅ Bob公钥: ${bobPublicKey.length}字节');
      
      expect(alicePublicKey.length, 32);
      expect(bobPublicKey.length, 32);

      // 2. 模拟设备公钥（使用Bob的公钥作为"设备"公钥）
      final devicePublicKeyHex = bobPublicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      
      // 3. Alice执行密钥交换（作为客户端，使用Bob的公钥作为设备公钥验证）
      await aliceCrypto.performKeyExchange(
        remotePublicKeyBytes: bobPublicKey,
        devicePublicKey: devicePublicKeyHex,
      );
      
      // 4. 为了测试Bob端，我们需要用Alice的公钥作为设备公钥（通常这来自QR码）
      final alicePublicKeyHex = alicePublicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await bobCrypto.performKeyExchange(
        remotePublicKeyBytes: alicePublicKey,
        devicePublicKey: alicePublicKeyHex,
      );
      
      print('✅ 密钥交换完成');
      expect(aliceCrypto.hasSecureSession, isTrue);
      expect(bobCrypto.hasSecureSession, isTrue);
    });

    test('端到端加密通信测试', () async {
      print('🧪 开始端到端加密通信测试');

      // 1. 建立安全会话
      await aliceCrypto.generateEphemeralKeyPair();
      await bobCrypto.generateEphemeralKeyPair();
      
      final alicePublicKey = await aliceCrypto.getLocalPublicKey();
      final bobPublicKey = await bobCrypto.getLocalPublicKey();
      final devicePublicKeyHex = bobPublicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      
      await aliceCrypto.performKeyExchange(
        remotePublicKeyBytes: bobPublicKey,
        devicePublicKey: devicePublicKeyHex,
      );
      
      final alicePublicKeyHex2 = alicePublicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await bobCrypto.performKeyExchange(
        remotePublicKeyBytes: alicePublicKey,
        devicePublicKey: alicePublicKeyHex2,
      );

      // 2. Alice加密消息
      const testMessage = '{"ssid":"TestWiFi","password":"TestPassword123"}';
      final encryptedData = await aliceCrypto.encrypt(testMessage);
      
      print('✅ 消息已加密: 密文${encryptedData.ciphertext.length}字节, nonce${encryptedData.nonce.length}字节');
      expect(encryptedData.ciphertext.isNotEmpty, isTrue);
      expect(encryptedData.nonce.length, 12); // GCM标准nonce长度
      expect(encryptedData.mac.length, 16);   // GCM标准MAC长度

      // 3. Bob解密消息
      final decryptedMessage = await bobCrypto.decrypt(encryptedData);
      
      print('✅ 消息解密成功: $decryptedMessage');
      expect(decryptedMessage, testMessage);
    });

    test('序列化和反序列化测试', () async {
      print('🧪 开始序列化测试');

      // 建立会话
      await aliceCrypto.generateEphemeralKeyPair();
      await bobCrypto.generateEphemeralKeyPair();
      
      final alicePublicKey = await aliceCrypto.getLocalPublicKey();
      final bobPublicKey = await bobCrypto.getLocalPublicKey();
      final devicePublicKeyHex = bobPublicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      
      await aliceCrypto.performKeyExchange(
        remotePublicKeyBytes: bobPublicKey,
        devicePublicKey: devicePublicKeyHex,
      );

      // 加密数据
      const testMessage = 'Hello, BLE World!';
      final encrypted = await aliceCrypto.encrypt(testMessage);
      
      // 序列化为字节数组（模拟BLE传输）
      final serializedBytes = encrypted.toBytes();
      print('✅ 序列化后字节长度: ${serializedBytes.length}');
      
      // 反序列化
      final deserializedEncrypted = EncryptedData.fromBytes(serializedBytes);
      
      // 验证数据一致性
      expect(deserializedEncrypted.ciphertext, encrypted.ciphertext);
      expect(deserializedEncrypted.nonce, encrypted.nonce);
      expect(deserializedEncrypted.mac, encrypted.mac);
      
      print('✅ 序列化测试通过');
    });

    test('握手协议JSON测试', () async {
      print('🧪 开始握手协议测试');

      await aliceCrypto.generateEphemeralKeyPair();
      
      // 生成握手初始化数据
      final handshakeInit = await aliceCrypto.getHandshakeInitData();
      print('✅ 握手初始化数据长度: ${handshakeInit.length}');
      
      expect(handshakeInit.contains('handshake_init'), isTrue);
      expect(handshakeInit.contains('public_key'), isTrue);
      expect(handshakeInit.contains('timestamp'), isTrue);
      
      // 模拟服务端响应
      await bobCrypto.generateEphemeralKeyPair();
      final bobPublicKey = await bobCrypto.getLocalPublicKey();
      final responseJson = '''
      {
        "type": "handshake_response",
        "public_key": "${bobPublicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}",
        "timestamp": ${DateTime.now().millisecondsSinceEpoch},
        "version": "1.0"
      }
      ''';
      
      // 解析握手响应
      final response = aliceCrypto.parseHandshakeResponse(responseJson);
      expect(response.publicKey.length, 32);
      expect(response.timestamp, isPositive);
      
      print('✅ 握手协议JSON测试通过');
    });

    test('错误处理测试', () async {
      print('🧪 开始错误处理测试');

      await aliceCrypto.generateEphemeralKeyPair();
      await bobCrypto.generateEphemeralKeyPair();
      
      final alicePublicKey = await aliceCrypto.getLocalPublicKey();
      final bobPublicKey = await bobCrypto.getLocalPublicKey();
      
      // 测试公钥不匹配的情况
      final wrongDevicePublicKey = alicePublicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      
      try {
        await aliceCrypto.performKeyExchange(
          remotePublicKeyBytes: bobPublicKey,
          devicePublicKey: wrongDevicePublicKey, // 错误的设备公钥
        );
        fail('应该抛出异常');
      } catch (e) {
        print('✅ 正确捕获公钥验证失败: $e');
        expect(e.toString().contains('公钥验证失败'), isTrue);
      }
      
      // 测试未建立会话时加密的情况
      final freshCrypto = CryptoService();
      await freshCrypto.generateEphemeralKeyPair();
      
      try {
        await freshCrypto.encrypt('test');
        fail('应该抛出异常');
      } catch (e) {
        print('✅ 正确捕获会话未建立错误: $e');
        expect(e.toString().contains('会话密钥未生成'), isTrue);
      }
      
      freshCrypto.cleanup();
      print('✅ 错误处理测试通过');
    });
  });
}