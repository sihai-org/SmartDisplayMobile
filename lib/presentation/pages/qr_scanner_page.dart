import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/l10n_extensions.dart';
import 'dart:ui' show Rect, Size;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/router/app_router.dart';
import '../../core/providers/app_state_provider.dart';
import '../../core/providers/saved_devices_provider.dart';
import '../../features/qr_scanner/providers/qr_scanner_provider.dart';
import '../../features/qr_scanner/utils/qr_data_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(qrScannerProvider.notifier);
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
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          try {
            print("✅ 进入导航逻辑，准备解析 QR 内容");
            final deviceData = QrDataParser.fromQrContent(current.qrContent!);
            // 停止扫描 - 延迟执行避免在构建期间修改Provider
            Future(() {
              ref.read(qrScannerProvider.notifier).stopScanning();
            });

            // 查看是否已保存过该TV
            await ref.read(savedDevicesProvider.notifier).load();
            final saved = ref.read(savedDevicesProvider);
            print("📦 Saved devices loaded: ${saved.devices.map((d) => d.deviceId).toList()}");
            if (saved.loaded && saved.devices.any((e) => e.deviceId == deviceData.deviceId)) {
              print("📌 已存在设备 ${deviceData.deviceId} → 跳转首页");
              // 已存在：选中并返回首页
              await ref.read(savedDevicesProvider.notifier).select(deviceData.deviceId);
              context.go(AppRoutes.home);
            } else {
              // 先记录扫描数据
              ref.read(appStateProvider.notifier).setScannedDeviceData(deviceData);

              // 调用 Edge Function 检查是否已绑定
              print("🌐 调用 device_check_binding 检查绑定状态");
              final supabase = Supabase.instance.client;
              try {
                final resp = await supabase.functions.invoke(
                  'device_check_binding',
                  body: { 'device_id': deviceData.deviceId },
                );
                if (resp.status != 200) {
                  throw Exception('device_check_binding 调用失败: ${resp.data}');
                }
                final data = resp.data as Map;
                final isBound = (data['is_bound'] == true);
                final isOwner = (data['is_owner'] == true);
                ref.read(appStateProvider.notifier)
                   .setScannedBindingStatus(isBound: isBound, isOwner: isOwner);

                if (isBound && isOwner) {
                  print('✅ 该设备已被自己绑定，设为当前并进入详情');
                  await ref.read(savedDevicesProvider.notifier)
                      .upsertFromQr(deviceData, lastBleAddress: deviceData.bleAddress);
                  await ref.read(savedDevicesProvider.notifier)
                      .select(deviceData.deviceId);
                  context.go(AppRoutes.home);
                  return;
                }

                if (isBound && !isOwner) {
                  print('⛔ 已被他人绑定，提示不可操作');
                  Fluttertoast.showToast(msg: '该设备已被他人绑定，如需操作请先解绑');
                  // 回到扫码页，允许继续扫码
                  return;
                }

                // 未绑定：进入连接流程（后续在连接页判断是否联网并引导配网或绑定）
                print("🆕 未绑定设备 ${deviceData.deviceId} → 跳转连接页");
                context.go('${AppRoutes.deviceConnection}?deviceId=${deviceData.deviceId}');
              } catch (e) {
                print('❌ 检查绑定状态失败: $e');
                // 回退到原先流程：进入连接页
                context.go('${AppRoutes.deviceConnection}?deviceId=${deviceData.deviceId}');
              }
            }
          } catch (e) {
            // 解析失败：跳转到结果展示页，直接显示原始文本以便复制
            print('QR码解析失败: $e');
            final raw = Uri.encodeComponent(current.qrContent!);
            Future(() {
              ref.read(qrScannerProvider.notifier).stopScanning();
            });
            if (mounted) {
              context.go('${AppRoutes.qrCodeResult}?text=$raw');
            }
          }
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
            // 闪光灯按钮
            IconButton(
              onPressed: () => scannerNotifier.toggleTorch(),
              icon: Icon(
                scannerState.isTorchOn ? Icons.flash_on : Icons.flash_off,
                color: scannerState.isTorchOn ? Colors.yellow : Colors.white,
              ),
              tooltip: context.l10n.torch,
            ),
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

                // 状态指示器
                _buildStatusIndicator(scannerState),

                // 底部提示信息
                _buildBottomInfo(),
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
    const color = Colors.green;

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

  /// 构建状态指示器
  Widget _buildStatusIndicator(QrScannerState state) {
    return Positioned(
      top: 120,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: _getStatusColor(state.status).withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: state.status == QrScannerStatus.success && state.qrContent != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _getStatusIcon(state.status),
                        const SizedBox(width: 8),
                        Text(
                          context.l10n.scan_success,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        state.qrContent!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => ref.read(qrScannerProvider.notifier).startScanning(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                      child: Text(context.l10n.rescan),
                    ),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _getStatusIcon(state.status),
                    const SizedBox(width: 8),
                    Text(
                      _getStatusText(state),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// 构建底部信息
  Widget _buildBottomInfo() {
    return Positioned(
      bottom: 60,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.qr_code_2,
              color: Colors.white70,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.aim_qr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.scan_success_will_show,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 获取状态颜色
  Color _getStatusColor(QrScannerStatus status) {
    switch (status) {
      case QrScannerStatus.idle:
        return Colors.grey;
      case QrScannerStatus.scanning:
        return Colors.blue;
      case QrScannerStatus.processing:
        return Colors.orange;
      case QrScannerStatus.success:
        return Colors.green;
      case QrScannerStatus.error:
        return Colors.red;
    }
  }

  /// 获取状态图标
  Widget _getStatusIcon(QrScannerStatus status) {
    switch (status) {
      case QrScannerStatus.idle:
        return const Icon(Icons.qr_code_scanner, color: Colors.white, size: 16);
      case QrScannerStatus.scanning:
        return const Icon(Icons.search, color: Colors.white, size: 16);
      case QrScannerStatus.processing:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2,
          ),
        );
      case QrScannerStatus.success:
        return const Icon(Icons.check_circle, color: Colors.white, size: 16);
      case QrScannerStatus.error:
        return const Icon(Icons.error, color: Colors.white, size: 16);
    }
  }

  /// 获取状态文本
  String _getStatusText(QrScannerState state) {
    switch (state.status) {
      case QrScannerStatus.idle:
        return context.l10n.status_ready;
      case QrScannerStatus.scanning:
        return context.l10n.status_scanning;
      case QrScannerStatus.processing:
        return context.l10n.status_processing;
      case QrScannerStatus.success:
        return context.l10n.scan_success;
      case QrScannerStatus.error:
        return state.errorMessage ?? context.l10n.status_failed;
    }
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
