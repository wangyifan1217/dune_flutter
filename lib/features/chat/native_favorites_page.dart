import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_widgets.dart';
import '../shell/dunes_toast.dart';
import 'chat_file_preview_page.dart';
import 'chat_media_widgets.dart';
import 'chat_pdf_preview.dart';
import 'chat_video_widgets.dart';
import 'chat_widgets.dart';
import 'file_download.dart' as file_dl;

/// 企微式「我的收藏」：文本 / 图片预览 / 文件打开 + 来源人/群 + 收藏日期。
class NativeFavoritesPage extends StatefulWidget {
  const NativeFavoritesPage({
    super.key,
    required this.session,
    required this.onBack,
  });

  final AuthSession session;
  final VoidCallback onBack;

  @override
  State<NativeFavoritesPage> createState() => _NativeFavoritesPageState();
}

class _NativeFavoritesPageState extends State<NativeFavoritesPage> {
  late final ConversationService _service;
  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  String _query = '';
  List<NativeMessageFavorite> _items = const <NativeMessageFavorite>[];

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scroll.dispose();
    _service.close();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
      _load(reset: false);
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      final next = value.trim();
      if (next == _query) return;
      setState(() => _query = next);
      _load(reset: true);
    });
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    showDunesToast(
      context,
      message,
      kind: error ? DunesToastKind.error : DunesToastKind.normal,
    );
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      if (_loadingMore || !_hasMore || _items.isEmpty) return;
      setState(() => _loadingMore = true);
    }
    try {
      final page = await _service.fetchFavorites(
        beforeId: reset ? null : _items.last.id,
        query: _query,
      );
      if (!mounted) return;
      setState(() {
        _items = reset
            ? page.items
            : <NativeMessageFavorite>[..._items, ...page.items];
        _hasMore = page.hasMore;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (reset) _error = friendlyErrorText(e);
      });
      if (!reset) {
        _toast('加载失败：${friendlyErrorText(e)}', error: true);
      }
    }
  }

  Future<void> _remove(NativeMessageFavorite item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消收藏'),
        content: const Text('确定从收藏中移除这条消息？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.deleteFavorite(item.id);
      if (!mounted) return;
      setState(() {
        _items = _items.where((e) => e.id != item.id).toList(growable: false);
      });
      _toast('已取消收藏');
    } catch (e) {
      _toast('取消失败：${friendlyErrorText(e)}', error: true);
    }
  }

  Future<void> _openImage(NativeMessageFavorite item) async {
    final payload = item.payload;
    if (payload == null) {
      _toast('图片地址为空', error: true);
      return;
    }
    try {
      await showChatImagePreview(
        context,
        service: _service,
        payload: payload,
        fileName: ConversationService.mediaFileName(
          payload,
          fallback: 'image.jpg',
        ),
        conversationId: item.conversationId,
      );
    } catch (e) {
      _toast('预览失败：${friendlyErrorText(e)}', error: true);
    }
  }

  Future<void> _openVideo(NativeMessageFavorite item) async {
    try {
      await showChatVideoPlayer(
        context,
        service: _service,
        payload: item.payload,
      );
    } catch (e) {
      _toast('播放失败：${friendlyErrorText(e)}', error: true);
    }
  }

  Future<void> _openFile(NativeMessageFavorite item) async {
    final payload = item.payload;
    if (payload == null) {
      _toast('附件地址为空', error: true);
      return;
    }
    final fileName = ConversationService.mediaFileName(
      payload,
      fallback: item.bodyText.isEmpty
          ? '文件'
          : item.bodyText.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), ''),
    );

    if (chatPayloadIsPdf(payload, fileName)) {
      await showChatPdfPreview(
        context: context,
        service: _service,
        payload: payload,
        fileName: fileName,
        saveToDriveSession: widget.session,
      );
      return;
    }

    if (isDesktopCommOnly) {
      await _openFileOnDesktop(payload, fileName, item.conversationId);
      return;
    }

    if (!mounted) return;
    await showChatFilePreview(
      context: context,
      service: _service,
      payload: payload,
      fileName: fileName,
      conversationId: item.conversationId,
      saveToDriveSession: widget.session,
    );
  }

  Future<void> _openFileOnDesktop(
    Map<String, dynamic> payload,
    String fileName,
    int conversationId,
  ) async {
    final cacheKey = () {
      final objectKey = (payload['objectKey'] ?? '').toString().trim();
      if (objectKey.isNotEmpty) return objectKey;
      return ConversationService.mediaDirectUrl(payload);
    }();

    if (!kIsWeb && (cacheKey.isNotEmpty || conversationId > 0)) {
      final cached = await file_dl.findCachedChatFile(
        cacheKey,
        fileName,
        conversationId: conversationId,
      );
      if (cached != null && cached.isNotEmpty) {
        try {
          await file_dl.openLocalFile(cached);
          return;
        } catch (_) {}
      }
    }

    try {
      if (ConversationService.hasAuthMedia(payload)) {
        final bytes = await _service.downloadAttachmentBytes(
          objectKey: ConversationService.mediaObjectKey(payload),
          fileName: fileName,
        );
        final path = await file_dl.saveBytesAsCachedFile(
          bytes,
          cacheKey,
          fileName,
          conversationId: conversationId,
        );
        if (path != null && path.isNotEmpty) {
          await file_dl.openLocalFile(path);
        } else {
          _toast('下载完成');
        }
      } else {
        final url = ConversationService.mediaDirectUrl(payload);
        if (url.isEmpty) {
          _toast('附件地址为空', error: true);
          return;
        }
        await file_dl.openUrlAsFile(
          url,
          fileName,
          cacheKey: cacheKey.isEmpty ? null : cacheKey,
          conversationId: conversationId,
        );
      }
    } catch (e) {
      _toast('打开失败：${friendlyErrorText(e)}', error: true);
    }
  }

  String _copyableText(NativeMessageFavorite item) {
    final body = item.bodyText.trim();
    if (body.isNotEmpty) return body;
    return ConversationService.mediaFileName(item.payload, fallback: '').trim();
  }

  Future<void> _copy(NativeMessageFavorite item) async {
    final text = _copyableText(item);
    if (text.isEmpty) {
      _toast('该消息无可复制文本');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _toast('已复制');
  }

  void _onCardAction(NativeMessageFavorite item, String action) {
    final kind = _favoriteContentKind(item);
    switch (action) {
      case 'open':
        if (kind == 'IMAGE') unawaited(_openImage(item));
        if (kind == 'VIDEO') unawaited(_openVideo(item));
        if (kind == 'FILE') unawaited(_openFile(item));
      case 'copy':
        unawaited(_copy(item));
      case 'remove':
        unawaited(_remove(item));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            ChatConvHeader(
              title: '我的收藏',
              subtitle: _query.isEmpty
                  ? (_items.isEmpty ? '收藏的消息' : '下滑可加载更多')
                  : (_items.isEmpty ? '无匹配结果' : '搜索结果'),
              onBack: widget.onBack,
            ),
            ChatInboxSearchBar(
              controller: _searchController,
              onChanged: _onSearchChanged,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: DunesColors.accent,
        ),
      );
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: DunesTypography.sans(
                fontSize: 13,
                color: DunesColors.text3,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _load(reset: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 48,
              color: DunesColors.text3.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 12),
            Text(
              _query.isEmpty ? '暂无收藏' : '未找到相关收藏',
              style: DunesTypography.sans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: DunesColors.text2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _query.isEmpty ? '在聊天中长按消息即可收藏' : '试试其他关键词',
              style: DunesTypography.sans(
                fontSize: 13,
                color: DunesColors.text3,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        itemCount: _items.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final item = _items[index];
          final kind = _favoriteContentKind(item);
          return _FavoriteCard(
            item: item,
            kind: kind,
            service: _service,
            canCopy: _copyableText(item).isNotEmpty,
            onAction: (action) => _onCardAction(item, action),
            onOpenImage: () => unawaited(_openImage(item)),
            onOpenVideo: () => unawaited(_openVideo(item)),
            onOpenFile: () => unawaited(_openFile(item)),
          );
        },
      ),
    );
  }
}

