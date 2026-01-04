import 'package:meta/meta.dart';
import 'package:smart_display_mobile/core/constants/enum.dart';

/// 用户在手机端为设备配置的个性化数据。
@immutable
class DeviceCustomization {
  /// 用户上传的自定义壁纸信息列表，空数组表示没上传
  final List<CustomWallpaperInfo> wallpaperInfos;

  final WallpaperType wallpaper;

  final LayoutType layout;

  const DeviceCustomization({
    this.wallpaperInfos = const [],
    this.wallpaper = WallpaperType.defaultWallpaper,
    this.layout = LayoutType.defaultLayout,
  });

  const DeviceCustomization.empty()
    : wallpaperInfos = const [],
      wallpaper = WallpaperType.defaultWallpaper,
      layout = LayoutType.defaultLayout;

  /// 没有壁纸 && 没有布局
  bool get isLikeDefault =>
      wallpaper == WallpaperType.defaultWallpaper &&
      wallpaperInfos.isEmpty &&
      layout == LayoutType.defaultLayout;

  DeviceCustomization copyWith({
    List<CustomWallpaperInfo>? wallpaperInfos,
    WallpaperType? wallpaper,
    LayoutType? layout,
  }) {
    return DeviceCustomization(
      wallpaperInfos: wallpaperInfos ?? this.wallpaperInfos,
      wallpaper: wallpaper ?? this.wallpaper,
      layout: layout ?? this.layout,
    );
  }

  Map<String, dynamic> toJson() => {
    'wallpaper_infos': wallpaperInfos.map((e) => e.toJson()).toList(),
    'wallpaper': wallpaper.value,
    'layout': layout.value,
  };

  static DeviceCustomization fromJson(Map<String, dynamic> json) {
    // 兼容本地旧字段
    final infosVal =
        json['wallpaper_infos'] ??
        json['wallpaperInfos'] ??
        json['customWallpaperInfos'];

    final wallpaperVal = json['wallpaper'];
    final layoutVal = json['layout'];

    List<CustomWallpaperInfo> infos = (infosVal is List)
        ? infosVal
              .map((item) => CustomWallpaperInfo.fromJson(item))
              .whereType<CustomWallpaperInfo>()
              .toList()
        : const <CustomWallpaperInfo>[];

    return DeviceCustomization(
      wallpaperInfos: infos.take(maxCustomWallpapers).toList(growable: false),
      wallpaper: WallpaperType.fromString(wallpaperVal),
      layout: LayoutType.fromString(layoutVal),
    );
  }

  /// 最多允许的自定义壁纸数量。
  static const int maxCustomWallpapers = 5;
}

/// 用户上传的壁纸信息（所有字段必填，允许值为空字符串代表无效）。
@immutable
class CustomWallpaperInfo {
  /// 存储后的对象 key（必填）。
  final String key;
  final String md5;
  final String mime;

  /// 用户上传时，该字段为''
  final String downloadUrl;

  const CustomWallpaperInfo({
    required this.key,
    required this.md5,
    required this.mime,
    required this.downloadUrl,
  });

  bool get canDownload => downloadUrl.isNotEmpty;

  static CustomWallpaperInfo fromJson(Map<String, dynamic> json) {
    final keyVal = json['key'];
    final md5Val = json['md5'];
    final mimeVal = json['mime'];
    final downloadUrlVal = json['downloadUrl'];

    return CustomWallpaperInfo(
      key: _normalizeString(keyVal),
      md5: _normalizeString(md5Val),
      mime: _normalizeString(mimeVal),
      downloadUrl: _normalizeString(downloadUrlVal),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'md5': md5,
    'mime': mime,
    'downloadUrl': downloadUrl,
  };

  static String _normalizeString(String? value) {
    if (value == null) return '';
    return value.trim();
  }
}
