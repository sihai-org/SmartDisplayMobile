import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';

Uint8List createDeviceFingerprint(String deviceId, {int? timestamp}) {
  const int version = 1;

  // 1. 用 SHA-256 生成稳定哈希
  final digest = sha256.convert(utf8.encode(deviceId));
  final deviceIdBytes = Uint8List.fromList(digest.bytes.sublist(0, 6));

  // 2. 时间戳（秒级，取后4字节）
  final ts = timestamp ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
  final tsBytes = Uint8List(4);
  tsBytes[0] = (ts >> 24) & 0xFF;
  tsBytes[1] = (ts >> 16) & 0xFF;
  tsBytes[2] = (ts >> 8) & 0xFF;
  tsBytes[3] = ts & 0xFF;

  // 3. 校验和（version + deviceIdBytes + tsBytes 的逐字节和）
  int checksum = version;
  for (final b in deviceIdBytes) checksum += b;
  for (final b in tsBytes) checksum += b;
  final checksumByte = checksum & 0xFF;

  // 4. 组装最终指纹
  return Uint8List.fromList([version, ...deviceIdBytes, ...tsBytes, checksumByte]);
}
