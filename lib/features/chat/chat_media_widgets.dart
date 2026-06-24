import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../conversation/conversation_service.dart';
import 'chat_widgets.dart';
import 'cors_safe_image.dart';
import 'file_download.dart' as file_dl;

/// 与 WebView `hydrateMediaUrls` 对齐：公网图直链、私有附件鉴权拉取，支持点击放大。
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
  static const _thumbWidth = 240.0;
  static const _thumbHeight = 170.0;

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
    _publicUrl = ConversationService.mediaPublicImageUrl(widget.payload);
    _bytesFuture = ConversationService.hasAuthMedia(widget.payload)
        ? widget.service.loadChatMediaBytes(widget.payload)
        : null;
  }

  Future<void> _openPreview({Uint8List? bytes, String? imageUrl}) async {
    final fileName = ConversationService.mediaFileName(widget.payload, fallback: 'image.jpg');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _ImagePreviewDialog(bytes: bytes, imageUrl: imageUrl, fileName: fileName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final publicUrl = _publicUrl;
    if (publicUrl != null) {
      return GestureDetector(
        onTap: () => _openPreview(imageUrl: publicUrl),
        child: _thumbWithOverlay(
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: buildCorsSafeImage(
              url: publicUrl,
              width: _thumbWidth,
              height: _thumbHeight,
              fit: BoxFit.contain,
            ),
          ),
          onPreview: () => _openPreview(imageUrl: publicUrl),
        ),
      );
    }

    final future = _bytesFuture;
    if (future == null) return _errorBubble();

    return FutureBuilder<Uint8List>(
      future: future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _frame(
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: DunesColors.text3),
              ),
            ),
          );
        }
        if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
          return _errorBubble();
        }
        final bytes = snap.data!;
        return GestureDetector(
          onTap: () => _openPreview(bytes: bytes),
          child: _thumbWithOverlay(
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                width: _thumbWidth,
                height: _thumbHeight,
                gaplessPlayback: true,
              ),
            ),
            onPreview: () => _openPreview(bytes: bytes),
          ),
        );
      },
    );
  }

  Widget _errorBubble() => ChatTextBubble(
        text: widget.bodyFallback.isEmpty ? '[图片加载失败]' : widget.bodyFallback,
        mine: widget.mine,
      );

  Widget _frame({required Widget child}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 120,
        minHeight: 90,
        maxWidth: _thumbWidth,
        maxHeight: _thumbHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.mine ? const Color(0x33FFFFFF) : DunesColors.bgSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.mine ? Colors.white24 : DunesColors.borderSoft),
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _thumbWithOverlay(Widget image, {required VoidCallback onPreview}) {
    return Stack(
      children: [
        _frame(child: image),
        Positioned(
          right: 8,
          bottom: 8,
          child: Material(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onPreview,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.open_in_full, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      '预览',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImagePreviewDialog extends StatelessWidget {
  const _ImagePreviewDialog({
    required this.fileName,
    this.bytes,
    this.imageUrl,
  });

  final Uint8List? bytes;
  final String? imageUrl;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final Widget image;
    if (bytes != null && bytes!.isNotEmpty) {
      image = Image.memory(bytes!, fit: BoxFit.contain);
    } else if ((imageUrl ?? '').isNotEmpty) {
      image = buildCorsSafeImage(
        url: imageUrl!,
        width: 900,
        height: 900,
        fit: BoxFit.contain,
      );
    } else {
      image = const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48);
    }

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          InteractiveViewer(child: image),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
          Positioned(
            top: 4,
            left: 4,
            child: IconButton(
              tooltip: '下载',
              onPressed: () async {
                if (bytes != null && bytes!.isNotEmpty) {
                  await file_dl.saveBytesAsFile(bytes!, fileName);
                } else if ((imageUrl ?? '').isNotEmpty) {
                  await file_dl.openUrlAsFile(imageUrl!, fileName);
                }
              },
              icon: const Icon(Icons.download_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
