import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'chat_image_editor.dart';
import 'chat_image_preview_models.dart';
import 'chat_image_preview_window_stub.dart'
    if (dart.library.io) 'chat_image_preview_window.dart';
import 'chat_image_utils.dart';
import 'desktop_image_preview_pref.dart';

export 'chat_image_preview_models.dart';
import 'cors_safe_image.dart';
import 'file_download.dart' as file_dl;
import 'gallery_save.dart' as gallery;

/// 左键默认应用内全屏；设置里可改为独立窗口。
bool get _preferDesktopImageWindow => DesktopImagePreviewPref.enabled;

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
    this.onLongPressStart,
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final bool mine;
  final int? conversationId;

  /// 为空时默认打开图片预览。
  final VoidCallback? onTap;

  /// 与单击预览放在同一手势器上，避免行级长按把安卓单击吞掉。
  final GestureLongPressStartCallback? onLongPressStart;

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

  Widget _withImageGestures(Widget child) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openPreview,
      onLongPressStart: widget.onLongPressStart,
      child: child,
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
        onLongPressStart: widget.onLongPressStart,
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
              return _withImageGestures(
                _isGif ? _gifPlaceholder() : _staticPlaceholder(),
              );
            }
            if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _fallbackToBytes();
              });
              return _withImageGestures(
                _isGif ? _gifPlaceholder() : _staticPlaceholder(),
              );
            }
            return _ChatInlineImage(
              url: snap.data!,
              isGif: _isGif,
              mine: widget.mine,
              onTap: _openPreview,
              onLongPressStart: widget.onLongPressStart,
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
          return _withImageGestures(
            _isGif ? _gifPlaceholder() : _staticPlaceholder(),
          );
        }
        if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
          return _errorBubble();
        }
        return _ChatInlineImage(
          bytes: snap.data!,
          isGif: _isGif,
          mine: widget.mine,
          onTap: _openPreview,
          onLongPressStart: widget.onLongPressStart,
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
    this.onLongPressStart,
  });

  final String? url;
  final Uint8List? bytes;
  final bool isGif;
  final bool mine;
  final VoidCallback onTap;
  final Widget Function() error;
  final Widget Function() placeholder;
  final VoidCallback? onUrlError;
  final GestureLongPressStartCallback? onLongPressStart;

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

    // 桌面 / APP 均单击打开。Mac 触控板双击在 ListView 里极易丢手势，
    // 表现为「点了没反应」；独立预览窗由 showChatImagePreview 负责。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPressStart: widget.onLongPressStart,
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

/// 打开会话风格的图片预览（缩放 + 关闭 + 保存/下载）。
/// PC 左键默认应用内全屏；设置「独立窗口查看图片」开启后走系统子窗。
/// 右键「弹框预览」走 [showChatImagePopupPreview]。
/// 群媒体、会话气泡等共用同一套 UI 与保存逻辑。
Future<void> showChatImagePreview(
  BuildContext context, {
  required ConversationService service,
  Map<String, dynamic>? payload,
  String fileName = 'image.jpg',
  List<ChatImagePreviewItem>? items,
  int initialIndex = 0,
  int? conversationId,
  VoidCallback? onLocateInChat,
}) {
  final gallery = (items != null && items.isNotEmpty)
      ? items
      : <ChatImagePreviewItem>[
          ChatImagePreviewItem(
            payload: payload,
            fileName: fileName,
            onLocateInChat: onLocateInChat,
          ),
        ];
  final index = initialIndex.clamp(0, gallery.length - 1);

  return _openChatImagePreviewByPref(
    context,
    service: service,
    items: gallery,
    initialIndex: index,
    conversationId: conversationId,
  );
}

Future<void> _openChatImagePreviewByPref(
  BuildContext context, {
  required ConversationService service,
  required List<ChatImagePreviewItem> items,
  required int initialIndex,
  int? conversationId,
}) async {
  await DesktopImagePreviewPref.ensureLoaded();
  if (_preferDesktopImageWindow) {
    await _openDesktopChatImagePreviewWithFeedback(
      context,
      service: service,
      items: items,
      initialIndex: initialIndex,
      conversationId: conversationId,
    );
    return;
  }
  if (!context.mounted) return;
  await _showInAppChatImagePreview(
    context,
    service: service,
    items: items,
    initialIndex: initialIndex,
    conversationId: conversationId,
  );
}

