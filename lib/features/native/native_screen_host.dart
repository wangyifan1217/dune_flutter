import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/http/session_http.dart';
import '../../core/layout/chat_layout.dart';
import '../../core/navigation/navigation_controller.dart';
import '../../core/navigation/generated/screen_registry.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/app_text_scale.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/cached_network_image.dart';
import '../../core/widgets/spotlight_tour.dart';
import '../weekly_summary/native_weekly_summary_page.dart';
import '../approval/native_approval_page.dart';
import '../approval_assistant/native_approval_assistant_page.dart';
import '../approval_assistant/native_approval_assistant_pending_page.dart';
import '../approval_assistant/native_approval_assistant_proposal_page.dart';
import '../proposal_intake/proposal_intake_overlay.dart';
import '../task_assistant/native_task_assistant_page.dart';
import '../reconciliation/native_reconciliation_assistant_page.dart';
import '../auth/auth_session.dart';
import '../auth/invite_qr_page.dart';
import '../auth/qr_login_scan_page.dart';
import '../chat/native_broadcast_page.dart';
import '../desktop/native_desktop_settings_page.dart';
import '../chat/chat_foreground_sync.dart';
import '../chat/desktop_composer_focus.dart';
import '../chat/native_chat_search_page.dart';
import '../chat/native_favorites_page.dart';
import '../chat/native_group_chat_page.dart';
import '../chat/native_group_info_page.dart';
import '../chat/native_group_media_page.dart';
import '../chat/native_message_center_page.dart';
import '../chat/native_private_chat_page.dart';
import '../chat/native_self_memo_settings_page.dart';
import '../contacts/contact_models.dart';
import '../contacts/native_contact_profile_page.dart';
import '../contacts/native_contacts_page.dart';
import '../ctrip/native_ctrip_h5_page_v2.dart';
import '../ctrip/native_ctrip_pc_page.dart';
import '../xrxs/native_xrxs_h5_page.dart';
import '../xrxs/native_xrxs_pc_page.dart';
import '../am_sso/native_am_sso_page.dart';
import '../conversation/chat_dual_pane_shell.dart';
import '../conversation/comm_unread_notifier.dart';
import '../conversation/conversation_inbox_realtime.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_mention_utils.dart';
import '../conversation/conversation_realtime_dedup.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_hidden_storage.dart';
import '../conversation/native_conversation_page.dart';
import '../conversation/notification_service.dart';
import '../desktop/windows_desktop_tray.dart';
import '../desktop/windows_tray_unread_items.dart';
import '../kb/kb_upload_coordinator.dart';
import '../kb/native_kb_chat_page.dart';
import '../kb/native_kb_doc_page.dart';
import '../kb/native_kb_home_page.dart';
import '../kb/native_kb_models.dart';
import '../kb/native_kb_service.dart';
import '../xflow/native_b10_page.dart';
import '../xflow/native_b3_page.dart';
import '../xflow/native_xflow_proposal_page.dart';
import '../xflow/native_xflow_submission_page.dart';
import '../xflow/approval_chat_share.dart';
import '../xflow/approval_detail_dialog.dart';
import '../xflow/proposal_launch_config.dart';
import '../xflow/xflow_models.dart';
import '../xflow/xflow_service.dart';
import '../nova/native_nova_history_page.dart';
import '../nova/native_nova_page.dart';
import '../nova/nova_background_coordinator.dart';
import '../nova/nova_web_storage.dart';
import '../push/push_service.dart';
import '../push/in_app_message_banner.dart';
import '../conversation/message_preview_text.dart';
import '../qianji/native_qianji_cursor_account_detail_page.dart';
import '../qianji/native_qianji_cursor_account_page.dart';
import '../qianji/native_qianji_fund_secondment_detail_page.dart';
import '../qianji/native_qianji_fund_secondment_page.dart';
import '../qianji/native_qianji_detail_page.dart';
import '../qianji/native_qianji_hub_page.dart';
import '../qianji/efficiency/native_qianji_efficiency_boss_preview.dart';
import '../qianji/efficiency/native_qianji_efficiency_page.dart';
import '../qianji/native_qianji_iteration_page.dart';
import '../qianji/native_qianji_kb_supervise_page.dart';
import '../qianji/digital_auto/digital_auto_config.dart';
import '../qianji/digital_auto/digital_employee_service.dart';
import '../qianji/digital_auto/native_digital_auto_chat_page.dart';
import '../qianji/native_qianji_meeting_supervise_page.dart';
import '../qianji/native_qianji_my_perf_page.dart';
import '../qianji/native_qianji_project_tasks_page.dart';
import '../qianji/native_qianji_projects_page.dart';
import '../qianji/native_qianji_session_supervise_page.dart';
import '../qianji/native_qianji_task_detail_page.dart';
import '../qianji/native_qianji_team_perf_page.dart';
import '../qianji/native_qianji_cash_flow_board_page.dart';
import '../qianji/native_qianji_monthly_bill_page.dart';
import '../qianji/travel/native_qianji_travel_page.dart';
import '../qianji/qianji_models.dart';
import '../qianji/qianji_project_models.dart';
import '../qianji_admin/native_qianji_admin_shell.dart';
import '../robots/native_robot_chat_page.dart';
import '../robots/native_robot_consult_create_page.dart';
import '../robots/native_robot_consult_detail_page.dart';
import '../robots/native_robot_consult_list_page.dart';
import '../robots/robot_models.dart';
import '../../core/util/friendly_error.dart';
import '../shell/dunes_main_tab_bar.dart';
import '../shell/dunes_toast.dart';
import '../update/app_update_dialog.dart';
import '../update/app_update_notifier.dart';
import '../update/app_update_service.dart';
import '../workbench/native_avatar_sheet.dart';
import '../workbench/native_my_workbench_pages.dart';
import '../workbench/workbench_badge_notifier.dart';
import '../lighthouse/native_lighthouse_page.dart';
import '../lighthouse/platform_tree.dart';
import '../meeting/meeting_list_cache.dart';
import '../meeting/meeting_abandoned_recovery.dart';
import '../meeting/meeting_live_controller.dart';
import '../meeting/meeting_recording_interruption.dart';
import '../meeting/meeting_upload_coordinator.dart';
import '../meeting/native_meeting_create_page.dart';
import '../meeting/native_meeting_detail_page.dart';
import '../meeting/native_meeting_list_page.dart';
import '../meeting/native_meeting_service.dart';
import '../wechat/native_wechat_bot_page.dart';
import '../ai_summary/ai_summary_models.dart';
import '../ai_summary/ai_summary_service.dart';
import '../ai_summary/native_ai_summary_create_page.dart';
import '../ai_summary/native_ai_summary_detail_page.dart';
import '../ai_summary/native_ai_summary_hub_page.dart';
import '../drive/native_drive_page.dart';
import '../drive/native_drive_assistant_page.dart';
import '../xrxs/native_xrxs_assistant_page.dart';
import '../administrative_notice/native_administrative_notice_page.dart';
import '../profile/native_profile_tour.dart';
import '../profile/native_user_work_profile_page.dart';
import '../profile/native_work_profile_collaboration_page.dart';
import '../profile/native_work_profile_detail_pages.dart';
import '../profile/native_work_profile_perf_page.dart';
import '../tasks/native_task_detail_page.dart';

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

