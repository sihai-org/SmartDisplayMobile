import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart'; // HapticFeedback
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import '../../core/l10n/l10n_extensions.dart';
import 'dart:ui' show Rect, Size;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/device_entry_coordinator.dart';
import '../../core/log/app_log.dart';

class QrScannerPage extends ConsumerStatefulWidget {
  const QrScannerPage({super.key});

  @override
  ConsumerState<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends ConsumerState<QrScannerPage> {
  // 新增：音频播放器（低延迟、可复用）
  late final AudioPlayer _beepPlayer;
  bool _beepPlayedForThisSuccess = false; // 防二次触发（例如重复状态回调）


  // ✅ 新增：本地相机&扫描状态
  late final MobileScannerController _controller;
  QrScannerStatus _status = QrScannerStatus.idle;
  String? _qrContent;
  bool _isTorchOn = false;
  bool _suggestTorch = false;
  Rect? _candidateRect;
  final _tracker = _CandidateTracker();
  DateTime? _lastAnyDetectAt;

  @override
  void initState() {
    super.initState();

    // 初始化播放器
    _beepPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop); // 播放完停止（不循环）

    // ✅ 初始化相机控制器（和页面同生共死）
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
      formats: const [BarcodeFormat.qrCode],
    );

    AppLog.instance.debug('[QrScannerPage] initState -> create controller + startScanning', tag: 'QR');

