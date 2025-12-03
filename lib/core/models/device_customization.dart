import 'package:meta/meta.dart';

/// 用户在手机端为设备配置的个性化数据。
///
/// - 壁纸：`wallpaper` 为 `default`/null 使用默认，为 `custom` 使用 `customWallpaperInfo`。
/// - 布局：为空或 `default` 代表默认布局；`frame` 代表相框布局。
@immutable
class DeviceCustomization {
  /// 用户上传的自定义壁纸信息；为空时表示未上传。
  final CustomWallpaperInfo? customWallpaperInfo;

  /// 壁纸选项：`default` 或 `custom`；为空时等同于 `default`。
  final String? wallpaper;

  /// 布局标识：`default` 或 `frame`；为空时等同于 `default`。
  final String? layout;

  const DeviceCustomization({
    this.customWallpaperInfo,
    this.wallpaper,
    this.layout,
  });

  const DeviceCustomization.empty()
      : customWallpaperInfo = null,
        wallpaper = null,
        layout = null;

  /// 当前布局（若为空则返回默认值）。
  String get effectiveLayout =>
      (layout == null || layout!.isEmpty) ? defaultLayout : layout!;

  /// 当前壁纸选项（若为空则返回默认值）。
  String get effectiveWallpaper =>
      (wallpaper == null || wallpaper!.isEmpty) ? defaultWallpaper : wallpaper!;

  /// 是否存在用户自定义壁纸。
  bool get hasCustomWallpaper =>
      effectiveWallpaper == customWallpaper &&
          (customWallpaperInfo?.hasData ?? false);

  /// 用于区分「未传参数」和「显式传 null」的哨兵值。
  static const Object _unset = Object();

  /// 支持：
  /// - 不传字段：保留原值
  /// - 传具体值：更新为该值
  /// - 传 null：将该字段置为 null
  DeviceCustomization copyWith({
    Object? customWallpaperInfo = _unset,
    Object? wallpaper = _unset,
    Object? layout = _unset,
  }) {
    return DeviceCustomization(
      customWallpaperInfo: identical(customWallpaperInfo, _unset)
          ? this.customWallpaperInfo
          : customWallpaperInfo as CustomWallpaperInfo?,
      wallpaper: identical(wallpaper, _unset)
          ? this.wallpaper
          : wallpaper as String?,
      layout: identical(layout, _unset)
          ? this.layout
          : layout as String?,
    );
  }

  /// 归一化空字符串为 null，便于存储和比较。
  DeviceCustomization normalized() {
    final normalizedCustomWallpaper = customWallpaperInfo?.normalized();
    final normalizedLayout = _normalizeLayout(layout);
    final normalizedWallpaper = _normalizeWallpaper(wallpaper);

    return DeviceCustomization(
      customWallpaperInfo:
      (normalizedCustomWallpaper == null || normalizedCustomWallpaper.isEmpty)
          ? null
          : normalizedCustomWallpaper,
      wallpaper: normalizedWallpaper,
      layout: normalizedLayout,
    );
  }

  Map<String, dynamic> toJson() => {
    'customWallpaperInfo': customWallpaperInfo?.toJson(),
    'wallpaper': wallpaper,
    'layout': layout,
  };

  static DeviceCustomization fromJson(Map<String, dynamic> json) {
    final layoutVal = json['layout'];
    final wallpaperField = json['wallpaper'];
    final wallpaperOption = wallpaperField is String
        ? wallpaperField
        : (json['wallpaperOption'] ?? json['wallpaper_option']);
    return DeviceCustomization(
      customWallpaperInfo:
      CustomWallpaperInfo.tryFrom(json['customWallpaperInfo']) ??
          CustomWallpaperInfo.tryFrom(json['wallpaper']) ?? // 兼容旧字段
          CustomWallpaperInfo.tryFrom(json['wallpaper_info']),
      wallpaper: _normalizeWallpaper(wallpaperOption),
      layout: _normalizeLayout(
        layoutVal is String ? layoutVal : layoutVal?.toString(),
      ),
    ).normalized();
  }

  /// 默认布局值；为空或该值都视作默认。
  static const String defaultLayout = 'default';

  /// 相框布局值。
  static const String frameLayout = 'frame';

  /// 默认壁纸选项。
  static const String defaultWallpaper = 'default';

  /// 自定义壁纸选项。
  static const String customWallpaper = 'custom';

  static String? _normalizeWallpaper(dynamic value) {
    final normalized = _normalizeString(value?.toString());
    if (normalized == null) return null;
    final lower = normalized.toLowerCase();
    if (lower == defaultWallpaper) return null;
    if (lower == customWallpaper) return customWallpaper;
    return lower;
  }

  static String? _normalizeLayout(String? value) {
    final normalized = _normalizeString(value);
    if (normalized == null) return null;
    final lower = normalized.toLowerCase();
    if (lower == defaultLayout) return null;
    return lower;
  }

  static String? _normalizeString(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// 用户上传的壁纸信息（所有字段必填，允许值为空字符串代表无效）。
@immutable
class CustomWallpaperInfo {
  /// 存储后的对象 key（必填）。
  final String key;
  final String md5;
  final String mime;

  const CustomWallpaperInfo({
    required this.key,
    required this.md5,
    required this.mime,
  });

  /// key 非空即认为有自定义壁纸。
  bool get hasData => key.trim().isNotEmpty;

  bool get isEmpty => !hasData;

  CustomWallpaperInfo copyWith({
    String? key,
    String? md5,
    String? mime,
  }) {
    return CustomWallpaperInfo(
      key: key ?? this.key,
      md5: md5 ?? this.md5,
      mime: mime ?? this.mime,
    );
  }

  CustomWallpaperInfo normalized() {
    return CustomWallpaperInfo(
      key: _normalizeString(key) ?? '',
      md5: _normalizeString(md5) ?? '',
      mime: _normalizeString(mime) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'md5': md5,
    'mime': mime,
  };

  static CustomWallpaperInfo? tryFrom(dynamic value) {
    if (value is Map) {
      return CustomWallpaperInfo(
        key: (value['key'] ?? value['url'] ?? value['version'] ?? '')
            .toString(),
        md5: value['md5']?.toString() ?? '',
        mime: value['mime']?.toString() ?? '',
      ).normalized();
    }
    return null;
  }

  static String? _normalizeString(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