class _NativeScreenHostState extends State<NativeScreenHost>
    with WidgetsBindingObserver {
  final CommUnreadNotifier _commUnread = CommUnreadNotifier();
  final WorkbenchBadgeNotifier _workbenchBadge = WorkbenchBadgeNotifier();
  final WorkbenchDataRefreshNotifier _workbenchRefresh =
      WorkbenchDataRefreshNotifier();
  int _lastPendingInitiateForMe = 0;
  bool _hasPendingInitiateBaseline = false;
  NativeConversation? _selectedPrivate;
  NativeConversation? _selectedGroup;
  NativeConversation? _selectedRobot;
  NativeConversation? _selectedApprovalAssistant;
  NativeConversation? _selectedTaskAssistant;
  NativeConversation? _selectedDriveAssistant;
  NativeConversation? _selectedXrxsAssistant;
  NativeConversation? _selectedWeeklySummary;
  NativeConversation? _selectedReconciliation;
  bool _openDailyReconPending = false;
  int _dailyReconOpenToken = 0;
  String _dailyReconAsOfDate = '';
  String _dailyReconCardType = '';
  NativeConversation? _selectedAdministrativeNotice;
  int? _administrativeNoticeTargetId;
  int? _driveTargetItemId;
  String? _xrxsLoginSid;
  String? _xrxsLoginRole;
  String? _ssoAppKey;
  String _ssoAppTitle = '';
  ApprovalAssistantPickMode _approvalAssistantPickMode =
      ApprovalAssistantPickMode.browse;
  String _approvalAssistantProposalKind = 'sales';

  /// 作废过期的「打开审批助手」异步结果，避免从灯塔等会话被事后抢跳到 AA1。
  int _approvalAssistantOpenGen = 0;

  /// 双栏右侧会话保活：机器人↔私聊/群切换时不销毁 State，避免整页转圈。
  static const int _maxDualChatKeepAlive = 8;
  final LinkedHashMap<String, _DualChatSlot> _dualChatSlots =
      LinkedHashMap<String, _DualChatSlot>();
  final Map<String, GlobalKey> _dualChatKeys = <String, GlobalKey>{};
  NativeConversation? _selectedBroadcast;
  String? _messageCenterInitialTab;
  bool _messageCenterMarkAllOnEnter = false;
  NativeContact? _selectedContact;

  /// PC 双栏：从会话打开名片时嵌在右侧栏，返回目标为 C2/C5；通讯录等入口为 null（整页）。
  String? _profileReturnScreen;
  bool _contactsGroupPickMode = false;
  Set<int> _contactsInitialSelectedUserIds = <int>{};
  Set<int> _contactsLockedSelectedUserIds = <int>{};
  Map<int, String> _contactsInitialSelectedNames = <int, String>{};
  int? _selectedPrivatePeerUserId;
  int? _selectedAiSummaryId;
  List<int> _aiSummaryPrefillConversationIds = const <int>[];
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
  NativeKbDocument? _kbSelectedDoc;
  String _kbChatKind = 'KB_ALL';
  String? _kbChatDocId;
  DateTime? _workProfileMonth;
  int _selectedProposalId = 0;
  XflowTodoHint? _selectedTodoHint;
  String _b10BackScreen = 'P1';
  String _xflowTemplateKey = XflowService.boundTemplateKeyForMenu(
    '/business/proposals/new',
  );
  String _b3InitialCategory = 'biz';
  String _b3SearchQuery = '';
  int? _xflowEditProposalId;
  String _xflowEditBusinessType = 'PROPOSAL';
  String _selectedSubmissionBusinessType = '';
  int _selectedSubmissionBusinessId = 0;
  String _xflowFormBackScreen = 'B3';
  String? _b14InitialFilter;
  int _meetingId = 0;
  int _cursorBindingId = 0;
  int _fundSecondmentId = 0;
  String _selectedRobotConsultId = '';

  /// 从通讯机器人会话进入 QJR 时带上 robotKey。
  String _qjrRobotKey = 'r_lighthouse';
  DigitalEmployeeItem? _selectedDigitalEmployee;

  /// true：从 IM 机器人会话进咨询明细；false：从 NOVA 板块进入。
  bool _qjrOpenedFromChat = false;
  String _lastMyScreen = 'B2';

  /// NOVA 板块离开时记住的子页（返回时恢复，对标 `_lastMyScreen`）。
  String _lastQianjiScreen = 'QJ';
  QianjiEntity? _selectedQianjiEntity;
  QianjiIteration? _selectedQianjiIteration;
  QianjiProjectItem? _selectedQianjiProject;
  QianjiTaskItem? _selectedQianjiTask;
  final ConversationRealtimeDedup _commBadgeDedup = ConversationRealtimeDedup();
  StreamSubscription<ConversationRealtimeEvent>? _commBadgeRtSub;
  Timer? _commBadgeRefreshDebounce;
  Timer? _commBadgeRecorrectTimer;
  Timer? _workbenchBadgeRefreshDebounce;
  bool _commBadgeRefreshInFlight = false;
  bool _commBadgeRefreshQueued = false;
  DateTime? _commBadgeRefreshBackoffUntil;
  bool _workbenchBadgeRefreshInFlight = false;
  bool _workbenchBadgeRefreshQueued = false;
  DateTime? _workbenchBadgeRefreshBackoffUntil;
  final Map<int, bool> _mutedConvIds = <int, bool>{};
  // 用于桌面实时弹框：群聊标题应使用会话名称，而不是消息发送人。
  final Map<int, NativeConversation> _commBadgeConversations =
      <int, NativeConversation>{};
  String? _lastScreen;
  int _lastHistoryDepth = 0;

  /// Keep lighthouse subtree alive across 通讯/我的 tab switches so L2/filters
  /// are not wiped by AnimatedSwitcher dispose. Created on first LH visit.
  bool _lighthouseMounted = false;

  /// Keep 手机端会话列表 alive：进 C2/C5 等会话页再返回时不 dispose，保留滚动位置。
  bool _inboxMounted = false;
  final GlobalKey _inboxPageKey = GlobalKey(
    debugLabel: 'inbox-page-keep-alive',
  );

  /// Keep 通讯录 alive：进 C9 名片再返回时不 dispose，保留列表滚动位置。
  bool _contactsMounted = false;
  final GlobalKey _contactsPageKey = GlobalKey(
    debugLabel: 'contacts-page-keep-alive',
  );

  /// Keep PC 通讯双栏 alive across 灯塔/我的/NOVA tab switches，避免列表整页转圈。
  bool _commDualMounted = false;
  final GlobalKey _commDualKeepAliveKey = GlobalKey(
    debugLabel: 'comm-dual-keep-alive',
  );

  /// Keep 工作台 alive：切到聊天后再回来，提案填写等内页不销毁。
  bool _workbenchMounted = false;
  final GlobalKey _workbenchKeepAliveKey = GlobalKey(
    debugLabel: 'workbench-keep-alive',
  );

  /// 允许在已读回执或重新拿到服务端快照后把桌面角标同步为 0。
  ///
  /// APP 可能在后台时收不到 PC 端发出的实时已读事件；下次恢复/启动
  /// 时必须允许“服务端总未读为 0”清掉遗留的系统角标。
  bool _pendingBadgeZeroSync = false;

  /// 用户本次前台会话内主动点进聊天；切后台后清零，避免 resume 误触已读。
  bool _userActivelyInChat = false;
  final Set<int> _tpnsOpeningConversationIds = <int>{};

  /// 已上报给服务端的「正在查看」会话，用于抑制该会话 APP TPNS。
  int _reportedActiveViewConvId = 0;
  Timer? _activeViewHeartbeat;

  /// mark-read 成功后通知双栏列表清零对应未读角标。
  final ConversationReadSignal _conversationReadSignal =
      ConversationReadSignal();

  /// 系统通知列表进入后完成已读，通知通讯列表同步本地通知未读数。
  final NotificationsReadSignal _notificationsReadSignal =
      NotificationsReadSignal();

  /// 资料页切换置顶 / 免打扰后立刻同步会话列表。
  final ConversationMemberSettingsSignal _conversationMemberSettingsSignal =
      ConversationMemberSettingsSignal();
  final ConversationRemovedSignal _conversationRemovedSignal =
      ConversationRemovedSignal();

  /// PC 侧栏「设置」页（保留侧栏，内容区切换）。
  bool _desktopSettingsOpen = false;
  bool _desktopSettingsChildReturnPending = false;
  bool _desktopQrLoginOpening = false;

  void _markUserEnteredChat() {
    _userActivelyInChat = true;
    _syncActiveViewReport();
  }

  void _markUserLeftChat() {
    _userActivelyInChat = false;
    _syncActiveViewReport();
  }

  /// 当前打开的会话 id（不判断窗口前后台）。
  int? _peekViewingConversationId() {
    final dualId = _dualPaneSelectedConversationId;
    if (dualId != null && dualId > 0) return dualId;
    final screen = widget.navigation.currentScreen;
    if (screen == 'C5') {
      final id = _selectedPrivate?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'C2') {
      final id = _selectedGroup?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'CR') {
      final id = _selectedRobot?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'C10') {
      final id = _selectedBroadcast?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'AA1') {
      final id = _selectedApprovalAssistant?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'TA1') {
      final id = _selectedTaskAssistant?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'DA1') {
      final id = _selectedDriveAssistant?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'XA1') {
      final id = _selectedXrxsAssistant?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'WS1') {
      final id = _selectedWeeklySummary?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'AN1') {
      final id = _selectedAdministrativeNotice?.id ?? 0;
      return id > 0 ? id : null;
    }
    return null;
  }

  void _syncActiveViewReport() {
    final shouldReport = _userActivelyInChat && !windowsTrayIsWindowInactive();
    final nextId = shouldReport ? (_peekViewingConversationId() ?? 0) : 0;
    final prevId = _reportedActiveViewConvId;
    if (nextId == prevId) {
      if (nextId > 0 && _activeViewHeartbeat == null) {
        _startActiveViewHeartbeat();
      }
      return;
    }
    final service = ConversationService(session: widget.session);
    if (prevId > 0) {
      unawaited(service.clearActiveView(prevId));
    }
    _reportedActiveViewConvId = nextId;
    _activeViewHeartbeat?.cancel();
    _activeViewHeartbeat = null;
    if (nextId > 0) {
      unawaited(service.reportActiveView(nextId));
      _startActiveViewHeartbeat();
    }
  }

  void _startActiveViewHeartbeat() {
    _activeViewHeartbeat?.cancel();
    _activeViewHeartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      final id = _reportedActiveViewConvId;
      if (id <= 0 || !_userActivelyInChat || windowsTrayIsWindowInactive()) {
        _syncActiveViewReport();
        return;
      }
      unawaited(
        ConversationService(session: widget.session).reportActiveView(id),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首次从服务端拿到完整未读快照时，服务端结果可以校正上一次设备
    // 留下的系统角标（例如 PC 已读、APP 当时处于后台的情况）。
    _pendingBadgeZeroSync = true;
    unawaited(ConversationRealtimeHub.instance.of(widget.session).connect());
    NovaBackgroundCoordinator.instance.addListener(_onNovaCoordinatorUpdate);
    MeetingUploadCoordinator.instance.attach(widget.session);
    MeetingUploadCoordinator.instance.addListener(_onMeetingUploadUpdate);
    KbUploadCoordinator.instance.addListener(_onKbUploadUpdate);
    unawaited(MeetingUploadCoordinator.instance.resumePending());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        MeetingAbandonedRecovery.promptIfNeeded(
          context: context,
          session: widget.session,
        ),
      );
    });
    unawaited(_bootCommBadgeRealtime());
    unawaited(_refreshCommUnreadBadge());
    unawaited(_refreshWorkbenchBadge());
    setPushBadgeRefreshHandler(_requestCommBadgeRefreshFromServer);
    setPushNotificationClickHandler(_handleTpnsNotificationClick);
    unawaited(
      bindPushSession(
        userId: widget.session.userId,
        token: widget.session.token,
        apiBase: widget.session.apiBase,
      ),
    );
    registerPushLifecycleObserver();
    setWindowsTrayOnInactiveChanged(_onDesktopWindowInactiveChanged);
    windowsTrayWindowObscuredListenable().addListener(
      _onDesktopWindowObscuredChanged,
    );
    setWindowsTrayOnPeekOpen(_onWindowsTrayPeekOpen);
    windowsTraySetUserLabel((widget.session.displayName ?? '').trim());
  }

  void _onWindowsTrayPeekOpen(int conversationId) {
    if (!mounted) return;
    if (conversationId <= 0) return;
    unawaited(_openConversationFromTpns(conversationId));
  }

  void _onDesktopWindowInactiveChanged(bool inactive) {
    if (!mounted) return;
    if (inactive) {
      // 先冻住聊天滚动，避免 Windows 把 reverse 列表夹到 0 后误判贴底。
      ChatForegroundSync.notifyPaused();
      // 最小化/失焦/托盘：停止 autoMarkRead，避免后台把消息标成已读。
      if (_userActivelyInChat) {
        setState(() => _userActivelyInChat = false);
      } else {
        _userActivelyInChat = false;
      }
      _syncActiveViewReport();
      _scheduleCommBadgeRefresh();
      return;
    }
    // 先通知聊天页补拉最新消息，再恢复已读上报，避免缺消息却先标已读。
    // 窗口恢复时重新以服务端快照校正角标，覆盖 PC/APP 跨端已读。
    _pendingBadgeZeroSync = true;
    ChatForegroundSync.notifyResumed();
    // 恢复前台且仍停在会话页时，重新允许已读上报。
    if (_isOnActiveChatScreen() && !_userActivelyInChat) {
      setState(() => _userActivelyInChat = true);
    }
    _syncActiveViewReport();
    _scheduleCommBadgeRefresh();
  }

  void _onDesktopWindowObscuredChanged() {
    if (!mounted || windowsTrayIsWindowObscured()) return;
    // 隐藏/最小化期间跳过了 presence 轮询，窗口重新可见时立刻补一次。
    unawaited(
      ConversationRealtimeHub.instance
          .of(widget.session)
          .refreshOnlinePresence(),
    );
  }

  void _requestCommBadgeRefreshFromServer() {
    // 推送展示/恢复回调意味着设备刚有机会与服务端同步；允许本次
    // 成功返回 0 时清除可能由其他设备留下的旧角标。
    _pendingBadgeZeroSync = true;
    _scheduleCommBadgeRefresh();
  }

  void _handleTpnsNotificationClick(PushNotificationClick event) {
    final eventType = event.eventType.trim().toLowerCase();
    if (event.isDuneAnnouncement) {
      if (widget.session.isExternalUser) {
        _fallbackToConversationListFromTpns();
        return;
      }
      _openDuneAnnouncementFromTpns(
        tab: _announcementTabFromTpns(event),
        conversationId: event.conversationId,
      );
      return;
    }
    if (eventType != 'im' &&
        eventType != 'admin_notice' &&
        eventType != 'administrative_notice') {
      return;
    }
    final conversationId = event.conversationId;
    if (conversationId <= 0) {
      _fallbackToConversationListFromTpns();
      return;
    }
    if (!_tpnsOpeningConversationIds.add(conversationId)) return;
    unawaited(() async {
      var routed = false;
      try {
        routed = await _openConversationFromTpns(
          conversationId,
          noticeId: event.noticeId,
        );
      } catch (error, stackTrace) {
        debugPrint(
          '[Push] failed to open conversation $conversationId: $error',
        );
        debugPrint('$stackTrace');
      } finally {
        _tpnsOpeningConversationIds.remove(conversationId);
      }
      if (!routed) {
        // Keep the existing successful-route behavior unchanged.  When an
        // explicit IM conversation cannot be resolved, still remove all local
        // TPNS entries for that conversation before falling back to C1.
        await clearPushConversationNotifications(conversationId);
        if (mounted) {
          _fallbackToConversationListFromTpns();
        }
      }
    }());
  }

  void _fallbackToConversationListFromTpns() {
    if (!mounted) return;
    _markUserEnteredChat();
    widget.navigation.go('C1');
  }

  String _announcementTabFromTpns(PushNotificationClick event) {
    final tab = event.announcementTab.trim().toLowerCase();
    if (tab == 'broadcast' || tab == 'notice') return tab;
    final eventType = event.eventType.trim().toLowerCase();
    if (eventType == 'broadcast' || event.conversationId > 0) {
      return 'broadcast';
    }
    return 'notice';
  }

  void _openDuneAnnouncementFromTpns({String? tab, int conversationId = 0}) {
    if (!mounted) return;
    if (widget.session.isExternalUser) {
      _fallbackToConversationListFromTpns();
      return;
    }
    _markUserEnteredChat();
    setState(() {
      _messageCenterInitialTab = tab;
      _messageCenterMarkAllOnEnter = false;
    });
    widget.navigation.go('Z2');
    if (tab == 'notice') {
      _handleNotificationsRead();
    } else if (conversationId > 0) {
      _handleConversationRead(conversationId);
    }
    if (conversationId > 0) {
      unawaited(clearPushConversationNotifications(conversationId));
    }
  }

  Future<bool> _openConversationFromTpns(
    int conversationId, {
    int noticeId = 0,
  }) async {
    NativeConversation? conversation = _commBadgeConversations[conversationId];
    if (conversation == null) {
      final service = ConversationService(session: widget.session);
      try {
        conversation = await service.fetchConversation(conversationId);
      } finally {
        service.close();
      }
    }
    final resolvedConversation = conversation;
    if (!mounted ||
        resolvedConversation == null ||
        !resolvedConversation.isVisible) {
      return false;
    }

    var routed = false;
    if (resolvedConversation.isPrivate) {
      _openPrivateConversation(resolvedConversation);
      routed = true;
    } else if (resolvedConversation.isGroup ||
        resolvedConversation.isWorkgroupApproval) {
      _openGroupConversation(resolvedConversation);
      routed = true;
    } else if (resolvedConversation.isRobot) {
      _openRobotConversation(resolvedConversation);
      routed = true;
    } else if (resolvedConversation.isApprovalAssistant) {
      await _openApprovalAssistant(resolvedConversation);
      routed = mounted && widget.navigation.currentScreen == 'AA1';
    } else if (resolvedConversation.isTaskAssistant) {
      await _openTaskAssistant(resolvedConversation);
      routed = mounted && widget.navigation.currentScreen == 'TA1';
    } else if (resolvedConversation.isDriveAssistant) {
      await _openDriveAssistant(resolvedConversation);
      routed = mounted && widget.navigation.currentScreen == 'DA1';
    } else if (resolvedConversation.isXrxsAssistant) {
      await _openXrxsAssistant(resolvedConversation);
      routed = mounted && widget.navigation.currentScreen == 'XA1';
    } else if (resolvedConversation.isWeeklySummary) {
      await _openWeeklySummary(resolvedConversation);
      routed = mounted && widget.navigation.currentScreen == 'WS1';
    } else if (resolvedConversation.isReconciliationAssistant) {
      _openReconciliationAssistant(resolvedConversation);
      routed =
          mounted &&
          (widget.navigation.currentScreen == 'QJA' ||
              widget.navigation.currentScreen == 'RA1');
    } else if (resolvedConversation.isAdministrativeNotice) {
      _openAdministrativeNotice(resolvedConversation, noticeId: noticeId);
      routed = mounted && widget.navigation.currentScreen == 'AN1';
    } else if (resolvedConversation.isBroadcast) {
      if (widget.session.isExternalUser) {
        return false;
      }
      _openDuneAnnouncementFromTpns(
        tab: 'broadcast',
        conversationId: resolvedConversation.id,
      );
      routed = true;
    } else if (resolvedConversation.isAiAssistant) {
      if (widget.session.isExternalUser) {
        return false;
      }
      setState(() {
        _novaFocusConversationId = resolvedConversation.id;
        _novaFocusMessageId = null;
      });
      _markUserEnteredChat();
      widget.navigation.go('C4');
      routed = true;
    }

    if (!mounted || !routed) return false;
    _handleConversationRead(
      resolvedConversation.id,
      preserveUnread: resolvedConversation.isAdministrativeNotice,
    );
    await clearPushConversationNotifications(resolvedConversation.id);
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('[Badge] lifecycle=$state activelyInChat=$_userActivelyInChat');
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      ChatForegroundSync.notifyPaused();
      if (_userActivelyInChat && mounted) {
        print('[Badge] app backgrounded -> clear activelyInChat');
        setState(() => _userActivelyInChat = false);
      } else {
        _userActivelyInChat = false;
      }
      _syncActiveViewReport();
    } else if (state == AppLifecycleState.resumed) {
      // 与托盘 inactive→active 对齐：恢复时补拉当前会话最新消息。
      _pendingBadgeZeroSync = true;
      ChatForegroundSync.notifyResumed();
      _scheduleCommBadgeRefresh();
      if (_isOnActiveChatScreen() && !_userActivelyInChat) {
        setState(() => _userActivelyInChat = true);
      }
      _syncActiveViewReport();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    setWindowsTrayOnInactiveChanged(null);
    windowsTrayWindowObscuredListenable().removeListener(
      _onDesktopWindowObscuredChanged,
    );
    setWindowsTrayOnPeekOpen(null);
    setPushBadgeRefreshHandler(null);
    setPushNotificationClickHandler(null);
    _activeViewHeartbeat?.cancel();
    _activeViewHeartbeat = null;
    if (_reportedActiveViewConvId > 0) {
      unawaited(
        ConversationService(
          session: widget.session,
        ).clearActiveView(_reportedActiveViewConvId),
      );
      _reportedActiveViewConvId = 0;
    }
    _commBadgeRefreshDebounce?.cancel();
    _commBadgeRecorrectTimer?.cancel();
    _workbenchBadgeRefreshDebounce?.cancel();
    _commBadgeRtSub?.cancel();
    dismissDunesActionToast();
    NovaBackgroundCoordinator.instance.removeListener(_onNovaCoordinatorUpdate);
    MeetingUploadCoordinator.instance.removeListener(_onMeetingUploadUpdate);
    KbUploadCoordinator.instance.removeListener(_onKbUploadUpdate);
    _commUnread.dispose();
    _workbenchBadge.dispose();
    _workbenchRefresh.dispose();
    _conversationReadSignal.dispose();
    _notificationsReadSignal.dispose();
    _conversationMemberSettingsSignal.dispose();
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
      'ai_summary_updated',
    };
    if (!relevant.contains(event.type)) return;
    if (!_commBadgeDedup.consume(event)) return;

    // 智能总结终态：Centrifugo +（后台）TPNS；未读走 chat_summary.read_at，不再写 notification。
    if (event.type == 'ai_summary_updated') {
      if (widget.session.isExternalUser) return;
      final data = event.raw['data'];
      final map = data is Map ? data : event.raw;
      final status = (map['status'] ?? '').toString().toUpperCase();
      if (status == 'SUCCESS' || status == 'FAILED') {
        final onSummary = const <String>{
          'AS1',
          'AS2',
          'AS3',
        }.contains(widget.navigation.currentScreen);
        if (onSummary) {
          final screen = widget.navigation.currentScreen;
          if (screen == 'AS3') {
            final summaryId = (map['id'] as num?)?.toInt() ?? 0;
            if (summaryId > 0 && summaryId == (_selectedAiSummaryId ?? 0)) {
              unawaited(
                AiSummaryService(
                  session: widget.session,
                ).markRead(summaryId).whenComplete(_scheduleCommBadgeRefresh),
              );
              return;
            }
          }
          _scheduleCommBadgeRefresh();
          return;
        }
        notifyPushRealtimeMessage(
          title: kAiSummaryPushTitle,
          body: aiSummaryPushBody(failed: status == 'FAILED'),
        );
        windowsTrayNotifyIncomingMessage();
      }
      _scheduleCommBadgeRefresh();
      return;
    }

    if (event.type == 'read') {
      final userId = (event.raw['userId'] as num?)?.toInt() ?? 0;
      final convId = event.conversationId ?? 0;
      if (userId == widget.session.userId) {
        // 同账号在其他设备已读时，也允许将本机的系统角标清零。
        _pendingBadgeZeroSync = true;
        _commUnread.clearMutedMention(convId);
      }
      _scheduleCommBadgeRefresh();
      return;
    }

    if (event.type == 'conversation_updated') {
      final totalUnread = (event.raw['totalUnread'] as num?)?.toInt();
      if (totalUnread != null) {
        // 正在看某会话时，totalUnread 可能仍含本会话未读；走 REST 汇总
        //（treatAsRead）避免 Tab 小红点误亮。
        final viewingId = _activeViewingConversationId() ?? 0;
        if (viewingId > 0) {
          _scheduleCommBadgeRefresh();
        } else {
          _applyRealtimeUnreadTotal(totalUnread);
        }
        return;
      }
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

      if (mentionHit && isMuted && convId > 0) {
        _commUnread.recordMutedMention(convId);
      }
      if (!isMuted) {
        _notifyAndroidPushForEvent(event);
        windowsTrayNotifyIncomingMessage();
      }
      _scheduleCommBadgeRefresh();
      return;
    }

    if (event.type == 'notification') {
      _notifyAndroidPushForEvent(event);
      windowsTrayNotifyIncomingMessage();
    }

    _scheduleCommBadgeRefresh();
  }

  void _notifyAndroidPushForEvent(ConversationRealtimeEvent event) {
    final convId = event.conversationId ?? 0;
    var title = '沙丘';
    var body = '您有新消息';
    if (event.type == 'notification') {
      title = (event.raw['title'] ?? '系统通知').toString();
      body = (event.raw['body'] ?? event.raw['content'] ?? '您有新的系统通知')
          .toString();
    } else {
      final msg = event.raw['message'];
      if (msg is Map) {
        final kind = (msg['kind'] ?? '').toString();
        final rawBody =
            (msg['bodyText'] ?? msg['content'] ?? msg['text'] ?? body)
                .toString();
        final preview = compactMessagePushPreview(kind: kind, body: rawBody);
        final sender = msg['sender'];
        var senderName = '';
        if (sender is Map) {
          senderName = (sender['displayName'] ?? sender['name'] ?? '')
              .toString()
              .trim();
        }

        final cachedConversation = _commBadgeConversations[convId];
        final rawTitle =
            (event.raw['conversationTitle'] ??
                    event.raw['conversationName'] ??
                    msg['conversationTitle'] ??
                    msg['conversationName'] ??
                    '')
                .toString()
                .trim();
        final conversationTitle = rawTitle.isNotEmpty
            ? rawTitle
            : (cachedConversation?.title ?? '').trim();
        final isPrivate =
            cachedConversation?.isPrivate == true ||
            (msg['conversationKind'] ?? event.raw['conversationKind'] ?? '')
                    .toString()
                    .trim()
                    .toUpperCase() ==
                'PRIVATE';
        if (!isPrivate && conversationTitle.isNotEmpty) {
          // 群聊/工作群/广播：标题显示会话名称，发送人放到正文前缀。
          title = conversationTitle;
          body = senderName.isEmpty ? preview : '$senderName：$preview';
        } else {
          // 私聊保持微信式提示：标题显示对方姓名。
          title = senderName.isEmpty ? '沙丘' : senderName;
          body = preview;
        }

        final conversationKind =
            (msg['conversationKind'] ??
                    event.raw['conversationKind'] ??
                    cachedConversation?.kind ??
                    '')
                .toString()
                .trim()
                .toUpperCase();
        final isTaskAssistant =
            cachedConversation?.isTaskAssistant == true ||
            conversationKind == 'TASK_ASSISTANT' ||
            kind.toUpperCase() == 'TASK_ASSISTANT';
        if (isTaskAssistant) {
          title = '任务助手';
          body = _taskAssistantPushBody(msg, preview);
        }
      }
    }
    final desktopFocused = isDesktopCommOnly && !windowsTrayIsWindowInactive();
    final isTaskNotice = title == '任务助手';
    if (desktopFocused && isTaskNotice && mounted && convId > 0) {
      final conv =
          _commBadgeConversations[convId] ??
          NativeConversation(
            id: convId,
            kind: 'TASK_ASSISTANT',
            title: '任务助手',
            unreadCount: 0,
            preview: body,
            updatedAt: null,
          );
      showInAppMessageBanner(
        context: context,
        conversationId: convId,
        title: title,
        body: body,
        conversation: conv,
        session: widget.session,
        onTap: () => unawaited(_openTaskAssistant(conv)),
      );
      return;
    }
    notifyPushRealtimeMessage(title: title, body: body, conversationId: convId);
  }

  Map<String, dynamic>? _mapPayload(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
  }

  String _taskAssistantPushBody(Map msg, String fallback) {
    final payload = _mapPayload(msg['payload']);
    final type = (payload?['type'] ?? '').toString();
    if (type == 'meetingTaskSuggestions') {
      final meeting = (payload?['meetingTitle'] ?? '').toString().trim();
      final count = (payload?['suggestions'] as List?)?.length ?? 0;
      if (meeting.isNotEmpty && count > 0) {
        return '「$meeting」有 $count 条待创建任务';
      }
    }
    return fallback.trim().isEmpty ? '你有新的任务通知' : fallback;
  }

  void _scheduleCommBadgeRefresh() {
    final backoffUntil = _commBadgeRefreshBackoffUntil;
    if (backoffUntil != null && DateTime.now().isBefore(backoffUntil)) {
      final delay = backoffUntil.difference(DateTime.now());
      _commBadgeRefreshDebounce?.cancel();
      _commBadgeRefreshDebounce = Timer(delay, () {
        if (!mounted) return;
        unawaited(_refreshCommUnreadBadge());
      });
      return;
    }
    _commBadgeRefreshDebounce?.cancel();
    _commBadgeRefreshDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      unawaited(_refreshCommUnreadBadge());
    });
    _commBadgeRecorrectTimer?.cancel();
    _commBadgeRecorrectTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      unawaited(_refreshCommUnreadBadge());
    });
  }

  void _handleConversationRead(
    int conversationId, {
    bool preserveUnread = false,
  }) {
    if (conversationId > 0) {
      _pendingBadgeZeroSync = true;
      if (!preserveUnread) {
        _commUnread.clearMutedMention(conversationId);
        _conversationReadSignal.notifyRead(conversationId);
      }
      // 按 peer 打开私聊时 Host 可能尚无 conversationId；已读回调补一次 active-view。
      if (_userActivelyInChat &&
          !windowsTrayIsWindowInactive() &&
          (_peekViewingConversationId() ?? 0) <= 0 &&
          _reportedActiveViewConvId != conversationId) {
        final prev = _reportedActiveViewConvId;
        final service = ConversationService(session: widget.session);
        if (prev > 0) unawaited(service.clearActiveView(prev));
        _reportedActiveViewConvId = conversationId;
        unawaited(service.reportActiveView(conversationId));
        _startActiveViewHeartbeat();
      } else {
        _syncActiveViewReport();
      }
    }
    print(
      '[Badge] handleConversationRead conv=$conversationId pendingZero=$_pendingBadgeZeroSync',
    );
    unawaited(_refreshCommUnreadBadge());
  }

  void _handleNotificationsRead() {
    _pendingBadgeZeroSync = true;
    _notificationsReadSignal.notifyRead();
    print('[Badge] handleNotificationsRead pendingZero=true');
    unawaited(_refreshCommUnreadBadge());
  }

  /// 服务端在同账号其他端完成已读后推送精确总未读，立即同步 Tab、
  /// 桌面托盘和移动端应用图标，避免等待 REST 刷新而残留旧角标。
  void _applyRealtimeUnreadTotal(int totalUnread) {
    final total = totalUnread < 0 ? 0 : totalUnread;
    _commUnread.update(total);
    windowsTrayUpdateUnread(total);
    if (total == 0) _pendingBadgeZeroSync = false;
    syncPushBadgeCount(total);
  }

  void _scheduleWorkbenchBadgeRefresh({bool rejected = false}) {
    final backoffUntil = _workbenchBadgeRefreshBackoffUntil;
    if (backoffUntil != null && DateTime.now().isBefore(backoffUntil)) {
      final delay = backoffUntil.difference(DateTime.now());
      _workbenchBadgeRefreshDebounce?.cancel();
      _workbenchBadgeRefreshDebounce = Timer(delay, () {
        if (!mounted) return;
        unawaited(_refreshWorkbenchBadge(notifyRejected: rejected));
      });
      return;
    }
    _workbenchBadgeRefreshDebounce?.cancel();
    _workbenchBadgeRefreshDebounce = Timer(
      const Duration(milliseconds: 350),
      () {
        if (!mounted) return;
        unawaited(_refreshWorkbenchBadge(notifyRejected: rejected));
      },
    );
  }

  Future<void> _refreshWorkbenchBadge({bool notifyRejected = false}) async {
    if (_workbenchBadgeRefreshInFlight) {
      _workbenchBadgeRefreshQueued = true;
      return;
    }
    final backoffUntil = _workbenchBadgeRefreshBackoffUntil;
    if (backoffUntil != null && DateTime.now().isBefore(backoffUntil)) {
      return;
    }
    _workbenchBadgeRefreshInFlight = true;
    final httpClient = http.Client();
    try {
      final resp = await dunesHttpGet(
        widget.session,
        '/workbench/my-stats',
        client: httpClient,
      ).timeout(const Duration(seconds: 8));
      _workbenchBadgeRefreshBackoffUntil = null;
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
        final body = delta == 1 ? '你有新的审批待办，请及时处理' : '您有 $delta 条新的待审批，请及时处理';
        showDunesToast(context, '您有 $delta 条新的待审批，请及时处理');
        // 与 APP TPNS（title=审批待办）对齐：桌面本地系统通知。
        notifyPushRealtimeMessage(title: '审批待办', body: body);
        windowsTrayNotifyIncomingMessage();
      } else if (pendingInitiateDelta > 0) {
        final body = '有 $pendingInitiateDelta 条同事推送的提案待您确认发起';
        showDunesActionToast(
          context,
          body,
          actionLabel: '去查看',
          icon: Icons.assignment_ind_outlined,
          onTap: () {
            if (!mounted) return;
            _goB14(filter: 'PENDING_INITIATE');
          },
        );
        notifyPushRealtimeMessage(title: '待确认发起', body: body);
        windowsTrayNotifyIncomingMessage();
      } else if (notifyRejected) {
        const body = '您有 1 条审批被驳回，请及时查看';
        showDunesActionToast(
          context,
          body,
          actionLabel: '去查看',
          icon: Icons.warning_amber_rounded,
          onTap: () {
            if (!mounted) return;
            _goB14();
          },
        );
        notifyPushRealtimeMessage(title: '审批驳回', body: body);
        windowsTrayNotifyIncomingMessage();
      }
    } catch (_) {
      // 弱网超时后退避，避免堆积无超时 HTTP 拖死 UI。
      _workbenchBadgeRefreshBackoffUntil = DateTime.now().add(
        const Duration(seconds: 15),
      );
    } finally {
      try {
        httpClient.close();
      } catch (_) {}
      _workbenchBadgeRefreshInFlight = false;
      if (_workbenchBadgeRefreshQueued && mounted) {
        _workbenchBadgeRefreshQueued = false;
        final until = _workbenchBadgeRefreshBackoffUntil;
        if (until == null || !DateTime.now().isBefore(until)) {
          unawaited(_refreshWorkbenchBadge(notifyRejected: notifyRejected));
        }
      }
    }
  }

  bool _isPeerRealtimeMessage(ConversationRealtimeEvent event) {
    final msg = event.raw['message'];
    if (msg is! Map) return false;
    final kind = (msg['kind'] ?? '').toString().toUpperCase();
    // 机器人回复、对账/审批等助手消息无真人 sender，仍视为对方消息（角标 / 托盘）。
    if (kind == 'ROBOT_REPLY' ||
        ConversationInboxRealtime.isIncomingAssistantMessageKind(kind)) {
      return true;
    }
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

  /// 当前是否停在可自动 mark-read 的会话页（含审批助手 / 任务助手）。
  bool _isOnActiveChatScreen([String? screen]) {
    final s = screen ?? widget.navigation.currentScreen;
    if (s == 'C5' ||
        s == 'C2' ||
        s == 'CR' ||
        s == 'C10' ||
        s == 'AA1' ||
        s == 'TA1' ||
        s == 'DA1' ||
        s == 'XA1' ||
        s == 'WS1' ||
        s == 'RA1' ||
        s == 'AN1') {
      return true;
    }
    return (_dualPaneSelectedConversationId ?? 0) > 0;
  }

  bool _isViewingConversation(int convId) {
    if (convId <= 0) return false;
    // 桌面窗口最小化、失焦或隐藏到托盘后，不能继续视为用户正在看此会话。
    // 否则新消息会在此提前返回，既没有系统通知也不会触发闪烁提醒。
    if (windowsTrayIsWindowInactive()) return false;
    // 双栏：右侧正在展示该会话时，Tab 角标不再累加。
    if (_dualPaneSelectedConversationId == convId) return true;
    final screen = widget.navigation.currentScreen;
    if (screen == 'C5' && _selectedPrivate?.id == convId) return true;
    if (screen == 'C2' && _selectedGroup?.id == convId) return true;
    if (screen == 'CR' && _selectedRobot?.id == convId) return true;
    if (screen == 'C10' && _selectedBroadcast?.id == convId) return true;
    if (screen == 'AA1' && _selectedApprovalAssistant?.id == convId) {
      return true;
    }
    if (screen == 'TA1' && _selectedTaskAssistant?.id == convId) return true;
    if (screen == 'DA1' && _selectedDriveAssistant?.id == convId) return true;
    if (screen == 'XA1' && _selectedXrxsAssistant?.id == convId) return true;
    if (screen == 'WS1' && _selectedWeeklySummary?.id == convId) return true;
    if (screen == 'RA1' && _selectedReconciliation?.id == convId) return true;
    if (screen == 'AN1' && _selectedAdministrativeNotice?.id == convId) {
      return true;
    }
    return false;
  }

  /// 当前正在查看的会话（双栏选中 / 窄屏聊天页），角标汇总时应视为已读。
  int? _activeViewingConversationId() {
    // 窗口后台时不能把当前会话当已读，否则未读角标/托盘提示会被清掉。
    if (windowsTrayIsWindowInactive()) return null;
    final dualId = _dualPaneSelectedConversationId;
    if (dualId != null && dualId > 0) return dualId;
    final screen = widget.navigation.currentScreen;
    if (screen == 'C5') {
      final id = _selectedPrivate?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'C2') {
      final id = _selectedGroup?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'CR') {
      final id = _selectedRobot?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'C10') {
      final id = _selectedBroadcast?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'AA1') {
      final id = _selectedApprovalAssistant?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'TA1') {
      final id = _selectedTaskAssistant?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'DA1') {
      final id = _selectedDriveAssistant?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'XA1') {
      final id = _selectedXrxsAssistant?.id ?? 0;
      return id > 0 ? id : null;
    }
    if (screen == 'WS1') {
      final id = _selectedWeeklySummary?.id ?? 0;
      return id > 0 ? id : null;
    }
    return null;
  }

  void _onNovaCoordinatorUpdate() {
    final shouldBump = NovaBackgroundCoordinator.instance
        .takePendingCommBadgeBump();
    final notOnC4 = widget.navigation.currentScreen != 'C4';
    unawaited(_handleNovaCoordinatorBadge(shouldBump: shouldBump && notOnC4));
  }

  void _onMeetingUploadUpdate() {
    if (!mounted) return;
    if (widget.navigation.currentScreen == 'B2') {
      setState(() {});
    }
  }

  void _onKbUploadUpdate() {
    if (!mounted) return;
    if (widget.navigation.currentScreen == 'K1') return;
    final toast = KbUploadCoordinator.instance.takeToast();
    if (toast == null) return;
    showDunesToast(
      context,
      toast.message,
      kind: toast.error || dunesToastLooksLikeError(toast.message)
          ? DunesToastKind.error
          : DunesToastKind.normal,
    );
  }

  Future<void> _handleNovaCoordinatorBadge({required bool shouldBump}) async {
    await _refreshCommUnreadBadge();
    if (!mounted || !shouldBump || widget.navigation.currentScreen == 'C4') {
      return;
    }
    showDunesToast(context, 'NOVA已回复，可返回查看');
  }

  Future<void> _refreshCommUnreadBadge() async {
    if (_commBadgeRefreshInFlight) {
      _commBadgeRefreshQueued = true;
      return;
    }
    final backoffUntil = _commBadgeRefreshBackoffUntil;
    if (backoffUntil != null && DateTime.now().isBefore(backoffUntil)) {
      return;
    }
    _commBadgeRefreshInFlight = true;
    // 共用 Client：超时后 close 可中止挂起连接，避免弱网堆积拖死 UI。
    final httpClient = http.Client();
    final convService = ConversationService(
      session: widget.session,
      client: httpClient,
    );
    final notifService = NotificationService(
      session: widget.session,
      client: httpClient,
    );
    final aiSummaryService = AiSummaryService(
      session: widget.session,
      client: httpClient,
    );
    try {
      final futures = <Future<Object?>>[
        convService.fetchConversations(),
        notifService.fetchSummary(),
        InboxHiddenStorage.load(),
        convService.fetchTotalUnread(),
      ];
      if (!widget.session.isExternalUser) {
        futures.add(aiSummaryService.fetchUnreadCount());
      }
      final results = await Future.wait<Object?>(
        futures,
      ).timeout(const Duration(seconds: 10));
      _commBadgeRefreshBackoffUntil = null;
      final allRows = results[0] as List<NativeConversation>;
      _commBadgeConversations
        ..clear()
        ..addEntries(
          allRows.where((c) => c.id > 0).map((c) => MapEntry(c.id, c)),
        );
      final notif = results[1] as NativeNotificationSummary;
      final hidden = results[2] as Map<String, InboxHiddenEntry>;
      final apiTotal = results[3] as int?;
      final aiSummaryUnread =
          !widget.session.isExternalUser && results.length > 4
          ? (results[4] as int? ?? 0)
          : 0;
      final onSummaryScreen = const <String>{
        'AS1',
        'AS2',
        'AS3',
      }.contains(widget.navigation.currentScreen);
      final effectiveAiUnread = onSummaryScreen || widget.session.isExternalUser
          ? 0
          : aiSummaryUnread;
      final rows = allRows
          .where(
            (c) =>
                c.isListedInInbox &&
                !isConversationHidden(hidden, c.id) &&
                !(widget.session.isExternalUser &&
                    (c.isBroadcast || c.isAiAssistant)),
          )
          .toList(growable: false);
      _mutedConvIds
        ..clear()
        ..addEntries(
          rows
              .where(CommUnreadNotifier.isMutedGroup)
              .map((c) => MapEntry(c.id, true)),
        );
      if (mounted) {
        final viewingId = _activeViewingConversationId() ?? 0;
        final treatAsRead = viewingId > 0 ? <int>{viewingId} : const <int>{};
        var viewingUnread = 0;
        if (viewingId > 0) {
          for (final c in rows) {
            if (c.id == viewingId) {
              viewingUnread = _commUnread.effectiveUnreadCount(c);
              break;
            }
          }
        }
        final summedTotal = _commUnread.sumConversationUnread(
          rows: rows,
          notifUnread: widget.session.isExternalUser ? 0 : notif.unreadCount,
          aiSummaryUnread: effectiveAiUnread,
          treatAsReadIds: treatAsRead,
        );
        // 取服务端总数与本地汇总的较大值：服务端 /comm/unread-total 会漏算
        // 广播等场景（返回 0），若盲信它的 0 会在仍有未读时误清角标。
        // 当前正在查看的会话已 mark-read / 不计入角标，需从 apiTotal 扣掉。
        final apiRaw = apiTotal ?? 0;
        final apiVal = apiRaw > viewingUnread ? apiRaw - viewingUnread : 0;
        final serverTotal = widget.session.isExternalUser
            ? summedTotal
            : (apiVal > summedTotal ? apiVal : summedTotal);
        final localBadge = await readPushBadgeCount();
        final unreadRows = rows
            .where((c) => c.unreadCount > 0 && c.id != viewingId)
            .map((c) => 'id=${c.id} kind=${c.kind} unread=${c.unreadCount}')
            .join('; ');
        print(
          '[Badge] refresh apiTotal=$apiTotal viewing=$viewingId viewingUnread=$viewingUnread '
          'summed=$summedTotal notif=${notif.unreadCount} '
          'next=$serverTotal local=$localBadge pendingZero=$_pendingBadgeZeroSync '
          'unreadRows=[$unreadRows]',
        );
        _commUnread.update(serverTotal);
        windowsTrayUpdateUnread(serverTotal);
        windowsTrayPushUnreadFromConversations(
          rows: rows,
          commUnread: _commUnread,
          viewingId: viewingId,
          session: widget.session,
          avatarService: convService,
        );
        if (serverTotal == 0) {
          if (!_pendingBadgeZeroSync) {
            print('[Badge] skip sync 0 (no fresh snapshot/read ack)');
            return;
          }
          _pendingBadgeZeroSync = false;
          print('[Badge] sync 0 after fresh snapshot/read ack');
        }
        syncPushBadgeCount(serverTotal);
      }
    } catch (e, st) {
      // 弱网下无超时会堆积连接拖死 UI；失败后短暂退避。
      _commBadgeRefreshBackoffUntil = DateTime.now().add(
        const Duration(seconds: 12),
      );
      print('[Badge] refresh failed: $e\n$st');
    } finally {
      try {
        httpClient.close();
      } catch (_) {}
      _commBadgeRefreshInFlight = false;
      if (_commBadgeRefreshQueued && mounted) {
        _commBadgeRefreshQueued = false;
        // 退避窗口内不要立刻连环重试。
        final until = _commBadgeRefreshBackoffUntil;
        if (until == null || !DateTime.now().isBefore(until)) {
          unawaited(_refreshCommUnreadBadge());
        }
      }
    }
  }

  /// 宽屏双栏：在会话/助手之间切换时替换栈顶，避免历史栈堆积。
  void _goChatScreen(String screenId) {
    final current = widget.navigation.currentScreen;
    if (current == 'C2' ||
        current == 'C5' ||
        current == 'CR' ||
        current == 'AA1' ||
        current == 'TA1' ||
        current == 'DA1' ||
        current == 'XA1' ||
        current == 'WS1' ||
        current == 'RA1' ||
        current == 'AN1') {
      widget.navigation.replaceTop(screenId);
    } else {
      widget.navigation.go(screenId);
    }
  }

  void _openPrivateConversation(NativeConversation conv) {
    _approvalAssistantOpenGen++;
    setState(() {
      _selectedPrivate = conv;
      _selectedPrivatePeerUserId = conv.peerUserId;
      _selectedGroup = null;
      _selectedRobot = null;
      _selectedApprovalAssistant = null;
      _selectedTaskAssistant = null;
      _selectedDriveAssistant = null;
      _selectedXrxsAssistant = null;
      _selectedWeeklySummary = null;
      _selectedReconciliation = null;
      _selectedAdministrativeNotice = null;
      _administrativeNoticeTargetId = null;
      _focusMessageId = null;
      _focusMessageHint = null;
    });
    _markUserEnteredChat();
    if (conv.id > 0) {
      _conversationReadSignal.notifyRead(conv.id);
    }
    _goChatScreen('C5');
    DesktopComposerFocus.request();
  }

  void _openRobotConversation(NativeConversation conv) {
    _approvalAssistantOpenGen++;
    setState(() {
      _selectedRobot = conv;
      _selectedPrivate = null;
      _selectedPrivatePeerUserId = null;
      _selectedGroup = null;
      _selectedApprovalAssistant = null;
      _selectedTaskAssistant = null;
      _selectedDriveAssistant = null;
      _selectedXrxsAssistant = null;
      _selectedWeeklySummary = null;
      _selectedReconciliation = null;
      _selectedAdministrativeNotice = null;
      _administrativeNoticeTargetId = null;
      _focusMessageId = null;
      _focusMessageHint = null;
    });
    _markUserEnteredChat();
    if (conv.id > 0) {
      _conversationReadSignal.notifyRead(conv.id);
    }
    _goChatScreen('CR');
  }

  /// NOVA 名片：可会话 → ensure 后进聊天；仅推送 → Toast，不进对话。
  Future<void> _openRobotFromCatalog(RobotRole role) async {
    if (!role.canChat) {
      if (!mounted) return;
      showDunesToast(context, '该机器人仅推送通知，不支持对话');
      return;
    }
    try {
      final conv = await ConversationService(
        session: widget.session,
      ).ensureRobotSession(role.id);
      if (!mounted) return;
      _openRobotConversation(conv);
    } catch (e) {
      if (!mounted) return;
      final msg = friendlyErrorText(e);
      showDunesToast(
        context,
        msg.contains('不支持') ? '该机器人仅推送，不支持回复' : msg,
        kind: DunesToastKind.error,
      );
    }
  }

  void _openRobotConsultListFromChat() {
    final key =
        (_selectedRobot?.robotKey ??
                _selectedRobot?.businessType ??
                'r_lighthouse')
            .trim();
    setState(() {
      _qjrRobotKey = key.isEmpty ? 'r_lighthouse' : key;
      _qjrOpenedFromChat = true;
    });
    // 离开会话页时立刻重算 active-view，避免仍登记「正在看机器人」导致推送被吞。
    _markUserLeftChat();
    widget.navigation.go('QJR');
  }

  void _openGroupConversation(NativeConversation conv) {
    _approvalAssistantOpenGen++;
    setState(() {
      _selectedGroup = conv;
      _selectedPrivate = null;
      _selectedPrivatePeerUserId = null;
      _selectedRobot = null;
      _selectedApprovalAssistant = null;
      _selectedTaskAssistant = null;
      _selectedDriveAssistant = null;
      _selectedXrxsAssistant = null;
      _selectedWeeklySummary = null;
      _selectedReconciliation = null;
      _selectedAdministrativeNotice = null;
      _administrativeNoticeTargetId = null;
      _focusMessageId = null;
      _focusMessageHint = null;
    });
    _markUserEnteredChat();
    if (conv.id > 0) {
      _conversationReadSignal.notifyRead(conv.id);
    }
    _goChatScreen('C2');
    DesktopComposerFocus.request();
  }

  void _openPrivateByPeerId(int peerUserId) {
    _approvalAssistantOpenGen++;
    setState(() {
      _selectedPrivate = null;
      _selectedPrivatePeerUserId = peerUserId;
      _selectedGroup = null;
      // 与 _openPrivateConversation 对齐：清掉机器人/助手，否则双栏仍显示 AI 咨询等旧槽位。
      _selectedRobot = null;
      _selectedApprovalAssistant = null;
      _selectedTaskAssistant = null;
      _selectedDriveAssistant = null;
      _selectedXrxsAssistant = null;
      _selectedWeeklySummary = null;
      _selectedReconciliation = null;
      _selectedAdministrativeNotice = null;
      _administrativeNoticeTargetId = null;
      _focusMessageId = null;
      _focusMessageHint = null;
    });
    _markUserEnteredChat();
    _goChatScreen('C5');
    DesktopComposerFocus.request();
  }

  void _openContactProfile(int userId, String displayName) {
    if (userId <= 0) return;
    final current = widget.navigation.currentScreen;
    // 仅从会话（含双栏内搜索/媒体/群资料）打开时嵌在右侧会话栏；其它入口整页展示。
    // PC 宽屏：只要右侧已有私聊/群聊上下文且不是通讯录入口，名片只占会话框，不撑满整页。
    String? returnScreen;
    final hasPrivate =
        _selectedPrivate != null || _selectedPrivatePeerUserId != null;
    final hasGroup = _selectedGroup != null;
    final fromContacts = current == 'C3';

    if (current == 'C5') {
      returnScreen = 'C5';
    } else if (current == 'C2' || current == 'C6') {
      returnScreen = current;
    } else if (current == 'C12' || current == 'C13') {
      if (hasGroup) {
        returnScreen = 'C2';
      } else if (hasPrivate) {
        returnScreen = 'C5';
      }
    } else if (isDesktopCommOnly && !fromContacts) {
      if (hasPrivate) {
        returnScreen = 'C5';
      } else if (hasGroup) {
        returnScreen = 'C2';
      }
    }

    setState(() {
      _selectedContact = NativeContact(
        userId: userId,
        displayName: displayName,
      );
      _profileReturnScreen = returnScreen;
    });
    widget.navigation.go('C9');
  }

  void _leaveChatToInbox({required bool clearSelection}) {
    _approvalAssistantOpenGen++;
    setState(() {
      _focusMessageId = null;
      _focusMessageHint = null;
      if (clearSelection) {
        _selectedPrivate = null;
        _selectedPrivatePeerUserId = null;
        _selectedGroup = null;
        _selectedRobot = null;
        _selectedApprovalAssistant = null;
        _selectedTaskAssistant = null;
        _selectedDriveAssistant = null;
        _selectedXrxsAssistant = null;
        _selectedWeeklySummary = null;
        _selectedReconciliation = null;
        _selectedAdministrativeNotice = null;
        _administrativeNoticeTargetId = null;
      }
    });
    _markUserLeftChat();
    widget.navigation.popTo('C1');
  }

  void _openAiSummaryCreate({int? conversationId}) {
    if (widget.session.isExternalUser) return;
    setState(() {
      _aiSummaryPrefillConversationIds =
          conversationId != null && conversationId > 0
          ? <int>[conversationId]
          : const <int>[];
    });
    widget.navigation.go('AS2');
  }

  ValueChanged<int>? get _onOpenAiSummaryFromChat {
    if (widget.session.isExternalUser) return null;
    return (convId) => _openAiSummaryCreate(conversationId: convId);
  }

  void _clearChatFocusMessage() {
    if (_focusMessageId == null && _focusMessageHint == null) return;
    setState(() {
      _focusMessageId = null;
      _focusMessageHint = null;
    });
  }

  int? get _dualPaneSelectedConversationId {
    final chatScreen = _dualPaneChatScreen;
    if (chatScreen == 'C12' && _searchConversationId > 0) {
      return _searchConversationId;
    }
    if (chatScreen == 'C13' && _mediaConversationId > 0) {
      return _mediaConversationId;
    }
    if (chatScreen == 'C6') return _selectedGroup?.id;
    if (chatScreen == 'C9') {
      if (_profileReturnScreen == 'C5') return _selectedPrivate?.id;
      if (_profileReturnScreen == 'C2' || _profileReturnScreen == 'C6') {
        return _selectedGroup?.id;
      }
    }
    if (chatScreen == 'C5') return _selectedPrivate?.id;
    if (chatScreen == 'C2') return _selectedGroup?.id;
    if (chatScreen == 'CR') return _selectedRobot?.id;
    if (chatScreen == 'AA1' || chatScreen == 'AA2' || chatScreen == 'AA3') {
      return _selectedApprovalAssistant?.id;
    }
    if (chatScreen == 'TA1') {
      return _selectedTaskAssistant?.id;
    }
    if (chatScreen == 'DA1') {
      return _selectedDriveAssistant?.id;
    }
    if (chatScreen == 'XA1') {
      return _selectedXrxsAssistant?.id;
    }
    if (chatScreen == 'WS1') {
      return _selectedWeeklySummary?.id;
    }
    if (chatScreen == 'RA1') {
      return _selectedReconciliation?.id;
    }
    if (chatScreen == 'AN1') {
      return _selectedAdministrativeNotice?.id;
    }
    return null;
  }

  /// 从「我的」回到桌面端通讯时，保留原来打开的会话，而不是重置右侧聊天栏。
  String get _dualPaneChatScreen {
    final screen = widget.navigation.currentScreen;
    // 历史 / 媒体 / 群资料 / 会话内名片 / 智能总结：嵌在右侧会话栏，不撑满整页。
    if (screen == 'C12' || screen == 'C13') return screen;
    if (screen == 'AS1' || screen == 'AS2' || screen == 'AS3') return screen;
    if (screen == 'AA1' || screen == 'AA2' || screen == 'AA3') return screen;
    if (screen == 'TA1') return screen;
    if (screen == 'DA1') return screen;
    if (screen == 'XA1') return screen;
    if (screen == 'WS1') return screen;
    if (screen == 'AN1') return screen;
    if (screen == 'RA1') return screen;
    if (screen == 'C6') return 'C6';
    if (screen == 'C9' && _profileEmbedsInDualPane) return 'C9';
    if (screen == 'C2' || screen == 'C5' || screen == 'CR') return screen;
    if (_selectedPrivate != null || _selectedPrivatePeerUserId != null) {
      return 'C5';
    }
    if (_selectedGroup != null) return 'C2';
    if (_selectedRobot != null) return 'CR';
    if (_selectedApprovalAssistant != null) return 'AA1';
    if (_selectedTaskAssistant != null) return 'TA1';
    if (_selectedDriveAssistant != null) return 'DA1';
    if (_selectedXrxsAssistant != null) return 'XA1';
    if (_selectedWeeklySummary != null) return 'WS1';
    if (_selectedReconciliation != null) return 'RA1';
    if (_selectedAdministrativeNotice != null) return 'AN1';
    return 'C1';
  }

  bool get _profileEmbedsInDualPane =>
      _profileReturnScreen == 'C2' ||
      _profileReturnScreen == 'C5' ||
      _profileReturnScreen == 'C6';

  /// 双栏右侧叠在会话上的子页（群资料/名片/搜索/媒体/智能总结）；有叠层时底层会话保持挂载不销毁。
  String? get _dualPaneOverlayScreen {
    final screen = widget.navigation.currentScreen;
    if (screen == 'C6') return 'C6';
    if (screen == 'C12' || screen == 'C13') return screen;
    if (screen == 'AS1' || screen == 'AS2' || screen == 'AS3') return screen;
    if (screen == 'AA2' || screen == 'AA3') return screen;
    if (screen == 'C9' && _profileEmbedsInDualPane) return 'C9';
    return null;
  }

  bool _isDualPaneChatRoute(String screen) {
    if (screen == 'C9') return _profileEmbedsInDualPane;
    return screen == 'C1' ||
        screen == 'C2' ||
        screen == 'C5' ||
        screen == 'C6' ||
        screen == 'CR' ||
        screen == 'C12' ||
        screen == 'C13' ||
        screen == 'AS1' ||
        screen == 'AS2' ||
        screen == 'AS3' ||
        screen == 'AA1' ||
        screen == 'AA2' ||
        screen == 'AA3' ||
        screen == 'RA1' ||
        screen == 'TA1' ||
        screen == 'DA1' ||
        screen == 'XA1' ||
        screen == 'WS1' ||
        screen == 'AN1';
  }

  void _onPrivateChatSettingsChanged({
    required int conversationId,
    bool? muted,
    bool? pinned,
  }) {
    if (conversationId <= 0) return;
    if (muted != null) {
      if (muted) {
        _mutedConvIds[conversationId] = true;
      } else {
        _mutedConvIds.remove(conversationId);
      }
    }
    // 同步当前选中会话的本地副本，避免侧栏/标题仍显示旧状态。
    NativeConversation patch(NativeConversation c) {
      return ConversationInboxRealtime.copyConversation(
        c,
        muted: muted,
        pinned: pinned,
      );
    }

    if (_selectedGroup?.id == conversationId) {
      _selectedGroup = patch(_selectedGroup!);
    }
    if (_selectedPrivate?.id == conversationId) {
      _selectedPrivate = patch(_selectedPrivate!);
    }
    _conversationMemberSettingsSignal.notifySettings(
      conversationId: conversationId,
      muted: muted,
      pinned: pinned,
    );
    _scheduleCommBadgeRefresh();
  }

  void _handleExitedGroup(int conversationId) {
    if (conversationId > 0) {
      _conversationRemovedSignal.notifyRemoved(conversationId);
      final slotId = 'group:$conversationId';
      _dualChatSlots.remove(slotId);
      _dualChatKeys.remove(slotId);
      _mutedConvIds.remove(conversationId);
    }
    _leaveChatToInbox(clearSelection: true);
  }

  Widget _buildDualPaneGroupInfoPage() {
    final group = _selectedGroup;
    if (group == null) {
      return const SizedBox.shrink();
    }
    return NativeGroupInfoPage(
      session: widget.session,
      conversationHint: group,
      onBack: widget.navigation.back,
      onOpenSearch: (convId) {
        setState(() {
          _searchConversationId = convId;
          _searchTitle = '${group.title} · 搜索';
          _searchReturnScreen = 'C6';
          _focusMessageId = null;
          _focusMessageHint = null;
        });
        widget.navigation.go('C12');
      },
      onOpenMedia: (convId) {
        setState(() {
          _mediaConversationId = convId;
          _mediaTitle = group.title;
        });
        widget.navigation.go('C13');
      },
      onOpenMember: (userId, displayName) {
        _openContactProfile(userId, displayName);
      },
      onOpenApproval: () => _goB14(),
      onExitedGroup: _handleExitedGroup,
      onChatSettingsChanged: _onPrivateChatSettingsChanged,
    );
  }

  Widget _buildDualPaneContactProfilePage() {
    if (_selectedPrivate?.isSelfMemo == true) {
      return _buildSelfMemoSettingsPage();
    }
    final profileConvId = _profileReturnScreen == 'C5'
        ? _selectedPrivate?.id
        : null;
    return NativeContactProfilePage(
      key: ValueKey<int>(_selectedContact?.userId ?? 0),
      session: widget.session,
      contactHint: _selectedContact,
      onBack: widget.navigation.back,
      onOpenPrivateChat: _openPrivateByPeerId,
      conversationId: profileConvId,
      onChatSettingsChanged: _onPrivateChatSettingsChanged,
      onCreateGroupWithContact: _startGroupFromContact,
      onOpenSearch: profileConvId == null
          ? null
          : (convId) {
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
  }

  Widget _buildSelfMemoSettingsPage() {
    final conversation = _selectedPrivate;
    if (conversation == null || !conversation.isSelfMemo) {
      return const SizedBox.shrink();
    }
    return NativeSelfMemoSettingsPage(
      conversation: conversation,
      session: widget.session,
      onBack: widget.navigation.back,
      onSettingsChanged: _onPrivateChatSettingsChanged,
      onOpenSearch: (convId) {
        setState(() {
          _searchConversationId = convId;
          _searchTitle = '文件传输助手 · 搜索';
          _searchReturnScreen = 'C9';
          _focusMessageId = null;
          _focusMessageHint = null;
        });
        widget.navigation.go('C12');
      },
    );
  }

  void _clearContactsGroupPickState() {
    _contactsGroupPickMode = false;
    _contactsInitialSelectedUserIds = <int>{};
    _contactsLockedSelectedUserIds = <int>{};
    _contactsInitialSelectedNames = <int, String>{};
  }

  /// 私聊详情头像旁「+」：进入通讯录建群，并预选当前联系人。
  void _startGroupFromContact(NativeContact contact) {
    final userId = contact.userId;
    if (userId <= 0 || userId == widget.session.userId) return;
    final name = contact.displayLabel.trim().isEmpty
        ? contact.displayName.trim()
        : contact.displayLabel.trim();
    setState(() {
      _contactsGroupPickMode = true;
      _contactsInitialSelectedUserIds = <int>{userId};
      _contactsLockedSelectedUserIds = <int>{userId};
      _contactsInitialSelectedNames = name.isEmpty
          ? <int, String>{}
          : <int, String>{userId: name};
    });
    widget.navigation.go('C3');
  }

  Widget _buildDualPaneSearchPage() {
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
        // 群聊信息页的历史入口先经过 C6，但定位结果必须回到 C2 会话内，
        // 让 NativeChatView 用 focusMessageId 拉取并滚到原消息。
        final returnScreen = _searchReturnScreen == 'C6'
            ? 'C2'
            : _searchReturnScreen == 'C9'
            ? 'C5'
            : _searchReturnScreen;
        if (returnScreen == 'C5' || returnScreen == 'C2') {
          _markUserEnteredChat();
        }
        if (widget.navigation.history.contains(returnScreen)) {
          widget.navigation.popTo(returnScreen);
        } else {
          _goChatScreen(returnScreen);
        }
      },
    );
  }

  Widget _buildDualPaneMediaPage() {
    return NativeGroupMediaPage(
      session: widget.session,
      conversationId: _mediaConversationId,
      title: _mediaTitle,
      onBack: widget.navigation.back,
    );
  }

  Widget _buildAiSummaryHubPage() {
    return NativeAiSummaryHubPage(
      session: widget.session,
      onBack: widget.navigation.back,
      onCreate: () => _openAiSummaryCreate(),
      onOpenDetail: (id) {
        setState(() => _selectedAiSummaryId = id);
        widget.navigation.go('AS3');
      },
      onOpened: () {
        _pendingBadgeZeroSync = true;
        unawaited(_refreshCommUnreadBadge());
      },
    );
  }

  Widget _buildAiSummaryCreatePage() {
    final prefill = _aiSummaryPrefillConversationIds;
    return NativeAiSummaryCreatePage(
      key: ValueKey<String>('as2-${prefill.join(',')}'),
      session: widget.session,
      initialConversationIds: prefill,
      onBack: () {
        setState(() => _aiSummaryPrefillConversationIds = const <int>[]);
        widget.navigation.back();
      },
      onCreated: (item) {
        setState(() {
          _selectedAiSummaryId = item.id;
          _aiSummaryPrefillConversationIds = const <int>[];
        });
        widget.navigation.replaceTop('AS3');
      },
    );
  }

  Widget _buildAiSummaryDetailPage() {
    final summaryId = _selectedAiSummaryId ?? 0;
    if (summaryId <= 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.navigation.back();
      });
      return const SizedBox.shrink();
    }
    return NativeAiSummaryDetailPage(
      key: ValueKey<int>(summaryId),
      session: widget.session,
      summaryId: summaryId,
      onBack: widget.navigation.back,
    );
  }

  /// 普通浏览通讯录（非建群多选）。用稳定 GlobalKey 保活，避免进名片后列表滚回顶部。
  Widget _buildContactsBrowsePage({bool useKeepAliveKey = false}) {
    return NativeContactsPage(
      key: useKeepAliveKey
          ? _contactsPageKey
          : const ValueKey<String>('native-contacts-browse'),
      session: widget.session,
      initialGroupPickMode: false,
      initialSelectedUserIds: const <int>{},
      lockedSelectedUserIds: const <int>{},
      initialSelectedNames: const <int, String>{},
      onBack: () {
        setState(_clearContactsGroupPickState);
        widget.navigation.back();
      },
      onOpenContact: (contact) {
        setState(() {
          _clearContactsGroupPickState();
          _selectedContact = contact;
          _profileReturnScreen = null;
        });
        widget.navigation.go('C9');
      },
      onStartPrivateChat: _openPrivateByPeerId,
      onOpenGroupChat: (conv) {
        setState(_clearContactsGroupPickState);
        _openGroupConversation(conv);
      },
    );
  }

  Widget _buildConversationListPage({
    int? selectedConversationId,
    bool listVisible = true,
    bool useKeepAliveKey = false,
  }) {
    return NativeConversationPage(
      key: useKeepAliveKey
          ? _inboxPageKey
          : const ValueKey<String>('native-conversation-inbox'),
      session: widget.session,
      navigation: widget.navigation,
      commUnread: _commUnread,
      workbenchBadge: _workbenchBadge,
      selectedConversationId: selectedConversationId,
      conversationReadSignal: _conversationReadSignal,
      notificationsReadSignal: _notificationsReadSignal,
      memberSettingsSignal: _conversationMemberSettingsSignal,
      conversationRemovedSignal: _conversationRemovedSignal,
      listVisible: listVisible,
      onOpenPrivate: _openPrivateConversation,
      onOpenGroup: _openGroupConversation,
      onOpenRobot: _openRobotConversation,
      onStartPrivateChat: _openPrivateByPeerId,
      onOpenContacts: () {
        setState(_clearContactsGroupPickState);
        widget.navigation.go('C3');
      },
      onOpenNova: () {
        if (widget.session.isExternalUser) return;
        NovaBackgroundCoordinator.instance.clearPendingCommBadgeBump();
        setState(() {
          _novaFocusConversationId = null;
          _novaFocusMessageId = null;
        });
        widget.navigation.go('C4');
      },
      onOpenNotifications: (tab) {
        if (widget.session.isExternalUser) return;
        setState(() {
          _messageCenterInitialTab = tab;
          _messageCenterMarkAllOnEnter = true;
        });
        widget.navigation.go('Z2');
      },
      onOpenNewChat: () {
        setState(() {
          _clearContactsGroupPickState();
          _contactsGroupPickMode = true;
        });
        widget.navigation.go('C3');
      },
      onOpenAiSummary: widget.session.isExternalUser
          ? () {}
          : () => widget.navigation.go('AS1'),
      onOpenFavorites: () => widget.navigation.go('CF'),
      onOpenApprovalAssistant: _openApprovalAssistant,
      onOpenTaskAssistant: _openTaskAssistant,
      onOpenDriveAssistant: _openDriveAssistant,
      onOpenXrxsAssistant: widget.session.isExternalUser
          ? null
          : _openXrxsAssistant,
      onOpenWeeklySummary: _openWeeklySummary,
      onOpenAdministrativeNotice: _openAdministrativeNotice,
      onOpenReconciliationAssistant: !widget.session.isExternalUser
          ? _openReconciliationAssistant
          : null,
    );
  }

  void _openReconciliationAssistant([NativeConversation? hint]) {
    setState(() {
      _selectedPrivate = null;
      _selectedPrivatePeerUserId = null;
      _selectedGroup = null;
      _selectedRobot = null;
      _selectedApprovalAssistant = null;
      _selectedTaskAssistant = null;
      _selectedDriveAssistant = null;
      _selectedXrxsAssistant = null;
      _selectedWeeklySummary = null;
      _selectedAdministrativeNotice = null;
      _administrativeNoticeTargetId = null;
      _focusMessageId = null;
      _focusMessageHint = null;
      if (hint != null && hint.id > 0) {
        _selectedReconciliation = hint;
      }
    });
    _markUserEnteredChat();
    _goChatScreen('RA1');
    if ((hint?.id ?? 0) > 0) {
      _conversationReadSignal.notifyRead(hint!.id);
    }
  }

  void _openDailyReconWorkbench({
    NativeConversation? hint,
    String asOfDate = '',
    String cardType = '',
  }) {
    setState(() {
      _selectedPrivate = null;
      _selectedPrivatePeerUserId = null;
      _selectedGroup = null;
      _selectedRobot = null;
      _selectedApprovalAssistant = null;
      _selectedTaskAssistant = null;
      _selectedDriveAssistant = null;
      _selectedXrxsAssistant = null;
      _selectedWeeklySummary = null;
      _selectedAdministrativeNotice = null;
      _administrativeNoticeTargetId = null;
      _focusMessageId = null;
      _focusMessageHint = null;
      if (hint != null && hint.id > 0) {
        _selectedReconciliation = hint;
      }
      _dailyReconAsOfDate = asOfDate.trim();
      _dailyReconCardType = cardType.trim();
      _dailyReconOpenToken++;
      _openDailyReconPending = true;
    });
    _markUserEnteredChat();
    widget.navigation.go('QJA');
    if ((hint?.id ?? 0) > 0) {
      _conversationReadSignal.notifyRead(hint!.id);
    }
  }

  Future<void> _openApprovalAssistant([NativeConversation? hint]) async {
    final openGen = ++_approvalAssistantOpenGen;
    setState(() {
      _selectedPrivate = null;
      _selectedPrivatePeerUserId = null;
      _selectedGroup = null;
      _selectedRobot = null;
      _selectedTaskAssistant = null;
      _selectedDriveAssistant = null;
      _selectedXrxsAssistant = null;
      _selectedWeeklySummary = null;
      _selectedReconciliation = null;
      _selectedAdministrativeNotice = null;
      _administrativeNoticeTargetId = null;
      _focusMessageId = null;
      _focusMessageHint = null;
      if (hint != null && hint.id > 0) {
        _selectedApprovalAssistant = hint;
      }
    });
    // 列表已有会话 id 时先打开，避免 ensure 慢/失败时用 id=0 拉消息 → 404。
    if ((_selectedApprovalAssistant?.id ?? 0) > 0) {
      _markUserEnteredChat();
      _goChatScreen('AA1');
      if ((_selectedApprovalAssistant?.id ?? 0) > 0) {
        _conversationReadSignal.notifyRead(_selectedApprovalAssistant!.id);
      }
    }
    try {
      final conv = await ConversationService(
        session: widget.session,
      ).ensureApprovalAssistantSession();
      if (!mounted || openGen != _approvalAssistantOpenGen) return;
      setState(() => _selectedApprovalAssistant = conv);
      if (conv.id > 0) {
        _conversationReadSignal.notifyRead(conv.id);
      }
      // 先前没有可用 hint（或仍停在 AA1）时再导航。
      final onAa =
          widget.navigation.currentScreen == 'AA1' ||
          widget.navigation.currentScreen == 'AA2' ||
          widget.navigation.currentScreen == 'AA3';
      if (!onAa) {
        _markUserEnteredChat();
        _goChatScreen('AA1');
      }
    } catch (e) {
      if (!mounted || openGen != _approvalAssistantOpenGen) return;
      if ((_selectedApprovalAssistant?.id ?? 0) <= 0) {
        showDunesToast(
          context,
          friendlyErrorText(e),
          kind: DunesToastKind.error,
        );
        return;
      }
      // 已有列表会话仍可看历史；ensure 失败只提示一次。
      showDunesToast(context, '审批助手会话同步失败，先展示本地会话', kind: DunesToastKind.error);
    }
  }

  Future<void> _openTaskAssistant([NativeConversation? hint]) async {
    setState(() {
      _selectedPrivate = null;
      _selectedPrivatePeerUserId = null;
      _selectedGroup = null;
      _selectedRobot = null;
      _selectedApprovalAssistant = null;
      _selectedDriveAssistant = null;
      _selectedXrxsAssistant = null;
      _selectedWeeklySummary = null;
      _selectedReconciliation = null;
      _selectedAdministrativeNotice = null;
      _administrativeNoticeTargetId = null;
      if (hint != null && hint.id > 0) _selectedTaskAssistant = hint;
    });
    if ((_selectedTaskAssistant?.id ?? 0) > 0) {
      _markUserEnteredChat();
      _goChatScreen('TA1');
      _conversationReadSignal.notifyRead(_selectedTaskAssistant!.id);
    }
    try {
      final conv = await ConversationService(
        session: widget.session,
      ).ensureTaskAssistantSession();
      if (!mounted) return;
      setState(() => _selectedTaskAssistant = conv);
      _conversationReadSignal.notifyRead(conv.id);
      if (widget.navigation.currentScreen != 'TA1') {
        _markUserEnteredChat();
        _goChatScreen('TA1');
      }
    } catch (_) {
      if (mounted && (_selectedTaskAssistant?.id ?? 0) <= 0) {
        showDunesToast(context, '任务助手会话同步失败', kind: DunesToastKind.error);
      }
    }
  }

  Widget _buildTaskAssistantPage({bool showBackButton = true}) {
    final hint =
        _selectedTaskAssistant ??
        const NativeConversation(
          id: 0,
          kind: 'TASK_ASSISTANT',
          title: '任务助手',
          unreadCount: 0,
          preview: '',
          updatedAt: null,
        );
    return NativeTaskAssistantPage(
      key: ValueKey<int>(hint.id),
      session: widget.session,
      conversationHint: hint,
      navigation: widget.navigation,
      showBackButton: showBackButton,
      onBack: () => _leaveChatToInbox(clearSelection: true),
      onConversationRead: _handleConversationRead,
      autoMarkRead: _userActivelyInChat,
    );
  }

  Future<void> _openDriveAssistant([NativeConversation? hint]) async {
    setState(() {
      _selectedPrivate = null;
      _selectedPrivatePeerUserId = null;
      _selectedGroup = null;
      _selectedRobot = null;
      _selectedApprovalAssistant = null;
      _selectedTaskAssistant = null;
      _selectedXrxsAssistant = null;
      _selectedWeeklySummary = null;
      _selectedReconciliation = null;
      _selectedAdministrativeNotice = null;
      _administrativeNoticeTargetId = null;
      if (hint != null && hint.id > 0) _selectedDriveAssistant = hint;
    });
    if ((_selectedDriveAssistant?.id ?? 0) > 0) {
      _markUserEnteredChat();
      _goChatScreen('DA1');
      _conversationReadSignal.notifyRead(_selectedDriveAssistant!.id);
    }
    try {
      final conv = await ConversationService(
        session: widget.session,
      ).ensureDriveAssistantSession();
      if (!mounted) return;
      setState(() => _selectedDriveAssistant = conv);
      _conversationReadSignal.notifyRead(conv.id);
      if (widget.navigation.currentScreen != 'DA1') {
        _markUserEnteredChat();
        _goChatScreen('DA1');
      }
    } catch (_) {
      if (mounted && (_selectedDriveAssistant?.id ?? 0) <= 0) {
        showDunesToast(context, '企业微盘会话同步失败', kind: DunesToastKind.error);
      }
    }
  }

  void _openDriveItemFromChat(int itemId) {
    if (itemId <= 0) return;
    setState(() => _driveTargetItemId = itemId);
    _markUserLeftChat();
    widget.navigation.go('FD1');
  }

  Future<void> _openWeeklySummary([NativeConversation? hint]) async {
    setState(() {
      _selectedPrivate = null;
      _selectedPrivatePeerUserId = null;
      _selectedGroup = null;
      _selectedRobot = null;
      _selectedApprovalAssistant = null;
      _selectedTaskAssistant = null;
      _selectedDriveAssistant = null;
      _selectedXrxsAssistant = null;
      _selectedReconciliation = null;
      _selectedAdministrativeNotice = null;
      _administrativeNoticeTargetId = null;
      if (hint != null && hint.id > 0) _selectedWeeklySummary = hint;
    });
    if ((_selectedWeeklySummary?.id ?? 0) > 0) {
      _markUserEnteredChat();
      _goChatScreen('WS1');
      _conversationReadSignal.notifyRead(_selectedWeeklySummary!.id);
    }
  }

  Widget _buildWeeklySummaryPage({bool showBackButton = true}) {
    final hint =
        _selectedWeeklySummary ??
        const NativeConversation(
          id: 0,
          kind: 'WEEKLY_SUMMARY',
          title: '一周小结',
          unreadCount: 0,
          preview: '',
          updatedAt: null,
        );
    return NativeWeeklySummaryPage(
      key: ValueKey<int>(hint.id),
      session: widget.session,
      conversationHint: hint,
      showBackButton: showBackButton,
      autoMarkRead: _userActivelyInChat,
      onBack: () => _leaveChatToInbox(clearSelection: true),
      onConversationRead: _handleConversationRead,
    );
  }

  void _openAdministrativeNotice(NativeConversation? hint, {int noticeId = 0}) {
    setState(() {
      _selectedPrivate = null;
      _selectedPrivatePeerUserId = null;
      _selectedGroup = null;
      _selectedRobot = null;
      _selectedApprovalAssistant = null;
      _selectedTaskAssistant = null;
      _selectedDriveAssistant = null;
      _selectedXrxsAssistant = null;
      _selectedWeeklySummary = null;
      _selectedReconciliation = null;
      if (hint != null && hint.id > 0) {
        _selectedAdministrativeNotice = hint;
      } else {
        _selectedAdministrativeNotice = null;
      }
      _administrativeNoticeTargetId = noticeId > 0 ? noticeId : null;
    });
    _markUserEnteredChat();
    // 行政通知未读以「确认」为准：进入详情不能本地清角标。
    _goChatScreen('AN1');
  }

  Widget _buildAdministrativeNoticePage({bool showBackButton = true}) {
    final hint =
        _selectedAdministrativeNotice ??
        const NativeConversation(
          id: 0,
          kind: 'ADMIN_NOTICE',
          title: '行政通知',
          unreadCount: 0,
          preview: '',
          updatedAt: null,
        );
    return NativeAdministrativeNoticePage(
      key: ValueKey<String>(
        'an1-${hint.id}-${_administrativeNoticeTargetId ?? 0}',
      ),
      session: widget.session,
      conversationHint: hint,
      initialNoticeId: _administrativeNoticeTargetId,
      showBackButton: showBackButton,
      onBack: () => _leaveChatToInbox(clearSelection: true),
      onAcknowledged: _handleConversationRead,
    );
  }

  Widget _buildDriveAssistantPage({bool showBackButton = true}) {
    final hint =
        _selectedDriveAssistant ??
        const NativeConversation(
          id: 0,
          kind: 'DRIVE_ASSISTANT',
          title: '企业微盘',
          unreadCount: 0,
          preview: '',
          updatedAt: null,
        );
    return NativeDriveAssistantPage(
      key: ValueKey<int>(hint.id),
      session: widget.session,
      conversationHint: hint,
      showBackButton: showBackButton,
      onBack: () => _leaveChatToInbox(clearSelection: true),
      onConversationRead: _handleConversationRead,
      onOpenItem: _openDriveItemFromChat,
    );
  }

  Future<void> _openXrxsAssistant([NativeConversation? hint]) async {
    setState(() {
      _selectedPrivate = null;
      _selectedPrivatePeerUserId = null;
      _selectedGroup = null;
      _selectedRobot = null;
      _selectedApprovalAssistant = null;
      _selectedTaskAssistant = null;
      _selectedDriveAssistant = null;
      _selectedWeeklySummary = null;
      _selectedReconciliation = null;
      _selectedAdministrativeNotice = null;
      _administrativeNoticeTargetId = null;
      if (hint != null && hint.id > 0) _selectedXrxsAssistant = hint;
    });
    if ((_selectedXrxsAssistant?.id ?? 0) > 0) {
      _markUserEnteredChat();
      _goChatScreen('XA1');
      _conversationReadSignal.notifyRead(_selectedXrxsAssistant!.id);
    }
    try {
      final conv = await ConversationService(
        session: widget.session,
      ).ensureXrxsAssistantSession();
      if (!mounted) return;
      setState(() => _selectedXrxsAssistant = conv);
      _conversationReadSignal.notifyRead(conv.id);
      if (widget.navigation.currentScreen != 'XA1') {
        _markUserEnteredChat();
        _goChatScreen('XA1');
      }
    } catch (_) {
      if (mounted && (_selectedXrxsAssistant?.id ?? 0) <= 0) {
        showDunesToast(context, '薪人薪事会话同步失败', kind: DunesToastKind.error);
      }
    }
  }

  Widget _buildXrxsAssistantPage({bool showBackButton = true}) {
    final hint =
        _selectedXrxsAssistant ??
        const NativeConversation(
          id: 0,
          kind: 'XRXS_ASSISTANT',
          title: '薪人薪事',
          unreadCount: 0,
          preview: '',
          updatedAt: null,
        );
    return NativeXrxsAssistantPage(
      key: ValueKey<int>(hint.id),
      session: widget.session,
      conversationHint: hint,
      showBackButton: showBackButton,
      onBack: () => _leaveChatToInbox(clearSelection: true),
      onConversationRead: _handleConversationRead,
      onOpenHome: () => _openXrxsPortal(),
      onOpenDetail: (sid, role) => _openXrxsPortal(sid: sid, role: role),
    );
  }

  /// APP：内嵌 XR1 WebView；PC 桌面：XR1 取免登后系统浏览器打开。
  void _openXrxsPortal({String? sid, String? role}) {
    _markUserLeftChat();
    setState(() {
      _xrxsLoginSid = sid?.trim().isEmpty == true ? null : sid?.trim();
      _xrxsLoginRole = role?.trim().isEmpty == true ? null : role?.trim();
    });
    widget.navigation.go('XR1');
  }

  void _openApprovalAssistantPending(ApprovalAssistantPickMode mode) {
    setState(() => _approvalAssistantPickMode = mode);
    widget.navigation.go('AA2');
  }

  void _openApprovalAssistantProposals(String kind) {
    setState(() => _approvalAssistantProposalKind = kind);
    widget.navigation.go('AA3');
  }

  Widget _buildApprovalAssistantPage({bool showBackButton = true}) {
    final hint =
        _selectedApprovalAssistant ??
        const NativeConversation(
          id: 0,
          kind: 'APPROVAL_ASSISTANT',
          title: '审批助手',
          unreadCount: 0,
          preview: '',
          updatedAt: null,
        );
    return NativeApprovalAssistantPage(
      key: ValueKey<int>(hint.id),
      session: widget.session,
      conversationHint: hint,
      showBackButton: showBackButton,
      autoMarkRead: _userActivelyInChat,
      onBack: () => _leaveChatToInbox(clearSelection: true),
      onConversationRead: _handleConversationRead,
      onOpenPendingList: _openApprovalAssistantPending,
      onOpenProposals: _openApprovalAssistantProposals,
      onOpenApproval: (share) => _openApprovalFromChat(share, from: 'AA1'),
    );
  }

  Widget _buildApprovalAssistantProposalPage() {
    return NativeApprovalAssistantProposalPage(
      session: widget.session,
      kind: _approvalAssistantProposalKind,
      onBack: () {
        if (widget.navigation.history.contains('AA1')) {
          widget.navigation.popTo('AA1');
        } else {
          widget.navigation.back();
        }
      },
    );
  }

  Widget _buildApprovalAssistantPendingPage() {
    return NativeApprovalAssistantPendingPage(
      session: widget.session,
      mode: _approvalAssistantPickMode,
      onBack: () {
        if (widget.navigation.history.contains('AA1')) {
          widget.navigation.popTo('AA1');
        } else {
          widget.navigation.back();
        }
      },
      onOpenDetail: (businessType, businessId) {
        // 复用现有审批详情入口（与聊天审批卡片一致）。
        // 返回 Future，AA2 在详情关闭后可刷新列表（如撤回后不再残留）。
        return _openApprovalFromChat(
          ApprovalChatShare(
            businessType: businessType,
            businessId: businessId,
            title: '',
          ),
          from: 'AA2',
        );
      },
      onActionDone: () {
        if (widget.navigation.history.contains('AA1')) {
          widget.navigation.popTo('AA1');
        } else {
          widget.navigation.go('AA1');
        }
      },
    );
  }

  /// 当前选中的底层会话（不随名片/搜索/媒体切换而卸载）。
  String? _activeDualChatSlotId() {
    final screen = widget.navigation.currentScreen;
    final dual = _dualPaneChatScreen;
    if (screen == 'AA1' ||
        screen == 'AA2' ||
        screen == 'AA3' ||
        dual == 'AA1' ||
        dual == 'AA2' ||
        dual == 'AA3') {
      return 'aa';
    }
    if (screen == 'TA1' || dual == 'TA1') {
      return 'ta';
    }
    if (screen == 'DA1' || dual == 'DA1') {
      return 'da';
    }
    if (screen == 'XA1' || dual == 'XA1') {
      return 'xa';
    }
    if (screen == 'WS1' || dual == 'WS1') {
      return 'ws';
    }
    if (screen == 'AN1' || dual == 'AN1') {
      return 'an';
    }
    if (screen == 'RA1' || dual == 'RA1') {
      return 'reconciliation';
    }
    // 路由优先：通讯录发消息进 C5 时，不能被残留的 AI 咨询选中态盖住。
    if (screen == 'C5' || dual == 'C5') {
      if (_selectedPrivate != null || _selectedPrivatePeerUserId != null) {
        final cid = _selectedPrivate?.id ?? 0;
        if (cid > 0) return 'private:$cid';
        final peer =
            _selectedPrivatePeerUserId ?? _selectedPrivate?.peerUserId ?? 0;
        return peer > 0 ? 'private-peer:$peer' : null;
      }
    }
    if (screen == 'C2' || dual == 'C2') {
      if (_selectedGroup != null) return 'group:${_selectedGroup!.id}';
    }
    if (screen == 'CR' || dual == 'CR') {
      if (_selectedRobot != null) return 'robot:${_selectedRobot!.id}';
    }
    if (_selectedRobot != null) {
      return 'robot:${_selectedRobot!.id}';
    }
    if (_selectedPrivate != null || _selectedPrivatePeerUserId != null) {
      final cid = _selectedPrivate?.id ?? 0;
      if (cid > 0) return 'private:$cid';
      final peer =
          _selectedPrivatePeerUserId ?? _selectedPrivate?.peerUserId ?? 0;
      return peer > 0 ? 'private-peer:$peer' : null;
    }
    if (_selectedGroup != null) {
      return 'group:${_selectedGroup!.id}';
    }
    return null;
  }

  _DualChatSlot? _captureActiveDualChatSlot() {
    final screen = widget.navigation.currentScreen;
    final dual = _dualPaneChatScreen;
    if (screen == 'AA1' ||
        screen == 'AA2' ||
        screen == 'AA3' ||
        dual == 'AA1' ||
        dual == 'AA2' ||
        dual == 'AA3') {
      return _DualChatSlot.approval(_selectedApprovalAssistant);
    }
    if (screen == 'TA1' || dual == 'TA1') {
      return _DualChatSlot.task(_selectedTaskAssistant);
    }
    if (screen == 'DA1' || dual == 'DA1') {
      return _DualChatSlot.drive(_selectedDriveAssistant);
    }
    if (screen == 'XA1' || dual == 'XA1') {
      return _DualChatSlot.xrxs(_selectedXrxsAssistant);
    }
    if (screen == 'WS1' || dual == 'WS1') {
      return _DualChatSlot.weeklySummary(_selectedWeeklySummary);
    }
    if (screen == 'AN1' || dual == 'AN1') {
      return _DualChatSlot.administrativeNotice(_selectedAdministrativeNotice);
    }
    if (screen == 'RA1' || dual == 'RA1') {
      return _DualChatSlot.reconciliation(_selectedReconciliation);
    }
    if (screen == 'C5' || dual == 'C5') {
      if (_selectedPrivate != null || _selectedPrivatePeerUserId != null) {
        return _DualChatSlot.private(
          conversation: _selectedPrivate,
          peerUserId: _selectedPrivatePeerUserId,
        );
      }
    }
    if (screen == 'C2' || dual == 'C2') {
      if (_selectedGroup != null) {
        return _DualChatSlot.group(_selectedGroup!);
      }
    }
    if (screen == 'CR' || dual == 'CR') {
      if (_selectedRobot != null) {
        return _DualChatSlot.robot(_selectedRobot!);
      }
    }
    if (_selectedRobot != null) {
      return _DualChatSlot.robot(_selectedRobot!);
    }
    if (_selectedPrivate != null || _selectedPrivatePeerUserId != null) {
      return _DualChatSlot.private(
        conversation: _selectedPrivate,
        peerUserId: _selectedPrivatePeerUserId,
      );
    }
    if (_selectedGroup != null) {
      return _DualChatSlot.group(_selectedGroup!);
    }
    return null;
  }

  void _touchDualChatKeepAlive(String slotId, _DualChatSlot data) {
    _dualChatSlots.remove(slotId);
    _dualChatSlots[slotId] = data;
    _dualChatKeys.putIfAbsent(
      slotId,
      () => GlobalKey(debugLabel: 'dual-$slotId'),
    );
    while (_dualChatSlots.length > _maxDualChatKeepAlive) {
      final evict = _dualChatSlots.keys.first;
      _dualChatSlots.remove(evict);
      _dualChatKeys.remove(evict);
    }
  }

  Widget _buildDualChatPageForSlot({
    required String slotId,
    required _DualChatSlot slot,
    required bool active,
  }) {
    final key = _dualChatKeys[slotId]!;
    final autoMark = active && _userActivelyInChat;
    switch (slot.kind) {
      case _DualChatKind.approval:
        return KeyedSubtree(
          key: key,
          child: NativeApprovalAssistantPage(
            session: widget.session,
            conversationHint:
                slot.conversation ??
                const NativeConversation(
                  id: 0,
                  kind: 'APPROVAL_ASSISTANT',
                  title: '审批助手',
                  unreadCount: 0,
                  preview: '',
                  updatedAt: null,
                ),
            showBackButton: false,
            autoMarkRead: autoMark,
            onBack: () => _leaveChatToInbox(clearSelection: true),
            onConversationRead: _handleConversationRead,
            onOpenPendingList: _openApprovalAssistantPending,
            onOpenProposals: _openApprovalAssistantProposals,
            onOpenApproval: (share) =>
                _openApprovalFromChat(share, from: 'AA1'),
          ),
        );
      case _DualChatKind.task:
        return KeyedSubtree(
          key: key,
          child: NativeTaskAssistantPage(
            session: widget.session,
            conversationHint:
                slot.conversation ??
                const NativeConversation(
                  id: 0,
                  kind: 'TASK_ASSISTANT',
                  title: '任务助手',
                  unreadCount: 0,
                  preview: '',
                  updatedAt: null,
                ),
            navigation: widget.navigation,
            showBackButton: false,
            autoMarkRead: autoMark,
            onBack: () => _leaveChatToInbox(clearSelection: true),
            onConversationRead: _handleConversationRead,
          ),
        );
      case _DualChatKind.drive:
        return KeyedSubtree(
          key: key,
          child: NativeDriveAssistantPage(
            session: widget.session,
            conversationHint:
                slot.conversation ??
                const NativeConversation(
                  id: 0,
                  kind: 'DRIVE_ASSISTANT',
                  title: '企业微盘',
                  unreadCount: 0,
                  preview: '',
                  updatedAt: null,
                ),
            showBackButton: false,
            onBack: () => _leaveChatToInbox(clearSelection: true),
            onConversationRead: _handleConversationRead,
            onOpenItem: _openDriveItemFromChat,
          ),
        );
      case _DualChatKind.xrxs:
        return KeyedSubtree(
          key: key,
          child: NativeXrxsAssistantPage(
            session: widget.session,
            conversationHint:
                slot.conversation ??
                const NativeConversation(
                  id: 0,
                  kind: 'XRXS_ASSISTANT',
                  title: '薪人薪事',
                  unreadCount: 0,
                  preview: '',
                  updatedAt: null,
                ),
            showBackButton: false,
            onBack: () => _leaveChatToInbox(clearSelection: true),
            onConversationRead: _handleConversationRead,
            onOpenHome: () => _openXrxsPortal(),
            onOpenDetail: (sid, role) => _openXrxsPortal(sid: sid, role: role),
          ),
        );
      case _DualChatKind.weeklySummary:
        return KeyedSubtree(
          key: key,
          child: NativeWeeklySummaryPage(
            session: widget.session,
            conversationHint:
                slot.conversation ??
                const NativeConversation(
                  id: 0,
                  kind: 'WEEKLY_SUMMARY',
                  title: '一周小结',
                  unreadCount: 0,
                  preview: '',
                  updatedAt: null,
                ),
            showBackButton: false,
            autoMarkRead: autoMark,
            onBack: () => _leaveChatToInbox(clearSelection: true),
            onConversationRead: _handleConversationRead,
          ),
        );
      case _DualChatKind.administrativeNotice:
        return KeyedSubtree(
          key: key,
          child: NativeAdministrativeNoticePage(
            session: widget.session,
            conversationHint:
                slot.conversation ??
                const NativeConversation(
                  id: 0,
                  kind: 'ADMIN_NOTICE',
                  title: '行政通知',
                  unreadCount: 0,
                  preview: '',
                  updatedAt: null,
                ),
            initialNoticeId: active ? _administrativeNoticeTargetId : null,
            isActive: active,
            showBackButton: false,
            onBack: () => _leaveChatToInbox(clearSelection: true),
            onAcknowledged: _handleConversationRead,
          ),
        );
      case _DualChatKind.reconciliation:
        return KeyedSubtree(
          key: key,
          child: NativeReconciliationAssistantPage(
            desktopMode: true,
            session: widget.session,
            conversationHint:
                slot.conversation ??
                const NativeConversation(
                  id: 0,
                  kind: 'RECONCILIATION_ASSISTANT',
                  title: '对账助手',
                  unreadCount: 0,
                  preview: '',
                  updatedAt: null,
                ),
            showBackButton: false,
            autoMarkRead: autoMark,
            onBack: () => _leaveChatToInbox(clearSelection: true),
            onConversationRead: _handleConversationRead,
            onOpenWorkbenchDailyRecon: (date, {cardType = ''}) {
              _openDailyReconWorkbench(
                hint: slot.conversation,
                asOfDate: date,
                cardType: cardType,
              );
            },
          ),
        );
      case _DualChatKind.robot:
        return NativeRobotChatPage(
          key: key,
          session: widget.session,
          conversationHint: slot.conversation!,
          showBackButton: false,
          autoMarkRead: autoMark,
          onBack: () => _leaveChatToInbox(clearSelection: true),
          onConversationRead: _handleConversationRead,
          onOpenConsultList: _openRobotConsultListFromChat,
        );
      case _DualChatKind.private:
        return NativePrivateChatPage(
          key: key,
          session: widget.session,
          conversationHint: slot.conversation,
          peerUserIdHint: slot.peerUserId,
          focusMessageId: active ? _focusMessageId : null,
          focusMessageHint: active ? _focusMessageHint : null,
          autoMarkRead: autoMark,
          showBackButton: false,
          onBack: () => _leaveChatToInbox(clearSelection: true),
          onOpenProfile: () {
            if (slot.conversation?.isSelfMemo == true) {
              setState(() {
                _selectedPrivate = slot.conversation;
                _profileReturnScreen = 'C5';
              });
              widget.navigation.go('C9');
              return;
            }
            final peerId = slot.conversation?.peerUserId ?? slot.peerUserId;
            if (peerId == null || peerId <= 0) return;
            _openContactProfile(
              peerId,
              slot.conversation?.peerDisplayName ??
                  slot.conversation?.title ??
                  '',
            );
          },
          onOpenUser: _openContactProfile,
          onOpenSearch: (convId) {
            setState(() {
              _searchConversationId = convId;
              _searchTitle = '${slot.conversation?.displayTitle ?? '私聊'} · 搜索';
              _searchReturnScreen = 'C5';
              _focusMessageId = null;
              _focusMessageHint = null;
            });
            widget.navigation.go('C12');
          },
          onOpenAiSummary: _onOpenAiSummaryFromChat,
          onOpenApprovalShare: (share) =>
              _openApprovalFromChat(share, from: 'C5'),
          onConversationRead: _handleConversationRead,
          onClearFocusMessage: _clearChatFocusMessage,
        );
      case _DualChatKind.group:
        return NativeGroupChatPage(
          key: key,
          session: widget.session,
          conversationHint: slot.conversation!,
          focusMessageId: active ? _focusMessageId : null,
          focusMessageHint: active ? _focusMessageHint : null,
          autoMarkRead: autoMark,
          showBackButton: false,
          onBack: () => _leaveChatToInbox(clearSelection: true),
          onOpenSearch: (convId) {
            setState(() {
              _searchConversationId = convId;
              _searchTitle = slot.conversation?.title ?? '群聊搜索';
              _searchReturnScreen = 'C2';
              _focusMessageId = null;
              _focusMessageHint = null;
            });
            widget.navigation.go('C12');
          },
          onOpenMedia: (convId) {
            setState(() {
              _mediaConversationId = convId;
              _mediaTitle = slot.conversation?.title ?? '群聊';
            });
            widget.navigation.go('C13');
          },
          onOpenGroupInfo: () => widget.navigation.go('C6'),
          onOpenUser: _openContactProfile,
          onOpenAiSummary: _onOpenAiSummaryFromChat,
          onOpenApprovalShare: (share) =>
              _openApprovalFromChat(share, from: 'C2'),
          onConversationRead: _handleConversationRead,
          onClearFocusMessage: _clearChatFocusMessage,
        );
    }
  }

  Widget _buildDualPaneChatPane() {
    final activeId = _activeDualChatSlotId();
    final activeData = _captureActiveDualChatSlot();
    if (activeId != null && activeData != null) {
      _touchDualChatKeepAlive(activeId, activeData);
    }

    final overlay = _dualPaneOverlayScreen;
    final Widget? overlayPage = switch (overlay) {
      'C6' => _buildDualPaneGroupInfoPage(),
      'C12' => _buildDualPaneSearchPage(),
      'C13' => _buildDualPaneMediaPage(),
      'C9' => _buildDualPaneContactProfilePage(),
      'AS1' => _buildAiSummaryHubPage(),
      'AS2' => _buildAiSummaryCreatePage(),
      'AS3' => _buildAiSummaryDetailPage(),
      'AA2' => _buildApprovalAssistantPendingPage(),
      'AA3' => _buildApprovalAssistantProposalPage(),
      _ => null,
    };

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final entry in _dualChatSlots.entries)
          Offstage(
            offstage: entry.key != activeId || overlay != null,
            child: TickerMode(
              enabled: entry.key == activeId && overlay == null,
              child: _buildDualChatPageForSlot(
                slotId: entry.key,
                slot: entry.value,
                active: entry.key == activeId,
              ),
            ),
          ),
        if (activeId == null && overlay == null) const ChatDualPaneEmpty(),
        if (overlayPage != null) overlayPage,
      ],
    );
  }

  Widget _buildChatDualPane() {
    return ChatDualPaneShell(
      listPane: _buildConversationListPage(
        selectedConversationId: _dualPaneSelectedConversationId,
      ),
      chatPane: _buildDualPaneChatPane(),
      sideRail: DunesMainTabBar(
        navigation: widget.navigation,
        activeScreen: 'C1',
        axis: Axis.vertical,
        commUnread: _commUnread,
        workbenchBadge: _workbenchBadge,
        lighthouseAccess: widget.session.lighthouseAccess,
        qianjiAccess: widget.session.effectiveQianjiAccess,
        qianjiAdminAccess: widget.session.effectiveQianjiAdminAccess,
        chatOnlyMode: widget.session.isExternalUser,
        onSwitchMainTab: _switchMainTab,
        onDesktopSettingsTap: _openDesktopSettings,
      ),
    );
  }

  Widget _buildCommDualKeepAlive({required bool active}) {
    return Offstage(
      offstage: !active,
      child: TickerMode(
        enabled: active,
        child: KeyedSubtree(
          key: _commDualKeepAliveKey,
          child: _buildChatDualPane(),
        ),
      ),
    );
  }

  Widget _buildWorkbenchKeepAlive({required bool active}) {
    final useSlide = !isDesktopCommOnly;
    final panel = KeyedSubtree(
      key: _workbenchKeepAliveKey,
      child: NativeQianjiAdminShell(
        session: widget.session,
        navigation: widget.navigation,
        active: active,
        onExit: isDesktopCommOnly ? null : () => widget.navigation.popTo('B2'),
        onAdministrativeNoticeAcknowledged: _handleConversationRead,
        openDailyRecon: _openDailyReconPending,
        dailyReconAsOfDate: _dailyReconAsOfDate,
        dailyReconCardType: _dailyReconCardType,
        dailyReconOpenToken: _dailyReconOpenToken,
        onDailyReconOpened: () {
          if (_openDailyReconPending) {
            setState(() => _openDailyReconPending = false);
          }
        },
        onOpenSsoApp: (app) {
          setState(() {
            _ssoAppKey = app.appKey;
            _ssoAppTitle = app.title.isEmpty ? app.appKey : app.title;
          });
          widget.navigation.go('AM1');
        },
      ),
    );
    return Positioned.fill(
      child: TickerMode(
        // APP 侧滑进出时需保持 ticker，否则收起动画会被冻住。
        enabled: active || useSlide,
        child: IgnorePointer(
          ignoring: !active,
          child: useSlide
              ? AnimatedSlide(
                  offset: active ? Offset.zero : const Offset(1, 0),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  child: ColoredBox(color: DunesColors.bgApp, child: panel),
                )
              : Opacity(opacity: active ? 1 : 0, child: panel),
        ),
      ),
    );
  }

  /// APP 工作台滑入时垫在底下的「我的」，避免 keep-alive 瞬切丢滑动感。
  Widget _buildMyWorkbenchUnderlay() {
    return _NativeB2Page(
      session: widget.session,
      navigation: widget.navigation,
      commUnread: _commUnread,
      workbenchBadge: _workbenchBadge,
      workbenchRefresh: _workbenchRefresh,
      onOpenB14: _goB14,
      onOpenB3: _goB3,
      onOpenXflowForm: _openXflowFormFromB2,
      onOpenWorkbench: !widget.session.isExternalUser
          ? () => widget.navigation.go('QJA')
          : null,
      onLogout: widget.onLogout,
    );
  }

  Widget _buildDigitalEmployeeChat(String screen) {
    if (!widget.session.effectiveDigitalEmployeeAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.navigation.go('QJ');
      });
      return const Scaffold(
        backgroundColor: DunesColors.bgApp,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final item = _selectedDigitalEmployee;
    final fallbackKey = switch (screen) {
      'QJMA' => 'meeting-minutes',
      'QJAM' => 'am-settlement',
      _ => 'channel-dock',
    };
    final fallbackIcon = switch (screen) {
      'QJMA' => 'auto_awesome',
      'QJAM' => 'account_balance',
      _ => 'oil_barrel',
    };
    final fallbackConfig = switch (screen) {
      'QJMA' => DigitalAutoConfig.meetingMinutes,
      'QJAM' => DigitalAutoConfig.amSettlement,
      _ => DigitalAutoConfig.channelDock,
    };
    final matchesSelected = switch (screen) {
      'QJMA' => item?.isMeetingMinutes == true,
      'QJAM' => item?.isAmSettlement == true,
      _ => item?.screenId == 'QJTO',
    };
    return NativeDigitalAutoChatPage(
      key: ValueKey<String>(
        '${screen.toLowerCase()}-${item?.employeeKey ?? fallbackKey}',
      ),
      session: widget.session,
      onBack: widget.navigation.back,
      iconKey: item?.iconKey ?? fallbackIcon,
      configuration: matchesSelected ? item!.chatConfig : fallbackConfig,
    );
  }

  Widget _buildCurrentScreen(BuildContext context) {
    if (widget.session.isExternalUser &&
        _isRestrictedForExternalUser(widget.navigation.currentScreen)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.session.isExternalUser &&
            _isRestrictedForExternalUser(widget.navigation.currentScreen)) {
          widget.navigation.popTo('C1');
        }
      });
      return _buildConversationListPage();
    }
    switch (widget.navigation.currentScreen) {
      case 'QJ':
        return NativeQianjiHubPage(
          session: widget.session,
          onOpenCursorAccount: () => widget.navigation.go('QJC'),
          onOpenMeetingSupervise: () => widget.navigation.go('QJMM'),
          onOpenSessionSupervise: () => widget.navigation.go('QJSS'),
          onOpenKbSupervise: () => widget.navigation.go('QJKB'),
          onOpenEfficiencyAnalysis: () => widget.navigation.go('QJEA'),
          onOpenEfficiencyBossPreview: () => widget.navigation.go('QJEAB'),
          onOpenFundSecondment: widget.session.effectiveFundSecondmentAccess
              ? () => widget.navigation.go('QJFS')
              : null,
          onOpenCashFlow: widget.session.effectiveCashFlowAccess
              ? () => widget.navigation.go('QJCF')
              : null,
          onOpenMonthlyBill: widget.session.effectiveMonthlyBillAccess
              ? () => widget.navigation.go('QJMB')
              : null,
          onOpenTravel: () => widget.navigation.go('QJTR'),
          onOpenRobotHome: () {
            setState(() {
              _qjrOpenedFromChat = false;
              _qjrRobotKey = 'r_lighthouse';
            });
            widget.navigation.go('QJR');
          },
          onOpenRobot: (role) => unawaited(_openRobotFromCatalog(role)),
          onOpenDigitalEmployee: (item) {
            setState(() => _selectedDigitalEmployee = item);
            switch (item.screenId) {
              case 'QJMA':
              case 'QJTO':
              case 'QJAM':
                widget.navigation.go(item.screenId);
            }
          },
        );
      case 'QJMA':
      case 'QJTO':
      case 'QJAM':
        return _buildDigitalEmployeeChat(widget.navigation.currentScreen);
      case 'QJR':
        if (!widget.session.effectiveRobotAccess) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.go('QJ');
          });
          return const Scaffold(
            backgroundColor: DunesColors.bgApp,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return NativeRobotConsultListPage(
          key: ValueKey<String>('qjr-${_qjrRobotKey}'),
          session: widget.session,
          robotKey: _qjrRobotKey,
          onBack: () {
            final nav = widget.navigation;
            // 仅「从 IM 点咨询明细」回来才回机器人会话；NOVA 内进入应回 NOVA 首页。
            if (_qjrOpenedFromChat) {
              _qjrOpenedFromChat = false;
              if (_selectedRobot != null) {
                _markUserEnteredChat();
                if (nav.history.contains('CR')) {
                  nav.popTo('CR');
                } else {
                  _goChatScreen('CR');
                }
                return;
              }
            }
            if (nav.history.contains('QJ')) {
              nav.popTo('QJ');
            } else {
              nav.back();
            }
          },
          onCreate: () => widget.navigation.go('QJRA'),
          onOpenDetail: (consultId) {
            setState(() => _selectedRobotConsultId = consultId);
            widget.navigation.go('QJRC');
          },
        );
      case 'QJRA':
        if (!widget.session.effectiveRobotAccess) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.go('QJ');
          });
          return const Scaffold(
            backgroundColor: DunesColors.bgApp,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return NativeRobotConsultCreatePage(
          session: widget.session,
          robotKey: _qjrRobotKey,
          onBack: () {
            final nav = widget.navigation;
            if (nav.history.contains('QJR')) {
              nav.popTo('QJR');
            } else {
              nav.back();
            }
          },
          onStarted: (record) {
            setState(() => _selectedRobotConsultId = record.id);
            // 回到列表并打开详情，类似智能总结创建后的体验
            final nav = widget.navigation;
            if (nav.history.contains('QJR')) {
              nav.popTo('QJR');
            }
            widget.navigation.go('QJRC');
          },
        );
      case 'QJRC':
        if (!widget.session.effectiveRobotAccess) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.go('QJ');
          });
          return const Scaffold(
            backgroundColor: DunesColors.bgApp,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (_selectedRobotConsultId.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.go('QJR');
          });
          return const Scaffold(
            backgroundColor: DunesColors.bgApp,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return NativeRobotConsultDetailPage(
          session: widget.session,
          consultId: _selectedRobotConsultId,
          onBack: () {
            final nav = widget.navigation;
            if (nav.history.contains('QJR')) {
              nav.popTo('QJR');
            } else if (nav.history.contains('QJ')) {
              nav.popTo('QJ');
            } else {
              nav.back();
            }
          },
        );
      case 'QJC':
        return NativeQianjiCursorAccountPage(
          session: widget.session,
          onBack: widget.navigation.back,
          onOpenDetail: (bindingId) {
            if (bindingId <= 0) return;
            setState(() => _cursorBindingId = bindingId);
            widget.navigation.go('QJCD');
          },
        );
      case 'QJCD':
        if (_cursorBindingId <= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.go('QJC');
          });
          return const Scaffold(
            backgroundColor: DunesColors.bgApp,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return NativeQianjiCursorAccountDetailPage(
          key: ValueKey<String>('qianji-cursor-$_cursorBindingId'),
          session: widget.session,
          bindingId: _cursorBindingId,
          onBack: () {
            final nav = widget.navigation;
            if (nav.history.contains('QJC')) {
              nav.popTo('QJC');
            } else {
              nav.back();
            }
          },
        );
      case 'QJMM':
        return NativeQianjiMeetingSupervisePage(
          session: widget.session,
          onBack: widget.navigation.back,
          onOpenDetail: (meetingId) {
            if (meetingId <= 0) return;
            setState(() => _meetingId = meetingId);
            widget.navigation.go('QJMD');
          },
        );
      case 'QJSS':
        return NativeQianjiSessionSupervisePage(
          session: widget.session,
          onBack: widget.navigation.back,
        );
      case 'QJKB':
        return NativeQianjiKbSupervisePage(
          session: widget.session,
          onBack: widget.navigation.back,
        );
      case 'QJEA':
        return NativeQianjiEfficiencyPage(
          session: widget.session,
          onBack: widget.navigation.back,
        );
      case 'QJEAB':
        return NativeQianjiEfficiencyBossPreview(
          session: widget.session,
          onBack: widget.navigation.back,
          viewAll: widget.session.workSituationViewAll,
          viewerName: widget.session.displayName ?? '',
        );
      case 'QJTR':
        return NativeQianjiTravelPage(
          session: widget.session,
          onBack: widget.navigation.back,
        );
      case 'QJCF':
        if (!widget.session.effectiveCashFlowAccess) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.go('QJ');
          });
          return const Scaffold(
            backgroundColor: DunesColors.bgApp,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return NativeQianjiCashFlowBoardPage(
          session: widget.session,
          onBack: widget.navigation.back,
        );
      case 'QJMB':
        if (!widget.session.effectiveMonthlyBillAccess) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.go('QJ');
          });
          return const Scaffold(
            backgroundColor: DunesColors.bgApp,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return NativeQianjiMonthlyBillPage(
          session: widget.session,
          onBack: widget.navigation.back,
        );
      case 'QJFS':
        if (!widget.session.effectiveFundSecondmentAccess) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.go('QJ');
          });
          return const Scaffold(
            backgroundColor: DunesColors.bgApp,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return NativeQianjiFundSecondmentPage(
          session: widget.session,
          onBack: widget.navigation.back,
          onOpenDetail: (id) {
            if (id <= 0) return;
            setState(() => _fundSecondmentId = id);
            widget.navigation.go('QJFSD');
          },
        );
      case 'QJFSD':
        if (!widget.session.effectiveFundSecondmentAccess) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.go('QJ');
          });
          return const Scaffold(
            backgroundColor: DunesColors.bgApp,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (_fundSecondmentId <= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.go('QJFS');
          });
          return const Scaffold(
            backgroundColor: DunesColors.bgApp,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return NativeQianjiFundSecondmentDetailPage(
          key: ValueKey<String>('qianji-fund-$_fundSecondmentId'),
          session: widget.session,
          recordId: _fundSecondmentId,
          onBack: () {
            final nav = widget.navigation;
            if (nav.history.contains('QJFS')) {
              nav.popTo('QJFS');
            } else {
              nav.back();
            }
          },
          onOpenApproval: (row) {
            if (row.loanDocId <= 0) return;
            unawaited(
              showApprovalDetailOverlay(
                context: context,
                session: widget.session,
                share: ApprovalChatShare(
                  businessType: 'LOAN_REQUEST',
                  businessId: row.loanDocId,
                  title: row.code.isEmpty ? '借款申请单' : '借款申请单 ${row.code}',
                  templateKey: 'loan-request',
                  code: row.code,
                  status: 'APPROVED',
                ),
              ),
            );
          },
        );
      case 'QJMD':
        if (_meetingId <= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.go('QJMM');
          });
          return const Scaffold(
            backgroundColor: DunesColors.bgApp,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return NativeMeetingDetailPage(
          key: ValueKey<String>('qianji-meeting-$_meetingId'),
          session: widget.session,
          meetingId: _meetingId,
          readOnly: true,
          onBack: () {
            final nav = widget.navigation;
            if (nav.history.contains('QJMM')) {
              nav.popTo('QJMM');
            } else {
              nav.back();
            }
          },
        );
      case 'QJA':
        return const SizedBox.shrink();
      case 'CT1':
        // 每次进入使用独立 key，强制重建，避免复用一次性 Ticket。
        // 桌面端走 PC 单点（系统浏览器）；手机 APP 继续走 H5 WebView。
        final ctripKey = ValueKey<String>(
          'ctrip-${widget.navigation.history.length}-'
          '${widget.navigation.history.where((e) => e == 'CT1').length}',
        );
        void ctripBack() {
          if (widget.navigation.history.contains('QJA')) {
            widget.navigation.popTo('QJA');
          } else if (widget.navigation.canGoBack) {
            widget.navigation.back();
          } else {
            widget.navigation.popTo(isDesktopCommOnly ? 'QJA' : 'B2');
          }
        }
        if (isDesktopCommOnly) {
          return NativeCtripPCPage(
            key: ctripKey,
            session: widget.session,
            navigation: widget.navigation,
            onBack: ctripBack,
          );
        }
        return NativeCtripH5Page(
          key: ctripKey,
          session: widget.session,
          navigation: widget.navigation,
          embedded: false,
          onBack: ctripBack,
        );
      case 'XR1':
        final xrxsKey = ValueKey<String>(
          'xrxs-${widget.navigation.history.length}-'
          '${widget.navigation.history.where((e) => e == 'XR1').length}-'
          '${_xrxsLoginSid ?? ''}-${_xrxsLoginRole ?? ''}',
        );
        void xrxsBack() {
          if (widget.navigation.history.contains('XA1')) {
            widget.navigation.popTo('XA1');
          } else if (widget.navigation.history.contains('QJA')) {
            widget.navigation.popTo('QJA');
          } else if (widget.navigation.canGoBack) {
            widget.navigation.back();
          } else {
            widget.navigation.popTo(isDesktopCommOnly ? 'QJA' : 'B2');
          }
        }
        if (isDesktopCommOnly) {
          return NativeXrxsPCPage(
            key: xrxsKey,
            session: widget.session,
            navigation: widget.navigation,
            onBack: xrxsBack,
            loginSid: _xrxsLoginSid,
            loginRole: _xrxsLoginRole,
          );
        }
        return NativeXrxsH5Page(
          key: xrxsKey,
          session: widget.session,
          navigation: widget.navigation,
          onBack: xrxsBack,
          loginSid: _xrxsLoginSid,
          loginRole: _xrxsLoginRole,
        );
      case 'AM1':
        final amKey = ValueKey<String>(
          'am-${widget.navigation.history.length}-'
          '${widget.navigation.history.where((e) => e == 'AM1').length}-'
          '${_ssoAppKey ?? ''}',
        );
        void amBack() {
          if (widget.navigation.history.contains('QJA')) {
            widget.navigation.popTo('QJA');
          } else if (widget.navigation.canGoBack) {
            widget.navigation.back();
          } else {
            widget.navigation.popTo(isDesktopCommOnly ? 'QJA' : 'B2');
          }
        }
        return NativeAmSsoPage(
          key: amKey,
          session: widget.session,
          navigation: widget.navigation,
          appKey: _ssoAppKey ?? 'oa',
          title: _ssoAppTitle.isEmpty ? '免登' : _ssoAppTitle,
          onBack: amBack,
        );
      case 'QJD':
        final entity =
            _selectedQianjiEntity ?? QianjiStaticCatalog.entities.first;
        return NativeQianjiDetailPage(
          entity: entity,
          onBack: widget.navigation.back,
          onOpenIteration: (iteration) {
            setState(() {
              _selectedQianjiEntity = entity;
              _selectedQianjiIteration = iteration;
            });
            widget.navigation.go('QJI');
          },
        );
      case 'QJI':
        final entity =
            _selectedQianjiEntity ?? QianjiStaticCatalog.entities.first;
        final iteration =
            _selectedQianjiIteration ??
            QianjiStaticCatalog.detailFor(entity).iterations.first;
        return NativeQianjiIterationPage(
          entity: entity,
          iteration: iteration,
          onBack: widget.navigation.back,
        );
      case 'QJT':
        return NativeQianjiTeamPerfPage(
          onBack: widget.navigation.back,
          onOpenMyPerf: () => widget.navigation.go('QJP'),
        );
      case 'QJP':
        return NativeQianjiMyPerfPage(
          onBack: widget.navigation.back,
          onOpenTeamPerf: () => widget.navigation.go('QJT'),
        );
      case 'QJM':
        return NativeQianjiProjectsPage(
          onBack: widget.navigation.back,
          onOpenProject: (project) {
            setState(() => _selectedQianjiProject = project);
            widget.navigation.go('QJMT');
          },
        );
      case 'QJMT':
        final project =
            _selectedQianjiProject ?? QianjiProjectCatalog.joined.last;
        return NativeQianjiProjectTasksPage(
          project: project,
          onBack: widget.navigation.back,
          onOpenTask: (task) {
            setState(() {
              _selectedQianjiProject = project;
              _selectedQianjiTask = task;
            });
            widget.navigation.go('QJTD');
          },
        );
      case 'QJTD':
        final project =
            _selectedQianjiProject ?? QianjiProjectCatalog.joined.last;
        final task =
            _selectedQianjiTask ??
            QianjiProjectCatalog.detailFor(project).myTasks.first;
        return NativeQianjiTaskDetailPage(
          project: project,
          task: task,
          onBack: widget.navigation.back,
        );
      case 'LH':
        // Built via keep-alive in [build]; placeholder for switcher when unused.
        return const SizedBox.shrink();
      case 'LM':
        return _NativePlatformTreeShell(navigation: widget.navigation);
      case 'B2':
        return _NativeB2Page(
          session: widget.session,
          navigation: widget.navigation,
          commUnread: _commUnread,
          workbenchBadge: _workbenchBadge,
          workbenchRefresh: _workbenchRefresh,
          onOpenB14: _goB14,
          onOpenB3: _goB3,
          onOpenXflowForm: _openXflowFormFromB2,
          onOpenWorkbench: !isDesktopCommOnly && !widget.session.isExternalUser
              ? () => widget.navigation.go('QJA')
              : null,
          onLogout: widget.onLogout,
        );
      case 'B2P':
        return NativeUserWorkProfilePage(
          session: widget.session,
          onBack: widget.navigation.back,
          initialMonth: _workProfileMonth,
          onOpenWorkRhythmMonth: (month) {
            _workProfileMonth = month;
            widget.navigation.go('B2RHYTHM');
          },
          onOpenCollaborationMonth: (month) {
            _workProfileMonth = month;
            widget.navigation.go('B2COLLAB');
          },
          onOpenKnowledgeMonth: (month) {
            _workProfileMonth = month;
            widget.navigation.go('B2KNOWLEDGE');
          },
          onOpenBusinessMonth: (month) {
            _workProfileMonth = month;
            widget.navigation.go('B2BUSINESS');
          },
          onOpenPerformanceMonth: (month) {
            _workProfileMonth = month;
            widget.navigation.go('B2PERF');
          },
        );
      case 'B2RHYTHM':
        return NativeWorkProfileRhythmPage(
          session: widget.session,
          month: _workProfileMonth ?? DateTime.now(),
          onBack: widget.navigation.back,
          onOpenTask: (taskId) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (routeContext) => Scaffold(
                  body: SafeArea(
                    child: NativeTaskDetailView(
                      session: widget.session,
                      taskId: taskId,
                      onBack: () => Navigator.of(routeContext).pop(),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      case 'B2COLLAB':
        return NativeWorkProfileCollaborationPage(
          session: widget.session,
          month: _workProfileMonth,
          onBack: widget.navigation.back,
          onOpenFavorites: () => widget.navigation.go('CF'),
          onOpenConversation: (conversation) {
            if (conversation.kind == 'PRIVATE') {
              _openPrivateConversation(conversation);
            } else {
              _openGroupConversation(conversation);
            }
          },
        );
      case 'B2KNOWLEDGE':
        return NativeWorkProfileKnowledgePage(
          session: widget.session,
          month: _workProfileMonth ?? DateTime.now(),
          onBack: widget.navigation.back,
          onOpenDocument: (doc) {
            setState(() {
              _kbSelectedDocId = doc.id;
              _kbSelectedDoc = doc;
            });
            widget.navigation.go('K3');
          },
          onOpenMeeting: (meetingId) {
            if (meetingId <= 0) return;
            setState(() => _meetingId = meetingId);
            widget.navigation.go('MM');
          },
        );
      case 'B2BUSINESS':
        return NativeWorkProfileBusinessPage(
          session: widget.session,
          month: _workProfileMonth ?? DateTime.now(),
          onBack: widget.navigation.back,
          onOpenProposal: (item) =>
              _openProposalDetail(item, from: 'B2BUSINESS'),
        );
      case 'B2PERF':
        return NativeWorkProfilePerfPage(
          session: widget.session,
          onBack: widget.navigation.back,
        );
      case 'C1':
        return _buildConversationListPage();
      case 'AN1':
        return _buildAdministrativeNoticePage(
          showBackButton: !isDesktopCommOnly,
        );
      case 'AA1':
        return _buildApprovalAssistantPage();
      case 'AA2':
        return _buildApprovalAssistantPendingPage();
      case 'AA3':
        return _buildApprovalAssistantProposalPage();
      case 'TA1':
        return _buildTaskAssistantPage();
      case 'DA1':
        return _buildDriveAssistantPage();
      case 'XA1':
        return _buildXrxsAssistantPage();
      case 'WS1':
        return _buildWeeklySummaryPage();
      case 'RA1':
        return NativeReconciliationAssistantPage(
          key: ValueKey<int>(_selectedReconciliation?.id ?? 0),
          desktopMode: isDesktopCommOnly,
          session: widget.session,
          conversationHint:
              _selectedReconciliation ??
              const NativeConversation(
                id: 0,
                kind: 'RECONCILIATION_ASSISTANT',
                title: '对账助手',
                unreadCount: 0,
                preview: '',
                updatedAt: null,
              ),
          showBackButton: true,
          autoMarkRead: _userActivelyInChat,
          onBack: () {
            if (widget.navigation.history.contains('C1')) {
              widget.navigation.popTo('C1');
            } else {
              widget.navigation.back();
            }
          },
          onConversationRead: _handleConversationRead,
          onOpenWorkbenchDailyRecon: (date, {cardType = ''}) {
            _openDailyReconWorkbench(
              hint: _selectedReconciliation,
              asOfDate: date,
              cardType: cardType,
            );
          },
        );
      case 'FD1':
        return NativeDrivePage(
          key: ValueKey<int?>(_driveTargetItemId),
          session: widget.session,
          initialItemId: _driveTargetItemId,
          onBack: () {
            setState(() => _driveTargetItemId = null);
            if (widget.navigation.history.contains('DA1')) {
              _markUserEnteredChat();
              widget.navigation.popTo('DA1');
            } else if (widget.navigation.history.contains('QJA')) {
              widget.navigation.popTo('QJA');
            } else {
              widget.navigation.popTo('B2');
            }
          },
        );
      case 'AS1':
        return _buildAiSummaryHubPage();
      case 'AS2':
        return _buildAiSummaryCreatePage();
      case 'AS3':
        return _buildAiSummaryDetailPage();
      case 'Z2':
        return NativeMessageCenterPage(
          key: ValueKey<String>(
            'z2-${_messageCenterInitialTab ?? 'notice'}-'
            '${_messageCenterMarkAllOnEnter ? 'all' : 'one'}',
          ),
          session: widget.session,
          onBack: widget.navigation.back,
          onNotificationsRead: _handleNotificationsRead,
          onBroadcastRead: _handleConversationRead,
          initialTab: _messageCenterInitialTab,
          markAllReadOnEnter: _messageCenterMarkAllOnEnter,
        );
      case 'CF':
        return NativeFavoritesPage(
          session: widget.session,
          onBack: widget.navigation.back,
        );
      case 'C10':
        return NativeBroadcastPage(
          session: widget.session,
          conversationHint: _selectedBroadcast,
          onBack: widget.navigation.back,
          onConversationRead: _handleConversationRead,
        );
      case 'CR':
        if (_selectedRobot == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.back();
          });
          return const SizedBox.shrink();
        }
        return NativeRobotChatPage(
          key: ValueKey<int>(_selectedRobot!.id),
          session: widget.session,
          conversationHint: _selectedRobot!,
          showBackButton: true,
          autoMarkRead: _userActivelyInChat,
          onBack: () => _leaveChatToInbox(clearSelection: false),
          onConversationRead: _handleConversationRead,
          onOpenConsultList: _openRobotConsultListFromChat,
        );
      case 'C7':
        // 新建会话已深度合并进通讯录；保留 C7 路由以兼容旧入口。
        return NativeContactsPage(
          session: widget.session,
          initialGroupPickMode: true,
          onBack: widget.navigation.back,
          onOpenContact: (contact) {
            setState(() {
              _selectedContact = contact;
              _profileReturnScreen = null;
            });
            widget.navigation.go('C9');
          },
          onStartPrivateChat: _openPrivateByPeerId,
          onOpenGroupChat: _openGroupConversation,
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
          onOpenMember: (userId, displayName) {
            _openContactProfile(userId, displayName);
          },
          onOpenApproval: () => _goB14(),
          onExitedGroup: _handleExitedGroup,
          onChatSettingsChanged: _onPrivateChatSettingsChanged,
        );
      case 'C3':
        // 普通浏览由 keep-alive 层承载；此处仅构建建群多选实例。
        if (!_contactsGroupPickMode) {
          return const SizedBox.shrink();
        }
        final pickKey = _contactsInitialSelectedUserIds.toList()..sort();
        return NativeContactsPage(
          key: ValueKey<String>(
            'contacts-group-pick-$_contactsGroupPickMode-${pickKey.join(',')}',
          ),
          session: widget.session,
          initialGroupPickMode: _contactsGroupPickMode,
          initialSelectedUserIds: _contactsInitialSelectedUserIds,
          lockedSelectedUserIds: _contactsLockedSelectedUserIds,
          initialSelectedNames: _contactsInitialSelectedNames,
          onBack: () {
            setState(_clearContactsGroupPickState);
            widget.navigation.back();
          },
          onOpenContact: (contact) {
            setState(() {
              _clearContactsGroupPickState();
              _selectedContact = contact;
              _profileReturnScreen = null;
            });
            widget.navigation.go('C9');
          },
          onStartPrivateChat: _openPrivateByPeerId,
          onOpenGroupChat: (conv) {
            setState(_clearContactsGroupPickState);
            _openGroupConversation(conv);
          },
        );
      case 'C9':
        if (_selectedPrivate?.isSelfMemo == true) {
          return _buildSelfMemoSettingsPage();
        }
        final profileConvId = _profileReturnScreen == 'C5'
            ? _selectedPrivate?.id
            : null;
        return NativeContactProfilePage(
          session: widget.session,
          contactHint: _selectedContact,
          onBack: widget.navigation.back,
          onOpenPrivateChat: _openPrivateByPeerId,
          conversationId: profileConvId,
          onChatSettingsChanged: _onPrivateChatSettingsChanged,
          onCreateGroupWithContact: _startGroupFromContact,
          onOpenSearch: profileConvId == null
              ? null
              : (convId) {
                  setState(() {
                    _searchConversationId = convId;
                    _searchTitle =
                        '${_selectedPrivate?.displayTitle ?? '私聊'} · 搜索';
                    _searchReturnScreen = 'C5';
                    _focusMessageId = null;
                    _focusMessageHint = null;
                  });
                  widget.navigation.go('C12');
                },
        );
      case 'B13':
        return NativeApprovalPage(
          session: widget.session,
          onOpenProposal: (item) => _openProposalDetail(item, from: 'B13'),
          onBack: () => widget.navigation.popTo('B2'),
          workbenchRefresh: _workbenchRefresh,
        );
      case 'B1':
        return NativeMyApprovalWorkbenchPage(
          session: widget.session,
          onOpenProposal: (item) => _openProposalDetail(item, from: 'B1'),
          onBack: () => widget.navigation.popTo('B2'),
          workbenchRefresh: _workbenchRefresh,
        );
      case 'B14':
        return NativeMyInitiatedPage(
          session: widget.session,
          onOpenProposal: (item) => _openProposalDetail(item, from: 'B14'),
          onBack: () => widget.navigation.popTo('B2'),
          initialStatusFilter: _b14InitialFilter,
          workbenchRefresh: _workbenchRefresh,
        );
      case 'P1':
        return NativeMyCcProposalPage(
          session: widget.session,
          onOpenProposal: (item) => _openProposalDetail(item, from: 'P1'),
          onBack: () => widget.navigation.popTo('B2'),
          workbenchRefresh: _workbenchRefresh,
        );
      case 'B3':
        return NativeB3Page(
          session: widget.session,
          navigation: widget.navigation,
          onBack: _desktopSettingsChildReturnPending
              ? _returnToDesktopSettings
              : null,
          initialCategory: _b3InitialCategory,
          initialSearch: _b3SearchQuery,
          onCategoryChanged: (category) {
            _b3InitialCategory = category;
          },
          onSearchChanged: (query) {
            _b3SearchQuery = query;
          },
          onOpenForm: (templateKey) {
            _openProposalEntry(templateKey: templateKey, backScreen: 'B3');
          },
        );
      case 'XFP':
      case 'XFU':
      case 'XF':
        return NativeXflowProposalPage(
          session: widget.session,
          navigation: widget.navigation,
          templateKey: _xflowTemplateKey,
          editProposalId: _xflowEditProposalId,
          editBusinessType: _xflowEditBusinessType,
          backScreen: _xflowFormBackScreen,
          onDeleted: () {
            setState(() {
              _xflowEditProposalId = null;
              _xflowEditBusinessType = 'PROPOSAL';
            });
          },
          onSubmitted: (proposalId, businessType) {
            // 提交成功后回到「我发起的」，便于立即看到新单据。
            setState(() {
              _selectedTodoHint = null;
              _xflowEditProposalId = null;
              _xflowEditBusinessType = businessType.trim().isEmpty
                  ? 'PROPOSAL'
                  : businessType;
              _lastMyScreen = 'B14';
              _b14InitialFilter = null;
            });
            _goB14();
          },
        );
      case 'XFS':
        return NativeXflowSubmissionPage(
          key: ValueKey(
            'XFS-$_selectedSubmissionBusinessType-$_selectedSubmissionBusinessId',
          ),
          session: widget.session,
          navigation: widget.navigation,
          businessType: _selectedSubmissionBusinessType,
          businessId: _selectedSubmissionBusinessId,
          backScreen: _b10BackScreen,
          todoHint: _selectedTodoHint,
          onApprovalCompleted: () => _scheduleWorkbenchBadgeRefresh(),
          onOpenPendingItem: (item) =>
              _openProposalDetail(item, from: _b10BackScreen),
          onEdit: () {
            _openProposalEntry(
              templateKey: _xflowTemplateKey,
              backScreen: _b10BackScreen,
              editProposalId: _selectedSubmissionBusinessId,
              editBusinessType: _selectedSubmissionBusinessType,
            );
          },
        );
      case 'B10':
        return NativeB10Page(
          key: ValueKey('B10-$_selectedProposalId'),
          session: widget.session,
          navigation: widget.navigation,
          proposalId: _selectedProposalId,
          todoHint: _selectedTodoHint,
          backScreen: _b10BackScreen,
          onApprovalCompleted: () => _scheduleWorkbenchBadgeRefresh(),
          onOpenPendingItem: (item) =>
              _openProposalDetail(item, from: _b10BackScreen),
          onReedit: (proposalId) {
            _openProposalEntry(
              templateKey: XflowService.boundTemplateKeyForMenu(
                '/business/proposals/new',
              ),
              backScreen: _b10BackScreen,
              editProposalId: proposalId,
            );
          },
        );
      case 'C4':
        return NativeNovaPage(
          session: widget.session,
          onBack: () {
            NovaBackgroundCoordinator.instance.clearPendingCommBadgeBump();
            setState(() {
              _novaFocusConversationId = null;
              _novaFocusMessageId = null;
            });
            widget.navigation.popTo('C1');
          },
          onHistory: () => widget.navigation.go('C11'),
          onOpenKb: () => widget.navigation.go('K1'),
          onOpenMeeting: () {
            widget.navigation.go('MM-L');
          },
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
              // 历史会话恢复完整内容后默认滚动到底部，不定位到单条中间消息。
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
          onOpenDoc: (doc) {
            setState(() {
              _kbSelectedDocId = doc.id;
              _kbSelectedDoc = doc;
            });
            widget.navigation.go('K3');
          },
        );
      case 'K3':
        return NativeKbDocPage(
          session: widget.session,
          navigation: widget.navigation,
          docId: _kbSelectedDocId ?? '',
          initialDoc: _kbSelectedDoc,
        );
      case 'K2':
        return NativeKbChatPage(
          session: widget.session,
          navigation: widget.navigation,
          chatKind: _kbChatKind,
          docId: _kbChatDocId,
        );
      case 'WX':
        return NativeWechatBotPage(
          session: widget.session,
          onBack: _desktopSettingsChildReturnPending
              ? _returnToDesktopSettings
              : widget.navigation.back,
        );
      case 'MM-L':
        return NativeMeetingListPage(
          session: widget.session,
          onBack: widget.navigation.leaveMeetingList,
          onCreate: () => widget.navigation.go('MM0'),
          onOpenDetail: (meetingId) {
            if (meetingId <= 0) return;
            setState(() => _meetingId = meetingId);
            widget.navigation.go('MM');
          },
        );
      case 'MM0':
        return NativeMeetingCreatePage(
          session: widget.session,
          navigation: widget.navigation,
          onBack: widget.navigation.leaveMeetingCreate,
          onCreated: (meetingId, {required isDraft}) {
            if (meetingId <= 0) return;
            // 新建后列表必须重新拉取，避免缓存漏掉新会议。
            MeetingListCache.instance.invalidate();
            setState(() => _meetingId = meetingId);
            final nav = widget.navigation;
            if (isDraft) {
              if (nav.history.contains('MM-L')) {
                nav.popTo('MM-L');
              } else {
                nav.replaceTop('MM-L');
              }
            } else {
              nav.replaceTop('MM');
            }
          },
        );
      case 'MM':
        if (_meetingId <= 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.navigation.go('MM-L');
          });
          return const Scaffold(
            backgroundColor: DunesColors.bgApp,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return NativeMeetingDetailPage(
          key: ValueKey<int>(_meetingId),
          session: widget.session,
          meetingId: _meetingId,
          onBack: () {
            final nav = widget.navigation;
            if (nav.history.contains('MM-L')) {
              nav.popTo('MM-L');
            } else {
              nav.back();
            }
          },
        );
      case 'C2':
        return NativeGroupChatPage(
          session: widget.session,
          conversationHint: _selectedGroup,
          focusMessageId: _focusMessageId,
          focusMessageHint: _focusMessageHint,
          autoMarkRead: _userActivelyInChat,
          onBack: () => _leaveChatToInbox(clearSelection: false),
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
          onOpenUser: _openContactProfile,
          onOpenAiSummary: _onOpenAiSummaryFromChat,
          onOpenApprovalShare: (share) =>
              _openApprovalFromChat(share, from: 'C2'),
          onConversationRead: _handleConversationRead,
          onClearFocusMessage: _clearChatFocusMessage,
        );
      case 'C5':
        return NativePrivateChatPage(
          session: widget.session,
          conversationHint: _selectedPrivate,
          peerUserIdHint: _selectedPrivatePeerUserId,
          focusMessageId: _focusMessageId,
          focusMessageHint: _focusMessageHint,
          autoMarkRead: _userActivelyInChat,
          onBack: () => _leaveChatToInbox(clearSelection: false),
          onOpenProfile: () {
            if (_selectedPrivate?.isSelfMemo == true) {
              setState(() => _profileReturnScreen = 'C5');
              widget.navigation.go('C9');
              return;
            }
            final peerId =
                _selectedPrivate?.peerUserId ?? _selectedPrivatePeerUserId;
            if (peerId == null || peerId <= 0) return;
            _openContactProfile(
              peerId,
              _selectedPrivate?.peerDisplayName ??
                  _selectedPrivate?.title ??
                  '',
            );
          },
          onOpenUser: _openContactProfile,
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
          onOpenAiSummary: _onOpenAiSummaryFromChat,
          onOpenApprovalShare: (share) =>
              _openApprovalFromChat(share, from: 'C5'),
          onConversationRead: _handleConversationRead,
          onClearFocusMessage: _clearChatFocusMessage,
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
            // 从群聊信息 C6 定位时切回 C2，而不是停留在群信息页。
            final returnScreen = _searchReturnScreen == 'C6'
                ? 'C2'
                : _searchReturnScreen == 'C9'
                ? 'C5'
                : _searchReturnScreen;
            if (returnScreen == 'C5' || returnScreen == 'C2') {
              _markUserEnteredChat();
            }
            // 从历史定位回会话时弹出 C12，避免返回键回到「查找聊天内容」。
            if (widget.navigation.history.contains(returnScreen)) {
              widget.navigation.popTo(returnScreen);
            } else {
              _goChatScreen(returnScreen);
            }
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

  @override
  Widget build(BuildContext context) {
    final screen = widget.navigation.currentScreen;
    final depth = widget.navigation.history.length;
    final previousScreen = _lastScreen;
    final isBack = previousScreen != null && depth < _lastHistoryDepth;

    if (isDesktopCommOnly && _desktopSettingsOpen) {
      return _wrapWithMainNavigation(
        NativeDesktopSettingsPage(
          onBack: () {
            if (!mounted) return;
            setState(() {
              _desktopSettingsOpen = false;
              _desktopSettingsChildReturnPending = false;
            });
          },
          onOpenTextScale: () => unawaited(_openDesktopTextScalePicker()),
          onCheckForUpdates: isWindowsDesktopCommOnly
              ? () => unawaited(_checkDesktopAppUpdate())
              : null,
          onScanWorkstation: !isWindowsDesktopCommOnly
              ? () {
                  _leaveDesktopSettingsForChild();
                  unawaited(_openDesktopQrLoginScanner(returnToSettings: true));
                }
              : null,
          onOpenWechatBot: !widget.session.isExternalUser
              ? () {
                  _leaveDesktopSettingsForChild();
                  widget.navigation.go('WX');
                }
              : null,
          onClearCache: () => unawaited(_clearDesktopLocalCache()),
          onStartProposal: !widget.session.isExternalUser
              ? () {
                  _leaveDesktopSettingsForChild();
                  _goB3();
                }
              : null,
          onLogout: widget.onLogout == null
              ? null
              : () => unawaited(_confirmDesktopLogout()),
        ),
        screen: screen,
      );
    }

    // Windows 桌面：白名单外的屏拉回会话首页。
    if (isWindowsDesktopCommOnly && !isWindowsAllowedCommScreen(screen)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!isWindowsAllowedCommScreen(widget.navigation.currentScreen)) {
          widget.navigation.popTo('C1');
        }
      });
      _lastScreen = 'C1';
      _lastHistoryDepth = depth;
      if (isWideChatLayout(context)) {
        _commDualMounted = true;
        return _buildCommDualKeepAlive(active: true);
      }
      return _wrapWithMainNavigation(
        _buildConversationListPage(),
        screen: 'C1',
      );
    }

    final wide = isWideChatLayout(context);
    final dualNow = wide && _isDualPaneChatRoute(screen);
    final dualPrev =
        previousScreen != null && wide && _isDualPaneChatRoute(previousScreen);

    // 路由变化时重算 active-view（CR→QJR / 切会话等），避免仍登记旧会话导致推送被吞。
    if (previousScreen != null && previousScreen != screen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncActiveViewReport();
      });
    }

    // 宽屏双栏内部（C1↔C2↔C5↔C6↔C12↔C13↔AS*↔会话内C9）仍瞬时切换聊天窗；
    // 进出通讯子页（通知/通讯录等）走整页滑动。
    if (dualNow) {
      _commDualMounted = true;
    }
    // 双栏内部切会话：仍走统一 Stack，保留灯塔/双栏 keep-alive，避免 dispose。
    if (dualNow && dualPrev) {
      _lastScreen = screen;
      _lastHistoryDepth = depth;
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildCommDualKeepAlive(active: true),
          if (_lighthouseMounted)
            Offstage(
              offstage: true,
              child: TickerMode(
                enabled: false,
                child: NativeLighthousePage(
                  key: const ValueKey<String>('lighthouse-keep-alive'),
                  session: widget.session,
                  navigation: widget.navigation,
                  commUnread: _commUnread,
                  workbenchBadge: _workbenchBadge,
                  active: false,
                ),
              ),
            ),
          if (_workbenchMounted) _buildWorkbenchKeepAlive(active: false),
        ],
      );
    }

    final useSlide =
        (_isChatRoute(screen) && _isChatRoute(previousScreen)) ||
        (_isMyRoute(screen) && _isMyRoute(previousScreen)) ||
        (_isQianjiRoute(screen) && _isQianjiRoute(previousScreen));
    final isLighthouse = screen == 'LH';
    final isInbox = screen == 'C1';
    final isWorkbench = screen == 'QJA';
    // APP：工作台从「我的」右侧滑入，底下继续保留 B2；PC 工作台是独立 Tab，仍走 keep-alive 显隐。
    final workbenchAsSlideOver = isWorkbench && !isDesktopCommOnly;
    // 建群多选仍走 AnimatedSwitcher；普通通讯录用 keep-alive 保滚动。
    final isContacts = screen == 'C3' && !_contactsGroupPickMode;
    if (isLighthouse) {
      _lighthouseMounted = true;
    }
    if (isInbox && !isDesktopCommOnly) {
      _inboxMounted = true;
    }
    if (isContacts) {
      _contactsMounted = true;
    }
    if (isWorkbench) {
      _workbenchMounted = true;
    }
    // 双栏 / 灯塔 / 会话列表 / 通讯录 / 工作台由 keep-alive 承载；此处占位避免 AnimatedSwitcher 再造一份。
    // APP 打开工作台时 AnimatedSwitcher 继续渲染「我的」底页，配合右侧滑入。
    final switcherScreenId = workbenchAsSlideOver ? 'B2' : screen;
    final currentScreen = dualNow
        ? const SizedBox.shrink()
        : (isLighthouse ||
              isInbox ||
              isContacts ||
              (isWorkbench && isDesktopCommOnly))
        ? const SizedBox.shrink()
        : workbenchAsSlideOver
        ? _buildMyWorkbenchUnderlay()
        : _buildCurrentScreen(context);
    final child = KeyedSubtree(
      key: ValueKey<String>(
        dualNow ? 'dual-$screen' : 'screen-$switcherScreenId',
      ),
      child: currentScreen,
    );

    _lastScreen = screen;
    _lastHistoryDepth = depth;

    final animatedContent = AnimatedSwitcher(
      duration: useSlide ? const Duration(milliseconds: 280) : Duration.zero,
      reverseDuration: useSlide
          ? const Duration(milliseconds: 240)
          : Duration.zero,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          // 返回时让离场页位于上层向右退出，避免它在入场页右侧留下残影。
          children: isBack
              ? [?currentChild, ...previousChildren]
              : [...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (transitionChild, animation) {
        final isIncoming = transitionChild.key == child.key;
        // AnimatedSwitcher 会反向驱动离场 child 的 animation：离场 Tween 必须
        // 以「目标位置 -> 原位」定义，才能从原位自然滑出而不是闪现/重复一帧。
        final begin = !useSlide
            ? Offset.zero
            : isIncoming
            ? (isBack ? const Offset(-0.18, 0) : const Offset(1, 0))
            : (isBack ? const Offset(1, 0) : const Offset(-0.18, 0));
        final end = Offset.zero;
        return SlideTransition(
          position: Tween<Offset>(begin: begin, end: end).animate(animation),
          child: transitionChild,
        );
      },
      child: child,
    );

    final body = Stack(
      fit: StackFit.expand,
      children: [
        if (_commDualMounted) _buildCommDualKeepAlive(active: dualNow),
        if (_lighthouseMounted)
          Offstage(
            offstage: !isLighthouse,
            child: TickerMode(
              enabled: isLighthouse,
              child: NativeLighthousePage(
                key: const ValueKey<String>('lighthouse-keep-alive'),
                session: widget.session,
                navigation: widget.navigation,
                commUnread: _commUnread,
                workbenchBadge: _workbenchBadge,
                active: isLighthouse,
              ),
            ),
          ),
        // 手机单栏会话列表：进出会话不销毁，返回时保持下滑位置。
        // 注意：不能用 Offstage——offstage 会以 0 尺寸布局，ListView 偏移会被钳成 0。
        // 用 Opacity + IgnorePointer 隐藏，仍按全尺寸布局，滚动位置才能保住。
        if (_inboxMounted && !dualNow && !isDesktopCommOnly)
          Positioned.fill(
            child: TickerMode(
              enabled: isInbox,
              child: IgnorePointer(
                ignoring: !isInbox,
                child: Opacity(
                  opacity: isInbox ? 1 : 0,
                  child: _buildConversationListPage(
                    listVisible: isInbox,
                    useKeepAliveKey: true,
                  ),
                ),
              ),
            ),
          ),
        // 通讯录：进名片（C9）再返回不销毁，保留列表位置。
        if (_contactsMounted && !dualNow)
          Positioned.fill(
            child: TickerMode(
              enabled: isContacts,
              child: IgnorePointer(
                ignoring: !isContacts,
                child: Opacity(
                  opacity: isContacts ? 1 : 0,
                  child: _buildContactsBrowsePage(useKeepAliveKey: true),
                ),
              ),
            ),
          ),
        if (!isLighthouse && !dualNow && !(isWorkbench && isDesktopCommOnly))
          animatedContent,
        // 须叠在「我的」之上，否则 APP 侧滑展开后仍被 B2 挡住、看起来像点不动。
        if (_workbenchMounted) _buildWorkbenchKeepAlive(active: isWorkbench),
      ],
    );
    // 双栏已自带侧栏，避免再套一层主导航。
    if (dualNow) {
      return body;
    }
    return _wrapWithMainNavigation(body, screen: screen);
  }

  bool _isChatRoute(String? screen) {
    return const <String>{
      // 通讯板块全链路：消息 / 群聊 / 通讯录 / NOVA / 私聊 / 群信息 /
      // 新建 / 通话 / 名片 / 广播 / AI 历史 / 搜索 / 媒体 / 通知。
      'C1',
      'C2',
      'C3',
      'C4',
      'C5',
      'C6',
      'C7',
      'C8',
      'C9',
      'C10',
      'C11',
      'C12',
      'C13',
      'CR',
      'CF',
      'TA1',
      'DA1',
      'XA1',
      'AN1',
      'WS1',
      'Z2',
      'AS1',
      'AS2',
      'AS3',
      'AA1',
      'AA2',
      'AA3',
      'RA1',
    }.contains(screen);
  }

  bool _isMyRoute(String? screen) {
    return const <String>{
      'B2',
      'B2P',
      'B2RHYTHM',
      'B2COLLAB',
      'B2KNOWLEDGE',
      'B2BUSINESS',
      'B2PERF',
      'B1',
      'B3',
      'B10',
      'B13',
      'B14',
      'P1',
      'XFP',
      'XFU',
      'XF',
      'XFS',
      'K1',
      'K2',
      'K3',
      'MM-L',
      'MM0',
      'MM',
      'WX',
      'QJT',
      'QJP',
      'QJM',
      'QJMT',
      'QJTD',
    }.contains(screen);
  }

  bool _isQianjiRoute(String? screen) {
    return const <String>{
      'QJ',
      'QJC',
      'QJCD',
      'QJD',
      'QJI',
      'QJA',
      'QJT',
      'QJP',
      'QJM',
      'QJMT',
      'QJTD',
      'QJMM',
      'QJMD',
      'QJMA',
      'QJTO',
      'QJAM',
      'QJSS',
      'QJKB',
      'QJEA',
      'QJEAB',
      'QJFS',
      'QJFSD',
      'QJTR',
      'QJCF',
      'QJMB',
      'QJR',
      'QJRA',
      'QJRC',
    }.contains(screen);
  }

  /// PC：任意业务页保留侧边主导航；宽屏通讯双栏已自带侧栏，不重复包裹。
  /// APP：仅在主 Tab 根页显示底部栏，进入子页后隐藏（恢复非固定行为）。
  Widget _wrapWithMainNavigation(Widget content, {required String screen}) {
    final tabBar = DunesMainTabBar(
      navigation: widget.navigation,
      activeScreen: _desktopSettingsOpen
          ? '__desktop_settings__'
          : _mainTabScreenFor(screen),
      axis: isDesktopCommOnly ? Axis.vertical : Axis.horizontal,
      commUnread: _commUnread,
      workbenchBadge: _workbenchBadge,
      lighthouseAccess: widget.session.lighthouseAccess,
      qianjiAccess: widget.session.effectiveQianjiAccess,
      qianjiAdminAccess: widget.session.effectiveQianjiAdminAccess,
      chatOnlyMode: widget.session.isExternalUser,
      onSwitchMainTab: _switchMainTab,
      onDesktopSettingsTap: isDesktopCommOnly ? _openDesktopSettings : null,
    );

    if (isDesktopCommOnly) {
      return ColoredBox(
        color: DunesColors.bgApp,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tabBar,
            Expanded(child: content),
          ],
        ),
      );
    }

    // APP：始终保持 Column > Expanded(content) 结构，避免进出子页时
    // 卸掉 AnimatedSwitcher 导致滑动动画丢失（此前直接 return content 会瞬切）。
    return ColoredBox(
      color: DunesColors.bgApp,
      child: Column(
        children: [
          Expanded(child: content),
          if (_showsAppBottomTabBar(screen)) tabBar,
        ],
      ),
    );
  }

  /// APP 底部 Tab 仅出现在主板块根页。
  bool _showsAppBottomTabBar(String screen) {
    return screen == 'C1' ||
        screen == 'B2' ||
        screen == 'QJ' ||
        screen == 'LH' ||
        screen == 'LM';
  }

  String _mainTabScreenFor(String screen) {
    if (!isDesktopCommOnly &&
        (screen == 'QJA' ||
            screen == 'CT1' ||
            screen == 'XR1' ||
            screen == 'AM1')) {
      return 'B2';
    }
    // 企业微盘从工作台进入：PC 归工作台 Tab，APP 归「我的」。
    if (screen == 'FD1') return isDesktopCommOnly ? 'QJA' : 'B2';
    // 会话入口的行政通知归属通讯 Tab；工作台发布走 embedded，不走 AN1 路由。
    if (screen == 'AN1') return isDesktopCommOnly ? 'C1' : 'B2';
    if (_isMyRoute(screen)) return 'B2';
    if (screen == 'QJ' ||
        screen == 'QJC' ||
        screen == 'QJCD' ||
        screen == 'QJD' ||
        screen == 'QJI' ||
        screen == 'QJMM' ||
        screen == 'QJMD' ||
        screen == 'QJMA' ||
        screen == 'QJTO' ||
        screen == 'QJAM' ||
        screen == 'QJSS' ||
        screen == 'QJKB' ||
        screen == 'QJEA' ||
        screen == 'QJEAB' ||
        screen == 'QJFS' ||
        screen == 'QJFSD' ||
        screen == 'QJTR' ||
        screen == 'QJCF' ||
        screen == 'QJMB' ||
        screen == 'QJR' ||
        screen == 'QJRA' ||
        screen == 'QJRC' ||
        screen == 'QJT' ||
        screen == 'QJP' ||
        screen == 'QJM' ||
        screen == 'QJMT' ||
        screen == 'QJTD') {
      return 'QJ';
    }
    if (screen == 'QJA' ||
        screen == 'CT1' ||
        screen == 'XR1' ||
        screen == 'AM1') {
      return 'QJA';
    }
    if (screen == 'LH' || screen == 'LM') return 'LH';
    return 'C1';
  }

  /// 主 Tab 在板块之间切换时，保留「我的 / NOVA」最后打开的子页面。
  void _switchMainTab(String screen) {
    if (_desktopSettingsOpen || _desktopSettingsChildReturnPending) {
      setState(() {
        _desktopSettingsOpen = false;
        _desktopSettingsChildReturnPending = false;
      });
    }
    final current = widget.navigation.currentScreen;
    final currentTab = _mainTabScreenFor(current);

    if (_isMyRoute(current)) {
      _lastMyScreen = current;
    }
    // 离开 NOVA 子树时记住位置。工作台 QJA 用 keep-alive 保内页，不靠导航栈恢复。
    if (currentTab == 'QJ' && screen != 'QJ') {
      _lastQianjiScreen = current;
    }

    if (screen == 'B2') {
      final target = _isMyRoute(_lastMyScreen) ? _lastMyScreen : 'B2';
      if (current != target) {
        widget.navigation.go('B2');
        if (target != 'B2') {
          widget.navigation.go(target);
        }
      }
      return;
    }

    if (screen == 'QJ') {
      // 从其它板块回到 NOVA：恢复上次子页；已在 NOVA 内再点 Tab → 回首页。
      if (currentTab != 'QJ') {
        setState(() => _qjrOpenedFromChat = false);
        _restoreQianjiStack(_resolveLastQianjiScreen());
      } else {
        widget.navigation.switchMainTab('QJ');
      }
      return;
    }

    widget.navigation.switchMainTab(screen);
  }

  String _resolveLastQianjiScreen() {
    final last = _lastQianjiScreen;
    if (!_isNovaTabScreen(last)) return 'QJ';
    if (last == 'QJRC' && _selectedRobotConsultId.isEmpty) return 'QJR';
    if (last == 'QJCD' && _cursorBindingId <= 0) return 'QJC';
    if (last == 'QJFSD' && _fundSecondmentId <= 0) return 'QJFS';
    if (last == 'QJI' && _selectedQianjiEntity == null) return 'QJD';
    if (last == 'QJTD' && _selectedQianjiTask == null) {
      return _selectedQianjiProject == null ? 'QJM' : 'QJMT';
    }
    if (last == 'QJMT' && _selectedQianjiProject == null) return 'QJM';
    return last;
  }

  bool _isNovaTabScreen(String? screen) {
    return const <String>{
      'QJ',
      'QJC',
      'QJCD',
      'QJD',
      'QJI',
      'QJMM',
      'QJMD',
      'QJMA',
      'QJTO',
      'QJAM',
      'QJSS',
      'QJKB',
      'QJEA',
      'QJEAB',
      'QJFS',
      'QJFSD',
      'QJTR',
      'QJCF',
      'QJMB',
      'QJR',
      'QJRA',
      'QJRC',
      'QJT',
      'QJP',
      'QJM',
      'QJMT',
      'QJTD',
    }.contains(screen);
  }

  bool _isNovaRestrictedScreen(String? screen) {
    return screen == 'C4' || screen == 'C11' || _isNovaTabScreen(screen);
  }

  bool _isRestrictedForExternalUser(String? screen) {
    return _isNovaRestrictedScreen(screen) ||
        screen == 'Z2' ||
        screen == 'C10' ||
        screen == 'AS1' ||
        screen == 'AS2' ||
        screen == 'AS3';
  }

  /// 重建 NOVA 导航链，保证返回键能逐级回到列表 / 首页。
  void _restoreQianjiStack(String target) {
    final nav = widget.navigation;
    if (nav.currentScreen == target) return;

    final chain = switch (target) {
      'QJR' => const ['QJ', 'QJR'],
      'QJRA' => const ['QJ', 'QJR', 'QJRA'],
      'QJRC' => const ['QJ', 'QJR', 'QJRC'],
      'QJC' => const ['QJ', 'QJC'],
      'QJCD' => const ['QJ', 'QJC', 'QJCD'],
      'QJMM' => const ['QJ', 'QJMM'],
      'QJMD' => const ['QJ', 'QJMM', 'QJMD'],
      'QJMA' => const ['QJ', 'QJMA'],
      'QJTO' => const ['QJ', 'QJTO'],
      'QJAM' => const ['QJ', 'QJAM'],
      'QJSS' => const ['QJ', 'QJSS'],
      'QJKB' => const ['QJ', 'QJKB'],
      'QJEA' => const ['QJ', 'QJEA'],
      'QJEAB' => const ['QJ', 'QJEAB'],
      'QJTR' => const ['QJ', 'QJTR'],
      'QJCF' => const ['QJ', 'QJCF'],
      'QJMB' => const ['QJ', 'QJMB'],
      'QJFS' => const ['QJ', 'QJFS'],
      'QJFSD' => const ['QJ', 'QJFS', 'QJFSD'],
      'QJD' => const ['QJ', 'QJD'],
      'QJI' => const ['QJ', 'QJD', 'QJI'],
      'QJM' => const ['QJ', 'QJM'],
      'QJMT' => const ['QJ', 'QJM', 'QJMT'],
      'QJTD' => const ['QJ', 'QJM', 'QJMT', 'QJTD'],
      'QJT' => const ['QJ', 'QJT'],
      'QJP' => const ['QJ', 'QJP'],
      'QJ' => const ['QJ'],
      _ => target == 'QJ' ? const ['QJ'] : <String>['QJ', target],
    };

    for (final s in chain) {
      if (nav.currentScreen != s) {
        nav.go(s);
      }
    }
  }

  /// 进入「我发起的(B14)」并可选预置筛选（如「待发起」用于代发起人入口）。
  void _goB14({String? filter}) {
    setState(() {
      _b14InitialFilter = filter;
      _lastMyScreen = 'B14';
    });
    // 先回到「我的」再进列表，避免从新建表单提交后返回又跳回表单页。
    widget.navigation.popTo('B2');
    widget.navigation.go('B14');
  }

  void _goB3({String category = 'biz'}) {
    setState(() {
      _b3InitialCategory = category;
      // 从入口重新进入时清空搜索；从表单返回仍走 B3 路由，保留 _b3SearchQuery。
      _b3SearchQuery = '';
    });
    widget.navigation.go('B3');
  }

  void _openProposalEntry({
    required String templateKey,
    required String backScreen,
    int? editProposalId,
    String editBusinessType = 'PROPOSAL',
  }) {
    setState(() {
      _xflowTemplateKey = templateKey;
      _xflowEditProposalId = editProposalId;
      _xflowEditBusinessType = editBusinessType;
      _xflowFormBackScreen = backScreen;
    });
    widget.navigation.go('XFP');
  }

  void _openXflowFormFromB2(String templateKey) {
    _openProposalEntry(templateKey: templateKey, backScreen: 'B2');
  }

  void _openProposalDetail(XflowProposalItem item, {required String from}) {
    // 「我发起的」列表点击草稿 → 进入可继续填写的表单（与提交页一致），并可删除草稿。
    if (from == 'B14' && item.status.toUpperCase() == 'DRAFT') {
      final templateKey = (item.templateKey ?? '').trim().isNotEmpty
          ? item.templateKey!.trim()
          : XflowService.boundTemplateKeyForMenu('/business/proposals/new');
      _openProposalEntry(
        templateKey: templateKey,
        backScreen: from,
        editProposalId: item.id,
        editBusinessType: item.businessType,
      );
      return;
    }
    if (item.businessType.toUpperCase() != 'PROPOSAL') {
      final bid = item.todoHint?.businessId ?? 0;
      setState(() {
        _selectedSubmissionBusinessType = item.businessType;
        _selectedSubmissionBusinessId = bid > 0 ? bid : item.id;
        _xflowTemplateKey = item.templateKey ?? '';
        _b10BackScreen = from;
        _selectedTodoHint = item.todoHint;
      });
      widget.navigation.go('XFS');
      return;
    }
    setState(() {
      _selectedProposalId = item.id;
      _selectedTodoHint = item.todoHint;
      _b10BackScreen = from;
    });
    widget.navigation.go('B10');
  }

  /// IM 审批卡片：不拦权限；若当前用户有 OPEN todo，详情页会自动进入可审批态。
  /// 用覆盖层打开（PC 对话框 / APP 推页），避免切屏导致会话被重建刷新。
  /// 返回的 Future 在详情关闭后完成，便于调用方刷新列表。
  Future<void> _openApprovalFromChat(
    ApprovalChatShare share, {
    required String from,
  }) {
    if (share.businessType.toUpperCase() == 'PROPOSAL_INTAKE') {
      return showProposalIntakeOverlay(
        context: context,
        session: widget.session,
        proposalId: share.businessId,
      );
    }
    return showApprovalDetailOverlay(
      context: context,
      session: widget.session,
      share: share,
      onApprovalCompleted: () => _scheduleWorkbenchBadgeRefresh(),
      onEditSubmission: (item) {
        final templateKey = (item.templateKey ?? '').trim().isNotEmpty
            ? item.templateKey!.trim()
            : _xflowTemplateKey;
        _openProposalEntry(
          templateKey: templateKey,
          backScreen: from,
          editProposalId: item.id,
          editBusinessType: item.businessType,
        );
      },
      onReeditProposal: (proposalId) {
        _openProposalEntry(
          templateKey: XflowService.boundTemplateKeyForMenu(
            '/business/proposals/new',
          ),
          backScreen: from,
          editProposalId: proposalId,
        );
      },
    );
  }

  void _openDesktopSettings() {
    if (!isDesktopCommOnly || !mounted) return;
    setState(() {
      _desktopSettingsOpen = true;
      _desktopSettingsChildReturnPending = false;
    });
  }

  void _leaveDesktopSettingsForChild() {
    if (!mounted) return;
    setState(() {
      _desktopSettingsOpen = false;
      _desktopSettingsChildReturnPending = true;
    });
  }

  void _returnToDesktopSettings() {
    if (!mounted) return;
    if (widget.navigation.canGoBack) {
      widget.navigation.back();
    }
    setState(() {
      _desktopSettingsOpen = true;
      _desktopSettingsChildReturnPending = false;
    });
  }

  Future<void> _openDesktopQrLoginScanner({
    bool returnToSettings = false,
  }) async {
    if (_desktopQrLoginOpening) return;
    setState(() => _desktopQrLoginOpening = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => QrLoginScanPage(session: widget.session),
        ),
      );
    } finally {
      if (mounted) setState(() => _desktopQrLoginOpening = false);
    }
    if (returnToSettings && mounted) {
      setState(() {
        _desktopSettingsOpen = true;
        _desktopSettingsChildReturnPending = false;
      });
    }
  }

  Future<void> _checkDesktopAppUpdate() async {
    showDunesToast(context, '正在检查更新…');
    final result = await AppUpdateService.instance.checkUpdate();
    if (!mounted) return;
    if (result == null) {
      showDunesToast(context, '暂无法检查更新，请稍后重试');
      return;
    }
    if (!result.updateAvailable) {
      AppUpdateNotifier.instance.clear();
      showDunesToast(context, '当前已是最新版本');
      return;
    }
    AppUpdateNotifier.instance.offer(result);
    await showAppUpdateDialog(context, result);
  }

  Future<void> _clearDesktopLocalCache() async {
    var cleared = false;
    try {
      await InboxHiddenStorage.save(const <String, InboxHiddenEntry>{});
      await NovaWebStorage.clear(widget.session.userId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('xflow_draft_sales-proposal');
      cleared = true;
    } catch (_) {}
    if (!mounted) return;
    showDunesToast(context, cleared ? '本地缓存已清除' : '清除本地缓存失败，请稍后重试');
  }

  Future<void> _openDesktopTextScalePicker() async {
    final controller = AppTextScaleController.instance;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '字体大小',
                  style: DunesTypography.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '调整后将作用于整个 App',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.text3,
                  ),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < AppTextScaleController.presets.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      AppTextScaleController.labels[i],
                      style: DunesTypography.sans(
                        fontSize: 15 * AppTextScaleController.presets[i],
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                    trailing: i == controller.presetIndex
                        ? const Icon(
                            Icons.check_rounded,
                            color: Color(0xFF7E64BD),
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, i),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    await controller.setPresetIndex(picked);
    if (!mounted) return;
    showDunesToast(context, '已切换为「${AppTextScaleController.labels[picked]}」字号');
  }

  Future<void> _confirmDesktopLogout() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('确认退出登录？'),
            content: const Text('退出后需要重新登录才能继续使用。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('退出登录'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed && mounted) widget.onLogout?.call();
  }
}

