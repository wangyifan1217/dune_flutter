import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../contacts/contact_service.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import 'chat_history_filter.dart';
import 'chat_widgets.dart';
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
          final contact =
              await ContactService(session: widget.session).fetchContact(peerId);
          if (contact != null) {
            _peerAvatarPreset ??= contact.avatarPreset;
            _peerAvatarObjectKey ??= contact.avatarObjectKey;
          }
        }
      } else {
        try {
          final members =
              await _service.fetchConversationMembers(widget.conversationId);
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
      final meResp = await ContactService(session: widget.session)
          .fetchContact(widget.session.userId);
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
    if (!_scrollController.hasClients || _loading || _loadingMore || !_hasMore) {
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

  Future<({List<NativeChatMessage> items, bool hasMore, int oldestId})>
      _fetchFilteredPage({
    required ChatHistoryFilter filter,
    required int cursor,
  }) async {
    final collected = <NativeChatMessage>[];
    var nextCursor = cursor;
    var hasMore = true;
    var guard = 0;

    while (collected.length < _filterTargetBatch && hasMore && guard < 8) {
      guard++;
      final before = nextCursor > 0 ? nextCursor : null;
      late final List<NativeChatMessage> pageItems;
      late final bool pageHasMore;

      if (filter.usesMediaApi) {
        final rows = await _service.fetchConversationMedia(
          widget.conversationId,
          size: _filterPageSize,
          before: before,
        );
        pageItems = rows;
        pageHasMore = rows.length >= _filterPageSize;
      } else {
        final page = await _service.searchMessagePage(
          conversationId: widget.conversationId,
          query: '',
          size: _filterPageSize,
          before: before,
        );
        pageItems = page.items;
        pageHasMore = page.hasMore && page.items.isNotEmpty;
      }

      if (pageItems.isEmpty) {
        hasMore = false;
        break;
      }
      collected.addAll(
        pageItems.where((m) => chatHistoryFilterMatches(filter, m)),
      );
      nextCursor = _oldestMessageId(pageItems);
      hasMore = pageHasMore && nextCursor > 0;
      if (!hasMore) break;
    }

    return (items: collected, hasMore: hasMore, oldestId: nextCursor);
  }

  Future<void> _search({bool append = false}) async {
    final q = _queryController.text.trim();
    final filter = _selectedFilter;

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
      if (filter != null && q.isEmpty) {
        final page = await _fetchFilteredPage(
          filter: filter,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: DunesColors.bgSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 16, color: DunesColors.text3),
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
              onSelect: _selectFilter,
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
      final emptyText = _selectedFilter?.emptyHint ??
          (_queryController.text.trim().isEmpty ? '暂无历史消息' : '暂无搜索结果');
      return Center(
        child: Text(
          emptyText,
          style: const TextStyle(fontSize: 12, color: DunesColors.text3),
        ),
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
        return ChatSearchHitCard(
          senderName: m.senderName,
          body: _hitBody(m),
          timeLabel: InboxFormat.formatTime(m.createdAt, withClock: true),
          avatar: ImUserAvatar(
            initial: m.senderName.isNotEmpty ? m.senderName.substring(0, 1) : '?',
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

/// 微信式分类入口：图片与视频 / 文件 / 链接 / 转发（APP / PC 共用）。
class _ChatHistoryCategoryGrid extends StatelessWidget {
  const _ChatHistoryCategoryGrid({
    required this.selected,
    required this.onSelect,
  });

  final ChatHistoryFilter? selected;
  final ValueChanged<ChatHistoryFilter> onSelect;

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
              for (var i = 0; i < _items.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => onSelect(_items[i].filter),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected == _items[i].filter
                            ? _items[i].soft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _items[i].soft,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              _items[i].icon,
                              color: _items[i].tint,
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _items[i].filter.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DunesTypography.sans(
                              fontSize: 11.5,
                              fontWeight: selected == _items[i].filter
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected == _items[i].filter
                                  ? DunesColors.text
                                  : DunesColors.text2,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
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
