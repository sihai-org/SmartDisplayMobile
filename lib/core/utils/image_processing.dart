import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

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

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw ImageProcessingException('无法解析图片');
    }

    final cropped = _cropToAspect(decoded, 16 / 9);
    final resized = img.copyResize(
      cropped,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.cubic,
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

  static _CompressionResult _compressToLimit(
    img.Image image,
    int maxBytes,
  ) {
    int quality = 90;
    Uint8List encoded = Uint8List.fromList(
      img.encodeJpg(image, quality: quality),
    );

    while (encoded.length > maxBytes && quality > 50) {
      quality -= 10;
      encoded = Uint8List.fromList(
        img.encodeJpg(image, quality: quality),
      );
    }

    if (encoded.length <= maxBytes) {
      return _CompressionResult(encoded, image.width, image.height);
    }

    // 如果质量降低后仍超出限制，则尝试按比例缩放后再压缩。
    int currentWidth = image.width;
    int currentHeight = image.height;
    int currentQuality = quality;
    img.Image currentImage = image;

    while (encoded.length > maxBytes &&
        currentWidth > 320 &&
        currentHeight > 180) {
      final scale = math.sqrt(maxBytes / encoded.length).clamp(0.35, 0.95);
      currentWidth =
          ((currentWidth * scale).round()).clamp(320, image.width).toInt();
      currentHeight =
          ((currentHeight * scale).round()).clamp(180, image.height).toInt();

      currentImage = img.copyResize(
        currentImage,
        width: currentWidth,
        height: currentHeight,
        interpolation: img.Interpolation.cubic,
      );

      encoded = Uint8List.fromList(
        img.encodeJpg(currentImage, quality: currentQuality),
      );

      if (encoded.length > maxBytes && currentQuality > 35) {
        currentQuality = math.max(35, currentQuality - 5);
        encoded = Uint8List.fromList(
          img.encodeJpg(currentImage, quality: currentQuality),
        );
      } else {
        break;
      }
    }

    return _CompressionResult(encoded, currentWidth, currentHeight);
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
