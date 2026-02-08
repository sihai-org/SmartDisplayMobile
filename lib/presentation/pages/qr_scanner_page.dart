import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart'; // HapticFeedback
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import '../../core/l10n/l10n_extensions.dart';
import 'dart:ui' show Rect, Size;

// 替换：不再使用 mobile_scanner
// import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import '../../core/router/app_router.dart';
import '../../core/utils/device_entry_coordinator.dart';
import '../../core/log/app_log.dart';

enum QrScannerSuccessAction {
  /// 保持现有链路：扫描成功后进入设备绑定/连接流程
  deviceEntry,

  /// 扫描成功后直接 pop 返回扫码结果（不触发现有链路）
  popResult,
}

class QrScannerPage extends ConsumerStatefulWidget {
  const QrScannerPage({
    super.key,
    this.successAction = QrScannerSuccessAction.deviceEntry,
  });

  final QrScannerSuccessAction successAction;

  @override
  ConsumerState<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends ConsumerState<QrScannerPage> {
  // 音频播放器（低延迟、可复用）
  late final AudioPlayer _beepPlayer;
  late final Future<void> _beepReady;
  bool _beepPlayedForThisSuccess = false; // 防二次触发（例如重复状态回调）

  // ZXing 相机控制器（支持 Android + iOS）
  QRViewController? _controller;
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'QR');

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
    _beepPlayer = AudioPlayer(
      playerId: 'qr_beep',
    );
    _beepPlayer.setPlayerMode(PlayerMode.lowLatency);
    _beepReady = _warmUpBeepPlayer();

    AppLog.instance.debug(
      '[QrScannerPage] initState -> wait for QRView create',
      tag: 'QR',
    );

