import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/widgets/cached_network_image.dart';
import '../nova/nova_background_coordinator.dart';
import '../nova/nova_generating_storage.dart';
import '../nova/nova_inbox_preview.dart';
import '../nova/nova_web_storage.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_main_tab_bar.dart';
import '../workbench/workbench_badge_notifier.dart';
import 'comm_unread_notifier.dart';
import 'conversation_inbox_merge.dart';
import 'conversation_inbox_realtime.dart';
import 'conversation_mention_utils.dart';
import 'conversation_models.dart';
import 'conversation_realtime_dedup.dart';
import 'conversation_realtime_hub.dart';
import 'conversation_realtime_service.dart';
import 'conversation_service.dart';
import 'inbox_format.dart';
import 'inbox_hidden_storage.dart';
import 'inbox_widgets.dart';
import 'notification_service.dart';

class NativeConversationPage extends StatefulWidget {
  const NativeConversationPage({
    super.key,
    required this.session,
    required this.navigation,
    required this.commUnread,
    this.workbenchBadge,
    required this.onOpenPrivate,
    required this.onOpenGroup,
    required this.onOpenContacts,
    required this.onOpenNova,
    required this.onOpenNotifications,
    required this.onOpenNewChat,
    this.selectedConversationId,
    this.showBottomTabBar = true,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final CommUnreadNotifier commUnread;
  final WorkbenchBadgeNotifier? workbenchBadge;
  final ValueChanged<NativeConversation> onOpenPrivate;
  final ValueChanged<NativeConversation> onOpenGroup;
  final VoidCallback onOpenContacts;
  final VoidCallback onOpenNova;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenNewChat;
  /// 双栏布局中当前选中的会话，用于列表高亮。
  final int? selectedConversationId;
  /// 双栏壳已提供底部 Tab 时关闭页内 Tab，避免重复。
  final bool showBottomTabBar;

  @override
  State<NativeConversationPage> createState() => _NativeConversationPageState();
}

class _InboxSection {
  const _InboxSection({
    required this.key,
    required this.label,
    required this.count,
    required this.timestamp,
    required this.pinned,
    required this.leading,
    required this.rows,
  });

  final String key;
  final String label;
  final int count;
  final int timestamp;
  final bool pinned;
  final Widget? leading;
  final List<Widget> rows;
}

class _NativeConversationPageState extends State<NativeConversationPage>
    with WidgetsBindingObserver {
  static const _yunshuName = 'NOVA';

  late final ConversationService _service;
  late final NotificationService _notificationService;
  late final ConversationRealtimeService _realtime;
  final ConversationRealtimeDedup _realtimeDedup = ConversationRealtimeDedup();
  final TextEditingController _searchController = TextEditingController();

  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  StreamSubscription<Set<int>>? _onlineSub;
  Timer? _rtRefreshDebounce;
  Timer? _searchDebounce;
  Timer? _novaInboxPollTimer;

  bool _loading = true;
  String? _error;
  List<NativeConversation> _items = const <NativeConversation>[];
  NativeNotificationSummary _notif = const NativeNotificationSummary(
    unreadCount: 0,
  );
  Set<int> _onlineUsers = <int>{};
  String _searchQuery = '';
  Map<String, String> _novaStorage = const {};
  Map<String, InboxHiddenEntry> _hiddenConversations = const {};

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _notificationService = NotificationService(session: widget.session);
    _realtime = ConversationRealtimeHub.instance.of(widget.session);
    WidgetsBinding.instance.addObserver(this);
    userAvatarRefresh.addListener(_onSelfAvatarUpdated);
    _load();
    _bootRealtime();
    NovaBackgroundCoordinator.instance.addListener(_onNovaBackgroundUpdate);
  }

  void _onSelfAvatarUpdated() {
    if (!mounted || _loading) return;
    final snap = userAvatarRefresh.snapshotFor(widget.session.userId);
    if (snap == null) return;
    setState(() {
      _items = applySelfAvatarToConversations(_items, snap);
    });
    unawaited(_load(silent: true, skipAvatarMerge: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // 从后台（含点击推送通知）回到前台时，重连实时通道并刷新未读，
    // 避免会话列表未读条数图标停留在旧状态。
    unawaited(_realtime.connect());
    if (mounted && !_loading) {
      _load(silent: true);
    }
  }

  void _onNovaBackgroundUpdate() {
    if (!mounted || _loading) return;
    _load(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    userAvatarRefresh.removeListener(_onSelfAvatarUpdated);
    NovaBackgroundCoordinator.instance.removeListener(_onNovaBackgroundUpdate);
    _rtRefreshDebounce?.cancel();
    _searchDebounce?.cancel();
    _novaInboxPollTimer?.cancel();
    _rtSub?.cancel();
    _onlineSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootRealtime() async {
    try {
      await _realtime.connect();
      _onlineSub = _realtime.trackOnlineUsers((ids) {
        if (!mounted) return;
        setState(() => _onlineUsers = ids);
      });
      _rtSub = _realtime.events.listen((event) {
        const liveEvents = <String>{
          'message',
          'system_flow',
          'conversation_updated',
          'read',
          'message_recalled',
          'message_updated',
          'message_deleted',
        };
        if (!liveEvents.contains(event.type)) return;
        _onInboxRealtimeEvent(event);
      });
    } catch (_) {
      // Realtime is best-effort.
    }
  }

  void _onInboxRealtimeEvent(ConversationRealtimeEvent event) {
    final like = ConversationInboxRealtime.fromEvent(event);
    final convId = like.conversationId ?? 0;

    if (convId > 0 &&
        shouldUnhideFromRealtimeEvent(
          like,
          _hiddenConversations,
          widget.session.userId,
        )) {
      unawaited(_unhideConversation(convId));
      _scheduleRealtimeRefresh();
      return;
    }

    if (convId > 0 && isConversationHidden(_hiddenConversations, convId)) {
      return;
    }

    if (!_realtimeDedup.consume(event)) {
      return;
    }

    if (event.type == 'read') {
      final userId = (like.raw['userId'] as num?)?.toInt() ?? 0;
      if (userId == widget.session.userId && convId > 0) {
        widget.commUnread.clearMutedMention(convId);
      }
    }

    if (ConversationInboxRealtime.needsFullRefresh(like, _items)) {
      _scheduleRealtimeRefresh();
      return;
    }

    if (!mounted || _loading) return;
    final mentionHit = ConversationMentionUtils.eventMentionsMe(
      event: like,
      selfUserId: widget.session.userId,
      selfDisplayName: widget.session.displayName,
    );
    NativeConversation? conv;
    for (final item in _items) {
      if (item.id == convId) {
        conv = item;
        break;
      }
    }
    final isMutedGroup = conv != null && CommUnreadNotifier.isMutedGroup(conv);
    setState(() {
      _items = ConversationInboxRealtime.applyEvent(
        items: _items,
        event: like,
        selfUserId: widget.session.userId,
        selfDisplayName: widget.session.displayName,
      );
    });
    if (mentionHit && isMutedGroup && convId > 0) {
      widget.commUnread.recordMutedMention(convId);
    }
    _updateCommBadge(_items, _notif.unreadCount);
  }

  Future<void> _unhideConversation(int conversationId) async {
    await InboxHiddenStorage.unhide(conversationId);
    _hiddenConversations = await InboxHiddenStorage.load();
  }

  Future<void> _hideConversation(NativeConversation conv) async {
    await InboxHiddenStorage.hide(conv.id);
    _hiddenConversations = await InboxHiddenStorage.load();
    if (!mounted) return;
    setState(() {
      _items = _items.where((c) => c.id != conv.id).toList(growable: false);
    });
    _updateCommBadge(_items, _notif.unreadCount);
  }

  void _scheduleRealtimeRefresh() {
    if (!mounted) return;
    _rtRefreshDebounce?.cancel();
    _rtRefreshDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _loading) return;
      _load(silent: true);
    });
  }

  Future<void> _load({
    bool silent = false,
    bool skipAvatarMerge = false,
  }) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final hidden = await InboxHiddenStorage.load();
      final results = await Future.wait(<Future<Object?>>[
        _service.fetchConversations(),
        _notificationService.fetchSummary(),
        NovaWebStorage.load(widget.session.userId),
      ]);
      final rows = (results[0] as List<NativeConversation>)
          .where((c) => c.isVisible && !isConversationHidden(hidden, c.id))
          .toList(growable: false);
      final dissolved = (results[0] as List<NativeConversation>)
          .where((c) => c.dissolved && c.id > 0)
          .map((c) => c.id)
          .toList(growable: false);
      if (dissolved.isNotEmpty) {
        await InboxHiddenStorage.upgradeDissolved(dissolved);
      }
      final notif = results[1] as NativeNotificationSummary;
      final novaStorage = results[2] as Map<String, String>;
      final refreshedHidden = await InboxHiddenStorage.load();
      if (!mounted) return;
      final selfAvatar = userAvatarRefresh.snapshotFor(widget.session.userId);
      final merged = silent && !skipAvatarMerge
          ? mergeInboxConversations(_items, rows, selfAvatar: selfAvatar)
          : applySelfAvatarToConversations(rows, selfAvatar);
      warmConversationAvatarCache(merged);
      setState(() {
        _items = merged;
        _notif = notif;
        _novaStorage = novaStorage;
        _hiddenConversations = refreshedHidden;
        _loading = false;
        if (!silent) _error = null;
      });
      _syncNovaInboxPoll(merged, novaStorage);
      _updateCommBadge(merged, notif.unreadCount);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(prefetchConversationAvatars(context, merged));
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  void _updateCommBadge(List<NativeConversation> rows, int notifUnread) {
    widget.commUnread.update(
      widget.commUnread.sumConversationUnread(
        rows: rows,
        notifUnread: notifUnread,
      ),
    );
  }

  NativeConversation? _primaryAiConversation(List<NativeConversation> rows) {
    final aiRows = rows.where((c) => c.isAiAssistant).toList();
    if (aiRows.isEmpty) return null;
    aiRows.sort((a, b) => b.sortTimestamp.compareTo(a.sortTimestamp));
    return aiRows.first;
  }

  void _openNovaConversation([NativeConversation? conversation]) {
    final nova = conversation ?? _primaryAiConversation(_items);
    if (nova != null) {
      NovaBackgroundCoordinator.instance.markReplySeen(nova.id);
      final remaining = widget.commUnread.total - nova.unreadCount;
      widget.commUnread.update(remaining > 0 ? remaining : 0);
      unawaited(
        _service.markConversationRead(nova.id).whenComplete(() {
          if (mounted) unawaited(_load(silent: true));
        }),
      );
    }
    widget.onOpenNova();
  }

  ({bool generating, String status}) _novaGeneratingFor(
    NativeConversation? ai,
  ) {
    final activeConvId = novaActiveConvIdFromStorage(_novaStorage);
    final local = readNovaGeneratingFromStorage(
      _novaStorage,
      convId: activeConvId,
      activeConvId: activeConvId,
    );
    final draft = readNovaStreamDraftFromStorage(_novaStorage, activeConvId);
    final streamInFlight = NovaBackgroundCoordinator.instance
        .serviceFor(widget.session)
        .isStreamInFlight;
    final localGenerating =
        local != null &&
        shouldPersistNovaGenerating(
          localGen: local,
          draft: draft,
          streamInFlight: streamInFlight,
        );
    final generating = (ai?.assistantGenerating ?? false) || localGenerating;
    final apiStatus = (ai?.assistantGeneratingStatus ?? '').trim();
    final status = apiStatus.isNotEmpty ? apiStatus : (local?.status ?? '');
    return (generating: generating, status: status);
  }

  void _syncNovaInboxPoll(
    List<NativeConversation> rows,
    Map<String, String> storage,
  ) {
    final ai = _primaryAiConversation(rows);
    final activeConvId = novaActiveConvIdFromStorage(storage);
    final local = readNovaGeneratingFromStorage(
      storage,
      convId: activeConvId,
      activeConvId: activeConvId,
    );
    final draft = readNovaStreamDraftFromStorage(storage, activeConvId);
    final streamInFlight = NovaBackgroundCoordinator.instance
        .serviceFor(widget.session)
        .isStreamInFlight;
    final shouldPoll =
        (ai?.assistantGenerating ?? false) ||
        (local != null &&
            shouldPersistNovaGenerating(
              localGen: local,
              draft: draft,
              streamInFlight: streamInFlight,
            ));
    if (shouldPoll) {
      _novaInboxPollTimer ??= Timer.periodic(
        const Duration(milliseconds: 2500),
        (_) {
          if (!mounted || _loading) return;
          _load(silent: true);
        },
      );
    } else {
      _novaInboxPollTimer?.cancel();
      _novaInboxPollTimer = null;
    }
  }

  bool _isStoppedStatus(String status) => status.trim().contains('停止');

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _searchQuery = value.trim().toLowerCase());
    });
  }

  List<NativeConversation> _sorted(List<NativeConversation> rows) {
    final copy = rows.toList(growable: true);
    copy.sort((a, b) {
      final ap = a.pinned ? 1 : 0;
      final bp = b.pinned ? 1 : 0;
      if (ap != bp) return bp.compareTo(ap);
      return b.sortTimestamp.compareTo(a.sortTimestamp);
    });
    return copy;
  }

  bool _matchesSearch(String title, String preview) {
    if (_searchQuery.isEmpty) return true;
    return title.toLowerCase().contains(_searchQuery) ||
        preview.toLowerCase().contains(_searchQuery);
  }

  String _privateTitle(NativeConversation c) => c.displayTitle;

  String? _privateSubtitle(NativeConversation c) {
    final parts = <String>[];
    final dept = c.peerDepartment?.trim();
    final role = c.peerRoleLabel?.trim();
    if (dept != null && dept.isNotEmpty) parts.add(dept);
    if (role != null && role.isNotEmpty) parts.add(role);
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  int? _peerUserId(NativeConversation c) {
    final id = c.peerUserId;
    if (id == null || id <= 0 || id == widget.session.userId) return null;
    return id;
  }

  bool _isPeerOnline(NativeConversation c) {
    final peerId = _peerUserId(c);
    return peerId != null && _onlineUsers.contains(peerId);
  }

  Widget? _buildConvRow(NativeConversation c) {
    final kind = c.kind.toUpperCase();
    final title = c.isPrivate ? _privateTitle(c) : c.title;
    if (!_matchesSearch(title, c.preview)) {
      return null;
    }

    ChatInboxRowKind rowKind;
    VoidCallback onTap;
    if (c.isPrivate) {
      rowKind = ChatInboxRowKind.private;
      onTap = () => widget.onOpenPrivate(c);
    } else if (c.isWorkgroupApproval) {
      rowKind = ChatInboxRowKind.workgroupApproval;
      onTap = () => widget.onOpenGroup(c);
    } else if (c.isGroup) {
      rowKind = ChatInboxRowKind.group;
      onTap = () => widget.onOpenGroup(c);
    } else if (c.isBroadcast) {
      rowKind = ChatInboxRowKind.broadcast;
      onTap = widget.onOpenNotifications;
    } else if (c.isAiAssistant) {
      rowKind = ChatInboxRowKind.aiAssistant;
      onTap = () => _openNovaConversation(c);
    } else {
      rowKind = ChatInboxRowKind.group;
      onTap = () => widget.onOpenGroup(c);
    }

    final gen = c.isAiAssistant
        ? _novaGeneratingFor(c)
        : (generating: false, status: '');

    // 暂时屏蔽私聊/群聊的左滑删除功能。
    final allowSwipeDelete =
        !(rowKind == ChatInboxRowKind.private ||
            rowKind == ChatInboxRowKind.group ||
            rowKind == ChatInboxRowKind.workgroupApproval);

    final row = ChatInboxRow(
      kind: rowKind,
      title: c.isAiAssistant ? _yunshuName : title,
      subtitle: c.isPrivate ? _privateSubtitle(c) : null,
      preview: c.isAiAssistant
          ? resolveNovaInboxPreview(
              storage: _novaStorage,
              convId: c.id,
              serverPreview: c.preview,
              generating: gen.generating,
              generatingStatus: gen.status,
              allowLocalCache: true,
            )
          : c.preview,
      timeLabel: InboxFormat.formatTime(c.updatedAt, withClock: c.isPrivate),
      memberCount: c.isPrivate || kind == 'AI_ASSISTANT' || kind == 'BROADCAST'
          ? null
          : c.memberCount,
      unreadCount:
          c.isAiAssistant &&
              NovaBackgroundCoordinator.instance.hasUnreadReplyFor(c.id)
          ? (c.unreadCount > 0 ? c.unreadCount : 1)
          : c.unreadCount,
      muted: c.muted,
      showAiMark: c.isAiAssistant,
      previewGenerating: c.isAiAssistant && gen.generating,
      showOnlineDot: c.isPrivate && _isPeerOnline(c),
      avatarInitial: c.isPrivate
          ? (_privateTitle(c).isNotEmpty
                ? _privateTitle(c).substring(0, 1)
                : '?')
          : null,
      avatarSeed: _peerUserId(c) ?? c.id,
      avatarPreset: c.isPrivate ? c.peerAvatarPreset : null,
      avatarObjectKey: c.isPrivate ? c.peerAvatarObjectKey : null,
      avatarUrl: c.isPrivate ? c.peerAvatarUrl : null,
      avatarService: c.isPrivate || c.isGroup || c.isWorkgroupApproval
          ? _service
          : null,
      groupAvatarMembers: c.isPrivate
          ? const <ConversationAvatarMember>[]
          : c.avatarMembers,
      sysTag: c.businessType,
      showDivider: true,
      selected: widget.selectedConversationId == c.id,
      onTap: onTap,
    );

    if (!allowSwipeDelete) {
      return KeyedSubtree(key: ValueKey<int>(c.id), child: row);
    }

    return KeyedSubtree(
      key: ValueKey<int>(c.id),
      child: SwipeableChatInboxRow(
        onDelete: () => _hideConversation(c),
        child: row,
      ),
    );
  }

  List<_InboxSection> _buildSections() {
    final approvals = _sorted(
      _items.where((c) => c.isWorkgroupApproval).toList(),
    );
    // 私聊与普通群聊共用一个按置顶、最近消息排序的会话流，和常见聊天
    // 应用一致；审批工作群仍保留在独立的系统分区中。
    final chats = _sorted(
      _items.where((c) => c.isGroup || c.isPrivate).toList(),
    );

    List<Widget> convRows(Iterable<NativeConversation> rows) =>
        rows.map(_buildConvRow).whereType<Widget>().toList();

    if (widget.session.isExternalUser) {
      final sections = <_InboxSection>[
        if (chats.isNotEmpty)
          _InboxSection(
            key: 'chat',
            label: '聊天',
            count: chats.length,
            timestamp: chats.first.sortTimestamp,
            pinned: false,
            leading: const Icon(
              Icons.chat_bubble_outline,
              size: 11,
              color: DunesColors.text3,
            ),
            rows: convRows(chats),
          ),
      ];
      sections.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return sections;
    }

    final sections = <_InboxSection>[
      if (approvals.isNotEmpty)
        _InboxSection(
          key: 'approval',
          label: '审批工作群 · 系统自动建群',
          count: approvals.length,
          timestamp: approvals.first.sortTimestamp,
          pinned: true,
          leading: const Icon(
            Icons.route_outlined,
            size: 11,
            color: DunesColors.accent,
          ),
          rows: convRows(approvals),
        ),
      if (chats.isNotEmpty)
        _InboxSection(
          key: 'chat',
          label: '聊天',
          count: chats.length,
          timestamp: chats.first.sortTimestamp,
          pinned: false,
          leading: const Icon(
            Icons.chat_bubble_outline,
            size: 11,
            color: DunesColors.text3,
          ),
          rows: convRows(chats),
        ),
    ];

    sections.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sections;
  }

  int get _messageCenterUnread {
    return _notif.unreadCount +
        _items
            .where((conversation) => conversation.isBroadcast)
            .fold(0, (total, conversation) => total + conversation.unreadCount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      // 搜索聚焦时键盘不顶起底部 Tab，与灯塔页一致。
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Column(
            children: [
              ChatInboxHeader(
                onOpenContacts: widget.onOpenContacts,
                onNewChat: widget.onOpenNewChat,
                onOpenNova: _openNovaConversation,
                onOpenMessageCenter: widget.onOpenNotifications,
                messageCenterUnread: _messageCenterUnread,
                novaThinking: _novaGeneratingFor(
                  _primaryAiConversation(_items),
                ).generating,
                novaUnread: NovaBackgroundCoordinator.instance.hasUnreadReply,
              ),
              ChatInboxSearchBar(
                controller: _searchController,
                onChanged: _onSearchChanged,
              ),
              Expanded(child: _buildBody()),
              if (widget.showBottomTabBar)
                DunesMainTabBar(
                  navigation: widget.navigation,
                  activeScreen: 'C1',
                  commUnread: widget.commUnread,
                  workbenchBadge: widget.workbenchBadge,
                  lighthouseAccess: widget.session.lighthouseAccess,
                  chatOnlyMode: widget.session.isExternalUser,
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
      return _ErrorPanel(error: _error!, onRetry: _load);
    }

    final sections = _buildSections();
    final children = <Widget>[];
    for (final section in sections) {
      children.add(
        ChatInboxSectionHeader(
          label: section.label,
          count: section.count,
          pinned: section.pinned,
          leading: section.leading,
        ),
      );
      children.addAll(section.rows);
    }
    children.add(const SizedBox(height: 6));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        children: children,
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '消息列表加载失败',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
