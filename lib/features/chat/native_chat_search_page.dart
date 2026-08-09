import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../contacts/contact_service.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../kb/kb_chat_share.dart';
import '../meeting/meeting_minutes_chat_share.dart';
import 'chat_history_filter.dart';
import 'chat_media_widgets.dart';
import 'chat_file_type_icon.dart';
import 'chat_video_widgets.dart';
import 'chat_widgets.dart';
import 'cors_safe_image.dart';
import 'user_avatar_widget.dart';

class NativeChatSearchPage extends StatefulWidget {
  const NativeChatSearchPage({
    super.key,
    required this.session,
    required this.conversationId,
    required this.title,
    required this.onBack,
    required this.onLocateMessage,
  });

  final AuthSession session;
  final int conversationId;
  final String title;
  final VoidCallback onBack;
  final ValueChanged<NativeChatMessage> onLocateMessage;

  @override
  State<NativeChatSearchPage> createState() => _NativeChatSearchPageState();
}

class _SearchListEntry {
  const _SearchListEntry.divider(this.label) : message = null;
  const _SearchListEntry.message(this.message) : label = null;

  final String? label;
  final NativeChatMessage? message;
}

class _NativeChatSearchPageState extends State<NativeChatSearchPage> {
  static const _pageSize = 20;
  static const _filterPageSize = 40;
  static const _filterTargetBatch = 20;

