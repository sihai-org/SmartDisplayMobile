import 'dart:convert';

/// 加密调试工具
class CryptoDebug {
  /// 比较两个公钥并输出详细信息
  static void comparePublicKeys({
    required String expectedKey,
    required String actualKey,
    String context = "公钥验证",
  }) {
    print('🔍 $context 调试信息:');
    print('   期望公钥: $expectedKey');
    print('   实际公钥: $actualKey');
    print('   长度对比: ${expectedKey.length} vs ${actualKey.length}');

    if (expectedKey == actualKey) {
      print('   ✅ 公钥完全匹配');
    } else {
      print('   ❌ 公钥不匹配');

      // 查找第一个不同的字符位置
      int diffIndex = -1;
      final minLength = expectedKey.length < actualKey.length
          ? expectedKey.length
          : actualKey.length;

      for (int i = 0; i < minLength; i++) {
        if (expectedKey[i] != actualKey[i]) {
          diffIndex = i;
          break;
        }
      }

      if (diffIndex >= 0) {
        print('   首次差异位置: $diffIndex');
        print('   期望字符: "${expectedKey[diffIndex]}"');
        print('   实际字符: "${actualKey[diffIndex]}"');

        // 显示差异周围的上下文
        final start = (diffIndex - 8).clamp(0, expectedKey.length);
        final end = (diffIndex + 8).clamp(0, expectedKey.length);

        if (start < expectedKey.length && end <= expectedKey.length) {
          print('   期望上下文: "${expectedKey.substring(start, end)}"');
        }
        if (start < actualKey.length && end <= actualKey.length) {
          print('   实际上下文: "${actualKey.substring(start, end)}"');
        }
      }
    }
    print('');
  }

  /// 分析握手数据
  static void analyzeHandshakeData(String jsonData) {
    try {
      final data = jsonDecode(jsonData);
      print('🤝 握手数据分析:');
      print('   类型: ${data['type']}');
      print('   版本: ${data['version']}');
      print('   时间戳: ${data['timestamp']}');

      if (data['public_key'] != null) {
        final publicKey = data['public_key'] as String;
        print('   公钥长度: ${publicKey.length}');
        print('   公钥前16字符: ${publicKey.substring(0, 16.clamp(0, publicKey.length))}...');
        print('   公钥后16字符: ...${publicKey.substring((publicKey.length - 16).clamp(0, publicKey.length))}');
      }

      print('');
    } catch (e) {
      print('❌ 握手数据解析失败: $e');
      print('   原始数据: ${jsonData.substring(0, 100.clamp(0, jsonData.length))}...');
      print('');
    }
  }

  /// 十六进制字符串转字节数组（用于调试）
  static List<int> hexToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  /// 字节数组转十六进制字符串（用于调试）
  static String bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 分析设备ID和公钥的一致性
  static void analyzeDeviceKeyConsistency({
    required String deviceId,
    required String publicKey,
  }) {
    print('🔑 设备密钥一致性分析:');
    print('   设备ID: $deviceId');
    print('   公钥: $publicKey');

    try {
      // 模拟Android端的密钥生成逻辑
      final deviceIdBytes = utf8.encode(deviceId);
      final hash = _sha256(deviceIdBytes);

      final expectedPublicKey = <int>[];
      for (int i = 0; i < 32; i++) {
        expectedPublicKey.add((hash[i] ^ 0x42) & 0xFF);
      }

      final expectedHex = bytesToHex(expectedPublicKey);
      print('   期望公钥: $expectedHex');

      if (publicKey.toLowerCase() == expectedHex.toLowerCase()) {
        print('   ✅ 密钥生成算法一致');
      } else {
        print('   ❌ 密钥生成算法不一致');
        comparePublicKeys(
          expectedKey: expectedHex,
          actualKey: publicKey.toLowerCase(),
          context: "算法一致性检查",
        );
      }

    } catch (e) {
      print('   ❌ 分析失败: $e');
    }

    print('');
  }

  /// 简化的SHA256实现（仅用于调试对比）
  static List<int> _sha256(List<int> data) {
    // 这里应该使用真正的SHA256，这只是占位符
    // 实际实现中应该导入crypto包
    final result = <int>[];
    for (int i = 0; i < 32; i++) {
      int val = 0;
      for (int j = 0; j < data.length; j++) {
        val ^= data[j] + i + j * 17;
      }
      result.add(val & 0xFF);
    }
    return result;
  }
}