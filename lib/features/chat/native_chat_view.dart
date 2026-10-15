import 'desktop_message_menu.dart';
import 'desktop_attachment_feedback.dart';
import 'chat_file_upload_source.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox, ScrollDirection;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/layout/chat_layout.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/util/native_permissions.dart';
import '../../core/widgets/cached_network_image.dart';
import '../am_sso/am_sso_service.dart';
import '../auth/auth_session.dart';
import '../contacts/contact_service.dart';
import '../meeting/meeting_live_controller.dart';
import '../conversation/chat_message_cache.dart';
import '../conversation/conversation_inbox_realtime.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_realtime_dedup.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/im_user_status.dart';
import '../conversation/inbox_format.dart';
import '../desktop/windows_desktop_tray.dart';
import '../drive/chat_save_to_drive.dart';
import '../kb/kb_chat_share.dart';
import '../kb/kb_document_coordinator.dart';
import '../kb/native_kb_service.dart';
import '../meeting/meeting_minutes_chat_share.dart';
import '../meeting/native_meeting_detail_page.dart';
import '../payroll/payroll_report_share_card.dart';
import '../profile/work_profile_chat_share.dart';
import '../kpi/kpi_score_summary_card.dart';
import '../kpi/kpi_summary_person_sheet.dart';
import '../robots/robot_markdown.dart';
import '../shell/dunes_toast.dart';
import '../weekly_summary/native_weekly_summary_page.dart';
import '../weekly_summary/weekly_summary_card.dart';
import '../weekly_summary/weekly_summary_models.dart';
import '../xflow/approval_chat_share.dart';
import '../xflow/proposal_intake_share_card.dart';
import '../tasks/task_chat_share.dart';
import '../tasks/task_chat_share_card.dart';
import '../tasks/task_chat_share_bundle_card.dart';
import '../tasks/task_api.dart';
import '../qianji/qianji_group_reply_person_card.dart';
import '../qianji/native_qianji_daily_report_supervise_page.dart';
import '../xflow/approval_picker_sheet.dart';
import '../xflow/xflow_detail_logic.dart';
import 'chat_emoji_gif_panel.dart';
import 'im_celebration.dart';
import 'chat_foreground_sync.dart';
import 'desktop_composer_focus.dart';
import 'chat_image_batch_preview.dart';
import 'chat_file_clipboard.dart';
import 'chat_image_clipboard.dart';
import 'chat_image_editor.dart';
import 'chat_image_utils.dart';
import 'chat_file_preview_page.dart';
import 'chat_file_type_icon.dart';
import 'chat_file_upload_coordinator.dart';
import 'chat_lighthouse_card.dart';
import '../lighthouse/lighthouse_shared_card_data.dart';
import 'chat_markdown_preview.dart';
import 'chat_pdf_preview.dart';
import 'chat_media_widgets.dart';
import 'chat_desktop_file_drag_stub.dart'
    if (dart.library.io) 'chat_desktop_file_drag.dart';
import 'chat_quote.dart';
import '../conversation/reply_sla_models.dart';
import 'chat_video_utils.dart';
import 'chat_video_widgets.dart';
import 'chat_voice_player.dart';
import 'voice_asr_store.dart';
import 'chat_compose_draft_store.dart';
import 'voice_recording_overlay.dart';
import 'voice_transcript_panel.dart';
import 'chat_widgets.dart';
import 'desktop_composer_pending.dart';
import 'desktop_screenshot.dart';
import 'file_download.dart' as file_dl;
import 'im_cached_file_names.dart';
import 'user_avatar_widget.dart';
import 'native_audio_recorder.dart';

enum NativeChatKind { private, group }

/// 纯文本行高约；图片/语音消息实际更高，估算时略保守。
const double _kChatMessageRowHeight = 76;

/// 会话列表滚动/分页参数，按列表可视高度自适应（Android / iOS、大小屏通用）。
class _ChatScrollMetrics {
  const _ChatScrollMetrics({required this.listViewportHeight});

  final double listViewportHeight;

  /// 顶栏 + 输入区大约占用（首屏尚未 layout 时 fallback）。
  static const double _screenChromeHeight = 168;

  /// 一屏大约能看到的消息条数（6~14）。
  int get visibleMessageEstimate =>
      (listViewportHeight / _kChatMessageRowHeight).ceil().clamp(6, 14);

  /// 首屏：约 1.8 屏，15~24 条。
  int get initialPageSize =>
      (visibleMessageEstimate * 1.8).round().clamp(15, 24);

  /// 上滑/下拉分页：约 1.2 屏，12~18 条。
  int get batchPageSize => (visibleMessageEstimate * 1.2).round().clamp(12, 18);

  /// 距顶部剩余多少时预拉下一批（约 0.55 屏）。
  double get prefetchLead => listViewportHeight * 0.55;

  /// 列表预渲染范围（约 0.85 屏）。
  double get cacheExtent => listViewportHeight * 0.85;

  /// 惯性初速上限：大屏略高、小屏略低。
  double get maxFlingVelocity => listViewportHeight * 2.5;

  /// iOS 系统滚动本身更「跟手」，阻尼略小；Android 略加强分段感。
  double get dragDamping {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return 0.91;
      default:
        return 0.88;
    }
  }

  factory _ChatScrollMetrics.fromListViewport(double listViewportHeight) {
    return _ChatScrollMetrics(
      listViewportHeight: math.max(240, listViewportHeight),
    );
  }

  factory _ChatScrollMetrics.fromScreenHeight(double screenHeight) {
    return _ChatScrollMetrics(
      listViewportHeight: math.max(240, screenHeight - _screenChromeHeight),
    );
  }
}

class _ChatListEntry {
  const _ChatListEntry.divider(this.dividerLabel)
    : message = null,
      showSenderMeta = false;

  const _ChatListEntry.message(this.message, {this.showSenderMeta = false})
    : dividerLabel = null;

  final String? dividerLabel;
  final NativeChatMessage? message;
  final bool showSenderMeta;
}