  late final ConversationService _service;
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;
  int _oldestId = 0;
  List<NativeChatMessage> _items = const <NativeChatMessage>[];
  ChatHistoryFilter? _selectedFilter;
  ChatHistoryTimeRange? _timeRange;
  Map<int, ({String? preset, String? objectKey})> _avatarByUserId =
      const <int, ({String? preset, String? objectKey})>{};
  String? _peerAvatarPreset;
  String? _peerAvatarObjectKey;
  int? _peerUserId;
  String? _selfAvatarPreset;
  String? _selfAvatarObjectKey;

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _scrollController.addListener(_onScroll);
    _queryController.addListener(() {
      if (mounted) setState(() {});
    });
    unawaited(_loadAvatarContext());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _search();
      }
    });
  }

  Future<void> _loadAvatarContext() async {
    try {
      final conv = await _service.fetchConversation(widget.conversationId);
      if (conv == null || !mounted) return;
      _peerAvatarPreset = conv.peerAvatarPreset;
      _peerAvatarObjectKey = conv.peerAvatarObjectKey;
      _peerUserId = conv.peerUserId;
      final isPrivate = conv.kind.toUpperCase() == 'PRIVATE';
      if (isPrivate) {
        final peerId = conv.peerUserId ?? 0;
        if (peerId > 0) {
          final contact = await ContactService(
            session: widget.session,
          ).fetchContact(peerId);
          if (contact != null) {
            _peerAvatarPreset ??= contact.avatarPreset;
            _peerAvatarObjectKey ??= contact.avatarObjectKey;
          }
        }
      } else {
        try {
          final members = await _service.fetchConversationMembers(
            widget.conversationId,
          );
          if (mounted) {
            _avatarByUserId = _service.avatarMapFromMembers(members);
          }
        } catch (_) {
          try {
            final info = await _service.fetchGroupInfo(widget.conversationId);
            if (mounted) {
              _avatarByUserId = {
                for (final m in info.members)
                  m.userId: (
                    preset: m.avatarPreset,
                    objectKey: m.avatarObjectKey,
                  ),
              };
            }
          } catch (_) {}
        }
      }
      final meResp = await ContactService(
        session: widget.session,
      ).fetchContact(widget.session.userId);
      if (meResp != null && mounted) {
        _selfAvatarPreset = meResp.avatarPreset;
        _selfAvatarObjectKey = meResp.avatarObjectKey;
      }
    } catch (_) {}
    if (mounted && _items.isNotEmpty) {
      setState(() {
        _items = _enrichItems(_items);
      });
    }
  }

  List<NativeChatMessage> _enrichItems(List<NativeChatMessage> items) {
    return _service.enrichMessagesWithAvatars(
      items,
      avatarByUserId: _avatarByUserId,
      peerAvatarPreset: _peerAvatarPreset,
      peerAvatarObjectKey: _peerAvatarObjectKey,
      peerUserId: _peerUserId,
      selfUserId: widget.session.userId,
      selfAvatarPreset: _selfAvatarPreset,
      selfAvatarObjectKey: _selfAvatarObjectKey,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 80) {
      unawaited(_search(append: true));
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

  void _selectFilter(ChatHistoryFilter filter) {
    final next = _selectedFilter == filter ? null : filter;
    setState(() {
      _selectedFilter = next;
      if (next != null) {
        _queryController.clear();
      }
    });
    unawaited(_search());
  }

  void _applyTimeRange(ChatHistoryTimeRange? range) {
    setState(() => _timeRange = range);
    unawaited(_search());
  }

  Future<void> _openTimeRangeSheet() async {
    final action = await showModalBottomSheet<_TimeRangeSheetAction>(
      context: context,
      backgroundColor: DunesColors.bgApp,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ChatHistoryTimeRangeSheet(current: _timeRange),
    );
    if (!mounted || action == null) return;
    if (action.clear) {
      _applyTimeRange(null);
      return;
    }
    if (action.pickCustom) {
      await _pickCustomTimeRange();
      return;
    }
    if (action.range != null) {
      _applyTimeRange(action.range);
    }
  }

  Future<void> _pickCustomTimeRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _timeRange == null
        ? DateTimeRange(
            start: today.subtract(const Duration(days: 6)),
            end: today,
          )
        : DateTimeRange(
            start: DateTime(
              _timeRange!.start.year,
              _timeRange!.start.month,
              _timeRange!.start.day,
            ),
            end: DateTime(
              _timeRange!.end.year,
              _timeRange!.end.month,
              _timeRange!.end.day,
            ),
          );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: today.subtract(const Duration(days: 365 * 3)),
      lastDate: today,
      initialDateRange: initial,
      helpText: '选择时间段',
      saveText: '确定',
      cancelText: '取消',
      builder: (context, child) {
        final base = Theme.of(context);
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: DunesColors.accent,
              onPrimary: Colors.white,
              surface: DunesColors.bgApp,
              onSurface: DunesColors.text,
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: DunesColors.bgApp,
              headerBackgroundColor: DunesColors.bgSoft,
              headerForegroundColor: DunesColors.text,
              rangeSelectionBackgroundColor: DunesColors.accentSoft,
              rangeSelectionOverlayColor: WidgetStateProperty.all(
                DunesColors.accent.withValues(alpha: 0.08),
              ),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                if (states.contains(WidgetState.disabled)) {
                  return DunesColors.text3;
                }
                return DunesColors.text;
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return DunesColors.accent;
                }
                return Colors.transparent;
              }),
              todayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return DunesColors.accent;
              }),
              todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return DunesColors.accent;
                }
                return Colors.transparent;
              }),
            ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted || picked == null) return;
    _applyTimeRange(ChatHistoryTimeRange.custom(picked));
  }

  Future<({List<NativeChatMessage> items, bool hasMore, int oldestId})>
  _fetchFilteredPage({
    required ChatHistoryFilter? filter,
    required ChatHistoryTimeRange? timeRange,
    required String query,
    required int cursor,
  }) async {
    final collected = <NativeChatMessage>[];
    var nextCursor = cursor;
    var hasMore = true;
    var guard = 0;
    final q = query.trim();
    final useMedia = filter != null && filter.usesMediaApi && q.isEmpty;
    final from = timeRange?.apiFrom;
    final to = timeRange?.apiTo;
    // 链接/转发仍需本地匹配；时间由服务端 from/to 过滤。
    final needsLocalTypeFilter = filter != null && !filter.usesMediaApi;

    while (collected.length < _filterTargetBatch && hasMore && guard < 8) {
      guard++;
      final before = nextCursor > 0 ? nextCursor : null;
      late final List<NativeChatMessage> pageItems;
      late final bool pageHasMore;

      if (useMedia) {
        final rows = await _service.fetchConversationMedia(
          widget.conversationId,
          size: _filterPageSize,
          before: before,
          from: from,
          to: to,
        );
        pageItems = rows;
        pageHasMore = rows.length >= _filterPageSize;
      } else {
        final page = await _service.searchMessagePage(
          conversationId: widget.conversationId,
          query: q,
          size: _filterPageSize,
          before: before,
          from: from,
          to: to,
        );
        pageItems = page.items;
        pageHasMore = page.hasMore && page.items.isNotEmpty;
      }

      if (pageItems.isEmpty) {
        hasMore = false;
        break;
      }

      if (needsLocalTypeFilter) {
        collected.addAll(
          pageItems.where((m) => chatHistoryFilterMatches(filter, m)),
        );
      } else if (filter == ChatHistoryFilter.imageVideo) {
        collected.addAll(
          pageItems.where((m) {
            final k = m.kind.toUpperCase();
            return k == 'IMAGE' || k == 'VIDEO';
          }),
        );
      } else if (filter == ChatHistoryFilter.files) {
        collected.addAll(
          pageItems.where((m) => m.kind.toUpperCase() == 'FILE'),
        );
      } else {
        collected.addAll(pageItems);
      }

      nextCursor = _oldestMessageId(pageItems);
      hasMore = pageHasMore && nextCursor > 0;
      if (!hasMore) break;
    }

    return (items: collected, hasMore: hasMore, oldestId: nextCursor);
  }

  Future<void> _search({bool append = false}) async {
    final q = _queryController.text.trim();
    final filter = _selectedFilter;
    final timeRange = _timeRange;
    final needsClientFilter = filter != null || timeRange != null;

    if (append) {
      if (_loadingMore || !_hasMore || _oldestId <= 0) return;
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _loading = true;
        _error = null;
        _oldestId = 0;
        _hasMore = false;
      });
    }

    try {
      if (needsClientFilter) {
        final page = await _fetchFilteredPage(
          filter: filter,
          timeRange: timeRange,
          query: q,
          cursor: append && _oldestId > 0 ? _oldestId : 0,
        );
        if (!mounted) return;
        setState(() {
          if (append) {
            _items = _enrichItems(_merge(_items, page.items));
          } else {
            _items = _enrichItems(page.items);
          }
          _oldestId = page.oldestId;
          _hasMore = page.hasMore;
          _loading = false;
          _loadingMore = false;
        });
        return;
      }

      final page = await _service.searchMessagePage(
        conversationId: widget.conversationId,
        query: q,
        size: _pageSize,
        before: append && _oldestId > 0 ? _oldestId : null,
      );
      if (!mounted) return;
      setState(() {
        if (append) {
          _items = _enrichItems(_merge(_items, page.items));
        } else {
          _items = _enrichItems(page.items);
        }
        _oldestId = _oldestMessageId(_items);
        _hasMore = page.hasMore && page.items.isNotEmpty;
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

  List<NativeChatMessage> _merge(
    List<NativeChatMessage> a,
    List<NativeChatMessage> b,
  ) {
    final map = <int, NativeChatMessage>{};
    for (final m in [...a, ...b]) {
      if (m.id > 0) map[m.id] = m;
    }
    return map.values.toList()..sort((x, y) => y.id.compareTo(x.id));
  }

  String _hitBody(NativeChatMessage m) {
    final meeting = MeetingMinutesChatShare.fromPayload(m.payload);
    if (meeting != null) return meeting.bodyText;
    final kb = KbChatDocShare.fromPayload(m.payload);
    if (kb != null) return kb.bodyText;
    if (chatMessageIsForward(m)) {
      final title = chatForwardTitle(m);
      final count = chatForwardItemCount(m);
      return count > 0 ? '$title（$count条）' : title;
    }
    final link = chatMessageFirstLink(m);
    if (link != null) return link;
    final kind = m.kind.toUpperCase();
    if (kind == 'IMAGE') return '发送了一张图片';
    if (kind == 'VIDEO') return '发送了一个视频';
    if (kind == 'FILE') return m.bodyText.isEmpty ? '发送了一个文件' : m.bodyText;
    if (kind == 'AUDIO') return '发送了一条语音';
    return m.bodyText.isEmpty ? '[${m.kind}]' : m.bodyText;
  }

  List<_SearchListEntry> _buildEntries() {
    final sorted = _items.toList()..sort((a, b) => b.id.compareTo(a.id));
    final entries = <_SearchListEntry>[];
    String? lastDivider;
    for (final m in sorted) {
      final label = InboxFormat.dayDividerLabel(m.createdAt);
      if (label != null && label != lastDivider) {
        entries.add(_SearchListEntry.divider(label));
        lastDivider = label;
      }
      entries.add(_SearchListEntry.message(m));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.chevron_left_rounded, size: 28),
                  ),
                  Expanded(
                    child: Text(
                      '查找聊天内容',
                      style: DunesTypography.sans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: DunesColors.bgSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search,
                      size: 16,
                      color: DunesColors.text3,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _queryController,
                        onSubmitted: (_) {
                          setState(() => _selectedFilter = null);
                          _search();
                        },
                        onChanged: (value) {
                          if (value.trim().isEmpty && _selectedFilter == null) {
                            _search();
                          }
                        },
                        style: DunesTypography.sans(
                          fontSize: 13,
                          color: DunesColors.text,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: '搜消息 / 文件 / @mention',
                          hintStyle: DunesTypography.sans(
                            fontSize: 13,
                            color: DunesColors.text3,
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (_queryController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _queryController.clear();
                          setState(() => _selectedFilter = null);
                          _search();
                        },
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: DunesColors.text3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _ChatHistoryCategoryGrid(
              selected: _selectedFilter,
              timeActive: _timeRange != null,
              onSelect: _selectFilter,
              onSelectTime: _openTimeRangeSheet,
            ),
            if (_timeRange != null)
              _ChatHistoryTimeRangeChip(
                label: _timeRange!.label,
                onClear: () => _applyTimeRange(null),
                onTap: _openTimeRangeSheet,
              ),
            Expanded(child: _buildResults(entries)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(List<_SearchListEntry> entries) {
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
    if (entries.isEmpty) {
      final emptyText =
          _selectedFilter?.emptyHint ??
          (_timeRange != null
              ? '该时间段暂无消息'
              : (_queryController.text.trim().isEmpty ? '暂无历史消息' : '暂无搜索结果'));
      return Center(
        child: Text(
          emptyText,
          style: const TextStyle(fontSize: 12, color: DunesColors.text3),
        ),
      );
    }
    if (_selectedFilter == ChatHistoryFilter.imageVideo) {
      final media = _items.where((m) {
        final kind = m.kind.toUpperCase();
        return kind == 'IMAGE' || kind == 'VIDEO';
      }).toList()..sort((a, b) => b.id.compareTo(a.id));
      final monthGroups = <String, List<NativeChatMessage>>{};
      for (final message in media) {
        final date = message.createdAt?.toLocal();
        final key = date == null ? '时间未知' : '${date.year}年${date.month}月';
        monthGroups.putIfAbsent(key, () => <NativeChatMessage>[]).add(message);
      }
      return CustomScrollView(
        controller: _scrollController,
        slivers: [
          for (final group in monthGroups.entries) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Text(
                  group.key,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text2,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 150,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                delegate: SliverChildBuilderDelegate((_, index) {
                  final message = group.value[index];
                  return _ChatSearchMediaTile(
                    message: message,
                    service: _service,
                    onTap: () => widget.onLocateMessage(message),
                  );
                }, childCount: group.value.length),
              ),
            ),
          ],
          if (_loadingMore || _hasMore)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: _loadingMore
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const SizedBox(height: 20),
              ),
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      );
    }
    return ListView.builder(
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: entries.length + (_loadingMore || _hasMore ? 1 : 0),
      itemBuilder: (_, index) {
        if (index == entries.length) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return const SizedBox(height: 24);
        }
        final entry = entries[index];
        if (entry.label != null) {
          return ChatDateDivider(label: entry.label!);
        }
        final m = entry.message!;
        final isFileResult =
            _selectedFilter == ChatHistoryFilter.files &&
            m.kind.toUpperCase() == 'FILE';
        final fileName = isFileResult
            ? ConversationService.mediaFileName(
                m.payload,
                fallback: m.bodyText.isEmpty ? '文件' : m.bodyText,
              )
            : '';
        return ChatSearchHitCard(
          senderName: m.senderName,
          body: _hitBody(m),
          timeLabel: InboxFormat.formatTime(m.createdAt, withClock: true),
          avatar: isFileResult
              ? SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ChatFileTypeIcon(fileName: fileName, size: 40),
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: ImUserAvatar(
                          initial: m.senderName.isNotEmpty
                              ? m.senderName.substring(0, 1)
                              : '?',
                          seed: m.senderUserId,
                          size: 18,
                          avatarPreset: m.senderAvatarPreset,
                          avatarObjectKey: m.senderAvatarObjectKey,
                          avatarService: _service,
                          borderRadius: 6,
                        ),
                      ),
                    ],
                  ),
                )
              : ImUserAvatar(
                  initial: m.senderName.isNotEmpty
                      ? m.senderName.substring(0, 1)
                      : '?',
                  seed: m.senderUserId,
                  size: 34,
                  avatarPreset: m.senderAvatarPreset,
                  avatarObjectKey: m.senderAvatarObjectKey,
                  avatarService: _service,
                  borderRadius: 34 * 0.18,
                ),
          onTap: () => widget.onLocateMessage(m),
        );
      },
    );
  }
}

