import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/models/device_customization.dart';
import '../../core/l10n/l10n_extensions.dart';

class DeviceEditPage extends StatefulWidget {
  final String? displayDeviceId;
  final String? deviceName;

  const DeviceEditPage({
    super.key,
    this.displayDeviceId,
    this.deviceName,
  });

  @override
  State<DeviceEditPage> createState() => _DeviceEditPageState();
}

class _DeviceEditPageState extends State<DeviceEditPage> {
  static const double _wallpaperViewportFraction = 0.82;
  static const double _wallpaperAspectRatio = 16 / 9;
  static const double _layoutViewportFraction = 0.86;

  String _layout = 'default';
  int _layoutViewedIndex = 0;
  double _layoutPage = 0;
  int _selectedWallpaperIndex = 0;
  int _viewedWallpaperIndex = 0;
  double _wallpaperPage = 0;
  bool _hasCustomWallpaper = false;
  bool _isUploading = false;
  String? _localWallpaperPath;
  PageController? _wallpaperController;
  PageController? _layoutController;

  @override
  void initState() {
    super.initState();
    _ensureWallpaperController();
    final initialLayoutPage = _layout == 'frame' ? 1 : 0;
    _layoutViewedIndex = initialLayoutPage;
    _ensureLayoutController(initialPage: initialLayoutPage);
  }

  @override
  void dispose() {
    _wallpaperController?.dispose();
    _layoutController?.dispose();
    super.dispose();
  }

  void _resetToDefault() {
    setState(() {
      _layout = 'default';
      _selectedWallpaperIndex = 0;
      _viewedWallpaperIndex = 0;
      _wallpaperPage = 0;
      _hasCustomWallpaper = false;
      _isUploading = false;
      _localWallpaperPath = null;
    });
    _wallpaperController?.jumpToPage(0);
  }