    // 首帧后标记为可扫描（控制器会在 onQRViewCreated 里赋值）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startScanning();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _beepPlayer.dispose();
    super.dispose();
  }

  // 播放提示音（失败时不抛异常）
  Future<void> _playSuccessBeep() async {
    try {
      await _beepReady; // 确保已预热，避免第一次播放丢失
      await _beepPlayer.seek(Duration.zero);
      await _beepPlayer.resume();
    } catch (e) {
      debugPrint('play beep error: $e');
    }
  }

  // 预热播放器，避免首次播放冷启动没有声音
  Future<void> _warmUpBeepPlayer() async {
    try {
      await _beepPlayer.setReleaseMode(ReleaseMode.stop);
      await _beepPlayer.setSourceAsset('sounds/scan_success.mp3');
      await _beepPlayer.setVolume(0); // 静音播放以拉起音频 Session
      await _beepPlayer.resume();
      await _beepPlayer.pause();
      await _beepPlayer.seek(Duration.zero);
      await _beepPlayer.setVolume(1);
    } catch (e) {
      debugPrint('warm up beep error: $e');
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

    // ZXing：恢复相机预览
    _controller?.resumeCamera();
  }

  void _stopScanning() {
    AppLog.instance.debug('[QrScannerPage] stopScanning', tag: 'QR');

    if (_status == QrScannerStatus.scanning) {
      _controller?.pauseCamera();
    }

    if (!mounted) return;
    setState(() {
      _status = QrScannerStatus.idle;
      _candidateRect = null;
    });
  }

  Future<void> _toggleTorch() async {
    await _controller?.toggleFlash();
    final flashStatus = await _controller?.getFlashStatus();
    final currentTorchState = flashStatus == true;
    AppLog.instance.debug(
      '[QrScannerPage] toggleTorch -> isOn=$currentTorchState',
      tag: 'QR',
    );
    if (!mounted) return;
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
      if (!mounted) return;
      setState(() {
        _suggestTorch = true;
      });
    }
  }

  /// ZXing 扫描结果回调（只给你一个字符串）
  void _onDetectText(String value) async {
    AppLog.instance.debug(
      '[QrScannerPage] onDetectText: status=$_status',
      tag: 'QR',
    );

    if (_status != QrScannerStatus.scanning) return;

    if (value.isEmpty) {
      _updateSuggestTorch();
      return;
    }

    _lastAnyDetectAt = DateTime.now();

    // 使用你原来的稳定追踪逻辑
    final stable = _tracker.update(value);
    if (!stable.isStable) {
      AppLog.instance.debug(
        '[QrScannerPage] onDetectText: candidate unstable hits=${stable.hitCount} elapsedMs=${stable.elapsedMs}',
        tag: 'QR',
      );
      return;
    }

    // 稳定成功
    AppLog.instance.info(
      '[QrScannerPage] onDetectText: STABLE success, contentLen=${value.length}',
      tag: 'QR',
    );

    if (_beepPlayedForThisSuccess) return;
    _beepPlayedForThisSuccess = true;

    // 提示音
    unawaited(_playSuccessBeep());

    if (!mounted) return;
    setState(() {
      _status = QrScannerStatus.success;
      _qrContent = value;
    });

    // 导航：和之前 ref.listen 中的逻辑类似
    // 编号统计页走 popResult，只需要返回结果即可，不需要额外 toast
    if (widget.successAction != QrScannerSuccessAction.popResult) {
      Fluttertoast.showToast(msg: context.l10n.qr_scan_success);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _qrContent == null) return;

      _stopScanning();

      final content = _qrContent!;
      if (widget.successAction == QrScannerSuccessAction.popResult) {
        if (context.mounted) {
          context.pop(content);
        }
        return;
      }

      await DeviceEntryCoordinator.handle(context, ref, content);
    });
  }

  /// QRView 创建时回调，绑定控制器并监听流
  void _onQRViewCreated(QRViewController controller) {
    AppLog.instance.debug('[QrScannerPage] QRView created', tag: 'QR');
    _controller = controller;

    // 开始预览和扫描
    _controller?.resumeCamera();
    _startScanning();

    controller.scannedDataStream.listen((scanData) {
      final text = scanData.code;
      if (text == null || text.isEmpty) {
        _updateSuggestTorch();
        return;
      }
      _onDetectText(text);
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _stopScanning();
              if (widget.successAction == QrScannerSuccessAction.popResult) {
                context.pop();
              } else {
                context.go(AppRoutes.home);
              }
            },
          ),
          actions: const [
            // 顶部右侧闪光灯按钮暂时移除（点击无效问题）
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final double boxSize = 250;
            final double left = (constraints.maxWidth - boxSize) / 2;
            final double top = (constraints.maxHeight - boxSize) / 2;
            final Rect scanRect = Rect.fromLTWH(left, top, boxSize, boxSize);

            return Stack(
              children: [
                // 相机预览：改用 QRView（ZXing）
                QRView(
                  key: _qrKey,
                  onQRViewCreated: _onQRViewCreated,
                  // overlay 我们自己画，所以这里用默认/不额外绘制也行
                  onPermissionSet: (ctrl, p) {
                    AppLog.instance.debug(
                      '[QrScannerPage] permissionSet: $p',
                      tag: 'QR',
                    );
                    if (!p && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.l10n.camera_permission_denied, // 自己的文案 key
                          ),
                        ),
                      );
                    }
                  },
                ),

                // 扫描框覆盖层（ROI 镂空 + 候选框）
                _buildScannerOverlay(
                  scanRect: scanRect,
                  candidate: _candidateRect,
                ),

                // 提示开启闪光灯
                if (_suggestTorch && !_isTorchOn)
                  Positioned(
                    bottom: 130,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.light_mode,
                              color: Colors.yellow,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              context.l10n.dark_env_hint,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _toggleTorch,
                              child: Text(
                                context.l10n.turn_on,
                                style: const TextStyle(
                                  color: Colors.yellow,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 构建扫描框覆盖层（含 ROI 镂空与候选框）
  Widget _buildScannerOverlay({
    required Rect scanRect,
    Rect? candidate,
  }) {
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

            // 这里原来有候选框高亮，现在关闭避免闪烁
          ],
        );
      },
    );
  }

  /// 构建四个角的装饰
  List<Widget> _buildCornerDecorations() {
    const cornerSize = 20.0;
    const cornerWidth = 3.0;
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
    final hole = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          scanRect,
          const Radius.circular(16),
        ),
      );
    final overlay = Path.combine(PathOperation.difference, bg, hole);
    canvas.drawPath(overlay, paint);
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) =>
      oldDelegate.scanRect != scanRect;
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

  const _CandidateUpdateResult(
    this.isStable,
    this.hitCount,
    this.elapsedMs,
  );
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
    _firstAt ??= now;

    if (_lastValue == value) {
      _hits += 1;
    } else {
      _hits = 1;
      _firstAt = now;
    }

    _lastValue = value;
    final inWindow = now.difference(_firstAt!).compareTo(_window) <= 0;
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
