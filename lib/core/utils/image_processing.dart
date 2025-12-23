import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../log/app_log.dart';

class ImageProcessingResult {
  final Uint8List bytes;
  final String mimeType;
  final String extension;
  final int width;
  final int height;
  final int sizeBytes;

  const ImageProcessingResult({
    required this.bytes,
    required this.mimeType,
    required this.extension,
    required this.width,
    required this.height,
    required this.sizeBytes,
  });
}

class ImageProcessingException implements Exception {
  final String message;

  ImageProcessingException(this.message);

  @override
  String toString() => message;
}

const DEFAULT_MAX_BYTES = 300 * 1024; // 压缩到300KB

class WallpaperImageProcessor {
  static const List<String> supportedExtensions = ['.jpg', '.jpeg', '.png'];

  static bool isSupportedExtension(String value) {
    final ext = _normalizedExtension(value);
    if (ext == null) return false;
    return supportedExtensions.contains(ext);
  }

  static String? _normalizedExtension(String? path) {
    if (path == null || path.isEmpty) return null;
    final normalized = path.trim();
    if (normalized.isEmpty) return null;

    // Handle direct extensions like ".jpg" or "jpg" without re-parsing as a file path.
    final hasSeparator = normalized.contains('/') || normalized.contains('\\');
    if (!hasSeparator) {
      if (normalized.startsWith('.')) {
        return normalized.toLowerCase();
      }
      if (!normalized.contains('.')) {
        return '.${normalized.toLowerCase()}';
      }
    }

    final ext = p.extension(normalized);
    if (ext.isEmpty) return null;
    return ext.toLowerCase();
  }

  static const int _targetW = 1920;
  static const int _targetH = 1080;
  static const double _targetRatio = 16 / 9;

  static img.Image _fit16x9AndResize(img.Image src) {
    final srcRatio = src.width / src.height;
    img.Image cropped = src;

    if (srcRatio > _targetRatio) {
      // 太宽：裁宽
      final newW = (src.height * _targetRatio).round();
      final x = ((src.width - newW) / 2).round();
      cropped = img.copyCrop(src, x: x, y: 0, width: newW, height: src.height);
    } else if (srcRatio < _targetRatio) {
      // 太高：裁高
      final newH = (src.width / _targetRatio).round();
      final y = ((src.height - newH) / 2).round();
      cropped = img.copyCrop(src, x: 0, y: y, width: src.width, height: newH);
    }

    // 教条一点：壁纸就是 1920x1080，直接输出这个分辨率（速度最稳）
    if (cropped.width == _targetW && cropped.height == _targetH) return cropped;

    return img.copyResize(
      cropped,
      width: _targetW,
      height: _targetH,
      interpolation: img.Interpolation.average,
    );
  }

  /// 仅压缩到指定大小以内
  static Future<ImageProcessingResult> processWallpaper({
    required Uint8List bytes,
    String? sourcePath,
    int maxBytes = DEFAULT_MAX_BYTES,
  }) async {
    return _processWallpaper(
      bytes: bytes,
      sourcePath: sourcePath,
      maxBytes: maxBytes,
    );
  }

  /// 在隔离线程中处理壁纸，避免主线程卡顿。
  static Future<ImageProcessingResult> processWallpaperInIsolate({
    required Uint8List bytes,
    String? sourcePath,
    int maxBytes = DEFAULT_MAX_BYTES,
  }) {
    final params = <String, Object?>{
      'bytes': bytes,
      'sourcePath': sourcePath,
      'maxBytes': maxBytes,
    };
    return compute(_processWallpaperOnIsolate, params).then(
      (value) => ImageProcessingResult(
        bytes: value['bytes'] as Uint8List,
        mimeType: value['mimeType'] as String,
        extension: value['extension'] as String,
        width: value['width'] as int,
        height: value['height'] as int,
        sizeBytes: value['sizeBytes'] as int,
      ),
    );
  }

