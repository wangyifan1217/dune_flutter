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
import '../ai_summary/ai_summary_models.dart';
import '../ai_summary/ai_summary_service.dart';
import '../auth/auth_session.dart';
import '../workbench/workbench_badge_notifier.dart';
import 'comm_unread_notifier.dart';
import 'conversation_inbox_cache.dart';
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
import '../robots/robot_analyzing_coordinator.dart';
import '../robots/robot_catalog_cache.dart';
import '../robots/robot_character.dart';
import '../robots/robot_markdown.dart';

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
    required this.onOpenAiSummary,
    this.onOpenFavorites,
    this.onOpenRobot,
    this.onOpenApprovalAssistant,
    this.onOpenTaskAssistant,
    this.onOpenReconciliationAssistant,
    this.selectedConversationId,
    this.conversationReadSignal,
    this.memberSettingsSignal,
    this.conversationRemovedSignal,
    this.listVisible = true,
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
  final VoidCallback onOpenAiSummary;
  final VoidCallback? onOpenFavorites;
  final ValueChanged<NativeConversation>? onOpenRobot;
  final ValueChanged<NativeConversation>? onOpenApprovalAssistant;
  final ValueChanged<NativeConversation>? onOpenTaskAssistant;
  final VoidCallback? onOpenReconciliationAssistant;

  /// 双栏布局中当前选中的会话，用于列表高亮。
  final int? selectedConversationId;

  /// Host 在 mark-read 成功后通知列表清零对应未读角标。
  final ConversationReadSignal? conversationReadSignal;

  /// Host 在资料页切换置顶/免打扰后，立刻同步列表排序与角标。
  final ConversationMemberSettingsSignal? memberSettingsSignal;

  /// Host 在退出群聊等场景后，立刻从列表移除对应会话。
  final ConversationRemovedSignal? conversationRemovedSignal;

  /// 手机端 keep-alive 时：进会话隐藏列表为 false，返回后为 true，用于恢复滚动。
  final bool listVisible;

  @override
  State<NativeConversationPage> createState() => _NativeConversationPageState();
}

/// Host → 会话列表：mark-read 成功后清零未读角标。
class ConversationReadSignal extends ChangeNotifier {
  int _conversationId = 0;

  int get conversationId => _conversationId;

  void notifyRead(int conversationId) {
    if (conversationId <= 0) return;
    _conversationId = conversationId;
    notifyListeners();
  }
}

/// Host → 会话列表：同步成员级置顶 / 免打扰。
class ConversationMemberSettingsSignal extends ChangeNotifier {
  int _conversationId = 0;
  bool? _muted;
  bool? _pinned;

  int get conversationId => _conversationId;
  bool? get muted => _muted;
  bool? get pinned => _pinned;

  void notifySettings({
    required int conversationId,
    bool? muted,
    bool? pinned,
  }) {
    if (conversationId <= 0) return;
    if (muted == null && pinned == null) return;
    _conversationId = conversationId;
    _muted = muted;
    _pinned = pinned;
    notifyListeners();
  }
}

/// Host → 会话列表：退出群聊等后立刻移除会话行。
class ConversationRemovedSignal extends ChangeNotifier {
  int _conversationId = 0;

  int get conversationId => _conversationId;

  void notifyRemoved(int conversationId) {
    if (conversationId <= 0) return;
    _conversationId = conversationId;
    notifyListeners();
  }
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
  late final AiSummaryService _aiSummaryService;
  late final ConversationRealtimeService _realtime;
  final ConversationRealtimeDedup _realtimeDedup = ConversationRealtimeDedup();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _listScrollController = ScrollController();

  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  StreamSubscription<Set<int>>? _onlineSub;
  Timer? _rtRefreshDebounce;
  Timer? _searchDebounce;
  Timer? _novaInboxPollTimer;
  Timer? _scrollRestoreRetry;

