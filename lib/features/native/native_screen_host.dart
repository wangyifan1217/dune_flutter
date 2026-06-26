import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/http/session_http.dart';
import '../../core/navigation/navigation_controller.dart';
import '../../core/navigation/generated/screen_registry.dart';
import '../../core/theme/dunes_theme.dart';
import '../approval/native_approval_page.dart';
import '../auth/auth_session.dart';
import '../chat/native_broadcast_page.dart';
import '../chat/native_chat_search_page.dart';
import '../chat/native_group_chat_page.dart';
import '../chat/native_group_info_page.dart';
import '../chat/native_group_media_page.dart';
import '../chat/native_new_chat_page.dart';
import '../chat/native_notifications_page.dart';
import '../chat/native_private_chat_page.dart';
import '../contacts/contact_models.dart';
import '../contacts/native_contact_profile_page.dart';
import '../contacts/native_contacts_page.dart';
import '../conversation/comm_unread_notifier.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_mention_utils.dart';
import '../conversation/conversation_realtime_dedup.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/native_conversation_page.dart';
import '../conversation/notification_service.dart';
import '../kb/native_kb_chat_page.dart';
import '../kb/native_kb_doc_page.dart';
import '../kb/native_kb_home_page.dart';
import '../kb/native_kb_models.dart';
import '../kb/native_kb_service.dart';
import '../xflow/native_b10_page.dart';
import '../xflow/native_b3_page.dart';
import '../xflow/native_xflow_form_page.dart';
import '../xflow/xflow_models.dart';
import '../xflow/xflow_service.dart';
import '../nova/native_nova_history_page.dart';
import '../nova/native_nova_page.dart';
import '../nova/nova_background_coordinator.dart';
import '../push/push_service.dart';
import '../shell/dunes_main_tab_bar.dart';
import '../shell/dunes_toast.dart';
import '../workbench/native_avatar_sheet.dart';
import '../workbench/native_my_workbench_pages.dart';
import '../workbench/workbench_badge_notifier.dart';

class NativeScreenHost extends StatefulWidget {
  const NativeScreenHost({
    super.key,
    required this.session,
    required this.navigation,
    this.onLogout,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final VoidCallback? onLogout;

  @override
  State<NativeScreenHost> createState() => _NativeScreenHostState();
}

class _NativeScreenHostState extends State<NativeScreenHost> {
  final CommUnreadNotifier _commUnread = CommUnreadNotifier();
  final WorkbenchBadgeNotifier _workbenchBadge = WorkbenchBadgeNotifier();
  final WorkbenchDataRefreshNotifier _workbenchRefresh = WorkbenchDataRefreshNotifier();
  int _lastPendingInitiateForMe = 0;
  bool _hasPendingInitiateBaseline = false;
  NativeConversation? _selectedPrivate;
  NativeConversation? _selectedGroup;
  NativeConversation? _selectedBroadcast;
  NativeContact? _selectedContact;
  int? _selectedPrivatePeerUserId;
  int _searchConversationId = 0;
  String _searchTitle = '聊天搜索';
  String _searchReturnScreen = 'C5';
  int? _focusMessageId;
  NativeChatMessage? _focusMessageHint;
  int? _novaFocusConversationId;
  int? _novaFocusMessageId;
  int _mediaConversationId = 0;
  String _mediaTitle = '群聊';
  String? _kbSelectedDocId;
  String _kbChatKind = 'KB_ALL';
  String? _kbChatDocId;
  int _selectedProposalId = 0;
  XflowTodoHint? _selectedTodoHint;
  String _b10BackScreen = 'P1';
  String _xflowTemplateKey = 'sales-proposal';
  int? _xflowEditProposalId;
  String _xflowFormBackScreen = 'B3';
  String? _b14InitialFilter;
  final ConversationRealtimeDedup _commBadgeDedup = ConversationRealtimeDedup();
  StreamSubscription<ConversationRealtimeEvent>? _commBadgeRtSub;
  Timer? _commBadgeRefreshDebounce;
  Timer? _workbenchBadgeRefreshDebounce;
  final Map<int, bool> _mutedConvIds = <int, bool>{};

  @override
  void initState() {
    super.initState();
    _commUnread.addListener(_onCommUnreadChanged);
    unawaited(ConversationRealtimeHub.instance.of(widget.session).connect());
    NovaBackgroundCoordinator.instance.addListener(_onNovaCoordinatorUpdate);
    unawaited(_bootCommBadgeRealtime());
    unawaited(_refreshCommUnreadBadge());
    unawaited(_refreshWorkbenchBadge());
    unawaited(bindPushSession(
      userId: widget.session.userId,
      token: widget.session.token,
      apiBase: widget.session.apiBase,
    ));
    registerPushLifecycleObserver();
  }

  void _onCommUnreadChanged() {
    syncPushBadgeCount(_commUnread.total);
  }

  @override
  void dispose() {
    _commUnread.removeListener(_onCommUnreadChanged);
    _commBadgeRefreshDebounce?.cancel();
    _workbenchBadgeRefreshDebounce?.cancel();
    _commBadgeRtSub?.cancel();
    dismissDunesActionToast();
    NovaBackgroundCoordinator.instance.removeListener(_onNovaCoordinatorUpdate);
    unawaited(unbindPushSession());
    _commUnread.dispose();
    _workbenchBadge.dispose();
    _workbenchRefresh.dispose();
    super.dispose();
  }

  Future<void> _bootCommBadgeRealtime() async {
    try {
      final rt = ConversationRealtimeHub.instance.of(widget.session);
      await rt.connect();
      _commBadgeRtSub = rt.events.listen(_onCommBadgeRealtimeEvent);
    } catch (_) {
      // Tab badge realtime is best-effort.
    }
  }

  void _onCommBadgeRealtimeEvent(ConversationRealtimeEvent event) {
    if (event.type == 'workbench_updated') {
      _scheduleWorkbenchBadgeRefresh(
        rejected: event.raw['event']?.toString() == 'approval_rejected',
      );
      return;
    }

    const relevant = <String>{
      'message',
      'system_flow',
      'read',
      'conversation_updated',
      'notification',
    };
    if (!relevant.contains(event.type)) return;
    if (!_commBadgeDedup.consume(event)) return;

    if (event.type == 'read') {
      final userId = (event.raw['userId'] as num?)?.toInt() ?? 0;
      final convId = event.conversationId ?? 0;
      if (userId == widget.session.userId && convId > 0) {
        _commUnread.clearMutedMention(convId);
      }
      _scheduleCommBadgeRefresh();
      return;
    }

    if (event.type == 'message' || event.type == 'system_flow') {
      if (!_isPeerRealtimeMessage(event)) return;
      final convId = event.conversationId ?? 0;
      if (_isViewingConversation(convId)) return;

      final mentionHit = ConversationMentionUtils.eventMentionsMeFromRealtime(
        event: event,
        selfUserId: widget.session.userId,
        selfDisplayName: widget.session.displayName,
      );
      final isMuted = _mutedConvIds[convId] == true;

      if (mentionHit && convId > 0) {
        _commUnread.recordMutedMention(convId);
        return;
      }
      if (!isMuted) {
        if (widget.navigation.currentScreen != 'C1') {
          _commUnread.bump();
        }
        _notifyAndroidPushForEvent(event);
        _scheduleCommBadgeRefresh();
      }
      return;
    }

    if (event.type == 'notification') {
      _notifyAndroidPushForEvent(event);
    }

    _scheduleCommBadgeRefresh();
  }

  void _notifyAndroidPushForEvent(ConversationRealtimeEvent event) {
    final convId = event.conversationId ?? 0;
    var title = '沙丘';
    var body = '您有新消息';
    if (event.type == 'notification') {
      title = (event.raw['title'] ?? '系统通知').toString();
      body = (event.raw['body'] ?? event.raw['content'] ?? '您有新的系统通知').toString();
    } else {
      final msg = event.raw['message'];
      if (msg is Map) {
        body = (msg['bodyText'] ?? msg['content'] ?? msg['text'] ?? body).toString();
        final sender = msg['sender'];
        if (sender is Map) {
          final name = (sender['displayName'] ?? sender['name'] ?? '').toString().trim();
          if (name.isNotEmpty) title = name;
        }
      }
    }
    notifyPushRealtimeMessage(title: title, body: body, conversationId: convId);
  }

  void _scheduleCommBadgeRefresh() {
    _commBadgeRefreshDebounce?.cancel();
    _commBadgeRefreshDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      unawaited(_refreshCommUnreadBadge());
    });
  }

