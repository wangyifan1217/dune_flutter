import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'chat_image_editor.dart';
import 'chat_image_utils.dart';
import 'cors_safe_image.dart';
import 'file_download.dart' as file_dl;
import 'gallery_save.dart' as gallery;

bool _chatImageHasSeparateOriginal(Map<String, dynamic>? payload) {
  if (payload == null) return false;
  final originalKey = (payload['objectKey'] ?? '').toString().trim();
  final originalUrl = (payload['url'] ?? '').toString().trim();
  final previewKey = (payload['previewObjectKey'] ?? '').toString().trim();
  final previewUrl = (payload['previewUrl'] ?? '').toString().trim();
  if (originalKey.isEmpty && originalUrl.isEmpty) return false;
  if (previewKey.isEmpty && previewUrl.isEmpty) return false;
  return originalKey != previewKey || originalUrl != previewUrl;
}

/// 与 WebView `hydrateMediaUrls` 对齐：公网图直链、私有附件鉴权拉取，支持点击放大。
/// 会话内按原图比例完整展示（不裁切），点击可全屏查看/保存。
class ChatAuthImageBubble extends StatefulWidget {
  const ChatAuthImageBubble({
    super.key,
    required this.service,
    required this.payload,
    required this.mine,
    this.conversationId,
    this.onTap,
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final bool mine;
  final int? conversationId;

  /// 为空时默认打开图片预览。
  final VoidCallback? onTap;

  @override
  State<ChatAuthImageBubble> createState() => _ChatAuthImageBubbleState();
}

class _ChatAuthImageBubbleState extends State<ChatAuthImageBubble> {
  /// 用于内联展示的预览 payload（旧消息无预览时回退为原图）。
  Map<String, dynamic>? _previewPayload;
  String? _publicUrl;
  Future<String>? _authUrlFuture;
  Future<Uint8List>? _bytesFuture;
  bool _useBytesFallback = false;
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
    final fileName = ConversationService.mediaFileName(
      widget.payload,
    ).toLowerCase();
    _isGif = mime.contains('gif') || fileName.endsWith('.gif');
    _previewPayload = _isGif
        ? widget.payload
        : ConversationService.previewMediaPayload(widget.payload);
    _loadGeneration++;
    final gen = _loadGeneration;
    _useBytesFallback = false;
    _authUrlFuture = null;
    _bytesFuture = null;

    _publicUrl =
        widget.service.publicImageUrlForPayload(_previewPayload) ??
        widget.service.publicImageUrlForPayload(widget.payload);

    if (_publicUrl != null && _publicUrl!.isNotEmpty) {
      return;
    }

    if (ConversationService.hasAuthMedia(_previewPayload) ||
        ConversationService.hasAuthMedia(widget.payload)) {
      _authUrlFuture = widget.service.resolveAuthImageDisplayUrl(
        previewPayload: _previewPayload,
        originalPayload: widget.payload,
      );
    }
    // Prevent stale async updates if bind called again quickly.
    if (gen != _loadGeneration) return;
  }

  void _fallbackToBytes() {
    if (_useBytesFallback || !mounted) return;
    setState(() {
      _useBytesFallback = true;
      _bytesFuture = widget.service.loadCachedChatMediaBytesWithFallback(
        previewPayload: _previewPayload,
        originalPayload: widget.payload,
      );
    });
  }

  void _onAuthUrlFailed() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _useBytesFallback) return;
      _fallbackToBytes();
    });
  }

  Future<void> _openPreview() async {
    if (!mounted) return;
    final custom = widget.onTap;
    if (custom != null) {
      custom();
      return;
    }
    final fileName = ConversationService.mediaFileName(
      widget.payload,
      fallback: 'image.jpg',
    );
    await showChatImagePreview(
      context,
      service: widget.service,
      payload: widget.payload,
      fileName: fileName,
      conversationId: widget.conversationId,
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

    if (!_useBytesFallback) {
      final urlFuture = _authUrlFuture;
      if (urlFuture != null) {
        return FutureBuilder<String>(
          future: urlFuture,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return _isGif ? _gifPlaceholder() : _staticPlaceholder();
            }
            if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _fallbackToBytes();
              });
              return _isGif ? _gifPlaceholder() : _staticPlaceholder();
            }
            return _ChatInlineImage(
              url: snap.data!,
              isGif: _isGif,
              mine: widget.mine,
              onTap: _openPreview,
              error: () => _errorBubble(),
              placeholder: () =>
                  _isGif ? _gifPlaceholder() : _staticPlaceholder(),
              onUrlError: _onAuthUrlFailed,
            );
          },
        );
      }
      return _errorBubble();
    }

    final bytesFuture = _bytesFuture;
    if (bytesFuture == null) return _errorBubble();

    return FutureBuilder<Uint8List>(
      future: bytesFuture,
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
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: DunesColors.text3,
        ),
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
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: DunesColors.text3,
        ),
      ),
    );
  }

  Widget _placeholder({
    required Widget child,
    double width = 120,
    double height = 90,
  }) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.mine ? const Color(0x33FFFFFF) : DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.mine ? Colors.white24 : DunesColors.borderSoft,
        ),
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
    this.onUrlError,
  });

  final String? url;
  final Uint8List? bytes;
  final bool isGif;
  final bool mine;
  final VoidCallback onTap;
  final Widget Function() error;
  final Widget Function() placeholder;
  final VoidCallback? onUrlError;

  @override
  State<_ChatInlineImage> createState() => _ChatInlineImageState();
}

