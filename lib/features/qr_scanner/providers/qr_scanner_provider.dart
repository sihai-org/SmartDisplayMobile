import 'dart:ui' show Rect;
import '../../../core/log/app_log.dart';
import 'package:flutter/foundation.dart';
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
  // 候选框（用于绘制实时引导）
  final Rect? candidateRect;
  // ROI（扫描窗口）
  final Rect? scanWindow;
  // 提示：是否建议开启闪光灯
  final bool suggestTorch;

  const QrScannerState({
    this.status = QrScannerStatus.idle,
    this.qrContent,
    this.errorMessage,
    this.isTorchOn = false,
    this.candidateRect,
    this.scanWindow,
    this.suggestTorch = false,
  });

  QrScannerState copyWith({
    QrScannerStatus? status,
    String? qrContent,
    String? errorMessage,
    bool? isTorchOn,
    Rect? candidateRect,
    Rect? scanWindow,
    bool? suggestTorch,
  }) {
    return QrScannerState(
      status: status ?? this.status,
      qrContent: qrContent ?? this.qrContent,
      errorMessage: errorMessage ?? this.errorMessage,
      isTorchOn: isTorchOn ?? this.isTorchOn,
      candidateRect: candidateRect ?? this.candidateRect,
      scanWindow: scanWindow ?? this.scanWindow,
      suggestTorch: suggestTorch ?? this.suggestTorch,
    );
  }
}

/// QR扫描器状态管理
class QrScannerNotifier extends StateNotifier<QrScannerState> {
  QrScannerNotifier() : super(const QrScannerState());

  MobileScannerController? _controller;
  Rect? _scanWindow;
  final _tracker = _CandidateTracker();
  DateTime? _lastAnyDetectAt;

  void _log(String msg) => AppLog.instance.debug(msg, tag: 'QR');

  /// 初始化控制器 (不更新状态)
  void initializeController() {
    _log('initializeController');
    _controller = MobileScannerController(
      // Use normal detection speed to reduce rapid UI updates
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  /// 初始化扫描器 (包含状态更新)
  void initialize() {
    initializeController();
    if (mounted) {
      _log('initialize -> set status=scanning');
      state = state.copyWith(status: QrScannerStatus.scanning);
    }
  }

  /// 处理扫描结果
  void onDetect(BarcodeCapture capture) {
    _log('onDetect: ----------------------${state.status}');
    if (state.status != QrScannerStatus.scanning) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) {
      _log('onDetect: no barcodes');
      _updateSuggestTorch();
      return;
    }

    _lastAnyDetectAt = DateTime.now();

    // 仅考虑包含内容的 QR
    final candidates = barcodes
        .where((b) => b.format == BarcodeFormat.qrCode && (b.rawValue?.isNotEmpty ?? false))
        .toList();
    _log('onDetect: barcodes=${barcodes.length}, qrCandidates=${candidates.length}');
    if (candidates.isEmpty) return;

    // 选择首个候选（ROI 已在控件层限定）
    final best = candidates.first;

    // 更新候选可视化（此版本不依赖 boundingBox，置空即可）
    if (mounted && state.candidateRect != null) {
      state = state.copyWith(candidateRect: null);
    }

    final stable = _tracker.update(best.rawValue!);
    if (!stable.isStable) {
      _log('onDetect: candidate unstable hits=${stable.hitCount} elapsedMs=${stable.elapsedMs}');
      return;
    }

    // 达到稳定阈值，判定成功
    _log('onDetect: STABLE success, contentLen=${best.rawValue?.length ?? 0}');
    QrScannerService.vibrate();
    if (mounted) {
      state = state.copyWith(
        status: QrScannerStatus.success,
        qrContent: best.rawValue,
        errorMessage: null,
      );
    }
  }

  /// 开始扫描
  void startScanning() {
    _log('startScanning');
    if (mounted) {
      state = state.copyWith(
        status: QrScannerStatus.scanning,
        errorMessage: null,
        qrContent: null,
        suggestTorch: false,
        candidateRect: null,
      );
    }
    _tracker.reset();
    _lastAnyDetectAt = null;
  }

  /// 停止扫描
  void stopScanning() {
    _log('stopScanning');
    if (mounted) {
      state = state.copyWith(status: QrScannerStatus.idle, candidateRect: null);
    }
  }

  /// 切换闪光灯
  void toggleTorch() {
    _controller?.toggleTorch();
    // 获取实际的闪光灯状态
    final currentTorchState = _controller?.torchState.value == TorchState.on;
    _log('toggleTorch -> wasOn=$currentTorchState');
    if (mounted) {
      state = state.copyWith(isTorchOn: !currentTorchState, suggestTorch: false);
    }
  }

  /// 更新扫描窗口（ROI），用于限定解码区域与引导绘制
  void updateScanWindow(Rect rect) {
    _scanWindow = rect;
    _log('updateScanWindow: ${rect.left},${rect.top},${rect.width}x${rect.height}');
    if (mounted) {
      state = state.copyWith(scanWindow: rect);
    }
  }

  /// 当前控制器（供页面访问）
  MobileScannerController? get controller => _controller;

  /// 自动亮度提示（简单：长时间未识别且未开灯）
  void _updateSuggestTorch() {
    if (!mounted) return;
    if (state.isTorchOn) return;
    final last = _lastAnyDetectAt;
    final now = DateTime.now();
    if (last == null || now.difference(last).inSeconds > 2) {
      // 2 秒内无稳定候选时提示
      _log('suggestTorch: true');
      state = state.copyWith(suggestTorch: true);
    }
  }

  // 已移除：从相册扫描图片相关方法（不再使用相册权限）

  /// 重置状态
  void reset() {
    // 清理现有控制器
    _log('reset: dispose controller and clear state');
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
    _log('dispose: controller cleanup');
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  /// 获取控制器（保持接口不变）
  @override
  String toString() => 'QrScannerNotifier(status: ${state.status}, torch: ${state.isTorchOn})';
}

class _CandidateUpdateResult {
  final bool isStable;
  final int hitCount;
  final int elapsedMs;
  const _CandidateUpdateResult(this.isStable, this.hitCount, this.elapsedMs);
}

/// 候选追踪：多帧一致性与位置稳定
class _CandidateTracker {
  String? _lastValue;
  int _hits = 0;
  DateTime? _firstAt;

  static const int _minHits = 1;
  static const Duration _window = Duration(milliseconds: 700);

  _CandidateUpdateResult update(String value) {
    final now = DateTime.now();
    if (_firstAt == null) _firstAt = now;

    if (_lastValue == value) {
      _hits += 1;
    } else {
      _hits = 1;
      _firstAt = now;
    }

    _lastValue = value;
    final inWindow = now.difference(_firstAt!) <= _window;
    final ok = _hits >= _minHits && inWindow;
    final elapsed = now.difference(_firstAt!).inMilliseconds;
    return _CandidateUpdateResult(ok, _hits, elapsed);
  }

  void reset() {
    _lastValue = null;
    _hits = 0;
    _firstAt = null;
  }
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