  void _scheduleWorkbenchBadgeRefresh({bool rejected = false}) {
    _workbenchBadgeRefreshDebounce?.cancel();
    _workbenchBadgeRefreshDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      unawaited(_refreshWorkbenchBadge(notifyRejected: rejected));
    });
  }

  Future<void> _refreshWorkbenchBadge({bool notifyRejected = false}) async {
    try {
      final resp = await dunesHttpGet(widget.session, '/workbench/my-stats');
      if (resp.statusCode < 200 || resp.statusCode >= 300) return;
      final body = jsonDecode(resp.body);
      final raw = body is Map<String, dynamic>
          ? (body['data'] is Map<String, dynamic>
              ? body['data'] as Map<String, dynamic>
              : body)
          : const <String, dynamic>{};
      final stats = _NativeMyStats.fromJson(raw);
      if (!mounted) return;
      final delta = _workbenchBadge.takeNewPendingDelta(stats.pendingForMe);
      final pi = stats.pendingInitiateForMe;
      var pendingInitiateDelta = 0;
      if (!_hasPendingInitiateBaseline) {
        _lastPendingInitiateForMe = pi;
        _hasPendingInitiateBaseline = true;
      } else if (pi > _lastPendingInitiateForMe) {
        pendingInitiateDelta = pi - _lastPendingInitiateForMe;
        _lastPendingInitiateForMe = pi;
      } else {
        _lastPendingInitiateForMe = pi;
      }
      _workbenchRefresh.bump();
      if (delta > 0 && !notifyRejected) {
        showDunesToast(context, '您有 $delta 条新的待审批，请及时处理');
      } else if (pendingInitiateDelta > 0) {
        showDunesActionToast(
          context,
          '有 $pendingInitiateDelta 条同事推送的提案待您确认发起',
          actionLabel: '去查看',
          icon: Icons.assignment_ind_outlined,
          onTap: () {
            if (!mounted) return;
            _goB14(filter: 'PENDING_INITIATE');
          },
        );
      } else if (notifyRejected) {
        showDunesActionToast(
          context,
          '您有 1 条审批被驳回，请及时查看',
          actionLabel: '去查看',
          icon: Icons.warning_amber_rounded,
          onTap: () {
            if (!mounted) return;
            _goB14();
          },
        );
      }
    } catch (_) {
      // Workbench badge is best-effort.
    }
  }

  bool _isPeerRealtimeMessage(ConversationRealtimeEvent event) {
    final msg = event.raw['message'];
    if (msg is! Map) return false;
    final sender = msg['sender'];
    var senderId = 0;
    if (sender is Map) {
      senderId = (sender['userId'] as num?)?.toInt() ?? 0;
    }
    if (senderId <= 0) {
      senderId = (msg['senderUserId'] as num?)?.toInt() ?? 0;
    }
    return senderId > 0 && senderId != widget.session.userId;
  }

  bool _isViewingConversation(int convId) {
    if (convId <= 0) return false;
    final screen = widget.navigation.currentScreen;
    if (screen == 'C5' && _selectedPrivate?.id == convId) return true;
    if (screen == 'C2' && _selectedGroup?.id == convId) return true;
    if (screen == 'C10' && _selectedBroadcast?.id == convId) return true;
    return false;
  }

  void _onNovaCoordinatorUpdate() {
    final shouldBump = NovaBackgroundCoordinator.instance.takePendingCommBadgeBump();
    final notOnC4 = widget.navigation.currentScreen != 'C4';
    unawaited(_handleNovaCoordinatorBadge(shouldBump: shouldBump && notOnC4));
  }

  Future<void> _handleNovaCoordinatorBadge({required bool shouldBump}) async {
    await _refreshCommUnreadBadge();
    if (!mounted || !shouldBump || widget.navigation.currentScreen == 'C4') return;
    if (_commUnread.total == 0) _commUnread.bump();
    showDunesToast(context, 'NOVA已回复，可返回查看');
  }

  Future<void> _refreshCommUnreadBadge() async {
    try {
      final convService = ConversationService(session: widget.session);
      final notifService = NotificationService(session: widget.session);
      final results = await Future.wait(<Future<Object?>>[
        convService.fetchConversations(),
        notifService.fetchSummary(),
      ]);
      final rows = results[0] as List<NativeConversation>;
      final notif = results[1] as NativeNotificationSummary;
      _mutedConvIds
        ..clear()
        ..addEntries(
          rows
              .where(CommUnreadNotifier.isMutedGroup)
              .map((c) => MapEntry(c.id, true)),
        );
      if (mounted) {
        _commUnread.update(
          _commUnread.sumConversationUnread(rows: rows, notifUnread: notif.unreadCount),
        );
        syncPushBadgeCount(_commUnread.total);
      }
    } catch (_) {
      // Tab badge is best-effort.
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.navigation.currentScreen) {
      case 'B2':
        return _NativeB2Page(
          session: widget.session,
          navigation: widget.navigation,
          commUnread: _commUnread,
          workbenchBadge: _workbenchBadge,
          workbenchRefresh: _workbenchRefresh,
          onOpenB14: _goB14,
          onLogout: widget.onLogout,
        );
      case 'C1':
        return NativeConversationPage(
          session: widget.session,
          navigation: widget.navigation,
          commUnread: _commUnread,
          workbenchBadge: _workbenchBadge,
          onOpenPrivate: (conv) {
            setState(() {
              _selectedPrivate = conv;
              _selectedPrivatePeerUserId = conv.peerUserId;
              _focusMessageId = null;
              _focusMessageHint = null;
            });
            widget.navigation.go('C5');
          },
          onOpenGroup: (conv) {
            setState(() {
              _selectedGroup = conv;
              _focusMessageId = null;
              _focusMessageHint = null;
            });
            widget.navigation.go('C2');
          },
          onOpenContacts: () => widget.navigation.go('C3'),
          onOpenNova: () {
            setState(() {
              _novaFocusConversationId = null;
              _novaFocusMessageId = null;
            });
            widget.navigation.go('C4');
          },
          onOpenNotifications: () => widget.navigation.go('Z2'),
          onOpenBroadcast: (conv) {
            setState(() => _selectedBroadcast = conv);
            widget.navigation.go('C10');
          },
          onOpenNewChat: () => widget.navigation.go('C7'),
        );
      case 'Z2':
        return NativeNotificationsPage(
          session: widget.session,
          onBack: widget.navigation.back,
        );
      case 'C10':
        return NativeBroadcastPage(
          session: widget.session,
          conversationHint: _selectedBroadcast,
          onBack: widget.navigation.back,
        );
      case 'C7':
        return NativeNewChatPage(
          session: widget.session,
          onBack: widget.navigation.back,
          onOpenPrivateChat: (peerUserId) {
            setState(() {
              _selectedPrivate = null;
              _selectedPrivatePeerUserId = peerUserId;
              _focusMessageId = null;
              _focusMessageHint = null;
            });
            widget.navigation.go('C5');
          },
          onOpenGroupChat: (conversation) {
            setState(() {
              _selectedGroup = conversation;
              _focusMessageId = null;
              _focusMessageHint = null;
            });
            widget.navigation.go('C2');
          },
        );
      case 'C6':
        if (_selectedGroup == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.back();
          });
          return const SizedBox.shrink();
        }
        return NativeGroupInfoPage(
          session: widget.session,
          conversationHint: _selectedGroup!,
          onBack: widget.navigation.back,
          onOpenSearch: (convId) {
            setState(() {
              _searchConversationId = convId;
              _searchTitle = '${_selectedGroup?.title ?? '群聊'} · 搜索';
              _searchReturnScreen = 'C6';
            });
            widget.navigation.go('C12');
          },
          onOpenMedia: (convId) {
            setState(() {
              _mediaConversationId = convId;
              _mediaTitle = _selectedGroup?.title ?? '群聊';
            });
            widget.navigation.go('C13');
          },
          onOpenMember: (userId, displayName) {
            setState(() {
              _selectedContact = NativeContact(userId: userId, displayName: displayName);
            });
            widget.navigation.go('C9');
          },
          onOpenApproval: () => _goB14(),
          onExitedGroup: () => widget.navigation.go('C1'),
        );
      case 'C3':
        return NativeContactsPage(
          session: widget.session,
          onBack: widget.navigation.back,
          onOpenContact: (contact) {
            setState(() => _selectedContact = contact);
            widget.navigation.go('C9');
          },
          onStartPrivateChat: (peerUserId) {
            setState(() {
              _selectedPrivate = null;
              _selectedPrivatePeerUserId = peerUserId;
              _focusMessageId = null;
              _focusMessageHint = null;
            });
            widget.navigation.go('C5');
          },
        );
      case 'C9':
        return NativeContactProfilePage(
          session: widget.session,
          contactHint: _selectedContact,
          onBack: widget.navigation.back,
          onOpenPrivateChat: (peerUserId) {
            setState(() {
              _selectedPrivate = null;
              _selectedPrivatePeerUserId = peerUserId;
              _focusMessageId = null;
              _focusMessageHint = null;
            });
            widget.navigation.go('C5');
          },
        );
      case 'B13':
        return NativeApprovalPage(
          session: widget.session,
          onOpenProposal: (item) => _openProposalDetail(item, from: 'B13'),
          onBack: widget.navigation.back,
          workbenchRefresh: _workbenchRefresh,
        );
      case 'B1':
        return NativeMyApprovalWorkbenchPage(
          session: widget.session,
          onOpenProposal: (item) => _openProposalDetail(item, from: 'B1'),
          onBack: widget.navigation.back,
          workbenchRefresh: _workbenchRefresh,
        );
      case 'B14':
        return NativeMyInitiatedPage(
          session: widget.session,
          onOpenProposal: (item) => _openProposalDetail(item, from: 'B14'),
          onBack: widget.navigation.back,
          initialStatusFilter: _b14InitialFilter,
          workbenchRefresh: _workbenchRefresh,
        );
      case 'P1':
        return NativeMyCcProposalPage(
          session: widget.session,
          onOpenProposal: (item) => _openProposalDetail(item, from: 'P1'),
          onBack: widget.navigation.back,
          workbenchRefresh: _workbenchRefresh,
        );
      case 'B3':
        return NativeB3Page(
          session: widget.session,
          navigation: widget.navigation,
          onOpenForm: (templateKey) {
            setState(() {
              _xflowTemplateKey = templateKey;
              _xflowEditProposalId = null;
              _xflowFormBackScreen = 'B3';
            });
            widget.navigation.go('XF');
          },
        );
      case 'XF':
        return NativeXflowFormPage(
          session: widget.session,
          navigation: widget.navigation,
          templateKey: _xflowTemplateKey,
          editProposalId: _xflowEditProposalId,
          backScreen: _xflowFormBackScreen,
          onDeleted: () {
            setState(() {
              _xflowEditProposalId = null;
            });
          },
          onSubmitted: (proposalId) {
            setState(() {
              _selectedProposalId = proposalId;
              _selectedTodoHint = null;
              if (_xflowEditProposalId == null) {
                _b10BackScreen = 'B3';
              }
            });
            widget.navigation.go('B10');
          },
        );
      case 'B10':
        return NativeB10Page(
          session: widget.session,
          navigation: widget.navigation,
          proposalId: _selectedProposalId,
          todoHint: _selectedTodoHint,
          backScreen: _b10BackScreen,
          onReedit: (proposalId) {
            setState(() {
              _xflowTemplateKey = 'sales-proposal';
              _xflowEditProposalId = proposalId;
              _xflowFormBackScreen = _b10BackScreen;
            });
            widget.navigation.go('XF');
          },
        );
      case 'C4':
        return NativeNovaPage(
          session: widget.session,
          onBack: widget.navigation.back,
          onHistory: () => widget.navigation.go('C11'),
          onOpenKb: () => widget.navigation.go('K1'),
          focusConversationId: _novaFocusConversationId,
          focusMessageId: _novaFocusMessageId,
          onClearHistoryFocus: () {
            setState(() {
              _novaFocusConversationId = null;
              _novaFocusMessageId = null;
            });
          },
        );
      case 'C11':
        return NativeNovaHistoryPage(
          session: widget.session,
          onBack: widget.navigation.back,
          onOpenConversation: (convId, messageId, title, preview) {
            setState(() {
              _novaFocusConversationId = convId;
              // 从历史列表进入会话时默认展示到最底部（最新消息），不跳到某条中间消息。
              _novaFocusMessageId = null;
            });
            widget.navigation.go('C4');
          },
        );
      case 'K1':
        return NativeKbHomePage(
          session: widget.session,
          navigation: widget.navigation,
          onBack: widget.navigation.back,
          onOpenChat: () {
            setState(() {
              _kbChatKind = 'KB_ALL';
              _kbChatDocId = null;
            });
            widget.navigation.go('K2');
          },
        );
      case 'K3':
        return NativeKbDocPage(
          session: widget.session,
          navigation: widget.navigation,
          docId: _kbSelectedDocId ?? '',
          onAskAi: (docId) {
            setState(() {
              _kbChatKind = 'KB_DOC';
              _kbChatDocId = docId;
            });
            widget.navigation.go('K2');
          },
        );
      case 'K2':
        return NativeKbChatPage(
          session: widget.session,
          navigation: widget.navigation,
          chatKind: _kbChatKind,
          docId: _kbChatDocId,
        );
      case 'C2':
        return NativeGroupChatPage(
          session: widget.session,
          conversationHint: _selectedGroup,
          focusMessageId: _focusMessageId,
          focusMessageHint: _focusMessageHint,
          onBack: () {
            setState(() {
              _focusMessageId = null;
              _focusMessageHint = null;
            });
            widget.navigation.back();
          },
          onOpenSearch: (convId) {
            setState(() {
              _searchConversationId = convId;
              _searchTitle = _selectedGroup?.title ?? '群聊搜索';
              _searchReturnScreen = 'C2';
              _focusMessageId = null;
              _focusMessageHint = null;
            });
            widget.navigation.go('C12');
          },
          onOpenMedia: (convId) {
            setState(() {
              _mediaConversationId = convId;
              _mediaTitle = _selectedGroup?.title ?? '群聊';
            });
            widget.navigation.go('C13');
          },
          onOpenGroupInfo: () => widget.navigation.go('C6'),
        );
      case 'C5':
        return NativePrivateChatPage(
          session: widget.session,
          conversationHint: _selectedPrivate,
          peerUserIdHint: _selectedPrivatePeerUserId,
          focusMessageId: _focusMessageId,
          focusMessageHint: _focusMessageHint,
          onBack: () {
            setState(() {
              _focusMessageId = null;
              _focusMessageHint = null;
            });
            widget.navigation.back();
          },
          onOpenProfile: () {
            final peerId = _selectedPrivate?.peerUserId ?? _selectedPrivatePeerUserId;
            if (peerId != null && peerId > 0) {
              setState(() {
                _selectedContact = NativeContact(
                  userId: peerId,
                  displayName: _selectedPrivate?.peerDisplayName ?? _selectedPrivate?.title ?? '',
                );
              });
            }
            widget.navigation.go('C9');
          },
          onOpenSearch: (convId) {
            setState(() {
              _searchConversationId = convId;
              _searchTitle = '${_selectedPrivate?.displayTitle ?? '私聊'} · 搜索';
              _searchReturnScreen = 'C5';
              _focusMessageId = null;
              _focusMessageHint = null;
            });
            widget.navigation.go('C12');
          },
        );
      case 'C12':
        return NativeChatSearchPage(
          session: widget.session,
          conversationId: _searchConversationId,
          title: _searchTitle,
          onBack: widget.navigation.back,
          onLocateMessage: (message) {
            setState(() {
              _focusMessageId = message.id;
              _focusMessageHint = message;
            });
            widget.navigation.go(_searchReturnScreen);
          },
        );
      case 'C13':
        return NativeGroupMediaPage(
          session: widget.session,
          conversationId: _mediaConversationId,
          title: _mediaTitle,
          onBack: widget.navigation.back,
        );
      default:
        final info = dunesScreenById(widget.navigation.currentScreen);
        return _NativeStubPage(
          title: info?.name ?? widget.navigation.currentScreen,
          subtitle: '该页面暂未上线',
          onBack: widget.navigation.canGoBack ? widget.navigation.back : null,
        );
    }
  }

  /// 进入「我发起的(B14)」并可选预置筛选（如「待发起」用于代发起人入口）。
  void _goB14({String? filter}) {
    setState(() => _b14InitialFilter = filter);
    widget.navigation.go('B14');
  }

  void _openProposalDetail(XflowProposalItem item, {required String from}) {
    // 「我发起的」列表点击草稿 → 进入可继续填写的表单（与提交页一致），并可删除草稿。
    if (from == 'B14' && item.status.toUpperCase() == 'DRAFT') {
      setState(() {
        _xflowTemplateKey = 'sales-proposal';
        _xflowEditProposalId = item.id;
        _xflowFormBackScreen = from;
      });
      widget.navigation.go('XF');
      return;
    }
    setState(() {
      _selectedProposalId = item.id;
      _selectedTodoHint = item.todoHint;
      _b10BackScreen = from;
    });
    widget.navigation.go('B10');
  }
}

