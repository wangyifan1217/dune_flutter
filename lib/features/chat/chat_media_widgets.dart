import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'chat_widgets.dart';
import 'cors_safe_image.dart';
import 'file_download.dart' as file_dl;
import 'gallery_save.dart' as gallery;

/// 与 WebView `hydrateMediaUrls` 对齐：公网图直链、私有附件鉴权拉取，支持点击放大。
/// 会话内联展示压缩预览图，点击后在全屏弹层加载原图，并可保存到相册。
class ChatAuthImageBubble extends StatefulWidget {
  const ChatAuthImageBubble({
    super.key,
    required this.service,
    required this.payload,
    required this.mine,
    this.bodyFallback = '[图片]',
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final bool mine;
  final String bodyFallback;

  @override
  State<ChatAuthImageBubble> createState() => _ChatAuthImageBubbleState();
}

class _ChatAuthImageBubbleState extends State<ChatAuthImageBubble> {
  static const _maxThumbWidth = 240.0;
  static const _maxThumbHeight = 280.0;
  static const _coverThumbHeight = 180.0;

  /// 用于内联展示的预览 payload（旧消息无预览时回退为原图）。
  Map<String, dynamic>? _previewPayload;
  String? _publicUrl;
  Future<Uint8List>? _bytesFuture;

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
    _previewPayload = ConversationService.previewMediaPayload(widget.payload);
    _publicUrl = ConversationService.mediaPublicImageUrl(_previewPayload);
    _bytesFuture = ConversationService.hasAuthMedia(_previewPayload)
        ? widget.service.loadChatMediaBytes(_previewPayload)
        : null;
  }

  Future<void> _openPreview() async {
    if (!mounted) return;
    final fileName =
        ConversationService.mediaFileName(widget.payload, fallback: 'image.jpg');
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _ImagePreviewDialog(
        service: widget.service,
        payload: widget.payload,
        fileName: fileName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final publicUrl = _publicUrl;
    if (publicUrl != null) {
      // 公网图：固定比例缩略框 + cover 填充，避免两侧留白导致"错位/偏移"。
      return GestureDetector(
        onTap: _openPreview,
        child: _thumbWithOverlay(
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: buildCorsSafeImage(
              url: publicUrl,
              width: _maxThumbWidth,
              height: _coverThumbHeight,
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
    }

    final future = _bytesFuture;
    if (future == null) return _errorBubble();

    return FutureBuilder<Uint8List>(
      future: future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _placeholder(
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: DunesColors.text3),
            ),
          );
        }
        if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
          return _errorBubble();
        }
        final bytes = snap.data!;
        // 私有图：按图片真实比例自适应（最大 240×280），气泡紧贴图片，
        // 不再被强制撑成固定宽度而出现向左偏移的留白。
        return GestureDetector(
          onTap: _openPreview,
          child: _thumbWithOverlay(
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: _maxThumbWidth,
                maxHeight: _maxThumbHeight,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _errorBubble() => ChatTextBubble(
        text: widget.bodyFallback.isEmpty ? '[图片加载失败]' : widget.bodyFallback,
        mine: widget.mine,
      );

  Widget _placeholder({required Widget child}) {
    return Container(
      width: 160,
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.mine ? const Color(0x33FFFFFF) : DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.mine ? Colors.white24 : DunesColors.borderSoft),
      ),
      child: child,
    );
  }

  Widget _thumbWithOverlay(Widget image) {
    return Stack(
      children: [
        image,
        Positioned(
          right: 8,
          bottom: 8,
          child: Material(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(14),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_full, size: 12, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    '查看原图',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
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
        _toast('保存失败: $e');
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
      _toast('保存失败: $e');
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
