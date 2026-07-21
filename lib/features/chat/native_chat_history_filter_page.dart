import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../shell/dunes_toast.dart';
import 'chat_history_filter.dart';
import 'chat_media_widgets.dart';
import 'chat_video_widgets.dart';
import 'cors_safe_image.dart';
import 'file_download.dart' as file_dl;

Future<void> openChatHistoryFilterPage({
  required BuildContext context,
  required AuthSession session,
  required int conversationId,
  required ChatHistoryFilter filter,
  required ValueChanged<NativeChatMessage> onLocateMessage,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => NativeChatHistoryFilterPage(
        session: session,
        conversationId: conversationId,
        filter: filter,
        onLocateMessage: onLocateMessage,
      ),
    ),
  );
}

class NativeChatHistoryFilterPage extends StatefulWidget {
  const NativeChatHistoryFilterPage({
    super.key,
    required this.session,
    required this.conversationId,
    required this.filter,
    required this.onLocateMessage,
  });

  final AuthSession session;
  final int conversationId;
  final ChatHistoryFilter filter;
  final ValueChanged<NativeChatMessage> onLocateMessage;

  @override
  State<NativeChatHistoryFilterPage> createState() =>
      _NativeChatHistoryFilterPageState();
}

class _NativeChatHistoryFilterPageState
    extends State<NativeChatHistoryFilterPage> {
  static const _pageSize = 40;
  static const _targetBatch = 30;

  late final ConversationService _service;
  final ScrollController _scrollController = ScrollController();
  final Map<int, Future<Uint8List>> _imageBytesCache =
      <int, Future<Uint8List>>{};

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _oldestId = 0;
  List<NativeChatMessage> _items = const <NativeChatMessage>[];

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _scrollController.addListener(_onScroll);
    unawaited(_load());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

  void _onScroll() {
    if (!_scrollController.hasClients || _loading || _loadingMore || !_hasMore) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 120) {
      unawaited(_load(append: true));
    }
  }

  int _oldestMessageId(Iterable<NativeChatMessage> items) {
    var oldest = 0;
    for (final m in items) {
      if (m.id <= 0) continue;
      if (oldest == 0 || m.id < oldest) oldest = m.id;
    }
    return oldest;
  }

  List<NativeChatMessage> _merge(
    List<NativeChatMessage> a,
    List<NativeChatMessage> b,
  ) {
    final map = <int, NativeChatMessage>{};
    for (final m in [...a, ...b]) {
      if (m.id > 0) {
        map[m.id] = m;
      } else {
        map[Object.hash(m.kind, m.bodyText, m.createdAt)] = m;
      }
    }
    return map.values.toList()..sort((x, y) => y.id.compareTo(x.id));
  }

  Future<void> _load({bool append = false}) async {
    if (append) {
      if (_loadingMore || !_hasMore || _oldestId <= 0) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _oldestId = 0;
        _hasMore = true;
      });
    }

    try {
      final collected = <NativeChatMessage>[];
      var cursor = append && _oldestId > 0 ? _oldestId : 0;
      var hasMore = true;
      var guard = 0;

      while (collected.length < _targetBatch && hasMore && guard < 8) {
        guard++;
        final page = await _fetchPage(before: cursor > 0 ? cursor : null);
        if (page.items.isEmpty) {
          hasMore = false;
          break;
        }
        final matched = page.items
            .where((m) => chatHistoryFilterMatches(widget.filter, m))
            .toList(growable: false);
        collected.addAll(matched);
        cursor = _oldestMessageId(page.items);
        hasMore = page.hasMore && page.items.isNotEmpty && cursor > 0;
        if (!hasMore) break;
      }

      if (!mounted) return;
      setState(() {
        if (append) {
          _items = _merge(_items, collected);
        } else {
          _items = collected;
        }
        _oldestId = cursor;
        _hasMore = hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<({List<NativeChatMessage> items, bool hasMore})> _fetchPage({
    int? before,
  }) async {
    if (widget.filter.usesMediaApi) {
      final rows = await _service.fetchConversationMedia(
        widget.conversationId,
        size: _pageSize,
        before: before,
      );
      return (items: rows, hasMore: rows.length >= _pageSize);
    }
    final page = await _service.searchMessagePage(
      conversationId: widget.conversationId,
      query: '',
      size: _pageSize,
      before: before,
    );
    return (items: page.items, hasMore: page.hasMore && page.items.isNotEmpty);
  }

  Future<Uint8List> _imageBytesFor(NativeChatMessage message) {
    final key = message.id > 0
        ? message.id
        : Object.hash(message.kind, message.bodyText, message.createdAt);
    return _imageBytesCache.putIfAbsent(
      key,
      () => _service.loadCachedChatMediaBytes(message.payload),
    );
  }

  Future<void> _openImage(NativeChatMessage m) async {
    final payload = m.payload;
    if (payload == null) return;
    try {
      await showChatImagePreview(
        context,
        service: _service,
        payload: payload,
        fileName: ConversationService.mediaFileName(payload, fallback: 'image.jpg'),
        conversationId: widget.conversationId,
      );
    } catch (e) {
      _toast('预览失败：${friendlyErrorText(e)}');
    }
  }

  Future<void> _openVideo(NativeChatMessage m) async {
    await showChatVideoPlayer(
      context,
      service: _service,
      payload: m.payload,
    );
  }

  Future<void> _openFile(NativeChatMessage m) async {
    final payload = m.payload;
    if (payload == null) {
      _toast('附件地址为空');
      return;
    }
    final fileName = ConversationService.mediaFileName(
      payload,
      fallback: m.bodyText.isEmpty ? 'download' : m.bodyText,
    );
    final cacheKey = () {
      final objectKey = (payload['objectKey'] ?? '').toString().trim();
      if (objectKey.isNotEmpty) return objectKey;
      return ConversationService.mediaDirectUrl(payload);
    }();

    if (!kIsWeb && (cacheKey.isNotEmpty || widget.conversationId > 0)) {
      final cached = await file_dl.findCachedChatFile(
        cacheKey,
        fileName,
        conversationId: widget.conversationId,
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
          conversationId: widget.conversationId,
        );
        if (path != null && path.isNotEmpty) {
          await file_dl.openLocalFile(path);
        } else {
          _toast('下载完成');
        }
      } else {
        final url = ConversationService.mediaDirectUrl(payload);
        if (url.isEmpty) {
          _toast('附件地址为空');
          return;
        }
        await file_dl.openUrlAsFile(
          url,
          fileName,
          cacheKey: cacheKey.isEmpty ? null : cacheKey,
          conversationId: widget.conversationId,
        );
      }
    } catch (e) {
      _toast('打开失败：${friendlyErrorText(e)}');
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _toast('链接无效');
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      _toast('无法打开链接');
    }
  }

  void _locate(NativeChatMessage m) {
    // 由上层 popTo 会话；C12 整页会被替换，无需再 pop 筛选页。
    widget.onLocateMessage(m);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        child: Column(
          children: [
            _FilterHeader(
              title: widget.filter.title,
              count: _items.length,
              onBack: () => Navigator.of(context).pop(),
              onRefresh: () => unawaited(_load()),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: const TextStyle(fontSize: 12, color: DunesColors.text3),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          widget.filter.emptyHint,
          style: const TextStyle(fontSize: 13, color: DunesColors.text3),
        ),
      );
    }

    switch (widget.filter) {
      case ChatHistoryFilter.imageVideo:
        return _buildImageVideoGrid();
      case ChatHistoryFilter.files:
        return _buildFileList();
      case ChatHistoryFilter.links:
        return _buildLinkList();
      case ChatHistoryFilter.forwards:
        return _buildForwardList();
    }
  }

  Widget _footerLoader() {
    if (!_loadingMore && !_hasMore) return const SizedBox(height: 20);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _loadingMore
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const SizedBox(height: 8),
      ),
    );
  }

  Widget _buildImageVideoGrid() {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _items.length + 1,
      itemBuilder: (_, index) {
        if (index >= _items.length) return _footerLoader();
        final m = _items[index];
        final isVideo = m.kind.toUpperCase() == 'VIDEO';
        return GestureDetector(
          onTap: () => isVideo ? unawaited(_openVideo(m)) : unawaited(_openImage(m)),
          onLongPress: () => _locate(m),
          child: _MediaThumb(
            message: m,
            isVideo: isVideo,
            loadBytes: () => _imageBytesFor(m),
          ),
        );
      },
    );
  }

  Widget _buildFileList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: _items.length + 1,
      itemBuilder: (_, index) {
        if (index >= _items.length) return _footerLoader();
        final m = _items[index];
        final name = ConversationService.mediaFileName(
          m.payload,
          fallback: m.bodyText.isEmpty ? '文件' : m.bodyText,
        );
        return _FilterListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: DunesColors.blueSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.insert_drive_file_outlined, color: DunesColors.blue),
          ),
          title: name,
          subtitle: '${m.senderName} · ${InboxFormat.formatTime(m.createdAt, withClock: true)}',
          onTap: () => unawaited(_openFile(m)),
          onLocate: () => _locate(m),
        );
      },
    );
  }

  Widget _buildLinkList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: _items.length + 1,
      itemBuilder: (_, index) {
        if (index >= _items.length) return _footerLoader();
        final m = _items[index];
        final link = chatMessageFirstLink(m) ?? '';
        return _FilterListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: DunesColors.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.link_rounded, color: DunesColors.accentDeep),
          ),
          title: link,
          subtitle: '${m.senderName} · ${InboxFormat.formatTime(m.createdAt, withClock: true)}',
          onTap: () => unawaited(_openLink(link)),
          onLocate: () => _locate(m),
        );
      },
    );
  }

  Widget _buildForwardList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: _items.length + 1,
      itemBuilder: (_, index) {
        if (index >= _items.length) return _footerLoader();
        final m = _items[index];
        final count = chatForwardItemCount(m);
        final title = chatForwardTitle(m);
        return _FilterListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: DunesColors.amberSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.reply_all_rounded, color: DunesColors.amber),
          ),
          title: title,
          subtitle:
              '${m.senderName} · ${count > 0 ? '$count条 · ' : ''}${InboxFormat.formatTime(m.createdAt, withClock: true)}',
          onTap: () => _locate(m),
          onLocate: () => _locate(m),
        );
      },
    );
  }
}