/// PC 右键：居中小窗预览（不另起 Flutter 引擎）。点遮罩或关闭即可关掉。
Future<void> showChatImagePopupPreview(
  BuildContext context, {
  required ConversationService service,
  Map<String, dynamic>? payload,
  String fileName = 'image.jpg',
  int? conversationId,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      final maxW = size.width * 0.6 < 640 ? size.width * 0.6 : 640.0;
      final maxH = size.height * 0.72;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxW,
            maxHeight: maxH,
            minWidth: 280,
            minHeight: 200,
          ),
          child: _ChatImagePopupBody(
            service: service,
            payload: payload,
            fileName: fileName,
            conversationId: conversationId,
          ),
        ),
      );
    },
  );
}

Future<void> _showInAppChatImagePreview(
  BuildContext context, {
  required ConversationService service,
  required List<ChatImagePreviewItem> items,
  required int initialIndex,
  int? conversationId,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭图片预览',
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return ChatImagePreviewPage(
        service: service,
        items: items,
        initialIndex: initialIndex,
        conversationId: conversationId,
        onClose: () => Navigator.of(ctx).maybePop(),
      );
    },
  );
}

/// 主窗立刻给出点击反馈，避免独立引擎启动期间「点了没反应」。
/// Mac 上 multi_window 偶发失败时回退到应用内全屏预览，避免「点了没窗」。
Future<void> _openDesktopChatImagePreviewWithFeedback(
  BuildContext context, {
  required ConversationService service,
  required List<ChatImagePreviewItem> items,
  required int initialIndex,
  int? conversationId,
}) async {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  OverlayEntry? entry;
  if (overlay != null) {
    entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.18),
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      '正在打开预览…',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
  }
  try {
    await openDesktopChatImagePreviewWindow(
      session: service.session,
      items: items,
      initialIndex: initialIndex,
      conversationId: conversationId,
    ).timeout(const Duration(seconds: 4));
  } catch (_) {
    if (!context.mounted) return;
    // Windows 独立窗超时/失败时回退，避免蒙版永久卡住。
    await _showInAppChatImagePreview(
      context,
      service: service,
      items: items,
      initialIndex: initialIndex,
      conversationId: conversationId,
    );
  } finally {
    entry?.remove();
  }
}

/// 全屏图片预览：缩放；APP 保存到相册；PC 独立窗 / 裁剪编辑 / 左右切换。
class ChatImagePreviewPage extends StatefulWidget {
  const ChatImagePreviewPage({
    super.key,
    required this.service,
    required this.items,
    required this.initialIndex,
    this.conversationId,
    this.initialPreviewBytes,
    this.onClose,
  });

  final ConversationService service;
  final List<ChatImagePreviewItem> items;
  final int initialIndex;
  final int? conversationId;

  /// 主窗口已缓存的当前预览图字节，用于独立窗首帧秒开。
  final Uint8List? initialPreviewBytes;

  /// 独立窗口关闭回调；为空时走 Navigator.pop。
  final VoidCallback? onClose;

  @override
  State<ChatImagePreviewPage> createState() => _ChatImagePreviewPageState();
}

class _ChatImagePreviewPageState extends State<ChatImagePreviewPage> {
  late int _index;
  Future<Uint8List>? _future;
  String? _webPublicUrl;
  bool _showingOriginal = false;
  bool _saving = false;
  bool _editing = false;
  bool _consumedInitialBytes = false;
  Uint8List? _editedBytes;
  Uint8List? _metadataBytes;
  Future<(int width, int height)?>? _dimensionsFuture;
  final FocusNode _focusNode = FocusNode();

  bool get _desktop => isDesktopCommOnly;
  bool get _canBrowse => widget.items.length > 1;
  ChatImagePreviewItem get _current => widget.items[_index];
  Map<String, dynamic>? get _payload => _current.payload;
  String get _fileName => _current.fileName;
  VoidCallback? get _onLocateInChat => _current.onLocateInChat;

  String get _cacheKey {
    final cachePayload = _showingOriginal
        ? _payload
        : ConversationService.previewMediaPayload(_payload);
    final objectKey = (cachePayload?['objectKey'] ?? '').toString().trim();
    if (objectKey.isNotEmpty) return objectKey;
    return ConversationService.mediaDirectUrl(cachePayload);
  }

