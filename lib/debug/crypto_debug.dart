import 'dart:convert';
import '../core/log/app_log.dart';

/// 加密调试工具
class CryptoDebug {
  /// 比较两个公钥并输出详细信息
  static void comparePublicKeys({
    required String expectedKey,
    required String actualKey,
    String context = "公钥验证",
  }) {
    AppLog.instance.info('🔍 $context 调试信息:', tag: 'Crypto');
    AppLog.instance.info('   期望公钥: $expectedKey', tag: 'Crypto');
    AppLog.instance.info('   实际公钥: $actualKey', tag: 'Crypto');
    AppLog.instance.info('   长度对比: ${expectedKey.length} vs ${actualKey.length}', tag: 'Crypto');

    if (expectedKey == actualKey) {
      AppLog.instance.info('   ✅ 公钥完全匹配', tag: 'Crypto');
    } else {
      AppLog.instance.warning('   ❌ 公钥不匹配', tag: 'Crypto');

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
        AppLog.instance.info('   首次差异位置: $diffIndex', tag: 'Crypto');
        AppLog.instance.info('   期望字符: "${expectedKey[diffIndex]}"', tag: 'Crypto');
        AppLog.instance.info('   实际字符: "${actualKey[diffIndex]}"', tag: 'Crypto');

        // 显示差异周围的上下文
        final start = (diffIndex - 8).clamp(0, expectedKey.length);
        final end = (diffIndex + 8).clamp(0, expectedKey.length);

        if (start < expectedKey.length && end <= expectedKey.length) {
          AppLog.instance.info('   期望上下文: "${expectedKey.substring(start, end)}"', tag: 'Crypto');
        }
        if (start < actualKey.length && end <= actualKey.length) {
          AppLog.instance.info('   实际上下文: "${actualKey.substring(start, end)}"', tag: 'Crypto');
        }
      }
    }
    AppLog.instance.info('', tag: 'Crypto');
  }

  /// 分析握手数据
  static void analyzeHandshakeData(String jsonData) {
    try {
      final data = jsonDecode(jsonData);
      AppLog.instance.info('🤝 握手数据分析:', tag: 'Crypto');
      AppLog.instance.info('   类型: ${data['type']}', tag: 'Crypto');
      AppLog.instance.info('   版本: ${data['version']}', tag: 'Crypto');
      AppLog.instance.info('   时间戳: ${data['timestamp']}', tag: 'Crypto');

      if (data['public_key'] != null) {
        final publicKey = data['public_key'] as String;
        AppLog.instance.info('   公钥长度: ${publicKey.length}', tag: 'Crypto');
        AppLog.instance.info('   公钥前16字符: ${publicKey.substring(0, 16.clamp(0, publicKey.length))}...', tag: 'Crypto');
        AppLog.instance.info('   公钥后16字符: ...${publicKey.substring((publicKey.length - 16).clamp(0, publicKey.length))}', tag: 'Crypto');
      }

      AppLog.instance.info('', tag: 'Crypto');
    } catch (e) {
      AppLog.instance.error('❌ 握手数据解析失败', tag: 'Crypto', error: e);
      AppLog.instance.info('   原始数据: ${jsonData.substring(0, 100.clamp(0, jsonData.length))}...', tag: 'Crypto');
      AppLog.instance.info('', tag: 'Crypto');
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
    AppLog.instance.info('🔑 设备密钥一致性分析:', tag: 'Crypto');
    AppLog.instance.info('   设备ID: $deviceId', tag: 'Crypto');
    AppLog.instance.info('   公钥: $publicKey', tag: 'Crypto');

    try {
      // 模拟Android端的密钥生成逻辑
      final deviceIdBytes = utf8.encode(deviceId);
      final hash = _sha256(deviceIdBytes);

      final expectedPublicKey = <int>[];
      for (int i = 0; i < 32; i++) {
        expectedPublicKey.add((hash[i] ^ 0x42) & 0xFF);
      }

      final expectedHex = bytesToHex(expectedPublicKey);
      AppLog.instance.info('   期望公钥: $expectedHex', tag: 'Crypto');

      if (publicKey.toLowerCase() == expectedHex.toLowerCase()) {
        AppLog.instance.info('   ✅ 密钥生成算法一致', tag: 'Crypto');
      } else {
        AppLog.instance.warning('   ❌ 密钥生成算法不一致', tag: 'Crypto');
        comparePublicKeys(
          expectedKey: expectedHex,
          actualKey: publicKey.toLowerCase(),
          context: "算法一致性检查",
        );
      }

    } catch (e) {
      AppLog.instance.error('   ❌ 分析失败', tag: 'Crypto', error: e);
    }

    AppLog.instance.info('', tag: 'Crypto');
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