/// 沙丘平台生态树（与灯塔同栈，主导航由宿主统一提供）。
class _NativePlatformTreeShell extends StatelessWidget {
  const _NativePlatformTreeShell({required this.navigation});

  final DunesNavigationController navigation;

  void _soon(BuildContext context, String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label · 敬请期待'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: DunesTheme.light(),
      child: Scaffold(
        backgroundColor: const Color(0xFFE8D5B8),
        body: Column(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFE8F0F4),
                      Color(0xFFF3E8D4),
                      Color(0xFFE8D5B8),
                      Color(0xFFD4B896),
                    ],
                    stops: [0.0, 0.35, 0.72, 1.0],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                        child: Row(
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => navigation.back(),
                              icon: const Icon(Icons.chevron_left_rounded),
                            ),
                            Text(
                              '沙丘',
                              style: DunesTypography.sans(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: DunesColors.text,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '生态树',
                              style: DunesTypography.mono(
                                fontSize: 11,
                                color: DunesColors.text3,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                          child: PlatformTree(
                            onLighthouseTap: () => navigation.popTo('LH'),
                            onQianjiTap: () => _soon(context, '千机'),
                            onAssetTap: () => _soon(context, '资管'),
                            onNovaTap: () => _soon(context, 'NOVA'),
                          ),
                        ),
                      ),
                    ],
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

class _NativeB2Page extends StatefulWidget {
  const _NativeB2Page({
    required this.session,
    required this.navigation,
    required this.commUnread,
    required this.workbenchBadge,
    required this.workbenchRefresh,
    required this.onOpenB14,
    required this.onOpenB3,
    required this.onOpenXflowForm,
    this.onOpenWorkbench,
    this.onLogout,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final CommUnreadNotifier commUnread;
  final WorkbenchBadgeNotifier workbenchBadge;
  final WorkbenchDataRefreshNotifier workbenchRefresh;
  final void Function({String? filter}) onOpenB14;
  final void Function({String category}) onOpenB3;
  final void Function(String templateKey) onOpenXflowForm;
  final VoidCallback? onOpenWorkbench;
  final VoidCallback? onLogout;

  @override
  State<_NativeB2Page> createState() => _NativeB2PageState();
}

class _NativeB2PageState extends State<_NativeB2Page> {
  static bool get _showDeferredTools => false;
  static bool get _showQuickStats => false;
  static bool get _showQuickLaunch => false;
  static bool get _showItemBadges => false;

  _NativeMyStats? _stats;
  NativeKbSummary? _kbSummary;
  _NativeB2Profile? _profile;
  int _meetingCount = 0;
  bool _loading = true;
  String? _loadError;
  int _statsLoadGeneration = 0;
  bool _avatarSheetOpen = false;
  bool _qrLoginOpening = false;
  int _avatarRefreshVersion = 0;
  List<ProposalLaunchItem> _quickLaunchItems = const <ProposalLaunchItem>[];
  String _defaultSalesTemplateKey = XflowService.boundTemplateKeyForMenu(
    '/business/proposals/new',
  );
  final MeetingLiveController _live = MeetingLiveController.instance;
  late final ProfileTourPrefs _profileTourPrefs;
  final GlobalKey _workProfileBtnKey = GlobalKey();
  bool _profileTourOpen = false;
  bool _profileTourAutoChecked = false;

  @override
  void initState() {
    super.initState();
    _profileTourPrefs = ProfileTourPrefs(widget.session.userId);
    widget.navigation.addListener(_onProfileTourNavigation);
    _profile = _restoreCachedProfile();
    _quickLaunchItems = buildQuickLaunchItems(
      bizTemplates: XflowService.cachedTemplatesByCategory('biz'),
      admTemplates: XflowService.cachedTemplatesByCategory('adm'),
      maxItems: 4,
      defaultSalesTemplateKey: _defaultSalesTemplateKey,
    );
    widget.workbenchRefresh.addListener(_onWorkbenchDataRefresh);
    _live.active.addListener(_onLiveStateChanged);
    _live.paused.addListener(_onLiveStateChanged);
    _live.elapsed.addListener(_onLiveStateChanged);
    _live.interruptionHint.addListener(_onLiveInterruptionHint);
    unawaited(
      XflowService.hydrateTemplateCache().then((_) {
        if (!mounted) return;
        setState(() {
          _quickLaunchItems = buildQuickLaunchItems(
            bizTemplates: XflowService.cachedTemplatesByCategory('biz'),
            admTemplates: XflowService.cachedTemplatesByCategory('adm'),
            maxItems: 4,
            defaultSalesTemplateKey: _defaultSalesTemplateKey,
          );
        });
      }),
    );
    _loadStats(silent: _profile != null);
    _refreshCommBadge();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeAutoStartProfileTour());
    });
  }

  void _onLiveStateChanged() {
    if (mounted) setState(() {});
  }

  void _onLiveInterruptionHint() {
    final hint = _live.interruptionHint.value?.trim() ?? '';
    if (hint.isEmpty || !mounted) return;
    showDunesToast(context, hint);
  }

  _NativeB2Profile? _restoreCachedProfile() {
    final cached = getCachedMyPageProfile(widget.session.userId);
    if (cached != null) {
      return _NativeB2Profile(
        displayName: cached.displayName,
        phone: cached.phone,
        departmentName: cached.departmentName,
        title: cached.title,
        avatarPreset: cached.avatarPreset,
        avatarObjectKey: cached.avatarObjectKey,
        avatarUrl: cached.avatarUrl,
      );
    }
    // 与聊天/Nova 共用进程内最新头像，避免「我的」冷启动再等一轮 /users/me。
    final snap = userAvatarRefresh.snapshotFor(widget.session.userId);
    if (snap == null) return null;
    var url = snap.avatarUrl.trim();
    final objectKey = snap.avatarObjectKey.trim();
    if (url.isEmpty && objectKey.isNotEmpty) {
      url =
          dunesAvatarResolvedUrlCache[objectKey] ?? _avatarProxyUrl(objectKey);
    }
    return _NativeB2Profile(
      displayName: (widget.session.displayName ?? '').trim(),
      phone: widget.session.phone,
      departmentName: '',
      title: '',
      avatarPreset: snap.avatarPreset,
      avatarObjectKey: objectKey,
      avatarUrl: url,
    );
  }

  void _persistProfileCache(_NativeB2Profile profile) {
    final signature = avatarSourceSignature(
      preset: profile.avatarPreset,
      objectKey: profile.avatarObjectKey,
      directUrl: profile.avatarUrl,
    );
    cacheMyPageProfile(
      widget.session.userId,
      CachedMyPageProfile(
        displayName: profile.displayName,
        phone: profile.phone,
        departmentName: profile.departmentName,
        title: profile.title,
        avatarPreset: profile.avatarPreset,
        avatarObjectKey: profile.avatarObjectKey,
        avatarUrl: profile.avatarUrl,
        signature: signature,
      ),
    );
  }

  @override
  void dispose() {
    widget.navigation.removeListener(_onProfileTourNavigation);
    widget.workbenchRefresh.removeListener(_onWorkbenchDataRefresh);
    _live.active.removeListener(_onLiveStateChanged);
    _live.paused.removeListener(_onLiveStateChanged);
    _live.elapsed.removeListener(_onLiveStateChanged);
    _live.interruptionHint.removeListener(_onLiveInterruptionHint);
    super.dispose();
  }

  void _onProfileTourNavigation() {
    if (widget.navigation.currentScreen == 'B2') {
      unawaited(_maybeAutoStartProfileTour());
    }
  }

  Future<void> _maybeAutoStartProfileTour() async {
    if (_profileTourOpen || _profileTourAutoChecked) return;
    if (widget.navigation.currentScreen != 'B2') return;
    try {
      if (await _profileTourPrefs.hasSeen()) {
        if (mounted) _profileTourAutoChecked = true;
        return;
      }
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (widget.navigation.currentScreen != 'B2') return;
    _profileTourAutoChecked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _profileTourOpen) return;
      if (widget.navigation.currentScreen != 'B2') {
        _profileTourAutoChecked = false;
        return;
      }
      setState(() => _profileTourOpen = true);
    });
  }

  Future<void> _closeProfileTour() async {
    if (_profileTourOpen) setState(() => _profileTourOpen = false);
    try {
      await _profileTourPrefs.markSeen();
    } catch (_) {}
  }

  String _formatLiveElapsed(Duration duration) {
    final total = duration.inSeconds.clamp(0, 24 * 60 * 60);
    final h = (total ~/ 3600).toString().padLeft(2, '0');
    final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
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
        InboxHiddenStorage.load(),
      ]);
      final allRows = results[0] as List<NativeConversation>;
      final notif = results[1] as NativeNotificationSummary;
      final hidden = results[2] as Map<String, InboxHiddenEntry>;
      final rows = allRows
          .where(
            (c) =>
                c.isListedInInbox &&
                !isConversationHidden(hidden, c.id) &&
                !(widget.session.isExternalUser &&
                    (c.isBroadcast || c.isAiAssistant)),
          )
          .toList(growable: false);
      if (mounted) {
        widget.commUnread.update(
          widget.commUnread.sumConversationUnread(
            rows: rows,
            notifUnread: widget.session.isExternalUser ? 0 : notif.unreadCount,
          ),
        );
      }
    } catch (_) {
      // Tab badge is best-effort on B2.
    }
  }

  bool _isCurrentStatsLoad(int generation) =>
      mounted && generation == _statsLoadGeneration;

  Future<void> _loadMyWorkbenchStats({
    required bool silent,
    required int generation,
    required List<XflowProposalItem>? Function() initiatedRows,
  }) async {
    try {
      final resp = await dunesHttpGet(widget.session, '/workbench/my-stats');
      if (!_isCurrentStatsLoad(generation)) return;
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final body = jsonDecode(resp.body);
      final raw = body is Map<String, dynamic>
          ? (body['data'] is Map<String, dynamic>
                ? body['data'] as Map<String, dynamic>
                : body)
          : const <String, dynamic>{};
      var stats = _NativeMyStats.fromJson(raw);
      final rows = initiatedRows();
      if (rows != null) {
        stats = stats.alignedWithInitiatedList(rows);
      }
      if (!_isCurrentStatsLoad(generation)) return;
      setState(() {
        _stats = stats;
        _loadError = null;
      });
      widget.workbenchBadge.update(stats.pendingForMe);
    } catch (error) {
      if (!_isCurrentStatsLoad(generation) || silent) return;
      setState(() => _loadError = error.toString());
    }
  }

  Future<void> _loadKbSummaryStats({required int generation}) async {
    try {
      final summary = await NativeKbService(
        session: widget.session,
      ).fetchSummary();
      if (!_isCurrentStatsLoad(generation)) return;
      setState(() => _kbSummary = summary);
    } catch (_) {
      // 单项失败不拖垮其它事项数字。
    }
  }

  Future<void> _loadMeetingCountStats({required int generation}) async {
    try {
      final count = await NativeMeetingService(
        session: widget.session,
      ).fetchMyCount();
      if (!_isCurrentStatsLoad(generation)) return;
      setState(() => _meetingCount = count);
    } catch (_) {
      // 单项失败不拖垮其它事项数字。
    }
  }

  Future<void> _alignInitiatedStats({
    required int generation,
    required void Function(List<XflowProposalItem> rows) onRows,
  }) async {
    try {
      final rows = await XflowService(
        session: widget.session,
      ).fetchB14Initiated();
      if (!_isCurrentStatsLoad(generation)) return;
      onRows(rows);
      final current = _stats;
      if (current == null) return;
      setState(() => _stats = current.alignedWithInitiatedList(rows));
    } catch (_) {
      // 校正失败时保留 my-stats 原始数字。
    }
  }

  Future<void> _loadQuickLaunchConfig({required int generation}) async {
    try {
      final xflow = XflowService(session: widget.session);
      final results = await Future.wait<Object>(<Future<Object>>[
        xflow
            .fetchTemplatesByCategory('biz')
            .catchError((_) => const <XflowTemplateCard>[]),
        xflow
            .fetchTemplatesByCategory('adm')
            .catchError((_) => const <XflowTemplateCard>[]),
        xflow.fetchWorkbenchConfig().catchError(
          (_) => const <String, dynamic>{},
        ),
      ]);
      if (!_isCurrentStatsLoad(generation)) return;
      final bizTemplates = results[0] as List<XflowTemplateCard>;
      final admTemplates = results[1] as List<XflowTemplateCard>;
      final wbConfig = results[2] as Map<String, dynamic>;
      final bindings = wbConfig['templateBindings'];
      var defaultTemplate = _defaultSalesTemplateKey;
      if (bindings is Map) {
        final hit = (bindings['/business/proposals/new'] ?? '')
            .toString()
            .trim();
        if (hit.isNotEmpty) defaultTemplate = hit;
      }
      setState(() {
        _defaultSalesTemplateKey = defaultTemplate;
        _quickLaunchItems = buildQuickLaunchItems(
          bizTemplates: bizTemplates,
          admTemplates: admTemplates,
          maxItems: 4,
          defaultSalesTemplateKey: defaultTemplate,
        );
      });
    } catch (_) {
      // 快捷发起失败不影响事项统计。
    }
  }

  Future<void> _loadStats({bool silent = false}) async {
    final generation = ++_statsLoadGeneration;
    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    // 头像/资料与工作台统计解耦，避免被其它接口拖慢首帧。
    unawaited(_loadAndApplyProfile());

    List<XflowProposalItem>? initiatedRows;
    var remaining = 5;

    void markDone() {
      remaining--;
      if (remaining <= 0 && _isCurrentStatsLoad(generation)) {
        setState(() => _loading = false);
      }
    }

    Future<void> track(Future<void> Function() task) async {
      try {
        await task();
      } finally {
        markDone();
      }
    }

    // 各数据源独立落数：谁先到谁先刷 UI，互不阻塞。
    await Future.wait<void>(<Future<void>>[
      track(
        () => _loadMyWorkbenchStats(
          silent: silent,
          generation: generation,
          initiatedRows: () => initiatedRows,
        ),
      ),
      track(() => _loadKbSummaryStats(generation: generation)),
      track(() => _loadMeetingCountStats(generation: generation)),
      track(
        () => _alignInitiatedStats(
          generation: generation,
          onRows: (rows) => initiatedRows = rows,
        ),
      ),
      track(() => _loadQuickLaunchConfig(generation: generation)),
    ]);
  }

  Future<void> _loadAndApplyProfile() async {
    final profile = await _loadProfile();
    if (!mounted) return;
    setState(() => _profile = profile);
    _persistProfileCache(profile);
    final url = _avatarUrlWithVersion(profile.avatarUrl);
    if (url.isEmpty) return;
    try {
      await precacheImage(NetworkImage(url), context);
    } catch (_) {}
  }

  void _showSoonToast([String label = '敬请期待']) {
    showDunesSoonToast(context, label);
  }

  Future<void> _openQrLoginScanner() async {
    if (_qrLoginOpening) return;
    setState(() => _qrLoginOpening = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => QrLoginScanPage(session: widget.session),
        ),
      );
    } finally {
      if (mounted) setState(() => _qrLoginOpening = false);
    }
  }

  Future<void> _checkDesktopAppUpdateFromMobileMenu() async {
    showDunesToast(context, '正在检查更新…');
    final result = await AppUpdateService.instance.checkUpdate();
    if (!mounted) return;
    if (result == null) {
      showDunesToast(context, '暂无法检查更新，请稍后重试');
      return;
    }
    if (!result.updateAvailable) {
      showDunesToast(context, '当前已是最新版本');
      return;
    }
    await showAppUpdateDialog(context, result);
  }

  Future<bool> _clearLocalCache() async {
    try {
      await InboxHiddenStorage.save(const <String, InboxHiddenEntry>{});
      await NovaWebStorage.clear(widget.session.userId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('xflow_draft_sales-proposal');
      if (!mounted) return true;
      await _refreshCommBadge();
      await _loadStats(silent: true);
      return true;
    } catch (_) {
      return false;
    }
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
      final objectKey =
          (data['avatarObjectKey'] ?? data['peerAvatarObjectKey'] ?? '')
              .toString();
      String avatarUrl =
          (data['avatarUrl'] ??
                  data['avatarFullUrl'] ??
                  data['avatarImageUrl'] ??
                  data['avatar'] ??
                  data['avatarSrc'] ??
                  data['avatarImage'] ??
                  '')
              .toString()
              .trim();
      if (avatarUrl.isEmpty) {
        avatarUrl =
            cachedMyPageAvatarUrl(
              widget.session.userId,
              preset: avatarPreset,
              objectKey: objectKey,
            ) ??
            '';
      }
      if (avatarUrl.isEmpty && _looksLikeUrl(objectKey)) {
        avatarUrl = objectKey;
      }
      // 与 IM 一致：user-avatars 同步拼 proxy URL，不再等 presigned-get。
      if (avatarUrl.isNotEmpty) {
        avatarUrl = _avatarProxyUrl(avatarUrl);
      } else if (objectKey.isNotEmpty) {
        avatarUrl = _avatarProxyUrl(objectKey);
      }
      final profile = _NativeB2Profile(
        displayName:
            (data['displayName'] ??
                    data['name'] ??
                    widget.session.displayName ??
                    '')
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
      _persistProfileCache(profile);
      userAvatarRefresh.remember(
        UserAvatarSnapshot(
          userId: widget.session.userId,
          avatarPreset: avatarPreset,
          avatarObjectKey: objectKey,
          avatarUrl: avatarUrl,
        ),
      );
      return profile;
    } catch (_) {
      return _NativeB2Profile.fromSession(widget.session);
    }
  }

  Future<void> _openAvatarEditor() async {
    if (_avatarSheetOpen) return;
    final profile = _profile ?? _NativeB2Profile.fromSession(widget.session);
    final oldObjectKey = profile.avatarObjectKey;
    final oldAvatarUrl = profile.avatarUrl;
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
      final optimistic = _profileFromAvatarPayload(profile, updated);
      setState(() {
        _profile = optimistic;
        _avatarRefreshVersion += 1;
      });
      await publishUserAvatarUpdated(
        userId: widget.session.userId,
        oldObjectKey: oldObjectKey,
        oldAvatarUrl: oldAvatarUrl,
        avatarPreset: optimistic.avatarPreset,
        avatarObjectKey: optimistic.avatarObjectKey,
        avatarUrl: optimistic.avatarUrl,
      );
      if (!mounted) return;
      showDunesToast(context, '头像已更新');
      unawaited(() async {
        final refreshed = await _loadProfile();
        if (!mounted) return;
        final changed =
            refreshed.avatarPreset != optimistic.avatarPreset ||
            refreshed.avatarObjectKey != optimistic.avatarObjectKey ||
            refreshed.avatarUrl != optimistic.avatarUrl;
        setState(() {
          _profile = refreshed;
          if (changed) _avatarRefreshVersion += 1;
        });
        if (!changed) return;
        await publishUserAvatarUpdated(
          userId: widget.session.userId,
          oldObjectKey: optimistic.avatarObjectKey,
          oldAvatarUrl: optimistic.avatarUrl,
          avatarPreset: refreshed.avatarPreset,
          avatarObjectKey: refreshed.avatarObjectKey,
          avatarUrl: refreshed.avatarUrl,
        );
      }());
    } finally {
      if (mounted) setState(() => _avatarSheetOpen = false);
    }
  }

  _NativeB2Profile _profileFromAvatarPayload(
    _NativeB2Profile base,
    Map<String, dynamic> payload,
  ) {
    final preset =
        (payload['avatarPreset'] ?? payload['peerAvatarPreset'] ?? '')
            .toString()
            .trim();
    final objectKey =
        (payload['avatarObjectKey'] ?? payload['peerAvatarObjectKey'] ?? '')
            .toString()
            .trim();
    var avatarUrl =
        (payload['avatarUrl'] ??
                payload['avatarFullUrl'] ??
                payload['avatarImageUrl'] ??
                payload['avatar'] ??
                payload['avatarSrc'] ??
                payload['avatarImage'] ??
                '')
            .toString()
            .trim();
    if (avatarUrl.isNotEmpty) {
      avatarUrl = _avatarProxyUrl(avatarUrl);
    } else if (objectKey.isNotEmpty) {
      avatarUrl = _avatarProxyUrl(objectKey);
    }
    return base.copyWith(
      avatarPreset: preset.isNotEmpty ? preset : base.avatarPreset,
      avatarObjectKey: objectKey.isNotEmpty ? objectKey : base.avatarObjectKey,
      avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : base.avatarUrl,
    );
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
    final isExternal = widget.session.isExternalUser;
    final kb = _kbSummary;
    final kbDocCount = kb != null && kb.documents.isNotEmpty
        ? kb.documents.length
        : (kb?.documentCount ?? 0);
    final kbCategoryCount = kb?.categoryCount ?? 0;
    final kbUnreadCount = kb?.unreadCount ?? 0;
    final body = Stack(
      children: [
        Column(
          children: [
            _buildB2TopBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadStats,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
                  children: [
                    _buildProfileCard(stats, profile),
                    if (isExternal) ...[
                      const SizedBox(height: 12),
                      Text(
                        '外部用户仅可使用通讯聊天功能',
                        textAlign: TextAlign.center,
                        style: DunesTypography.sans(
                          fontSize: 14,
                          color: DunesColors.text3,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 10),
                      if (_showQuickStats) ...[
                        _buildQuickStats(stats),
                        const SizedBox(height: 14),
                      ],
                      if (_showQuickLaunch) ...[
                        _buildQuickLaunch(),
                        const SizedBox(height: 14),
                      ],
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
                          text:
                              '您有 ${stats.approvalRejected} 条审批被驳回，点击进入「我发起的审批」',
                          onTap: () => widget.onOpenB14(),
                        ),
                      ],
                      if (stats.pendingInitiateForMe > 0) ...[
                        const SizedBox(height: 8),
                        _buildReminderBanner(
                          icon: Icons.assignment_ind_outlined,
                          text:
                              '有 ${stats.pendingInitiateForMe} 条同事推送给您、待您确认发起的提案',
                          onTap: () =>
                              widget.onOpenB14(filter: 'PENDING_INITIATE'),
                        ),
                      ],
                      if (stats.pendingForMe > 0 ||
                          stats.approvalRejected > 0 ||
                          stats.pendingInitiateForMe > 0)
                        const SizedBox(height: 14),
                      _buildSectionLabel('我的事项'),
                      const SizedBox(height: 8),
                      _buildMenuList(<Widget>[
                        if (widget.onOpenWorkbench != null)
                          _buildMenuItem(
                            icon: Icons.apps_rounded,
                            title: '工作台',
                            desc: '任务与协作',
                            onTap: widget.onOpenWorkbench,
                          ),
                        _buildMenuItem(
                          icon: Icons.add_task_outlined,
                          title: '审批填写',
                          desc: '选择并填写审批单',
                          onTap: widget.onOpenB3,
                        ),
                      ]),
                      const SizedBox(height: 10),
                      _buildMenuList(<Widget>[
                        _buildMenuItem(
                          icon: Icons.article_outlined,
                          title: '会议纪要',
                          desc: '$_meetingCount 场 · 录音转写 · 纪要生成',
                          badge: _meetingCount,
                          onTap: () => widget.navigation.go('MM-L'),
                        ),
                        _buildMenuItem(
                          icon: Icons.auto_stories_outlined,
                          title: '知识库',
                          desc: '$kbDocCount 文档 · $kbCategoryCount 分类',
                          badge: kbUnreadCount,
                          onTap: () => widget.navigation.go('K1'),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      _buildMenuList(<Widget>[
                        _buildMenuItem(
                          icon: Icons.edit_note_outlined,
                          title: '我审批的',
                          desc:
                              '${stats.pendingForMe} 待我审 · ${stats.handledThisMonth} 已审核',
                          badge: stats.pendingForMe,
                          onTap: () => widget.navigation.go('B1'),
                        ),
                        if (stats.postApprovalTodoEnabled)
                          _buildMenuItem(
                            icon: Icons.task_alt_outlined,
                            title: '审批待办',
                            desc:
                                '${stats.pendingTodoForMe} 待办理 · ${stats.handledTodoThisMonth} 本月已办',
                            badge: stats.pendingTodoForMe,
                            onTap: () => widget.navigation.go('B13'),
                          ),
                        _buildMenuItem(
                          icon: Icons.description_outlined,
                          title: '我发起的审批',
                          desc:
                              '$initiatedTotal 条总数 · ${stats.approvalPending} 审批中',
                          badge: initiatedTotal,
                          onTap: () => widget.onOpenB14(),
                        ),
                        _buildMenuItem(
                          icon: Icons.check_box_outlined,
                          title: '抄送我的',
                          desc:
                              '${stats.ccProposalCount} 份抄送 · ${stats.ccProposalPending} 审批中',
                          badge: stats.ccProposalCount,
                          onTap: () => widget.navigation.go('P1'),
                        ),
                      ]),
                      if (_showDeferredTools) ...[
                        const SizedBox(height: 10),
                        _buildMenuList(<Widget>[
                          _buildMenuItem(
                            icon: Icons.receipt_long_outlined,
                            title: '应付账单',
                            desc:
                                '${stats.outstandingInvoices} 待处理 · 总 ¥0 · 灯塔联动',
                            badge: stats.outstandingInvoices,
                            comingSoon: true,
                            onTap: () => _showSoonToast(),
                          ),
                          _buildMenuItem(
                            icon: Icons.warning_amber_rounded,
                            title: '欠票催办',
                            desc: '0 笔 · ¥0 · 欠 0 天',
                            badge: 0,
                            comingSoon: true,
                            onTap: () => _showSoonToast(),
                          ),
                        ]),
                      ],
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
                    ],
                    if (_loadError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton(
                          onPressed: _loadStats,
                          child: const Text('数据同步失败，点击重试'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (_live.active.value && !isWindowsDesktopCommOnly)
          Positioned(
            right: 16,
            bottom:
                kDunesMainTabBarHeight +
                MediaQuery.viewPaddingOf(context).bottom +
                12,
            child: _buildLiveTranscribeFab(),
          ),
        if (_profileTourOpen)
          Positioned.fill(
            child: SpotlightTourOverlay(
              steps: [
                SpotlightTourStep(
                  targetKey: _workProfileBtnKey,
                  title: '个人工作画像',
                  body: '点这里查看你的工作节奏、协作沉淀、绩效发展等内容。之后就不会再出现这条指引。',
                  holeRadius: 99,
                ),
              ],
              onClose: _closeProfileTour,
            ),
          ),
      ],
    );
    return ColoredBox(
      color: DunesColors.bgApp,
      child: SafeArea(bottom: false, child: body),
    );
  }

  Widget _buildLiveTranscribeFab() {
    final paused = _live.paused.value;
    final elapsedText = _formatLiveElapsed(_live.elapsed.value);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => widget.navigation.go('MM0'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: paused ? DunesColors.text3 : DunesColors.coral,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: (paused ? DunesColors.text3 : DunesColors.coral)
                    .withValues(alpha: 0.4),
                blurRadius: 12,
                spreadRadius: 1,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                paused ? Icons.pause_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                MeetingRecordingInterruption.fabLabel(
                  paused: paused,
                  pausedByInterruption: _live.pausedByInterruption,
                  elapsedText: elapsedText,
                ),
                style: DunesTypography.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _looksLikeUrl(String value) {
    final v = value.toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  String _avatarProxyUrl(String source) {
    final raw = source.trim();
    if (raw.isEmpty) return raw;
    final apiBase = widget.session.apiBase;
    // 已是完整 URL 时直接用，避免被误当成 objectKey。
    if (raw.startsWith(apiBase) || _looksLikeUrl(raw)) return raw;
    return '$apiBase/storage/download?bucket=user-avatars&objectKey=${Uri.encodeQueryComponent(raw)}&proxy=1';
  }

  String _avatarUrlWithVersion(String rawUrl) {
    final url = rawUrl.trim();
    if (url.isEmpty) return url;
    // 仅换头像后加版本戳；平时与 IM 共用同一 URL，复用 ImageCache。
    if (_avatarRefreshVersion <= 0) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}dunes_avatar_v=$_avatarRefreshVersion';
  }

  Future<void> _openTextScalePicker() async {
    final controller = AppTextScaleController.instance;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '字体大小',
                  style: DunesTypography.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '调整后将作用于整个 App',
                  style: DunesTypography.sans(
                    fontSize: 13,
                    color: DunesColors.text3,
                  ),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < AppTextScaleController.presets.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      AppTextScaleController.labels[i],
                      style: DunesTypography.sans(
                        fontSize: 15 * AppTextScaleController.presets[i],
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                    trailing: i == controller.presetIndex
                        ? const Icon(
                            Icons.check_rounded,
                            color: Color(0xFF7E64BD),
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, i),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    await controller.setPresetIndex(picked);
    if (!mounted) return;
    showDunesToast(context, '已切换为「${AppTextScaleController.labels[picked]}」字号');
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
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
                TextSpan(
                  text: ' DUNES',
                  style: TextStyle(color: DunesColors.text3, fontSize: 11),
                ),
                TextSpan(
                  text: '  ·  我的',
                  style: TextStyle(color: DunesColors.text2, fontSize: 11),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (!isDesktopCommOnly)
            IconButton(
              tooltip: '字体大小',
              onPressed: _openTextScalePicker,
              icon: const Icon(Icons.format_size_rounded, size: 22),
              color: DunesColors.text2,
            ),
          // PC 外部用户无可用项；APP 仍保留清缓存/退出等。
          if (!(isDesktopCommOnly && widget.session.isExternalUser))
            _buildB2OverflowMenu(),
        ],
      ),
    );
  }

  void _openInviteQrPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InviteQrPage(session: widget.session),
      ),
    );
  }

  Widget _buildB2OverflowMenu() {
    return PopupMenuButton<_B2MenuAction>(
      tooltip: '更多功能',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 4),
      shape: const _WechatMenuShape(),
      menuPadding: const EdgeInsets.only(top: 12, bottom: 8),
      color: const Color(0xFFF2F2F2),
      onSelected: (action) {
        switch (action) {
          case _B2MenuAction.scanWorkstation:
            _openQrLoginScanner();
          case _B2MenuAction.wechatBot:
            widget.navigation.go('WX');
          case _B2MenuAction.checkUpdate:
            unawaited(_checkDesktopAppUpdateFromMobileMenu());
          case _B2MenuAction.clearCache:
            _clearLocalCache();
          case _B2MenuAction.startProposal:
            widget.onOpenB3();
          case _B2MenuAction.inviteUser:
            _openInviteQrPage();
          case _B2MenuAction.logout:
            unawaited(_confirmLogout());
        }
      },
      itemBuilder: (context) {
        // PC：右上角保留微信 Bot / 发起提案 / 邀请用户；其余能力在「设置」。
        if (isDesktopCommOnly) {
          return [
            if (!widget.session.isExternalUser)
              const PopupMenuItem(
                value: _B2MenuAction.wechatBot,
                child: _B2MenuEntry(icon: Icons.chat_rounded, label: '微信 Bot'),
              ),
            if (!widget.session.isExternalUser)
              const PopupMenuItem(
                value: _B2MenuAction.startProposal,
                child: _B2MenuEntry(
                  icon: Icons.add_circle_outline_rounded,
                  label: '发起提案',
                ),
              ),
            if (!widget.session.isExternalUser)
              const PopupMenuItem(
                value: _B2MenuAction.inviteUser,
                child: _B2MenuEntry(
                  icon: Icons.person_add_alt_1_outlined,
                  label: '邀请用户',
                ),
              ),
          ];
        }
        return [
          PopupMenuItem(
            value: _B2MenuAction.scanWorkstation,
            enabled: !_qrLoginOpening,
            child: const _B2MenuEntry(
              icon: Icons.qr_code_scanner_rounded,
              label: '扫码登录工作台',
            ),
          ),
          if (!widget.session.isExternalUser)
            const PopupMenuItem(
              value: _B2MenuAction.wechatBot,
              child: _B2MenuEntry(icon: Icons.chat_rounded, label: '微信 Bot'),
            ),
          const PopupMenuItem(
            value: _B2MenuAction.clearCache,
            child: _B2MenuEntry(
              icon: Icons.cleaning_services_outlined,
              label: '清除本地缓存',
            ),
          ),
          if (!widget.session.isExternalUser)
            const PopupMenuItem(
              value: _B2MenuAction.startProposal,
              child: _B2MenuEntry(
                icon: Icons.add_circle_outline_rounded,
                label: '发起提案',
              ),
            ),
          if (!widget.session.isExternalUser)
            const PopupMenuItem(
              value: _B2MenuAction.inviteUser,
              child: _B2MenuEntry(
                icon: Icons.person_add_alt_1_outlined,
                label: '邀请用户',
              ),
            ),
          if (widget.onLogout != null) ...[
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: _B2MenuAction.logout,
              child: _B2MenuEntry(
                icon: Icons.logout_rounded,
                label: '退出登录',
                color: DunesColors.coral,
              ),
            ),
          ],
        ];
      },
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: DunesColors.borderSoft),
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          size: 24,
          color: DunesColors.text2,
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认退出登录？'),
            content: const Text('退出后需要重新登录才能继续使用。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('退出登录'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed && mounted) widget.onLogout?.call();
  }

  Widget _buildProfileCard(_NativeMyStats stats, _NativeB2Profile profile) {
    final name = profile.displayName.trim().isEmpty
        ? (widget.session.displayName ?? widget.session.phone).trim()
        : profile.displayName.trim();
    final avatarText = name.isEmpty ? '我' : name.characters.first;
    final displayAvatarUrl = _avatarUrlWithVersion(profile.avatarUrl);
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
            borderRadius: BorderRadius.circular(52 * 0.18),
            child: Stack(
              children: [
                NativeAvatarCircle(
                  key: ValueKey<String>(
                    '${profile.avatarPreset}|${profile.avatarObjectKey}|${profile.avatarUrl}|$_avatarRefreshVersion',
                  ),
                  size: 52,
                  avatarPreset: profile.avatarPreset,
                  avatarUrl: displayAvatarUrl,
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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  profile.subtitleLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: DunesColors.text2,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: '查看个人工作画像',
            child: Tooltip(
              message: '个人工作画像',
              child: InkWell(
                key: _workProfileBtnKey,
                borderRadius: BorderRadius.circular(18),
                onTap: () => widget.navigation.go('B2P'),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F3FC),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFC1B0D6),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.insights_rounded,
                      size: 19,
                      color: Color(0xFF7651B8),
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

    Widget cell(
      String title,
      String value, {
      bool soon = false,
      VoidCallback? onTap,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 76,
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
                      style: const TextStyle(
                        fontSize: 10,
                        color: DunesColors.text3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        height: .9,
                      ),
                    ),
                  ],
                ),
              ),
              if (soon) Positioned(top: 3, right: 3, child: soonBadge()),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final cellW = ((constraints.maxWidth - gap * 3) / 4).clamp(
          0.0,
          double.infinity,
        );
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
    final items = _quickLaunchItems.isEmpty
        ? buildQuickLaunchItems(
            bizTemplates: const <XflowTemplateCard>[],
            admTemplates: const <XflowTemplateCard>[],
            maxItems: 4,
          )
        : _quickLaunchItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '快速发起',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => widget.onOpenB3(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('更多审批  →', style: TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i < items.length - 1 ? 7 : 0),
                  child: ProposalQuickLaunchCell(
                    item: items[i],
                    onTap: items[i].enabled && !items[i].isPlaceholder
                        ? () => _onQuickLaunchTap(items[i])
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _onQuickLaunchTap(ProposalLaunchItem item) {
    if (!item.enabled || item.isPlaceholder) return;
    final templateKey = item.templateKey?.trim();
    if (templateKey != null && templateKey.isNotEmpty) {
      widget.onOpenXflowForm(templateKey);
      return;
    }
    final screenId = item.screenId?.trim();
    if (screenId != null && screenId.isNotEmpty) {
      widget.navigation.go(screenId);
      return;
    }
    widget.onOpenB3();
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: DunesColors.text2,
        fontSize: 14,
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
              Icon(icon, size: 16, color: const Color(0xFF8A5A14)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6E4A11),
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Color(0xFF8A5A14),
              ),
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
  }) {
    final row = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: comingSoon && onTap == null ? null : onTap,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              const SizedBox(width: 14),
              Icon(icon, size: 21, color: DunesColors.text2),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      desc,
                      style: const TextStyle(
                        fontSize: 10,
                        color: DunesColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              if (_showItemBadges && badge != null && badge > 0)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC6C2B8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
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
        IgnorePointer(ignoring: onTap == null, child: withBorder),
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Container(
                color: const Color(0x38FFFFFF),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 44),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xE61F2421),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Text(
                    '敬请期待',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _B2MenuAction {
  scanWorkstation,
  wechatBot,
  checkUpdate,
  clearCache,
  startProposal,
  inviteUser,
  logout,
}

class _B2MenuEntry extends StatelessWidget {
  const _B2MenuEntry({
    required this.icon,
    required this.label,
    this.color = DunesColors.text,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Text(label, style: DunesTypography.sans(fontSize: 14, color: color)),
      ],
    );
  }
}

class _WechatMenuShape extends ShapeBorder {
  const _WechatMenuShape({
    this.radius = 12,
    this.tipWidth = 14,
    this.tipHeight = 8,
  });

  final double radius;
  final double tipWidth;
  final double tipHeight;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final top = rect.top + tipHeight;
    final tipCenter = rect.right - 28;
    final path = Path()
      ..moveTo(rect.left + radius, top)
      ..lineTo(tipCenter - tipWidth / 2, top)
      ..lineTo(tipCenter, rect.top)
      ..lineTo(tipCenter + tipWidth / 2, top)
      ..lineTo(rect.right - radius, top)
      ..quadraticBezierTo(rect.right, top, rect.right, top + radius)
      ..lineTo(rect.right, rect.bottom - radius)
      ..quadraticBezierTo(
        rect.right,
        rect.bottom,
        rect.right - radius,
        rect.bottom,
      )
      ..lineTo(rect.left + radius, rect.bottom)
      ..quadraticBezierTo(
        rect.left,
        rect.bottom,
        rect.left,
        rect.bottom - radius,
      )
      ..lineTo(rect.left, top + radius)
      ..quadraticBezierTo(rect.left, top, rect.left + radius, top)
      ..close();
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) {
    return _WechatMenuShape(
      radius: radius * t,
      tipWidth: tipWidth * t,
      tipHeight: tipHeight * t,
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
    required this.pendingTodoForMe,
    required this.handledTodoThisMonth,
    this.postApprovalTodoEnabled = false,
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
      pendingInitiateForMe = 0,
      pendingTodoForMe = 0,
      handledTodoThisMonth = 0,
      postApprovalTodoEnabled = false;

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
  final int pendingTodoForMe;
  final int handledTodoThisMonth;
  final bool postApprovalTodoEnabled;

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
      pendingTodoForMe: pendingTodoForMe,
      handledTodoThisMonth: handledTodoThisMonth,
      postApprovalTodoEnabled: postApprovalTodoEnabled,
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
      handledThisMonth: readInt(<String>[
        'approvalHandled',
        'handledThisMonth',
        'approved',
      ]),
      outstandingInvoices: readInt(<String>['outstandingInvoices']),
      approvalRejected: readInt(<String>['approvalRejected']),
      ccProposalCount: readInt(<String>['ccProposalCount']),
      ccProposalPending: readInt(<String>['ccProposalPending']),
      pendingInitiateForMe: readInt(<String>['pendingInitiateForMe']),
      pendingTodoForMe: readInt(<String>['pendingTodoForMe']),
      handledTodoThisMonth: readInt(<String>['handledTodoThisMonth']),
      postApprovalTodoEnabled: json['postApprovalTodoEnabled'] == true,
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

  _NativeB2Profile copyWith({
    String? displayName,
    String? phone,
    String? departmentName,
    String? title,
    String? avatarPreset,
    String? avatarObjectKey,
    String? avatarUrl,
  }) {
    return _NativeB2Profile(
      displayName: displayName ?? this.displayName,
      phone: phone ?? this.phone,
      departmentName: departmentName ?? this.departmentName,
      title: title ?? this.title,
      avatarPreset: avatarPreset ?? this.avatarPreset,
      avatarObjectKey: avatarObjectKey ?? this.avatarObjectKey,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

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
          _ActionTile(title: '返回', subtitle: '回到上一页', onTap: onBack),
      ],
    );
  }
}

class _NativeScaffold extends StatelessWidget {
  const _NativeScaffold({required this.title, required this.body});

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
  const _ActionTile({required this.title, required this.subtitle, this.onTap});

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
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

enum _DualChatKind {
  robot,
  private,
  group,
  approval,
  task,
  drive,
  xrxs,
  weeklySummary,
  administrativeNotice,
  reconciliation,
}

class _DualChatSlot {
  const _DualChatSlot._({
    required this.kind,
    this.conversation,
    this.peerUserId,
  });

  factory _DualChatSlot.robot(NativeConversation conversation) {
    return _DualChatSlot._(
      kind: _DualChatKind.robot,
      conversation: conversation,
    );
  }

  factory _DualChatSlot.private({
    NativeConversation? conversation,
    int? peerUserId,
  }) {
    return _DualChatSlot._(
      kind: _DualChatKind.private,
      conversation: conversation,
      peerUserId: peerUserId,
    );
  }

  factory _DualChatSlot.group(NativeConversation conversation) {
    return _DualChatSlot._(
      kind: _DualChatKind.group,
      conversation: conversation,
    );
  }

  factory _DualChatSlot.approval(NativeConversation? conversation) {
    return _DualChatSlot._(
      kind: _DualChatKind.approval,
      conversation: conversation,
    );
  }

  factory _DualChatSlot.task(NativeConversation? conversation) {
    return _DualChatSlot._(
      kind: _DualChatKind.task,
      conversation: conversation,
    );
  }

  factory _DualChatSlot.drive(NativeConversation? conversation) {
    return _DualChatSlot._(
      kind: _DualChatKind.drive,
      conversation: conversation,
    );
  }

  factory _DualChatSlot.xrxs(NativeConversation? conversation) {
    return _DualChatSlot._(
      kind: _DualChatKind.xrxs,
      conversation: conversation,
    );
  }

  factory _DualChatSlot.weeklySummary(NativeConversation? conversation) {
    return _DualChatSlot._(
      kind: _DualChatKind.weeklySummary,
      conversation: conversation,
    );
  }

  factory _DualChatSlot.administrativeNotice(NativeConversation? conversation) {
    return _DualChatSlot._(
      kind: _DualChatKind.administrativeNotice,
      conversation: conversation,
    );
  }

  factory _DualChatSlot.reconciliation(NativeConversation? conversation) {
    return _DualChatSlot._(
      kind: _DualChatKind.reconciliation,
      conversation: conversation,
    );
  }

  final _DualChatKind kind;
  final NativeConversation? conversation;
  final int? peerUserId;
}
