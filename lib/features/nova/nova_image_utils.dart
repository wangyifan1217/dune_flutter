import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';

class NovaNormalizedImage {
  const NovaNormalizedImage({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

/// 对齐 WebView `normalizeImageForVision`：最长边 1568px，JPEG 82% 质量。
Future<NovaNormalizedImage> normalizeImageForVision(
  Uint8List bytes, {
  String fileName = 'image.jpg',
}) async {
  final fallbackMime = lookupMimeType(fileName) ?? 'image/jpeg';
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return NovaNormalizedImage(bytes: bytes, fileName: fileName, mimeType: fallbackMime);
    }
    const maxDim = 1568;
    final w = decoded.width;
    final h = decoded.height;
    final longest = w > h ? w : h;
    final resized = longest > maxDim
        ? img.copyResize(
            decoded,
            width: w >= h ? maxDim : (w * maxDim / h).round(),
            height: h > w ? maxDim : (h * maxDim / w).round(),
          )
        : decoded;
    final jpeg = img.encodeJpg(resized, quality: 82);
    final base = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return NovaNormalizedImage(
      bytes: Uint8List.fromList(jpeg),
      fileName: '$base.jpg',
      mimeType: 'image/jpeg',
    );
  } catch (_) {
    return NovaNormalizedImage(bytes: bytes, fileName: fileName, mimeType: fallbackMime);
  }
}
