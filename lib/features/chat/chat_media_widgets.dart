import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'chat_image_utils.dart';
import 'cors_safe_image.dart';
import 'file_download.dart' as file_dl;
import 'gallery_save.dart' as gallery;

/// 与 WebView `hydrateMediaUrls` 对齐：公网图直链、私有附件鉴权拉取，支持点击放大。
/// 会话内按原图比例完整展示（不裁切），点击可全屏查看/保存。
class ChatAuthImageBubble extends StatefulWidget {
  const ChatAuthImageBubble({
    super.key,
    required this.service,
    required this.payload,
    required this.mine,
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final bool mine;

  @override
  State<ChatAuthImageBubble> createState() => _ChatAuthImageBubbleState();
}

class _ChatAuthImageBubbleState extends State<ChatAuthImageBubble> {
  /// 用于内联展示的预览 payload（旧消息无预览时回退为原图）。
  Map<String, dynamic>? _previewPayload;
  String? _publicUrl;
  Future<Uint8List>? _bytesFuture;
  bool _isGif = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _bindMedia();
  }

  @override
  void didUpdateWidget(ChatAuthImageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payload != widget.payload) {
      setState(_bindMedia);
    }
  }

  void _bindMedia() {
    final mime = (widget.payload?['mimeType'] ?? '').toString().toLowerCase();
    final fileName = ConversationService.mediaFileName(widget.payload).toLowerCase();
    _isGif = mime.contains('gif') || fileName.endsWith('.gif');
    _previewPayload = _isGif
        ? widget.payload
        : ConversationService.previewMediaPayload(widget.payload);
    _loadGeneration++;
    final gen = _loadGeneration;

    _publicUrl = widget.service.publicImageUrlForPayload(_previewPayload) ??
        widget.service.publicImageUrlForPayload(widget.payload);

    if (_publicUrl != null && _publicUrl!.isNotEmpty) {
      _bytesFuture = null;
      return;
    }

    if (ConversationService.hasAuthMedia(_previewPayload) ||
        ConversationService.hasAuthMedia(widget.payload)) {
      _bytesFuture = widget.service.loadChatMediaBytesWithFallback(
        previewPayload: _previewPayload,
        originalPayload: widget.payload,
      );
    } else {
      _bytesFuture = null;
    }
    // Prevent stale async updates if bind called again quickly.
    if (gen != _loadGeneration) return;
  }

  Future<void> _openPreview() async {
    if (!mounted) return;
    final fileName =
        ConversationService.mediaFileName(widget.payload, fallback: 'image.jpg');
    await showChatImagePreview(
      context,
      service: widget.service,
      payload: widget.payload,
      fileName: fileName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final publicUrl = _publicUrl;
    if (publicUrl != null) {
      return _ChatInlineImage(
        url: publicUrl,
        isGif: _isGif,
        mine: widget.mine,
        onTap: _openPreview,
        error: () => _errorBubble(),
        placeholder: () => _isGif ? _gifPlaceholder() : _staticPlaceholder(),
      );
    }

    final future = _bytesFuture;
    if (future == null) return _errorBubble();

    return FutureBuilder<Uint8List>(
      future: future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _isGif ? _gifPlaceholder() : _staticPlaceholder();
        }
        if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
          return _errorBubble();
        }
        return _ChatInlineImage(
          bytes: snap.data!,
          isGif: _isGif,
          mine: widget.mine,
          onTap: _openPreview,
          error: () => _errorBubble(),
          placeholder: () => _isGif ? _gifPlaceholder() : _staticPlaceholder(),
        );
      },
    );
  }

  Widget _errorBubble() {
    return GestureDetector(
      onTap: () => setState(_bindMedia),
      child: _placeholder(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              size: 28,
              color: widget.mine ? Colors.white70 : DunesColors.text3,
            ),
            const SizedBox(height: 6),
            Text(
              '[图片]',
              style: DunesTypography.sans(
                fontSize: 13,
                color: widget.mine ? Colors.white : DunesColors.text2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '点击重试',
              style: DunesTypography.sans(
                fontSize: 11,
                color: widget.mine ? Colors.white60 : DunesColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _staticPlaceholder() {
    final box = chatImageBubbleMaxSize(context);
    return _placeholder(
      width: box.width,
      height: box.width * 0.72,
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: DunesColors.text3),
      ),
    );
  }

  Widget _gifPlaceholder() {
    final box = chatImageBubbleMaxSize(context);
    return _placeholder(
      width: box.width * 0.72,
      height: box.width * 0.54,
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: DunesColors.text3),
      ),
    );
  }

  Widget _placeholder({required Widget child, double width = 120, double height = 90}) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.mine ? const Color(0x33FFFFFF) : DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.mine ? Colors.white24 : DunesColors.borderSoft),
      ),
      child: child,
    );
  }
}