  int? get _payloadSizeBytes {
    final raw =
        _payload?['sizeBytes'] ??
        _payload?['size_bytes'] ??
        _payload?['fileSizeBytes'] ??
        _payload?['fileSize'] ??
        _payload?['file_size'] ??
        _payload?['originalSizeBytes'] ??
        _payload?['original_size_bytes'] ??
        _payload?['size'];
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
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _bindCurrentItem();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _bindCurrentItem() {
    _showingOriginal = false;
    _saving = false;
    _editing = false;
    _editedBytes = null;
    _metadataBytes = null;
    _dimensionsFuture = null;
    // 首次打开保持原有行为，先展示会话内预览图；查看原图由预览页内按钮触发。
    final publicUrl = ConversationService.mediaPublicImageUrl(_payload);
    if (kIsWeb && publicUrl != null) {
      _webPublicUrl = publicUrl;
      _future = null;
      return;
    }
    _webPublicUrl = null;
    final seed = widget.initialPreviewBytes;
    if (!_consumedInitialBytes &&
        seed != null &&
        seed.isNotEmpty &&
        _index == widget.initialIndex) {
      _consumedInitialBytes = true;
      _future = Future<Uint8List>.value(seed);
      _prepareMetadata(seed);
      return;
    }
    _future = _loadPreviewBytes();
  }

  void _goTo(int index) {
    if (!_canBrowse) return;
    if (index < 0 || index >= widget.items.length || index == _index) return;
    setState(() {
      _index = index;
      _bindCurrentItem();
    });
  }

  void _goPrev() => _goTo(_index - 1);
  void _goNext() => _goTo(_index + 1);

  Future<Uint8List> _loadPreviewBytes() async {
    final previewPayload = ConversationService.previewMediaPayload(_payload);
    final publicUrl = ConversationService.mediaPublicImageUrl(_payload);
    if (publicUrl != null && publicUrl.isNotEmpty) {
      try {
        return await widget.service.downloadAttachmentBytes(
          objectKey: publicUrl,
          fileName: _fileName,
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
    if (_showingOriginal || !_chatImageHasSeparateOriginal(_payload)) {
      return;
    }
    final publicUrl = ConversationService.mediaOriginalPublicImageUrl(_payload);
    // Web 才用公网直链渲染；桌面/APP 一律拉原图像素字节，避免错误 CDN
    // 地址抢占 _webPublicUrl 分支后看起来像「点了没效果」。
    final useWebPublic = kIsWeb && publicUrl != null && publicUrl.isNotEmpty;
    final fullFuture = useWebPublic
        ? null
        : widget.service.loadFullImageBytes(_payload);
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
    final name = (fileName ?? _fileName).trim().isEmpty
        ? _fileName
        : (fileName ?? _fileName);
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
        _fileName,
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
      await _save(edited, fileName: chatImageEditedFileName(_fileName));
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Widget _navButton({required IconData icon, required VoidCallback? onTap}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            color: onTap == null ? Colors.white38 : Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActionChildren({
    required bool forWeb,
    String? webUrl,
    Uint8List? bytes,
  }) {
    return [
      if (_onLocateInChat != null) ...[
        _PreviewActionButton(
          icon: Icons.my_location_rounded,
          label: '定位聊天',
          onTap: () {
            _close();
            _onLocateInChat!();
          },
        ),
        const SizedBox(width: 8),
      ],
      if (!_showingOriginal && _chatImageHasSeparateOriginal(_payload)) ...[
        _PreviewActionButton(
          icon: Icons.high_quality_rounded,
          label: '查看原图',
          onTap: _viewOriginal,
        ),
        const SizedBox(width: 8),
      ],
      if (_desktop && !forWeb && bytes != null) ...[
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
        onTap: _saving || _editing
            ? null
            : () {
                if (forWeb && webUrl != null) {
                  unawaited(_saveWebUrl(webUrl));
                } else if (bytes != null) {
                  unawaited(_save(bytes));
                }
              },
      ),
    ];
  }

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
      return;
    }
    Navigator.of(context).maybePop();
  }

  /// APP 端：点击图片或黑色背景关闭预览（与微信一致）；
  /// 桌面独立窗保持原行为（点击不关窗，Esc / 关闭按钮退出）。
  Widget _dismissOnTap({required Widget child}) {
    if (_desktop) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _close,
      child: child,
    );
  }

  Widget _wrapPreviewShell({required Widget child}) {
    final body = CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _goPrev,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _goNext,
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: Material(color: Colors.black, child: child),
      ),
    );
    // 独立系统窗口：铺满；手机端仍用 Dialog。
    if (widget.onClose != null) {
      return SizedBox.expand(child: body);
    }
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 全屏预览会铺到状态栏下方，顶部控件必须避开系统安全区（刘海/挖孔），
    // 否则关闭按钮被状态栏遮住点不到；桌面独立窗 padding 为 0，不受影响。
    final topInset = MediaQuery.paddingOf(context).top;
    final webUrl = _webPublicUrl;
    if (webUrl != null) {
      return _wrapPreviewShell(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _dismissOnTap(
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
                  ),
                  Positioned(
                    top: 4 + topInset,
                    right: 4,
                    child: IconButton(
                      onPressed: _close,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 14 + topInset,
                    left: 14,
                    child: Row(
                      children: [
                        _metadataPill(
                          sizeBytes: _showingOriginal
                              ? _payloadSizeBytes
                              : null,
                          dimensions: null,
                          original: _showingOriginal,
                          force: _showingOriginal,
                        ),
                        if (_canBrowse) ...[
                          const SizedBox(width: 8),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Text(
                                '${_index + 1} / ${widget.items.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_canBrowse) ...[
                    Positioned(
                      left: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _navButton(
                          icon: Icons.chevron_left_rounded,
                          onTap: _index > 0 ? _goPrev : null,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _navButton(
                          icon: Icons.chevron_right_rounded,
                          onTap: _index < widget.items.length - 1
                              ? _goNext
                              : null,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
                        children: _buildActionChildren(
                          forWeb: true,
                          webUrl: webUrl,
                        ),
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

    return _wrapPreviewShell(
      child: FutureBuilder<Uint8List>(
        key: ValueKey<int>(_index),
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
                    Positioned.fill(child: _dismissOnTap(child: content)),
                    Positioned(
                      top: 4 + topInset,
                      right: 4,
                      child: IconButton(
                        onPressed: _close,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (!loading && !failed && bytes != null)
                      Positioned(
                        top: 14 + topInset,
                        left: 14,
                        child: Row(
                          children: [
                            _metadataPill(
                              sizeBytes: _showingOriginal
                                  ? (_payloadSizeBytes ?? originalBytes?.length)
                                  : originalBytes?.length,
                              dimensions: _dimensionsFuture,
                              original: _showingOriginal,
                            ),
                            if (_canBrowse) ...[
                              const SizedBox(width: 8),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    '${_index + 1} / ${widget.items.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (_canBrowse) ...[
                      Positioned(
                        left: 12,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _navButton(
                            icon: Icons.chevron_left_rounded,
                            onTap: _index > 0 ? _goPrev : null,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _navButton(
                            icon: Icons.chevron_right_rounded,
                            onTap: _index < widget.items.length - 1
                                ? _goNext
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
                            children: _buildActionChildren(
                              forWeb: false,
                              bytes: bytes,
                            ),
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

class _ChatImagePopupBody extends StatefulWidget {
  const _ChatImagePopupBody({
    required this.service,
    required this.payload,
    required this.fileName,
    this.conversationId,
  });

  final ConversationService service;
  final Map<String, dynamic>? payload;
  final String fileName;
  final int? conversationId;

  @override
  State<_ChatImagePopupBody> createState() => _ChatImagePopupBodyState();
}

class _ChatImagePopupBodyState extends State<_ChatImagePopupBody> {
  late final Future<Uint8List> _future = _loadBytes();
  var _saving = false;

  Future<Uint8List> _loadBytes() async {
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
      } catch (_) {}
    }
    return widget.service.loadCachedChatMediaBytesWithFallback(
      previewPayload: previewPayload,
      originalPayload: null,
    );
  }

  Future<void> _download(Uint8List bytes) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final key = ConversationService.mediaAuthObjectKey(
        ConversationService.previewMediaPayload(widget.payload),
      );
      if (key.isNotEmpty ||
          (widget.conversationId != null && widget.conversationId! > 0)) {
        await file_dl.saveBytesAsCachedFile(
          bytes,
          key,
          widget.fileName,
          conversationId: widget.conversationId,
        );
      } else {
        await file_dl.saveBytesAsFile(bytes, widget.fileName);
      }
      if (!mounted) return;
      showDunesToast(context, '已下载');
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        '下载失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          Flexible(
            child: ColoredBox(
              color: const Color(0xFFF3F4F6),
              child: FutureBuilder<Uint8List>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    );
                  }
                  final bytes = snap.data;
                  if (snap.hasError || bytes == null || bytes.isEmpty) {
                    return const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 48,
                        color: DunesColors.text3,
                      ),
                    );
                  }
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: InteractiveViewer(
                          maxScale: 5,
                          child: Center(
                            child: Image.memory(bytes, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: _saving ? null : () => _download(bytes),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.download_rounded,
                                    size: 16,
                                    color: Colors.white.withValues(
                                      alpha: _saving ? 0.5 : 1,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _saving ? '下载中…' : '下载',
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
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
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
