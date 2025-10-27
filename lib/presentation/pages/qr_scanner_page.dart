import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/l10n_extensions.dart';
import 'dart:ui' show Rect, Size;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/router/app_router.dart';
import '../../features/qr_scanner/providers/qr_scanner_provider.dart';
import '../../core/flow/device_entry_coordinator.dart';

class QrScannerPage extends ConsumerStatefulWidget {
  const QrScannerPage({super.key});

  @override
  ConsumerState<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends ConsumerState<QrScannerPage> {
  @override
  void initState() {
    super.initState();
    // 初始化扫描器
    // ignore: avoid_print
    print('[QrScannerPage] initState -> initializeController + startScanning');
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
  }

  @override
  Widget build(BuildContext context) {
    final scannerState = ref.watch(qrScannerProvider);
    final scannerNotifier = ref.read(qrScannerProvider.notifier);

    // 监听扫描成功状态，跳转到设备连接页面显示信息（加 mounted 防护，并在帧回调中导航）
    ref.listen<QrScannerState>(qrScannerProvider, (previous, current) async {
      if (!mounted) return;
      if (current.status == QrScannerStatus.success && current.qrContent != null) {
        // ignore: avoid_print
        print('[QrScannerPage] detect SUCCESS -> navigate via DeviceEntryCoordinator');
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
                // ignore: avoid_print
                print('[QrScannerPage] back pressed -> stopScanning and go home');
                ref.read(qrScannerProvider.notifier).stopScanning();
              });
              // 返回主页
              context.go(AppRoutes.home);
            },
          ),
          actions: [
            // cc暂未实现，先注释掉
            // // 相册选择按钮
            // IconButton(
            //   onPressed: () => scannerNotifier.scanFromImage(),
            //   icon: const Icon(
            //     Icons.photo_library,
            //     color: Colors.white,
            //   ),
            //   tooltip: context.l10n.gallery_picker,
            // ),
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