/// 会话内图片：解析原图比例后在气泡框内完整展示（BoxFit.contain 语义）。
class _ChatInlineImage extends StatefulWidget {
  const _ChatInlineImage({
    required this.isGif,
    required this.mine,
    required this.onTap,
    required this.error,
    required this.placeholder,
    this.url,
    this.bytes,
  });

  final String? url;
  final Uint8List? bytes;
  final bool isGif;
  final bool mine;
  final VoidCallback onTap;
  final Widget Function() error;
  final Widget Function() placeholder;

  @override
  State<_ChatInlineImage> createState() => _ChatInlineImageState();
}

class _ChatInlineImageState extends State<_ChatInlineImage> {
  Size get _maxBox => chatImageBubbleMaxSize(context);

  @override
  Widget build(BuildContext context) {
    final box = _maxBox;
    final bytes = widget.bytes;
    final url = widget.url;

    Widget image;
    if (bytes != null) {
      image = Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => widget.error(),
      );
    } else if (url != null) {
      // Web 上公网图走 CORS-safe 通道；其余平台用 Image.network（自带缓存与自适应尺寸）。
      if (kIsWeb) {
        image = buildCorsSafeImage(
          url: url,
          width: box.width,
          height: box.width * 0.72,
          fit: BoxFit.contain,
        );
      } else {
        image = Image.network(
          url,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          loadingBuilder: (ctx, child, progress) {
            if (progress == null) return child;
            return widget.placeholder();
          },
          errorBuilder: (_, _, _) => widget.error(),
        );
      }
    } else {
      return widget.error();
    }

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: box.width,
            maxHeight: box.height,
          ),
          child: image,
        ),
      ),
    );
  }
}

/// 打开会话风格的全屏图片预览（缩放 + 关闭 + 保存到相册）。
/// 群媒体、会话气泡等共用同一套 UI 与保存逻辑。
Future<void> showChatImagePreview(
  BuildContext context, {
  required ConversationService service,
  required Map<String, dynamic>? payload,
  required String fileName,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _ImagePreviewDialog(
      service: service,
      payload: payload,
      fileName: fileName,
    ),
  );
}

/// 全屏图片预览：加载并展示原图，支持缩放、保存到相册、下载。
class _ImagePreviewDialog extends StatefulWidget {
  const _ImagePreviewDialog({
    required this.service,
    required this.payload,
    required this.fileName,
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final String fileName;

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  Future<Uint8List>? _future;
  String? _webPublicUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Web 上的公网图用 <img> 标签展示以规避 CORS；鉴权图与移动端统一拉取字节，
    // 这样才能「查看原图」并保存到相册。
    final publicUrl = ConversationService.mediaPublicImageUrl(widget.payload);
    if (kIsWeb && publicUrl != null) {
      _webPublicUrl = publicUrl;
      _future = null;
    } else {
      _future = widget.service.loadFullImageBytes(widget.payload);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    showDunesToast(
      context,
      message,
      kind: dunesToastLooksLikeError(message)
          ? DunesToastKind.error
          : DunesToastKind.normal,
    );
  }

  Future<void> _save(Uint8List bytes) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await gallery.saveImageToGallery(bytes, widget.fileName);
      _toast('已保存到相册');
    } catch (e) {
      // 桌面端等不支持相册的平台，回退为普通文件保存/下载。
      try {
        await file_dl.saveBytesAsFile(bytes, widget.fileName);
        _toast('已保存');
      } catch (_) {
        _toast('保存失败：${friendlyErrorText(e)}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveWebUrl(String url) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await file_dl.openUrlAsFile(url, widget.fileName);
    } catch (e) {
      _toast('保存失败：${friendlyErrorText(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final webUrl = _webPublicUrl;
    if (webUrl != null) {
      return Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: buildCorsSafeImage(
                    url: webUrl,
                    width: 1200,
                    height: 1200,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
            Positioned(
              left: 4,
              bottom: 4,
              child: _PreviewActionButton(
                icon: Icons.save_alt_rounded,
                label: _saving ? '保存中…' : '保存图片',
                onTap: _saving ? null : () => _saveWebUrl(webUrl),
              ),
            ),
          ],
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: FutureBuilder<Uint8List>(
        future: _future,
        builder: (context, snap) {
          final loading = snap.connectionState != ConnectionState.done;
          final bytes = snap.data;
          final failed = snap.hasError || (!loading && (bytes == null || bytes.isEmpty));

          final Widget content;
          if (loading) {
            content = const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
            );
          } else if (failed) {
            content = const Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
            );
          } else {
            content = InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.memory(bytes!, fit: BoxFit.contain)),
            );
          }

          return Stack(
            children: [
              Positioned.fill(child: content),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ),
              if (!loading && !failed && bytes != null)
                Positioned(
                  left: 4,
                  bottom: 4,
                  child: Row(
                    children: [
                      _PreviewActionButton(
                        icon: Icons.save_alt_rounded,
                        label: _saving ? '保存中…' : '保存到相册',
                        onTap: _saving ? null : () => _save(bytes),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewActionButton extends StatelessWidget {
  const _PreviewActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
