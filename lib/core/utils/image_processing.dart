import 'dart:async';
import 'dart:math' as math;
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

  /// 裁剪为 16:9、缩放到 1980x1080，并压缩到指定大小以内（默认 200KB）。
  static Future<ImageProcessingResult> processWallpaper({
    required Uint8List bytes,
    String? sourcePath,
    int targetWidth = 1980,
    int targetHeight = 1080,
    int maxBytes = 200 * 1024,
  }) async {
    return _processWallpaper(
      bytes: bytes,
      sourcePath: sourcePath,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      maxBytes: maxBytes,
    );
  }

  /// 在隔离线程中处理壁纸，避免主线程卡顿。
  static Future<ImageProcessingResult> processWallpaperInIsolate({
    required Uint8List bytes,
    String? sourcePath,
    int targetWidth = 1980,
    int targetHeight = 1080,
    int maxBytes = 200 * 1024,
  }) {
    final params = <String, Object?>{
      'bytes': bytes,
      'sourcePath': sourcePath,
      'targetWidth': targetWidth,
      'targetHeight': targetHeight,
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
    int targetWidth = 1980,
    int targetHeight = 1080,
    int maxBytes = 200 * 1024,
  }) async {
    final format = _detectFormat(bytes);
    final ext = _normalizedExtension(sourcePath);
    final isPreferred =
        format == 'jpeg' || format == 'png' || (ext != null && isSupportedExtension(ext));

    if (isPreferred) {
      return processWallpaperInIsolate(
        bytes: bytes,
        sourcePath: sourcePath,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
        maxBytes: maxBytes,
      );
    }

    // HEIC/WebP 等用 UI 解码兜底；若失败再抛出详细错误。
    return _processWithUiDecode(
      bytes: bytes,
      sourcePath: sourcePath,
      detectedFormat: format,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
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
      targetWidth: params['targetWidth'] as int,
      targetHeight: params['targetHeight'] as int,
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
    required int targetWidth,
    required int targetHeight,
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
    try {
      decoded = decoder.decode(bytes);
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

    if (decoded == null) {
      _logProcessFailure(
        sourcePath: sourcePath,
        bytes: bytes.length,
        ext: ext,
        message: 'decode-null($detectedFormat)',
      );
      throw ImageProcessingException('无法解析图片');
    }

    return _processDecodedImage(
      decoded: decoded,
      originalBytes: bytes,
      originalExt: ext,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      maxBytes: maxBytes,
    );
  }

  static _CompressionResult _compressToLimit(
    img.Image image,
    int maxBytes,
  ) {
    int quality = 82;
    Uint8List encoded = _encodeJpg(image, quality);

    if (encoded.length <= maxBytes) {
      return _CompressionResult(encoded, image.width, image.height);
    }

    // 预估一次缩放比例，减少多次尝试带来的耗时。
    final scale =
        math.sqrt(maxBytes / encoded.length).clamp(0.35, 0.95).toDouble();
    int targetWidth =
        (image.width * scale).round().clamp(320, image.width).toInt();
    int targetHeight =
        (image.height * scale).round().clamp(180, image.height).toInt();

    if (scale < 0.98) {
      image = img.copyResize(
        image,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.linear,
      );
      encoded = _encodeJpg(image, quality);
    }

    while (encoded.length > maxBytes && quality > 55) {
      quality -= 7;
      encoded = _encodeJpg(image, quality);
    }

    // 如果仍然超出，做一次额外缩放兜底，但不做过多迭代以保持速度。
    if (encoded.length > maxBytes &&
        image.width > 480 &&
        image.height > 270) {
      final secondaryScale =
          math.sqrt(maxBytes / encoded.length).clamp(0.45, 0.9).toDouble();
      targetWidth =
          (image.width * secondaryScale).round().clamp(320, image.width).toInt();
      targetHeight = (image.height * secondaryScale)
          .round()
          .clamp(180, image.height)
          .toInt();

      image = img.copyResize(
        image,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.linear,
      );
      encoded = _encodeJpg(image, math.max(55, quality - 5));
    }

    return _CompressionResult(encoded, image.width, image.height);
  }

  static Uint8List _encodeJpg(img.Image image, int quality) {
    return Uint8List.fromList(
      img.encodeJpg(image, quality: quality),
    );
  }

  static String _mimeForExt(String ext) {
    return ext.toLowerCase() == '.png' ? 'image/png' : 'image/jpeg';
  }

  static ImageProcessingResult _processDecodedImage({
    required img.Image decoded,
    required Uint8List originalBytes,
    String? originalExt,
    required int targetWidth,
    required int targetHeight,
    required int maxBytes,
  }) {
    final ext = originalExt;
    if (originalBytes.length <= maxBytes &&
        ext != null &&
        isSupportedExtension(ext)) {
      return ImageProcessingResult(
        bytes: originalBytes,
        mimeType: _mimeForExt(ext),
        extension: ext,
        width: decoded.width,
        height: decoded.height,
        sizeBytes: originalBytes.length,
      );
    }

    final cropped = _cropToAspect(decoded, 16 / 9);
    final resized = img.copyResize(
      cropped,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.linear,
    );

    final compressed = _compressToLimit(resized, maxBytes);

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
    required int targetWidth,
    required int targetHeight,
    required int maxBytes,
  }) async {
    ui.Image uiImage;
    try {
      uiImage = await _decodeWithUi(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
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
        await uiImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw ImageProcessingException(
        '无法解析图片（检测到: $detectedFormat），请导出为标准 JPG/PNG 后重试',
      );
    }

    final pngBytes = Uint8List.view(
      byteData.buffer,
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) {
      throw ImageProcessingException(
        '无法解析图片（检测到: $detectedFormat），请导出为标准 JPG/PNG 后重试',
      );
    }

    return _processDecodedImage(
      decoded: decoded,
      originalBytes: pngBytes,
      originalExt: '.png', // 已经转成 PNG
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      maxBytes: maxBytes,
    );
  }

  static Future<ui.Image> _decodeWithUi(
    Uint8List bytes, {
    int? targetWidth,
    int? targetHeight,
  }) {
    return ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    ).then(
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

  static img.Image _cropToAspect(img.Image image, double targetAspect) {
    final currentAspect = image.width / image.height;
    if ((currentAspect - targetAspect).abs() < 0.001) {
      return image;
    }

    if (currentAspect > targetAspect) {
      final targetWidth = (image.height * targetAspect).round();
      final offsetX = ((image.width - targetWidth) / 2).round();
      return img.copyCrop(
        image,
        x: offsetX,
        y: 0,
        width: targetWidth,
        height: image.height,
      );
    } else {
      final targetHeight = (image.width / targetAspect).round();
      final offsetY = ((image.height - targetHeight) / 2).round();
      return img.copyCrop(
        image,
        x: 0,
        y: offsetY,
        width: image.width,
        height: targetHeight,
      );
    }
  }
}

class _CompressionResult {
  final Uint8List bytes;
  final int width;
  final int height;

  _CompressionResult(this.bytes, this.width, this.height);
}