class _MessageQuickAction {
  const _MessageQuickAction({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

typedef _ForwardUnit = ({
  String senderName,
  String timeLabel,
  String text,
  String kind,
  Map<String, dynamic>? payload,
  String? avatarPreset,
  String? avatarObjectKey,
});

class _ForwardBundle {
  const _ForwardBundle({required this.title, required this.entries});

  final String title;
  final List<_ForwardEntry> entries;
}

class _ForwardEntry {
  const _ForwardEntry({
    required this.senderName,
    required this.timeLabel,
    required this.text,
    required this.kind,
    this.payload,
    this.avatarPreset,
    this.avatarObjectKey,
  });

  final String senderName;
  final String timeLabel;
  final String text;
  final String kind;
  final Map<String, dynamic>? payload;
  final String? avatarPreset;
  final String? avatarObjectKey;
}

/// PC 输入框中尚未发送的附件。仅保存在当前聊天页内，不改变服务端消息结构。
class _DesktopComposerAttachment {
  const _DesktopComposerAttachment({
    required this.bytes,
    this.uploadSource,
    required this.fileName,
    required this.mimeType,
    required this.isImage,
    required this.sourceLabel,
  });

  final Uint8List bytes;
  final ChatFileUploadSource? uploadSource;
  final String fileName;
  final String mimeType;
  final bool isImage;
  final String sourceLabel;
}

class NativeChatView extends StatefulWidget {
  const NativeChatView({
    super.key,
    required this.session,
    required this.kind,
    this.conversationHint,
    this.peerUserIdHint,
    this.focusMessageId,
    this.focusMessageHint,
    required this.onBack,
    this.onOpenProfile,
    this.onOpenUser,
    this.onOpenGroupInfo,
    this.onOpenSearch,
    this.onOpenMedia,
    this.onOpenCall,
    this.onOpenAiSummary,
    this.onOpenApprovalShare,
    this.onOpenTaskShare,
    this.onConversationRead,
    this.onClearFocusMessage,
    this.autoMarkRead = false,
    this.showBackButton = true,
  });

  final AuthSession session;
  final NativeChatKind kind;
  final NativeConversation? conversationHint;
  final int? peerUserIdHint;
  final int? focusMessageId;
  final NativeChatMessage? focusMessageHint;
  final VoidCallback onBack;
  final VoidCallback? onOpenProfile;

  /// 点击消息头像进入用户详情（群聊/私聊）。
  final void Function(int userId, String displayName)? onOpenUser;
  final VoidCallback? onOpenGroupInfo;
  final ValueChanged<int>? onOpenSearch;
  final ValueChanged<int>? onOpenMedia;
  final VoidCallback? onOpenCall;

  /// 对本会话发起智能总结（回调参数为当前 conversationId）。
  final ValueChanged<int>? onOpenAiSummary;

  /// 打开转发的审批卡片详情（与「我审批的」同一套 B10 / XFS）。
  final ValueChanged<ApprovalChatShare>? onOpenApprovalShare;
  final ValueChanged<TaskChatShare>? onOpenTaskShare;
  final ValueChanged<int>? onConversationRead;

  /// 「回到最新」时清掉上层 focus，避免后续静默刷新又跳回定位消息。
  final VoidCallback? onClearFocusMessage;
  final bool autoMarkRead;

  /// 双栏布局下列表已可见时隐藏返回按钮。
  final bool showBackButton;

  @override
  State<NativeChatView> createState() => _NativeChatViewState();
}

class _NativeChatViewState extends State<NativeChatView>
    with WidgetsBindingObserver {
  late final ConversationService _service;
  late final ConversationRealtimeService _realtime;
  final ConversationRealtimeDedup _realtimeDedup = ConversationRealtimeDedup();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  StreamSubscription<Set<int>>? _onlineSub;
  Timer? _rtRefreshDebounce;
  Timer? _recordTicker;

  bool _loading = true;
  bool _bootstrapped = false;
  bool _locating = false;

  /// 会话内置顶消息（最新在前）。
  List<NativePinnedMessage> _pinnedMessages = const <NativePinnedMessage>[];
  bool _pinnedExpanded = false;

  /// 文本发送中（不阻塞媒体上传）。
  bool _sending = false;

  /// 滚动中收到实时消息时只改内存，松手后再画。
  bool _realtimePaintDeferred = false;

  List<_ChatListEntry>? _cachedListEntries;
  List<NativeChatMessage>? _cachedListEntriesSource;
  int _cachedListEntriesLen = 0;
  int _cachedListEntriesLastId = 0;

  /// 媒体/文件上传中（不阻塞文本继续发送）。
  bool _uploading = false;
  bool _showingBackgroundFileUpload = false;

  /// 当前可取消的媒体上传令牌（文件后台任务另见 ChatFileUploadCoordinator）。
  ChatUploadCancelToken? _activeUploadCancel;

  /// 当前可取消的附件下载令牌。
  ChatUploadCancelToken? _activeDownloadCancel;

  /// PC 拖入文件/图片时的悬停高亮。
  bool _fileDropHovering = false;
  String? _uploadLabel;
  String? _desktopAttachmentNotice;
  bool _desktopAttachmentFailed = false;
  double _uploadProgress = 0;
  bool _recording = false;

  /// 当前正在下载的附件 cacheKey；非空时仅该文件气泡转圈。
  String? _downloadingFileKey;
  double _downloadProgress = 0;
  final Stopwatch _downloadProgressClock = Stopwatch();
  int _lastDownloadProgressUpdate = -200;

  /// 本地已缓存的文件 cacheKey（或 fileName 兜底），用于气泡勾选。
  final Set<String> _downloadedFileKeys = <String>{};

  /// 已存入微盘的 IM 附件 sourceKey（objectKey / url）。
  final Set<String> _driveSavedFileKeys = <String>{};
  VoiceHoldAction _recordHoldAction = VoiceHoldAction.none;
  Offset? _recordFocalPoint;

  bool get _recordWillCancel => _recordHoldAction == VoiceHoldAction.cancel;
  bool get _recordWillTranscribe =>
      _recordHoldAction == VoiceHoldAction.transcribe;
  bool _loadingOlder = false;

  /// prepend 历史消息后正在恢复滚动位置，避免仍停在 maxScrollExtent 连续拉完全部历史。
  bool _olderScrollRestorePending = false;
  int _olderLoadCooldownUntilMs = 0;
  int _newerLoadCooldownUntilMs = 0;
  int? _scrollRestoreAnchorId;
  final Map<int, GlobalKey> _scrollRestoreKeys = <int, GlobalKey>{};
  ScrollHoldController? _olderScrollHold;
  double _olderScrollHoldPixels = 0;

  /// 最小化期间收到新消息但贴底失败时，恢复前台后再滚一次。
  /// 也会在「最小化前贴在最新端」时置位，避免还原窗口把列表拽去历史方向。
  bool _pendingStickBottomAfterForeground = false;
  bool _foregroundSyncRunning = false;
  DateTime? _lastForegroundSyncAt;

  /// 窗口收起/还原时 reverse 列表会乱跳，这段时间不要把像素变化当成用户上滑。
  bool _backgroundLayoutActive = false;

  /// 本次失焦是否把窗口收起/夹扁。仅切软件时为 false，恢复后不要重载列表。
  bool _foregroundPauseWasObscured = false;
  DateTime? _foregroundRestoredAt;
  DateTime? _lastPointerSignalScrollAt;
  double _olderScrollHoldMax = 0;
  bool _loadingNewer = false;
  bool _locatedMode = false;
  bool _forceLatestMode = false;

  /// 历史定位正在对准目标：禁止自动补历史/补更新，避免和 ensureVisible 抢滚动。
  bool _messageLocateSettling = false;

  /// 用户已点「回到最新」后忽略的 focusMessageId，防止父级未清掉时再次定位。
  int _suppressedFocusMessageId = 0;

  /// 递增后作废仍在排队的定位滚动，避免「回到最新」被旧 ensureVisible 拉回去。
  int _messageScrollGen = 0;

  /// 递增后忽略过期的 `_load` 结果，避免快速切会话时旧请求回写空白/错误态。
  int _loadGeneration = 0;

  /// 进入会话后需持续尝试滚到底，直到成功或用户手动滚动（解决 ListView/图片懒加载竞态）。
  bool _enterStickBottomPending = true;
  int _scrollBottomGen = 0;
  int _bottomAnchorMessageId = 0;
  int _pendingNewMessageCount = 0;
  int _lastMarkedReadNewestId = 0;
  bool _wasNearBottom = true;

  /// 用户已上滑离开最新消息端，显示「回到最新」入口。
  bool _awayFromLatest = false;

  /// 视口稳定时「正在看历史」的快照。PC 最小化会把 reverse 列表
  /// pixels 夹到 0，不能用当时像素判断，否则恢复前台会被当成贴底。
  bool _stableAwayFromLatest = false;
  double _stableHistoryPixels = 0;
  int _stableHistoryAnchorId = 0;
  bool _historyViewportFrozen = false;
  bool _userInteractedWithScroll = false;
  bool _userScrollActive = false;
  DateTime? _lastUserScrollTowardLatestAt;

  /// 进入会话时捕获的未读（微信式右上角「N 条未读」）。
  int _sessionUnreadCount = 0;
  int _firstUnreadMessageId = 0;
  bool _unreadJumpDismissed = false;
  bool _unreadMessageVisible = false;
  bool _unreadVisibilityCheckPending = false;
  bool _unreadVisibilityKeyRetryUsed = false;

  /// 当前 firstUnread 是否只是「已加载窗口最旧一条」占位（未读数尚未被历史覆盖）。
  bool _firstUnreadTruncated = false;
  bool _hasMore = false;
  bool _hasNewer = false;
  int? _highlightMessageId;
  int _peerLastReadMessageId = 0;
  Timer? _highlightTimer;
  bool _voiceMode = false;
  bool _emojiOpen = false;
  bool _toolsOpen = false;

  /// 移动端发送后保持键盘；用户点消息区空白后置 false，避免发送回调再抢回焦点。
  bool _composerKeepFocus = false;

  /// PC：输入框可拖拽高度（托起消息列表）。
  /// 下限需容纳一行字高 + 上下 padding + 发送按钮行，否则会裁切首行。
  double _pcInputHeight = 108;
  static const double _pcInputHeightMin = 100;
  static const double _pcInputHeightMax = 320;
  final List<_DesktopComposerAttachment> _desktopComposerAttachments =
      <_DesktopComposerAttachment>[];
  static const int _maxDesktopComposerAttachments = 20;
  bool _peerOnline = false;
  int _recordDurationMs = 0;
  String? _error;
  String? _selfAvatarPreset;
  String? _selfAvatarObjectKey;
  String? _selfAvatarUrl;

  /// 上传中气泡预览（微信式圆形进度）。
  Uint8List? _pendingUploadBytes;
  String _pendingUploadKind = '';
  String _pendingUploadName = '';
  int _pendingVideoDurationSec = 0;
  int? _pendingVideoWidth;
  int? _pendingVideoHeight;
  NativeConversation? _conversation;
  List<NativeChatMessage> _messages = const <NativeChatMessage>[];
  List<Map<String, dynamic>> _groupMembers = const <Map<String, dynamic>>[];
  bool _atSheetOpen = false;
  bool _atSheetOpening = false;
  ValueNotifier<String>? _atFilterNotifier;
  bool _syncingAtFilter = false;
  bool _insertingAtMentions = false;
  String _lastComposeText = '';
  Map<int, int> _groupReadMap = const <int, int>{};
  final Map<String, Future<String>> _mediaUrlCache = <String, Future<String>>{};
  ChatMessageQuote? _quoteDraft;

  // 工作群已读不回：与我相关的回复义务（仅 reply_sla 工作群有数据）。
  ReplySlaSnapshot _replySla = ReplySlaSnapshot.empty;
  Timer? _replySlaReloadDebounce;
  Timer? _replySlaTicker;
  int _replySlaLoadSeq = 0;
  // 「去回复」：最早一条未关义务是否在视口内（在则隐藏按钮）。
  // 默认按「已在屏内」藏住，视口量准且确认离开后才出现，避免和 @ 消息同屏时先闪出来。
  // 对应消息发出超过 24 小时后不再作为目标，见 ReplySlaItem.jumpButtonMaxAge。
  bool _replySlaTargetVisible = true;
  int _replySlaTrackedJumpTarget = 0;
  bool _replySlaVisibilityCheckPending = false;
  bool _replySlaVisibilityKeyRetryUsed = false;
  bool _messageMultiSelectMode = false;
  bool _messageActionsMenuOpen = false;
  final Set<int> _multiSelectedMessageIds = <int>{};
  double _lastKeyboardInset = 0;
  String? _composeDraftKey;
  bool _restoringComposeDraft = false;

  bool get _isPrivate => widget.kind == NativeChatKind.private;

  bool get _useDesktopAttachmentStaging =>
      isDesktopCommOnly && isWideChatLayout(context);

  String? _draftKeyFor({
    NativeConversation? conversation,
    int? peerUserId,
    int? conversationId,
  }) {
    final id =
        conversationId ?? conversation?.id ?? widget.conversationHint?.id ?? 0;
    if (id > 0) return ChatComposeDraftStore.keyFor(conversationId: id);
    final peer =
        peerUserId ?? conversation?.peerUserId ?? widget.peerUserIdHint ?? 0;
    if (_isPrivate && peer > 0) {
      return ChatComposeDraftStore.keyFor(peerUserId: peer);
    }
    return null;
  }

  void _persistComposeDraft({bool flush = false}) {
    final key = _composeDraftKey ?? _draftKeyFor(conversation: _conversation);
    if (key == null) return;
    ChatComposeDraftStore.instance.save(
      key,
      _inputController.text,
      flush: flush,
    );
  }

  Future<void> _restoreComposeDraft({NativeConversation? conversation}) async {
    await ChatComposeDraftStore.instance.ensureLoaded();
    if (!mounted) return;
    final key = _draftKeyFor(conversation: conversation ?? _conversation);
    _composeDraftKey = key;
    final draft = ChatComposeDraftStore.instance.textFor(key);
    if (draft == null || draft.isEmpty) return;
    if (_inputController.text.isNotEmpty) return;
    _restoringComposeDraft = true;
    _inputController.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    _lastComposeText = draft;
    _restoringComposeDraft = false;
  }

  void _clearComposeDraft() {
    final key = _composeDraftKey ?? _draftKeyFor(conversation: _conversation);
    ChatComposeDraftStore.instance.clear(key);
    _composeDraftKey = key;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ChatForegroundSync.addListener(_onChatForegroundResumed);
    ChatForegroundSync.addPauseListener(_onChatForegroundPaused);
    _service = ConversationService(session: widget.session);
    if (_supportsMobileEggs) unawaited(_ensureEggSettings());
    ChatFileUploadCoordinator.instance.addListener(_onFileUploadUpdate);
    _realtime = ConversationRealtimeHub.instance.of(widget.session);
    _scrollController.addListener(_onScroll);
    _inputController.addListener(_onComposeInputChanged);
    _inputFocusNode.addListener(_onInputFocusChanged);
    if (widget.conversationHint != null) {
      _conversation = widget.conversationHint;
      _sessionUnreadCount = widget.conversationHint!.unreadCount;
      final cached = ChatMessageCache.instance.peek(
        widget.conversationHint!.id,
      );
      if (cached != null && cached.isNotEmpty) {
        _messages = cached;
        _loading = false;
        _bootstrapped = true;
        if (_sessionUnreadCount > 0) {
          _captureSessionUnread(widget.conversationHint!, cached);
        }
      }
    }
    _syncBackgroundFileUpload();
    // _load 会按 MediaQuery 计算首屏消息数量；initState 阶段尚不能读取
    // inherited widget，等首帧完成后再启动首次加载。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load(silent: _bootstrapped));
    });
    _bootRealtime();
    unawaited(VoiceAsrStore.instance.ensureLoaded());
    unawaited(
      ChatComposeDraftStore.instance.ensureLoaded().then((_) {
        if (mounted) unawaited(_restoreComposeDraft());
      }),
    );
    unawaited(_loadSelfAvatar());
    userAvatarRefresh.addListener(_onSelfAvatarUpdated);
    MeetingLiveController.instance.active.addListener(
      _onMeetingLiveActiveChanged,
    );
    if (isDesktopCommOnly) {
      // 热键全局只注册一次；切会话只更新回调，避免 native unregister abort。
      unawaited(registerDesktopScreenshotHotkey(_onWindowsHotkeyPressed));
      DesktopComposerFocus.addListener(_focusDesktopComposerIfActive);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusDesktopComposerIfActive();
      });
    }
  }

  void _focusDesktopComposerIfActive() {
    if (!isDesktopCommOnly || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!TickerMode.valuesOf(context).enabled) return;
      if (_conversation?.dissolved == true) return;
      if (_voiceMode || _messageMultiSelectMode) return;
      // 历史定位过程中不要抢焦点：requestFocus 会走「回到最新」，把定位冲掉。
      if (_locatedMode || _effectiveFocusMessageId > 0) return;
      _consumePendingComposerDrop();
      _inputFocusNode.requestFocus();
    });
  }

  void _consumePendingComposerDrop() {
    if (!isDesktopCommOnly || !mounted) return;
    if (!TickerMode.valuesOf(context).enabled) return;
    if (_conversation?.dissolved == true) return;
    final convId = _conversation?.id ?? widget.conversationHint?.id ?? 0;
    final peerId = widget.peerUserIdHint ?? _conversation?.peerUserId ?? 0;
    final pending = DesktopComposerPending.take(
      conversationId: convId,
      peerUserId: peerId,
    );
    if (pending == null || pending.isEmpty) return;
    for (final file in pending) {
      _stageDesktopAttachment(
        bytes: file.bytes,
        uploadSource: file.uploadSource,
        fileName: file.fileName,
        mimeType: file.mimeType,
        isImage: file.isImage,
        sourceLabel: file.sourceLabel,
      );
    }
  }

  void _onWindowsHotkeyPressed() {
    unawaited(_desktopScreenshotAndSend());
  }

  void _onFileUploadUpdate() {
    _syncBackgroundFileUpload();
  }

  void _syncBackgroundFileUpload() {
    if (!mounted) return;
    final conversationId =
        _conversation?.id ?? widget.conversationHint?.id ?? 0;
    final job = ChatFileUploadCoordinator.instance.jobForConversation(
      conversationId,
    );
    if (job != null) {
      setState(() {
        _showingBackgroundFileUpload = true;
        _uploading = true;
        _uploadLabel = job.progress >= 0.99 ? '正在完成发送' : '上传文件';
        _uploadProgress = job.progress;
        _pendingUploadBytes = null;
        _pendingUploadKind = 'FILE';
        _pendingUploadName = job.fileName;
      });
      return;
    }
    if (!_showingBackgroundFileUpload) return;
    setState(() {
      _showingBackgroundFileUpload = false;
      _uploading = false;
      _uploadLabel = null;
      _uploadProgress = 0;
      _pendingUploadBytes = null;
      _pendingUploadKind = '';
      _pendingUploadName = '';
    });
    unawaited(_load(silent: true));
  }

  void _onMeetingLiveActiveChanged() {
    if (!MeetingLiveController.instance.isActive || !_voiceMode || !mounted) {
      return;
    }
    setState(() => _voiceMode = false);
  }

  void _onSelfAvatarUpdated() {
    final snap = userAvatarRefresh.snapshotFor(widget.session.userId);
    if (snap == null || !mounted) return;
    setState(() {
      _selfAvatarPreset = snap.avatarPreset.isEmpty ? null : snap.avatarPreset;
      _selfAvatarObjectKey = snap.avatarObjectKey.isEmpty
          ? null
          : snap.avatarObjectKey;
      _selfAvatarUrl = snap.avatarUrl.isEmpty ? null : snap.avatarUrl;
      if (_messages.isNotEmpty) {
        _messages = _enrichMessages(_messages);
      }
    });
  }

  void _toggleEmojiPicker() {
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _emojiOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_emojiOpen || _shouldAnchorMessagesAtTop) return;
      _scrollBottom(force: true, animated: true, gentle: false);
    });
  }

  Future<void> _loadSelfAvatar() async {
    final cached = userAvatarRefresh.snapshotFor(widget.session.userId);
    if (cached != null && mounted) {
      setState(() {
        _selfAvatarPreset = cached.avatarPreset.isEmpty
            ? null
            : cached.avatarPreset;
        _selfAvatarObjectKey = cached.avatarObjectKey.isEmpty
            ? null
            : cached.avatarObjectKey;
        _selfAvatarUrl = cached.avatarUrl.isEmpty ? null : cached.avatarUrl;
      });
      // 已有进程内缓存则不再打 /users/me（资料不会每秒变，勿当心跳）。
      return;
    }
    try {
      final resp = await http.get(
        Uri.parse('${widget.session.apiBase}/users/me'),
        headers: <String, String>{
          'Authorization': 'Bearer ${widget.session.token}',
          'Content-Type': 'application/json',
        },
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300 || !mounted) return;
      final body = jsonDecode(resp.body);
      final data = body is Map<String, dynamic>
          ? (body['data'] is Map<String, dynamic>
                ? body['data'] as Map<String, dynamic>
                : body)
          : const <String, dynamic>{};
      final preset = (data['avatarPreset'] ?? '').toString().trim();
      final objectKey = (data['avatarObjectKey'] ?? '').toString().trim();
      var avatarUrl = (data['avatarUrl'] ?? '').toString().trim();
      if (avatarUrl.isEmpty && objectKey.isNotEmpty) {
        avatarUrl = _service.mediaProxyUrl(objectKey, bucket: 'user-avatars');
      }
      final snapshot = UserAvatarSnapshot(
        userId: widget.session.userId,
        avatarPreset: preset,
        avatarObjectKey: objectKey,
        avatarUrl: avatarUrl,
      );
      userAvatarRefresh.remember(snapshot);
      if (!mounted) return;
      setState(() {
        _selfAvatarPreset = preset.isEmpty ? null : preset;
        _selfAvatarObjectKey = objectKey.isEmpty ? null : objectKey;
        _selfAvatarUrl = avatarUrl.isEmpty ? null : avatarUrl;
        if (_messages.isNotEmpty) {
          _messages = _enrichMessages(_messages);
        }
      });
    } catch (_) {}
  }

  @override
  void didUpdateWidget(NativeChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newFocus = widget.focusMessageId ?? 0;
    final oldFocus = oldWidget.focusMessageId ?? 0;
    final oldConvId = oldWidget.conversationHint?.id ?? 0;
    final newConvId = widget.conversationHint?.id ?? 0;
    final oldPeer = oldWidget.peerUserIdHint ?? 0;
    final newPeer = widget.peerUserIdHint ?? 0;
    final conversationSwitched =
        (newConvId > 0 && newConvId != oldConvId) ||
        (newConvId <= 0 && newPeer > 0 && newPeer != oldPeer);
    if (conversationSwitched) {
      // 同一 State 复用时立即作废旧加载；有缓存则先展示，避免整页转圈。
      _persistComposeDraft(flush: true);
      _loadGeneration++;
      _enterStickBottomPending = true;
      _userInteractedWithScroll = false;
      _locatedMode = false;
      _forceLatestMode = true;
      _suppressedFocusMessageId = 0;
      _pendingStickBottomAfterForeground = false;
      final cachedId = newConvId > 0
          ? newConvId
          : (widget.conversationHint?.id ?? 0);
      final cached = ChatMessageCache.instance.peek(cachedId);
      final hasCache = cached != null && cached.isNotEmpty;
      final hintUnread = widget.conversationHint?.unreadCount ?? 0;
      _restoringComposeDraft = true;
      _inputController.clear();
      _lastComposeText = '';
      _restoringComposeDraft = false;
      _quoteDraft = null;
      _desktopComposerAttachments.clear();
      _desktopAttachmentNotice = null;
      _desktopAttachmentFailed = false;
      setState(() {
        _conversation = widget.conversationHint;
        _messages = hasCache ? cached : const <NativeChatMessage>[];
        _groupMembers = const <Map<String, dynamic>>[];
        _bootstrapped = hasCache;
        _loading = !hasCache;
        _locating = false;
        _error = null;
        _hasMore = false;
        _hasNewer = false;
        _awayFromLatest = false;
        _clearPendingNewMessages();
        _lastMarkedReadNewestId = 0;
        // 进会话立刻用列表未读数种子，避免后续 silent/缓存加载漏捕获。
        _sessionUnreadCount = hintUnread;
        _firstUnreadMessageId = 0;
        _unreadJumpDismissed = false;
        _unreadMessageVisible = false;
        _unreadVisibilityKeyRetryUsed = false;
        _firstUnreadTruncated = false;
        _replySla = ReplySlaSnapshot.empty;
        _replySlaTargetVisible = true;
        _replySlaVisibilityKeyRetryUsed = false;
        _replySlaTrackedJumpTarget = 0;
        _replySlaLoadSeq++;
      });
      if (hasCache && hintUnread > 0 && cached != null) {
        _captureSessionUnread(widget.conversationHint!, cached);
      }
      unawaited(_restoreComposeDraft(conversation: widget.conversationHint));
      unawaited(_load(silent: hasCache));
      _focusDesktopComposerIfActive();
      return;
    }
    final hint = widget.conversationHint;
    final current = _conversation;
    if (hint != null &&
        current != null &&
        hint.id == current.id &&
        (hint.kind != current.kind || hint.replySla != current.replySla)) {
      setState(() {
        _conversation = ConversationInboxRealtime.copyConversation(
          current,
          kind: hint.kind,
          replySla: hint.replySla,
          muted: hint.muted,
        );
      });
      _scheduleReplySlaReload();
    }
    if (newFocus > 0 && newFocus != oldFocus) {
      _forceLatestMode = false;
      _suppressedFocusMessageId = 0;
      _enterStickBottomPending = false;
      unawaited(_load(silent: _bootstrapped));
    }
    if (!oldWidget.autoMarkRead && widget.autoMarkRead) {
      // 恢复已读权限时不要清滚动交互态，否则最小化再回来会误跳到底。
      // 前台补拉由 ChatForegroundSync / lifecycle 统一触发，这里不再二次调用。
      if (widget.autoMarkRead && _isNearBottom && !_isScrolledAwayFromLatest) {
        unawaited(_markReadIfNeeded());
      }
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    if (!_hasStableChatViewport || windowsTrayIsWindowObscured()) {
      _backgroundLayoutActive = true;
      _foregroundPauseWasObscured = true;
      _freezeHistoryViewportForBackground();
    }
    if (_isBrowsingHistory || _locatedMode) return;
    final inset = View.of(context).viewInsets.bottom;
    final keyboardOpening =
        _inputFocusNode.hasFocus && inset > _lastKeyboardInset + 1;
    _lastKeyboardInset = inset;
    if (keyboardOpening && !_shouldAnchorMessagesAtTop) {
      _scrollBottom(force: true, gentle: true);
    } else if (_emojiOpen && !_shouldAnchorMessagesAtTop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _emojiOpen && !_isBrowsingHistory) {
          _scrollBottom(force: true, animated: true, gentle: false);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _onChatForegroundPaused(viewportCollapsed: true);
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _onChatForegroundPaused();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _onChatForegroundResumed();
    }
  }

  void _onChatForegroundPaused({bool viewportCollapsed = false}) {
    // 先快照再标后台，否则 capture 会被 backgroundLayoutActive 跳过。
    // Windows 收起窗口时 reverse 列表可能已经跳到历史方向，
    // 不能用跳变后的 pixels 覆盖「贴底」快照，否则还原后会被当成在看历史并往上拽。
    if (_hasStableChatViewport && !_looksLikeUnsolicitedHistoryJump) {
      _captureStableHistoryViewport(ignoreNoise: true);
    }
    final collapsed =
        viewportCollapsed ||
        windowsTrayIsWindowObscured() ||
        !_hasStableChatViewport;
    _backgroundLayoutActive = true;
    if (collapsed) {
      _foregroundPauseWasObscured = true;
    }
    _freezeHistoryViewportForBackground();
    if (collapsed && !_historyViewportFrozen && !_locatedMode) {
      _pendingStickBottomAfterForeground = true;
    }
  }

  void _onChatForegroundResumed() {
    _foregroundRestoredAt = DateTime.now();
    final needsRepair = chatForegroundNeedsListRepair(
      windowObscured: _foregroundPauseWasObscured,
      viewportCollapsed: !_hasStableChatViewport,
    );
    _foregroundPauseWasObscured = false;
    if (_looksLikeUnsolicitedHistoryJump && !_locatedMode) {
      // 缩小/还原把 reverse 列表拽去历史：贴回最新端，不要 ensureVisible 往上拉。
      _pendingStickBottomAfterForeground = true;
      _scrollBottom(force: true, gentle: false);
    } else if (_isBrowsingHistory) {
      if (!needsRepair && _historyViewportUnchangedSinceSnapshot) {
        // 仅切软件：列表位置没被动过，再按估算锚点 ensureVisible 会每次往上挪一截。
        if (!_olderScrollRestorePending &&
            _scrollRestoreAnchorId == _stableHistoryAnchorId) {
          _scrollRestoreAnchorId = null;
        }
        _finishHistoryViewportRestore();
      } else {
        _restoreHistoryViewportAfterForeground();
      }
    } else if (!_locatedMode && needsRepair) {
      // 最小化/托盘还原：Windows 会把 reverse 列表夹到 0 或拽去历史。
      _pendingStickBottomAfterForeground = true;
      _scrollBottom(force: true, gentle: false);
    } else if (!_locatedMode &&
        (_pendingStickBottomAfterForeground || !_rawPixelsNearLatest)) {
      // 切软件时列表可能漂离最新端；失焦期间来的新消息也只需贴一次底。
      _scrollBottom(force: true, gentle: true);
      _pendingStickBottomAfterForeground = false;
    }
    if (needsRepair) {
      unawaited(_syncLatestOnForeground());
    } else {
      unawaited(_reconnectRealtimeOnForeground());
    }
    // 等视口重新铺开后再允许把滚动当用户操作；过长会卡住滚轮加载历史。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        if (_hasStableChatViewport && !windowsTrayIsWindowInactive()) {
          _backgroundLayoutActive = false;
        }
      });
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        if (!windowsTrayIsWindowInactive()) {
          _backgroundLayoutActive = false;
        }
      });
    });
  }

  /// 从最小化/失焦恢复后：重连 realtime、REST 补最新消息。
  /// 用户正在上滑看历史时只补数据，不强制跳到最新。
  Future<void> _syncLatestOnForeground() async {
    if (!mounted || !_bootstrapped || _loading || _sending || _uploading) {
      return;
    }
    final now = DateTime.now();
    if (_lastForegroundSyncAt != null &&
        now.difference(_lastForegroundSyncAt!) <
            const Duration(milliseconds: 800)) {
      return;
    }
    if (_foregroundSyncRunning) return;
    _lastForegroundSyncAt = now;
    _foregroundSyncRunning = true;
    // 不要用还原后的像素重新冻结：Windows 还原窗口时 reverse 列表会先跳到
    // 历史方向，再冻就会把「贴底」误判成「在看历史」，会话被往上拽。
    final locating = _locatedMode || _effectiveFocusMessageId > 0;
    final browsingHistory = _isBrowsingHistory;
    final nearBottom =
        !browsingHistory &&
        !locating &&
        _hasStableChatViewport &&
        _rawPixelsNearLatest;
    final shouldStick =
        !locating &&
        !browsingHistory &&
        (_pendingStickBottomAfterForeground || nearBottom);
    try {
      await _realtime.connect();
      if (!mounted) return;
      if (shouldStick) {
        _clearStableHistoryViewport();
        _forceLatestMode = true;
        _enterStickBottomPending = true;
      } else if (browsingHistory) {
        _historyViewportFrozen = true;
        _stableAwayFromLatest = true;
        _pendingStickBottomAfterForeground = false;
      }
      await _load(silent: true);
      if (!mounted) return;
      if (shouldStick && !_shouldAnchorMessagesAtTop) {
        _pendingStickBottomAfterForeground = false;
        _scrollBottom(force: true, gentle: false);
      } else {
        // 看历史时清掉误挂起的贴底标记，避免后续仍被拉到底。
        _pendingStickBottomAfterForeground = false;
        if (browsingHistory) {
          _restoreHistoryViewportAfterForeground();
        }
      }
      if (widget.autoMarkRead && shouldStick) {
        unawaited(_markReadIfNeeded());
      }
      if (_isPrivate) {
        unawaited(_refreshPeerReadFromServer());
      }
    } catch (_) {
      // 补同步失败不打断会话；下次前台/实时事件仍可重试。
    } finally {
      _foregroundSyncRunning = false;
    }
  }

  Future<void> _reconnectRealtimeOnForeground() async {
    try {
      await _realtime.connect();
    } catch (_) {}
  }

  @override
  void dispose() {
    _loadGeneration++;
    _replySlaReloadDebounce?.cancel();
    _replySlaTicker?.cancel();
    if (isDesktopCommOnly) {
      clearDesktopScreenshotHotkey(_onWindowsHotkeyPressed);
    }
    WidgetsBinding.instance.removeObserver(this);
    ChatForegroundSync.removeListener(_onChatForegroundResumed);
    ChatForegroundSync.removePauseListener(_onChatForegroundPaused);
    DesktopComposerFocus.removeListener(_focusDesktopComposerIfActive);
    ChatFileUploadCoordinator.instance.removeListener(_onFileUploadUpdate);
    userAvatarRefresh.removeListener(_onSelfAvatarUpdated);
    MeetingLiveController.instance.active.removeListener(
      _onMeetingLiveActiveChanged,
    );
    _rtRefreshDebounce?.cancel();
    _rtSub?.cancel();
    _onlineSub?.cancel();
    _recordTicker?.cancel();
    _highlightTimer?.cancel();
    _inputController.removeListener(_onComposeInputChanged);
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _persistComposeDraft(flush: true);
    _inputFocusNode.dispose();
    _atFilterNotifier?.dispose();
    if (_recording) {
      unawaited(NativeAudioRecorder.instance.cancel());
    }
    unawaited(ChatVoicePlayer.instance.stop());
    _olderScrollHold?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    // 关闭本页 HTTP client，打断未完成请求并释放连接，减轻频繁切会话时的连接压力。
    _service.close();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _scheduleUnreadVisibilityCheck();
    _scheduleReplySlaVisibilityCheck();
    if (_isBackgroundLayoutNoise) {
      // 最小化/视口被夹扁才冻滚动；仅切软件失焦时的 pixels 抖动不要当成在看历史。
      if (_foregroundPauseWasObscured || !_hasStableChatViewport) {
        if (!_historyViewportFrozen && !_locatedMode) {
          _freezeHistoryViewportForBackground();
        }
        if (_pendingStickBottomAfterForeground &&
            !_historyViewportFrozen &&
            !_rawPixelsNearLatest) {
          _scrollBottom(force: true, gentle: true);
        }
      }
      return;
    }
    if (_historyViewportFrozen) {
      // 只有用户真的在滚，才解除冻结；还原窗口造成的 pixels 变化不能解冻。
      if (_userScrollActive && !_rawPixelsNearLatest) {
        _historyViewportFrozen = false;
      } else {
        return;
      }
    }
    final viewportUnstable = pos.viewportDimension <= 80;
    final jumpedAway = _looksLikeUnsolicitedHistoryJump;
    if (viewportUnstable || _looksLikeBackgroundScrollClamp || jumpedAway) {
      if (_enterStickBottomPending || _forceLatestMode) {
        return;
      }
      _freezeHistoryViewportForBackground();
      if (jumpedAway && !_historyViewportFrozen && !_locatedMode) {
        _pendingStickBottomAfterForeground = true;
        _scrollBottom(force: true, gentle: true);
      }
      return;
    }
    // 定位动画期间不要补历史、不要改贴底状态，否则会和 ensureVisible 对拉。
    if (_messageLocateSettling) {
      if (pos.pixels > 72) {
        _enterStickBottomPending = false;
      }
      return;
    }
    // 用户已上滑离开最新端时，清掉进会话贴底标记，避免后续补历史被拽回底部。
    if (pos.pixels > 72) {
      _enterStickBottomPending = false;
      _captureStableHistoryViewport();
    }
    // reverse 列表：scroll≈0 为最新消息（靠近输入框），maxScrollExtent 为历史方向。
    // PC 宽屏 shrinkWrap 时，消息未撑满视口会出现 maxScrollExtent≈0，
    // 此时仍应自动拉更早消息，不能只依赖「滑到顶」。
    // 注意：加载历史时不要 return，否则定位模式下无法继续触发「加载更新」。
    if (!_loadingOlder &&
        !_olderScrollRestorePending &&
        _shouldAutoloadOlder(pos)) {
      unawaited(_loadOlder());
    }
    if (_shouldAutoloadNewer(pos)) {
      unawaited(_loadNewer());
    }
    // 手指拖动或惯性滑动期间不刷新 UI，避免滚动中 setState 导致卡顿。
    if (!_userScrollActive) {
      _updateStickBottomState();
    }
  }

  /// 定位模式下滑向更新端时自动续拉（需用户已滚动，避免定位落地后连拉到最新）。
  bool _shouldAutoloadNewer(ScrollPosition pos) {
    if (!_locatedMode || !_hasNewer || _loadingNewer) return false;
    if (_messageLocateSettling || !_userInteractedWithScroll) return false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs < _newerLoadCooldownUntilMs) return false;
    return pos.pixels <= 72;
  }

  /// 是否应自动加载更早消息（含：已顶到历史端 / 列表尚未撑满视口）。
  bool _shouldAutoloadOlder(ScrollPosition pos) {
    if (!_hasMore ||
        _loadingOlder ||
        _olderScrollRestorePending ||
        !_hasStableChatViewport ||
        _historyViewportFrozen ||
        _messageLocateSettling) {
      return false;
    }
    // 还原窗口时的程序化滚动不要去补历史（ensureVisible 会把会话往上拽）。
    // 最小化前贴底时仍允许续拉填满视口，且走贴底分支。
    if (_isBackgroundLayoutNoise && !_pendingStickBottomAfterForeground) {
      return false;
    }
    if (_looksLikeUnsolicitedHistoryJump) return false;
    // 定位落地后未动手滚动前不要自动补历史，否则 prepend 会把视口拽来拽去。
    if (_locatedMode && !_userInteractedWithScroll) return false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs < _olderLoadCooldownUntilMs) return false;
    // 内容撑不满：无法靠「滑到顶」触发，直接续拉。
    if (pos.maxScrollExtent <= 24) return true;
    final edge = math.max(120.0, pos.viewportDimension * 0.35);
    return pos.pixels >= pos.maxScrollExtent - edge;
  }

  void _scheduleAutoloadOlderToFill({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || attempt > 12) return;
      if (!_scrollController.hasClients) {
        _scheduleAutoloadOlderToFill(attempt: attempt + 1);
        return;
      }
      if (!_shouldAutoloadOlder(_scrollController.position)) return;
      unawaited(
        _loadOlder().whenComplete(() {
          if (!mounted) return;
          _scheduleAutoloadOlderToFill();
        }),
      );
    });
  }

  /// 鼠标滚轮 / 触控板：上滑加载历史，下滑（定位模式）加载更新消息。
  void _onMessageListPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_scrollController.hasClients) return;
    _lastPointerSignalScrollAt = DateTime.now();
    _userInteractedWithScroll = true;
    _enterStickBottomPending = false;
    final pos = _scrollController.position;
    // reverse 列表：dy<0 朝历史；dy>0 朝更新。
    if (event.scrollDelta.dy < 0) {
      _lastUserScrollTowardLatestAt = null;
      if (!_hasMore || _loadingOlder || _olderScrollRestorePending) return;
      if (pos.maxScrollExtent <= 24 ||
          pos.pixels >=
              pos.maxScrollExtent -
                  math.max(160.0, pos.viewportDimension * 0.4)) {
        unawaited(_loadOlder());
      }
      return;
    }
    if (event.scrollDelta.dy > 0) {
      _lastUserScrollTowardLatestAt = DateTime.now();
    }
    if (event.scrollDelta.dy > 0 && _shouldAutoloadNewer(pos)) {
      unawaited(_loadNewer());
    }
  }

  int get _newestMessageId {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final id = _messages[i].id;
      if (id > 0) return id;
    }
    return 0;
  }

  void _updateStickBottomState() {
    if (_locatedMode) {
      if (_pendingNewMessageCount != 0 || _awayFromLatest) {
        setState(() {
          _pendingNewMessageCount = 0;
          _awayFromLatest = false;
        });
      }
      return;
    }
    if (!_hasStableChatViewport) {
      _freezeHistoryViewportForBackground();
      return;
    }
    if (_isBackgroundLayoutNoise) return;
    if (_looksLikeUnsolicitedHistoryJump) {
      _pendingStickBottomAfterForeground = true;
      return;
    }
    if (_historyViewportFrozen) return;
    if (_looksLikeBackgroundScrollClamp) {
      _freezeHistoryViewportForBackground();
      return;
    }
    _captureStableHistoryViewport();
    final near = _isNearBottom;
    final away = _isScrolledAwayFromLatest;
    var nextPending = _pendingNewMessageCount;
    if (near) {
      _bottomAnchorMessageId = _newestMessageId;
      nextPending = 0;
    } else {
      if (_wasNearBottom) {
        _bottomAnchorMessageId = _newestMessageId;
      }
      final anchor = _bottomAnchorMessageId;
      if (anchor > 0) {
        nextPending = _messages.where((m) => m.id > anchor).length;
      }
    }
    _wasNearBottom = near;
    if (_awayFromLatest != away || _pendingNewMessageCount != nextPending) {
      setState(() {
        _awayFromLatest = away;
        _pendingNewMessageCount = nextPending;
      });
    }
  }

  void _recountPendingNewMessages() {
    if (_locatedMode || _isNearBottom) return;
    final anchor = _bottomAnchorMessageId;
    if (anchor <= 0) return;
    final count = _messages.where((m) => m.id > anchor).length;
    if (count == _pendingNewMessageCount && _awayFromLatest) return;
    setState(() {
      _pendingNewMessageCount = count;
      _awayFromLatest = true;
    });
  }

  void _clearPendingNewMessages() {
    _bottomAnchorMessageId = _newestMessageId;
    _pendingNewMessageCount = 0;
    _awayFromLatest = false;
    _wasNearBottom = true;
    _clearStableHistoryViewport();
  }

  void _rememberCachedMessages() {
    final id = _conversation?.id ?? 0;
    if (id <= 0 || _messages.isEmpty) return;
    ChatMessageCache.instance.put(id, _messages);
  }

  void _flushDeferredRealtimePaint() {
    if (!_realtimePaintDeferred) return;
    _realtimePaintDeferred = false;
    if (!mounted) return;
    setState(() {});
    if (_isBrowsingHistory || !_isNearBottom) return;
    if (windowsTrayIsWindowInactive()) {
      _pendingStickBottomAfterForeground = true;
    } else {
      _scrollToPreferredAnchor(gentle: true);
    }
    unawaited(_markReadIfNeeded());
  }

  Future<void> _jumpToPendingMessages() async {
    if (_locatedMode) {
      await _jumpToLatest();
      return;
    }
    setState(_clearPendingNewMessages);
    _scrollBottom(animated: true, force: true);
    _userInteractedWithScroll = true;
    unawaited(_markReadIfNeeded());
  }

  Future<void> _bootRealtime() async {
    try {
      await _realtime.connect();
      if (_isPrivate) {
        _onlineSub = _realtime.trackOnlineUsers((ids) {
          final peerId = _conversation?.peerUserId ?? 0;
          final online = peerId > 0 && ids.contains(peerId);
          if (!mounted || _peerOnline == online) return;
          setState(() => _peerOnline = online);
          if (online) unawaited(_refreshPeerReadFromServer());
        });
        unawaited(_realtime.refreshOnlinePresence());
      }
      _rtSub = _realtime.events.listen(_onRealtimeEvent);
    } catch (_) {}
  }

  void _onRealtimeEvent(ConversationRealtimeEvent event) {
    if (event.type == 'im_status') {
      _applyPeerImStatusEvent(event);
      return;
    }
    final convId = _conversation?.id ?? 0;
    if (convId <= 0) return;
    if (event.conversationId != null && event.conversationId != convId) return;
    if (event.type == 'reply_sla_changed') {
      _scheduleReplySlaReload();
      return;
    }
    if (event.type == 'conversation_updated' &&
        event.raw['groupTypeChanged'] == true) {
      unawaited(_refreshConversationKind());
      return;
    }

    final isNew = _realtimeDedup.consume(event);
    var handled = false;

    if (event.type == 'message' || event.type == 'system_flow') {
      handled = _appendRealtimeMessage(event, allowDup: !isNew);
    } else if (event.type == 'message_recalled') {
      handled = _patchRecalledMessage(event);
    } else if (event.type == 'message_updated') {
      handled = _patchUpdatedMessage(event);
    } else if (event.type == 'message_deleted') {
      handled = _removeDeletedMessage(event);
    } else if (event.type == 'message_pinned' ||
        event.type == 'message_unpinned') {
      handled = _applyPinnedMessagesEvent(event);
    } else if (event.type == 'read') {
      handled = _handleReadEvent(event);
    }

    if (!handled) {
      _scheduleRealtimeRefresh();
    }
  }

  Future<void> _refreshConversationKind() async {
    final id = _conversation?.id ?? 0;
    if (id <= 0) return;
    try {
      final fresh = await _service.fetchConversation(id);
      if (fresh == null || !mounted || (_conversation?.id ?? 0) != id) return;
      setState(() {
        final current = _conversation;
        if (current == null) return;
        _conversation = ConversationInboxRealtime.copyConversation(
          current,
          kind: fresh.kind,
          replySla: fresh.replySla,
          muted: fresh.muted,
        );
      });
      _scheduleReplySlaReload();
    } catch (_) {}
  }

  void _applyPeerImStatusEvent(ConversationRealtimeEvent event) {
    if (!_isPrivate || !mounted) return;
    final conv = _conversation;
    if (conv == null || conv.isSelfMemo) return;
    final userId = (event.raw['userId'] as num?)?.toInt() ?? 0;
    final peerId = conv.peerUserId ?? 0;
    if (userId <= 0 || peerId <= 0 || userId != peerId) return;
    final parsed = ImUserStatusCatalog.parse(
      status: event.raw['status']?.toString(),
      text: event.raw['text']?.toString(),
      icon: event.raw['icon']?.toString(),
      color: event.raw['color']?.toString(),
    );
    if (parsed.key == conv.peerImStatus &&
        parsed.text == conv.peerImStatusText &&
        parsed.icon == conv.peerImStatusIcon &&
        parsed.color == conv.peerImStatusColor) {
      return;
    }
    setState(() {
      _conversation = ConversationInboxRealtime.copyConversation(
        conv,
        peerImStatus: parsed.key,
        peerImStatusText: parsed.text,
        peerImStatusIcon: parsed.icon,
        peerImStatusColor: parsed.color,
      );
    });
  }

  bool _applyPinnedMessagesEvent(ConversationRealtimeEvent event) {
    final rawItems = event.raw['items'];
    if (rawItems is! List) {
      unawaited(_refreshPinnedMessages());
      return true;
    }
    final items = rawItems
        .whereType<Map>()
        .map((e) => _service.mapPinnedMessage(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    if (!mounted) return true;
    setState(() {
      _pinnedMessages = items;
      if (items.length <= 1) _pinnedExpanded = false;
    });
    return true;
  }

  bool _appendRealtimeMessage(
    ConversationRealtimeEvent event, {
    required bool allowDup,
  }) {
    final raw = event.raw['message'];
    if (raw is! Map<String, dynamic>) return false;
    final msg = _service.mapMessage(raw);
    if (msg.id <= 0) return false;
    if (!allowDup && _messages.any((m) => m.id == msg.id)) return true;
    if (_messages.any((m) => m.id == msg.id)) return true;

    final stickBottom = !_isBrowsingHistory && _isNearBottom;
    final prevNewestId = _newestMessageId;
    void apply() {
      _messages = _mergeMessages(_messages, [msg]);
      if (stickBottom) {
        _clearPendingNewMessages();
      } else {
        if (_bottomAnchorMessageId <= 0) {
          _bottomAnchorMessageId = prevNewestId;
        }
        _pendingNewMessageCount = _messages
            .where((m) => m.id > _bottomAnchorMessageId)
            .length;
      }
    }

    if (_userScrollActive) {
      apply();
      _realtimePaintDeferred = true;
      _rememberCachedMessages();
    } else {
      setState(apply);
      _rememberCachedMessages();
    }
    if (_userScrollActive) {
      if (_isPrivate && msg.senderUserId != widget.session.userId) {
        unawaited(_refreshPeerReadFromServer());
      }
      _maybePlayIncomingEgg(msg);
      return true;
    }
    if (stickBottom) {
      // 最小化/失焦时 gentle 贴底常空跑；记下来等恢复前台再强制滚到底。
      if (windowsTrayIsWindowInactive()) {
        _pendingStickBottomAfterForeground = true;
      } else {
        _scrollToPreferredAnchor(gentle: true);
      }
      // 只有正在看本会话且贴在最新端时才标已读；看历史/后台 keep-alive 不标。
      unawaited(_markReadIfNeeded());
    }
    if (_isPrivate && msg.senderUserId != widget.session.userId) {
      unawaited(_refreshPeerReadFromServer());
    }
    _maybePlayIncomingEgg(msg);
    return true;
  }

  Future<void> _maybePlayIncomingEgg(NativeChatMessage message) async {
    if (!_supportsMobileEggs ||
        message.senderUserId == widget.session.userId ||
        message.kind.toUpperCase() != 'TEXT' ||
        !_canPlayChatEffect) {
      return;
    }
    final effectOverlay = Overlay.maybeOf(context, rootOverlay: true);
    if (effectOverlay == null) return;
    await _ensureEggSettings();
    if (!ImEggSettings.instance.activeReceiverEnabled) return;
    final effect = matchImEggEffect(message.bodyText);
    if (effect == null) return;
    final conversationId = _conversation?.id ?? 0;
    if (!ImEggPlaybackStore.allowEffect(
      userId: widget.session.userId,
      conversationId: conversationId,
      maxPer10Minutes: ImEggSettings.instance.maxPer10Minutes,
    )) {
      return;
    }
    final shouldPlay = await ImEggPlaybackStore.markPlayed(
      userId: widget.session.userId,
      conversationId: conversationId,
      messageId: message.id,
    );
    if (!shouldPlay || _conversation?.id != conversationId) {
      return;
    }
    if (!effectOverlay.mounted || !_canPlayChatEffect) return;
    showImEggEffectOnOverlay(effectOverlay, effect, seed: message.id);
  }

  bool get _canPlayChatEffect =>
      mounted &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  bool get _supportsMobileEggs =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<void> _ensureEggSettings() => ImEggSettings.instance.ensureLoaded(
    apiBase: widget.session.apiBase,
    token: widget.session.token,
  );

  Future<void> _replayLatestUnreadEgg(
    List<NativeChatMessage> messages,
    int conversationId,
  ) async {
    if (!_supportsMobileEggs) return;
    final effectOverlay = Overlay.maybeOf(context, rootOverlay: true);
    if (effectOverlay == null) return;
    await _ensureEggSettings();
    if (!ImEggSettings.instance.replayLatestOnOpen ||
        !ImEggSettings.instance.activeReceiverEnabled) {
      return;
    }
    if (_sessionUnreadCount <= 0 || _firstUnreadMessageId <= 0) return;
    final candidates = messages
        .where(
          (message) =>
              message.id >= _firstUnreadMessageId &&
              message.senderUserId != widget.session.userId &&
              message.kind.toUpperCase() == 'TEXT' &&
              matchImEggEffect(message.bodyText) != null,
        )
        .toList(growable: false);
    if (candidates.isEmpty) return;
    final latest = candidates.last;
    final lastPlayed = await ImEggPlaybackStore.lastPlayedId(
      widget.session.userId,
      conversationId,
    );
    if (latest.id <= lastPlayed ||
        !mounted ||
        _conversation?.id != conversationId) {
      return;
    }
    if (!_canPlayChatEffect ||
        !ImEggPlaybackStore.allowEffect(
          userId: widget.session.userId,
          conversationId: conversationId,
          maxPer10Minutes: ImEggSettings.instance.maxPer10Minutes,
        )) {
      return;
    }
    final effect = matchImEggEffect(latest.bodyText);
    if (effect == null) return;
    final shouldPlay = await ImEggPlaybackStore.markPlayed(
      userId: widget.session.userId,
      conversationId: conversationId,
      messageId: latest.id,
    );
    if (!shouldPlay || _conversation?.id != conversationId) {
      return;
    }
    if (!effectOverlay.mounted || !_canPlayChatEffect) return;
    showImEggEffectOnOverlay(effectOverlay, effect, seed: latest.id);
  }

  bool _patchRecalledMessage(ConversationRealtimeEvent event) {
    final recallId =
        (event.raw['messageId'] as num?)?.toInt() ??
        ((event.raw['message'] is Map<String, dynamic>)
            ? ((event.raw['message'] as Map<String, dynamic>)['id'] as num?)
                  ?.toInt()
            : null);
    if (recallId == null || recallId <= 0) return false;
    final index = _messages.indexWhere((m) => m.id == recallId);
    if (index < 0) return false;
    final preview = (event.raw['preview'] ?? '').toString();
    final recalledByName =
        (event.raw['recalledByDisplayName'] ??
                event.raw['recalledByName'] ??
                '')
            .toString()
            .trim();
    final old = _messages[index];
    final mine = old.senderUserId == widget.session.userId;
    final who = mine
        ? '你'
        : (recalledByName.isNotEmpty ? recalledByName : old.senderName);
    final text = preview.contains('撤回')
        ? preview
        : '${who.isEmpty ? '对方' : who}撤回了一条消息';
    setState(() {
      final next = List<NativeChatMessage>.from(_messages);
      next[index] = NativeChatMessage(
        id: old.id,
        senderUserId: old.senderUserId,
        senderName: old.senderName,
        kind: 'SYSTEM',
        bodyText: text,
        createdAt: old.createdAt,
        payload: old.payload,
        peerRead: old.peerRead,
      );
      _messages = next;
    });
    return true;
  }

  bool _patchUpdatedMessage(ConversationRealtimeEvent event) {
    final raw = event.raw['message'];
    if (raw is! Map<String, dynamic>) return false;
    final msg = _service.mapMessage(raw);
    if (msg.id <= 0) return false;
    final index = _messages.indexWhere((m) => m.id == msg.id);
    if (index < 0) return false;
    setState(() {
      final next = List<NativeChatMessage>.from(_messages);
      next[index] = msg;
      _messages = next;
    });
    return true;
  }

  bool _removeDeletedMessage(ConversationRealtimeEvent event) {
    final mid =
        (event.raw['messageId'] as num?)?.toInt() ??
        ((event.raw['message'] is Map<String, dynamic>)
            ? ((event.raw['message'] as Map<String, dynamic>)['id'] as num?)
                  ?.toInt()
            : null);
    if (mid == null || mid <= 0) return false;
    if (!_messages.any((m) => m.id == mid)) return false;
    setState(() => _messages = _messages.where((m) => m.id != mid).toList());
    return true;
  }

  bool _handleReadEvent(ConversationRealtimeEvent event) {
    final userId = _realtimeInt(event.raw['userId']);
    if (userId <= 0 || userId == widget.session.userId) return true;
    final lastRead = _realtimeInt(
      event.raw['lastReadMessageId'] ??
          event.raw['readMessageId'] ??
          event.raw['messageId'],
    );
    if (lastRead <= 0) {
      // 实时包缺字段时回源校验，避免一直停在「未读」。
      unawaited(_refreshPeerReadFromServer());
      return true;
    }
    _applyPeerLastRead(lastRead);
    return true;
  }

  /// 实时/JSON 字段兼容 num / 数字字符串。
  int _realtimeInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  /// 仅依据服务端返回的 peerLastReadMessageId 推进「已读」状态。
  /// 不再因为对方仅仅在线（presence）就假设其已读，避免对方尚未进入会话
  /// 却在发送方界面显示「已读」的 bug。
  void _applyPeerLastRead(int lastRead) {
    if (lastRead <= _peerLastReadMessageId) return;
    setState(() {
      _peerLastReadMessageId = lastRead;
      _messages = _messages
          .map(
            (m) => NativeChatMessage(
              id: m.id,
              senderUserId: m.senderUserId,
              senderName: m.senderName,
              kind: m.kind,
              bodyText: m.bodyText,
              createdAt: m.createdAt,
              payload: m.payload,
              peerRead: m.id <= _peerLastReadMessageId || m.peerRead,
              senderAvatarPreset: m.senderAvatarPreset,
              senderAvatarObjectKey: m.senderAvatarObjectKey,
            ),
          )
          .toList(growable: false);
    });
  }

  Future<void> _refreshPeerReadFromServer() async {
    final conv = _conversation;
    if (conv == null || !_isPrivate) return;
    try {
      final page = await _service.fetchMessagePage(conv.id, size: 1);
      final lastRead = page.peerLastReadMessageId ?? 0;
      if (!mounted || lastRead <= 0) return;
      _applyPeerLastRead(lastRead);
    } catch (_) {}
  }

  Future<void> _openChatVideo(Map<String, dynamic>? payload) async {
    // 点开视频即视为已读会话（避免定位进会话 / 未贴底时漏报已读，发送方一直「未读」）。
    unawaited(_markReadIfNeeded());
    if (!mounted) return;
    await showChatVideoPlayer(context, service: _service, payload: payload);
  }

  Future<void> _markReadIfNeeded() async {
    if (!_canMarkReadNow) return;
    // PC 最小化/失焦/托盘时禁止已读上报，保持未读并驱动托盘闪烁。
    if (windowsTrayIsWindowInactive()) return;
    final conv = _conversation;
    if (conv == null) return;
    final newest = _newestMessageId;
    if (newest <= 0 || newest <= _lastMarkedReadNewestId) return;
    print(
      '[ChatRead] mark conv=${conv.id} newest=$newest '
      'auto=${widget.autoMarkRead} scroll=$_userInteractedWithScroll',
    );
    await _service.markConversationRead(conv.id);
    _lastMarkedReadNewestId = newest;
    widget.onConversationRead?.call(conv.id);
  }

  /// 仅当前真正正在看该会话（autoMarkRead=true）时才允许标已读。
  /// 不能用 `_userInteractedWithScroll` 放行：双栏 keep-alive 的后台会话
  /// 若曾滚过，会在用户已回列表时仍把新消息标成已读。
  bool get _canMarkReadNow =>
      !windowsTrayIsWindowInactive() && widget.autoMarkRead;

  bool get _mediaBusy => _uploading;

  bool get _supportsDesktopFileDrop => !kIsWeb && isDesktopCommOnly;

  bool _onMessageListScroll(ScrollNotification notification) {
    // 手指拖动 / 惯性：记为用户交互，并取消进会话贴底。
    if (notification is UserScrollNotification ||
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null)) {
      _userInteractedWithScroll = true;
      _enterStickBottomPending = false;
    }
    // PC 滚轮常无 dragDetails；必须有最近的 PointerScroll，才能当成用户滚动。
    // 否则 Windows 最小化/还原时 reverse 列表的程序化 delta 会被误判成上滑。
    if (isDesktopCommOnly &&
        notification is ScrollUpdateNotification &&
        notification.dragDetails == null &&
        (notification.scrollDelta ?? 0).abs() > 0.5 &&
        _hasRecentPointerScroll) {
      _userInteractedWithScroll = true;
      _enterStickBottomPending = false;
    }
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final scrollDelta = notification.scrollDelta ?? 0;
      // ScrollPosition 的 delta<0 表示 reverse 列表朝 pixels=0（最新端）移动。
      // 无 dragDetails 的 PC 滚轮方向已由 PointerSignal 记录，避免把最小化
      // 造成的程序化 clamp 误认成用户主动回到底部。
      if (scrollDelta < -0.5) {
        _lastUserScrollTowardLatestAt = DateTime.now();
      } else if (scrollDelta > 0.5) {
        _lastUserScrollTowardLatestAt = null;
      }
    }
    // 鼠标滚轮 / 触控板：用通知兜底触发历史/更新消息加载（不依赖 dragDetails）。
    if (notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      if (_scrollController.hasClients) {
        final pos = _scrollController.position;
        if (_shouldAutoloadOlder(pos)) {
          unawaited(_loadOlder());
        }
        if (_shouldAutoloadNewer(pos)) {
          unawaited(_loadNewer());
        }
      }
    }
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _scheduleUnreadVisibilityCheck();
    }
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) {
        _userScrollActive = true;
      }
    } else if (notification is ScrollUpdateNotification) {
      if (notification.dragDetails != null) {
        _userScrollActive = true;
      }
    } else if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        _userScrollActive = true;
      }
    } else if (notification is ScrollEndNotification) {
      _userScrollActive = false;
      _flushDeferredRealtimePaint();
      if (!_isBackgroundLayoutNoise && !_looksLikeUnsolicitedHistoryJump) {
        _updateStickBottomState();
      }
      if (_canMarkReadNow && _isNearBottom) {
        unawaited(_markReadIfNeeded());
      }
    }
    return false;
  }

  bool get _hasRecentUserScrollTowardLatest {
    final at = _lastUserScrollTowardLatestAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < const Duration(milliseconds: 480);
  }

  bool get _hasRecentPointerScroll {
    final at = _lastPointerSignalScrollAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < const Duration(milliseconds: 480);
  }

  bool get _isForegroundSettling {
    final at = _foregroundRestoredAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < const Duration(milliseconds: 900);
  }

  /// 最小化收起、还原窗口、视口尚未铺开时的程序化滚动，不能当成用户上滑。
  bool get _isBackgroundLayoutNoise {
    if (windowsTrayIsWindowInactive()) return true;
    if (_backgroundLayoutActive) return true;
    if (_scrollController.hasClients &&
        _scrollController.position.viewportDimension <= 80) {
      return true;
    }
    return _isForegroundSettling &&
        !_userScrollActive &&
        !_hasRecentPointerScroll;
  }

  /// 贴在最新端时，缩小/还原窗口会把 reverse 列表一次性拽去历史。
  /// 没有滚轮/拖动就不能记成用户上滑，否则会补历史并把会话往上拽。
  bool get _looksLikeUnsolicitedHistoryJump {
    if (_locatedMode || _historyViewportFrozen) return false;
    if (!_scrollController.hasClients) return false;
    return chatForegroundJumpedAwayFromLatest(
      userScrolling: _userScrollActive || _hasRecentPointerScroll,
      wasAwayFromLatest: _stableAwayFromLatest,
      pixelsAwayFromLatest: _scrollController.position.pixels > 140,
    );
  }

  /// 最小化等后台场景会把 reverse 列表一下子夹到 0；用户自己滑回底部、
  /// 或点「回到最新」则不要当成夹死。
  bool get _looksLikeBackgroundScrollClamp {
    if (!_rawPixelsNearLatest) return false;
    if (_hasRecentUserScrollTowardLatest) return false;
    if (_enterStickBottomPending || _forceLatestMode) return false;
    return _stableAwayFromLatest || _stableHistoryPixels > 140;
  }

  bool get _rawPixelsNearLatest {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels <= 72;
  }

  bool get _isNearBottom {
    // 冻结看历史时 pixels 可能已被夹到 0，不能当成贴底。
    if (_historyViewportFrozen) return false;
    // 最小化前贴在最新端：还原窗口时 pixels 会先跳到历史方向。
    if (_pendingStickBottomAfterForeground && !_stableAwayFromLatest) {
      return true;
    }
    return _rawPixelsNearLatest;
  }

  /// 上滑超过该阈值才显示「回到最新」，避免轻微滚动闪一下。
  bool get _isScrolledAwayFromLatest {
    if (_historyViewportFrozen) return true;
    if (!_scrollController.hasClients) return false;
    return _scrollController.position.pixels > 140;
  }

  bool get _hasStableChatViewport {
    if (!_scrollController.hasClients) return false;
    return _scrollController.position.viewportDimension > 80;
  }

  /// 用户正在看历史。最小化后 pixels 会被夹到 0，必须优先用冻结快照。
  bool get _isBrowsingHistory {
    if (_locatedMode) return false;
    // 最小化前贴在最新端：还原时列表会往上跳，不能当成在看历史。
    if (_pendingStickBottomAfterForeground && !_historyViewportFrozen) {
      return false;
    }
    if (_looksLikeUnsolicitedHistoryJump) return false;
    if (_historyViewportFrozen || _stableAwayFromLatest) return true;
    if (!_hasStableChatViewport) return false;
    return !_rawPixelsNearLatest &&
        (_isScrolledAwayFromLatest || _userInteractedWithScroll);
  }

  void _captureStableHistoryViewport({bool ignoreNoise = false}) {
    if (_historyViewportFrozen) return;
    if (!ignoreNoise && _isBackgroundLayoutNoise) return;
    if (!ignoreNoise && _looksLikeUnsolicitedHistoryJump) return;
    if (!_hasStableChatViewport) return;
    final away =
        !_rawPixelsNearLatest &&
        (_scrollController.position.pixels > 140 || _userInteractedWithScroll);
    _stableAwayFromLatest = away;
    if (!away) {
      _stableHistoryPixels = 0;
      _stableHistoryAnchorId = 0;
      return;
    }
    _stableHistoryPixels = _scrollController.position.pixels;
    _stableHistoryAnchorId =
        _topVisibleMessageId() ?? _bottomVisibleMessageId() ?? 0;
  }

  void _freezeHistoryViewportForBackground() {
    if (_locatedMode || _historyViewportFrozen) return;
    // 窗口正在收起时 pixels 已不可信，只用上一帧稳定快照。
    if (_hasStableChatViewport &&
        !windowsTrayIsWindowInactive() &&
        !_backgroundLayoutActive) {
      _captureStableHistoryViewport();
    }
    if (_stableAwayFromLatest ||
        _awayFromLatest ||
        _stableHistoryPixels > 140) {
      _historyViewportFrozen = true;
      _stableAwayFromLatest = true;
      _pendingStickBottomAfterForeground = false;
      if (_stableHistoryAnchorId > 0 && !_olderScrollRestorePending) {
        _scrollRestoreAnchorId = _stableHistoryAnchorId;
      }
    }
  }

  bool get _historyViewportUnchangedSinceSnapshot {
    if (!_hasStableChatViewport) return false;
    final saved = _stableHistoryPixels;
    if (saved <= 72) return false;
    return (_scrollController.position.pixels - saved).abs() <= 2.0;
  }

  void _clearStableHistoryViewport() {
    _stableAwayFromLatest = false;
    _stableHistoryPixels = 0;
    _stableHistoryAnchorId = 0;
    _historyViewportFrozen = false;
  }

  void _restoreHistoryViewportAfterForeground({int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_stableAwayFromLatest && !_historyViewportFrozen) return;
      if (!_scrollController.hasClients || !_hasStableChatViewport) {
        if (attempt < 16) {
          _restoreHistoryViewportAfterForeground(attempt: attempt + 1);
        }
        return;
      }
      final anchorId = _stableHistoryAnchorId;
      if (anchorId > 0) {
        final ctx = _scrollRestoreKeys[anchorId]?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.08,
            duration: Duration.zero,
          );
          _finishHistoryViewportRestore();
          return;
        }
        final entries = _buildListEntries();
        final listIndex = _listIndexForMessageId(anchorId, entries);
        if (listIndex != null) {
          _scrollToListIndex(listIndex, entries);
          _finishHistoryViewportRestore();
          return;
        }
      }
      final pixels = _stableHistoryPixels;
      if (pixels > 72) {
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(pixels.clamp(0.0, max));
        _finishHistoryViewportRestore();
        return;
      }
      if (attempt < 16) {
        _restoreHistoryViewportAfterForeground(attempt: attempt + 1);
        return;
      }
      // 视口始终没落地也不要贴底；保持冻结直到用户自己滚动。
    });
  }

  void _finishHistoryViewportRestore() {
    if (_rawPixelsNearLatest && _stableHistoryPixels > 72) {
      _historyViewportFrozen = true;
      _stableAwayFromLatest = true;
      return;
    }
    _historyViewportFrozen = false;
    _captureStableHistoryViewport();
    _updateStickBottomState();
  }

  int get _listFooterCount => (_locatedMode && _hasNewer) ? 1 : 0;

  /// reverse 列表视觉顶部：加载更早消息入口（对齐 admin-web）。
  int get _listHeaderCount => _hasMore ? 1 : 0;

  _ChatListEntry? _entryForListIndex(int index, List<_ChatListEntry> entries) {
    final footer = _listFooterCount;
    final header = _listHeaderCount;
    if (footer > 0 && index == 0) return null;
    final contentCount = entries.length + footer;
    if (header > 0 && index >= contentCount) return null;
    final adj = index - footer;
    final entryIndex = entries.length - 1 - adj;
    if (entryIndex < 0 || entryIndex >= entries.length) return null;
    return entries[entryIndex];
  }

  ScrollPhysics _chatListScrollPhysics(_ChatScrollMetrics metrics) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AlwaysScrollableScrollPhysics(
          parent: _ChatScrollPhysics(
            flingVelocityCap: metrics.maxFlingVelocity,
            dragDampingFactor: metrics.dragDamping,
            parent: const BouncingScrollPhysics(),
          ),
        );
      default:
        return AlwaysScrollableScrollPhysics(
          parent: _ChatScrollPhysics(
            flingVelocityCap: metrics.maxFlingVelocity,
            dragDampingFactor: metrics.dragDamping,
            parent: const ClampingScrollPhysics(),
          ),
        );
    }
  }

  _ChatScrollMetrics _scrollMetricsForScreen() {
    if (!mounted) {
      return _ChatScrollMetrics.fromScreenHeight(780);
    }
    return _ChatScrollMetrics.fromScreenHeight(
      MediaQuery.sizeOf(context).height,
    );
  }

  int? _listIndexForMessageId(int messageId, List<_ChatListEntry> entries) {
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].message?.id == messageId) {
        return _listFooterCount + (entries.length - 1 - i);
      }
    }
    return null;
  }

  int? _findMessageListChildIndex(Key key) {
    final entries = _buildListEntries();
    if (key is ValueKey<int>) {
      return _listIndexForMessageId(key.value, entries);
    }
    if (key is ValueKey<String>) {
      final value = key.value;
      if (value.startsWith('day-')) {
        final label = value.substring(4);
        for (var i = 0; i < entries.length; i++) {
          if (entries[i].dividerLabel == label) {
            return _listFooterCount + (entries.length - 1 - i);
          }
        }
      }
    }
    return null;
  }

  void _scrollToListIndex(int listIndex, List<_ChatListEntry> entries) {
    if (!_scrollController.hasClients) return;
    final total = entries.length + _listFooterCount + _listHeaderCount;
    if (total <= 1 || listIndex < 0 || listIndex >= total) return;
    final max = _scrollController.position.maxScrollExtent;
    final ratio = listIndex / (total - 1);
    _scrollController.jumpTo((max * ratio).clamp(0.0, max));
  }

  /// reverse 列表下默认最新消息贴底，无需再滚到 maxScrollExtent。
  bool get _shouldAnchorMessagesAtTop => false;

  /// 当前应生效的定位消息；「回到最新」后抑制旧 focus。
  int get _effectiveFocusMessageId {
    if (_forceLatestMode) return 0;
    final focusId = widget.focusMessageId ?? 0;
    if (focusId > 0 && focusId == _suppressedFocusMessageId) return 0;
    return focusId;
  }

  bool get _shouldStickToLatestOnLoad {
    if (_locatedMode) return false;
    if (_effectiveFocusMessageId > 0) return false;
    // 用户已上滑看历史时，静默补拉不要强行贴底。
    if (_isBrowsingHistory) {
      return false;
    }
    return _enterStickBottomPending || _isNearBottom;
  }

  void _scrollToLatestOnEnter() {
    if (_locatedMode) return;
    if (_enterStickBottomPending) {
      _clearStableHistoryViewport();
    } else if (_historyViewportFrozen) {
      return;
    }
    setState(_clearPendingNewMessages);
    _ensureScrolledToBottom(attempt: 0);
  }

  /// reverse 列表进入时 scroll=0 即最新；仅图片/GIF 撑高后再补一次。
  void _ensureScrolledToBottom({required int attempt}) {
    if (!mounted || _locatedMode) return;
    if (_historyViewportFrozen && !_enterStickBottomPending) {
      _enterStickBottomPending = false;
      return;
    }
    if (_enterStickBottomPending && _historyViewportFrozen) {
      _clearStableHistoryViewport();
    }
    if (_userInteractedWithScroll && attempt > 0) {
      _enterStickBottomPending = false;
      return;
    }
    _scrollBottom(force: true, gentle: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _locatedMode) return;
      if (_userInteractedWithScroll && attempt > 0) {
        _enterStickBottomPending = false;
        return;
      }
      if (_isNearBottom || attempt >= 6) {
        _enterStickBottomPending = false;
        return;
      }
      final next = attempt + 1;
      final ms = next <= 2 ? 80 : 220;
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (!mounted || _locatedMode) return;
        _ensureScrolledToBottom(attempt: next);
      });
    });
  }

  void _scrollToPreferredAnchor({
    bool animated = false,
    bool force = false,
    bool gentle = false,
  }) {
    if (_shouldAnchorMessagesAtTop) {
      _scrollTop(animated: animated, force: force);
    } else {
      _scrollBottom(animated: animated, force: force, gentle: gentle);
    }
  }

  void _scrollTop({bool animated = false, bool force = false}) {
    if (_locatedMode && !force) return;
    final gen = ++_scrollBottomGen;

    void doScroll() {
      if (!mounted || gen != _scrollBottomGen) return;
      if (!_scrollController.hasClients) return;
      if (animated) {
        unawaited(
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        );
      } else {
        _scrollController.jumpTo(0);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());
  }

  bool _messagePeerRead(NativeChatMessage m) {
    if (m.peerRead) return true;
    if (_peerLastReadMessageId >= m.id) return true;
    return false;
  }

  Future<void> _refreshGroupReadMap(int conversationId) async {
    if (_isPrivate || conversationId <= 0) return;
    try {
      final rows = await _service.fetchGroupReadStatus(conversationId);
      if (!mounted) return;
      final next = <int, int>{};
      for (final row in rows) {
        final uid = (row['userId'] as num?)?.toInt() ?? 0;
        final lastRead =
            (row['lastReadMessageId'] as num?)?.toInt() ??
            (row['readMessageId'] as num?)?.toInt() ??
            (row['lastRead'] as num?)?.toInt() ??
            0;
        if (uid > 0 && uid != widget.session.userId && lastRead > 0) {
          next[uid] = lastRead;
        }
      }
      setState(() => _groupReadMap = next);
    } catch (_) {
      // Best effort only.
    }
  }

  List<Map<String, dynamic>> _groupReadPeers() {
    return _groupMembers
        .where((m) {
          final uid = (m['userId'] as num?)?.toInt() ?? 0;
          return uid > 0 && uid != widget.session.userId;
        })
        .toList(growable: false);
  }

  int _groupReadCountForMessage(int messageId) {
    if (messageId <= 0) return 0;
    var count = 0;
    for (final m in _groupReadPeers()) {
      final uid = (m['userId'] as num?)?.toInt() ?? 0;
      if ((_groupReadMap[uid] ?? 0) >= messageId) count += 1;
    }
    return count;
  }

  String? _groupReadLabelForMessage(
    NativeChatMessage message, {
    required bool mine,
  }) {
    if (_isPrivate || !mine || message.id <= 0) return null;
    final peers = _groupReadPeers();
    if (peers.isEmpty) return null;
    final count = _groupReadCountForMessage(message.id);
    if (count <= 0) return '未读';
    if (count >= peers.length) return '全部已读';
    return '$count人已读';
  }

  List<_ChatListEntry> _buildListEntries() {
    final lastId = _messages.isEmpty ? 0 : _messages.last.id;
    if (identical(_cachedListEntriesSource, _messages) &&
        _cachedListEntries != null &&
        _cachedListEntriesLen == _messages.length &&
        _cachedListEntriesLastId == lastId) {
      return _cachedListEntries!;
    }
    final entries = <_ChatListEntry>[];
    String? lastDivider;
    for (final m in _messages) {
      final label = InboxFormat.dayDividerLabel(m.createdAt);
      if (label != null && label != lastDivider) {
        entries.add(_ChatListEntry.divider(label));
        lastDivider = label;
      }
      entries.add(
        _ChatListEntry.message(m, showSenderMeta: !_isSystemKind(m.kind)),
      );
    }
    _cachedListEntries = entries;
    _cachedListEntriesSource = _messages;
    _cachedListEntriesLen = _messages.length;
    _cachedListEntriesLastId = lastId;
    return entries;
  }

  String _privateHeaderSubtitle(NativeConversation conv) {
    if (conv.isSelfMemo) return '';
    final parts = <String>[];
    final dept = conv.peerDepartment?.trim();
    final role = conv.peerRoleLabel?.trim();
    if (dept != null && dept.isNotEmpty) parts.add(dept);
    if (role != null && role.isNotEmpty) parts.add(role);
    parts.add(_peerOnline ? '在线' : '离线');
    return parts.join(' · ');
  }

  void _scheduleRealtimeRefresh() {
    if (!mounted ||
        _sending ||
        _uploading ||
        !_isNearBottom ||
        _loadingOlder ||
        _olderScrollRestorePending) {
      return;
    }
    _rtRefreshDebounce?.cancel();
    _rtRefreshDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || _sending || _uploading) return;
      _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    final gen = ++_loadGeneration;
    bool stale() => !mounted || gen != _loadGeneration;
    final focusId = _effectiveFocusMessageId;
    final locating = focusId > 0;
    final forceLatest = _forceLatestMode;
    if (!silent && !_bootstrapped) {
      setState(() {
        _loading = true;
        _locating = locating;
        _error = null;
      });
    } else if (locating) {
      setState(() => _locating = true);
    }
    try {
      final hintId = widget.conversationHint?.id ?? 0;
      final prefetchLatest = hintId > 0 && focusId <= 0;
      final convFuture = _resolveConversation();
      final pageFuture = prefetchLatest
          ? _service.fetchMessagePage(
              hintId,
              size: _scrollMetricsForScreen().initialPageSize,
            )
          : null;
      final conv = await convFuture;
      if (stale()) return;
      if (conv == null) {
        setState(() {
          _loading = false;
          _locating = false;
          _error = _isPrivate ? '未找到私聊会话' : '未找到群聊会话';
        });
        return;
      }
      // 本地占位私聊（尚未发过消息）：不拉历史、不订阅，展示空会话页。
      if (conv.id <= 0) {
        setState(() {
          _conversation = conv;
          _messages = const <NativeChatMessage>[];
          _hasMore = false;
          _hasNewer = false;
          _locatedMode = false;
          _loading = false;
          _locating = false;
          _bootstrapped = true;
          if (!silent) _error = null;
        });
        unawaited(_restoreComposeDraft(conversation: conv));
        if (_isPrivate) {
          final peerId = conv.peerUserId ?? widget.peerUserIdHint ?? 0;
          _realtime.setPresenceContext(conversationId: 0, peerUserId: peerId);
          final online =
              peerId > 0 && _realtime.currentOnlineUsers.contains(peerId);
          if (!stale() && _peerOnline != online) {
            setState(() => _peerOnline = online);
          }
        }
        _focusDesktopComposerIfActive();
        return;
      }
      final NativeMessagePage page;
      if (focusId > 0) {
        page = await _service.fetchMessagesAround(
          conv.id,
          focusId,
          hint: widget.focusMessageHint,
        );
      } else if (pageFuture != null && conv.id == hintId) {
        page = await pageFuture;
      } else {
        page = await _service.fetchMessagePage(
          conv.id,
          size: _scrollMetricsForScreen().initialPageSize,
        );
      }
      if (stale()) return;
      if (!_isPrivate) {
        unawaited(_refreshGroupReadMap(conv.id));
        unawaited(_hydrateGroupMembers(conv.id, gen));
      }
      unawaited(_loadReplySla(conv.id));
      unawaited(_realtime.ensureConversationSubscription(conv.id));
      if (_isPrivate) {
        _realtime.setPresenceContext(
          conversationId: conv.id,
          peerUserId: conv.peerUserId ?? 0,
        );
        final peerId = conv.peerUserId ?? 0;
        final online =
            peerId > 0 && _realtime.currentOnlineUsers.contains(peerId);
        if (!stale() && _peerOnline != online) {
          setState(() => _peerOnline = online);
        }
      }
      if (stale()) return;
      final msgs = _enrichMessages(page.items, conv)
        ..sort((a, b) => a.id.compareTo(b.id));
      final conversationChanged = _conversation?.id != conv.id;
      // 「回到最新」必须整页替换，不能与定位窗口合并，否则仍停在历史位置。
      final preservePaginatedHistory =
          silent &&
          _bootstrapped &&
          !conversationChanged &&
          focusId <= 0 &&
          !forceLatest &&
          (!_isNearBottom || _isBrowsingHistory);
      final nextMessages = preservePaginatedHistory
          ? (_enrichMessages(_mergeMessages(_messages, msgs), conv)
              ..sort((a, b) => a.id.compareTo(b.id)))
          : msgs;
      setState(() {
        if (conversationChanged) {
          _lastMarkedReadNewestId = 0;
          _userInteractedWithScroll = false;
          _enterStickBottomPending = true;
          _clearPendingNewMessages();
          _pinnedMessages = const <NativePinnedMessage>[];
          _pinnedExpanded = false;
        }
        _conversation = conv;
        _messages = nextMessages;
        if (!preservePaginatedHistory) {
          _hasMore = page.hasMore;
          _hasNewer = page.hasNewer;
        }
        _locatedMode = focusId > 0;
        _loading = false;
        _locating = false;
        _bootstrapped = true;
        _peerLastReadMessageId = math.max(
          _peerLastReadMessageId,
          page.peerLastReadMessageId ?? 0,
        );
        if (!silent) _error = null;
      });
      if (!preservePaginatedHistory || conversationChanged) {
        if (conv.id > 0) {
          ChatMessageCache.instance.put(conv.id, nextMessages);
        }
      }
      unawaited(_refreshPinnedMessages());
      unawaited(_refreshDownloadedFileFlags());
      unawaited(_restoreComposeDraft(conversation: conv));
      _focusDesktopComposerIfActive();
      // 有缓存的 silent 首进也要捕获；已捕获过则用 hint/会话未读数取大值补齐。
      final hintUnread = widget.conversationHint?.unreadCount ?? 0;
      final shouldCaptureUnread =
          !silent ||
          conversationChanged ||
          (_sessionUnreadCount <= 0 &&
              !_unreadJumpDismissed &&
              (conv.unreadCount > 0 || hintUnread > 0)) ||
          (_sessionUnreadCount > 0 && _firstUnreadMessageId <= 0);
      if (shouldCaptureUnread) {
        final unreadSource = hintUnread > conv.unreadCount
            ? ConversationInboxRealtime.copyConversation(
                conv,
                unreadCount: hintUnread,
              )
            : conv;
        _captureSessionUnread(unreadSource, nextMessages);
      }
      if (!locating) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _conversation?.id == conv.id) {
            unawaited(_replayLatestUnreadEgg(nextMessages, conv.id));
          }
        });
      }
      final stickLatest = focusId <= 0 && _shouldStickToLatestOnLoad;
      _forceLatestMode = false;
      if (focusId > 0) {
        _highlightAndScroll(focusId);
      } else if (stickLatest || forceLatest) {
        _scrollToLatestOnEnter();
      } else {
        _recountPendingNewMessages();
        if (_isBrowsingHistory) {
          _restoreHistoryViewportAfterForeground();
        }
      }
      // PC 宽屏短会话常未撑满视口，进会话后自动补历史，避免只能点「加载更早」。
      // 看历史/冻结恢复期间不要续拉，否则 reverse 列表会先贴底再被拽乱。
      if (focusId <= 0 && page.hasMore && !_isBrowsingHistory) {
        _scheduleAutoloadOlderToFill();
      }
      if (widget.autoMarkRead) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (stale()) return;
          unawaited(_markReadIfNeeded());
        });
      }
    } catch (e) {
      _forceLatestMode = false;
      if (stale()) return;
      final text = friendlyErrorText(e);
      // 静默刷新 / 已有消息时失败不冲掉当前会话，避免快速切会话后出现空白页。
      if (silent || (_bootstrapped && _messages.isNotEmpty)) {
        setState(() {
          _loading = false;
          _locating = false;
        });
        return;
      }
      setState(() {
        _error = text;
        _loading = false;
        _locating = false;
      });
    }
  }

  Future<void> _hydrateGroupMembers(int convId, int gen) async {
    List<Map<String, dynamic>> members = const <Map<String, dynamic>>[];
    try {
      members = await _service.fetchConversationMembers(convId);
    } catch (_) {
      if (!mounted || gen != _loadGeneration) return;
      try {
        final info = await _service.fetchGroupInfo(convId);
        members = info.members
            .map(
              (m) => <String, dynamic>{
                'userId': m.userId,
                'displayName': m.displayName,
                'name': m.displayName,
                'role': m.role,
                'roleLabel': m.roleLabel,
                'title': m.roleLabel,
                'avatarPreset': m.avatarPreset,
                'avatarObjectKey': m.avatarObjectKey,
              },
            )
            .toList(growable: false);
      } catch (_) {
        return;
      }
    }
    if (!mounted || gen != _loadGeneration) return;
    if ((_conversation?.id ?? 0) != convId) return;
    _groupMembers = members;
    if (_messages.isEmpty) return;
    setState(() {
      _messages = _enrichMessages(_messages);
    });
  }

  int? _topVisibleMessageId() {
    final entries = _buildListEntries();
    final total = entries.length + _listFooterCount + _listHeaderCount;
    if (total <= 0 || !_scrollController.hasClients) return null;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) {
      for (var i = entries.length - 1; i >= 0; i--) {
        final id = entries[i].message?.id;
        if (id != null && id > 0) return id;
      }
      return null;
    }
    // reverse 列表：scroll 越大，视口上沿越靠近更老的消息。
    final topRatio =
        ((pos.pixels + pos.viewportDimension * 0.1) / pos.maxScrollExtent)
            .clamp(0.0, 1.0);
    final listIndex = (topRatio * (total - 1)).round().clamp(0, total - 1);
    return _entryForListIndex(listIndex, entries)?.message?.id;
  }

  /// reverse 列表视口下沿附近的消息（更靠近更新端）。
  int? _bottomVisibleMessageId() {
    final entries = _buildListEntries();
    final total = entries.length + _listFooterCount + _listHeaderCount;
    if (total <= 0 || !_scrollController.hasClients) return null;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) {
      for (final e in entries) {
        final id = e.message?.id;
        if (id != null && id > 0) return id;
      }
      return null;
    }
    final bottomRatio =
        ((pos.pixels + pos.viewportDimension * 0.85) / pos.maxScrollExtent)
            .clamp(0.0, 1.0);
    final listIndex = (bottomRatio * (total - 1)).round().clamp(0, total - 1);
    return _entryForListIndex(listIndex, entries)?.message?.id;
  }

  Key _messageRowKey(int messageId) {
    // 滚动锚点 / 首条未读都需要 GlobalKey：前者供 ensureVisible，
    // 后者供「是否在视口内」判断（否则角标会一直误显）。
    if (_scrollRestoreAnchorId == messageId ||
        _firstUnreadMessageId == messageId ||
        (messageId > 0 && _replySlaJumpTargetId == messageId)) {
      return _scrollRestoreKeys.putIfAbsent(messageId, GlobalKey.new);
    }
    return ValueKey<int>(messageId);
  }

  void _finishOlderScrollRestore() {
    _olderScrollHold?.cancel();
    _olderScrollHold = null;
    _scrollRestoreAnchorId = null;
    _releaseOlderScrollRestoreGate();
    if (mounted) setState(() {});
    // 恢复锚点后再检查是否仍需补页（未撑满 / 仍贴历史顶）。
    _scheduleAutoloadOlderToFill();
  }

  void _ensureAnchorVisibleAfterOlderLoad(
    int anchorId, {
    int attempt = 0,
    double? fallbackPixels,
    double? fallbackOldMax,
    required int gen,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (gen != _messageScrollGen) {
        _olderScrollHold?.cancel();
        _olderScrollHold = null;
        _scrollRestoreAnchorId = null;
        _releaseOlderScrollRestoreGate();
        return;
      }
      if (!_scrollController.hasClients) {
        _finishOlderScrollRestore();
        return;
      }
      final ctx = _scrollRestoreKeys[anchorId]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.06, duration: Duration.zero);
        _finishOlderScrollRestore();
        return;
      }
      if (attempt < 18) {
        _ensureAnchorVisibleAfterOlderLoad(
          anchorId,
          attempt: attempt + 1,
          fallbackPixels: fallbackPixels,
          fallbackOldMax: fallbackOldMax,
          gen: gen,
        );
        return;
      }
      if (fallbackPixels != null && fallbackOldMax != null) {
        final pos = _scrollController.position;
        final delta = pos.maxScrollExtent - fallbackOldMax;
        if (delta > 0.5) {
          final wasAtHistoryTop =
              fallbackOldMax > 0 && fallbackPixels >= fallbackOldMax - 1.0;
          final target = wasAtHistoryTop
              ? fallbackPixels.clamp(0.0, pos.maxScrollExtent)
              : (fallbackPixels + delta).clamp(0.0, pos.maxScrollExtent);
          _scrollController.jumpTo(target);
        }
      }
      _finishOlderScrollRestore();
    });
  }

  Future<void> _loadOlder() async {
    final conv = _conversation;
    if (conv == null ||
        _loadingOlder ||
        _olderScrollRestorePending ||
        _messages.isEmpty ||
        !_hasMore) {
      return;
    }
    final oldestId = _messages.first.id;
    if (oldestId <= 0) return;
    final anchorMessageId = _topVisibleMessageId() ?? oldestId;
    final batchSize = _scrollController.hasClients
        ? _ChatScrollMetrics.fromListViewport(
            _scrollController.position.viewportDimension,
          ).batchPageSize
        : _scrollMetricsForScreen().batchPageSize;
    setState(() => _loadingOlder = true);
    try {
      final page = await _service.fetchMessagePage(
        conv.id,
        size: batchSize,
        before: oldestId,
      );
      if (!mounted) return;
      if (page.items.isEmpty) {
        _olderScrollHold?.cancel();
        _olderScrollHold = null;
        setState(() => _hasMore = false);
        return;
      }
      final merged = _enrichMessages(_mergeMessages(page.items, _messages));
      if (!mounted) return;
      // 网络请求期间允许用户继续滚动；响应回来后再以当前视口为锚点。
      // ScrollHold 只覆盖 prepend 与锚点恢复，避免整个请求期间吞掉滚轮输入。
      final restoreAnchorMessageId = _topVisibleMessageId() ?? anchorMessageId;
      final restoreOldPixels = _scrollController.hasClients
          ? _scrollController.position.pixels
          : 0.0;
      final restoreOldMax = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0.0;
      // 贴底看最新时补历史：只钉在最新端，不要 ensureVisible 把视口往上拽。
      // 用户已上滑看历史时，绝不能走贴底分支（否则 APP 上滑加载会被拽回最新）。
      final stickBottom =
          !_isBrowsingHistory &&
          !_isScrolledAwayFromLatest &&
          (_enterStickBottomPending || _isNearBottom);
      if (stickBottom) {
        _olderScrollHold?.cancel();
        _olderScrollHold = null;
        _scrollRestoreAnchorId = null;
        setState(() {
          _messages = merged;
          _hasMore = page.hasMore;
          _loadingOlder = false;
          _refreshFirstUnreadAfterHistory(merged);
        });
        unawaited(_refreshDownloadedFileFlags());
        _olderLoadCooldownUntilMs = DateTime.now().millisecondsSinceEpoch + 600;
        _releaseOlderScrollRestoreGate();
        _scrollBottom(force: true, gentle: false);
        _scheduleAutoloadOlderToFill();
        _scheduleUnreadVisibilityCheck();
        return;
      }
      _scrollRestoreAnchorId = restoreAnchorMessageId;
      _olderScrollHold?.cancel();
      _olderScrollHoldPixels = restoreOldPixels;
      _olderScrollHoldMax = restoreOldMax;
      if (_scrollController.hasClients) {
        _olderScrollHold = _scrollController.position.hold(() {});
      }
      _olderScrollRestorePending = true;
      setState(() {
        _messages = merged;
        _hasMore = page.hasMore;
        _loadingOlder = false;
        _refreshFirstUnreadAfterHistory(merged);
      });
      unawaited(_refreshDownloadedFileFlags());
      _olderLoadCooldownUntilMs = DateTime.now().millisecondsSinceEpoch + 600;
      _ensureAnchorVisibleAfterOlderLoad(
        restoreAnchorMessageId,
        fallbackPixels: _olderScrollHoldPixels,
        fallbackOldMax: _olderScrollHoldMax,
        gen: _messageScrollGen,
      );
      _scheduleUnreadVisibilityCheck();
    } catch (e) {
      _olderScrollHold?.cancel();
      _olderScrollHold = null;
      _scrollRestoreAnchorId = null;
      _olderScrollRestorePending = false;
      _showToast('加载历史失败：${friendlyErrorText(e)}');
    } finally {
      if (mounted && _loadingOlder) setState(() => _loadingOlder = false);
    }
  }

  void _releaseOlderScrollRestoreGate() {
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) _olderScrollRestorePending = false;
    });
  }

  Future<void> _loadNewer() async {
    final conv = _conversation;
    if (conv == null || _loadingNewer || _messages.isEmpty || !_hasNewer) {
      return;
    }
    final newestId = _messages.last.id;
    if (newestId <= 0) return;
    final batchSize = _scrollController.hasClients
        ? _ChatScrollMetrics.fromListViewport(
            _scrollController.position.viewportDimension,
          ).batchPageSize
        : _scrollMetricsForScreen().batchPageSize;
    // 锚定当前可见消息，避免 reverse 列表追加更新后视口被拽到最新。
    final anchorId = _bottomVisibleMessageId() ?? newestId;
    final oldPixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    setState(() => _loadingNewer = true);
    try {
      final page = await _service.fetchMessagePage(
        conv.id,
        size: batchSize,
        after: newestId,
      );
      if (!mounted) return;
      if (page.items.isEmpty) {
        setState(() => _hasNewer = false);
        return;
      }
      final merged = _enrichMessages(_mergeMessages(_messages, page.items));
      if (!mounted) return;
      // 兼容旧后端：未返回 hasNewer 时，本页满页则继续认为还有更新。
      final nextHasNewer = page.hasNewer || page.items.length >= batchSize;
      setState(() {
        _messages = merged;
        _hasNewer = nextHasNewer;
      });
      unawaited(_refreshDownloadedFileFlags());
      _newerLoadCooldownUntilMs = DateTime.now().millisecondsSinceEpoch + 600;
      if (_locatedMode) {
        // 定位浏览：只续一页，保持阅读位置，绝不连拉/贴底到全局最新。
        _restoreViewportAfterNewerLoad(
          anchorMessageId: anchorId,
          fallbackPixels: oldPixels,
        );
        return;
      }
      if (_isNearBottom) {
        setState(_clearPendingNewMessages);
        _scrollBottom(gentle: true, force: true);
      } else {
        _recountPendingNewMessages();
      }
    } catch (e) {
      _showToast('加载新消息失败：${friendlyErrorText(e)}');
    } finally {
      if (mounted) setState(() => _loadingNewer = false);
    }
  }

  /// reverse 列表追加更新消息后，尽量钉回加载前看到的那条，防止跳到最底部。
  void _restoreViewportAfterNewerLoad({
    required int anchorMessageId,
    required double fallbackPixels,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final entries = _buildListEntries();
      final listIndex = _listIndexForMessageId(anchorMessageId, entries);
      if (listIndex != null) {
        _scrollToListIndex(listIndex, entries);
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(fallbackPixels.clamp(0.0, max));
    });
  }

  List<NativeChatMessage> _mergeMessages(
    List<NativeChatMessage> a,
    List<NativeChatMessage> b,
  ) {
    final map = <int, NativeChatMessage>{};
    for (final m in [...a, ...b]) {
      if (m.id > 0) map[m.id] = m;
    }
    return map.values.toList()..sort((x, y) => x.id.compareTo(y.id));
  }

  Future<void> _jumpToLatest() async {
    final focusToSuppress = widget.focusMessageId ?? 0;
    _messageScrollGen++;
    _highlightTimer?.cancel();
    _olderScrollHold?.cancel();
    _olderScrollHold = null;
    _olderScrollRestorePending = false;
    _scrollRestoreAnchorId = null;
    setState(() {
      _locatedMode = false;
      _highlightMessageId = null;
      _hasNewer = false;
      _forceLatestMode = true;
      _suppressedFocusMessageId = focusToSuppress;
      _enterStickBottomPending = true;
      _userInteractedWithScroll = false;
      _awayFromLatest = false;
      _pendingNewMessageCount = 0;
    });
    _clearStableHistoryViewport();
    _lastUserScrollTowardLatestAt = DateTime.now();
    widget.onClearFocusMessage?.call();
    await _load(silent: _bootstrapped);
    if (!mounted) return;
    _scrollToLatestOnEnter();
  }

  void _preScrollTowardMessage(
    int messageId, {
    bool allowNearLatestShortcut = true,
  }) {
    if (!_scrollController.hasClients) return;
    final msgIndex = _messages.indexWhere((m) => m.id == messageId);
    if (msgIndex < 0) return;
    // 未读跳转时禁止「靠近最新就贴底」，否则永远停在最新消息。
    if (allowNearLatestShortcut && msgIndex >= _messages.length - 2) {
      _scrollBottom(force: true);
      return;
    }
    final entries = _buildListEntries();
    final listIndex = _listIndexForMessageId(messageId, entries);
    if (listIndex != null) {
      _scrollToListIndex(listIndex, entries);
    }
  }

  void _highlightAndScroll(int messageId) {
    final gen = ++_messageScrollGen;
    // 作废进会话时已经排队的贴底 jumpTo，避免 50/150/350ms 后再把定位拽回最新。
    _scrollBottomGen++;
    _messageLocateSettling = true;
    setState(() {
      // 让目标行使用 GlobalKey；粗定位把它构建出来后才能用
      // Scrollable.ensureVisible 按真实行高精确对准。
      _scrollRestoreAnchorId = messageId;
      _highlightMessageId = messageId;
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightMessageId = null);
    });
    unawaited(_ensureLocatedMessageVisible(messageId, gen: gen));
  }

  /// 历史定位滚动：最多一次动画对准，禁止未读跳转那套左右步进逼近。
  Future<void> _ensureLocatedMessageVisible(
    int messageId, {
    required int gen,
  }) async {
    try {
      for (var i = 0; i < 2; i++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || gen != _messageScrollGen) return;
      }
      var ctx = _scrollRestoreKeys[messageId]?.currentContext;
      if (ctx == null) {
        _preScrollTowardMessage(messageId, allowNearLatestShortcut: false);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || gen != _messageScrollGen) return;
        ctx = _scrollRestoreKeys[messageId]?.currentContext;
      }
      if (ctx == null) return;
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.28,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted || gen != _messageScrollGen) return;
      ctx = _scrollRestoreKeys[messageId]?.currentContext;
      if (ctx == null) return;
      if (_isMessageTouchedInViewport(messageId)) return;
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.28,
        duration: Duration.zero,
      );
    } finally {
      if (gen == _messageScrollGen) {
        _messageLocateSettling = false;
        _olderLoadCooldownUntilMs = DateTime.now().millisecondsSinceEpoch + 800;
        if (mounted && _scrollRestoreAnchorId == messageId) {
          setState(() => _scrollRestoreAnchorId = null);
        }
      }
    }
  }

  /// 定位落稳判断：任意重叠即可。未读角标那套 45% 高度会让长图永远「未可见」从而反复重试。
  bool _isMessageTouchedInViewport(int messageId) {
    if (messageId <= 0) return false;
    if (_scrollController.hasClients &&
        _scrollController.position.maxScrollExtent <= 1) {
      return _messages.any((m) => m.id == messageId);
    }
    final itemContext = _scrollRestoreKeys[messageId]?.currentContext;
    if (itemContext == null) return false;
    final itemRender = itemContext.findRenderObject();
    if (itemRender is! RenderBox || !itemRender.hasSize) return false;
    final scrollable = Scrollable.maybeOf(itemContext);
    final viewportRender = scrollable?.context.findRenderObject();
    if (viewportRender is! RenderBox || !viewportRender.hasSize) return false;
    final itemRect = itemRender.localToGlobal(Offset.zero) & itemRender.size;
    final viewportRect =
        viewportRender.localToGlobal(Offset.zero) & viewportRender.size;
    return itemRect.overlaps(viewportRect);
  }

  void _captureSessionUnread(
    NativeConversation conv,
    List<NativeChatMessage> messages,
  ) {
    if (_unreadJumpDismissed && _conversation?.id == conv.id) return;
    final hintUnread = widget.conversationHint?.id == conv.id
        ? (widget.conversationHint?.unreadCount ?? 0)
        : 0;
    final unread = math.max(conv.unreadCount, hintUnread);
    if (unread <= 0 || messages.isEmpty) {
      // 勿把已展示的会话内未读角标清掉（进会话后服务端/列表可能已把 unreadCount 置 0）。
      if (_sessionUnreadCount > 0 && _firstUnreadMessageId > 0) return;
      if (mounted) {
        setState(() {
          _sessionUnreadCount = 0;
          _firstUnreadMessageId = 0;
          _unreadMessageVisible = false;
          _firstUnreadTruncated = false;
        });
      } else {
        _sessionUnreadCount = 0;
        _firstUnreadMessageId = 0;
        _unreadMessageVisible = false;
        _firstUnreadTruncated = false;
      }
      return;
    }
    // 未读窗口可能超出当前页：先落到当前页估算位置，点击时再向上补拉。
    final target = _resolveFirstUnreadTarget(messages, unread);
    if (target.id <= 0) return;
    if (!mounted) {
      _sessionUnreadCount = unread;
      _firstUnreadMessageId = target.id;
      _firstUnreadTruncated = target.truncated;
      return;
    }
    setState(() {
      _sessionUnreadCount = unread;
      _firstUnreadMessageId = target.id;
      _firstUnreadTruncated = target.truncated;
      _unreadJumpDismissed = false;
      _unreadMessageVisible = false;
    });
    _scheduleUnreadVisibilityCheck();
  }

  bool get _showUnreadJumpBadge {
    // 临时屏蔽会话页右上角「N 条未读」浮动入口。
    return false;
  }

  /// 只在首条未读确实离开消息列表视口时显示跳转提示。
  ///
  /// 不能仅用 scroll offset 推算：消息高度、日期分隔线、图片加载都会改变
  /// 实际位置。使用消息行和 ListView 视口的 global rect 求交集，分页补历史也
  /// 不会改变这个判断。
  bool _isMessageVisibleInViewport(int messageId) {
    if (messageId <= 0) return false;
    // 内容未撑满一屏：所有已加载消息都在视口内。
    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      if (pos.maxScrollExtent <= 1) {
        return _messages.any((m) => m.id == messageId);
      }
    }
    final itemContext = _scrollRestoreKeys[messageId]?.currentContext;
    if (itemContext == null) return false;
    final itemRender = itemContext.findRenderObject();
    if (itemRender is! RenderBox || !itemRender.hasSize) return false;
    final scrollable = Scrollable.maybeOf(itemContext);
    final viewportRender = scrollable?.context.findRenderObject();
    if (viewportRender is! RenderBox || !viewportRender.hasSize) return false;
    final itemRect = itemRender.localToGlobal(Offset.zero) & itemRender.size;
    final viewportRect =
        viewportRender.localToGlobal(Offset.zero) & viewportRender.size;
    if (!itemRect.overlaps(viewportRect)) return false;
    final top = math.max(itemRect.top, viewportRect.top);
    final bottom = math.min(itemRect.bottom, viewportRect.bottom);
    final visibleHeight = bottom - top;
    final requiredHeight = math.min(40.0, itemRect.height * 0.45);
    return visibleHeight >= requiredHeight;
  }

  void _scheduleUnreadVisibilityCheck() {
    if (_unreadVisibilityCheckPending || _firstUnreadMessageId <= 0) return;
    _unreadVisibilityCheckPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unreadVisibilityCheckPending = false;
      if (!mounted || _firstUnreadMessageId <= 0) return;
      final targetId = _firstUnreadMessageId;
      final shortList =
          _scrollController.hasClients &&
          _scrollController.position.maxScrollExtent <= 1;
      final keyReady = _scrollRestoreKeys[targetId]?.currentContext != null;
      // setState 刚写入 firstUnread 时，GlobalKey 可能要等本帧重建后才挂上。
      if (!keyReady &&
          !shortList &&
          !_unreadVisibilityKeyRetryUsed &&
          !_isScrolledAwayFromLatest &&
          _messages.any((m) => m.id == targetId)) {
        _unreadVisibilityKeyRetryUsed = true;
        _scheduleUnreadVisibilityCheck();
        return;
      }
      _unreadVisibilityKeyRetryUsed = false;
      final visible = _isMessageVisibleInViewport(targetId);
      if (visible == _unreadMessageVisible) return;
      setState(() => _unreadMessageVisible = visible);
    });
  }

  /// 按未读数从「他人消息」池里取首条未读。
  ///
  /// 当已加载的他人消息不足 [unread] 时，返回当前池最旧一条（仅作继续补拉的锚点，
  /// 此时 [truncated] 为 true，调用方必须继续分页，不能直接拿去定位）。
  ({int id, bool truncated}) _resolveFirstUnreadTarget(
    List<NativeChatMessage> messages,
    int unread,
  ) {
    if (unread <= 0 || messages.isEmpty) {
      return (id: 0, truncated: false);
    }
    final sorted = List<NativeChatMessage>.from(messages)
      ..sort((a, b) => a.id.compareTo(b.id));
    final others = sorted
        .where(
          (m) =>
              m.id > 0 &&
              m.senderUserId != widget.session.userId &&
              !_isSystemKind(m.kind),
        )
        .toList(growable: false);
    final pool = others.isNotEmpty
        ? others
        : sorted.where((m) => m.id > 0).toList(growable: false);
    if (pool.isEmpty) return (id: 0, truncated: false);
    if (pool.length < unread) {
      return (id: pool.first.id, truncated: true);
    }
    return (id: pool[pool.length - unread].id, truncated: false);
  }

  int _resolveFirstUnreadMessageId(
    List<NativeChatMessage> messages,
    int unread,
  ) {
    return _resolveFirstUnreadTarget(messages, unread).id;
  }

  /// 自动补历史后，若已能完整覆盖未读窗口，刷新首条未读 id（供角标可见性判断）。
  void _refreshFirstUnreadAfterHistory(List<NativeChatMessage> messages) {
    if (_unreadJumpDismissed || _sessionUnreadCount <= 0) return;
    final target = _resolveFirstUnreadTarget(messages, _sessionUnreadCount);
    if (target.id <= 0) return;
    _firstUnreadTruncated = target.truncated;
    if (target.id != _firstUnreadMessageId) {
      _firstUnreadMessageId = target.id;
    }
  }

  Future<void> _jumpToFirstUnread() async {
    if (_firstUnreadMessageId <= 0 || _sessionUnreadCount <= 0) return;
    final conv = _conversation;
    if (conv == null || conv.id <= 0) return;
    if (_locating) return;

    _userInteractedWithScroll = true;
    _enterStickBottomPending = false;
    setState(() => _locating = true);

    try {
      // 1) 只在内存里补历史，算出真正的首条未读 id。
      //    不要把整段分页历史直接塞进列表——消息高度不一，比例滚动会严重偏移。
      var working = List<NativeChatMessage>.from(_messages)
        ..sort((a, b) => a.id.compareTo(b.id));
      var hasMore = _hasMore;
      var target = _resolveFirstUnreadTarget(working, _sessionUnreadCount);

      for (var i = 0; i < 256 && mounted && hasMore && target.truncated; i++) {
        final oldestId = working.isEmpty ? 0 : working.first.id;
        if (oldestId <= 0) break;
        final page = await _service.fetchMessagePage(
          conv.id,
          size: 40,
          before: oldestId,
        );
        if (!mounted) return;
        if (page.items.isEmpty) {
          hasMore = false;
          break;
        }
        working = _enrichMessages(_mergeMessages(page.items, working))
          ..sort((a, b) => a.id.compareTo(b.id));
        hasMore = page.hasMore;
        target = _resolveFirstUnreadTarget(working, _sessionUnreadCount);
      }

      final targetId = target.id;
      if (!mounted || targetId <= 0) {
        if (mounted) setState(() => _locating = false);
        return;
      }

      // 2) 用 around 拉「目标附近」窗口，和引用跳转同一套定位路径。
      final page = await _service.fetchMessagesAround(conv.id, targetId);
      if (!mounted) return;
      var msgs = _enrichMessages(page.items, conv)
        ..sort((a, b) => a.id.compareTo(b.id));
      if (!msgs.any((m) => m.id == targetId)) {
        // around 未命中时，退回已补全的 working 窗口，至少保证目标在列表里。
        msgs = working;
      }
      if (!msgs.any((m) => m.id == targetId)) {
        setState(() => _locating = false);
        _showToast('找不到未读消息');
        return;
      }

      final gen = ++_messageScrollGen;
      setState(() {
        _messages = msgs;
        _hasMore = page.hasMore;
        _hasNewer = page.hasNewer || msgs.any((m) => m.id > targetId);
        // 进入定位模式：底部出现「回到最新消息」，避免停在历史窗口出不去。
        _locatedMode = true;
        _locating = false;
        _firstUnreadMessageId = targetId;
        _firstUnreadTruncated = false;
        _unreadJumpDismissed = true;
        _unreadMessageVisible = false;
        _awayFromLatest = true;
        _scrollRestoreAnchorId = targetId;
        _highlightMessageId = targetId;
        if (page.peerLastReadMessageId != null) {
          _peerLastReadMessageId = page.peerLastReadMessageId!;
        }
      });
      ChatMessageCache.instance.put(conv.id, msgs);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _highlightMessageId = null);
      });
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted || gen != _messageScrollGen) return;
      await _ensureUnreadMessageVisible(targetId, gen: gen);
    } catch (e) {
      if (!mounted) return;
      setState(() => _locating = false);
      _showToast('定位未读失败：${friendlyErrorText(e)}');
    }
  }

  Future<void> _ensureUnreadMessageVisible(
    int messageId, {
    required int gen,
    int attempt = 0,
  }) async {
    if (!mounted || gen != _messageScrollGen) return;
    // 粗定位：比例估算 + 按视口步进逼近，让目标行进入构建范围。
    if (attempt == 0 || attempt == 3 || attempt == 7 || attempt == 12) {
      _preScrollTowardMessage(messageId, allowNearLatestShortcut: false);
      await Future<void>.delayed(const Duration(milliseconds: 32));
      if (!mounted || gen != _messageScrollGen) return;
    } else if (attempt == 5 || attempt == 9 || attempt == 15 || attempt == 20) {
      // 无其它 GlobalKey 可参照时，在历史/最新两个方向交替步进逼近。
      final towardHistory = attempt == 5 || attempt == 15;
      _nudgeScrollTowardUnreadTarget(towardHistory: towardHistory);
      await Future<void>.delayed(const Duration(milliseconds: 32));
      if (!mounted || gen != _messageScrollGen) return;
    }
    final ctx = _scrollRestoreKeys[messageId]?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        // 首条未读靠近视口上方，贴近微信「以下为未读」阅读位置。
        alignment: 0.12,
        duration: attempt == 0
            ? const Duration(milliseconds: 420)
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      if (!mounted || gen != _messageScrollGen) return;
      // 再确认一次：图片/气泡二次布局后可能仍偏一点。
      if (!_isMessageVisibleInViewport(messageId) && attempt < 22) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await _ensureUnreadMessageVisible(
          messageId,
          gen: gen,
          attempt: attempt + 1,
        );
        return;
      }
      if (mounted && _scrollRestoreAnchorId == messageId) {
        setState(() => _scrollRestoreAnchorId = null);
      }
      return;
    }
    if (attempt < 28) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await _ensureUnreadMessageVisible(
        messageId,
        gen: gen,
        attempt: attempt + 1,
      );
      return;
    }
    if (mounted && _scrollRestoreAnchorId == messageId) {
      setState(() => _scrollRestoreAnchorId = null);
    }
  }

  /// 目标行尚未构建时，按视口高度向历史或最新方向步进，逼它进入构建范围。
  void _nudgeScrollTowardUnreadTarget({required bool towardHistory}) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    final step = (pos.viewportDimension * 0.85).clamp(120.0, 560.0);
    final next = towardHistory ? pos.pixels + step : pos.pixels - step;
    pos.jumpTo(next.clamp(0.0, pos.maxScrollExtent));
  }

  void _ensureMessageVisible(
    int messageId, {
    int attempt = 0,
    required int gen,
    Duration duration = const Duration(milliseconds: 280),
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _messageScrollGen) return;
      if (attempt == 0) {
        _preScrollTowardMessage(messageId, allowNearLatestShortcut: false);
      }
      final entries = _buildListEntries();
      final listIndex = _listIndexForMessageId(messageId, entries);
      if (listIndex != null && _scrollController.hasClients) {
        final total = entries.length + _listFooterCount + _listHeaderCount;
        if (total > 1) {
          final max = _scrollController.position.maxScrollExtent;
          final ratio = listIndex / (total - 1);
          final target = (max * ratio).clamp(0.0, max);
          if ((_scrollController.position.pixels - target).abs() > 8) {
            _scrollController.animateTo(
              target,
              duration: duration,
              curve: Curves.easeOutCubic,
            );
          }
        }
        return;
      }
      if (attempt < 8) {
        _ensureMessageVisible(
          messageId,
          attempt: attempt + 1,
          gen: gen,
          duration: duration,
        );
        return;
      }
      if (_messages.any((m) => m.id == messageId)) {
        _scrollBottom(force: true);
      }
    });
  }

  Future<NativeConversation?> _resolveConversation() async {
    NativeConversation? conv;
    final hasHint =
        widget.conversationHint != null && widget.conversationHint!.id > 0;
    if (hasHint) {
      conv = widget.conversationHint;
    } else if (_isPrivate) {
      final peerId = widget.peerUserIdHint ?? 0;
      if (peerId > 0) {
        // 只查找已有会话；没有消息活动的空私聊不当作有效会话。
        final convId = await _service.findPrivateConversationForPeer(peerId);
        if (convId != null && convId > 0) {
          conv = await _service.fetchConversation(convId);
        } else {
          // 本地占位：首次发消息再建服务端会话，避免对方提前看到空会话。
          conv = NativeConversation(
            id: 0,
            kind: 'PRIVATE',
            title: '私聊',
            unreadCount: 0,
            preview: '',
            updatedAt: null,
            peerUserId: peerId,
          );
        }
      }
    }
    if (conv == null) {
      final all = await _service.fetchConversations();
      for (final c in all) {
        if (_isPrivate && c.isPrivate) {
          if (!c.hasInboxActivity) continue;
          conv = c;
          break;
        }
        if (!_isPrivate &&
            (c.kind == 'GROUP' ||
                c.kind == 'WORKGROUP' ||
                c.kind == 'WORKGROUP_APPROVAL')) {
          conv = c;
          break;
        }
      }
    }
    if (conv == null) return null;
    var resolved = conv;
    if (resolved.id > 0) {
      try {
        final fresh = await _service.fetchConversation(resolved.id);
        if (fresh != null) resolved = fresh;
      } catch (_) {
        // 列表 hint 可用时，刷新会话详情失败不阻断进会话（频繁切会话时很常见）。
        if (!hasHint || widget.conversationHint!.id != resolved.id) rethrow;
      }
    }
    if (_isPrivate) {
      try {
        return await _enrichPrivateConversation(resolved);
      } catch (_) {
        return resolved;
      }
    }
    return resolved;
  }

  /// 首次发消息时再创建服务端私聊；已有 id 则直接返回。
  Future<NativeConversation?> _ensureConversationReadyForSend() async {
    final current = _conversation;
    if (current != null && current.id > 0) return current;
    if (!_isPrivate) return current;
    if (current?.dissolved == true) return null;
    final peerId = current?.peerUserId ?? widget.peerUserIdHint ?? 0;
    if (peerId <= 0 || peerId == widget.session.userId) {
      throw Exception('无法创建私聊：对方无效');
    }
    final convId = await _service.ensurePrivateConversationForPeer(peerId);
    if (convId == null || convId <= 0) {
      throw Exception('创建私聊失败');
    }
    ChatComposeDraftStore.instance.migratePeerToConversation(peerId, convId);
    var fresh = await _service.fetchConversation(convId);
    fresh ??= NativeConversation(
      id: convId,
      kind: 'PRIVATE',
      title: current?.title ?? '私聊',
      unreadCount: 0,
      preview: current?.preview ?? '',
      updatedAt: DateTime.now(),
      peerUserId: peerId,
      peerDisplayName: current?.peerDisplayName,
      peerEnabled: current?.peerEnabled ?? true,
      peerDepartment: current?.peerDepartment,
      peerRoleLabel: current?.peerRoleLabel,
      peerAvatarPreset: current?.peerAvatarPreset,
      peerAvatarObjectKey: current?.peerAvatarObjectKey,
      peerAvatarUrl: current?.peerAvatarUrl,
      peerImStatus: current?.peerImStatus ?? '',
      peerImStatusText: current?.peerImStatusText ?? '',
      peerImStatusIcon: current?.peerImStatusIcon ?? '',
      peerImStatusColor: current?.peerImStatusColor ?? '',
    );
    final enriched = await _enrichPrivateConversation(fresh);
    if (!mounted) return enriched;
    setState(() {
      _conversation = enriched;
      _composeDraftKey = _draftKeyFor(conversation: enriched);
    });
    unawaited(_realtime.ensureConversationSubscription(enriched.id));
    _realtime.setPresenceContext(
      conversationId: enriched.id,
      peerUserId: enriched.peerUserId ?? peerId,
    );
    return enriched;
  }

  Future<NativeConversation> _enrichPrivateConversation(
    NativeConversation conv,
  ) async {
    var peerId = conv.peerUserId ?? widget.peerUserIdHint ?? 0;
    if (peerId <= 0 || peerId == widget.session.userId) {
      peerId = widget.peerUserIdHint ?? 0;
    }
    if (peerId <= 0 || peerId == widget.session.userId) return conv;
    final needsContact =
        conv.peerUserId == null ||
        conv.peerUserId == widget.session.userId ||
        (conv.peerDisplayName ?? '').trim().isEmpty ||
        conv.displayTitle == widget.session.displayName;
    final needsAvatar =
        (conv.peerAvatarPreset ?? '').trim().isEmpty &&
        (conv.peerAvatarObjectKey ?? '').trim().isEmpty;
    if (!needsContact && !needsAvatar) return conv;
    final contact = await ContactService(
      session: widget.session,
    ).fetchContact(peerId);
    if (contact == null) return conv;
    return NativeConversation(
      id: conv.id,
      kind: conv.kind,
      title: contact.displayName.isNotEmpty ? contact.displayName : conv.title,
      unreadCount: conv.unreadCount,
      preview: conv.preview,
      updatedAt: conv.updatedAt,
      peerUserId: peerId,
      peerDisplayName: contact.displayName,
      peerEnabled: contact.enabled,
      memberCount: conv.memberCount,
      muted: conv.muted,
      pinned: conv.pinned,
      businessType: conv.businessType,
      peerDepartment: (contact.department ?? '').trim().isNotEmpty
          ? contact.department
          : conv.peerDepartment,
      peerRoleLabel: (contact.title ?? '').trim().isNotEmpty
          ? contact.title
          : conv.peerRoleLabel,
      peerAvatarPreset: contact.avatarPreset ?? conv.peerAvatarPreset,
      peerAvatarObjectKey: contact.avatarObjectKey ?? conv.peerAvatarObjectKey,
      dissolved: conv.dissolved,
      replySla: conv.replySla,
      membershipStatus: conv.membershipStatus,
      assistantGenerating: conv.assistantGenerating,
      assistantGeneratingStatus: conv.assistantGeneratingStatus,
      hasUnreadMention: conv.hasUnreadMention,
      hasUnreadAtAll: conv.hasUnreadAtAll,
      markedUnread: conv.markedUnread,
      peerImStatus: conv.peerImStatus,
      peerImStatusText: conv.peerImStatusText,
      peerImStatusIcon: conv.peerImStatusIcon,
      peerImStatusColor: conv.peerImStatusColor,
    );
  }

  void _onInputFocusChanged() {
    if (!_inputFocusNode.hasFocus) return;
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
    }
    // PC 窗口恢复时输入框会被程序自动 requestFocus。此时如果用户正在看
    // 历史 / 历史定位结果，不能把“恢复输入焦点”当成用户点击输入框并强制滚到最新。
    if (_isBrowsingHistory || _locatedMode) return;
    unawaited(_scrollToLatestForInput());
  }

  Future<void> _scrollToLatestForInput({bool userInitiated = false}) async {
    if ((_isBrowsingHistory || _locatedMode) && !userInitiated) return;
    if (_locatedMode && userInitiated) {
      await _jumpToLatest();
      return;
    }
    if (_shouldAnchorMessagesAtTop) return;
    setState(_clearPendingNewMessages);
    _wasNearBottom = true;
    void snap({bool animated = false}) {
      if (!mounted) return;
      _clearStableHistoryViewport();
      _scrollBottom(force: true, animated: animated, gentle: true);
    }

    snap(animated: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => snap());
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (mounted && _inputFocusNode.hasFocus) snap();
    });
  }

  void _scrollToLatestAfterKeyboard() {
    // TextField.onTap 才是用户明确点击输入框；允许其主动回到最新。
    unawaited(_scrollToLatestForInput(userInitiated: true));
  }

  bool _tryApplySentTextMessage(
    NativeChatMessage? sent, {
    required int conversationId,
    required bool locating,
  }) {
    if (locating) return false;
    if (sent == null || sent.id <= 0) return false;
    if ((_conversation?.id ?? 0) != conversationId) return false;
    final enriched = _enrichMessages([sent]);
    final msg = enriched.isEmpty ? sent : enriched.first;
    setState(() {
      _messages = _mergeMessages(_messages, [msg]);
    });
    _rememberCachedMessages();
    return true;
  }

  Future<void> _send() async {
    final effectOverlay = _supportsMobileEggs
        ? Overlay.maybeOf(context, rootOverlay: true)
        : null;
    if (_desktopComposerAttachments.isNotEmpty) {
      await _sendDesktopStagedBundle();
      return;
    }
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending || _conversation?.dissolved == true) return;
    final mentionIds = _parseMentionUserIds(text);
    final payload = <String, dynamic>{};
    if (mentionIds.isNotEmpty) {
      payload['mentionUserIds'] = mentionIds;
    }
    final quote = _quoteDraft;
    if (quote != null && !quote.isEmpty) {
      payload['quote'] = quote.toPayloadMap();
    }
    final payloadOrNull = payload.isEmpty ? null : payload;
    setState(() => _sending = true);
    // 键盘「发送」会先 unfocus；连发场景下立刻抢回焦点，避免先折叠再展开。
    // 用户点消息区空白后 _composerKeepFocus 会被清掉，后续不再抢回。
    _composerKeepFocus = !isWideChatLayout(context);
    _requestComposerFocusIfKept();
    try {
      var conv = _conversation;
      if (conv == null || conv.id <= 0) {
        final ready = await _ensureConversationReadyForSend();
        if (ready == null || ready.id <= 0) {
          throw Exception('会话未就绪');
        }
        conv = ready;
        // 首次建会话的 await 后补一次焦点，防止键盘被系统收起。
        _requestComposerFocusIfKept();
      }
      final locating = _locatedMode || (_effectiveFocusMessageId > 0);
      final sent = await _service.sendText(
        conv.id,
        text,
        payload: payloadOrNull,
      );
      _inputController.clear();
      _clearComposeDraft();
      setState(() {
        _emojiOpen = false;
        _locatedMode = false;
        _quoteDraft = null;
      });
      if (!_tryApplySentTextMessage(
        sent,
        conversationId: conv.id,
        locating: locating,
      )) {
        await _load(silent: true);
      }
      if (_supportsMobileEggs) await _ensureEggSettings();
      final sentEffect = _supportsMobileEggs ? matchImEggEffect(text) : null;
      final activeConversationId = conv.id;
      if (sentEffect != null &&
          ImEggSettings.instance.senderEnabled &&
          _canPlayChatEffect &&
          effectOverlay?.mounted == true &&
          ImEggPlaybackStore.allowEffect(
            userId: widget.session.userId,
            conversationId: activeConversationId,
            maxPer10Minutes: ImEggSettings.instance.maxPer10Minutes,
          )) {
        showImEggEffectOnOverlay(
          effectOverlay!,
          sentEffect,
          seed: sent?.id ?? 0,
        );
      }
      if (mounted) {
        setState(_clearPendingNewMessages);
        _scrollToPreferredAnchor(force: true);
        _requestComposerFocusIfKept();
      }
    } catch (e) {
      _showToast('发送失败：${friendlyErrorText(e)}');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        if (_composerKeepFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _requestComposerFocusIfKept();
          });
        }
      }
    }
  }

  Future<void> _sendDesktopStagedBundle() async {
    if (_sending || _conversation?.dissolved == true) return;
    final text = _inputController.text.trim();
    if (text.isEmpty && _desktopComposerAttachments.isEmpty) return;

    final mentionIds = _parseMentionUserIds(text);
    final payload = <String, dynamic>{};
    if (mentionIds.isNotEmpty) payload['mentionUserIds'] = mentionIds;
    final quote = _quoteDraft;
    if (quote != null && !quote.isEmpty) {
      payload['quote'] = quote.toPayloadMap();
    }
    final cancel = ChatUploadCancelToken();
    setState(() {
      _sending = true;
      _desktopAttachmentNotice = null;
      _desktopAttachmentFailed = false;
    });
    try {
      await _guardSend(
        () async {
          final conversationId = _requireReadyConversationId();
          // 文本先发，保证所有端都能以既有 TEXT/IMAGE/FILE 消息展示本次内容。
          if (text.isNotEmpty) {
            await _service.sendText(
              conversationId,
              text,
              payload: payload.isEmpty ? null : payload,
            );
            if (mounted) {
              setState(() {
                _inputController.clear();
                _clearComposeDraft();
                _quoteDraft = null;
                _emojiOpen = false;
              });
            }
          }

          var completed = 0;
          while (_desktopComposerAttachments.isNotEmpty) {
            cancel.throwIfCancelled();
            final attachment = _desktopComposerAttachments.first;
            completed++;
            final total = completed + _desktopComposerAttachments.length - 1;
            _beginUpload(
              attachment.isImage
                  ? '上传图片 ($completed/$total)'
                  : '上传文件 ($completed/$total)',
              previewBytes: attachment.isImage ? attachment.bytes : null,
              kind: attachment.isImage ? 'IMAGE' : 'FILE',
              fileName: attachment.fileName,
            );
            if (attachment.isImage) {
              await _service.sendImage(
                conversationId: conversationId,
                bytes: attachment.bytes,
                fileName: attachment.fileName,
                mimeType: attachment.mimeType,
                sourceLabel: attachment.sourceLabel,
                preparePreview: () => _prepareChatImagePreview(
                  attachment.bytes,
                  attachment.fileName,
                ),
                onProgress: (p) => _setUploadProgress(p),
                cancelToken: cancel,
              );
            } else {
              await _service.sendFile(
                conversationId: conversationId,
                bytes: attachment.uploadSource == null
                    ? attachment.bytes
                    : null,
                source: attachment.uploadSource,
                fileName: attachment.fileName,
                mimeType: attachment.mimeType,
                onProgress: _setUploadProgress,
                cancelToken: cancel,
              );
            }
            if (!mounted) return;
            setState(() => _desktopComposerAttachments.removeAt(0));
          }
        },
        cancelToken: cancel,
        desktopAttachmentFeedback: true,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _stageDesktopAttachment({
    required Uint8List bytes,
    ChatFileUploadSource? uploadSource,
    required String fileName,
    required String mimeType,
    required bool isImage,
    required String sourceLabel,
  }) {
    if (!isDesktopCommOnly) return;
    if (_desktopComposerAttachments.length >= _maxDesktopComposerAttachments) {
      _showToast('一次最多添加 $_maxDesktopComposerAttachments 个附件');
      return;
    }
    setState(() {
      _desktopComposerAttachments.add(
        