  bool _loading = true;
  String? _error;
  List<NativeConversation> _items = const <NativeConversation>[];
  AiSummaryItem? _aiSummaryPreview;
  int _aiSummaryUnread = 0;
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
    _aiSummaryService = AiSummaryService(session: widget.session);
    _realtime = ConversationRealtimeHub.instance.of(widget.session);
    WidgetsBinding.instance.addObserver(this);
    _listScrollController.addListener(_onListScroll);
    userAvatarRefresh.addListener(_onSelfAvatarUpdated);
    widget.conversationReadSignal?.addListener(_onConversationReadSignal);
    widget.memberSettingsSignal?.addListener(_onMemberSettingsSignal);
    widget.conversationRemovedSignal?.addListener(_onConversationRemovedSignal);
    final cached = ConversationInboxCache.instance.peek(widget.session.userId);
    if (cached != null) {
      _items = cached.conversations;
      _notif = cached.notif;
      _novaStorage = cached.novaStorage;
      _aiSummaryPreview = cached.aiSummaryPreview;
      _aiSummaryUnread = cached.aiSummaryUnread;
      _loading = false;
      unawaited(_load(silent: true));
    } else {
      unawaited(_load());
    }
    _bootRealtime();
    unawaited(_preloadRobotCatalog());
    NovaBackgroundCoordinator.instance.addListener(_onNovaBackgroundUpdate);
    RobotAnalyzingCoordinator.instance.bindSession(widget.session);
    RobotAnalyzingCoordinator.instance.addListener(_onRobotAnalyzingUpdate);
    if (widget.listVisible) {
      _scheduleScrollRestore();
    }
  }

  void _persistScrollNow() {
    if (!_listScrollController.hasClients) return;
    ConversationInboxCache.instance.saveScrollOffset(
      userId: widget.session.userId,
      offset: _listScrollController.offset,
    );
  }

  void _onListScroll() {
    // 隐藏期间不写入，避免异常布局把 0 偏移覆盖掉真实位置。
    if (!widget.listVisible) return;
    _persistScrollNow();
  }

  void _scheduleScrollRestore() {
    _scrollRestoreRetry?.cancel();
    void attempt() {
      if (!mounted || !widget.listVisible) return;
      _applySavedScroll();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => attempt());
    // 覆盖「返回后静默刷新 / 布局完成」竞态，连续多帧回写偏移。
    _scrollRestoreRetry = Timer.periodic(const Duration(milliseconds: 48), (t) {
      if (!mounted || !widget.listVisible || t.tick > 12) {
        t.cancel();
        return;
      }
      attempt();
    });
  }

  void _applySavedScroll() {
    if (!mounted || !widget.listVisible) return;
    final target = ConversationInboxCache.instance.peekScrollOffset(
      widget.session.userId,
    );
    if (target <= 0 || !_listScrollController.hasClients) return;
    final max = _listScrollController.position.maxScrollExtent;
    final next = target.clamp(0.0, max);
    if ((_listScrollController.offset - next).abs() < 0.5) return;
    _listScrollController.jumpTo(next);
  }

  VoidCallback _openWithScrollPersist(VoidCallback open) {
    return () {
      _persistScrollNow();
      open();
    };
  }

  Future<void> _preloadRobotCatalog() async {
    try {
      await RobotCatalogCache.instance.refresh(widget.session);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant NativeConversationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationReadSignal != widget.conversationReadSignal) {
      oldWidget.conversationReadSignal?.removeListener(
        _onConversationReadSignal,
      );
      widget.conversationReadSignal?.addListener(_onConversationReadSignal);
    }
    if (oldWidget.memberSettingsSignal != widget.memberSettingsSignal) {
      oldWidget.memberSettingsSignal?.removeListener(_onMemberSettingsSignal);
      widget.memberSettingsSignal?.addListener(_onMemberSettingsSignal);
    }
    if (oldWidget.conversationRemovedSignal !=
        widget.conversationRemovedSignal) {
      oldWidget.conversationRemovedSignal?.removeListener(
        _onConversationRemovedSignal,
      );
      widget.conversationRemovedSignal?.addListener(
        _onConversationRemovedSignal,
      );
    }
    final selected = widget.selectedConversationId ?? 0;
    final prev = oldWidget.selectedConversationId ?? 0;
    if (selected > 0 && selected != prev) {
      _clearUnreadLocally(selected);
    }
    // 从会话页返回：列表重新可见时强制恢复滚动（并扛住随后的静默刷新）。
    if (!oldWidget.listVisible && widget.listVisible) {
      _scheduleScrollRestore();
    } else if (oldWidget.listVisible && !widget.listVisible) {
      _persistScrollNow();
      _scrollRestoreRetry?.cancel();
    }
  }

  void _onConversationReadSignal() {
    final id = widget.conversationReadSignal?.conversationId ?? 0;
    if (id > 0) _clearUnreadLocally(id);
  }

  void _onMemberSettingsSignal() {
    final signal = widget.memberSettingsSignal;
    if (signal == null || !mounted) return;
    final id = signal.conversationId;
    if (id <= 0) return;
    final idx = _items.indexWhere((c) => c.id == id);
    if (idx < 0) return;
    final old = _items[idx];
    final nextMuted = signal.muted ?? old.muted;
    final nextPinned = signal.pinned ?? old.pinned;
    if (nextMuted == old.muted && nextPinned == old.pinned) return;
    setState(() {
      final copy = _items.toList(growable: true);
      copy[idx] = ConversationInboxRealtime.copyConversation(
        old,
        muted: nextMuted,
        pinned: nextPinned,
      );
      copy.sort((a, b) {
        final ap = a.pinned ? 1 : 0;
        final bp = b.pinned ? 1 : 0;
        if (ap != bp) return bp.compareTo(ap);
        return b.sortTimestamp.compareTo(a.sortTimestamp);
      });
      _items = copy;
    });
    _updateCommBadge(_items, _notif.unreadCount);
  }

  void _onConversationRemovedSignal() {
    final id = widget.conversationRemovedSignal?.conversationId ?? 0;
    if (id <= 0 || !mounted) return;
    unawaited(_removeConversationLocally(id));
  }

  Future<void> _removeConversationLocally(int conversationId) async {
    if (conversationId <= 0 || !mounted) return;
    _hiddenConversations = await InboxHiddenStorage.load();
    if (!mounted) return;
    final next = _items
        .where((c) => c.id != conversationId)
        .toList(growable: false);
    if (next.length == _items.length) {
      // 列表暂无该项时仍刷新隐藏集，避免后续静默拉取又露出来。
      return;
    }
    setState(() => _items = next);
    ConversationInboxCache.instance.put(
      userId: widget.session.userId,
      conversations: _items,
      notif: _notif,
      novaStorage: _novaStorage,
      aiSummaryPreview: _aiSummaryPreview,
      aiSummaryUnread: _aiSummaryUnread,
    );
    _updateCommBadge(_items, _notif.unreadCount);
  }

  void _clearUnreadLocally(int conversationId) {
    if (conversationId <= 0 || !mounted) return;
    final idx = _items.indexWhere((c) => c.id == conversationId);
    if (idx < 0) return;
    if (_items[idx].unreadCount <= 0) return;
    setState(() {
      final copy = _items.toList(growable: true);
      final old = copy[idx];
      copy[idx] = NativeConversation(
        id: old.id,
        kind: old.kind,
        title: old.title,
        unreadCount: 0,
        preview: old.preview,
        updatedAt: old.updatedAt,
        peerUserId: old.peerUserId,
        peerDisplayName: old.peerDisplayName,
        memberCount: old.memberCount,
        muted: old.muted,
        pinned: old.pinned,
        businessType: old.businessType,
        peerDepartment: old.peerDepartment,
        peerRoleLabel: old.peerRoleLabel,
        peerAvatarPreset: old.peerAvatarPreset,
        peerAvatarObjectKey: old.peerAvatarObjectKey,
        peerAvatarUrl: old.peerAvatarUrl,
        avatarMembers: old.avatarMembers,
        dissolved: old.dissolved,
        membershipStatus: old.membershipStatus,
        assistantGenerating: old.assistantGenerating,
        assistantGeneratingStatus: old.assistantGeneratingStatus,
      );
      _items = copy;
    });
    widget.commUnread.clearMutedMention(conversationId);
    _updateCommBadge(_items, _notif.unreadCount);
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

  void _onRobotAnalyzingUpdate() {
    if (!mounted || _loading) return;
    setState(() {});
  }

  @override
  void dispose() {
    if (_listScrollController.hasClients) {
      ConversationInboxCache.instance.saveScrollOffset(
        userId: widget.session.userId,
        offset: _listScrollController.offset,
      );
    }
    WidgetsBinding.instance.removeObserver(this);
    userAvatarRefresh.removeListener(_onSelfAvatarUpdated);
    widget.conversationReadSignal?.removeListener(_onConversationReadSignal);
    widget.memberSettingsSignal?.removeListener(_onMemberSettingsSignal);
    widget.conversationRemovedSignal?.removeListener(
      _onConversationRemovedSignal,
    );
    NovaBackgroundCoordinator.instance.removeListener(_onNovaBackgroundUpdate);
    RobotAnalyzingCoordinator.instance.removeListener(_onRobotAnalyzingUpdate);
    _scrollRestoreRetry?.cancel();
    _rtRefreshDebounce?.cancel();
    _searchDebounce?.cancel();
    _novaInboxPollTimer?.cancel();
    _rtSub?.cancel();
    _onlineSub?.cancel();
    _listScrollController.removeListener(_onListScroll);
    _listScrollController.dispose();
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
        if (event.type == 'ai_summary_updated') {
          _onAiSummaryRealtime(event);
          return;
        }
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

  bool get _isViewingAiSummary {
    final screen = widget.navigation.currentScreen;
    return screen == 'AS1' || screen == 'AS2' || screen == 'AS3';
  }

  bool get _isViewingApprovalAssistant =>
      widget.navigation.currentScreen == 'AA1';

  void _onAiSummaryRealtime(ConversationRealtimeEvent event) {
    final update = AiSummaryRealtimeUpdate.fromPayload(event.raw);
    if (!mounted) return;
    final terminal = update.status == 'SUCCESS' || update.status == 'FAILED';
    // 仅终态更新通讯列表预览；未读由服务端 read_at 统计。
    if (terminal) {
      setState(() {
        if (update.id > 0) {
          final prev = _aiSummaryPreview;
          _aiSummaryPreview = AiSummaryItem(
            id: update.id,
            theme: update.theme.isNotEmpty
                ? update.theme
                : (prev?.theme ?? '智能总结'),
            template: prev?.template ?? 'custom',
            conversationIds: prev?.conversationIds ?? const <int>[],
            memberUserIds: prev?.memberUserIds ?? const <int>[],
            memberCount: prev?.memberCount ?? 0,
            from: prev?.from,
            to: prev?.to,
            status: update.status,
            summaryPreview:
                update.preview ?? update.body ?? prev?.summaryPreview,
            createdAt: DateTime.now(),
            finishedAt: DateTime.now(),
            initiator:
                prev?.initiator ??
                const AiSummaryInitiator(userId: 0, displayName: ''),
          );
        }
      });
      unawaited(_syncAiSummaryUnreadFromServer());
    }
    unawaited(_refreshAiSummaryPreview());
  }

  Future<void> _syncAiSummaryUnreadFromServer() async {
    if (widget.session.isExternalUser) return;
    try {
      final unread = await _aiSummaryService.fetchUnreadCount();
      if (!mounted) return;
      setState(() => _aiSummaryUnread = unread);
      _updateCommBadge(_items, _notif.unreadCount);
    } catch (_) {
      if (mounted) _updateCommBadge(_items, _notif.unreadCount);
    }
  }

  Future<void> _openAiSummaryHub() async {
    widget.onOpenAiSummary();
  }

  Future<AiSummaryItem?> _safeFetchAiSummaryPreview() async {
    try {
      return await _aiSummaryService.fetchLatestPreview();
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshAiSummaryPreview() async {
    if (widget.session.isExternalUser) return;
    final latest = await _safeFetchAiSummaryPreview();
    if (!mounted) return;
    setState(() => _aiSummaryPreview = latest);
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
        activeOnChatScreen:
            (widget.selectedConversationId ?? 0) > 0 &&
            widget.selectedConversationId == convId,
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
    ConversationInboxCache.instance.put(
      userId: widget.session.userId,
      conversations: _items,
      notif: _notif,
      novaStorage: _novaStorage,
      aiSummaryPreview: _aiSummaryPreview,
      aiSummaryUnread: _aiSummaryUnread,
    );
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
    // 已有列表时不再整页转圈（下拉刷新用 RefreshIndicator，切 Tab 用静默刷新）。
    if (!silent && _items.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (!silent) {
      setState(() => _error = null);
    }
    try {
      final hidden = await InboxHiddenStorage.load();
      final results = await Future.wait(<Future<Object?>>[
        _service.fetchConversations(),
        _notificationService.fetchSummary(),
        NovaWebStorage.load(widget.session.userId),
        if (!widget.session.isExternalUser) _safeFetchAiSummaryPreview(),
        if (!widget.session.isExternalUser)
          _aiSummaryService.fetchUnreadCount(),
      ]);
      var rows = (results[0] as List<NativeConversation>)
          .where((c) => c.isVisible && !isConversationHidden(hidden, c.id))
          .toList(growable: true);
      // 内部用户确保审批助手会话存在，并入列表按 updatedAt 排序（不硬置顶）。
      if (!widget.session.isExternalUser &&
          widget.onOpenApprovalAssistant != null &&
          !rows.any((c) => c.isApprovalAssistant)) {
        try {
          final ensured = await _service.ensureApprovalAssistantSession();
          if (ensured.id > 0 && !rows.any((c) => c.id == ensured.id)) {
            rows = <NativeConversation>[...rows, ensured];
          }
        } catch (_) {
          // 后端未就绪时不影响其它会话列表。
        }
      }
      if (!widget.session.isExternalUser &&
          widget.onOpenTaskAssistant != null &&
          !rows.any((c) => c.isTaskAssistant)) {
        try {
          final ensured = await _service.ensureTaskAssistantSession();
          if (ensured.id > 0 && !rows.any((c) => c.id == ensured.id)) {
            rows = <NativeConversation>[...rows, ensured];
          }
        } catch (e) {
          // 后端未就绪时仍展示入口，点击时再尝试同步。
          debugPrint('[task-assistant] ensure failed: $e');
          rows = <NativeConversation>[
            ...rows,
            NativeConversation(
              id: 0,
              kind: 'TASK_ASSISTANT',
              title: '任务助手',
              unreadCount: 0,
              preview: '子任务分配 · 进度跟进',
              updatedAt: DateTime.now(),
            ),
          ];
        }
      }
      rows = List<NativeConversation>.unmodifiable(rows);
      final dissolved = (results[0] as List<NativeConversation>)
          .where((c) => c.dissolved && c.id > 0)
          .map((c) => c.id)
          .toList(growable: false);
      if (dissolved.isNotEmpty) {
        await InboxHiddenStorage.upgradeDissolved(dissolved);
      }
      final notif = results[1] as NativeNotificationSummary;
      final novaStorage = results[2] as Map<String, String>;
      final aiPreview = !widget.session.isExternalUser && results.length > 3
          ? results[3] as AiSummaryItem?
          : null;
      final aiUnread = !widget.session.isExternalUser && results.length > 4
          ? (results[4] as int? ?? 0)
          : 0;
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
        if (aiPreview != null || !silent) {
          _aiSummaryPreview = aiPreview;
        }
        // 智能总结未读：走 /ai/summaries/unread-count，不再依赖 AI_SUMMARY 通知。
        if (!_isViewingAiSummary) {
          _aiSummaryUnread = aiUnread;
        } else {
          _aiSummaryUnread = 0;
        }
        _loading = false;
        if (!silent) _error = null;
      });
      ConversationInboxCache.instance.put(
        userId: widget.session.userId,
        conversations: merged,
        notif: notif,
        novaStorage: novaStorage,
        aiSummaryPreview: _aiSummaryPreview,
        aiSummaryUnread: _aiSummaryUnread,
      );
      _syncNovaInboxPoll(merged, novaStorage);
      _updateCommBadge(merged, notif.unreadCount);
      // 静默刷新后 ListView 可能重建，把保存的偏移再写回去。
      if (widget.listVisible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _applySavedScroll();
        });
      }
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
    final selected = widget.selectedConversationId ?? 0;
    widget.commUnread.update(
      widget.commUnread.sumConversationUnread(
        rows: rows,
        notifUnread: notifUnread,
        aiSummaryUnread: _isViewingAiSummary ? 0 : _aiSummaryUnread,
        treatAsReadIds: selected > 0 ? <int>{selected} : const <int>{},
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
      onTap = _openWithScrollPersist(() => widget.onOpenPrivate(c));
    } else if (c.isRobot) {
      rowKind = ChatInboxRowKind.robot;
      onTap = _openWithScrollPersist(() => widget.onOpenRobot?.call(c));
    } else if (c.isApprovalAssistant) {
      rowKind = ChatInboxRowKind.approvalAssistant;
      onTap = _openWithScrollPersist(
        () => widget.onOpenApprovalAssistant?.call(c),
      );
    } else if (c.isTaskAssistant) {
      rowKind = ChatInboxRowKind.taskAssistant;
      onTap = _openWithScrollPersist(() => widget.onOpenTaskAssistant?.call(c));
    } else if (c.isReconciliationAssistant) {
      // 对账助手入口已屏蔽，后端若仍返回对应会话也不展示。
      return null;
    } else if (c.isWorkgroupApproval) {
      rowKind = ChatInboxRowKind.workgroupApproval;
      onTap = _openWithScrollPersist(() => widget.onOpenGroup(c));
    } else if (c.isGroup) {
      rowKind = ChatInboxRowKind.group;
      onTap = _openWithScrollPersist(() => widget.onOpenGroup(c));
    } else if (c.isBroadcast) {
      rowKind = ChatInboxRowKind.broadcast;
      onTap = _openWithScrollPersist(widget.onOpenNotifications);
    } else if (c.isAiAssistant) {
      rowKind = ChatInboxRowKind.aiAssistant;
      onTap = _openWithScrollPersist(() => _openNovaConversation(c));
    } else {
      rowKind = ChatInboxRowKind.group;
      onTap = _openWithScrollPersist(() => widget.onOpenGroup(c));
    }

    final gen = c.isAiAssistant
        ? _novaGeneratingFor(c)
        : (generating: false, status: '');

    // 暂时屏蔽私聊/群聊/机器人的左滑删除功能。
    final allowSwipeDelete =
        !(rowKind == ChatInboxRowKind.private ||
            rowKind == ChatInboxRowKind.group ||
            rowKind == ChatInboxRowKind.workgroupApproval ||
            rowKind == ChatInboxRowKind.robot ||
            rowKind == ChatInboxRowKind.approvalAssistant ||
            rowKind == ChatInboxRowKind.taskAssistant ||
            rowKind == ChatInboxRowKind.reconciliationAssistant);

    final robotKey = c.robotKey ?? '';
    final analyzingRobot =
        c.isRobot && RobotAnalyzingCoordinator.instance.isAnalyzing(c.id);
    final selected = widget.selectedConversationId == c.id;
    final row = ChatInboxRow(
      kind: rowKind,
      title: c.isReconciliationAssistant
          ? '对账助手'
          : c.isAiAssistant
          ? _yunshuName
          : (c.isApprovalAssistant
                ? '审批助手'
                : (c.isTaskAssistant ? '任务助手' : title)),
      subtitle: null,
      preview: analyzingRobot
          ? '正在分析…'
          : c.isAiAssistant
          ? resolveNovaInboxPreview(
              storage: _novaStorage,
              convId: c.id,
              serverPreview: c.preview,
              generating: gen.generating,
              generatingStatus: gen.status,
              allowLocalCache: true,
            )
          : c.isReconciliationAssistant
          ? (c.preview.isEmpty ? '每日对账 · 待你确认' : c.preview)
          : c.isRobot
          ? robotPlainPreview(c.preview, maxChars: 48)
          : c.preview.isEmpty && c.isApprovalAssistant
          ? '待办简报 · 解释 · 催办'
          : c.preview.isEmpty && c.isTaskAssistant
          ? '子任务分配 · 进度跟进'
          : c.preview,
      timeLabel: InboxFormat.formatTime(c.updatedAt, withClock: c.isPrivate),
      memberCount:
          c.isPrivate ||
              c.isRobot ||
              c.isApprovalAssistant ||
              c.isTaskAssistant ||
              c.isReconciliationAssistant ||
              kind == 'AI_ASSISTANT' ||
              kind == 'BROADCAST'
          ? null
          : c.memberCount,
      unreadCount: selected
          ? 0
          : (c.isAiAssistant &&
                    NovaBackgroundCoordinator.instance.hasUnreadReplyFor(c.id)
                ? (c.unreadCount > 0 ? c.unreadCount : 1)
                : widget.commUnread.effectiveUnreadCount(c)),
      muted: c.muted,
      pinned: c.pinned,
      showAiMark: c.isAiAssistant,
      selected:
          selected || (c.isApprovalAssistant && _isViewingApprovalAssistant),
      previewGenerating: (c.isAiAssistant && gen.generating) || analyzingRobot,
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
      robotAvatar: c.isRobot
          ? RobotFaceAvatar(
              role: RobotCatalogCache.instance.resolve(
                robotKey.isEmpty ? 'r_lighthouse' : robotKey,
              ),
              size: 45,
              animate: true,
              busy: analyzingRobot,
            )
          : null,
      sysTag: c.businessType,
      showDivider: true,
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
    // 审批助手 / 任务助手与机器人同属「聊天」区，内部用户全员可见。
    final chats = _sorted(
      _items
          .where(
            (c) =>
                c.isGroup ||
                c.isPrivate ||
                c.isRobot ||
                c.isApprovalAssistant ||
                c.isTaskAssistant ||
                c.isReconciliationAssistant,
          )
          .toList(),
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

    final chatRows = _buildChatRowsMergedWithAiSummary(chats);
    final aiTs = _aiSummaryPreview?.sortTime?.millisecondsSinceEpoch ?? 0;
    final chatTs = chats.isNotEmpty
        ? (chats.first.sortTimestamp > aiTs ? chats.first.sortTimestamp : aiTs)
        : aiTs;

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
      if (chatRows.isNotEmpty)
        _InboxSection(
          key: 'chat',
          label: '聊天',
          count: chatRows.length,
          timestamp: chatTs,
          pinned: false,
          leading: const Icon(
            Icons.chat_bubble_outline,
            size: 11,
            color: DunesColors.text3,
          ),
          rows: chatRows,
        ),
    ];

    sections.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sections;
  }

  /// 智能总结与私聊/群/机器人/审批助手/任务助手同一排序：置顶优先，再按最近时间。
  /// 仅在已有分析结果时显示智能总结（默认不占位）。
  List<Widget> _buildChatRowsMergedWithAiSummary(
    List<NativeConversation> chats,
  ) {
    final entries = <({int ts, bool pinned, Widget row})>[];
    for (final c in chats) {
      final row = _buildConvRow(c);
      if (row == null) continue;
      entries.add((ts: c.sortTimestamp, pinned: c.pinned, row: row));
    }
    final aiRow = _buildAiSummaryInboxRow();
    if (aiRow != null) {
      final ts = _aiSummaryPreview?.sortTime?.millisecondsSinceEpoch ?? 0;
      entries.add((ts: ts, pinned: false, row: aiRow));
    }
    final reconciliationRow = _buildReconciliationAssistantInboxRow();
    if (reconciliationRow != null &&
        !chats.any((c) => c.isReconciliationAssistant)) {
      entries.add((
        ts: DateTime.now().millisecondsSinceEpoch,
        pinned: false,
        row: reconciliationRow,
      ));
    }
    entries.sort((a, b) {
      final ap = a.pinned ? 1 : 0;
      final bp = b.pinned ? 1 : 0;
      if (ap != bp) return bp.compareTo(ap);
      return b.ts.compareTo(a.ts);
    });
    return entries.map((e) => e.row).toList(growable: false);
  }

  Widget? _buildReconciliationAssistantInboxRow() {
    // 对账助手暂为静态预览，入口先屏蔽；恢复时按 onOpenReconciliationAssistant 硬插会话行即可。
    return null;
  }

  Widget? _buildAiSummaryInboxRow() {
    if (widget.session.isExternalUser) return null;
    final preview = _aiSummaryPreview;
    // 默认不展示；仅分析产出结果（SUCCESS）后出现在通讯页。
    if (preview == null || !preview.isSuccess) return null;
    final previewText = preview.inboxPreview;
    if (!_matchesSearch('智能总结', previewText)) return null;
    return KeyedSubtree(
      key: const ValueKey<String>('ai-summary-inbox'),
      child: ChatInboxRow(
        kind: ChatInboxRowKind.aiSummary,
        title: '智能总结',
        preview: previewText,
        timeLabel: InboxFormat.formatTime(preview.sortTime),
        unreadCount: _aiSummaryUnread,
        previewGenerating: false,
        selected: _isViewingAiSummary,
        onTap: () => unawaited(_openAiSummaryHub()),
      ),
    );
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
                onOpenFavorites: widget.onOpenFavorites,
                onOpenAiSummary: widget.session.isExternalUser
                    ? null
                    : () => unawaited(_openAiSummaryHub()),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null && _items.isEmpty) {
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
      onRefresh: () => _load(silent: true),
      child: ListView(
        // 不用 PageStorageKey：曾被 Offstage 钳成 0 的偏移会写回并盖掉恢复。
        controller: _listScrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        // 必须裁剪：头像 OverflowBox / 未读角标会画出行外，否则上滑会盖住「消息」标题与搜索栏。
        clipBehavior: Clip.hardEdge,
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