    // 首帧后开始扫描
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startScanning();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _beepPlayer.dispose();
    super.dispose();
  }

  // 新增：播放提示音（失败时不抛异常）
  Future<void> _playSuccessBeep() async {
    try {
      // 保守一点：先停掉上一次，避免状态乱
      await _beepPlayer.stop();
      await _beepPlayer.play(AssetSource('sounds/scan_success.mp3'));
    } catch (e) {
      debugPrint('play beep error: $e');
    }
  }

  void _startScanning() {
    AppLog.instance.debug('[QrScannerPage] startScanning', tag: 'QR');
    setState(() {
      _status = QrScannerStatus.scanning;
      _qrContent = null;
      _suggestTorch = false;
      _candidateRect = null;
    });
    _tracker.reset();
    _lastAnyDetectAt = null;
    _beepPlayedForThisSuccess = false;
  }

  void _stopScanning() {
    AppLog.instance.debug('[QrScannerPage] stopScanning', tag: 'QR');

    if (_status == QrScannerStatus.scanning) {
      _controller.stop();
    }

    if (!mounted) return;
    setState(() {
      _status = QrScannerStatus.idle;
      _candidateRect = null;
    });
  }

  void _toggleTorch() {
    _controller.toggleTorch();
    final currentTorchState = _controller.torchState.value == TorchState.on;
    AppLog.instance.debug('[QrScannerPage] toggleTorch -> isOn=$currentTorchState', tag: 'QR');
    setState(() {
      _isTorchOn = currentTorchState;
      _suggestTorch = false;
    });
  }

  void _updateSuggestTorch() {
    if (_isTorchOn) return;
    final last = _lastAnyDetectAt;
    final now = DateTime.now();
    if (last == null || now.difference(last).inSeconds > 2) {
      AppLog.instance.debug('[QrScannerPage] suggestTorch: true', tag: 'QR');
      setState(() {
        _suggestTorch = true;
      });
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    AppLog.instance.debug('[QrScannerPage] onDetect: status=$_status', tag: 'QR');

    if (_status != QrScannerStatus.scanning) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) {
      AppLog.instance.debug('[QrScannerPage] onDetect: no barcodes', tag: 'QR');
      _updateSuggestTorch();
      return;
    }

    _lastAnyDetectAt = DateTime.now();

    final candidates = barcodes
        .where((b) => b.format == BarcodeFormat.qrCode && (b.rawValue?.isNotEmpty ?? false))
        .toList();
    AppLog.instance.debug(
      '[QrScannerPage] onDetect: barcodes=${barcodes.length}, qrCandidates=${candidates.length}',
      tag: 'QR',
    );
    if (candidates.isEmpty) return;

    final best = candidates.first;

    if (_candidateRect != null) {
      if (!mounted) return;
      setState(() {
        _candidateRect = null;
      });
    }

    final stable = _tracker.update(best.rawValue!);
    if (!stable.isStable) {
      AppLog.instance.debug(
        '[QrScannerPage] onDetect: candidate unstable hits=${stable.hitCount} elapsedMs=${stable.elapsedMs}',
        tag: 'QR',
      );
      return;
    }

    // 稳定成功
    AppLog.instance.info('[QrScannerPage] onDetect: STABLE success, contentLen=${best.rawValue?.length ?? 0}', tag: 'QR');

    if (_beepPlayedForThisSuccess) return;
    _beepPlayedForThisSuccess = true;

    // 提示音
    unawaited(_playSuccessBeep());

    if (!mounted) return;
    setState(() {
      _status = QrScannerStatus.success;
      _qrContent = best.rawValue;
    });

    // 导航：和之前 ref.listen 中的逻辑类似
    Fluttertoast.showToast(msg: "扫描成功，跳转中...");

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _qrContent == null) return;

      _stopScanning();

      // 这里仍然可以用 ref，因为我们保留了 ConsumerState
      await DeviceEntryCoordinator.handle(context, ref, _qrContent!);
    });
  }


  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _stopScanning();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
      appBar: AppBar(
          title: Text(
            context.l10n.qr_scanner_title,
            // 明确指定白色标题，避免被全局 AppBarTheme 覆盖
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
          ),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          // 确保状态栏图标为浅色（适配黑色背景）
          systemOverlayStyle: SystemUiOverlayStyle.light,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _stopScanning();
              // 返回主页
              context.go(AppRoutes.home);
            },
          ),
          actions: [
            // 顶部右侧闪光灯按钮暂时移除（点击无效问题）
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final double boxSize = 250;
            final double left = (constraints.maxWidth - boxSize) / 2;
            final double top = (constraints.maxHeight - boxSize) / 2;
            final Rect scanRect = Rect.fromLTWH(left, top, boxSize, boxSize);

            // 直接将 ROI 传给 MobileScanner，避免在 build 周期修改 Provider

            return Stack(
              children: [
                // 相机预览
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  scanWindow: scanRect,
                  errorBuilder: (context, error, child) {
                    AppLog.instance.error('[QrScannerPage] MobileScanner error: $error', tag: 'QR');
                    return const Center(
                      child: Icon(Icons.error, color: Colors.red, size: 48),
                    );
                  },
                ),

                // 扫描框覆盖层（ROI 镂空 + 候选框）
                _buildScannerOverlay(scanRect: scanRect, candidate: _candidateRect),

                // 提示开启闪光灯
                if (_suggestTorch && !_isTorchOn)
                  Positioned(
                    bottom: 130,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.light_mode, color: Colors.yellow, size: 16),
                            const SizedBox(width: 6),
                            Text(context.l10n.dark_env_hint, style: const TextStyle(color: Colors.white, fontSize: 12)),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _toggleTorch,
                              child: Text(context.l10n.turn_on, style: const TextStyle(color: Colors.yellow)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 已按需求移除上下方的文案提示（状态指示器与底部提示信息）
              ],
            );
          },
        ),
      ),
    );
  }

  /// 构建扫描框覆盖层（含 ROI 镂空与候选框）
  Widget _buildScannerOverlay({required Rect scanRect, Rect? candidate}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // 半透明遮罩 + ROI 镂空
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _OverlayPainter(scanRect: scanRect),
            ),

            // 扫描框四角装饰
            Positioned(
              left: scanRect.left,
              top: scanRect.top,
              child: SizedBox(
                width: scanRect.width,
                height: scanRect.height,
                child: Stack(children: _buildCornerDecorations()),
              ),
            ),

            // 关闭候选框高亮，避免扫描时绿色闪烁
          ],
        );
      },
    );
  }

  /// 构建四个角的装饰
  List<Widget> _buildCornerDecorations() {
    const cornerSize = 20.0;
    const cornerWidth = 3.0;
    // Use neutral color to avoid green flicker perception
    const color = Colors.white;

    return [
      // 左上角
      Positioned(
        top: -1,
        left: -1,
        child: Container(
          width: cornerSize,
          height: cornerSize,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: color, width: cornerWidth),
              left: BorderSide(color: color, width: cornerWidth),
            ),
          ),
        ),
      ),
      // 右上角
      Positioned(
        top: -1,
        right: -1,
        child: Container(
          width: cornerSize,
          height: cornerSize,
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: color, width: cornerWidth),
              right: BorderSide(color: color, width: cornerWidth),
            ),
          ),
        ),
      ),
      // 左下角
      Positioned(
        bottom: -1,
        left: -1,
        child: Container(
          width: cornerSize,
          height: cornerSize,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: color, width: cornerWidth),
              left: BorderSide(color: color, width: cornerWidth),
            ),
          ),
        ),
      ),
      // 右下角
      Positioned(
        bottom: -1,
        right: -1,
        child: Container(
          width: cornerSize,
          height: cornerSize,
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: color, width: cornerWidth),
              right: BorderSide(color: color, width: cornerWidth),
            ),
          ),
        ),
      ),
    ];
  }
}

/// 遮罩绘制：全屏半透明 + ROI 镂空
class _OverlayPainter extends CustomPainter {
  final Rect scanRect;
  _OverlayPainter({required this.scanRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x88000000);
    final bg = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(16)));
    final overlay = Path.combine(PathOperation.difference, bg, hole);
    canvas.drawPath(overlay, paint);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) => oldDelegate.scanRect != scanRect;
}

/// QR扫描状态
enum QrScannerStatus {
  idle,
  scanning,
  processing,
  success,
  error,
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
