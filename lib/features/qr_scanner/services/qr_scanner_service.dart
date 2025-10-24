import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import '../models/device_qr_data.dart';

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
      if (deviceData.deviceId.isEmpty) {
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

  /// 从相册选择图片并扫描QR码
  static Future<QrScanResult> scanQrFromImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      
      // 选择图片
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (image == null) {
        return const QrScanResult.cancelled();
      }

      // TODO: 实现图片QR码扫描
      // 目前mobile_scanner包对图片扫描的支持有限
      // 可以考虑集成其他图片QR识别库
      
      return const QrScanResult.error('图片扫描功能正在开发中，请使用摄像头扫描QR码');
      
    } catch (e) {
      return QrScanResult.error('选择图片时发生错误: $e');
    }
  }

  /// 简化版：从相册选择图片并返回原始二维码内容
  static Future<String> scanQrFromImageSimple() async {
    try {
      final ImagePicker picker = ImagePicker();
      
      // 选择图片
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      
      if (image == null) {
        return ''; // 用户取消选择
      }

      // TODO: 实现图片QR码扫描，暂时返回空字符串
      return '';
      
    } catch (e) {
      throw Exception('选择图片时发生错误: $e');
    }
  }
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
