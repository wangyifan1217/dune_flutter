import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import '../../core/layout/chat_layout.dart';

/// 微信 / 工作台 IM 风格：会话内图片上限。
/// 宽屏用绝对上限，避免按整窗宽度比例把气泡撑得过高。
Size chatImageBubbleMaxSize(BuildContext context) {
  final screenW = MediaQuery.sizeOf(context).width;
  if (!shouldExpandChatBubbles) {
    if (screenW >= 900) {
      // 对齐 admin-web `.im-msg-image`：max-width 200 / max-height 240
      return const Size(200, 240);
    }
    return Size(screenW * 0.32, screenW * 0.38);
  }
  // Android：直板机比例不变；折叠展开后按栏宽约 45%。
  if (screenW <= kChatPhoneWidthCap) {
    return Size(screenW * 0.32, screenW * 0.38);
  }
  return Size(
    screenW * kChatImageFoldWidthFactor,
    screenW * kChatImageFoldWidthFactor * (0.38 / 0.32),
  );
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

/// 编辑器导出最长边上限。选图阶段不再主动缩放；常见手机原图（4K/8K）
/// 可以保留原始像素，超过上限时才做保护性缩放。
const int kChatImageEditorMaxOutputEdge = 8192;

/// 编辑器导出 JPEG 质量。查看原图时优先保证清晰度，预览图仍由单独的
/// [buildChatImagePreview] 生成并上传。
const int kChatImageEditorJpegQuality = 100;

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

/// 非「原图」发送时的默认压缩：最长边 [kChatImagePickMaxEdge]，质量 [kChatImagePickQuality]。
/// 返回 null 表示无需压缩（已更小或无法解码），调用方应回退源文件。
Future<Uint8List?> compressChatImageForSend(
  Uint8List bytes, {
  String fileName = 'image.jpg',
  int maxDim = 0,
  int quality = 0,
}) async {
  final dim = maxDim > 0 ? maxDim : kChatImagePickMaxEdge.round();
  final q = quality > 0 ? quality : kChatImagePickQuality;
  try {
    final jpeg = await compute(_encodePreview, _PreviewRequest(bytes, dim, q));
    if (jpeg == null || jpeg.isEmpty) return null;
    if (jpeg.length >= bytes.length) return null;
    return jpeg;
  } catch (_) {
    return null;
  }
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
  int maxDim = kChatImageEditorMaxOutputEdge,
  int quality = kChatImageEditorJpegQuality,
}) {
  return compute(
    _prepareForEditor,
    _EditorPrepareRequest(bytes, maxDim, quality),
  );
}
