import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/router/app_router.dart';
import '../../core/providers/app_state_provider.dart';
import '../../features/qr_scanner/providers/qr_scanner_provider.dart';
import '../../features/qr_scanner/utils/qr_data_parser.dart';

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
    ref.listen<QrScannerState>(qrScannerProvider, (previous, current) {
      if (!mounted) return;
      if (current.status == QrScannerStatus.success && current.qrContent != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            final deviceData = QrDataParser.fromQrContent(current.qrContent!);
            // 停止扫描，避免在已销毁元素上继续更新
            ref.read(qrScannerProvider.notifier).stopScanning();
            // 保存扫描结果到全局状态
            ref.read(appStateProvider.notifier).setScannedDeviceData(deviceData);
            // 跳转到设备连接页面（仅显示信息，不启动连接）
            context.go('${AppRoutes.deviceConnection}?deviceId=${deviceData.deviceId}');
          } catch (e) {
            print('QR码解析失败: $e');
          }
        });
      }
    });

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // 停止扫描并清理资源
          ref.read(qrScannerProvider.notifier).stopScanning();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
      appBar: AppBar(
          title: const Text('扫描设备二维码'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              // 停止扫描并清理资源
              ref.read(qrScannerProvider.notifier).stopScanning();
              // 返回主页
              context.go(AppRoutes.home);
            },
          ),
          actions: [
            // 相册选择按钮
            IconButton(
              onPressed: () => scannerNotifier.scanFromImage(),
              icon: const Icon(
                Icons.photo_library,
                color: Colors.white,
              ),
              tooltip: '从相册选择',
            ),
            // 闪光灯按钮
            IconButton(
              onPressed: () => scannerNotifier.toggleTorch(),
              icon: Icon(
                scannerState.isTorchOn ? Icons.flash_on : Icons.flash_off,
                color: scannerState.isTorchOn ? Colors.yellow : Colors.white,
              ),
              tooltip: '闪光灯',
            ),
          ],
        ),
        body: Stack(
          children: [
            // 相机预览
            if (scannerNotifier.controller != null)
              MobileScanner(
                controller: scannerNotifier.controller!,
                onDetect: scannerNotifier.onDetect,
              ),

            // 扫描框覆盖层
            _buildScannerOverlay(),

            // 状态指示器
            _buildStatusIndicator(scannerState),

            // 底部提示信息
            _buildBottomInfo(),
          ],
        ),
      ),
    );
  }

  /// 构建扫描框覆盖层
  Widget _buildScannerOverlay() {
    return Stack(
      children: [
        // 半透明遮罩
        Container(
          decoration: const BoxDecoration(
            color: Colors.black54,
          ),
        ),

        // 扫描框
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                // 四个角的装饰
                ..._buildCornerDecorations(),

                // 中间透明区域
                Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.transparent,
                      width: 0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
                          '扫描成功！',
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
                      child: Text('重新扫描'),
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
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.qr_code_2,
              color: Colors.white70,
              size: 32,
            ),
            SizedBox(height: 8),
            Text(
              '将二维码对准扫描框',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4),
            Text(
              '扫描成功后会显示二维码内容',
              style: TextStyle(
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
        return '准备扫描';
      case QrScannerStatus.scanning:
        return '扫描中...';
      case QrScannerStatus.processing:
        return '解析数据...';
      case QrScannerStatus.success:
        return '扫描成功！';
      case QrScannerStatus.error:
        return state.errorMessage ?? '扫描失败';
    }
  }

}