class _FilterHeader extends StatelessWidget {
  const _FilterHeader({
    required this.title,
    required this.count,
    required this.onBack,
    required this.onRefresh,
  });

  final String title;
  final int count;
  final VoidCallback onBack;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 10),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DunesTypography.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
                if (count > 0)
                  Text(
                    '$count 项',
                    style: DunesTypography.mono(
                      fontSize: 10,
                      color: DunesColors.text3,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: DunesColors.text2,
            tooltip: '刷新',
          ),
        ],
      ),
    );
  }
}

class _FilterListTile extends StatelessWidget {
  const _FilterListTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onLocate,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: DunesColors.bgApp,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLocate,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DunesColors.borderSoft),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: DunesColors.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 11.5,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onLocate,
                  tooltip: '定位到聊天',
                  icon: const Icon(Icons.my_location_outlined, size: 18),
                  color: DunesColors.accentDeep,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({
    required this.message,
    required this.isVideo,
    required this.loadBytes,
  });

  final NativeChatMessage message;
  final bool isVideo;
  final Future<Uint8List> Function() loadBytes;

  @override
  Widget build(BuildContext context) {
    final payload = message.payload;
    Widget child = Container(
      color: DunesColors.bgSoft,
      child: Icon(
        isVideo ? Icons.videocam_outlined : Icons.image_outlined,
        color: DunesColors.text3,
        size: 22,
      ),
    );

    if (payload != null && !isVideo) {
      final publicUrl = ConversationService.mediaPublicImageUrl(payload);
      if (publicUrl != null && publicUrl.isNotEmpty) {
        child = buildCorsSafeImage(
          url: publicUrl,
          fit: BoxFit.cover,
          width: 200,
          height: 200,
        );
      } else if (ConversationService.hasAuthMedia(payload)) {
        child = FutureBuilder<Uint8List>(
          future: loadBytes(),
          builder: (_, snap) {
            if (!snap.hasData) {
              return Container(
                color: DunesColors.bgSoft,
                child: const Center(
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ),
              );
            }
            return Image.memory(
              snap.data!,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            );
          },
        );
      }
    } else if (isVideo) {
      child = Container(
        color: const Color(0xFF2A2A2A),
        child: const Center(
          child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 30),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (isVideo)
            const Positioned(
              right: 4,
              bottom: 4,
              child: Icon(Icons.videocam, size: 14, color: Colors.white),
            ),
        ],
      ),
    );
  }
}