  /// 自动处理（优先隔离线程，对 HEIC/WebP 等不支持的格式走 UI 解码兜底）。
  static Future<ImageProcessingResult> processWallpaperAuto({
    required Uint8List bytes,
    String? sourcePath,
    int maxBytes = DEFAULT_MAX_BYTES,
  }) async {
    final format = _detectFormat(bytes);
    final ext = _normalizedExtension(sourcePath);
    final isPreferred =
        format == 'jpeg' || format == 'png' || (ext != null && isSupportedExtension(ext));

    if (isPreferred) {
      return processWallpaperInIsolate(
        bytes: bytes,
        sourcePath: sourcePath,
        maxBytes: maxBytes,
      );
    }

    // HEIC/WebP 等用 UI 解码兜底；若失败再抛出详细错误。
    return _processWithUiDecode(
      bytes: bytes,
      sourcePath: sourcePath,
      detectedFormat: format,
      maxBytes: maxBytes,
    );
  }

  @pragma('vm:entry-point')
  static Map<String, Object> _processWallpaperOnIsolate(
    Map<String, Object?> params,
  ) {
    final processed = _processWallpaper(
      bytes: params['bytes'] as Uint8List,
      sourcePath: params['sourcePath'] as String?,
      maxBytes: params['maxBytes'] as int,
    );

    return {
      'bytes': processed.bytes,
      'mimeType': processed.mimeType,
      'extension': processed.extension,
      'width': processed.width,
      'height': processed.height,
      'sizeBytes': processed.sizeBytes,
    };
  }

  static ImageProcessingResult _processWallpaper({
    required Uint8List bytes,
    String? sourcePath,
    required int maxBytes,
  }) {
    final ext = _normalizedExtension(sourcePath);
    if (ext != null && !isSupportedExtension(ext)) {
      throw ImageProcessingException('不支持$ext, 仅支持 JPG / PNG 格式的图片');
    }

    final detectedFormat = _detectFormat(bytes);

    img.Decoder? decoder;
    try {
      decoder = img.findDecoderForData(bytes);
    } catch (_) {
      decoder = null;
    }

    if (decoder == null) {
      throw ImageProcessingException(
        '无法解析图片：格式不支持或文件损坏（检测到: $detectedFormat，扩展名: ${ext ?? '未知'}）',
      );
    }

    img.Image? decoded;
    img.Image? fitted;
    try {
      decoded = decoder.decode(bytes);
      fitted = _fit16x9AndResize(decoded!);
    } catch (error, stackTrace) {
      _logProcessFailure(
        sourcePath: sourcePath,
        bytes: bytes.length,
        ext: ext,
        message: 'decode-failed($detectedFormat)',
        error: error,
        stackTrace: stackTrace,
      );
      throw ImageProcessingException(
        '无法解析图片（检测到: $detectedFormat，扩展名: ${ext ?? '未知'}），可能是 CMYK/渐进式 JPEG、WebP/HEIC 等，请导出为标准 JPG/PNG 后重试',
      );
    }

    if (fitted == null) {
      _logProcessFailure(
        sourcePath: sourcePath,
        bytes: bytes.length,
        ext: ext,
        message: 'decode-null($detectedFormat)',
      );
      throw ImageProcessingException('无法解析图片');
    }

    return _processDecodedImage(
      fitted: fitted,
      originalBytes: bytes,
      originalExt: ext,
      maxBytes: maxBytes,
    );
  }

  static _CompressionResult _compressToLimit(img.Image image, int maxBytes) {
    int lo = 45;
    int hi = 92;

    // 先试 hi：满足直接返回
    Uint8List best = _encodeJpg(image, hi);
    if (best.length <= maxBytes) {
      return _CompressionResult(best, image.width, image.height);
    }

    Uint8List? ok;
    for (int i = 0; i < 8 && lo <= hi; i++) {
      final mid = (lo + hi) >> 1;
      final encoded = _encodeJpg(image, mid);

      if (encoded.length <= maxBytes) {
        ok = encoded; // mid 可行，尝试更高质量
        lo = mid + 1;
      } else {
        hi = mid - 1; // 太大，降质量
      }
    }

    ok ??= _encodeJpg(image, 45);
    return _CompressionResult(ok, image.width, image.height);
  }

