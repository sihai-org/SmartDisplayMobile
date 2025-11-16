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
import '../../features/qr_scanner/providers/qr_scanner_provider.dart';
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

  @override
  void initState() {
    super.initState();

    // 初始化播放器
    _beepPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop); // 播放完停止（不循环）

    // 初始化扫描器
    AppLog.instance.debug('[QrScannerPage] initState -> initializeController + startScanning', tag: 'QR');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final notifier = ref.read(qrScannerProvider.notifier);

      // ✅ 如果 controller 已存在，说明是 hot reload 后重建的 Widget，要强制重置
      if (notifier.controller != null) {
        notifier.reset();
        await Future.delayed(const Duration(milliseconds: 100));
      }

      notifier.initializeController();
      notifier.startScanning();
    });
  }

  @override
  void dispose() {
    super.dispose();
    _beepPlayer.dispose();
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

  @override
  Widget build(BuildContext context) {
    final scannerState = ref.watch(qrScannerProvider);
    final scannerNotifier = ref.read(qrScannerProvider.notifier);

    // 当从其他页面返回且当前处于 idle 时，自动重启扫描
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
      if (isCurrent && scannerState.status == QrScannerStatus.idle && scannerNotifier.controller != null) {
        _beepPlayedForThisSuccess = false; // 重置提示音触发标记
        scannerNotifier.startScanning();
      }
    });

    // 监听扫描成功状态，跳转到设备连接页面显示信息（加 mounted 防护，并在帧回调中导航）
    ref.listen<QrScannerState>(qrScannerProvider, (previous, current) async {
      if (!mounted) return;
      if (current.status == QrScannerStatus.success && current.qrContent != null) {
        AppLog.instance.info('[QrScannerPage] detect SUCCESS -> navigate via DeviceEntryCoordinator', tag: 'QR');
        Fluttertoast.showToast(msg: "扫描成功，跳转中...");

        // 避免重复触发（比如状态快速抖动）
        if (_beepPlayedForThisSuccess) return;
        _beepPlayedForThisSuccess = true;

        unawaited(_playSuccessBeep());

        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          // 停止扫描 - 延迟执行避免在构建期间修改Provider
          Future(() {
            ref.read(qrScannerProvider.notifier).stopScanning();
          });

          // 统一入口：与深链相同流程
          await DeviceEntryCoordinator.handle(context, ref, current.qrContent!);
        });
      }
    });

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // 停止扫描并清理资源 - 延迟执行避免在构建期间修改Provider
          Future(() {
            ref.read(qrScannerProvider.notifier).stopScanning();
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
      appBar: AppBar(
          title: Text(context.l10n.qr_scanner_title),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // 停止扫描并清理资源 - 延迟执行避免在构建期间修改Provider
              Future(() {
                AppLog.instance.debug('[QrScannerPage] back pressed -> stopScanning and go home', tag: 'QR');
                ref.read(qrScannerProvider.notifier).stopScanning();
              });
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
                if (scannerNotifier.controller != null)
                  MobileScanner(
                    controller: scannerNotifier.controller!,
                    onDetect: scannerNotifier.onDetect,
                    scanWindow: scanRect,
                  ),

                // 扫描框覆盖层（ROI 镂空 + 候选框）
                _buildScannerOverlay(scanRect: scanRect, candidate: scannerState.candidateRect),

                // 提示开启闪光灯
                if (scannerState.suggestTorch && !scannerState.isTorchOn)
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
                              onPressed: () => scannerNotifier.toggleTorch(),
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
