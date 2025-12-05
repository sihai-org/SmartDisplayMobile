import 'dart:io';

import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:smart_display_mobile/core/log/app_log.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/models/device_customization.dart';
import '../../core/providers/device_customization_provider.dart';
import '../../core/utils/image_processing.dart';

class DeviceEditPage extends ConsumerStatefulWidget {
  final String? displayDeviceId;
  final String? deviceName;

  const DeviceEditPage({
    super.key,
    this.displayDeviceId,
    this.deviceName,
  });

  @override
  ConsumerState<DeviceEditPage> createState() => _DeviceEditPageState();
}

class _DeviceEditPageState extends ConsumerState<DeviceEditPage> {
  static const double _wallpaperViewportFraction = 0.82;
  static const double _wallpaperAspectRatio = 16 / 9;

  static const double _layoutViewportFraction = 0.86;

  int _wallpaperPageIndex = 0;
  double _wallpaperPage = 0;

  int _layoutPageIndex = 0;
  double _layoutPage = 0;

  PageController? _wallpaperController;
  PageController? _layoutController;
  bool _isProcessingWallpaper = false;

  bool get _hasCustomWallpaper =>
      ref
          .read(deviceCustomizationProvider)
          .customization
          .customWallpaperInfo
          ?.hasData ??
          false;

  int get _selectedWallpaperPageIndex {
    final c = ref.read(deviceCustomizationProvider).customization;
    return c.effectiveWallpaper == DeviceCustomization.customWallpaper ? 1 : 0;
  }

  String get _layoutValue =>
      ref.read(deviceCustomizationProvider).customization.effectiveLayout;

