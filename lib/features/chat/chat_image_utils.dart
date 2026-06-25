import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 聊天图片压缩产物：用于在会话中展示的缩略/预览图。
class ChatImagePreview {
  const ChatImagePreview({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}

class _PreviewRequest {
  const _PreviewRequest(this.bytes, this.maxDim, this.quality);

  final Uint8List bytes;
  final int maxDim;
  final int quality;
}

Uint8List? _encodePreview(_PreviewRequest req) {
  final decoded = img.decodeImage(req.bytes);
  if (decoded == null) return null;
  final w = decoded.width;
  final h = decoded.height;
  final longest = w > h ? w : h;
  final resized = longest > req.maxDim
      ? img.copyResize(
          decoded,
          width: w >= h ? req.maxDim : (w * req.maxDim / h).round(),
          height: h > w ? req.maxDim : (h * req.maxDim / w).round(),
        )
      : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: req.quality));
}

/// 生成用于会话内展示的压缩预览图（最长边 [maxDim]px，JPEG [quality]% 质量）。
///
/// 返回 null 表示无需/无法生成（解码失败，或压缩后体积反而更大），
/// 调用方应回退为直接使用原图展示。解码/编码在后台 isolate 执行，避免卡顿。
Future<ChatImagePreview?> buildChatImagePreview(
  Uint8List bytes, {
  String fileName = 'image.jpg',
  int maxDim = 1280,
  int quality = 70,
}) async {
  try {
    final jpeg = await compute(
      _encodePreview,
      _PreviewRequest(bytes, maxDim, quality),
    );
    if (jpeg == null || jpeg.isEmpty) return null;
    // 压缩后没有更小（例如本身就是很小的图）就不生成预览，避免无意义的二次上传。
    if (jpeg.length >= bytes.length) return null;
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    return ChatImagePreview(
      bytes: jpeg,
      fileName: '$base-preview.jpg',
      mimeType: 'image/jpeg',
    );
  } catch (_) {
    return null;
  }
}
