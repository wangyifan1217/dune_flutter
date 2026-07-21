import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../shell/dunes_toast.dart';
import 'ai_summary_models.dart';
import 'ai_summary_participants.dart';
import 'ai_summary_service.dart';
import 'ai_summary_sparkle_icon.dart';
import 'ai_summary_status_bus.dart';

/// 「智能总结 AI+」列表页（企微式卡片流）。
class NativeAiSummaryHubPage extends StatefulWidget {
  const NativeAiSummaryHubPage({
    super.key,
    required this.session,
    required this.onBack,
    required this.onCreate,
    required this.onOpenDetail,
    this.onOpened,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final VoidCallback onCreate;
  final ValueChanged<int> onOpenDetail;
  /// 进入页时回调（用于 Host 刷新通讯 Tab 未读）。
  final VoidCallback? onOpened;

  @override
  State<NativeAiSummaryHubPage> createState() => _NativeAiSummaryHubPageState();
}

class _NativeAiSummaryHubPageState extends State<NativeAiSummaryHubPage> {
  late final AiSummaryService _service;
  late final ConversationService _conversations;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  StreamSubscription<AiSummaryItem>? _localStatusSub;
  Timer? _pollTimer;
  Timer? _searchDebounce;

  bool _loading = true;
  String? _error;
  List<AiSummaryItem> _items = const <AiSummaryItem>[];
  Map<int, NativeConversation> _convById = const <int, NativeConversation>{};
  bool _hasMore = false;
  int _page = 1;
  bool _loadingMore = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _service = AiSummaryService(session: widget.session);
    _conversations = ConversationService(session: widget.session);
    _rtSub = ConversationRealtimeHub.instance
        .of(widget.session)
        .events
        .listen(_onRealtime);
    _localStatusSub = AiSummaryStatusBus.instance.stream.listen(_applyItemUpdate);
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    unawaited(_load());
    widget.onOpened?.call();
  }

  Future<void> _openDetail(AiSummaryItem item) async {
    if (item.isUnread) {
      try {
        await _service.markRead(item.id);
      } catch (_) {}
      if (mounted) {
        setState(() {
          final idx = _items.indexWhere((e) => e.id == item.id);
          if (idx >= 0) {
            _items = List<AiSummaryItem>.from(_items)
              ..[idx] = _items[idx].copyWith(unread: false);
          }
        });
        widget.onOpened?.call();
      }
    }
    widget.onOpenDetail(item.id);
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _localStatusSub?.cancel();
    _pollTimer?.cancel();
    _searchDebounce?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      unawaited(_loadMore());
    }
  }

