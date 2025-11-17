import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// 创建设备指纹 (稳定版，不带时间戳)
/// 格式: [版本(1字节)] + [设备ID哈希前6字节] + [校验和(1字节)]
Uint8List createDeviceFingerprint(String deviceId) {
  // Avoid noisy logs in production
  // print("createDeviceFingerprint $deviceId");
  const int version = 1;

  // 1. 用 SHA-256 生成稳定哈希，取前6字节
  final digest = sha256.convert(utf8.encode(deviceId));
  final deviceIdBytes = Uint8List.fromList(digest.bytes.sublist(0, 6));

  // 2. 校验和（version + deviceIdBytes 的逐字节和）
  int checksum = version;
  for (final b in deviceIdBytes) {
    checksum += b;
  }
  final checksumByte = checksum & 0xFF;

  // 3. 组装最终指纹 (共8字节)
  return Uint8List.fromList([version, ...deviceIdBytes, checksumByte]);
}
