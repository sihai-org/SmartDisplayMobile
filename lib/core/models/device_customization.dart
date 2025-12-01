import 'package:meta/meta.dart';

/// 用户在手机端为设备配置的个性化数据。
///
/// - 壁纸：为空代表使用设备默认壁纸；否则保存用户上传的图片对象。
/// - 布局：为空或 `default` 代表默认布局；`frame` 代表相框布局。
@immutable
class DeviceCustomization {
  /// 自定义壁纸信息；为空时表示使用默认壁纸。
  final WallpaperInfo? wallpaper;

  /// 布局标识：`default` 或 `frame`；为空时等同于 `default`。
  final String? layout;

  const DeviceCustomization({
    this.wallpaper,
    this.layout,
  });

  const DeviceCustomization.empty()
      : wallpaper = null,
        layout = null;

  /// 当前布局（若为空则返回默认值）。
  String get effectiveLayout =>
      (layout == null || layout!.isEmpty) ? defaultLayout : layout!;

  /// 是否存在用户自定义壁纸。
  bool get hasCustomWallpaper => wallpaper?.hasData ?? false;

  DeviceCustomization copyWith({
    WallpaperInfo? wallpaper,
    String? layout,
  }) {
    return DeviceCustomization(
      wallpaper: wallpaper ?? this.wallpaper,
      layout: layout ?? this.layout,
    );
  }

  /// 归一化空字符串为 null，便于存储和比较。
  DeviceCustomization normalized() {
    final normalizedWallpaper = wallpaper?.normalized();
    final normalizedLayout = _normalizeString(layout);

    return DeviceCustomization(
      wallpaper: (normalizedWallpaper == null || normalizedWallpaper.isEmpty)
          ? null
          : normalizedWallpaper,
      layout: normalizedLayout,
    );
  }

  Map<String, dynamic> toJson() => {
        'wallpaper': wallpaper?.toJson(),
        'layout': layout,
      };

  static DeviceCustomization fromJson(Map<String, dynamic> json) {
    final layoutVal = json['layout'];
    return DeviceCustomization(
      wallpaper: WallpaperInfo.tryFrom(json['wallpaper']),
      layout: _normalizeString(layoutVal is String ? layoutVal : layoutVal?.toString()),
    ).normalized();
  }

  /// 默认布局值；为空或该值都视作默认。
  static const String defaultLayout = 'default';

  /// 相框布局值。
  static const String frameLayout = 'frame';

  static String? _normalizeString(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// 用户上传的壁纸信息（所有字段必填，允许值为空字符串代表无效）。
@immutable
class WallpaperInfo {
  final String version;
  final String url;
  final String md5;
  final String mime;

  const WallpaperInfo({
    required this.version,
    required this.url,
    required this.md5,
    required this.mime,
  });

  /// URL 非空即认为有自定义壁纸。
  bool get hasData => url.trim().isNotEmpty;

  bool get isEmpty => !hasData;

  WallpaperInfo copyWith({
    String? version,
    String? url,
    String? md5,
    String? mime,
  }) {
    return WallpaperInfo(
      version: version ?? this.version,
      url: url ?? this.url,
      md5: md5 ?? this.md5,
      mime: mime ?? this.mime,
    );
  }

  WallpaperInfo normalized() {
    return WallpaperInfo(
      version: _normalizeString(version) ?? '',
      url: _normalizeString(url) ?? '',
      md5: _normalizeString(md5) ?? '',
      mime: _normalizeString(mime) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'url': url,
        'md5': md5,
        'mime': mime,
      };

  static WallpaperInfo? tryFrom(dynamic value) {
    if (value is Map) {
      return WallpaperInfo(
        version: value['version']?.toString() ?? '',
        url: value['url']?.toString() ?? '',
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
