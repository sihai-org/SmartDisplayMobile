import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/qr_scanner_service.dart';

/// QR扫描状态
enum QrScannerStatus {
  idle,
  scanning,
  processing,
  success,
  error,
}

/// QR扫描状态数据
class QrScannerState {
  final QrScannerStatus status;
  final String? qrContent; // 简化：只存储二维码内容
  final String? errorMessage;
  final bool isTorchOn;

  const QrScannerState({
    this.status = QrScannerStatus.idle,
    this.qrContent,
    this.errorMessage,
    this.isTorchOn = false,
  });

  QrScannerState copyWith({
    QrScannerStatus? status,
    String? qrContent,
    String? errorMessage,
    bool? isTorchOn,
  }) {
    return QrScannerState(
      status: status ?? this.status,
      qrContent: qrContent ?? this.qrContent,
      errorMessage: errorMessage ?? this.errorMessage,
      isTorchOn: isTorchOn ?? this.isTorchOn,
    );
  }
}

/// QR扫描器状态管理
class QrScannerNotifier extends StateNotifier<QrScannerState> {
  QrScannerNotifier() : super(const QrScannerState());

  MobileScannerController? _controller;

  /// 初始化控制器 (不更新状态)
  void initializeController() {
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  /// 初始化扫描器 (包含状态更新)
  void initialize() {
    initializeController();
    if (mounted) {
      state = state.copyWith(status: QrScannerStatus.scanning);
    }
  }

  /// 处理扫描结果
  void onDetect(BarcodeCapture capture) {
    if (state.status != QrScannerStatus.scanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    // 振动反馈
    QrScannerService.vibrate();

    // 简化：直接显示二维码内容
    if (mounted) {
      state = state.copyWith(
        status: QrScannerStatus.success,
        qrContent: code,
        errorMessage: null,
      );
    }
  }

  /// 开始扫描
  void startScanning() {
    if (mounted) {
      state = state.copyWith(
        status: QrScannerStatus.scanning,
        errorMessage: null,
        qrContent: null,
      );
    }
  }

  /// 停止扫描
  void stopScanning() {
    if (mounted) {
      state = state.copyWith(status: QrScannerStatus.idle);
    }
  }

  /// 切换闪光灯
  void toggleTorch() {
    _controller?.toggleTorch();
    // 获取实际的闪光灯状态
    final currentTorchState = _controller?.torchState.value == TorchState.on;
    if (mounted) {
      state = state.copyWith(isTorchOn: !currentTorchState);
    }
  }

  /// 从相册扫描图片
  Future<void> scanFromImage() async {
    // 设置为处理状态
    if (mounted) {
      state = state.copyWith(status: QrScannerStatus.processing);
    }

    try {
      // 调用服务扫描图片（简化版）
      final result = await QrScannerService.scanQrFromImageSimple();
      
      if (result.isNotEmpty) {
        // 振动反馈
        QrScannerService.vibrate();
        
        if (mounted) {
          state = state.copyWith(
            status: QrScannerStatus.success,
            qrContent: result,
            errorMessage: null,
          );
        }
      } else {
        if (mounted) {
          state = state.copyWith(status: QrScannerStatus.scanning);
        }
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          status: QrScannerStatus.error,
          errorMessage: '扫描图片时发生错误: $e',
        );
      }
      // 2秒后重新开始扫描
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          startScanning();
        }
      });
    }
  }

  /// 重置状态
  void reset() {
    // 清理现有控制器
    _controller?.dispose();
    _controller = null;
    // 重置状态 (只有在未销毁时才更新状态)
    if (mounted) {
      state = const QrScannerState();
    }
  }

  /// 释放资源
  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  /// 获取控制器
  MobileScannerController? get controller => _controller;
}

/// QR扫描器Provider
final qrScannerProvider = StateNotifierProvider<QrScannerNotifier, QrScannerState>((ref) {
  final notifier = QrScannerNotifier();
  
  // 当Provider被销毁时自动释放资源
  ref.onDispose(() {
    notifier.dispose();
  });
  
  return notifier;
});