import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

import 'package:fluttertoast/fluttertoast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:smart_display_mobile/core/log/app_log.dart';

import '../../core/l10n/l10n_extensions.dart';
import '../../core/models/device_customization.dart';
import '../../core/providers/device_customization_provider.dart';
import '../../core/utils/image_processing.dart';
import '../../core/widgets/progress_dialog.dart';
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

  static const Duration _singleProcessingTimeout = Duration(seconds: 5);

  int _wallpaperPageIndex = 0;
  double _wallpaperPage = 0;

  PageController? _wallpaperController;

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

  Future<void> _saveRemoteWithProgress(ProgressDialogController progress,
      AppLocalizations l10n,) async {
    final notifier = ref.read(deviceCustomizationProvider.notifier);

    progress.update(l10n.saving_ellipsis);
    try {
      await notifier.saveRemote();
      progress.success(l10n.settings_saved);
      await Future.delayed(const Duration(milliseconds: 600));
    } catch (e) {
      progress.error(e.toString());
      await Future.delayed(const Duration(milliseconds: 1200));
      rethrow;
    }
  }

  Future<void> _saveRemote() async {
    final l10n = context.l10n;
    final state = ref.read(deviceCustomizationProvider);

    if (state.isSaving) return;

    final deviceId = widget.displayDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      _safelyShowToast(l10n.missing_device_id_save);
      return;
    }

    final progress = await showProgressDialog(
      context,
      initialMessage: l10n.saving_ellipsis,
    );
    try {
      await _saveRemoteWithProgress(progress, l10n);
    } catch (e, st) {
      AppLog.instance.error('[device_edit_page][_handleSave] error',
          error: e, stackTrace: st);
    } finally {
      if (mounted) {
        progress.close();
      }
    }
  }

  /// 恢复默认
  Future<void> _resetToDefault() async {
    ref.read(deviceCustomizationProvider.notifier).resetToDefault();

    setState(() {
      _wallpaperPageIndex = 0;
      _wallpaperPage = 0;
    });

    if (_wallpaperController?.hasClients == true) {
      _wallpaperController!.jumpToPage(0);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _wallpaperController?.hasClients == true) {
          _wallpaperController!.jumpToPage(0);
        }
      });
    }

    await _saveRemote();
  }

  /// 上传壁纸
  Future<void> _handleUploadTap() async {
    final l10n = context.l10n; // ✅ 缓存，后面别再用 context.l10n
    final notifier = ref.read(deviceCustomizationProvider.notifier);
    final state = ref.read(deviceCustomizationProvider);

    if (state.isUploading) return;

    final deviceId = widget.displayDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      _safelyShowToast(l10n.missing_device_id_upload_wallpaper);
      return;
    }

    final hasPermission = await _ensurePhotoPermission();
    if (!hasPermission) {
      _safelyShowToast(l10n.photo_permission_required_upload_wallpaper);
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
    if (!mounted || picked == null || picked.isEmpty) return;

    List<XFile> selected = picked;
    if (picked.length > maxCount) {
      // 部分平台可能未严格限制，再次兜底截取并提示。
      _safelyShowToast(l10n.wallpaper_upload_limit(maxCount));
      selected = picked.take(maxCount).toList();
    }

    for (final file in selected) {
      final validationMessage = _validateImageFormat(file, l10n);
      if (validationMessage != null) {
        _safelyShowToast(validationMessage);
        return;
      }
    }

    final progress = await showProgressDialog(
      context,
      initialMessage: '',
    );
    try {
      final processedList = <ImageProcessingResult>[];
      for (var i = 0; i < selected.length; i++) {
        if (mounted) {
          progress.update(l10n.wallpaper_processing_index_total(
            i + 1,
            selected.length,
          ));
        }
        final processed = await _processSingleWallpaper(
          selected[i],
          index: i,
          l10n: l10n,
        ).timeout(
          _singleProcessingTimeout,
          onTimeout: () =>
          throw TimeoutException(
            l10n.wallpaper_processing_timeout_index(i + 1),
          ),
        );
        processedList.add(processed);
      }
      if (mounted) {
        progress.update(l10n.wallpaper_uploading_ellipsis);
      }
      await notifier.applyProcessedWallpapers(
        deviceId: deviceId,
        processedList: processedList,
      );
      if (mounted) {
        _setCurrentWallpaperLocal(1);
        await _saveRemoteWithProgress(progress, l10n);
      }
    } catch (error) {
      if (mounted) {
        final message = switch (error) {
          TimeoutException _ =>
          error.message ?? l10n.image_processing_timeout_hint,
          String s when s.isNotEmpty => s,
          ImageProcessingException e => e.message,
          _ => l10n.image_processing_failed(error.toString()),
        };
        progress.error(message);
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    } finally {
      if (mounted) {
        progress.close();
      }
    }
  }

  Future<ImageProcessingResult> _processSingleWallpaper(XFile file, {
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

  /// 删除壁纸
  Future<void> _handleDeleteWallpaper() async {
    final l10n = context.l10n;
    final state = ref.read(deviceCustomizationProvider);
    final notifier = ref.read(deviceCustomizationProvider.notifier);

    if (state.isUploading) return;

    final deviceId = widget.displayDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      _safelyShowToast(l10n.missing_device_id_delete_wallpaper);
      return;
    }

    await notifier.deleteWallpaper(deviceId);
    _setCurrentWallpaperLocal(0);
    await _saveRemote();
  }

  void _setCurrentWallpaperLocal(int index) {
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

  /// 设为当前壁纸
  Future<void> _setCurrentWallpaper(int index) async {
    _setCurrentWallpaperLocal(index);
    await _saveRemote();
  }

  /// 设置布局
  Future<void> _setLayout(String value, int index) async {
    final notifier = ref.read(deviceCustomizationProvider.notifier);

    if (_layoutValue == value) return;
    notifier.updateLayout(value);

    await _saveRemote();
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

  void _safelyShowToast(String message) {
    if (!mounted) return;
    Fluttertoast.showToast(
      msg: message,
      gravity: ToastGravity.BOTTOM,
    );
  }

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
            _safelyShowToast(l10n.device_edit_load_failed(error.toString()));
      });
    });
  }

  @override
  void dispose() {
    _wallpaperController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(l10n.edit_device),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildWallpaperSelector(),
              const SizedBox(height: 12),
              _buildLayoutSection(),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _resetToDefault,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.onSurface,
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: Text(
                  l10n.reset_to_default,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWallpaperSelector() {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final state = ref.watch(deviceCustomizationProvider);
    final isUploading = state.isUploading;
    final isBusy = isUploading;

    final screenWidth = MediaQuery.of(context).size.width;
    final tileWidth = screenWidth * _wallpaperViewportFraction;
    final imageHeight = tileWidth / _wallpaperAspectRatio;

    const double verticalGap = 10;

    final isViewingCustom = _wallpaperPageIndex == 1;
    final isCurrentView = _selectedWallpaperPageIndex == _wallpaperPageIndex;
    _ensureWallpaperController();

    final isViewingEmptyCustom = isViewingCustom && !_hasCustomWallpaper;

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
                const SizedBox(height: verticalGap),
                _CurrentToggle(
                  currentText: isCurrentView
                      ? l10n.current_label
                      : isViewingEmptyCustom
                      ? l10n.new_wallpaper
                      : l10n.set_as_current,
                  onSetAsCurrent: !isCurrentView && !isViewingEmptyCustom
                      ? () => _setCurrentWallpaper(_wallpaperPageIndex)
                      : null,
                ),
                const SizedBox(height: verticalGap),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 布局区
  Widget _buildLayoutSection() {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    final options = [
      _LayoutOption(
        value: 'default',
        title: l10n.layout_default, // “默认模式”
        subtitle: l10n.layout_default_hint, // 如果不想显示可不传/不显示
        iconAsset: 'assets/images/layout_default_icon.png', // ✅ 左侧图标
      ),
      _LayoutOption(
        value: 'frame',
        title: l10n.layout_frame, // 你要显示成“相册模式”就改 l10n 或直接写死
        subtitle: l10n.layout_frame_hint,
        iconAsset: 'assets/images/layout_frame_icon.png', // ✅ 左侧图标
      ),
    ];

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
                l10n.layout_section_title, // “选择布局”
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            // ✅ 两行列表
            _LayoutChoiceTile(
              title: options[0].title,
              iconAsset: options[0].iconAsset,
              selected: _layoutValue == options[0].value,
              onTap: () => _setLayout(options[0].value, 0),
            ),

            Divider(
              height: 1,
              thickness: 0.8,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey.shade800
                  : Colors.grey.shade300,
              indent: MediaQuery.of(context).size.width / 7, // 左侧留白
            ),

            _LayoutChoiceTile(
              title: options[1].title,
              iconAsset: options[1].iconAsset,
              selected: _layoutValue == options[1].value,
              onTap: () => _setLayout(options[1].value, 1),
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

  /// 壁纸区
  Widget _wallpaperImageWidget(
    int index,
    DeviceCustomizationState state, {
    required bool isBusy,
  }) {
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
                : _buildUploadPlaceholder(isBusy: isBusy),
          ],
        ),
    };
  }

  /// 自定义壁纸：预览
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
        if (paths.length > 1) ...[
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l10n.wallpaper_count(paths.length),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        ],
        Positioned(
          right: 10,
          bottom: 10,
          child: GestureDetector(
            onTap: _handleDeleteWallpaper,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l10n.delete,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        )
      ],
    );
  }

  /// 自定义壁纸：占位
  Widget _buildUploadPlaceholder({required bool isBusy}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Center(
        child: InkWell(
          onTap: isBusy ? null : _handleUploadTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: Color(0xFF2F6BFF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.add,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _LayoutOption {
  final String value;
  final String title;
  final String subtitle;
  final String iconAsset;

  const _LayoutOption({
    required this.value,
    required this.title,
    required this.subtitle,
    required this.iconAsset,
  });
}

class _CurrentToggle extends StatelessWidget {
  final String currentText;
  final VoidCallback? onSetAsCurrent;

  const _CurrentToggle({
    required this.currentText,
    this.onSetAsCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: onSetAsCurrent != null
              ? FilledButton(
            onPressed: onSetAsCurrent,
            key: const ValueKey('set'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE8F0FE), // 浅蓝背景
              foregroundColor: const Color(0xFF1A73E8), // 蓝色文字
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
            ),
            child: Text(
              currentText,
              style: const TextStyle(fontSize: 16),
            ),
          )
              : Text(
            currentText,
                  key: const ValueKey('current'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
        ),
      ),
    );
  }
}

class _LayoutChoiceTile extends StatelessWidget {
  final String title;
  final String iconAsset;
  final bool selected;
  final VoidCallback onTap;

  const _LayoutChoiceTile({
    required this.title,
    required this.iconAsset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE), // 淡蓝色背景
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  iconAsset,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 16),

            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 16),
              ),
            ),

            // 右侧选中态：圆形勾选
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      selected ? theme.colorScheme.primary : theme.dividerColor,
                  width: 1,
                ),
                color:
                    selected ? theme.colorScheme.primary : Colors.transparent,
              ),
              child: selected
                  ? Icon(
                      Icons.check,
                      size: 16,
                      color: theme.colorScheme.onPrimary,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
