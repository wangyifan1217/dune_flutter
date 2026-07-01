import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

/// 微信风格：会话内图片最大宽≈屏宽 32%，最大高≈屏宽 38%（按宽度 cap 竖图）。
Size chatImageBubbleMaxSize(BuildContext context) {
  final screenW = MediaQuery.sizeOf(context).width;
  return Size(screenW * 0.32, screenW * 0.38);
}

/// 按原图比例缩放到上限框内，保证完整可见。
Size chatImageBubbleDisplaySize(
  double sourceWidth,
  double sourceHeight, {
  required double maxWidth,
  required double maxHeight,
}) {
  if (sourceWidth <= 0 || sourceHeight <= 0) {
    return Size(maxWidth, maxWidth * 0.75);
  }
  var w = sourceWidth;
  var h = sourceHeight;
  final widthScale = maxWidth / w;
  final heightScale = maxHeight / h;
  final scale = widthScale < heightScale ? widthScale : heightScale;
  if (scale < 1) {
    w *= scale;
    h *= scale;
  }
  return Size(w, h);
}

class _ImageDimensionRequest {
  const _ImageDimensionRequest(this.bytes);

  final Uint8List bytes;
}

(int, int)? _decodeImageDimensions(_ImageDimensionRequest req) {
  final decoded = img.decodeImage(req.bytes);
  if (decoded == null) return null;
  return (decoded.width, decoded.height);
}

/// 解析图片像素尺寸（后台 isolate）。
Future<(int width, int height)?> decodeChatImageDimensions(Uint8List bytes) {
  return compute(_decodeImageDimensions, _ImageDimensionRequest(bytes));
}

/// 选图/编辑链路最长边（IM 场景足够，显著加快导出）。
const double kChatImagePickMaxEdge = 2048;

/// 选图压缩质量（Android/iOS 原生缩放时使用）。
const int kChatImagePickQuality = 90;

/// 编辑器导出最长边上限。
const int kChatImageEditorMaxOutputEdge = 1920;

/// 编辑器导出 JPEG 质量（86 在体积与清晰度间平衡，编码比 100 快）。
const int kChatImageEditorJpegQuality = 86;

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

class _EditorPrepareRequest {
  const _EditorPrepareRequest(this.bytes, this.maxDim, this.quality);

  final Uint8List bytes;
  final int maxDim;
  final int quality;
}

Uint8List _prepareForEditor(_EditorPrepareRequest req) {
  final decoded = img.decodeImage(req.bytes);
  if (decoded == null) return req.bytes;
  final w = decoded.width;
  final h = decoded.height;
  final longest = w > h ? w : h;
  if (longest <= req.maxDim) return req.bytes;
  final resized = img.copyResize(
    decoded,
    width: w >= h ? req.maxDim : (w * req.maxDim / h).round(),
    height: h > w ? req.maxDim : (h * req.maxDim / w).round(),
  );
  return Uint8List.fromList(img.encodeJpg(resized, quality: req.quality));
}

/// 进入编辑器前按需缩小超大原图，减轻截屏导出耗时。
Future<Uint8List> prepareChatImageForEditor(
  Uint8List bytes, {
  int maxDim = 2048,
  int quality = kChatImagePickQuality,
}) {
  return compute(
    _prepareForEditor,
    _EditorPrepareRequest(bytes, maxDim, quality),
  );
}
