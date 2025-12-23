import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/models/device_customization.dart';
import '../../core/providers/device_customization_provider.dart';
import '../../core/utils/image_processing.dart';
import '../../l10n/app_localizations.dart';

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
  static const Duration _singleProcessingTimeout = Duration(seconds: 5);

  int _wallpaperPageIndex = 0;
  double _wallpaperPage = 0;

  int _layoutPageIndex = 0;
  double _layoutPage = 0;

  PageController? _wallpaperController;
  PageController? _layoutController;

  bool _isProcessingWallpaper = false;
  int _processingWallpaperIndex = 0; // 0-based
  int _processingWallpaperTotal = 0; // n
  bool _processingWallpapersUploading = false;

  bool get _hasCustomWallpaper {
    final wallpapers = ref
        .read(deviceCustomizationProvider)
        .customization
        .customWallpaperInfos;
    return wallpapers.any((item) => item.hasData);
  }

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
            if (!mounted) return;
            final l10n = context.l10n;
            _showToast(l10n.device_edit_load_failed(error.toString()));
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
    final l10n = context.l10n;
    final state = ref.read(deviceCustomizationProvider);
    final notifier = ref.read(deviceCustomizationProvider.notifier);

    if (state.isSaving) return;
    if (_isProcessingWallpaper) {
      _showToast(l10n.image_processing_save_wait);
      return;
    }
    if (state.isUploading) {
      _showToast(l10n.wallpaper_uploading_save_wait);
      return;
    }
    final deviceId = widget.displayDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      _showToast(l10n.missing_device_id_save);
      return;
    }

    try {
      await notifier.saveRemote();
      if (!mounted) return;
      _showToast(l10n.settings_saved);
      context.pop();
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
                  ? l10n.saving_ellipsis
                  : (isBusyWithWallpaper ? l10n.processing_ellipsis : l10n.done),
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
                            ? l10n.saving_ellipsis
                            : (isBusyWithWallpaper
                                ? l10n.processing_ellipsis
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
                  currentLabel: l10n.current_label,
                  setLabel: l10n.set_as_current,
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
                currentLabel: l10n.current_label,
                setLabel: l10n.set_as_current,
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
    DeviceCustomizationState state, {
    required bool isBusy,
  }) {
    final l10n = context.l10n;
    return switch (index) {
      0 => Image.asset(
          'assets/images/device_wallpaper_default.png',
          fit: BoxFit.cover,
        ),
      _ => Stack(
          fit: StackFit.expand,
          children: [
            // —— 底图：有 custom 就用 preview，没有就用占位
            _hasCustomWallpaper
                ? _buildUploadedWallpaperPreview(state)
                : _buildUploadPlaceholder(),

            // —— 处理中：统一盖进度蒙层（无 loading）
            if (_isProcessingWallpaper)
              Positioned.fill(
                child: Container(
                  color: Colors.black45,
                  alignment: Alignment.center,
                  child: Text(
                    _processingWallpapersUploading
                        ? l10n.wallpaper_uploading_ellipsis
                        : l10n.wallpaper_processing_index_total(
                            _processingWallpaperIndex + 1,
                            _processingWallpaperTotal,
                          ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
          ],
        ),
    };
  }

  Widget _buildUploadedWallpaperPreview(DeviceCustomizationState state) {
    final l10n = context.l10n;
    const fallbackDecoration = BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF1E1E1E), Color(0xFF444545)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );
    final paths = state.localWallpaperPaths;
    if (paths.isEmpty) {
      return Container(decoration: fallbackDecoration);
    }

    final cacheKey = state.customization.customWallpaperInfos
        .map((info) => info.md5.isNotEmpty ? info.md5 : info.key)
        .where((value) => value.isNotEmpty)
        .join('|');

    if (paths.length == 1) {
      final path = paths.first;
      return Image.file(
        File(path),
        key: ValueKey(cacheKey.isEmpty ? path : cacheKey),
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) {
          return Container(decoration: fallbackDecoration);
        },
      );
    }

    final visible = paths.take(3).toList();
    const double offset = 12;

    return Stack(
      children: [
        for (var i = visible.length - 1; i >= 0; i--)
          Positioned.fill(
            left: offset * i,
            right: offset * (visible.length - i - 1),
            top: offset * (visible.length - i - 1) / 1.4,
            bottom: offset * i / 1.4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    spreadRadius: 1,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.file(
                  File(visible[i]),
                  key: ValueKey('$cacheKey-$i-${visible[i]}'),
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, __) {
                    return Container(decoration: fallbackDecoration);
                  },
                ),
              ),
            ),
          ),
        Positioned(
          right: 10,
          top: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              l10n.wallpaper_count(paths.length),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUploadPlaceholder() {
    final l10n = context.l10n;
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wallpaper_outlined,
              size: 48,
              color: Colors.black45,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.wallpaper_not_uploaded,
              style: const TextStyle(
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
    final l10n = context.l10n;
    if (!isViewingCustom) {
      return const SizedBox(height: 48);
    }

    if (!_hasCustomWallpaper) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: isBusy ? null : _handleUploadTap,
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(l10n.wallpaper_upload_from_gallery),
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
          label: Text(l10n.delete),
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
          label: Text(
            isBusy ? l10n.processing_ellipsis : l10n.wallpaper_reupload,
          ),
        ),
      ],
    );
  }

  Future<void> _handleUploadTap() async {
    final l10n = context.l10n; // ✅ 缓存，后面别再用 context.l10n
    final notifier = ref.read(deviceCustomizationProvider.notifier);
    final state = ref.read(deviceCustomizationProvider);

    if (state.isUploading || _isProcessingWallpaper) return;

    final deviceId = widget.displayDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      _showToast(l10n.missing_device_id_upload_wallpaper);
      return;
    }

    final hasPermission = await _ensurePhotoPermission();
    if (!hasPermission) {
      _showToast(l10n.photo_permission_required_upload_wallpaper);
      return;
    }

    final picker = ImagePicker();
    final maxCount = DeviceCustomization.maxCustomWallpapers;

    const int softMaxDim = 1920;
    const int softQuality = 90;

    // 设置 imageQuality 可促使部分平台（如 iOS HEIC）返回转码后的 JPEG，避免后续解析失败。
    final picked = await picker.pickMultiImage(
      limit: maxCount,
      imageQuality: softQuality,
      maxWidth: softMaxDim.toDouble(),
      maxHeight: softMaxDim.toDouble(),
    );
    if (picked == null || picked.isEmpty) return;

    List<XFile> selected = picked;
    if (picked.length > maxCount) {
      // 部分平台可能未严格限制，再次兜底截取并提示。
      _showToast(l10n.wallpaper_upload_limit(maxCount));
      selected = picked.take(maxCount).toList();
    }

    for (final file in selected) {
      final validationMessage = _validateImageFormat(file, l10n);
      if (validationMessage != null) {
        _showToast(validationMessage);
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isProcessingWallpaper = true;
        _processingWallpaperTotal = selected.length;
        _processingWallpaperIndex = 0;
        _processingWallpapersUploading = false;
      });
    }

    try {
      final processedList = <ImageProcessingResult>[];
      for (var i = 0; i < selected.length; i++) {
        if (mounted) {
          setState(() {
            _processingWallpaperIndex = i; // 当前正在处理第 i 张
          });
        }
        final processed = await _processSingleWallpaper(
          selected[i],
          index: i,
          l10n: l10n,
        ).timeout(
          _singleProcessingTimeout,
          onTimeout: () => throw TimeoutException(
            l10n.wallpaper_processing_timeout_index(i + 1),
          ),
        );
        processedList.add(processed);
      }
      if (mounted) {
        setState(() {
          _processingWallpapersUploading = true;
        });
      }
      await notifier.applyProcessedWallpapers(
        deviceId: deviceId,
        processedList: processedList,
      );

      if (mounted) {
        setState(() {
          _processingWallpapersUploading = false;
        });
      }

      _setCurrentWallpaper(1);
      _showToast(l10n.wallpaper_upload_success);
    } catch (error) {
      final message = switch (error) {
        TimeoutException _ => error.message ?? l10n.image_processing_timeout_hint,
        String s when s.isNotEmpty => s,
        ImageProcessingException e => e.message,
        _ => l10n.image_processing_failed(error.toString()),
      };
      _showToast(message);
    } finally {
      if (mounted) {
        setState(() => _isProcessingWallpaper = false);
      }
    }
  }

  Future<ImageProcessingResult> _processSingleWallpaper(
    XFile file, {
    required int index,
    required AppLocalizations l10n,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      return await WallpaperImageProcessor.processWallpaperAuto(
        bytes: bytes,
        sourcePath: file.path,
      );
    } on ImageProcessingException catch (error) {
      throw ImageProcessingException(
        l10n.image_processing_failed_index(
          index + 1,
          error.message,
        ),
      );
    } catch (_) {
      throw ImageProcessingException(
        l10n.image_processing_failed_index_retry(index + 1),
      );
    }
  }

  Future<void> _handleDeleteWallpaper() async {
    final l10n = context.l10n;
    final state = ref.read(deviceCustomizationProvider);
    final notifier = ref.read(deviceCustomizationProvider.notifier);

    if (state.isUploading || _isProcessingWallpaper) return;

    final deviceId = widget.displayDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      _showToast(l10n.missing_device_id_delete_wallpaper);
      return;
    }

    await notifier.deleteWallpaper(deviceId);
    if (!mounted) return;
    _showToast(l10n.wallpaper_deleted);
  }

  void _setCurrentWallpaper(int index) {
    final state = ref.read(deviceCustomizationProvider);
    final notifier = ref.read(deviceCustomizationProvider.notifier);

    if (_selectedWallpaperPageIndex == index) return;

    final targetWallpaper = index == 1
        ? DeviceCustomization.customWallpaper
        : DeviceCustomization.defaultWallpaper;

    notifier.updateWallpaper(wallpaper: targetWallpaper);

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
    // iOS / 其他平台
    if (!Platform.isAndroid) {
      final s = await Permission.photos.request();
      if (s.isGranted || s.isLimited) return true;
      if (s.isPermanentlyDenied) await openAppSettings();
      return false;
    }

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;

    // Android 14/13+：只要 photos（READ_MEDIA_IMAGES）
    if (sdkInt >= 33) {
      final s = await Permission.photos.request();
      if (s.isGranted || s.isLimited) return true;
      if (s.isPermanentlyDenied) await openAppSettings();
      return false;
    }

    // Android 12-：用 storage（READ_EXTERNAL_STORAGE）
    final s = await Permission.storage.request();
    if (s.isGranted) return true;
    if (s.isPermanentlyDenied) await openAppSettings();
    return false;
  }

  String? _validateImageFormat(XFile file, AppLocalizations l10n) {
    final ext = p.extension(file.path).toLowerCase();
    const allowed = ['.jpg', '.jpeg', '.png'];

    if (ext.isEmpty) return null; // content:// 场景

    if (!allowed.contains(ext)) return l10n.image_format_not_supported;
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