  void _onSearchChanged() {
    setState(() {}); // 刷新清除按钮等
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      final next = _searchController.text.trim();
      if (next == _query) return;
      setState(() => _query = next);
      unawaited(_load());
    });
  }

  bool _itemMatchesQuery(AiSummaryItem item, String keyword) {
    if (keyword.isEmpty) return true;
    final q = keyword.toLowerCase();
    if (item.theme.toLowerCase().contains(q)) return true;
    if (item.initiator.displayName.toLowerCase().contains(q)) return true;
    final matched = _matchingConversationIds(keyword).toSet();
    return item.conversationIds.any(matched.contains);
  }

  /// 关键词匹配的会话（私聊人名 / 群名），供后端按参与会话过滤。
  List<int> _matchingConversationIds(String keyword) {
    if (keyword.isEmpty) return const <int>[];
    final q = keyword.toLowerCase();
    return _convById.values
        .where((c) {
          final title = c.displayTitle.toLowerCase();
          final peer = (c.peerDisplayName ?? '').toLowerCase();
          return title.contains(q) || peer.contains(q);
        })
        .map((c) => c.id)
        .toList(growable: false);
  }

  void _applyItemUpdate(AiSummaryItem item) {
    if (!mounted || item.id <= 0) return;
    final idx = _items.indexWhere((e) => e.id == item.id);
    setState(() {
      if (idx < 0) {
        if (_itemMatchesQuery(item, _query)) {
          _items = [item, ..._items];
        }
      } else if (!_itemMatchesQuery(item, _query) && _query.isNotEmpty) {
        _items = List<AiSummaryItem>.from(_items)..removeAt(idx);
      } else {
        _items = List<AiSummaryItem>.from(_items)..[idx] = item;
      }
    });
    _syncPoll();
  }

  void _onRealtime(ConversationRealtimeEvent event) {
    if (event.type != 'ai_summary_updated') return;
    final update = AiSummaryRealtimeUpdate.fromPayload(event.raw);
    if (update.id <= 0) {
      unawaited(_load(silent: true));
      return;
    }
    final idx = _items.indexWhere((e) => e.id == update.id);
    if (idx < 0) {
      unawaited(_load(silent: true));
      return;
    }
    final generating =
        update.status == 'PENDING' || update.status == 'RUNNING';
    final terminal =
        update.status == 'SUCCESS' || update.status == 'FAILED';
    setState(() {
      _items = List<AiSummaryItem>.from(_items)
        ..[idx] = _items[idx].copyWith(
          status: update.status,
          summaryPreview: generating
              ? (update.preview?.trim().isNotEmpty == true
                    ? update.preview
                    : '正在生成…')
              : (update.preview ?? _items[idx].summaryPreview),
          resultMarkdown: generating ? null : _items[idx].resultMarkdown,
          finishedAt: generating ? null : DateTime.now(),
          unread: terminal,
        );
    });
    _syncPoll();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      // 先确保会话缓存可用，便于按人名/群名解析 conversationIds。
      if (_convById.isEmpty) {
        final convs = await _conversations.fetchConversations();
        if (!mounted) return;
        setState(() => _convById = {for (final c in convs) c.id: c});
      }
      final page = await _service.fetchList(
        page: 1,
        size: 20,
        q: _query,
        conversationIds: _matchingConversationIds(_query),
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _page = 1;
        _hasMore = page.hasMore;
        _loading = false;
        _error = null;
      });
      _syncPoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorText(e, fallback: '总结列表加载失败');
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.fetchList(
        page: _page + 1,
        size: 20,
        q: _query,
        conversationIds: _matchingConversationIds(_query),
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _page = page.page;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
      _syncPoll();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '加载更多失败'),
        kind: DunesToastKind.error,
      );
    }
  }

  void _syncPoll() {
    final generating = _items.any((e) => e.isGenerating);
    if (!generating) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _pollTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_pollGenerating());
    });
  }

  Future<void> _pollGenerating() async {
    final pending = _items.where((e) => e.isGenerating).toList();
    if (pending.isEmpty) {
      _syncPoll();
      return;
    }
    // 并发轮询多个进行中的任务
    final results = await Future.wait(
      pending.map((e) async {
        try {
          return await _service.fetchDetail(e.id);
        } catch (_) {
          return e;
        }
      }),
    );
    if (!mounted) return;
    final map = {for (final r in results) r.id: r};
    setState(() {
      _items = _items.map((e) => map[e.id] ?? e).toList(growable: false);
    });
    _syncPoll();
  }

  Future<void> _delete(AiSummaryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除总结'),
        content: Text('确定删除「${item.theme}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.delete(item.id);
      if (!mounted) return;
      setState(() => _items = _items.where((e) => e.id != item.id).toList());
      showDunesToast(context, '已删除');
    } catch (e) {
      if (!mounted) return;
      showDunesToast(
        context,
        friendlyErrorText(e, fallback: '删除失败'),
        kind: DunesToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEDE6F8), Color(0xFFF2F4F7)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: widget.onCreate,
                    tooltip: '新建总结',
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Row(
                  children: [
                    const AiSummaryAvatarMark(size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '智能总结 AI+',
                        style: DunesTypography.sans(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1C1C1C),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '选择聊天会话与日期，根据聊天记录自动总结。',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    height: 1.45,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜索主题、发起人或会话（人/群）',
                    hintStyle: DunesTypography.sans(
                      fontSize: 13.5,
                      color: const Color(0xFF9CA3AF),
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: Color(0xFF9CA3AF),
                    ),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除',
                            onPressed: () => _searchController.clear(),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: DunesColors.brandPurple,
                      ),
                    ),
                  ),
                  style: DunesTypography.sans(fontSize: 14),
                ),
              ),
            ],
          ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: DunesTypography.sans(color: DunesColors.text3)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => _load(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF7B5CD8),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final emptyHint = _query.isEmpty
        ? '还没有总结，点上方新建开始'
        : '未找到与「$_query」相关的总结';

    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          _NewSummaryCard(onTap: widget.onCreate),
          const SizedBox(height: 10),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Center(
                child: Text(
                  emptyHint,
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.text3,
                  ),
                ),
              ),
            )
          else
            ..._items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _SummaryCard(
                  item: item,
                  conversations: [
                    for (final id in item.conversationIds)
                      if (_convById[id] != null) _convById[id]!,
                  ],
                  service: _conversations,
                  onTap: () => unawaited(_openDetail(item)),
                  onMore: () => _delete(item),
                  onParticipantsTap: () {
                    final list = [
                      for (final id in item.conversationIds)
                        if (_convById[id] != null) _convById[id]!,
                    ];
                    unawaited(
                      showAiSummaryParticipantsSheet(
                        context: context,
                        service: _conversations,
                        conversations: list,
                      ),
                    );
                  },
                ),
              ),
            ),
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (!_hasMore && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  '没有更多了',
                  style: DunesTypography.sans(
                    fontSize: 12,
                    color: const Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NewSummaryCard extends StatelessWidget {
  const _NewSummaryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFF1C1C1C),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                '新建总结',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1C1C1C),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.item,
    required this.conversations,
    required this.service,
    required this.onTap,
    required this.onMore,
    required this.onParticipantsTap,
  });

  final AiSummaryItem item;
  final List<NativeConversation> conversations;
  final ConversationService service;
  final VoidCallback onTap;
  final VoidCallback onMore;
  final VoidCallback onParticipantsTap;

  @override
  Widget build(BuildContext context) {
    final initiator = item.initiator.displayName.trim().isEmpty
        ? '我'
        : item.initiator.displayName;
    final preview = item.isGenerating
        ? (item.summaryPreview?.trim().isNotEmpty == true
              ? item.summaryPreview!
              : item.statusLabel)
        : item.isFailed
        ? (item.errorMessage?.trim().isNotEmpty == true
              ? item.errorMessage!
              : '生成失败，可重新生成')
        : (item.summaryPreview?.trim().isNotEmpty == true
              ? item.summaryPreview!
              : '点击查看详情');
    final time = InboxFormat.formatTime(item.sortTime);
    final participantCount = item.conversationIds.isNotEmpty
        ? item.conversationIds.length
        : conversations.length;
    final badge = item.statusBadgeLabel;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$initiator 发起',
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: const Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                  if (badge.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: item.isFailed
                            ? const Color(0xFFFEE2E2)
                            : DunesColors.brandPurpleSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.isGenerating) ...[
                            SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: DunesColors.brandPurple,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          Text(
                            badge,
                            style: DunesTypography.sans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: item.isFailed
                                  ? const Color(0xFFB91C1C)
                                  : DunesColors.brandPurpleDeep,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.isUnread)
                    Padding(
                      padding: const EdgeInsets.only(top: 7, right: 8),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: DunesColors.brandPurple,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      item.theme,
                      style: DunesTypography.sans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF111827),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 13.5,
                  height: 1.5,
                  color: item.isGenerating
                      ? DunesColors.brandPurple
                      : const Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (conversations.isNotEmpty) ...[
                    GestureDetector(
                      onTap: onParticipantsTap,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AiSummaryAvatarStack(
                            conversations: conversations,
                            service: service,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$participantCount位成员',
                            style: DunesTypography.sans(
                              fontSize: 12,
                              color: const Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                  ] else if (participantCount > 0) ...[
                    GestureDetector(
                      onTap: onParticipantsTap,
                      child: Text(
                        '$participantCount位成员',
                        style: DunesTypography.sans(
                          fontSize: 12,
                          color: const Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    time,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onMore,
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      size: 18,
                      color: Color(0xFF9CA3AF),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