class _NativeB2Page extends StatefulWidget {
  const _NativeB2Page({
    required this.session,
    required this.navigation,
    required this.commUnread,
    required this.workbenchBadge,
    required this.workbenchRefresh,
    required this.onOpenB14,
    this.onLogout,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final CommUnreadNotifier commUnread;
  final WorkbenchBadgeNotifier workbenchBadge;
  final WorkbenchDataRefreshNotifier workbenchRefresh;
  final void Function({String? filter}) onOpenB14;
  final VoidCallback? onLogout;

  @override
  State<_NativeB2Page> createState() => _NativeB2PageState();
}

class _NativeB2PageState extends State<_NativeB2Page> {
  _NativeMyStats? _stats;
  NativeKbSummary? _kbSummary;
  _NativeB2Profile? _profile;
  bool _loading = true;
  String? _loadError;
  bool _avatarSheetOpen = false;

  @override
  void initState() {
    super.initState();
    widget.workbenchRefresh.addListener(_onWorkbenchDataRefresh);
    _loadStats();
    _refreshCommBadge();
  }

  @override
  void dispose() {
    widget.workbenchRefresh.removeListener(_onWorkbenchDataRefresh);
    super.dispose();
  }

  void _onWorkbenchDataRefresh() {
    if (!mounted) return;
    unawaited(_loadStats(silent: true));
  }

  Future<void> _refreshCommBadge() async {
    try {
      final convService = ConversationService(session: widget.session);
      final notifService = NotificationService(session: widget.session);
      final results = await Future.wait(<Future<Object?>>[
        convService.fetchConversations(),
        notifService.fetchSummary(),
      ]);
      final rows = results[0] as List<NativeConversation>;
      final notif = results[1] as NativeNotificationSummary;
      if (mounted) {
        widget.commUnread.update(
          widget.commUnread.sumConversationUnread(rows: rows, notifUnread: notif.unreadCount),
        );
      }
    } catch (_) {
      // Tab badge is best-effort on B2.
    }
  }

  Future<NativeKbSummary?> _fetchKbSummary() async {
    try {
      return await NativeKbService(session: widget.session).fetchSummary();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadStats({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final xflow = XflowService(session: widget.session);
      List<XflowProposalItem>? initiatedRows;
      final results = await Future.wait<Object?>(<Future<Object?>>[
        dunesHttpGet(widget.session, '/workbench/my-stats'),
        _fetchKbSummary(),
        _loadProfile(),
        xflow.fetchB14Initiated().then<List<XflowProposalItem>?>((v) => v).catchError((_) => null),
      ]);
      final resp = results[0] as http.Response;
      final kbSummary = results[1] as NativeKbSummary?;
      final profile = results[2] as _NativeB2Profile;
      initiatedRows = results[3] as List<XflowProposalItem>?;
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final body = jsonDecode(resp.body);
      final raw = body is Map<String, dynamic>
          ? (body['data'] is Map<String, dynamic>
              ? body['data'] as Map<String, dynamic>
              : body)
          : const <String, dynamic>{};
      if (!mounted) return;
      var stats = _NativeMyStats.fromJson(raw);
      if (initiatedRows != null) {
        stats = stats.alignedWithInitiatedList(initiatedRows);
      }
      setState(() {
        _stats = stats;
        _kbSummary = kbSummary;
        _profile = profile;
        _loading = false;
      });
      widget.workbenchBadge.update(_stats?.pendingForMe ?? 0);
    } catch (error) {
      if (!mounted) return;
      if (silent) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  void _showSoonToast([String label = '敬请期待']) {
    showDunesSoonToast(context, label);
  }

  Future<_NativeB2Profile> _loadProfile() async {
    try {
      final meResp = await dunesHttpGet(widget.session, '/users/me');
      if (meResp.statusCode < 200 || meResp.statusCode >= 300) {
        return _NativeB2Profile.fromSession(widget.session);
      }
      final body = jsonDecode(meResp.body);
      final data = body is Map<String, dynamic>
          ? (body['data'] is Map<String, dynamic>
              ? body['data'] as Map<String, dynamic>
              : body)
          : const <String, dynamic>{};
      final avatarPreset =
          (data['avatarPreset'] ?? data['peerAvatarPreset'] ?? '').toString();
      final objectKey = (data['avatarObjectKey'] ?? data['peerAvatarObjectKey'] ?? '')
          .toString();
      String avatarUrl = (data['avatarUrl'] ??
              data['avatar'] ??
              data['avatarSrc'] ??
              data['avatarImage'] ??
              '')
          .toString();
      if (avatarPreset.isEmpty &&
          objectKey.isNotEmpty &&
          avatarUrl.isEmpty) {
        try {
          final preResp = await dunesHttpGet(
            widget.session,
            '/storage/presigned-get?bucket=user-avatars&objectKey=${Uri.encodeQueryComponent(objectKey)}',
          );
          if (preResp.statusCode >= 200 && preResp.statusCode < 300) {
            final preBody = jsonDecode(preResp.body);
            if (preBody is Map<String, dynamic>) {
              final preData = preBody['data'];
              if (preData is Map<String, dynamic>) {
                avatarUrl =
                    (preData['url'] ?? preData['downloadUrl'] ?? '').toString();
              } else {
                avatarUrl = (preBody['url'] ?? preBody['downloadUrl'] ?? '')
                    .toString();
              }
            }
          }
        } catch (_) {}
      }
      return _NativeB2Profile(
        displayName:
            (data['displayName'] ?? data['name'] ?? widget.session.displayName ?? '')
                .toString(),
        phone: (data['phone'] ?? widget.session.phone).toString(),
        departmentName: (data['departmentName'] ?? data['department'] ?? '')
            .toString()
            .trim(),
        title: (data['title'] ?? data['positionName'] ?? '').toString().trim(),
        avatarPreset: avatarPreset,
        avatarObjectKey: objectKey,
        avatarUrl: avatarUrl,
      );
    } catch (_) {
      return _NativeB2Profile.fromSession(widget.session);
    }
  }

  Future<void> _openAvatarEditor() async {
    if (_avatarSheetOpen) return;
    final profile = _profile ?? _NativeB2Profile.fromSession(widget.session);
    setState(() => _avatarSheetOpen = true);
    try {
      final updated = await NativeAvatarSheet.show(
        context,
        session: widget.session,
        initialPreset: profile.avatarPreset,
        initialObjectKey: profile.avatarObjectKey,
        initialAvatarUrl: profile.avatarUrl,
      );
      if (updated == null || !mounted) return;
      final refreshed = await _loadProfile();
      if (!mounted) return;
      setState(() => _profile = refreshed);
      showDunesToast(context, '头像已更新');
    } finally {
      if (mounted) setState(() => _avatarSheetOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats ?? const _NativeMyStats.empty();
    final initiatedTotal =
        stats.initiatedByMe +
        stats.pendingInitiateForMe +
        stats.approvalPending +
        stats.approvalRejected;
    final profile = _profile ?? _NativeB2Profile.fromSession(widget.session);
    final kb = _kbSummary;
    final kbDocCount = kb != null && kb.documents.isNotEmpty
        ? kb.documents.length
        : (kb?.documentCount ?? 0);
    final kbCategoryCount = kb?.categoryCount ?? 0;
    final kbUnreadCount = kb?.unreadCount ?? 0;
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildB2TopBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadStats,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                  children: [
                    _buildProfileCard(stats, profile),
                    const SizedBox(height: 10),
                    _buildQuickStats(stats),
                    const SizedBox(height: 14),
                    _buildQuickLaunch(),
                    const SizedBox(height: 14),
                    if (stats.pendingForMe > 0)
                      _buildReminderBanner(
                        icon: Icons.notifications_active_outlined,
                        text: '您有 ${stats.pendingForMe} 条待审批，点击进入「我审批的」',
                        onTap: () => widget.navigation.go('B1'),
                      ),
                    if (stats.approvalRejected > 0) ...[
                      const SizedBox(height: 8),
                      _buildReminderBanner(
                        icon: Icons.warning_amber_rounded,
                        text: '您有 ${stats.approvalRejected} 条审批被驳回，点击进入「我发起的审批」',
                        onTap: () => widget.onOpenB14(),
                      ),
                    ],
                    if (stats.pendingInitiateForMe > 0) ...[
                      const SizedBox(height: 8),
                      _buildReminderBanner(
                        icon: Icons.assignment_ind_outlined,
                        text: '有 ${stats.pendingInitiateForMe} 条同事推送给您、待您确认发起的提案',
                        onTap: () => widget.onOpenB14(filter: 'PENDING_INITIATE'),
                      ),
                    ],
                    if (stats.pendingForMe > 0 ||
                        stats.approvalRejected > 0 ||
                        stats.pendingInitiateForMe > 0)
                      const SizedBox(height: 14),
                    _buildSectionLabel('我的事项 · 审批与穿透'),
                    const SizedBox(height: 8),
                    _buildMenuList(<Widget>[
                      _buildMenuItem(
                        icon: Icons.send_outlined,
                        title: '我发起的审批',
                        desc:
                            '${initiatedTotal} 条总数 · ${stats.pendingInitiateForMe} 条代发起 · ${stats.approvalPending} 审批中',
                        badge: initiatedTotal,
                        onTap: () => widget.onOpenB14(),
                      ),
                      _buildMenuItem(
                        icon: Icons.assignment_outlined,
                        title: '抄送我的提案',
                        desc: '${stats.ccProposalCount} 份抄送 · ${stats.ccProposalPending} 审批中',
                        badge: stats.ccProposalCount,
                        onTap: () => widget.navigation.go('P1'),
                      ),
                      _buildMenuItem(
                        icon: Icons.fact_check_outlined,
                        title: '我审批的',
                        desc: '${stats.pendingForMe} 待我审 · ${stats.handledThisMonth} 已审核',
                        badge: stats.pendingForMe,
                        tint: const Color(0xFFDFF1E8),
                        onTap: () => widget.navigation.go('B1'),
                      ),
                      _buildMenuItem(
                        icon: Icons.menu_book_outlined,
                        title: '知识库',
                        desc: '$kbDocCount 文档 · $kbCategoryCount 分类 · $kbUnreadCount 未读',
                        badge: kbUnreadCount,
                        onTap: () => widget.navigation.go('K1'),
                      ),
                      _buildMenuItem(
                        icon: Icons.edit_outlined,
                        title: '写汇报',
                        desc: '0 篇 · 0 草稿 · 日 / 周 / 月 / 季',
                        badge: 0,
                        comingSoon: true,
                        onTap: () => _showSoonToast(),
                      ),
                      _buildMenuItem(
                        icon: Icons.mic_none_rounded,
                        title: '会议纪要',
                        desc: '0 条 · 0 已生成 · 0 转写中',
                        badge: 0,
                        comingSoon: true,
                        onTap: () => _showSoonToast(),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    _buildMenuList(<Widget>[
                      _buildMenuItem(
                        icon: Icons.receipt_long_outlined,
                        title: '应付账单',
                        desc: '${stats.outstandingInvoices} 待处理 · 总 ¥0 · 灯塔联动',
                        badge: stats.outstandingInvoices,
                        tint: const Color(0xFFE1ECF7),
                        comingSoon: true,
                        onTap: () => _showSoonToast(),
                      ),
                      _buildMenuItem(
                        icon: Icons.file_copy_outlined,
                        title: '我的合同 / 用印记录',
                        desc: '0 份 · 0 临期 · 寄出待回收 0',
                        comingSoon: true,
                        onTap: () => _showSoonToast(),
                      ),
                      _buildMenuItem(
                        icon: Icons.warning_amber_rounded,
                        title: '欠票催办',
                        desc: '0 笔 · ¥0 · 欠 0 天',
                        badge: 0,
                        tint: const Color(0xFFF5E5DC),
                        comingSoon: true,
                        onTap: () => _showSoonToast(),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                    if (_loadError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton(
                          onPressed: _loadStats,
                          child: const Text('数据同步失败，点击重试'),
                        ),
                      ),
                    if (widget.onLogout != null) ...[
                      const SizedBox(height: 8),
                      _buildLogoutButton(),
                    ],
                  ],
                ),
              ),
            ),
            DunesMainTabBar(
              navigation: widget.navigation,
              activeScreen: 'B2',
              commUnread: widget.commUnread,
              workbenchBadge: widget.workbenchBadge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 28),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: widget.onLogout,
          icon: const Icon(Icons.logout, size: 18, color: DunesColors.coral),
          label: Text(
            '退出登录',
            style: DunesTypography.sans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: DunesColors.coral,
            ),
          ),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: BorderSide(color: DunesColors.coral.withValues(alpha: 0.28)),
            backgroundColor: DunesColors.coral.withValues(alpha: 0.08),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  Widget _buildB2TopBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: '沙丘',
                  style: TextStyle(
                    color: Color(0xFF7C5CE6),
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
                TextSpan(
                  text: ' DUNES',
                  style: TextStyle(color: DunesColors.text3, fontSize: 10),
                ),
                TextSpan(
                  text: '  ·  我的',
                  style: TextStyle(color: DunesColors.text2, fontSize: 10),
                ),
              ],
            ),
          ),
          const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => widget.navigation.go('B3'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: DunesColors.accentSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 15, color: DunesColors.accentDeep),
                  SizedBox(width: 2),
                  Text(
                    '发起',
                    style: TextStyle(
                      color: DunesColors.accentDeep,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(_NativeMyStats stats, _NativeB2Profile profile) {
    final name = profile.displayName.trim().isEmpty
        ? (widget.session.displayName ?? widget.session.phone).trim()
        : profile.displayName.trim();
    final avatarText = name.isEmpty ? '我' : name.characters.first;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFFF0ECF6), Color(0xFFE7E2F2), Color(0xFFDCD5EA)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: _avatarSheetOpen ? null : _openAvatarEditor,
            borderRadius: BorderRadius.circular(99),
            child: Stack(
              children: [
                NativeAvatarCircle(
                  size: 52,
                  avatarPreset: profile.avatarPreset,
                  avatarUrl: profile.avatarUrl,
                  fallbackText: avatarText,
                ),
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Icon(
                      _avatarSheetOpen ? Icons.more_horiz : Icons.edit,
                      size: 11,
                      color: DunesColors.accentDeep,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '未命名用户' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 3),
                Text(
                  profile.subtitleLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: DunesColors.text2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(_NativeMyStats stats) {
    final initiatedTotal =
        stats.initiatedByMe +
        stats.pendingInitiateForMe +
        stats.approvalPending +
        stats.approvalRejected;
    Widget soonBadge() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: const Color(0xE61F2421),
          borderRadius: BorderRadius.circular(99),
        ),
        child: const Text(
          '敬请期待',
          style: TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    Widget cell(String title, String value, {bool soon = false, VoidCallback? onTap}) {
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 70,
          decoration: BoxDecoration(
            color: const Color(0xFFF0EEE8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 8.5, color: DunesColors.text3),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: .9,
                      ),
                    ),
                  ],
                ),
              ),
              if (soon)
                Positioned(
                  top: 3,
                  right: 3,
                  child: soonBadge(),
                ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final cellW = ((constraints.maxWidth - gap * 3) / 4).clamp(0.0, double.infinity);
        return Row(
          children: [
            SizedBox(
              width: cellW,
              child: cell(
                '待我处理',
                '${stats.pendingForMe}',
                onTap: () => widget.navigation.go('B1'),
              ),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: cellW,
              child: cell(
                '我发起的',
                '$initiatedTotal',
                onTap: () => widget.onOpenB14(),
              ),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: cellW,
              child: cell(
                '本月经办',
                '${stats.handledThisMonth}',
                soon: true,
                onTap: _showSoonToast,
              ),
            ),
            const SizedBox(width: gap),
            SizedBox(
              width: cellW,
              child: cell(
                '欠票',
                '${stats.outstandingInvoices}笔',
                soon: true,
                onTap: _showSoonToast,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickLaunch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('快速发起', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
            const Spacer(),
            TextButton(
              onPressed: () => widget.navigation.go('B3'),
              child: const Text(
                '销售提案  →',
                style: TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => widget.navigation.go('B3'),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 136,
            height: 112,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DunesColors.border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6F5BC9),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Icon(
                        Icons.assignment_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFEAFF),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          '新建',
                          style: TextStyle(fontSize: 7.5, color: Color(0xFF7058D8)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('销售提案', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: DunesColors.text2,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildReminderBanner({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFFF5EEE1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF8A5A14)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF6E4A11)),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 16, color: Color(0xFF8A5A14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuList(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String desc,
    VoidCallback? onTap,
    int? badge,
    bool comingSoon = false,
    Color tint = const Color(0xFFE9E4F5),
  }) {
    final row = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 15, color: DunesColors.accentDeep),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(desc, style: const TextStyle(fontSize: 10, color: DunesColors.text3)),
                  ],
                ),
              ),
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC6C2B8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              const Icon(Icons.chevron_right_rounded, color: DunesColors.text3),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
    final withBorder = Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: row,
    );
    if (!comingSoon) return withBorder;
    return Stack(
      children: [
        withBorder,
        Positioned.fill(
          child: InkWell(
            onTap: onTap,
            child: Container(
              color: const Color(0x38FFFFFF),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 44),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xE61F2421),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  '敬请期待',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NativeMyStats {
  const _NativeMyStats({
    required this.pendingForMe,
    required this.initiatedByMe,
    required this.approvalPending,
    required this.handledThisMonth,
    required this.outstandingInvoices,
    required this.approvalRejected,
    required this.ccProposalCount,
    required this.ccProposalPending,
    required this.pendingInitiateForMe,
  });

  const _NativeMyStats.empty()
      : pendingForMe = 0,
        initiatedByMe = 0,
        approvalPending = 0,
        handledThisMonth = 0,
        outstandingInvoices = 0,
        approvalRejected = 0,
        ccProposalCount = 0,
        ccProposalPending = 0,
        pendingInitiateForMe = 0;

  final int pendingForMe;
  final int initiatedByMe;
  final int approvalPending;
  final int handledThisMonth;
  final int outstandingInvoices;
  final int approvalRejected;
  final int ccProposalCount;
  final int ccProposalPending;

  /// 待我发起：他人推送给我、待我确认发起的提案数。
  final int pendingInitiateForMe;

  /// 与 B14「我发起的」列表口径对齐，避免 my-stats 历史 approval 行导致数字偏大/横幅闪烁。
  _NativeMyStats alignedWithInitiatedList(List<XflowProposalItem> rows) {
    var initiated = 0;
    var pending = 0;
    var rejected = 0;
    for (final row in rows) {
      switch (row.status.toUpperCase()) {
        case 'PENDING_INITIATE':
          // 待我发起口径仅信任 my-stats.pendingInitiateForMe，这里不覆盖。
          break;
        case 'PENDING':
          pending++;
          break;
        case 'REJECTED':
          rejected++;
          break;
        default:
          initiated++;
          break;
      }
    }
    return copyWith(
      initiatedByMe: initiated,
      approvalPending: pending,
      approvalRejected: rejected,
    );
  }

  _NativeMyStats copyWith({
    int? initiatedByMe,
    int? pendingInitiateForMe,
    int? approvalPending,
    int? approvalRejected,
  }) {
    return _NativeMyStats(
      pendingForMe: pendingForMe,
      initiatedByMe: initiatedByMe ?? this.initiatedByMe,
      approvalPending: approvalPending ?? this.approvalPending,
      handledThisMonth: handledThisMonth,
      outstandingInvoices: outstandingInvoices,
      approvalRejected: approvalRejected ?? this.approvalRejected,
      ccProposalCount: ccProposalCount,
      ccProposalPending: ccProposalPending,
      pendingInitiateForMe: pendingInitiateForMe ?? this.pendingInitiateForMe,
    );
  }

  factory _NativeMyStats.fromJson(Map<String, dynamic> json) {
    int readInt(List<String> keys) {
      for (final key in keys) {
        final raw = json[key];
        if (raw is num) return raw.toInt();
      }
      return 0;
    }

    return _NativeMyStats(
      pendingForMe: readInt(<String>['pendingForMe', 'openTodos']),
      initiatedByMe: readInt(<String>['initiatedByMe', 'initiated']),
      approvalPending: readInt(<String>['approvalPending']),
      handledThisMonth:
          readInt(<String>['approvalHandled', 'handledThisMonth', 'approved']),
      outstandingInvoices: readInt(<String>['outstandingInvoices']),
      approvalRejected: readInt(<String>['approvalRejected']),
      ccProposalCount: readInt(<String>['ccProposalCount']),
      ccProposalPending: readInt(<String>['ccProposalPending']),
      pendingInitiateForMe: readInt(<String>['pendingInitiateForMe']),
    );
  }
}

class _NativeB2Profile {
  const _NativeB2Profile({
    required this.displayName,
    required this.phone,
    required this.departmentName,
    required this.title,
    required this.avatarPreset,
    required this.avatarObjectKey,
    required this.avatarUrl,
  });

  final String displayName;
  final String phone;
  final String departmentName;
  final String title;
  final String avatarPreset;
  final String avatarObjectKey;
  final String avatarUrl;

  String get subtitleLine {
    final parts = <String>[
      if (departmentName.isNotEmpty) departmentName,
      if (title.isNotEmpty) title,
      if (phone.trim().isNotEmpty) phone.trim(),
    ];
    return parts.join(' · ');
  }

  factory _NativeB2Profile.fromSession(AuthSession session) {
    return _NativeB2Profile(
      displayName: session.displayName ?? '',
      phone: session.phone,
      departmentName: '',
      title: '',
      avatarPreset: '',
      avatarObjectKey: '',
      avatarUrl: '',
    );
  }
}

class _NativeStubPage extends StatelessWidget {
  const _NativeStubPage({
    required this.title,
    required this.subtitle,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return _NativeScaffold(
      title: title,
      body: [
        _InfoTile(label: '状态', value: subtitle),
        if (onBack != null)
          _ActionTile(
            title: '返回',
            subtitle: '回到上一页',
            onTap: onBack,
          ),
      ],
    );
  }
}

class _NativeScaffold extends StatelessWidget {
  const _NativeScaffold({
    required this.title,
    required this.body,
  });

  final String title;
  final List<Widget> body;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  Text(
                    'NATIVE PILOT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: DunesColors.text3,
                          letterSpacing: 0.8,
                        ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: body.length,
                padding: const EdgeInsets.all(16),
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, index) => body[index],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                  ],
                ),
              ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: DunesColors.text3,
                ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: DunesColors.text3)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