  void _handleSave() {
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final resolvedName = (widget.deviceName ?? '').isEmpty
        ? l10n.unknown_device
        : widget.deviceName!;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(l10n.device_edit_title),
        actions: [
          TextButton(
            onPressed: _handleSave,
            child: Text(
              l10n.done,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPreview(resolvedName, widget.displayDeviceId),
              const SizedBox(height: 16),
              _buildWallpaperSelector(),
              const SizedBox(height: 12),
              _buildLayoutSection(),
              const SizedBox(height: 24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: _handleSave,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(l10n.save_settings),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _resetToDefault,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(l10n.reset_to_default),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(String deviceName, String? deviceId) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              deviceName,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (deviceId != null && deviceId.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                deviceId,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Image.asset(
                  'assets/images/device.png',
                  height: 120,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWallpaperSelector() {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // 1. 根据屏幕宽度和 viewportFraction 算出壁纸的宽度
    final screenWidth = MediaQuery.of(context).size.width;
    final tileWidth = screenWidth * _wallpaperViewportFraction;

    // 2. 再根据 16:9 算出高度（以后如果别处需要可以直接用）
    final imageHeight = tileWidth / _wallpaperAspectRatio;

    const double verticalGap = 10; // current / image / bottomAction 之间的等距间隔

    final isViewingCustom = _viewedWallpaperIndex == 1;
    final isCurrentView = _selectedWallpaperIndex == _viewedWallpaperIndex;
    _ensureWallpaperController();

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.wallpaper_section_title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            /// 用一个 Column 把 current / image / bottomAction 包起来，
            /// 用相同的 SizedBox(height: verticalGap) 保证三者垂直等距
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // current
                _CurrentToggle(
                  isCurrent: isCurrentView,
                  canSelect: !isCurrentView &&
                      !(isViewingCustom && !_hasCustomWallpaper),
                  currentLabel: '当前',
                  setLabel: '设为当前',
                  onSelect: () => _setCurrentWallpaper(_viewedWallpaperIndex),
                ),

                const SizedBox(height: verticalGap),

                // image（壁纸预览），根据屏幕宽度计算 16:9 宽高
                Center(
                  child: SizedBox(
                    width: tileWidth,
                    height: imageHeight,
                    child: AspectRatio(
                      aspectRatio: _wallpaperAspectRatio,
                      child: PageView.builder(
                        controller: _wallpaperController,
                        itemCount: 2,
                        onPageChanged: (index) {
                          setState(() => _viewedWallpaperIndex = index);
                        },
                        itemBuilder: (context, index) {
                          final distance = (_wallpaperPage - index).abs();
                          final scale = (1 - distance * 0.08).clamp(0.9, 1.0);

                          return AspectRatio(
                            aspectRatio: 16 / 9, // 16:9 边框
                            child: AnimatedScale(
                              scale: scale,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              alignment: Alignment.center,
                              // 中心缩放
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: ImageWidget(index),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: verticalGap + 4),

                // bottomAction
                _buildBottomAction(isViewingCustom: isViewingCustom),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayoutSection() {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    const double verticalGap = 10;
    final options = [
      _LayoutOption(
        value: 'default',
        title: l10n.layout_default,
        subtitle: l10n.layout_default_hint,
        imageAsset: 'assets/images/layout_default.jpg',
      ),
      _LayoutOption(
        value: 'frame',
        title: l10n.layout_frame,
        subtitle: l10n.layout_frame_hint,
        imageAsset: 'assets/images/layout_frame.jpg',
      ),
    ];
    final selectedIndex =
        options.indexWhere((option) => option.value == _layout);
    final effectiveIndex = selectedIndex == -1 ? 0 : selectedIndex;
    final screenWidth = MediaQuery.of(context).size.width;
    final tileWidth = screenWidth * _layoutViewportFraction;
    final imageHeight = tileWidth / _wallpaperAspectRatio;
    final isCurrentView =
        options[_layoutViewedIndex.clamp(0, options.length - 1)].value ==
            _layout;

    _ensureLayoutController(initialPage: effectiveIndex);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.layout_section_title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Center(
              child: _CurrentToggle(
                isCurrent: isCurrentView,
                canSelect: !isCurrentView,
                currentLabel: '当前',
                setLabel: '设为当前',
                onSelect: () => _setLayout(
                  options[_layoutViewedIndex].value,
                  _layoutViewedIndex,
                ),
              ),
            ),
            const SizedBox(height: verticalGap),
            Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: tileWidth,
                height: imageHeight + 36,
                child: PageView.builder(
                  controller: _layoutController,
                  itemCount: options.length,
                  onPageChanged: (index) {
                    setState(() {
                      _layoutViewedIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final distance = (_layoutPage - index).abs();
                    final scale = (1 - distance * 0.08).clamp(0.9, 1.0);
                    final option = options[index];

                    return AnimatedScale(
                      scale: scale,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      alignment: Alignment.center,
                      child: _LayoutPreviewCard(
                        option: option,
                        isSelected: _layout == option.value,
                        onSelect: () => _setLayout(option.value, index),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _ensureWallpaperController() {
    if (_wallpaperController != null) return;
    final controller =
        PageController(viewportFraction: _wallpaperViewportFraction);
    controller.addListener(() {
      final page = controller.page;
      if (!mounted || page == null) return;
      setState(() => _wallpaperPage = page);
    });
    _wallpaperController = controller;
  }

  void _ensureLayoutController({int initialPage = 0}) {
    if (_layoutController != null) return;
    final controller = PageController(
        viewportFraction: _layoutViewportFraction, initialPage: initialPage);
    _layoutPage = initialPage.toDouble();
    controller.addListener(() {
      final page = controller.page;
      if (!mounted || page == null) return;
      setState(() => _layoutPage = page);
    });
    _layoutController = controller;
  }

  Widget _buildDefaultWallpaperPreview() {
    return Container(
      decoration: const BoxDecoration(color: Colors.black12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/device_wallpaper_default.png',
            fit: BoxFit.cover,
            errorBuilder: (context, _, __) {
              // Fallback in case asset is missing in the current build.
              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF20387A), Color(0xFF5173E0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget ImageWidget(int index) {
    return switch (index) {
      0 => Image.asset(
          'assets/images/device_wallpaper_default.png',
          fit: BoxFit.cover,
        ),
      _ => _hasCustomWallpaper
          ? Image.file(File(_localWallpaperPath!), fit: BoxFit.cover)
          : _buildUploadPlaceholder(),
    };
  }

  Widget _buildUploadedWallpaperPreview() {
    final fallbackDecoration = BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1E1E1E), Color(0xFF444545)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );
    final path = _localWallpaperPath;

    return path != null
        ? Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (context, _, __) {
              return Container(decoration: fallbackDecoration);
            },
          )
        : Container(decoration: fallbackDecoration);
  }

  Widget _buildUploadPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: _isUploading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.wallpaper_outlined,
                    size: 48,
                    color: Colors.black45,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '未上传壁纸',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildBottomAction({required bool isViewingCustom}) {
    if (!isViewingCustom) {
      return const SizedBox(height: 48);
    }

    if (!_hasCustomWallpaper) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: _isUploading ? null : _handleUploadTap,
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('从相册上传'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: _isUploading ? null : _handleDeleteWallpaper,
          icon: const Icon(Icons.delete_outline),
          label: const Text('删除'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          onPressed: _isUploading ? null : _handleUploadTap,
          icon: _isUploading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Icon(Icons.refresh),
          label: Text(_isUploading ? '处理中...' : '重新上传'),
        ),
      ],
    );
  }

  Future<void> _handleUploadTap() async {
    if (_isUploading) return;

    final hasPermission = await _ensurePhotoPermission();
    if (!hasPermission) {
      _showSnack('需要相册权限才能上传壁纸');
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final validationMessage = await _validateImage(picked);
    if (validationMessage != null) {
      _showSnack(validationMessage);
      return;
    }

    setState(() => _isUploading = true);

    try {
      await _mockUpload(picked);
      final savedPath = await _saveImageLocally(picked);
      setState(() {
        _hasCustomWallpaper = true;
        _localWallpaperPath = savedPath;
      });
      _setCurrentWallpaper(1);
      _showSnack('壁纸上传成功');
    } catch (error) {
      _showSnack('上传失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _handleDeleteWallpaper() async {
    if (_isUploading) return;

    final path = _localWallpaperPath;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // Ignore deletion errors; proceed to clear state.
        }
      }
    }

    setState(() {
      _hasCustomWallpaper = false;
      _localWallpaperPath = null;
      if (_selectedWallpaperIndex == 1) {
        _selectedWallpaperIndex = 0;
      }
    });

    _showSnack('已删除上传的壁纸');
  }

  void _setCurrentWallpaper(int index) {
    if (_selectedWallpaperIndex == index) return;
    setState(() => _selectedWallpaperIndex = index);
    _wallpaperController?.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _setLayout(String value, int index) {
    if (_layout == value && _layoutViewedIndex == index) return;
    setState(() {
      _layout = value;
      _layoutViewedIndex = index;
    });
    _layoutController?.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<bool> _ensurePhotoPermission() async {
    final requestedStatuses = await <Permission>[
      Permission.photos,
      Permission.storage,
    ].request();

    final granted = requestedStatuses.values.any(
      (status) => status.isGranted || status.isLimited,
    );
    if (granted) return true;

    final permanentlyDenied =
        requestedStatuses.values.any((status) => status.isPermanentlyDenied);
    if (permanentlyDenied) {
      await openAppSettings();
    }
    return false;
  }

  Future<String?> _validateImage(XFile file) async {
    final extension = p.extension(file.path).toLowerCase();
    const allowed = ['.jpg', '.jpeg', '.png'];
    if (!allowed.contains(extension)) {
      return '仅支持 JPG / PNG 格式的图片';
    }

    const maxSizeBytes = 8 * 1024 * 1024; // 8MB
    final length = await file.length();
    if (length > maxSizeBytes) {
      return '图片过大，请选择 8MB 以内的文件';
    }

    return null;
  }

  Future<WallpaperInfo> _mockUpload(XFile file) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return WallpaperInfo(
      version: DateTime.now().millisecondsSinceEpoch.toString(),
      url: 'https://m.vzngpt.com/device_web/www.jpg',
      md5: 'mock-md5',
      mime: 'image/${p.extension(file.path).replaceFirst('.', '')}',
    );
  }

  Future<String> _saveImageLocally(XFile file) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName =
        'wallpaper_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}';
    final target = File(p.join(dir.path, fileName));
    await file.saveTo(target.path);
    return target.path;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _LayoutPreviewCard extends StatelessWidget {
  final _LayoutOption option;
  final bool isSelected;
  final VoidCallback onSelect;

  const _LayoutPreviewCard({
    required this.option,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = isSelected
        ? Border.all(color: theme.colorScheme.primary, width: 1.5)
        : null;

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                border: border,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.asset(
                    option.imageAsset,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              option.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayoutOption {
  final String value;
  final String title;
  final String subtitle;
  final String imageAsset;

  const _LayoutOption({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.imageAsset,
  });
}

class _CurrentToggle extends StatelessWidget {
  final bool isCurrent;
  final bool canSelect;
  final String currentLabel;
  final String setLabel;
  final VoidCallback onSelect;

  const _CurrentToggle({
    required this.isCurrent,
    required this.canSelect,
    required this.currentLabel,
    required this.setLabel,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 40,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: isCurrent
              ? Text(
                  currentLabel,
                  key: const ValueKey('current'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                )
              : FilledButton.tonal(
                  key: const ValueKey('set'),
                  onPressed: canSelect ? onSelect : null,
                  child: Text(setLabel),
                ),
        ),
      ),
    );
  }
}
