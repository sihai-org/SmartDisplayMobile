import 'dart:typed_data';
import 'dart:ui' as ui;

class ImageProcessingResult {
  final Uint8List bytes;
  final String mimeType;
  final String extension;
  final int sizeBytes;

  const ImageProcessingResult({
    required this.bytes,
    required this.mimeType,
    required this.extension,
    required this.sizeBytes,
  });
}

class ImageProcessingException implements Exception {
  final String message;

  ImageProcessingException(this.message);

  @override
  String toString() => message;
}

/// 仅做格式识别（magic header）与扩展名白名单判断（可选）
/// 不做任何解码/压缩/裁剪/重编码
class WallpaperImageUtil {
  /// 只做魔数检测：返回 jpeg/png/webp/gif/bmp/heic/heif/avif/unknown
  static String detectFormat(Uint8List bytes) {
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

  static Future<(int width, int height)> readImageSize(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;

    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);

      final w = descriptor.width;
      final h = descriptor.height;

      // 宽高异常也当失败（更稳）
      if (w <= 0 || h <= 0) {
        throw ImageProcessingException('无法识别图片尺寸，请换一张/导出后重试');
      }
      return (w, h);
    } catch (_) {
      throw ImageProcessingException('无法识别图片尺寸，请换一张/导出后重试');
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  static (String mime, String ext) mimeAndExtForFormat(String format) {
    switch (format) {
      case 'jpeg':
        return ('image/jpeg', '.jpg');
      case 'png':
        return ('image/png', '.png');
      case 'webp':
        return ('image/webp', '.webp');
      default:
        return ('application/octet-stream', '');
    }
  }
}