/// 微信式「图片与视频」搜索结果：先预览，再由预览页决定是否定位原消息。
class _ChatSearchMediaTile extends StatelessWidget {
  const _ChatSearchMediaTile({
    required this.message,
    required this.service,
    required this.onTap,
  });

  final NativeChatMessage message;
  final ConversationService service;
  final VoidCallback onTap;

  Future<void> _openPreview(BuildContext context) async {
    final fileName = ConversationService.mediaFileName(
      message.payload,
      fallback: message.kind.toUpperCase() == 'VIDEO'
          ? 'video.mp4'
          : 'image.jpg',
    );
    if (message.kind.toUpperCase() == 'VIDEO') {
      await showChatVideoPlayer(
        context,
        service: service,
        payload: message.payload,
        title: fileName,
        onLocateInChat: onTap,
      );
      return;
    }
    await showChatImagePreview(
      context,
      service: service,
      payload: message.payload,
      fileName: fileName,
      onLocateInChat: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = message.kind.toUpperCase() == 'VIDEO';
    final payload = isVideo
        ? ConversationService.previewMediaPayload(message.payload)
        : message.payload;
    final publicUrl = ConversationService.mediaPublicImageUrl(payload);
    Widget child = Container(
      color: isVideo ? const Color(0xFF2A2A2A) : DunesColors.bgSoft,
      alignment: Alignment.center,
      child: Icon(
        isVideo ? Icons.videocam_outlined : Icons.image_outlined,
        color: isVideo ? Colors.white54 : DunesColors.text3,
      ),
    );
    if (publicUrl != null && publicUrl.isNotEmpty) {
      child = buildCorsSafeImage(
        url: publicUrl,
        fit: BoxFit.cover,
        width: 200,
        height: 200,
        hitTestOverlay: true,
      );
    } else if (ConversationService.hasAuthMedia(payload)) {
      child = FutureBuilder<Uint8List>(
        future: service.loadCachedChatMediaBytes(payload),
        builder: (_, snapshot) {
          if (!snapshot.hasData) {
            return Container(
              color: DunesColors.bgSoft,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        },
      );
    }
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _openPreview(context),
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (isVideo)
                const Center(
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 5,
                child: Text(
                  message.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    shadows: [Shadow(blurRadius: 3, color: Colors.black)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 与 WebView C12 `noti-card` 命中行对齐。
class ChatSearchHitCard extends StatelessWidget {
  const ChatSearchHitCard({
    super.key,
    required this.senderName,
    required this.body,
    required this.timeLabel,
    required this.onTap,
    this.avatar,
  });

  final String senderName;
  final String body;
  final String timeLabel;
  final VoidCallback onTap;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: DunesColors.bgApp,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DunesColors.borderSoft),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                avatar ??
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: DunesColors.accentSoft,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline,
                        size: 16,
                        color: DunesColors.accentDeep,
                      ),
                    ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DunesTypography.sans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (timeLabel.isNotEmpty)
                            Text(
                              timeLabel,
                              style: DunesTypography.mono(
                                fontSize: 9.5,
                                color: DunesColors.text3,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: body,
                              style: DunesTypography.sans(
                                fontSize: 12.5,
                                color: DunesColors.text2,
                                height: 1.35,
                              ),
                            ),
                            TextSpan(
                              text: '  → 点击定位',
                              style: DunesTypography.mono(
                                fontSize: 9,
                                color: DunesColors.accentDeep,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 微信式分类入口：日期 / 图片与视频 / 文件 / 链接 / 转发（APP / PC 共用）。
class _ChatHistoryCategoryGrid extends StatelessWidget {
  const _ChatHistoryCategoryGrid({
    required this.selected,
    required this.timeActive,
    required this.onSelect,
    required this.onSelectTime,
  });

  final ChatHistoryFilter? selected;
  final bool timeActive;
  final ValueChanged<ChatHistoryFilter> onSelect;
  final VoidCallback onSelectTime;

  static const _items =
      <({ChatHistoryFilter filter, IconData icon, Color tint, Color soft})>[
        (
          filter: ChatHistoryFilter.imageVideo,
          icon: Icons.photo_library_outlined,
          tint: DunesColors.blue,
          soft: DunesColors.blueSoft,
        ),
        (
          filter: ChatHistoryFilter.files,
          icon: Icons.folder_outlined,
          tint: DunesColors.amber,
          soft: DunesColors.amberSoft,
        ),
        (
          filter: ChatHistoryFilter.links,
          icon: Icons.link_rounded,
          tint: DunesColors.accentDeep,
          soft: DunesColors.accentSoft,
        ),
        (
          filter: ChatHistoryFilter.forwards,
          icon: Icons.reply_all_rounded,
          tint: DunesColors.green,
          soft: DunesColors.greenSoft,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '快速筛选',
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 11.5,
              color: DunesColors.text3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _CategoryTile(
                  icon: Icons.calendar_month_outlined,
                  tint: DunesColors.accentDeep,
                  soft: DunesColors.accentSoft,
                  title: '日期',
                  selected: timeActive,
                  onTap: onSelectTime,
                ),
              ),
              for (final item in _items) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _CategoryTile(
                    icon: item.icon,
                    tint: item.tint,
                    soft: item.soft,
                    title: item.filter.title,
                    selected: selected == item.filter,
                    onTap: () => onSelect(item.filter),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: DunesColors.borderSoft),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.tint,
    required this.soft,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final Color tint;
  final Color soft;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? soft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: soft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: tint, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? DunesColors.text : DunesColors.text2,
                height: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatHistoryTimeRangeChip extends StatelessWidget {
  const _ChatHistoryTimeRangeChip({
    required this.label,
    required this.onClear,
    required this.onTap,
  });

  final String label;
  final VoidCallback onClear;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Material(
          color: DunesColors.accentSoft,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    size: 13,
                    color: DunesColors.accentDeep,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: DunesColors.accentDeep,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onClear,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: DunesColors.accentDeep,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeRangeSheetAction {
  const _TimeRangeSheetAction._({
    this.range,
    this.clear = false,
    this.pickCustom = false,
  });

  const _TimeRangeSheetAction.range(ChatHistoryTimeRange range)
    : this._(range: range);

  const _TimeRangeSheetAction.clear() : this._(clear: true);

  const _TimeRangeSheetAction.pickCustom() : this._(pickCustom: true);

  final ChatHistoryTimeRange? range;
  final bool clear;
  final bool pickCustom;
}

class _ChatHistoryTimeRangeSheet extends StatelessWidget {
  const _ChatHistoryTimeRangeSheet({required this.current});

  final ChatHistoryTimeRange? current;

  static const _presets = <ChatHistoryTimePreset>[
    ChatHistoryTimePreset.today,
    ChatHistoryTimePreset.last7Days,
    ChatHistoryTimePreset.last30Days,
    ChatHistoryTimePreset.last90Days,
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: DunesColors.borderSoft,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '按时间段筛选',
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
              ),
            ),
            const SizedBox(height: 14),
            for (final preset in _presets)
              _TimeRangeOption(
                title: preset.title,
                selected: current?.preset == preset,
                onTap: () => Navigator.of(context).pop(
                  _TimeRangeSheetAction.range(
                    ChatHistoryTimeRange.fromPreset(preset),
                  ),
                ),
              ),
            _TimeRangeOption(
              title: '自定义时间段',
              selected: current?.preset == ChatHistoryTimePreset.custom,
              subtitle: current?.preset == ChatHistoryTimePreset.custom
                  ? current!.label
                  : null,
              onTap: () => Navigator.of(
                context,
              ).pop(const _TimeRangeSheetAction.pickCustom()),
            ),
            if (current != null) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).pop(const _TimeRangeSheetAction.clear()),
                child: Text(
                  '清除时间筛选',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.text3,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TimeRangeOption extends StatelessWidget {
  const _TimeRangeOption({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? DunesColors.accentSoft : DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: DunesColors.text,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: DunesTypography.sans(
                            fontSize: 12,
                            color: DunesColors.text3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
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