  static Uint8List _encodeJpg(img.Image image, int quality) {
    return Uint8List.fromList(
      img.encodeJpg(image, quality: quality),
    );
  }

  static ImageProcessingResult _processDecodedImage({
    required img.Image fitted,
    required Uint8List originalBytes,
    String? originalExt,
    required int maxBytes,
  }) {
    final compressed = _compressToLimit(fitted, maxBytes);

    return ImageProcessingResult(
      bytes: compressed.bytes,
      mimeType: 'image/jpeg',
      extension: '.jpg',
      width: compressed.width,
      height: compressed.height,
      sizeBytes: compressed.bytes.length,
    );
  }

  static String _detectFormat(Uint8List bytes) {
    if (bytes.length < 12) return 'unknown';
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'jpeg';
    }
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'png';
    }
    // RIFF .... WEBP
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    // GIF
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return 'gif';
    }
    // BMP
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'bmp';
    }
    // HEIC/HEIF/AVIF family (ftyp....)
    if (bytes[4] == 0x66 &&
        bytes[5] == 0x74 &&
        bytes[6] == 0x79 &&
        bytes[7] == 0x70) {
      final type = String.fromCharCodes(bytes.sublist(8, 12));
      if (type == 'heic' ||
          type == 'heix' ||
          type == 'hevc' ||
          type == 'hevx') {
        return 'heic';
      }
      if (type == 'mif1' || type == 'msf1') {
        return 'heif';
      }
      if (type == 'avif' || type == 'avis') {
        return 'avif';
      }
    }
    return 'unknown';
  }

  static Future<ImageProcessingResult> _processWithUiDecode({
    required Uint8List bytes,
    required String detectedFormat,
    String? sourcePath,
    required int maxBytes,
  }) async {
    ui.Image uiImage;
    try {
      uiImage = await _decodeWithUi(bytes);
    } catch (error, stackTrace) {
      _logProcessFailure(
        sourcePath: sourcePath,
        bytes: bytes.length,
        ext: _normalizedExtension(sourcePath),
        message: 'ui-decode-failed($detectedFormat)',
        error: error,
        stackTrace: stackTrace,
      );
      throw ImageProcessingException(
        '无法解析图片（检测到: $detectedFormat），请导出为标准 JPG/PNG 后重试',
      );
    }

    final byteData =
        await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw ImageProcessingException(
        '无法解析图片（检测到: $detectedFormat），请导出为标准 JPG/PNG 后重试',
      );
    }

    final rgba = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );

    // ✅ 用 raw RGBA 直接构造 img.Image（不要 decodePng）
    final decoded = img.Image.fromBytes(
      width: uiImage.width,
      height: uiImage.height,
      bytes: rgba.buffer,
      bytesOffset: rgba.offsetInBytes,
      // image 包新版本一般用 numChannels；旧版本用 format
      numChannels: 4,
    );

    // ✅ UI decode 路径也要裁剪+缩放到目标分辨率
    final fitted = _fit16x9AndResize(decoded);

    return _processDecodedImage(
      fitted: fitted,
      originalBytes: bytes, // 这里保留原始输入 bytes 仅用于日志也行
      originalExt: '.png', // 这里其实已经不重要了，最终都会输出 jpg
      maxBytes: maxBytes,
    );
  }

  static Future<ui.Image> _decodeWithUi(
    Uint8List bytes,
  ) {
    return ui.instantiateImageCodec(bytes).then(
      (codec) => codec.getNextFrame().then((frame) => frame.image),
    );
  }

  static void _logProcessFailure({
    String? sourcePath,
    String? message,
    int? bytes,
    String? ext,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final details =
        'source:${sourcePath ?? ''} bytes:${bytes ?? 0} ext:${ext ?? ''} errorType:${error?.runtimeType.toString() ?? ''}';
    AppLog.instance.warning(
      'Wallpaper process failed: $message | $details',
      tag: 'ImageProcessing',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class _CompressionResult {
  final Uint8List bytes;
  final int width;
  final int height;

  _CompressionResult(this.bytes, this.width, this.height);
}