/// 收藏列表只展示日期，不带时分秒。
String _favoriteDateLabel(DateTime? at) {
  if (at == null) return '';
  final local = at.isUtc ? at.toLocal() : at;
  final now = DateTime.now();
  if (local.year == now.year) {
    return '${local.month}月${local.day}日';
  }
  return '${local.year}年${local.month}月${local.day}日';
}

/// 收藏内容类型：FILE 优先于「文件名像图片」的误判。
String _favoriteContentKind(NativeMessageFavorite item) {
  final kind = item.kind.trim().toUpperCase();
  final body = item.bodyText.trim();
  final bodyLower = body.toLowerCase();

  if (kind == 'FILE' || bodyLower.startsWith('[文件]')) return 'FILE';
  if (kind == 'VIDEO' || bodyLower.startsWith('[视频]')) return 'VIDEO';
  if (kind == 'AUDIO' ||
      kind == 'VOICE' ||
      bodyLower.startsWith('[语音]')) {
    return 'AUDIO';
  }
  if (kind == 'IMAGE' ||
      bodyLower.startsWith('[图片]') ||
      bodyLower.startsWith('[相册]') ||
      bodyLower.startsWith('[拍照]') ||
      bodyLower.startsWith('[gif]')) {
    return 'IMAGE';
  }

  // kind 缺失时才按 payload 推断；有明确 FILE 时绝不能落到 IMAGE。
  if (kind.isEmpty || kind == 'TEXT') {
    final mime = (item.payload?['mimeType'] ?? '').toString().toLowerCase();
    final name = ConversationService.mediaFileName(
      item.payload,
      fallback: body.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), ''),
    ).toLowerCase();
    if (mime.startsWith('video/') ||
        name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm')) {
      return 'VIDEO';
    }
    if (mime.startsWith('audio/') ||
        name.endsWith('.m4a') ||
        name.endsWith('.aac') ||
        name.endsWith('.mp3')) {
      return 'AUDIO';
    }
    if (mime.startsWith('image/') ||
        name.endsWith('.png') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp') ||
        name.endsWith('.bmp') ||
        name.endsWith('.heic') ||
        name.endsWith('.heif')) {
      return 'IMAGE';
    }
    if (item.payload != null &&
        (ConversationService.hasAuthMedia(item.payload) ||
            ConversationService.mediaDirectUrl(item.payload).isNotEmpty ||
            ConversationService.mediaFileName(item.payload).isNotEmpty)) {
      return 'FILE';
    }
  }
  return kind.isEmpty ? 'TEXT' : kind;
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({
    required this.item,
    required this.kind,
    required this.service,
    required this.canCopy,
    required this.onAction,
    required this.onOpenImage,
    required this.onOpenVideo,
    required this.onOpenFile,
  });

  final NativeMessageFavorite item;
  final String kind;
  final ConversationService service;
  final bool canCopy;
  final ValueChanged<String> onAction;
  final VoidCallback onOpenImage;
  final VoidCallback onOpenVideo;
  final VoidCallback onOpenFile;

  @override
  Widget build(BuildContext context) {
    final dateLabel = _favoriteDateLabel(item.favoritedAt);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _kindIcon(kind),
                  size: 16,
                  color: const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _kindLabel(kind),
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: const Color(0xFF9CA3AF),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (dateLabel.isNotEmpty)
                  Text(
                    dateLabel,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            _buildContent(),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  item.isGroup
                      ? Icons.groups_outlined
                      : Icons.person_outline_rounded,
                  size: 15,
                  color: const Color(0xFF6B7280),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.sourceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 12.5,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ),
                if (item.senderName.isNotEmpty && item.isGroup) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      item.senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                ],
                PopupMenuButton<String>(
                  tooltip: '更多',
                  padding: EdgeInsets.zero,
                  offset: const Offset(0, 36),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onSelected: onAction,
                  itemBuilder: (ctx) => <PopupMenuEntry<String>>[
                    if (kind == 'IMAGE')
                      const PopupMenuItem(
                        value: 'open',
                        child: Text('查看图片'),
                      ),
                    if (kind == 'VIDEO')
                      const PopupMenuItem(
                        value: 'open',
                        child: Text('播放视频'),
                      ),
                    if (kind == 'FILE')
                      const PopupMenuItem(
                        value: 'open',
                        child: Text('打开文件'),
                      ),
                    if (canCopy)
                      const PopupMenuItem(
                        value: 'copy',
                        child: Text('复制'),
                      ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text('取消收藏'),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(8, 4, 4, 4),
                    child: Icon(
                      Icons.more_horiz_rounded,
                      size: 20,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (kind) {
      case 'IMAGE':
        if (item.payload == null) {
          return _selectableBodyText(item.previewText);
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: ChatAuthImageBubble(
            service: service,
            payload: item.payload,
            mine: false,
            conversationId: item.conversationId,
            onTap: onOpenImage,
          ),
        );
      case 'VIDEO':
        if (item.payload == null) {
          return _selectableBodyText(item.previewText);
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: ChatAuthVideoBubble(
            service: service,
            payload: item.payload,
            mine: false,
            onTap: onOpenVideo,
          ),
        );
      case 'FILE':
        final fileName = ConversationService.mediaFileName(
          item.payload,
          fallback: item.bodyText.isEmpty
              ? '文件'
              : item.bodyText.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), ''),
        );
        return Align(
          alignment: Alignment.centerLeft,
          child: ChatFileAttach(
            fileName: fileName,
            mine: false,
            fileSizeBytes: (item.payload?['size'] as num?)?.toInt(),
            onTap: onOpenFile,
          ),
        );
      case 'AUDIO':
      case 'VOICE':
        final sec = (item.payload?['durationSec'] as num?)?.toInt() ?? 0;
        final label = sec > 0 ? '语音 $sec″' : '语音消息';
        return Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: DunesColors.accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.mic_none_rounded,
                color: DunesColors.accentDeep,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: DunesTypography.sans(
                fontSize: 15,
                color: const Color(0xFF1C1C1C),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      default:
        return _selectableBodyText(
          item.bodyText.trim().isNotEmpty ? item.bodyText : item.previewText,
        );
    }
  }

  Widget _selectableBodyText(String text) {
    final style = DunesTypography.sans(
      fontSize: 15,
      height: 1.45,
      color: const Color(0xFF1C1C1C),
    );
    // PC：拖拽选区 + 右键复制；APP：长按选区 + 系统复制菜单。
    return SelectableText(
      text,
      style: style,
      contextMenuBuilder: (context, editableTextState) {
        return AdaptiveTextSelectionToolbar.editableText(
          editableTextState: editableTextState,
        );
      },
    );
  }

  IconData _kindIcon(String kind) {
    switch (kind) {
      case 'IMAGE':
        return Icons.image_outlined;
      case 'FILE':
        return Icons.insert_drive_file_outlined;
      case 'AUDIO':
      case 'VOICE':
        return Icons.mic_none_rounded;
      case 'VIDEO':
        return Icons.videocam_outlined;
      default:
        return Icons.chat_bubble_outline_rounded;
    }
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'IMAGE':
        return '图片';
      case 'FILE':
        return '文件';
      case 'AUDIO':
      case 'VOICE':
        return '语音';
      case 'VIDEO':
        return '视频';
      default:
        return '文本';
    }
  }
}
