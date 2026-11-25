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
import 'im_ui_kit.dart';
import 'user_avatar_widget.dart';

bool chatSearchShouldShowFilters({
  required bool keyboardVisible,
  required bool inputFocused,
}) => !keyboardVisible && !inputFocused;

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
  final FocusNode _queryFocusNode = FocusNode();
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
    _queryFocusNode.addListener(() {
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
    _queryFocusNode.dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    if (_queryFocusNode.hasFocus) _queryFocusNode.unfocus();
  }

  void _handleBack() {
    if (_queryFocusNode.hasFocus ||
        MediaQuery.viewInsetsOf(context).bottom > 0) {
      _dismissKeyboard();
      return;
    }
    widget.onBack();
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
      backgroundColor: ImVisualTokens.groupedBackground(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
              primary: DunesColors.resolve(
                context,
                DunesColors.accent,
                role: DunesColorRole.surface,
              ),
              onPrimary: DunesColors.resolve(context, Colors.white),
              surface: DunesColors.resolve(
                context,
                DunesColors.bgApp,
                role: DunesColorRole.surface,
              ),
              onSurface: DunesColors.resolve(context, DunesColors.text),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor: DunesColors.resolve(
                context,
                DunesColors.bgApp,
                role: DunesColorRole.surface,
              ),
              headerBackgroundColor: DunesColors.resolve(
                context,
                DunesColors.bgSoft,
                role: DunesColorRole.surface,
              ),
              headerForegroundColor: DunesColors.resolve(
                context,
                DunesColors.text,
              ),
              rangeSelectionBackgroundColor: DunesColors.resolve(
                context,
                DunesColors.accentSoft,
                role: DunesColorRole.surface,
              ),
              rangeSelectionOverlayColor: WidgetStateProperty.all(
                DunesColors.resolve(
                  context,
                  DunesColors.accent,
                ).withValues(alpha: 0.08),
              ),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return DunesColors.resolve(context, Colors.white);
                }
                if (states.contains(WidgetState.disabled)) {
                  return DunesColors.resolve(context, DunesColors.text3);
                }
                return DunesColors.resolve(context, DunesColors.text);
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return DunesColors.resolve(
                    context,
                    DunesColors.accent,
                    role: DunesColorRole.surface,
                  );
                }
                return Colors.transparent;
              }),
              todayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return DunesColors.resolve(context, Colors.white);
                }
                return DunesColors.resolve(context, DunesColors.accent);
              }),
              todayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return DunesColors.resolve(
                    context,
                    DunesColors.accent,
                    role: DunesColorRole.surface,
                  );
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
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final showFilters = chatSearchShouldShowFilters(
      keyboardVisible: keyboardVisible,
      inputFocused: _queryFocusNode.hasFocus,
    );
    final accent = ImVisualTokens.accent(context);
    final focused = _queryFocusNode.hasFocus;
    return Scaffold(
      backgroundColor: ImVisualTokens.groupedBackground(context),
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _dismissKeyboard,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: ImVisualTokens.cardSurface(context),
                  border: Border(
                    bottom: BorderSide(
                      color: ImVisualTokens.hairlineBorder(context),
                      width: 0.7,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 8, 6),
                      child: SizedBox(
                        height: 44,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                onPressed: _handleBack,
                                tooltip: '返回',
                                icon: const Icon(
                                  Icons.chevron_left_rounded,
                                  size: 28,
                                ),
                              ),
                            ),
                            Text(
                              '查找聊天内容',
                              style: DunesTypography.sans(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w600,
                                color: DunesColors.resolve(
                                  context,
                                  DunesColors.text,
                                ),
                                context: context,
                              ),
                            ),
                            if (_selectedFilter != null ||
                                _timeRange != null ||
                                _queryController.text.isNotEmpty)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    _queryController.clear();
                                    setState(() {
                                      _selectedFilter = null;
                                      _timeRange = null;
                                    });
                                    _search();
                                  },
                                  child: Text(
                                    '重置',
                                    style: DunesTypography.sans(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: ImVisualTokens.accentText(context),
                                      context: context,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: AnimatedContainer(
                        duration: ImVisualTokens.fastAnim,
                        curve: ImVisualTokens.iosCurve,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9.5,
                        ),
                        decoration: BoxDecoration(
                          color: focused
                              ? ImVisualTokens.cardSurface(context)
                              : ImVisualTokens.groupedBackground(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: focused
                                ? accent.withValues(alpha: 0.56)
                                : ImVisualTokens.hairlineBorder(context),
                            width: focused ? 1.1 : 0.7,
                          ),
                          boxShadow: focused
                              ? [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.12),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : const [],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 17,
                              color: focused
                                  ? accent
                                  : DunesColors.resolve(
                                      context,
                                      DunesColors.text3,
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _queryController,
                                focusNode: _queryFocusNode,
                                cursorColor: accent,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) {
                                  setState(() => _selectedFilter = null);
                                  _search();
                                },
                                onChanged: (value) {
                                  if (value.trim().isEmpty &&
                                      _selectedFilter == null) {
                                    _search();
                                  }
                                },
                                style: DunesTypography.sans(
                                  fontSize: 14,
                                  color: DunesColors.resolve(
                                    context,
                                    DunesColors.text,
                                  ),
                                  context: context,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: '搜消息 / 文件 / @mention',
                                  hintStyle: DunesTypography.sans(
                                    fontSize: 13.5,
                                    color: DunesColors.resolve(
                                      context,
                                      DunesColors.text3,
                                    ),
                                    context: context,
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onTapOutside: (_) => _dismissKeyboard(),
                              ),
                            ),
                            if (_queryController.text.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _queryController.clear();
                                  setState(() => _selectedFilter = null);
                                  _search();
                                },
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: ImVisualTokens.isDark(context)
                                        ? Colors.white.withValues(alpha: 0.16)
                                        : const Color(0xFFD5D1E0),
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: showFilters
                    ? Column(
                        key: const ValueKey('chat-search-filters'),
                        children: [
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
                        ],
                      )
                    : const SizedBox(
                        key: ValueKey('chat-search-filters-hidden'),
                      ),
              ),
              Expanded(child: _buildResults(entries)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(List<_SearchListEntry> entries) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: ImShimmerRow(count: 5),
      );
    }
    if (_error != null) {
      return ImEmptyState(
        icon: Icons.error_outline_rounded,
        title: '搜索加载失败',
        subtitle: _error!,
        action: OutlinedButton(
          onPressed: _search,
          child: const Text('重试'),
        ),
      );
    }
    if (entries.isEmpty) {
      final hasQuery = _queryController.text.trim().isNotEmpty;
      final emptyText =
          _selectedFilter?.emptyHint ??
          (_timeRange != null
              ? '该时间段暂无消息'
              : (hasQuery ? '暂无匹配结果' : '暂无历史消息'));
      return ImEmptyState(
        icon: Icons.manage_search_rounded,
        title: emptyText,
        subtitle: hasQuery || _selectedFilter != null || _timeRange != null
            ? '试试更换关键词，或切换上方日期/类型筛选'
            : '当前会话的聊天消息、文件与链接都会展示在这里',
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
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                    color: DunesColors.resolve(context, DunesColors.text2),
                    context: context,
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
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
          query: _queryController.text.trim(),
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
      color: isVideo
          ? DunesColors.resolve(
              context,
              const Color(0xFF2A2A2A),
              role: DunesColorRole.surface,
            )
          : DunesColors.resolve(
              context,
              DunesColors.bgSoft,
              role: DunesColorRole.surface,
            ),
      alignment: Alignment.center,
      child: Icon(
        isVideo ? Icons.videocam_outlined : Icons.image_outlined,
        color: isVideo
            ? DunesColors.resolve(context, Colors.white54)
            : DunesColors.resolve(context, DunesColors.text3),
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
              color: DunesColors.resolve(
                context,
                DunesColors.bgSoft,
                role: DunesColorRole.surface,
              ),
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
    return ImTapScale(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openPreview(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (isVideo)
              Center(
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 12, 6, 5),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
                child: Text(
                  message.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 命中消息卡片（iOS 圆角卡片 + 关键词高亮 + 右侧引导箭头）。
class ChatSearchHitCard extends StatelessWidget {
  const ChatSearchHitCard({
    super.key,
    required this.senderName,
    required this.body,
    required this.timeLabel,
    required this.onTap,
    this.avatar,
    this.query = '',
  });

  final String senderName;
  final String body;
  final String timeLabel;
  final VoidCallback onTap;
  final Widget? avatar;
  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ImTapScale(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: ImVisualTokens.cardSurface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: ImVisualTokens.hairlineBorder(context),
              width: 0.8,
            ),
            boxShadow: ImVisualTokens.softCardShadow(context),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              avatar ??
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: ImVisualTokens.accentSoftSurface(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 16,
                      color: ImVisualTokens.accent(context),
                    ),
                  ),
              const SizedBox(width: 11),
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
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text,
                              ),
                              context: context,
                            ),
                          ),
                        ),
                        if (timeLabel.isNotEmpty)
                          Text(
                            timeLabel,
                            style: DunesTypography.sans(
                              fontSize: 11,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text3,
                              ),
                              context: context,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ImHighlightedText(
                      text: body,
                      query: query,
                      maxLines: 2,
                      style: DunesTypography.sans(
                        fontSize: 12.5,
                        color: DunesColors.resolve(context, DunesColors.text2),
                        height: 1.38,
                        context: context,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 微信式分类入口：统一收纳于一张 iOS 圆角白卡内（日期 / 图片与视频 / 文件 / 链接 / 转发）。
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
      <({ChatHistoryFilter filter, String shortLabel, IconData icon, Color tint, Color soft})>[
        (
          filter: ChatHistoryFilter.imageVideo,
          shortLabel: '图片视频',
          icon: Icons.photo_library_rounded,
          tint: Color(0xFF4F6CE6),
          soft: Color(0xFFEDF1FD),
        ),
        (
          filter: ChatHistoryFilter.files,
          shortLabel: '文件',
          icon: Icons.folder_rounded,
          tint: Color(0xFFD9821E),
          soft: Color(0xFFFCF2E4),
        ),
        (
          filter: ChatHistoryFilter.links,
          shortLabel: '链接',
          icon: Icons.link_rounded,
          tint: ImVisualTokens.purple,
          soft: ImVisualTokens.purpleSoft,
        ),
        (
          filter: ChatHistoryFilter.forwards,
          shortLabel: '转发',
          icon: Icons.reply_all_rounded,
          tint: Color(0xFF159969),
          soft: Color(0xFFE7F7F0),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        decoration: BoxDecoration(
          color: ImVisualTokens.cardSurface(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: ImVisualTokens.hairlineBorder(context),
            width: 0.7,
          ),
          boxShadow: ImVisualTokens.softCardShadow(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '按内容类型快速筛选',
                style: DunesTypography.sans(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  context: context,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _CategoryTile(
                    icon: Icons.calendar_month_rounded,
                    tint: ImVisualTokens.accent(context),
                    soft: ImVisualTokens.accentSoftSurface(context),
                    title: '日期',
                    selected: timeActive,
                    onTap: onSelectTime,
                  ),
                ),
                for (final item in _items)
                  Expanded(
                    child: _CategoryTile(
                      icon: item.icon,
                      tint: item.tint,
                      soft: item.soft,
                      title: item.shortLabel,
                      selected: selected == item.filter,
                      onTap: () => onSelect(item.filter),
                    ),
                  ),
              ],
            ),
          ],
        ),
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
    final accent = ImVisualTokens.accent(context);
    final dark = ImVisualTokens.isDark(context);
    return ImTapScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: ImVisualTokens.fastAnim,
              curve: ImVisualTokens.iosCurve,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: selected
                    ? ImVisualTokens.primaryGradient(context)
                    : null,
                color: selected
                    ? null
                    : (dark ? tint.withValues(alpha: 0.16) : soft),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.25)
                      : tint.withValues(alpha: 0.14),
                  width: 0.7,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : const [],
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : tint,
                size: 21,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DunesTypography.sans(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected
                    ? ImVisualTokens.accentText(context)
                    : DunesColors.resolve(context, DunesColors.text2),
                context: context,
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
    final accentText = ImVisualTokens.accentText(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ImTapScale(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 5.5, 8, 5.5),
            decoration: BoxDecoration(
              color: ImVisualTokens.accentSoftSurface(context),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: ImVisualTokens.accent(context).withValues(alpha: 0.24),
                width: 0.7,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 13,
                  color: accentText,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accentText,
                    context: context,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: accentText,
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
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ImVisualTokens.hairlineBorder(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '按时间段筛选',
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: DunesColors.resolve(context, DunesColors.text),
                context: context,
              ),
            ),
            const SizedBox(height: 14),
            ImGroupedCard(
              dividerIndent: 16,
              children: [
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
              ],
            ),
            if (current != null) ...[
              const SizedBox(height: 10),
              ImTapScale(
                onTap: () => Navigator.of(
                  context,
                ).pop(const _TimeRangeSheetAction.clear()),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: ImVisualTokens.cardSurface(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: ImVisualTokens.hairlineBorder(context),
                      width: 0.7,
                    ),
                  ),
                  child: Text(
                    '清除时间筛选',
                    style: DunesTypography.sans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: ImVisualTokens.accentText(context),
                      context: context,
                    ),
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
    return ImTapScale(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      pressedScale: 0.99,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: DunesTypography.sans(
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? ImVisualTokens.accentText(context)
                          : DunesColors.resolve(context, DunesColors.text),
                      context: context,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: DunesColors.resolve(
                          context,
                          DunesColors.text3,
                        ),
                        context: context,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ImSelectCircle(selected: selected),
          ],
        ),
      ),
    );
  }
}