  @override
  void initState() {
    super.initState();
    _ensureWallpaperController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(deviceCustomizationProvider.notifier)
          .load(widget.displayDeviceId)
          .catchError((error) {
        _showToast('加载失败：$error');
      });
    });
  }

  @override
  void dispose() {
    _wallpaperController?.dispose();
    _layoutController?.dispose();
    super.dispose();
  }

  void _resetToDefault() {
    ref.read(deviceCustomizationProvider.notifier).resetToDefault();

    setState(() {
      _wallpaperPageIndex = 0;
      _wallpaperPage = 0;
      _layoutPageIndex = 0;
      _layoutPage = 0;
    });
    _wallpaperController?.jumpToPage(0);
    _layoutController?.jumpToPage(0);
  }

  Future<void> _handleSave() async {
    final state = ref.read(deviceCustomizationProvider);
    final notifier = ref.read(deviceCustomizationProvider.notifier);

    if (state.isSaving) return;
    if (_isProcessingWallpaper) {
      _showToast('图片处理中，请稍后保存');
      return;
    }
    if (state.isUploading) {
      _showToast('壁纸上传中，请稍后保存');
      return;
    }
    final deviceId = widget.displayDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      _showToast('缺少设备 ID，无法保存');
      return;
    }

    try {
      await notifier.saveRemote();
      _showToast('设置已保存');
      if (mounted) {
        context.pop();
      }
    } catch (error) {
      _showToast(error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceCustomizationProvider);

    final l10n = context.l10n;
    final resolvedName = (widget.deviceName ?? '').isEmpty
        ? l10n.unknown_device
        : widget.deviceName!;

    final isSaving = state.isSaving;
    final isUploading = state.isUploading;
    final isProcessingWallpaper = _isProcessingWallpaper;
    final isBusyWithWallpaper = isUploading || isProcessingWallpaper;
    final disableSave = isSaving || isBusyWithWallpaper;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(l10n.device_edit_title),
        actions: [
          TextButton(
            onPressed: disableSave ? null : _handleSave,
            child: Text(
              isSaving
                  ? '保存中...'
                  : (isBusyWithWallpaper ? '处理中...' : l10n.done),
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
                    onPressed: disableSave ? null : _handleSave,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        isSaving
                            ? '保存中...'
                            : (isBusyWithWallpaper
                            ? '处理中...'
                            : l10n.save_settings),
                      ),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              'assets/images/device.png',
              height: 62,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            Expanded(
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
                    const SizedBox(height: 6),
                    Text(
                      deviceId,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
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
    final state = ref.watch(deviceCustomizationProvider);
    AppLog.instance.info("~~~~~~~~~~state=${state.localWallpaperPath}");
    final isUploading = state.isUploading;
    final isBusy = isUploading || _isProcessingWallpaper;

    final screenWidth = MediaQuery.of(context).size.width;
    final tileWidth = screenWidth * _wallpaperViewportFraction;
    final imageHeight = tileWidth / _wallpaperAspectRatio;

    const double verticalGap = 10;

    final isViewingCustom = _wallpaperPageIndex == 1;
    final isCurrentView = _selectedWallpaperPageIndex == _wallpaperPageIndex;
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
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CurrentToggle(
                  isCurrent: isCurrentView,
                  canSelect: !isCurrentView &&
                      !(isViewingCustom && !_hasCustomWallpaper),
                  currentLabel: '当前',
                  setLabel: '设为当前',
                  onSelect: () => _setCurrentWallpaper(_wallpaperPageIndex),
                ),
                const SizedBox(height: verticalGap),
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
                          setState(() => _wallpaperPageIndex = index);
                        },
                        itemBuilder: (context, index) {
                          final distance = (_wallpaperPage - index).abs();
                          final scale = (1 - distance * 0.08).clamp(0.9, 1.0);

                          return AspectRatio(
                            aspectRatio: 16 / 9,
                            child: AnimatedScale(
                              scale: scale,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              alignment: Alignment.center,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: _wallpaperImageWidget(
                              index,
                              state,
                              isBusy: isBusy,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                    ),
                  ),
                ),
                const SizedBox(height: verticalGap + 4),
                _buildBottomAction(
                  isViewingCustom: isViewingCustom,
                  isBusy: isBusy,
                ),
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
    options.indexWhere((option) => option.value == _layoutValue);
    final effectiveIndex = selectedIndex == -1 ? 0 : selectedIndex;
    final screenWidth = MediaQuery.of(context).size.width;
    final tileWidth = screenWidth * _layoutViewportFraction;
    final imageHeight = tileWidth / _wallpaperAspectRatio;
    final isCurrentView =
        options[_layoutPageIndex.clamp(0, options.length - 1)].value ==
            _layoutValue;

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
                  options[_layoutPageIndex].value,
                  _layoutPageIndex,
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
                      _layoutPageIndex = index;
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
                        isSelected: _layoutValue == option.value,
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
    final initialPage = _selectedWallpaperPageIndex;
    _wallpaperPageIndex = initialPage;
    _wallpaperPage = initialPage.toDouble();
    final controller = PageController(
      viewportFraction: _wallpaperViewportFraction,
      initialPage: initialPage,
    );
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
      viewportFraction: _layoutViewportFraction,
      initialPage: initialPage,
    );
    _layoutPageIndex = initialPage;
    _layoutPage = initialPage.toDouble();
    controller.addListener(() {
      final page = controller.page;
      if (!mounted || page == null) return;
      setState(() => _layoutPage = page);
    });
    _layoutController = controller;
  }

  Widget _wallpaperImageWidget(
      int index,
      DeviceCustomizationState state,
      {required bool isBusy}) {
    return switch (index) {
      0 => Image.asset(
        'assets/images/device_wallpaper_default.png',
        fit: BoxFit.cover,
      ),
      _ => _hasCustomWallpaper
          ? _buildUploadedWallpaperPreview(state)
          : _buildUploadPlaceholder(isBusy),
    };
  }

  Widget _buildUploadedWallpaperPreview(DeviceCustomizationState state) {
    const fallbackDecoration = BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF1E1E1E), Color(0xFF444545)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );
    final path = state.localWallpaperPath;
    final cacheKey = state.customization.customWallpaperInfo?.md5.isNotEmpty == true
        ? state.customization.customWallpaperInfo!.md5
        : state.customization.customWallpaperInfo?.key ?? path;

    return path != null
        ? Image.file(
      File(path),
      key: ValueKey(cacheKey ?? path),
      fit: BoxFit.cover,
      errorBuilder: (context, _, __) {
        return Container(decoration: fallbackDecoration);
      },
    )
        : Container(decoration: fallbackDecoration);
  }

  Widget _buildUploadPlaceholder(bool isBusy) {

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: isBusy
            ? const CircularProgressIndicator()
            : const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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

  Widget _buildBottomAction({
    required bool isViewingCustom,
    required bool isBusy,
  }) {

    if (!isViewingCustom) {
      return const SizedBox(height: 48);
    }

    if (!_hasCustomWallpaper) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: isBusy ? null : _handleUploadTap,
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
          onPressed: isBusy ? null : _handleDeleteWallpaper,
          icon: const Icon(Icons.delete_outline),
          label: const Text('删除'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.tonalIcon(
          onPressed: isBusy ? null : _handleUploadTap,
          icon: isBusy
              ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          )
              : const Icon(Icons.refresh),
          label: Text(isBusy ? '处理中...' : '重新上传'),
        ),
      ],
    );
  }

  Future<void> _handleUploadTap() async {
    final notifier = ref.read(deviceCustomizationProvider.notifier);
    final state = ref.read(deviceCustomizationProvider);

    if (state.isUploading || _isProcessingWallpaper) return;

    final deviceId = widget.displayDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      _showToast('缺少设备 ID，无法上传壁纸');
      return;
    }

    final hasPermission = await _ensurePhotoPermission();
    if (!hasPermission) {
      _showToast('需要相册权限才能上传壁纸');
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final validationMessage = _validateImageFormat(picked);
    if (validationMessage != null) {
      _showToast(validationMessage);
      return;
    }

    if (mounted) {
      setState(() => _isProcessingWallpaper = true);
      _showToast('图片处理中...需要几秒，请耐心等待');
    }

    try {
      final processed = await WallpaperImageProcessor.processWallpaperInIsolate(
        bytes: await picked.readAsBytes(),
        sourcePath: picked.path,
      );

      await notifier.applyProcessedWallpaper(
        deviceId: deviceId,
        processed: processed,
      );

      _setCurrentWallpaper(1);
      _showToast('壁纸上传成功');
    } catch (error) {
      _showToast('上传失败：$error');
    } finally {
      if (mounted) {
        setState(() => _isProcessingWallpaper = false);
      }
    }
  }

  Future<void> _handleDeleteWallpaper() async {
    final state = ref.read(deviceCustomizationProvider);
    final notifier = ref.read(deviceCustomizationProvider.notifier);

    if (state.isUploading || _isProcessingWallpaper) return;

    final deviceId = widget.displayDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      _showToast('缺少设备 ID，无法删除壁纸');
      return;
    }

    await notifier.deleteWallpaper(deviceId);

    _showToast('已删除上传的壁纸');
  }

  void _setCurrentWallpaper(int index) {
    final state = ref.read(deviceCustomizationProvider);
    final notifier = ref.read(deviceCustomizationProvider.notifier);

    if (_selectedWallpaperPageIndex == index) return;

    final targetWallpaper = index == 1
        ? DeviceCustomization.customWallpaper
        : DeviceCustomization.defaultWallpaper;

    notifier.updateWallpaper(
      state.customization.customWallpaperInfo,
      wallpaper: targetWallpaper,
    );

    _wallpaperController?.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _setLayout(String value, int index) {
    final notifier = ref.read(deviceCustomizationProvider.notifier);

    if (_layoutValue == value && _layoutPageIndex == index) return;
    notifier.updateLayout(value);

    setState(() {
      _layoutPageIndex = index;
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

  String? _validateImageFormat(XFile file) {
    final extension = p.extension(file.path).toLowerCase();
    const allowed = ['.jpg', '.jpeg', '.png'];
    if (!allowed.contains(extension)) {
      return '仅支持 JPG / PNG 格式的图片';
    }
    return null;
  }

  void _showToast(String message) {
    if (!mounted) return;
    Fluttertoast.showToast(
      msg: message,
      gravity: ToastGravity.BOTTOM,
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
