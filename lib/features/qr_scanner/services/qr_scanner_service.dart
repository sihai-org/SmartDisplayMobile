import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/models/device_qr_data.dart';

/// QR码扫描服务
class QrScannerService {

  /// 解析QR码数据
  static QrScanResult parseQrCode(String rawData) {
    try {
      // 尝试解析JSON格式的QR码
      final raw = jsonDecode(rawData);
      if (raw is! Map<String, dynamic>) {
        return const QrScanResult.error('QR码格式不正确：必须为JSON对象');
      }

      final Map<String, dynamic> jsonData = Map<String, dynamic>.from(raw);

      // 验证必需字段（不再强制 bleAddress）
      if (!jsonData.containsKey('deviceId') ||
          !jsonData.containsKey('deviceName') ||
          !jsonData.containsKey('publicKey')) {
        return const QrScanResult.error('QR码格式不正确：缺少必需字段');
      }

      // 兼容：若缺少 bleAddress，则置为空字符串
      jsonData.putIfAbsent('bleAddress', () => '');

      // 创建设备数据对象
      final deviceData = DeviceQrData.fromJson(jsonData);

      // 基本数据验证（仅关键标识）
      if (deviceData.bleDeviceId.isEmpty) {
        return const QrScanResult.error('设备ID不能为空');
      }
      if (deviceData.publicKey.isEmpty) {
        return const QrScanResult.error('设备公钥不能为空');
      }

      // 不再校验 BLE 地址是否存在或格式
      return QrScanResult.success(deviceData);
    } on FormatException catch (e) {
      return QrScanResult.error('QR码格式错误: ${e.message}');
    } catch (e) {
      return QrScanResult.error('解析QR码时发生错误: $e');
    }
  }

  /// 振动反馈
  static Future<void> vibrate() async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (e) {
      // 忽略振动错误，某些设备可能不支持
    }
  }

  /// 检查相机权限
  static Future<bool> checkCameraPermission() async {
    try {
      // mobile_scanner会自动处理权限请求
      return true;
    } catch (e) {
      return false;
    }
  }

  // 已移除：相册图片选择与扫描相关逻辑（不再使用相册权限）
}

/// QR码扫描器控制器扩展
extension MobileScannerControllerExt on MobileScannerController {
  /// 切换闪光灯
  Future<void> toggleTorchLight() async {
    await toggleTorch();
  }

  /// 获取当前闪光灯状态
  bool get isTorchOn => torchState.value == TorchState.on;
}