class _ChatInlineImageState extends State<_ChatInlineImage> {
  Size? _decodedSize;
  ImageStream? _netStream;
  ImageStreamListener? _netListener;

  Size get _maxBox => chatImageBubbleMaxSize(context);

  @override
  void initState() {
    super.initState();
    _resolveBytesSize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveNetworkSize();
  }

  @override
  void didUpdateWidget(_ChatInlineImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bytes != widget.bytes || oldWidget.url != widget.url) {
      _decodedSize = null;
      _clearNetworkListener();
      _resolveBytesSize();
      _resolveNetworkSize();
    }
  }

  @override
  void dispose() {
    _clearNetworkListener();
    super.dispose();
  }

  void _clearNetworkListener() {
    if (_netStream != null && _netListener != null) {
      _netStream!.removeListener(_netListener!);
    }
    _netStream = null;
    _netListener = null;
  }

  void _resolveBytesSize() {
    final bytes = widget.bytes;
    if (bytes == null || bytes.isEmpty) return;
    unawaited(() async {
      final dims = await decodeChatImageDimensions(bytes);
      if (!mounted || dims == null) return;
      setState(() {
        _decodedSize = Size(dims.$1.toDouble(), dims.$2.toDouble());
      });
    }());
  }

  void _resolveNetworkSize() {
    final url = widget.url;
    if (url == null || url.isEmpty || widget.bytes != null || kIsWeb) return;
    if (_decodedSize != null) return;
    _clearNetworkListener();
    final provider = NetworkImage(url);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (w <= 0 || h <= 0) return;
        setState(() => _decodedSize = Size(w, h));
        stream.removeListener(listener);
        if (_netStream == stream) {
          _netStream = null;
          _netListener = null;
        }
      },
      onError: (_, _) {
        stream.removeListener(listener);
        if (_netStream == stream) {
          _netStream = null;
          _netListener = null;
        }
      },
    );
    _netStream = stream;
    _netListener = listener;
    stream.addListener(listener);
  }

  Size _displaySize() {
    final box = _maxBox;
    final src = _decodedSize;
    if (src != null) {
      return chatImageBubbleDisplaySize(
        src.width,
        src.height,
        maxWidth: box.width,
        maxHeight: box.height,
      );
    }
    // 未知尺寸时用较扁占位，避免按 maxHeight 撑出大块空白。
    return Size(box.width, box.width * 0.72);
  }

  @override
  Widget build(BuildContext context) {
    final box = _maxBox;
    final display = _displaySize();
    final bytes = widget.bytes;
    final url = widget.url;

    Widget image;
    if (bytes != null) {
      image = Image.memory(
        bytes,
        width: display.width,
        height: display.height,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => widget.error(),
      );
    } else if (url != null) {
      if (kIsWeb) {
        image = buildCorsSafeImage(
          url: url,
          width: display.width,
          height: display.height,
          fit: BoxFit.contain,
          // 会话气泡需要点击预览；HtmlElementView 会吃掉点击。
          hitTestOverlay: true,
        );
      } else {
        image = Image.network(
          url,
          width: display.width,
          height: display.height,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return SizedBox(
              width: display.width,
              height: display.height,
              child: widget.placeholder(),
            );
          },
          errorBuilder: (_, _, _) {
            widget.onUrlError?.call();
            return widget.onUrlError != null
                ? widget.placeholder()
                : widget.error();
          },
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
  int? conversationId,
  VoidCallback? onLocateInChat,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (_) => _ImagePreviewDialog(
      service: service,
      payload: payload,
      fileName: fileName,
      conversationId: conversationId,
      onLocateInChat: onLocateInChat,
    ),
  );
}

/// 全屏图片预览：缩放；APP 保存到相册；PC 下载 / 裁剪编辑。
class _ImagePreviewDialog extends StatefulWidget {
  const _ImagePreviewDialog({
    required this.service,
    required this.payload,
    required this.fileName,
    this.conversationId,
    this.onLocateInChat,
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final String fileName;
  final int? conversationId;
  final VoidCallback? onLocateInChat;

  @override
  State<_ImagePreviewDialog> createState() => _ImagePreviewDialogState();
}

class _ImagePreviewDialogState extends State<_ImagePreviewDialog> {
  Future<Uint8List>? _future;
  String? _webPublicUrl;
  bool _showingOriginal = false;
  bool _saving = false;
  bool _editing = false;
  Uint8List? _editedBytes;
  Uint8List? _metadataBytes;
  Future<(int width, int height)?>? _dimensionsFuture;

  bool get _desktop => isDesktopCommOnly;

  String get _cacheKey {
    final cachePayload = _showingOriginal
        ? widget.payload
        : ConversationService.previewMediaPayload(widget.payload);
    final objectKey = (cachePayload?['objectKey'] ?? '').toString().trim();
    if (objectKey.isNotEmpty) return objectKey;
    return ConversationService.mediaDirectUrl(cachePayload);
  }

  int? get _payloadSizeBytes {
    final raw =
        widget.payload?['sizeBytes'] ??
        widget.payload?['size_bytes'] ??
        widget.payload?['fileSizeBytes'] ??
        widget.payload?['fileSize'] ??
        widget.payload?['file_size'] ??
        widget.payload?['originalSizeBytes'] ??
        widget.payload?['original_size_bytes'] ??
        widget.payload?['size'];
    if (raw is num && raw >= 0) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '');
  }

  void _prepareMetadata(Uint8List bytes) {
    if (identical(_metadataBytes, bytes)) return;
    _metadataBytes = bytes;
    _dimensionsFuture = decodeChatImageDimensions(bytes);
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(bytes < 10240 ? 1 : 0)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Widget _metadataPill({
    required int? sizeBytes,
    required Future<(int width, int height)?>? dimensions,
    bool original = true,
    bool force = false,
  }) {
    if (!force && sizeBytes == null && dimensions == null) {
      return const SizedBox.shrink();
    }
    final sizeText = sizeBytes == null ? '' : _formatBytes(sizeBytes);
    return FutureBuilder<(int width, int height)?>(
      future: dimensions,
      builder: (context, snapshot) {
        final dimension = snapshot.data;
        final dimensionText = dimension == null
            ? ''
            : '${dimension.$1} × ${dimension.$2}';
        final details = <String>[
          if (dimensionText.isNotEmpty) dimensionText,
          if (sizeText.isNotEmpty) sizeText,
        ].join(' · ');
        final label = original ? '原图' : '预览图';
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              details.isEmpty ? label : '$label · $details',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // 首次打开保持原有行为，先展示会话内预览图；查看原图由预览页内按钮触发。
    final publicUrl = ConversationService.mediaPublicImageUrl(widget.payload);
    if (kIsWeb && publicUrl != null) {
      _webPublicUrl = publicUrl;
      _future = null;
    } else {
      _future = _loadPreviewBytes();
    }
  }

  Future<Uint8List> _loadPreviewBytes() async {
    final previewPayload = ConversationService.previewMediaPayload(
      widget.payload,
    );
    final publicUrl = ConversationService.mediaPublicImageUrl(widget.payload);
    if (publicUrl != null && publicUrl.isNotEmpty) {
      try {
        return await widget.service.downloadAttachmentBytes(
          objectKey: publicUrl,
          fileName: widget.fileName,
        );
      } catch (_) {
        // 公网地址失效时回退到鉴权预览下载。
      }
    }
    return widget.service.loadCachedChatMediaBytesWithFallback(
      previewPayload: previewPayload,
      // 预览页初次打开不能静默回退到原图；原图必须由用户点击按钮后加载。
      originalPayload: null,
    );
  }

  void _viewOriginal() {
    if (_showingOriginal || !_chatImageHasSeparateOriginal(widget.payload)) {
      return;
    }
    final publicUrl = ConversationService.mediaOriginalPublicImageUrl(
      widget.payload,
    );
    // Web 才用公网直链渲染；桌面/APP 一律拉原图像素字节，避免错误 CDN
    // 地址抢占 _webPublicUrl 分支后看起来像「点了没效果」。
    final useWebPublic = kIsWeb && publicUrl != null && publicUrl.isNotEmpty;
    final fullFuture = useWebPublic
        ? null
        : widget.service.loadFullImageBytes(widget.payload);
    setState(() {
      _showingOriginal = true;
      _webPublicUrl = useWebPublic ? publicUrl : null;
      _future = fullFuture;
      _editedBytes = null;
      _metadataBytes = null;
      _dimensionsFuture = null;
    });
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

  Future<void> _save(Uint8List bytes, {String? fileName}) async {
    if (_saving) return;
    final name = (fileName ?? widget.fileName).trim().isEmpty
        ? widget.fileName
        : (fileName ?? widget.fileName);
    setState(() => _saving = true);
    try {
      if (_desktop) {
        final key = _cacheKey;
        if (key.isNotEmpty ||
            (widget.conversationId != null && widget.conversationId! > 0)) {
          await file_dl.saveBytesAsCachedFile(
            bytes,
            key,
            name,
            conversationId: widget.conversationId,
          );
        } else {
          await file_dl.saveBytesAsFile(bytes, name);
        }
        _toast('已下载');
      } else {
        await gallery.saveImageToGallery(bytes, name);
        _toast('已保存到相册');
      }
    } catch (e) {
      if (_desktop) {
        _toast('下载失败：${friendlyErrorText(e)}');
      } else {
        // 不支持相册的平台，回退为普通文件保存。
        try {
          await file_dl.saveBytesAsFile(bytes, name);
          _toast('已保存');
        } catch (_) {
          _toast('保存失败：${friendlyErrorText(e)}');
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveWebUrl(String url) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await file_dl.openUrlAsFile(
        url,
        widget.fileName,
        cacheKey: _cacheKey.isEmpty ? null : _cacheKey,
        conversationId: widget.conversationId,
      );
      _toast(_desktop ? '已下载' : '已保存');
    } catch (e) {
      _toast('保存失败：${friendlyErrorText(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editAndMaybeDownload(Uint8List source) async {
    if (_editing || !_desktop) return;
    setState(() => _editing = true);
    try {
      final edited = await openChatImageEditor(
        context,
        bytes: source,
        doneLabel: '完成',
      );
      if (!mounted || edited == null || edited.isEmpty) return;
      setState(() => _editedBytes = edited);
      await _save(edited, fileName: chatImageEditedFileName(widget.fileName));
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final webUrl = _webPublicUrl;
    if (webUrl != null) {
      return Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Expanded(
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
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14,
                    left: 14,
                    child: _metadataPill(
                      sizeBytes: _showingOriginal ? _payloadSizeBytes : null,
                      dimensions: null,
                      original: _showingOriginal,
                      force: _showingOriginal,
                    ),
                  ),
                ],
              ),
            ),
            // 底栏单独占位，避免挡住图片底部内容。
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                child: Align(
                  alignment: Alignment.center,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.onLocateInChat != null) ...[
                            _PreviewActionButton(
                              icon: Icons.my_location_rounded,
                              label: '定位聊天',
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.onLocateInChat!();
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (!_showingOriginal &&
                              _chatImageHasSeparateOriginal(
                                widget.payload,
                              )) ...[
                            _PreviewActionButton(
                              icon: Icons.high_quality_rounded,
                              label: '查看原图',
                              onTap: _viewOriginal,
                            ),
                            const SizedBox(width: 8),
                          ],
                          _PreviewActionButton(
                            icon: Icons.download_rounded,
                            label: _saving
                                ? '下载中…'
                                : (_showingOriginal
                                      ? (_desktop ? '下载原图' : '保存原图')
                                      : (_desktop ? '下载预览' : '保存预览')),
                            onTap: _saving
                                ? null
                                : () => _saveWebUrl(webUrl),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
          final loaded = snap.data;
          final bytes = _editedBytes ?? loaded;
          final originalBytes = loaded;
          final failed =
              snap.hasError || (!loading && (loaded == null || loaded.isEmpty));

          final Widget content;
          if (loading) {
            content = const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            );
          } else if (failed || bytes == null) {
            content = const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            );
          } else {
            _prepareMetadata(originalBytes ?? bytes);
            content = InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            );
          }

          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: content),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (!loading && !failed && bytes != null)
                      Positioned(
                        top: 14,
                        left: 14,
                        child: _metadataPill(
                          sizeBytes: _showingOriginal
                              ? (_payloadSizeBytes ?? originalBytes?.length)
                              : originalBytes?.length,
                          dimensions: _dimensionsFuture,
                          original: _showingOriginal,
                        ),
                      ),
                  ],
                ),
              ),
              // 底栏与图片分区布局，避免「查看原图/裁剪/下载」盖住图底部内容。
              if (!loading && !failed && bytes != null)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                    child: Align(
                      alignment: Alignment.center,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.onLocateInChat != null) ...[
                                _PreviewActionButton(
                                  icon: Icons.my_location_rounded,
                                  label: '定位聊天',
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    widget.onLocateInChat!();
                                  },
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (!_showingOriginal &&
                                  _chatImageHasSeparateOriginal(
                                    widget.payload,
                                  )) ...[
                                _PreviewActionButton(
                                  icon: Icons.high_quality_rounded,
                                  label: '查看原图',
                                  onTap: _viewOriginal,
                                ),
                                const SizedBox(width: 8),
                              ],
                              if (_desktop) ...[
                                _PreviewActionButton(
                                  icon: Icons.crop_rounded,
                                  label: _editing ? '编辑中…' : '裁剪',
                                  onTap: (_saving || _editing)
                                      ? null
                                      : () => _editAndMaybeDownload(bytes),
                                ),
                                const SizedBox(width: 8),
                              ],
                              _PreviewActionButton(
                                icon: Icons.download_rounded,
                                label: _saving
                                    ? (_desktop ? '下载中…' : '保存中…')
                                    : (_showingOriginal
                                          ? (_desktop ? '下载原图' : '保存原图')
                                          : (_desktop ? '下载预览' : '保存预览')),
                                onTap: (_saving || _editing)
                                    ? null
                                    : () => _save(bytes),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
