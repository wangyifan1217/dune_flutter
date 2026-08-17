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
import '../conversation/inbox_format.dart';
import '../desktop/windows_desktop_tray.dart';
import '../drive/chat_save_to_drive.dart';
import '../kb/kb_chat_share.dart';
import '../kb/kb_document_coordinator.dart';
import '../kb/native_kb_service.dart';
import '../meeting/meeting_minutes_chat_share.dart';
import '../meeting/native_meeting_detail_page.dart';
import '../robots/robot_markdown.dart';
import '../shell/dunes_toast.dart';
import '../weekly_summary/native_weekly_summary_page.dart';
import '../weekly_summary/weekly_summary_card.dart';
import '../weekly_summary/weekly_summary_models.dart';
import '../xflow/approval_chat_share.dart';
import '../xflow/approval_picker_sheet.dart';
import '../xflow/xflow_detail_logic.dart';
import 'chat_emoji_gif_panel.dart';
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
import 'chat_pdf_preview.dart';
import 'chat_media_widgets.dart';
import 'chat_desktop_file_drag_stub.dart'
    if (dart.library.io) 'chat_desktop_file_drag.dart';
import 'chat_quote.dart';
import 'chat_video_utils.dart';
import 'chat_video_widgets.dart';
import 'chat_voice_player.dart';
import 'voice_asr_store.dart';
import 'chat_compose_draft_store.dart';
import 'voice_recording_overlay.dart';
import 'voice_transcript_panel.dart';
import 'chat_widgets.dart';
import 'desktop_screenshot.dart';
import 'file_download.dart' as file_dl;
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
    required this.fileName,
    required this.mimeType,
    required this.isImage,
    required this.sourceLabel,
  });

  final Uint8List bytes;
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
  double _uploadProgress = 0;
  bool _recording = false;

  /// 当前正在下载的附件 cacheKey；非空时仅该文件气泡转圈。
  String? _downloadingFileKey;
  double _downloadProgress = 0;

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
  bool _pendingStickBottomAfterForeground = false;
  bool _foregroundSyncRunning = false;
  DateTime? _lastForegroundSyncAt;
  double _olderScrollHoldMax = 0;
  bool _loadingNewer = false;
  bool _locatedMode = false;
  bool _forceLatestMode = false;

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
  bool _userInteractedWithScroll = false;
  bool _userScrollActive = false;

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
    _service = ConversationService(session: widget.session);
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
    _load(silent: _bootstrapped);
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
      _inputFocusNode.requestFocus();
    });
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
        _uploadLabel = '上传文件';
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
      });
      if (hasCache && hintUnread > 0 && cached != null) {
        _captureSessionUnread(widget.conversationHint!, cached);
      }
      unawaited(_restoreComposeDraft(conversation: widget.conversationHint));
      unawaited(_load(silent: hasCache));
      _focusDesktopComposerIfActive();
      return;
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
    final inset = View.of(context).viewInsets.bottom;
    final keyboardOpening =
        _inputFocusNode.hasFocus && inset > _lastKeyboardInset + 1;
    _lastKeyboardInset = inset;
    if (keyboardOpening && !_shouldAnchorMessagesAtTop) {
      _scrollBottom(force: true, gentle: true);
    } else if (_emojiOpen && !_shouldAnchorMessagesAtTop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _emojiOpen) {
          _scrollBottom(force: true, animated: true, gentle: false);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncLatestOnForeground());
    }
  }

  void _onChatForegroundResumed() {
    unawaited(_syncLatestOnForeground());
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
    // 优先用像素位置判断是否在看历史（覆盖滚轮未置交互标志的情况）。
    final browsingHistory =
        _isScrolledAwayFromLatest ||
        (_userInteractedWithScroll &&
            (!_scrollController.hasClients ||
                _scrollController.position.pixels > 72));
    final nearBottom =
        _scrollController.hasClients && _scrollController.position.pixels <= 72;
    final shouldStick =
        !browsingHistory && (_pendingStickBottomAfterForeground || nearBottom);
    try {
      await _realtime.connect();
      if (!mounted) return;
      if (shouldStick) {
        _forceLatestMode = true;
        _enterStickBottomPending = true;
      }
      await _load(silent: true);
      if (!mounted) return;
      if (shouldStick && !_shouldAnchorMessagesAtTop) {
        _pendingStickBottomAfterForeground = false;
        _scrollBottom(force: true, gentle: false);
      } else {
        // 看历史时清掉误挂起的贴底标记，避免后续仍被拉到底。
        _pendingStickBottomAfterForeground = false;
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

  @override
  void dispose() {
    _loadGeneration++;
    if (isDesktopCommOnly) {
      clearDesktopScreenshotHotkey(_onWindowsHotkeyPressed);
    }
    WidgetsBinding.instance.removeObserver(this);
    ChatForegroundSync.removeListener(_onChatForegroundResumed);
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
    // 用户已上滑离开最新端时，清掉进会话贴底标记，避免后续补历史被拽回底部。
    if (pos.pixels > 72) {
      _enterStickBottomPending = false;
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
    if (!_userInteractedWithScroll) return false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs < _newerLoadCooldownUntilMs) return false;
    return pos.pixels <= 72;
  }

  /// 是否应自动加载更早消息（含：已顶到历史端 / 列表尚未撑满视口）。
  bool _shouldAutoloadOlder(ScrollPosition pos) {
    if (!_hasMore || _loadingOlder || _olderScrollRestorePending) return false;
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
    final pos = _scrollController.position;
    // reverse 列表：dy<0 朝历史；dy>0 朝更新。
    if (event.scrollDelta.dy < 0) {
      if (!_hasMore || _loadingOlder || _olderScrollRestorePending) return;
      if (pos.maxScrollExtent <= 24 ||
          pos.pixels >=
              pos.maxScrollExtent -
                  math.max(160.0, pos.viewportDimension * 0.4)) {
        unawaited(_loadOlder());
      }
      return;
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
    final convId = _conversation?.id ?? 0;
    if (convId <= 0) return;
    if (event.conversationId != null && event.conversationId != convId) return;

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

    final stickBottom = _isNearBottom;
    final prevNewestId = _newestMessageId;
    setState(() {
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
    });
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
    return true;
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
    // PC 滚轮常无 dragDetails；仅桌面用 scrollDelta 兜底，避免 APP 把程序化滚动误判成用户上滑。
    if (isDesktopCommOnly &&
        notification is ScrollUpdateNotification &&
        notification.dragDetails == null &&
        (notification.scrollDelta ?? 0).abs() > 0.5) {
      _userInteractedWithScroll = true;
      _enterStickBottomPending = false;
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
      _updateStickBottomState();
      if (_canMarkReadNow && _isNearBottom) {
        unawaited(_markReadIfNeeded());
      }
    }
    return false;
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    // reverse 列表：pixels 接近 0 即在最新消息端。
    return _scrollController.position.pixels <= 72;
  }

  /// 上滑超过该阈值才显示「回到最新」，避免轻微滚动闪一下。
  bool get _isScrolledAwayFromLatest {
    if (!_scrollController.hasClients) return false;
    return _scrollController.position.pixels > 140;
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
    if (_isScrolledAwayFromLatest ||
        (_userInteractedWithScroll && !_isNearBottom)) {
      return false;
    }
    return _enterStickBottomPending || _isNearBottom;
  }

  void _scrollToLatestOnEnter() {
    if (_locatedMode) return;
    setState(_clearPendingNewMessages);
    _ensureScrolledToBottom(attempt: 0);
  }

  /// reverse 列表进入时 scroll=0 即最新；仅图片/GIF 撑高后再补一次。
  void _ensureScrolledToBottom({required int attempt}) {
    if (!mounted || _locatedMode) return;
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
      final conv = await _resolveConversation();
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
        return;
      }
      final NativeMessagePage page;
      if (focusId > 0) {
        page = await _service.fetchMessagesAround(
          conv.id,
          focusId,
          hint: widget.focusMessageHint,
        );
      } else {
        page = await _service.fetchMessagePage(
          conv.id,
          size: _scrollMetricsForScreen().initialPageSize,
        );
      }
      if (stale()) return;
      if (!_isPrivate) {
        try {
          _groupMembers = await _service.fetchConversationMembers(conv.id);
        } catch (_) {
          if (stale()) return;
          try {
            final info = await _service.fetchGroupInfo(conv.id);
            if (stale()) return;
            _groupMembers = info.members
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
          } catch (_) {}
        }
        if (stale()) return;
        unawaited(_refreshGroupReadMap(conv.id));
      }
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
          !_isNearBottom;
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
      final stickLatest = focusId <= 0 && _shouldStickToLatestOnLoad;
      _forceLatestMode = false;
      if (focusId > 0) {
        _highlightAndScroll(focusId);
      } else if (stickLatest || forceLatest) {
        _scrollToLatestOnEnter();
      } else {
        _recountPendingNewMessages();
      }
      // PC 宽屏短会话常未撑满视口，进会话后自动补历史，避免只能点「加载更早」。
      if (focusId <= 0 && page.hasMore) {
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
        _firstUnreadMessageId == messageId) {
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
    final oldMax = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final oldPixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    final batchSize = _scrollController.hasClients
        ? _ChatScrollMetrics.fromListViewport(
            _scrollController.position.viewportDimension,
          ).batchPageSize
        : _scrollMetricsForScreen().batchPageSize;
    _olderScrollHold?.cancel();
    if (_scrollController.hasClients) {
      _olderScrollHold = _scrollController.position.hold(() {});
      _olderScrollHoldPixels = oldPixels;
      _olderScrollHoldMax = oldMax;
    }
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
      // 贴底看最新时补历史：只钉在最新端，不要 ensureVisible 把视口往上拽。
      // 用户已上滑看历史时，绝不能走贴底分支（否则 APP 上滑加载会被拽回最新）。
      final stickBottom =
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
      _scrollRestoreAnchorId = anchorMessageId;
      setState(() {
        _messages = merged;
        _hasMore = page.hasMore;
        _loadingOlder = false;
        _refreshFirstUnreadAfterHistory(merged);
      });
      unawaited(_refreshDownloadedFileFlags());
      _olderScrollRestorePending = true;
      _olderLoadCooldownUntilMs = DateTime.now().millisecondsSinceEpoch + 600;
      _ensureAnchorVisibleAfterOlderLoad(
        anchorMessageId,
        fallbackPixels: _olderScrollHoldPixels,
        fallbackOldMax: _olderScrollHoldMax,
        gen: _messageScrollGen,
      );
      _scheduleUnreadVisibilityCheck();
    } catch (e) {
      _olderScrollHold?.cancel();
      _olderScrollHold = null;
      _scrollRestoreAnchorId = null;
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
    });
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

  void _highlightAndScroll(
    int messageId, {
    Duration duration = const Duration(milliseconds: 280),
  }) {
    final gen = ++_messageScrollGen;
    setState(() => _highlightMessageId = messageId);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightMessageId = null);
    });
    _ensureMessageVisible(messageId, gen: gen, duration: duration);
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
        _preScrollTowardMessage(messageId);
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
      membershipStatus: conv.membershipStatus,
      assistantGenerating: conv.assistantGenerating,
      assistantGeneratingStatus: conv.assistantGeneratingStatus,
    );
  }

  void _onInputFocusChanged() {
    if (!_inputFocusNode.hasFocus) return;
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
    }
    unawaited(_scrollToLatestForInput());
  }

  Future<void> _scrollToLatestForInput() async {
    if (_locatedMode) {
      await _jumpToLatest();
      return;
    }
    if (_shouldAnchorMessagesAtTop) return;
    setState(_clearPendingNewMessages);
    _wasNearBottom = true;
    void snap({bool animated = false}) {
      if (!mounted) return;
      _scrollBottom(force: true, animated: animated, gentle: true);
    }

    snap(animated: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => snap());
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (mounted && _inputFocusNode.hasFocus) snap();
    });
  }

  void _scrollToLatestAfterKeyboard() {
    unawaited(_scrollToLatestForInput());
  }

  Future<void> _send() async {
    if (_useDesktopAttachmentStaging &&
        _desktopComposerAttachments.isNotEmpty) {
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
    final keepKeyboard = !isWideChatLayout(context);
    if (keepKeyboard) _inputFocusNode.requestFocus();
    try {
      var conv = _conversation;
      if (conv == null || conv.id <= 0) {
        final ready = await _ensureConversationReadyForSend();
        if (ready == null || ready.id <= 0) {
          throw Exception('会话未就绪');
        }
        conv = ready;
        // 首次建会话的 await 后补一次焦点，防止键盘被系统收起。
        if (keepKeyboard && mounted) _inputFocusNode.requestFocus();
      }
      await _service.sendText(conv.id, text, payload: payloadOrNull);
      _inputController.clear();
      _clearComposeDraft();
      setState(() {
        _emojiOpen = false;
        _locatedMode = false;
        _quoteDraft = null;
      });
      await _load(silent: true);
      if (mounted) {
        setState(_clearPendingNewMessages);
        _scrollToPreferredAnchor(force: true);
        if (keepKeyboard) _inputFocusNode.requestFocus();
      }
    } catch (e) {
      _showToast('发送失败：${friendlyErrorText(e)}');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        if (keepKeyboard) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _inputFocusNode.requestFocus();
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
    setState(() => _sending = true);
    try {
      await _guardSend(() async {
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
              bytes: attachment.bytes,
              fileName: attachment.fileName,
              mimeType: attachment.mimeType,
              onProgress: _setUploadProgress,
              cancelToken: cancel,
            );
          }
          if (!mounted) return;
          setState(() => _desktopComposerAttachments.removeAt(0));
        }
      }, cancelToken: cancel);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _stageDesktopAttachment({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required bool isImage,
    required String sourceLabel,
  }) {
    if (!_useDesktopAttachmentStaging) return;
    if (_desktopComposerAttachments.length >= _maxDesktopComposerAttachments) {
      _showToast('一次最多添加 $_maxDesktopComposerAttachments 个附件');
      return;
    }
    setState(() {
      _desktopComposerAttachments.add(
        _DesktopComposerAttachment(
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          isImage: isImage,
          sourceLabel: sourceLabel,
        ),
      );
    });
    _inputFocusNode.requestFocus();
  }

  void _removeDesktopComposerAttachment(_DesktopComposerAttachment attachment) {
    setState(() => _desktopComposerAttachments.remove(attachment));
  }

  List<int> _parseMentionUserIds(String text) {
    if (_isPrivate || _groupMembers.isEmpty) return const <int>[];
    const atAll = '所有人';
    final ids = <int>[];
    final seen = <int>{};
    if (text.contains('@$atAll')) {
      for (final m in _groupMembers) {
        final uid = (m['userId'] as num?)?.toInt() ?? 0;
        if (uid <= 0 || uid == widget.session.userId || seen.contains(uid))
          continue;
        seen.add(uid);
        ids.add(uid);
      }
      return ids;
    }
    for (final m in _groupMembers) {
      final name = (m['displayName'] ?? m['name'] ?? '').toString();
      if (name.isEmpty || !text.contains('@$name')) continue;
      final uid = (m['userId'] as num?)?.toInt() ?? 0;
      if (uid <= 0 || seen.contains(uid)) continue;
      seen.add(uid);
      ids.add(uid);
    }
    return ids;
  }

  Future<bool> _ensureCameraPermission() async {
    if (kIsWeb) return true;
    if (await ensureCameraPermission()) return true;
    _showToast(cameraPermissionHint(await Permission.camera.status));
    return false;
  }

  Future<bool> _ensurePhotosPermission() async {
    if (kIsWeb) return true;
    if (await ensurePhotosPermission()) return true;
    _showToast(photosPermissionHint(await Permission.photos.status));
    return false;
  }

  /// 单张图片原图大小上限（压缩后仍超过则拒绝）。
  static const int _maxImageBytes = 30 * 1024 * 1024;

  /// 普通文件大小上限。
  static const int _maxFileBytes = 100 * 1024 * 1024;

  bool _checkSizeLimit(int length, int maxBytes, String fileName) {
    if (length <= maxBytes) return true;
    final mb = (maxBytes / (1024 * 1024)).round();
    _showToast('$fileName 超过 ${mb}MB 上限，无法发送');
    return false;
  }

  Future<({Uint8List bytes, String fileName, String mimeType})?>
  _prepareChatImagePreview(Uint8List bytes, String fileName) async {
    final preview = await buildChatImagePreview(bytes, fileName: fileName);
    if (preview == null) return null;
    return (
      bytes: preview.bytes,
      fileName: preview.fileName,
      mimeType: preview.mimeType,
    );
  }

  /// 统一图片确认：预览 + 原图开关 + 可选编辑。取消返回 null。
  Future<List<ChatImageDraft>?> _confirmImageDrafts(
    List<ChatImageDraft> drafts,
  ) async {
    if (drafts.isEmpty) return null;
    if (!mounted) return null;
    // GIF 无需确认页上的原图选项，但仍走同一预览以便统一发送。
    return openChatImageBatchPreview(context, drafts: drafts);
  }

  Future<void> _emitPreparedImageDrafts(
    List<ChatImageDraft> drafts, {
    required String sourceLabel,
  }) async {
    if (drafts.isEmpty) return;
    if (_useDesktopAttachmentStaging) {
      for (final draft in drafts) {
        final bytes = draft.sendAsOriginal && !draft.edited
            ? draft.sourceBytes
            : draft.bytes;
        final fileName = draft.uploadFileName;
        if (!_checkSizeLimit(bytes.length, _maxImageBytes, fileName)) continue;
        _stageDesktopAttachment(
          bytes: bytes,
          fileName: fileName,
          mimeType:
              lookupMimeType(fileName) ??
              (draft.sendAsOriginal && !draft.edited
                  ? (lookupMimeType(draft.sourceFileName) ?? 'image/*')
                  : 'image/jpeg'),
          isImage: true,
          sourceLabel: sourceLabel,
        );
      }
      return;
    }

    final cancel = ChatUploadCancelToken();
    await _guardSend(() async {
      final total = drafts.length;
      var done = 0;
      for (final draft in drafts) {
        cancel.throwIfCancelled();
        final bytes = draft.sendAsOriginal && !draft.edited
            ? draft.sourceBytes
            : draft.bytes;
        final fileName = draft.uploadFileName;
        if (!_checkSizeLimit(bytes.length, _maxImageBytes, fileName)) {
          done++;
          continue;
        }
        final mimeType =
            lookupMimeType(fileName) ??
            (draft.sendAsOriginal && !draft.edited
                ? (lookupMimeType(draft.sourceFileName) ?? 'image/*')
                : 'image/jpeg');
        final baseDone = done;
        _beginUpload(
          total > 1 ? '上传图片 (${baseDone + 1}/$total)' : '上传图片',
          previewBytes: bytes,
          kind: 'IMAGE',
          fileName: fileName,
        );
        await _service.sendImage(
          conversationId: _requireReadyConversationId(),
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          sourceLabel: sourceLabel,
          preparePreview: () => _prepareChatImagePreview(bytes, fileName),
          onProgress: (p) => _setUploadProgress(
            (baseDone + p) / total,
            label: total > 1 ? '上传图片 (${baseDone + 1}/$total)' : '上传图片',
          ),
          cancelToken: cancel,
        );
        done++;
      }
    }, cancelToken: cancel);
  }

  Future<void> _sendImageFrom(ImageSource source, String label) async {
    final conv = _conversation;
    if (conv == null || _mediaBusy) return;
    if (source == ImageSource.camera && !await _ensureCameraPermission()) {
      return;
    }
    if (source == ImageSource.gallery && !await _ensurePhotosPermission()) {
      return;
    }
    final picked = await _imagePicker.pickImage(source: source);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final fileName = picked.name.isNotEmpty
        ? picked.name
        : 'image-${DateTime.now().millisecondsSinceEpoch}.jpg';
    if (!_checkSizeLimit(bytes.length, _maxImageBytes, fileName)) return;
    if (chatImageShouldSkipEditor(fileName: fileName)) {
      await _emitPreparedImageDrafts([
        ChatImageDraft(bytes: bytes, fileName: fileName, sendAsOriginal: true),
      ], sourceLabel: label);
      return;
    }
    final confirmed = await _confirmImageDrafts([
      ChatImageDraft(bytes: bytes, fileName: fileName),
    ]);
    if (confirmed == null || confirmed.isEmpty) return;
    await _emitPreparedImageDrafts(confirmed, sourceLabel: label);
  }

  /// 粘贴图片 / 文件（对齐拖入发送；PC 支持从资源管理器复制文件后 Ctrl+V）。
  Future<bool> _attemptPasteImage() async {
    if (_mediaBusy || _conversation == null || _conversation!.dissolved) {
      return false;
    }
    try {
      // 剪贴板已有普通文本（用户又复制了文字）时，绝不用旧的图片/文件备份抢粘贴。
      final clipText =
          (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
      final hasRealText =
          clipText.isNotEmpty &&
          !_isImageClipboardPlaceholder(clipText) &&
          !_isFileClipboardPlaceholder(clipText);
      if (hasRealText) {
        ChatImageClipboard.clear();
        ChatFileClipboard.clear();
        return false;
      }

      final image = await Pasteboard.image;
      if (image != null && image.isNotEmpty && _looksLikeImageBytes(image)) {
        ChatFileClipboard.clear();
        await _sendPastedImageBytes(image);
        return true;
      }
      if (!kIsWeb) {
        final paths = await Pasteboard.files();
        if (paths.isNotEmpty) {
          final handled = await _pasteLocalFilePaths(paths, sourceLabel: '粘贴');
          if (handled) return true;
        }
      }
      // 系统剪贴板拿不到时，回退到本应用「复制图片」的进程内备份。
      final mem = ChatImageClipboard.peek();
      if (mem != null) {
        await _sendPastedImageBytes(
          mem.bytes,
          fileName: mem.fileName,
          openEditor: false,
          sourceLabel: '粘贴',
        );
        return true;
      }
      // PC：本应用「复制文件」的进程内备份。
      if (isDesktopCommOnly) {
        final memFile = ChatFileClipboard.peek();
        if (memFile != null) {
          Uint8List bytes = memFile.bytes;
          if (bytes.isEmpty && (memFile.localPath ?? '').trim().isNotEmpty) {
            bytes = await XFile(memFile.localPath!.trim()).readAsBytes();
          }
          if (bytes.isNotEmpty) {
            if (_isChatImageFileName(memFile.fileName)) {
              await _sendPastedImageBytes(
                bytes,
                fileName: memFile.fileName,
                openEditor: false,
                sourceLabel: '粘贴',
              );
            } else if (isChatVideoFileName(memFile.fileName)) {
              final path = (memFile.localPath ?? '').trim();
              if (path.isNotEmpty) {
                await _sendVideoXFile(
                  XFile(path, name: memFile.fileName),
                  sourceLabel: '粘贴',
                );
              } else {
                // 无本地路径的视频字节：暂按文件发送。
                await _sendFileBytes(bytes, fileName: memFile.fileName);
              }
            } else {
              await _sendFileBytes(bytes, fileName: memFile.fileName);
            }
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('[Chat] paste attachment failed: $e');
    }
    return false;
  }

  /// 将剪贴板中的本地文件路径粘贴为图片 / 视频 / 文件（与拖入逻辑对齐）。
  Future<bool> _pasteLocalFilePaths(
    List<String> paths, {
    required String sourceLabel,
  }) async {
    final cleaned = paths
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (cleaned.isEmpty) return false;

    const maxPaste = 20;
    if (cleaned.length > maxPaste) {
      _showToast('一次最多粘贴 $maxPaste 个文件');
    }
    final toSend = cleaned.take(maxPaste).toList();
    final imageDrafts = <ChatImageDraft>[];
    var handled = false;

    for (final path in toSend) {
      if (!mounted || _conversation == null || _conversation!.dissolved) {
        break;
      }
      final fileName = path.replaceAll('\\', '/').split('/').last;
      try {
        final bytes = await XFile(path).readAsBytes();
        if (bytes.isEmpty) {
          _showToast('$fileName 无法读取');
          continue;
        }
        if (_isChatImageFileName(fileName)) {
          if (!_checkSizeLimit(bytes.length, _maxImageBytes, fileName)) {
            continue;
          }
          imageDrafts.add(ChatImageDraft(bytes: bytes, fileName: fileName));
          handled = true;
        } else if (isDesktopCommOnly &&
            (isChatVideoFileName(fileName) ||
                isChatVideoXFile(XFile(path, name: fileName)))) {
          await _sendVideoXFile(
            XFile(path, name: fileName),
            sourceLabel: sourceLabel,
          );
          handled = true;
        } else if (isDesktopCommOnly) {
          await _sendFileBytes(bytes, fileName: fileName);
          handled = true;
        }
      } catch (e) {
        _showToast('$fileName 粘贴失败：${friendlyErrorText(e)}', error: true);
      }
    }

    if (imageDrafts.isNotEmpty) {
      ChatFileClipboard.clear();
      if (imageDrafts.length == 1) {
        await _sendPastedImageBytes(
          imageDrafts.first.bytes,
          fileName: imageDrafts.first.fileName,
          sourceLabel: sourceLabel,
        );
      } else {
        final confirmed = await _confirmImageDrafts(imageDrafts);
        if (confirmed != null && confirmed.isNotEmpty) {
          await _emitPreparedImageDrafts(confirmed, sourceLabel: sourceLabel);
        }
      }
      return true;
    }
    return handled;
  }

  bool _isImageClipboardPlaceholder(String text) {
    final t = text.trim();
    return t == '[图片]' || t == '图片' || t == '发送了一张图片';
  }

  bool _isFileClipboardPlaceholder(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return t == '[文件]' ||
        t == '文件' ||
        t.startsWith('[文件]') ||
        t.startsWith('[附件]');
  }

  bool _looksLikeImageBytes(Uint8List bytes) {
    if (bytes.length < 12) return false;
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
    // PNG
    if (bytes[0] == 0x89 && bytes[1] == 0x50) return true;
    // GIF
    if (bytes[0] == 0x47 && bytes[1] == 0x49) return true;
    // BMP（Windows 剪贴板读回常见）
    if (bytes[0] == 0x42 && bytes[1] == 0x4D) return true;
    // WEBP
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45) {
      return true;
    }
    return false;
  }

  Future<void> _sendPastedImageBytes(
    Uint8List bytes, {
    String? fileName,
    String sourceLabel = '粘贴',
    bool openEditor = true,
  }) async {
    final conv = _conversation;
    if (conv == null || _mediaBusy) return;
    final name =
        fileName ?? 'paste-${DateTime.now().millisecondsSinceEpoch}.png';
    if (!_checkSizeLimit(bytes.length, _maxImageBytes, name)) return;
    if (chatImageShouldSkipEditor(fileName: name)) {
      await _emitPreparedImageDrafts([
        ChatImageDraft(bytes: bytes, fileName: name, sendAsOriginal: true),
      ], sourceLabel: sourceLabel);
      return;
    }
    if (openEditor) {
      final confirmed = await _confirmImageDrafts([
        ChatImageDraft(bytes: bytes, fileName: name),
      ]);
      if (confirmed == null || confirmed.isEmpty) return;
      await _emitPreparedImageDrafts(confirmed, sourceLabel: sourceLabel);
      return;
    }
    // 多文件拖入时不逐张弹预览：默认压缩后发送/暂存。
    final compressed = await compressChatImageForSend(bytes, fileName: name);
    final outBytes = compressed ?? bytes;
    final outName = compressed == null ? name : chatImageEditedFileName(name);
    if (!_checkSizeLimit(outBytes.length, _maxImageBytes, outName)) return;
    if (_useDesktopAttachmentStaging) {
      _stageDesktopAttachment(
        bytes: outBytes,
        fileName: outName,
        mimeType: lookupMimeType(outName) ?? 'image/jpeg',
        isImage: true,
        sourceLabel: sourceLabel,
      );
      return;
    }
    final cancel = ChatUploadCancelToken();
    await _guardSend(() async {
      _beginUpload(
        '上传图片',
        previewBytes: outBytes,
        kind: 'IMAGE',
        fileName: outName,
      );
      await _service.sendImage(
        conversationId: _requireReadyConversationId(),
        bytes: outBytes,
        fileName: outName,
        mimeType: lookupMimeType(outName) ?? 'image/jpeg',
        sourceLabel: sourceLabel,
        preparePreview: () => _prepareChatImagePreview(outBytes, outName),
        onProgress: (p) => _setUploadProgress(p),
        cancelToken: cancel,
      );
    }, cancelToken: cancel);
  }

  /// PC：微信式应用内框选截图 → 裁剪编辑 → 发送。
  Future<void> _desktopScreenshotAndSend() async {
    if (!isDesktopCommOnly || _mediaBusy || _conversation == null) return;
    if (_conversation!.dissolved) {
      _showToast('会话已解散，无法发送');
      return;
    }

    Uint8List? image;
    try {
      image = await captureDesktopRegionScreenshot();
    } catch (e) {
      if (!mounted) return;
      final msg = friendlyErrorText(e);
      if (msg.contains('取消')) {
        _showToast('已取消截图');
      } else {
        _showToast('截图失败：$msg', error: true);
      }
      return;
    }
    if (!mounted) return;
    if (image == null || image.isEmpty) {
      _showToast('已取消截图');
      return;
    }

    await _sendPastedImageBytes(
      image,
      fileName: 'screenshot-${DateTime.now().millisecondsSinceEpoch}.png',
      sourceLabel: '截图',
      openEditor: true,
    );
  }

  /// Ctrl+Alt+A：窗口聚焦时全局可触发（不依赖当前 Focus 落在哪个输入框）。
  bool _onDesktopScreenshotHotkey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyA) return false;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final ctrl =
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    final alt =
        pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight);
    if (!ctrl || !alt) return false;
    if (_mediaBusy || _conversation == null || _conversation!.dissolved) {
      return true;
    }
    unawaited(_desktopScreenshotAndSend());
    return true;
  }

  /// PC：系统文件对话框选图/视频（Windows 上 image_picker 基本选不到视频）。
  Future<List<XFile>> _pickDesktopAlbumOrVideo({
    required bool videoOnly,
  }) async {
    final videos = XTypeGroup(
      label: 'videos',
      extensions: kChatVideoPickExtensions,
    );
    if (videoOnly) {
      try {
        return await openFiles(acceptedTypeGroups: [videos]);
      } catch (_) {
        return openFiles();
      }
    }
    const images = XTypeGroup(
      label: 'images',
      extensions: <String>[
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'bmp',
        'heic',
        'heif',
      ],
    );
    try {
      return await openFiles(acceptedTypeGroups: [images, videos]);
    } catch (_) {
      try {
        return await openFiles(acceptedTypeGroups: [images]);
      } catch (_) {
        return openFiles();
      }
    }
  }

  Future<void> _pickAndSendVideo() async {
    final conv = _conversation;
    if (conv == null || _mediaBusy) return;
    List<XFile> picked;
    if (isDesktopCommOnly) {
      picked = await _pickDesktopAlbumOrVideo(videoOnly: true);
    } else {
      if (!await _ensurePhotosPermission()) return;
      final one = await _imagePicker.pickVideo(source: ImageSource.gallery);
      picked = one == null ? const <XFile>[] : <XFile>[one];
    }
    if (picked.isEmpty) return;
    for (final file in picked) {
      if (!mounted || _conversation == null) return;
      if (!isChatVideoXFile(file)) {
        _showToast('请选择视频文件');
        continue;
      }
      await _sendVideoXFile(file, sourceLabel: '视频');
    }
  }

  Future<void> _sendMultiImagesFromGallery() async {
    final conv = _conversation;
    if (conv == null || _mediaBusy) return;

    // 相册同时可选图片 + 视频（对齐微信）。PC 走文件对话框，避免选不到视频。
    List<XFile> picked;
    if (isDesktopCommOnly) {
      picked = await _pickDesktopAlbumOrVideo(videoOnly: false);
    } else {
      if (!await _ensurePhotosPermission()) return;
      try {
        picked = await _imagePicker.pickMultipleMedia();
      } catch (_) {
        picked = await _imagePicker.pickMultiImage();
      }
    }
    if (picked.isEmpty) return;

    final imageFiles = <XFile>[];
    final videoFiles = <XFile>[];
    for (final file in picked) {
      if (isChatVideoXFile(file)) {
        videoFiles.add(file);
      } else {
        imageFiles.add(file);
      }
    }

    for (final video in videoFiles) {
      if (!mounted || _conversation == null) return;
      await _sendVideoXFile(video, sourceLabel: '相册');
    }
    if (imageFiles.isEmpty) return;

    final drafts = <ChatImageDraft>[];
    for (final file in imageFiles) {
      final bytes = await file.readAsBytes();
      final fileName = file.name.isNotEmpty
          ? file.name
          : 'image-${DateTime.now().millisecondsSinceEpoch}.jpg';
      if (!_checkSizeLimit(bytes.length, _maxImageBytes, fileName)) continue;
      drafts.add(ChatImageDraft(bytes: bytes, fileName: fileName));
    }
    if (drafts.isEmpty) return;
    if (!mounted) return;

    final confirmed = await _confirmImageDrafts(drafts);
    if (confirmed == null || confirmed.isEmpty) return;
    await _emitPreparedImageDrafts(confirmed, sourceLabel: '多图');
  }

  /// 长按拍照：录制小视频（最长 60 秒）。
  Future<void> _recordAndSendVideo() async {
    final conv = _conversation;
    if (conv == null || _mediaBusy) return;
    if (!await _ensureCameraPermission()) return;
    if (!await ensureMicrophonePermission()) {
      _showToast(microphonePermissionHint(await Permission.microphone.status));
      return;
    }
    final picked = await _imagePicker.pickVideo(
      source: ImageSource.camera,
      maxDuration: kChatVideoRecordMaxDuration,
    );
    if (picked == null) return;
    await _sendVideoXFile(picked, sourceLabel: '拍摄');
  }

  Future<void> _sendVideoXFile(
    XFile file, {
    required String sourceLabel,
  }) async {
    final conv = _conversation;
    if (conv == null || _mediaBusy) return;
    final fileName = file.name.isNotEmpty
        ? file.name
        : 'video-${DateTime.now().millisecondsSinceEpoch}.mp4';
    final cancel = ChatUploadCancelToken();
    await _guardSend(() async {
      _beginUpload('上传视频', kind: 'VIDEO', fileName: fileName);
      cancel.throwIfCancelled();
      ChatVideoPrepared prepared;
      try {
        if (file.path.isNotEmpty && !kIsWeb) {
          prepared = await prepareChatVideoForSend(
            path: file.path,
            preferredName: fileName,
            onProgress: (p) {
              cancel.throwIfCancelled();
              _setUploadProgress(p * 0.35, label: '压缩视频');
            },
          );
        } else {
          final bytes = await file.readAsBytes();
          cancel.throwIfCancelled();
          prepared = await prepareChatVideoBytesForSend(
            bytes: bytes,
            fileName: fileName,
          );
        }
      } on ChatUploadCancelledException {
        rethrow;
      } catch (e) {
        if (cancel.isCancelled) throw const ChatUploadCancelledException();
        throw Exception(friendlyErrorText(e));
      }
      cancel.throwIfCancelled();
      _beginUpload(
        '上传视频',
        previewBytes: prepared.thumbnailBytes,
        kind: 'VIDEO',
        fileName: prepared.fileName,
        videoDurationSec: prepared.durationSec,
        videoWidth: prepared.width,
        videoHeight: prepared.height,
      );
      await _service.sendVideo(
        conversationId: _requireReadyConversationId(),
        bytes: prepared.bytes,
        fileName: prepared.fileName,
        mimeType: prepared.mimeType,
        durationSec: prepared.durationSec,
        thumbnailBytes: prepared.thumbnailBytes,
        width: prepared.width,
        height: prepared.height,
        onProgress: (p) => _setUploadProgress(0.35 + p * 0.65, label: '上传视频'),
        cancelToken: cancel,
      );
    }, cancelToken: cancel);
  }

  Future<void> _sendFile() async {
    final conv = _conversation;
    if (conv == null || _mediaBusy) return;
    final file = await openFile();
    if (file == null) return;
    final fileName = file.name.isNotEmpty
        ? file.name
        : file.path.replaceAll('\\', '/').split('/').last;
    if (isChatVideoXFile(file) || isChatVideoFileName(fileName)) {
      await _sendVideoXFile(
        XFile(
          file.path,
          name: fileName,
          mimeType: file.mimeType ?? lookupMimeType(fileName),
        ),
        sourceLabel: '文件',
      );
      return;
    }
    final bytes = await file.readAsBytes();
    if (_useDesktopAttachmentStaging) {
      if (!_checkSizeLimit(bytes.length, _maxFileBytes, fileName)) return;
      _stageDesktopAttachment(
        bytes: bytes,
        fileName: fileName,
        mimeType:
            file.mimeType ??
            lookupMimeType(fileName) ??
            'application/octet-stream',
        isImage: false,
        sourceLabel: '文件',
      );
      return;
    }
    await _sendFileBytes(bytes, fileName: fileName);
  }

  Future<void> _sendFileBytes(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final conv = _conversation;
    if (conv == null || _mediaBusy) return;
    if (!_checkSizeLimit(bytes.length, _maxFileBytes, fileName)) return;
    final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
    if (_useDesktopAttachmentStaging) {
      _stageDesktopAttachment(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        isImage: false,
        sourceLabel: '拖入',
      );
      return;
    }
    final cancel = ChatUploadCancelToken();
    await _guardSend(() async {
      _beginUpload('上传文件', kind: 'FILE', fileName: fileName);
      await ChatFileUploadCoordinator.instance.sendFile(
        session: widget.session,
        conversationId: _requireReadyConversationId(),
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        cancelToken: cancel,
      );
    }, cancelToken: cancel);
  }

  static bool _isChatImageFileName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  Future<void> _onDesktopFilesDropped(DropDoneDetails detail) async {
    final conv = _conversation;
    if (!_supportsDesktopFileDrop ||
        !TickerMode.valuesOf(context).enabled ||
        conv == null ||
        conv.dissolved ||
        _messageMultiSelectMode) {
      return;
    }
    if (_mediaBusy) {
      _showToast('正在上传，请稍后再拖入');
      return;
    }

    final accessed = <Uint8List>[];
    try {
      final files = <XFile>[];
      for (final item in detail.files) {
        if (item is DropItemDirectory) continue;
        final bookmark = item.extraAppleBookmark;
        if (bookmark != null && bookmark.isNotEmpty) {
          try {
            final ok = await DesktopDrop.instance
                .startAccessingSecurityScopedResource(bookmark: bookmark);
            if (ok) accessed.add(bookmark);
          } catch (_) {}
        }
        files.add(XFile(item.path, name: item.name));
      }
      if (files.isEmpty) {
        _showToast('请拖入文件或图片（不支持文件夹）');
        return;
      }
      const maxDrop = 20;
      if (files.length > maxDrop) {
        _showToast('一次最多拖入 $maxDrop 个文件');
      }
      final toSend = files.take(maxDrop).toList();
      final imageDrafts = <ChatImageDraft>[];
      for (var i = 0; i < toSend.length; i++) {
        if (!mounted || _conversation == null || _conversation!.dissolved) {
          return;
        }
        final file = toSend[i];
        final fileName = file.name.isNotEmpty
            ? file.name
            : file.path.replaceAll('\\', '/').split('/').last;
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          _showToast('$fileName 无法读取');
          continue;
        }
        if (_isChatImageFileName(fileName)) {
          if (!_checkSizeLimit(bytes.length, _maxImageBytes, fileName)) {
            continue;
          }
          imageDrafts.add(ChatImageDraft(bytes: bytes, fileName: fileName));
        } else if (isChatVideoXFile(file) || isChatVideoFileName(fileName)) {
          await _sendVideoXFile(file, sourceLabel: '拖入');
        } else {
          await _sendFileBytes(bytes, fileName: fileName);
        }
      }
      if (imageDrafts.isNotEmpty) {
        final confirmed = await _confirmImageDrafts(imageDrafts);
        if (confirmed != null && confirmed.isNotEmpty) {
          await _emitPreparedImageDrafts(confirmed, sourceLabel: '拖入');
        }
      }
    } catch (e) {
      _showToast('拖入发送失败：${friendlyErrorText(e)}', error: true);
    } finally {
      for (final bookmark in accessed) {
        try {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(
            bookmark: bookmark,
          );
        } catch (_) {}
      }
    }
  }

  Future<void> _startHoldRecord(Offset focalPoint) async {
    if (_mediaBusy || _recording) return;
    if (MeetingLiveController.instance.isActive) {
      _showToast('会议录音进行中，暂无法发送语音');
      return;
    }
    if (!NativeAudioRecorder.isSupported) {
      _showToast('当前环境不支持录音');
      return;
    }
    if (!kIsWeb) {
      final mic = await ensureMicrophonePermission();
      if (!mic) {
        _showToast('请先允许麦克风权限');
        return;
      }
    }
    try {
      await NativeAudioRecorder.instance.start();
      _recordTicker?.cancel();
      setState(() {
        _recording = true;
        _recordHoldAction = VoiceHoldAction.none;
        _recordFocalPoint = focalPoint;
        _recordDurationMs = 0;
      });
      _recordTicker = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (!mounted || !_recording) return;
        setState(() => _recordDurationMs += 120);
        // 最长 60 秒，到点强制发送语音（忽略当前取消/转文字手势）。
        if (_recordDurationMs >= kVoiceRecordMaxDurationMs) {
          _recordTicker?.cancel();
          _recordHoldAction = VoiceHoldAction.none;
          _showToast('已达最长 60 秒，自动发送');
          unawaited(_finishHoldRecord());
        }
      });
    } catch (e) {
      if (e is NativeAudioRecorderBusyException) {
        _showToast(e.message);
        return;
      }
      _showToast('录音启动失败：${friendlyErrorText(e)}');
    }
  }

  Future<void> _finishHoldRecord() async {
    if (!_recording) return;
    if (_recordWillCancel) {
      await _cancelHoldRecordInternal(showHint: true);
      return;
    }
    final transcribe = !isDesktopCommOnly && _recordWillTranscribe;
    _recordTicker?.cancel();
    setState(() {
      _recording = false;
      _recordHoldAction = VoiceHoldAction.none;
      _recordFocalPoint = null;
    });
    try {
      final recorded = await NativeAudioRecorder.instance.stop();
      if (recorded == null) return;
      if (recorded.durationMs < 500) {
        _showToast('录音时间太短');
        return;
      }
      final conv = _conversation;
      if (conv == null) return;
      final file = XFile(recorded.path);
      final bytes = await file.readAsBytes();
      final fileName = Uri.file(recorded.path).pathSegments.isEmpty
          ? 'voice-${DateTime.now().millisecondsSinceEpoch}.m4a'
          : Uri.file(recorded.path).pathSegments.last;
      final mimeType = lookupMimeType(fileName) ?? 'audio/mp4';
      final durationSec = (recorded.durationMs / 1000).ceil();
      if (transcribe) {
        try {
          // 录音草稿只在当前编辑面板使用，不写入消息转写缓存。
          final text = await _service.transcribeVoice(
            bytes: bytes,
            fileName: fileName,
          );
          if (mounted) {
            await _showVoiceTranscriptComposer(
              text,
              originalBytes: bytes,
              originalFilePath: recorded.path,
              fileName: fileName,
              mimeType: mimeType,
              durationSec: durationSec,
            );
          }
        } catch (e) {
          if (mounted) {
            // ASR 错误已在 ConversationService 里转成中文，避免再被友好文案盖掉。
            final detail = friendlyErrorText(
              e,
              fallback: e.toString().replaceFirst(
                RegExp(r'^Exception:\s*'),
                '',
              ),
            );
            _showToast(
              detail.startsWith('转写') || detail.startsWith('语音')
                  ? detail
                  : '转写失败：$detail',
              error: true,
            );
          }
        }
        return;
      }
      await _guardSend(() async {
        await _service.sendAudio(
          conversationId: _requireReadyConversationId(),
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          durationSec: durationSec,
        );
      });
    } catch (e) {
      _showToast('录音发送失败：${friendlyErrorText(e)}');
    }
  }

  Future<void> _cancelHoldRecordInternal({required bool showHint}) async {
    if (!_recording) return;
    _recordTicker?.cancel();
    setState(() {
      _recording = false;
      _recordHoldAction = VoiceHoldAction.none;
      _recordFocalPoint = null;
      _recordDurationMs = 0;
    });
    try {
      await NativeAudioRecorder.instance.cancel();
    } catch (_) {}
    if (showHint) _showToast('已取消发送');
  }

  void _onRecordMove(LongPressMoveUpdateDetails details) {
    if (!_recording) return;
    final action = resolveVoiceHoldAction(
      details.globalPosition,
      MediaQuery.sizeOf(context),
      transcribeEnabled: !isDesktopCommOnly,
    );
    setState(() {
      _recordHoldAction = action;
      _recordFocalPoint = details.globalPosition;
    });
  }

  void _beginDownload(String fileKey) {
    if (!mounted) return;
    _activeDownloadCancel = ChatUploadCancelToken();
    setState(() {
      _downloadingFileKey = fileKey.isEmpty ? '__download__' : fileKey;
      _downloadProgress = 0;
    });
  }

  void _setDownloadProgress(double progress) {
    if (!mounted) return;
    setState(() {
      _downloadProgress = progress.clamp(0.0, 1.0);
    });
  }

  void _endDownload() {
    if (_activeDownloadCancel != null) {
      _activeDownloadCancel = null;
    }
    if (!mounted) return;
    setState(() {
      _downloadingFileKey = null;
      _downloadProgress = 0;
    });
  }

  void _cancelPendingDownload() {
    _activeDownloadCancel?.cancel();
  }

  bool get _downloadingMedia => _downloadingFileKey != null;

  double? _downloadProgressFor(Map<String, dynamic>? payload) {
    final key = _downloadingFileKey;
    if (key == null) return null;
    final fileKey = _fileCacheKey(payload);
    if (fileKey.isEmpty) {
      return key == '__download__'
          ? (_downloadProgress <= 0 ? 0.01 : _downloadProgress)
          : null;
    }
    if (fileKey != key) return null;
    return _downloadProgress <= 0 ? 0.01 : _downloadProgress;
  }

  VoidCallback? _downloadCancelFor(Map<String, dynamic>? payload) {
    if (_downloadProgressFor(payload) == null) return null;
    return _cancelPendingDownload;
  }

  void _beginUpload(
    String label, {
    Uint8List? previewBytes,
    String kind = '',
    String fileName = '',
    int videoDurationSec = 0,
    int? videoWidth,
    int? videoHeight,
  }) {
    if (!mounted) return;
    setState(() {
      _uploadLabel = label;
      _uploadProgress = 0;
      _pendingUploadBytes = previewBytes;
      _pendingUploadKind = kind.toUpperCase();
      _pendingUploadName = fileName;
      _pendingVideoDurationSec = videoDurationSec;
      _pendingVideoWidth = videoWidth;
      _pendingVideoHeight = videoHeight;
    });
  }

  void _setUploadProgress(double progress, {String? label}) {
    if (!mounted) return;
    setState(() {
      _uploadProgress = progress.clamp(0.0, 1.0);
      if (label != null) _uploadLabel = label;
    });
  }

  void _cancelPendingUpload() {
    _activeUploadCancel?.cancel();
    final conversationId =
        _conversation?.id ?? widget.conversationHint?.id ?? 0;
    if (conversationId > 0) {
      ChatFileUploadCoordinator.instance.cancelForConversation(conversationId);
    }
  }

  Future<void> _guardSend(
    Future<void> Function() task, {
    ChatUploadCancelToken? cancelToken,
    bool ensureCurrentConversation = true,
  }) async {
    _activeUploadCancel = cancelToken;
    setState(() => _uploading = true);
    try {
      if (ensureCurrentConversation && (_conversation?.id ?? 0) <= 0) {
        final ready = await _ensureConversationReadyForSend();
        if (ready == null || ready.id <= 0) {
          throw Exception('会话未就绪');
        }
      }
      await task();
      if (!mounted) return;
      // 与普通文本发送一致：退出定位态，回到最新消息端并贴底。
      setState(() {
        _locatedMode = false;
        _hasNewer = false;
        _forceLatestMode = true;
        _enterStickBottomPending = true;
        _awayFromLatest = false;
      });
      await _load(silent: true);
      if (!mounted) return;
      setState(_clearPendingNewMessages);
      _scrollToPreferredAnchor(force: true);
    } on ChatUploadCancelledException {
      if (mounted) _showToast('已取消上传');
    } catch (e) {
      if (cancelToken?.isCancelled == true) {
        if (mounted) _showToast('已取消上传');
      } else {
        _showToast('发送失败：${friendlyErrorText(e)}');
      }
    } finally {
      if (_activeUploadCancel == cancelToken) {
        _activeUploadCancel = null;
      }
      if (mounted) {
        setState(() {
          _uploading = false;
          _uploadLabel = null;
          _uploadProgress = 0;
          _pendingUploadBytes = null;
          _pendingUploadKind = '';
          _pendingUploadName = '';
          _pendingVideoDurationSec = 0;
          _pendingVideoWidth = null;
          _pendingVideoHeight = null;
        });
      }
    }
  }

  int _requireReadyConversationId() {
    final id = _conversation?.id ?? 0;
    if (id <= 0) throw Exception('会话未就绪');
    return id;
  }

  Widget _buildPendingUploadBubble() {
    final progress = _uploadProgress;
    final kind = _pendingUploadKind;
    final name = _pendingUploadName.isNotEmpty
        ? _pendingUploadName
        : (_uploadLabel ?? '上传中');
    final bytes = _pendingUploadBytes;
    if (kind == 'VIDEO') {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: ChatVideoBubble(
            mine: true,
            thumbnailBytes: bytes,
            durationSec: _pendingVideoDurationSec,
            width: _pendingVideoWidth,
            height: _pendingVideoHeight,
            uploadProgress: progress <= 0 ? 0.01 : progress,
            onTap: () {},
            onCancelUpload: _cancelPendingUpload,
          ),
        ),
      );
    }
    if (kind == 'IMAGE' && bytes != null && bytes.isNotEmpty) {
      final box = chatImageBubbleMaxSize(context);
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: box.width * 0.72,
              height: box.width * 0.72,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(bytes, fit: BoxFit.cover),
                  Container(color: Colors.black45),
                  Center(
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        value: progress > 0 && progress < 1 ? progress : null,
                        strokeWidth: 3,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _cancelPendingUpload,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (progress > 0)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Text(
                        '${(progress * 100).round()}%',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: ChatFileAttach(
          fileName: name,
          mine: true,
          fileSizeBytes: bytes?.length,
          onTap: () {},
          uploadProgress: progress <= 0 ? 0.01 : progress,
          onCancelUpload: _cancelPendingUpload,
        ),
      ),
    );
  }

  Future<void> _tryRecallMessage(NativeChatMessage m) async {
    final conv = _conversation;
    if (conv == null || m.id <= 0 || m.senderUserId != widget.session.userId)
      return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('撤回消息'),
        content: const Text('确认撤回这条消息吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('撤回'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.recallMessage(conversationId: conv.id, messageId: m.id);
      await _load(silent: true);
      _restoreRecalledTextToComposer(m);
    } catch (e) {
      _showToast('撤回失败：${friendlyErrorText(e)}');
    }
  }

  /// 撤回成功后保留发送前的文本，用户可以修改后重新发送。
  /// 只对文本消息恢复，图片/文件/语音没有可编辑的文本草稿。
  void _restoreRecalledTextToComposer(NativeChatMessage message) {
    if (message.kind.trim().toUpperCase() != 'TEXT') return;
    final text = message.bodyText;
    if (text.trim().isEmpty || !mounted) return;
    if (_inputController.text.trim().isNotEmpty) {
      _showToast('消息已撤回，输入框已有内容，未覆盖现有草稿');
      return;
    }
    _inputController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _lastComposeText = text;
    _persistComposeDraft(flush: true);
    _inputFocusNode.requestFocus();
  }

  Future<void> _showReadReceipts(NativeChatMessage m) async {
    final conv = _conversation;
    if (conv == null || m.id <= 0) return;
    try {
      final members = _groupMembers.isNotEmpty
          ? _groupMembers
          : await _service.fetchConversationMembers(conv.id);
      if (_groupMembers.isEmpty) _groupMembers = members;
      final statusRows = await _service.fetchGroupReadStatus(conv.id);
      final receiptRows = await _service.fetchMessageReadReceipts(
        conversationId: conv.id,
        messageId: m.id,
      );
      final reads = <int, int>{};
      for (final row in statusRows) {
        final uid = (row['userId'] as num?)?.toInt() ?? 0;
        final lastRead =
            (row['lastReadMessageId'] as num?)?.toInt() ??
            (row['readMessageId'] as num?)?.toInt() ??
            (row['lastRead'] as num?)?.toInt() ??
            0;
        if (uid > 0 && uid != widget.session.userId && lastRead > 0) {
          reads[uid] = lastRead;
        }
      }
      for (final row in receiptRows) {
        final uid = (row['userId'] as num?)?.toInt() ?? 0;
        final lastRead =
            (row['lastReadMessageId'] as num?)?.toInt() ??
            (row['readMessageId'] as num?)?.toInt() ??
            (row['lastRead'] as num?)?.toInt() ??
            m.id;
        if (uid > 0 && uid != widget.session.userId && lastRead > 0) {
          final prev = reads[uid] ?? 0;
          if (lastRead > prev) reads[uid] = lastRead;
        }
      }
      if (reads.isNotEmpty && mounted) {
        setState(() => _groupReadMap = Map<int, int>.from(reads));
      }
      final readRows = <_GroupReadPerson>[];
      final unreadRows = <_GroupReadPerson>[];
      for (final member in members) {
        final uid = (member['userId'] as num?)?.toInt() ?? 0;
        if (uid <= 0 || uid == widget.session.userId) continue;
        final person = _GroupReadPerson(
          uid: uid,
          name: (member['displayName'] ?? member['name'] ?? '用户$uid')
              .toString(),
          sub: _memberDeptTitle(member),
          avatarPreset: _memberAvatarPreset(member),
          avatarObjectKey: _memberAvatarObjectKey(member),
        );
        if ((reads[uid] ?? 0) >= m.id) {
          readRows.add(person);
        } else {
          unreadRows.add(person);
        }
      }
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) {
          return _GroupReadSheet(
            readRows: readRows,
            unreadRows: unreadRows,
            avatarService: _service,
          );
        },
      );
    } catch (e) {
      _showToast('读取已读明细失败：${friendlyErrorText(e)}');
    }
  }

  String _memberDeptTitle(Map<String, dynamic> member) {
    final parts = <String>[];
    final dept = (member['department'] ?? member['departmentName'] ?? '')
        .toString()
        .trim();
    final title =
        (member['title'] ?? member['roleLabel'] ?? member['role'] ?? '')
            .toString()
            .trim();
    if (dept.isNotEmpty) parts.add(dept);
    if (title.isNotEmpty) parts.add(title);
    return parts.join(' · ');
  }

  Future<void> _onMessageActions(
    NativeChatMessage m,
    bool mine, {
    Offset? anchor,
    String? selectedText,
  }) async {
    if (_isSystemKind(m.kind)) return;
    if (_messageActionsMenuOpen) return;
    _messageActionsMenuOpen = true;
    try {
      final selection = (selectedText ?? '').trim();
      final copyText = selection.isNotEmpty ? selection : _messageCopyText(m);
      final kind = m.kind.toUpperCase();
      final isFile = kind == 'FILE';
      final isImage = kind == 'IMAGE';
      final isAudio = kind == 'AUDIO';
      final desktop = isDesktopCommOnly;
      final attachmentName = _mediaDownloadFileName(m);
      final fileDownloaded =
          isFile && _isFileDownloaded(m.payload, attachmentName);
      final canSaveFileToKb =
          (isFile || isImage || isAudio) &&
          chatFileSupportsKbUpload(attachmentName, m.payload);
      if (isFile) {
        await _ensureDriveSavedKnown(m.payload);
      }
      final driveSaved = isFile && _isDriveSaved(m.payload);
      final actions = <_MessageQuickAction>[
        if (desktop && isFile) ...[
          const _MessageQuickAction(
            id: 'open_file',
            label: '打开',
            icon: Icons.open_in_new_rounded,
          ),
          const _MessageQuickAction(
            id: 'reveal_file',
            label: '打开文件夹',
            icon: Icons.folder_open_rounded,
          ),
        ],
        if (desktop && isImage) ...[
          const _MessageQuickAction(
            id: 'popup_preview',
            label: '弹框预览',
            icon: Icons.photo_size_select_large_outlined,
          ),
          const _MessageQuickAction(
            id: 'reveal_file',
            label: '打开文件夹',
            icon: Icons.folder_open_rounded,
          ),
        ],
        if (isAudio)
          const _MessageQuickAction(
            id: 'transcribe',
            label: '转文字',
            icon: Icons.text_fields_rounded,
          ),
        const _MessageQuickAction(
          id: 'quote',
          label: '引用',
          icon: Icons.format_quote_outlined,
        ),
        const _MessageQuickAction(
          id: 'forward',
          label: '转发',
          icon: Icons.shortcut_rounded,
        ),
        if (m.id > 0)
          const _MessageQuickAction(
            id: 'favorite',
            label: '收藏',
            icon: Icons.bookmark_border_rounded,
          ),
        if (m.id > 0)
          _MessageQuickAction(
            id: _isMessagePinned(m.id) ? 'unpin' : 'pin',
            label: _isMessagePinned(m.id) ? '取消置顶' : '置顶',
            icon: _isMessagePinned(m.id)
                ? Icons.push_pin_outlined
                : Icons.push_pin_rounded,
          ),
        if (canSaveFileToKb)
          const _MessageQuickAction(
            id: 'save_to_kb',
            label: '存入知识库',
            icon: Icons.cloud_upload_outlined,
          ),
        if (isFile)
          _MessageQuickAction(
            id: 'save_to_drive',
            label: driveSaved ? '再次存入微盘' : '存入微盘',
            icon: driveSaved
                ? Icons.folder_copy_outlined
                : Icons.folder_shared_outlined,
          ),
        if (isImage || copyText.isNotEmpty)
          const _MessageQuickAction(
            id: 'copy',
            label: '复制',
            icon: Icons.copy_rounded,
          ),
        if (isFile && fileDownloaded)
          const _MessageQuickAction(
            id: 'redownload',
            label: '重新下载',
            icon: Icons.refresh_rounded,
          )
        else if (_canDownloadMessage(m))
          const _MessageQuickAction(
            id: 'download',
            label: '下载',
            icon: Icons.download_rounded,
          ),
        if (_canSelectMessageForMulti(m))
          const _MessageQuickAction(
            id: 'multi_msg',
            label: '多选',
            icon: Icons.checklist_rounded,
          ),
        if (mine && m.id > 0)
          const _MessageQuickAction(
            id: 'recall',
            label: '撤回',
            icon: Icons.undo_rounded,
          ),
      ];
      final action = await _showMessageActionsMenu(actions, anchor: anchor);
      switch (action) {
        case 'popup_preview':
          await _openChatImagePopupPreview(m);
          break;
        case 'open_file':
          await _openFileAttachment(m.payload, attachmentName);
          break;
        case 'reveal_file':
          await _revealFileOnDesktop(m.payload, attachmentName);
          break;
        case 'transcribe':
          await _transcribeVoiceMessage(m);
          break;
        case 'quote':
          if (selection.isNotEmpty) {
            _quoteFromSelectedText(m, selection);
          } else {
            _startQuote(m);
          }
          break;
        case 'forward':
          if (selection.isNotEmpty) {
            _forwardFromSelectedText(m, selection);
          } else {
            _forwardMessage(m);
          }
          break;
        case 'favorite':
          await _favoriteMessage(m);
          break;
        case 'pin':
          await _pinMessage(m);
          break;
        case 'unpin':
          await _unpinMessage(m.id);
          break;
        case 'save_to_kb':
          await _saveChatAttachmentToKb(m.payload, attachmentName);
          break;
        case 'save_to_drive':
          await _saveChatAttachmentToDrive(m.payload, attachmentName);
          break;
        case 'copy':
          if (selection.isEmpty && isImage) {
            await _copyMessageImage(m);
          } else if (selection.isEmpty && isFile && desktop) {
            await _copyMessageFile(m);
          } else {
            await _copyMessageText(copyText);
          }
          break;
        case 'download':
          await _downloadFile(m.payload, attachmentName);
          break;
        case 'redownload':
          await _redownloadFile(m.payload, attachmentName);
          break;
        case 'multi_msg':
          if (selection.isNotEmpty) {
            _multiFromSelectedText(m, selection);
          } else {
            _enterMessageMultiSelect(initialMessageId: m.id);
          }
          break;
        case 'recall':
          await _tryRecallMessage(m);
          break;
      }
    } finally {
      _messageActionsMenuOpen = false;
    }
  }

  Future<String?> _showMessageActionsMenu(
    List<_MessageQuickAction> actions, {
    Offset? anchor,
  }) async {
    if (actions.isEmpty) return null;
    return showGeneralDialog<String>(
      context: context,
      barrierLabel: 'message_actions',
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, _, _) {
        final media = MediaQuery.of(ctx);
        final size = media.size;
        final safeTop = media.padding.top + 8;
        final safeBottom = size.height - media.padding.bottom - 8;
        final menuWidth = math.min(size.width - 24, 324.0).toDouble();
        final left =
            (anchor == null
                    ? (size.width - menuWidth) / 2
                    : (anchor.dx - menuWidth / 2).clamp(
                        12.0,
                        size.width - menuWidth - 12,
                      ))
                .toDouble();
        final preferredTop = anchor == null
            ? size.height * 0.35
            : anchor.dy - 136;
        final top = preferredTop
            .clamp(safeTop, math.max(safeTop, safeBottom - 190))
            .toDouble();
        return SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                child: Material(
                  color: const Color(0xF0303030),
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: menuWidth),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 8,
                        children: actions
                            .map(
                              (item) => SizedBox(
                                width: 54,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => Navigator.of(ctx).pop(item.id),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          item.icon,
                                          size: 19,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          item.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: DunesTypography.sans(
                                            fontSize: 11,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curve),
            child: child,
          ),
        );
      },
    );
  }

  void _startQuote(NativeChatMessage message, {String? excerpt}) {
    final selected = excerpt?.trim() ?? '';
    final full = ChatMessageQuote.fromMessage(message);
    final useExcerpt =
        selected.isNotEmpty && selected != message.bodyText.trim();
    setState(() {
      _quoteDraft = useExcerpt
          ? ChatMessageQuote(
              messageId: full.messageId,
              senderUserId: full.senderUserId,
              senderName: full.senderName,
              kind: full.kind,
              bodyText: selected,
              preview: selected.length > 80
                  ? '${selected.substring(0, 80)}…'
                  : selected,
            )
          : full;
      _voiceMode = false;
      _emojiOpen = false;
    });
    _inputFocusNode.requestFocus();
  }

  void _closeEmojiPicker() {
    if (!_emojiOpen) return;
    setState(() => _emojiOpen = false);
  }

  Widget _buildMultiSelectHeader() {
    final selectedCount = _multiSelectedMessageIds.length;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: _exitMessageMultiSelect,
            child: const Text('取消'),
          ),
          Expanded(
            child: Center(
              child: Text(
                selectedCount > 0 ? '已选择 $selectedCount 条消息' : '多选消息',
                style: DunesTypography.sans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: selectedCount > 0 ? _forwardSelectedMessages : null,
            child: const Text('转发'),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiSelectBottomBar() {
    final selectedCount = _multiSelectedMessageIds.length;
    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        6,
        8,
        (MediaQuery.paddingOf(context).bottom > 0
                ? MediaQuery.paddingOf(context).bottom
                : 8) +
            2,
      ),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _multiBarAction(
            icon: Icons.reply_outlined,
            label: '转发',
            enabled: selectedCount > 0,
            onTap: _forwardSelectedMessages,
          ),
          _multiBarAction(
            icon: Icons.more_horiz_rounded,
            label: '更多',
            enabled: true,
            onTap: _showMultiMoreActions,
          ),
        ],
      ),
    );
  }

  Widget _multiBarAction({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: enabled ? DunesColors.text2 : DunesColors.text3,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: DunesTypography.sans(
                fontSize: 11,
                color: enabled ? DunesColors.text2 : DunesColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMultiMoreActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_all_rounded),
              title: const Text('复制'),
              onTap: () => Navigator.of(context).pop('copy'),
            ),
            ListTile(
              leading: const Icon(Icons.clear_all_rounded),
              title: const Text('清空选择'),
              onTap: () => Navigator.of(context).pop('clear'),
            ),
            ListTile(
              leading: const Icon(Icons.done_rounded),
              title: const Text('完成'),
              onTap: () => Navigator.of(context).pop('done'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'copy':
        await _copySelectedMessages();
        break;
      case 'clear':
        if (mounted) setState(_multiSelectedMessageIds.clear);
        break;
      case 'done':
        _exitMessageMultiSelect();
        break;
    }
  }

  Widget _buildComposerDock({required bool locked, required String inputHint}) {
    final wide = isWideChatLayout(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_uploadLabel != null) _buildPendingUploadBubble(),
        // PC：工具栏常显在输入区上方；APP：点「+」后在下方展开宫格。
        if (wide)
          ChatQuickActions(
            onCamera: locked || _mediaBusy
                ? () {}
                : () => _sendImageFrom(ImageSource.camera, '拍照'),
            onCameraLongPress: locked || _mediaBusy
                ? null
                : _recordAndSendVideo,
            onAlbum: locked || _mediaBusy ? () {} : _sendMultiImagesFromGallery,
            onScreenshot: !isDesktopCommOnly || locked || _mediaBusy
                ? null
                : _desktopScreenshotAndSend,
            onFile: locked || _mediaBusy ? () {} : _sendFile,
            onApproval: locked || _mediaBusy
                ? () {}
                : () => unawaited(_forwardApprovalToChat()),
            onAt: locked ? null : _pickAtMember,
            onEmoji: locked ? null : _toggleEmojiPicker,
            onVideo: locked || _mediaBusy ? () {} : _pickAndSendVideo,
            showAt: !_isPrivate,
            showVideo: true,
          ),
        if (_quoteDraft != null && !_quoteDraft!.isEmpty && !locked)
          ChatQuotePreviewBar(quote: _quoteDraft!, onCancel: _clearQuoteDraft),
        if (_useDesktopAttachmentStaging &&
            _desktopComposerAttachments.isNotEmpty)
          _buildDesktopAttachmentTray(),
        ValueListenableBuilder<bool>(
          valueListenable: MeetingLiveController.instance.active,
          builder: (context, meetingLive, _) {
            // 录音能力仅移动端可用；Chrome/桌面仍显示语音按钮，点击时提示。
            final voiceSupported =
                !kIsWeb &&
                defaultTargetPlatform != TargetPlatform.windows &&
                defaultTargetPlatform != TargetPlatform.macOS;
            final voiceBlocked = !voiceSupported || locked || meetingLive;
            final effectiveVoiceMode = voiceBlocked ? false : _voiceMode;
            // PC 不展示语音入口；APP 始终展示（不支持时点按提示）。
            final showVoice = wide ? voiceSupported : true;
            return ChatInputBar(
              controller: _inputController,
              focusNode: _inputFocusNode,
              onInputFocused: () {
                if (!wide && _toolsOpen) setState(() => _toolsOpen = false);
                _scrollToLatestAfterKeyboard();
              },
              inputHeight: wide ? _pcInputHeight : null,
              onInputHeightDrag: wide
                  ? (deltaDy) {
                      setState(() {
                        _pcInputHeight = (_pcInputHeight - deltaDy).clamp(
                          _pcInputHeightMin,
                          _pcInputHeightMax,
                        );
                      });
                    }
                  : null,
              voiceMode: effectiveVoiceMode,
              voiceEnabled: showVoice,
              sending: _sending,
              enabled: !locked,
              hintText: inputHint,
              onAttemptPasteImage: locked ? null : _attemptPasteImage,
              onToggleVoice: () {
                if (!wide && _toolsOpen) setState(() => _toolsOpen = false);
                if (meetingLive) {
                  _showToast('会议录音进行中，暂无法发送语音');
                  return;
                }
                if (!voiceSupported) {
                  _showToast('当前环境不支持录音');
                  return;
                }
                if (locked) return;
                setState(() {
                  _voiceMode = !_voiceMode;
                  _emojiOpen = false;
                });
              },
              onSend: () {
                _send();
              },
              onPlus: wide || locked || _mediaBusy
                  ? null
                  : () => setState(() {
                      _toolsOpen = !_toolsOpen;
                      if (_toolsOpen) {
                        _emojiOpen = false;
                        FocusScope.of(context).unfocus();
                      }
                    }),
              plusOpen: _toolsOpen,
              onEmoji: locked
                  ? null
                  : () {
                      if (!wide) setState(() => _toolsOpen = false);
                      _toggleEmojiPicker();
                    },
              recording: _recording,
              recordWillCancel: _recordWillCancel,
              recordWillTranscribe: _recordWillTranscribe,
              recordDurationMs: _recordDurationMs,
              onVoiceHoldStart: voiceBlocked
                  ? null
                  : (details) => _startHoldRecord(details.globalPosition),
              onVoiceHoldMove: _onRecordMove,
              onVoiceHoldEnd: (_) => _finishHoldRecord(),
              onVoiceHoldCancel: () =>
                  _cancelHoldRecordInternal(showHint: false),
            );
          },
        ),
        // APP：微信式工具宫格在输入栏下方展开。
        if (!wide && _toolsOpen && !locked)
          ChatQuickActions(
            onCamera: locked || _mediaBusy
                ? () {}
                : () => _sendImageFrom(ImageSource.camera, '拍照'),
            onCameraLongPress: locked || _mediaBusy
                ? null
                : _recordAndSendVideo,
            onAlbum: locked || _mediaBusy ? () {} : _sendMultiImagesFromGallery,
            onFile: locked || _mediaBusy ? () {} : _sendFile,
            onApproval: locked || _mediaBusy
                ? () {}
                : () => unawaited(_forwardApprovalToChat()),
            onAt: locked ? null : _pickAtMember,
            onVideo: null,
            showAt: !_isPrivate,
            showVideo: false,
          ),
        if (_emojiOpen && !locked)
          ChatEmojiGifPanel(controller: _inputController),
      ],
    );
  }

  Widget _buildDesktopAttachmentTray() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(top: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: SizedBox(
        height: 66,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _desktopComposerAttachments.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final attachment = _desktopComposerAttachments[index];
            return SizedBox(
              width: attachment.isImage ? 66 : 150,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: DunesColors.borderSoft),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: attachment.isImage
                            ? Image.memory(
                                attachment.bytes,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Row(
                                  children: [
                                    ChatFileTypeIcon(
                                      fileName: attachment.fileName,
                                      size: 34,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        attachment.fileName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: DunesTypography.sans(
                                          fontSize: 11,
                                          color: DunesColors.text2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Material(
                      color: const Color(0xFF625B6D),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sending
                            ? null
                            : () =>
                                  _removeDesktopComposerAttachment(attachment),
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _clearQuoteDraft() {
    if (_quoteDraft == null) return;
    setState(() => _quoteDraft = null);
  }

  String _messageCopyText(NativeChatMessage message) {
    if (message.kind.toUpperCase() == 'TEXT') {
      return message.bodyText.trim();
    }
    if (message.kind.toUpperCase() == 'AUDIO') {
      final key = _voiceAsrKey(messageId: message.id, payload: message.payload);
      final transcript = VoiceAsrStore.instance.textFor(key);
      if (transcript != null && transcript.isNotEmpty) return transcript;
    }
    return ChatMessageQuote.previewForMessage(message);
  }

  /// 图片消息复制：优先用会话里已缓存的预览图，立刻可粘贴；系统剪贴板后台刷新。
  Future<void> _copyMessageImage(NativeChatMessage message) async {
    try {
      final payload = message.payload;
      final preview = ConversationService.previewMediaPayload(payload);
      Uint8List bytes;
      try {
        bytes = await _service.loadCachedChatMediaBytesWithFallback(
          previewPayload: preview,
          originalPayload: payload,
        );
      } catch (_) {
        bytes = await _service.loadFullImageBytes(payload);
      }
      if (bytes.isEmpty) {
        if (mounted) _showToast('图片为空', error: true);
        return;
      }
      final name = ConversationService.mediaFileName(
        payload,
        fallback: 'image.jpg',
      );
      ChatFileClipboard.clear();
      await ChatImageClipboard.write(bytes, fileName: name);
      if (mounted) _showToast('已复制图片');
    } catch (_) {
      if (mounted) _showToast('复制失败，请重试', error: true);
    }
  }

  /// PC：文件消息复制到系统剪贴板，可在会话输入框粘贴发出。
  Future<void> _copyMessageFile(NativeChatMessage message) async {
    try {
      final payload = message.payload;
      final fileName = _mediaDownloadFileName(message);
      final cacheKey = _fileCacheKey(payload);
      final cachedPath = await file_dl.findCachedChatFile(
        cacheKey,
        fileName,
        conversationId: _chatConversationId,
      );
      if (cachedPath != null && cachedPath.trim().isNotEmpty) {
        await ChatFileClipboard.writePath(
          cachedPath.trim(),
          fileName: fileName,
        );
        if (mounted) _showToast('已复制文件');
        return;
      }
      final bytes = await _service.loadCachedChatMediaBytes(payload);
      if (bytes.isEmpty) {
        if (mounted) _showToast('文件为空', error: true);
        return;
      }
      await ChatFileClipboard.write(bytes, fileName: fileName);
      if (mounted) _showToast('已复制文件');
    } catch (e) {
      if (mounted) {
        _showToast('复制失败：${friendlyErrorText(e)}', error: true);
      }
    }
  }

  Future<void> _copyMessageText(String text) async {
    final value = text.trim();
    if (value.isEmpty) {
      _showToast('暂无可复制内容');
      return;
    }
    try {
      // 复制文字后清掉图片/文件备份，避免下次粘贴仍发出旧附件。
      ChatImageClipboard.clear();
      ChatFileClipboard.clear();
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) _showToast('已复制');
    } catch (_) {
      if (mounted) _showToast('复制失败，请重试', error: true);
    }
  }

  bool _isRobotMarkdownPayload(Map<String, dynamic>? payload) {
    final value = payload?['robotMarkdown'];
    return value == true || value.toString().toLowerCase() == 'true';
  }

  void _quoteFromSelectedText(NativeChatMessage message, String selectedText) {
    _startQuote(message, excerpt: selectedText);
  }

  bool _canSelectMessageForMulti(NativeChatMessage message) {
    if (message.id <= 0) return false;
    return !_isSystemKind(message.kind);
  }

  Future<void> _favoriteMessage(NativeChatMessage message) async {
    final convId = _conversation?.id ?? widget.conversationHint?.id ?? 0;
    if (convId <= 0 || message.id <= 0) {
      _showToast('收藏失败：会话无效', error: true);
      return;
    }
    if (_isSystemKind(message.kind)) {
      _showToast('该消息无法收藏', error: true);
      return;
    }
    try {
      await _service.favoriteMessage(convId, message.id);
      if (!mounted) return;
      _showToast('已收藏');
    } catch (e) {
      if (!mounted) return;
      _showToast('收藏失败：${friendlyErrorText(e)}', error: true);
    }
  }

  bool _isMessagePinned(int messageId) {
    if (messageId <= 0) return false;
    return _pinnedMessages.any((p) => p.messageId == messageId);
  }

  Future<void> _refreshPinnedMessages() async {
    final convId = _conversation?.id ?? 0;
    if (convId <= 0) return;
    try {
      final items = await _service.fetchPinnedMessages(convId);
      if (!mounted || (_conversation?.id ?? 0) != convId) return;
      setState(() {
        _pinnedMessages = items;
        if (items.length <= 1) _pinnedExpanded = false;
      });
    } catch (_) {
      // 置顶拉取失败不影响会话主流程。
    }
  }

  Future<void> _pinMessage(NativeChatMessage message) async {
    final convId = _conversation?.id ?? widget.conversationHint?.id ?? 0;
    if (convId <= 0) {
      _showToast('置顶失败：会话无效', error: true);
      return;
    }
    if (message.id <= 0 || _isSystemKind(message.kind)) {
      _showToast('该消息无法置顶', error: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('置顶消息'),
        content: const Text('确认置顶这条消息吗？置顶后会话内全员可见。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('置顶'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final items = await _service.pinMessage(convId, message.id);
      if (!mounted) return;
      setState(() {
        _pinnedMessages = items;
        if (items.length <= 1) _pinnedExpanded = false;
      });
      _showToast('已置顶');
    } catch (e) {
      if (!mounted) return;
      _showToast('置顶失败：${friendlyErrorText(e)}', error: true);
    }
  }

  Future<void> _unpinMessage(int messageId) async {
    final convId = _conversation?.id ?? widget.conversationHint?.id ?? 0;
    if (convId <= 0 || messageId <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('取消置顶'),
        content: const Text('确认取消这条置顶消息吗？取消后会话内全员不再看到该置顶。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('取消置顶'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final items = await _service.unpinMessage(convId, messageId);
      if (!mounted) return;
      setState(() {
        _pinnedMessages = items;
        if (items.length <= 1) _pinnedExpanded = false;
      });
      _showToast('已取消置顶');
    } catch (e) {
      if (!mounted) return;
      _showToast('取消置顶失败：${friendlyErrorText(e)}', error: true);
    }
  }

  Future<void> _jumpToPinnedMessage(NativePinnedMessage pin) async {
    if (pin.messageId <= 0) {
      _showToast('无法定位到原消息');
      return;
    }
    await _jumpToQuotedMessage(
      pin.messageId,
      quote: ChatMessageQuote(
        messageId: pin.messageId,
        senderUserId: pin.senderUserId ?? 0,
        senderName: pin.senderName,
        kind: pin.kind,
        bodyText: pin.bodyText,
        preview: pin.previewText.isNotEmpty ? pin.previewText : pin.bodyText,
      ),
    );
  }

  void _forwardMessage(NativeChatMessage message) {
    final units = _forwardUnitsFromMessages(<NativeChatMessage>[message]);
    if (units.isEmpty) {
      _showToast('暂无可转发内容');
      return;
    }
    unawaited(_startForwardFlow(units, fromMultiSelect: false));
  }

  void _setMessageMultiSelectMode(
    bool enabled, {
    int? initialMessageId,
    bool clearSelection = false,
  }) {
    if (!mounted) return;
    final keepPixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : null;
    setState(() {
      _messageMultiSelectMode = enabled;
      if (enabled) {
        if (initialMessageId != null && initialMessageId > 0) {
          _multiSelectedMessageIds.add(initialMessageId);
        }
      } else {
        _multiSelectedMessageIds.clear();
      }
      if (clearSelection) {
        _multiSelectedMessageIds.clear();
      }
    });
    if (keepPixels != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final pos = _scrollController.position;
        final target = keepPixels.clamp(0.0, pos.maxScrollExtent);
        if ((pos.pixels - target).abs() > 0.5) {
          _scrollController.jumpTo(target);
        }
      });
    }
  }

  void _enterMessageMultiSelect({int? initialMessageId}) {
    _setMessageMultiSelectMode(true, initialMessageId: initialMessageId);
  }

  void _exitMessageMultiSelect() {
    _setMessageMultiSelectMode(false, clearSelection: true);
  }

  void _toggleMessageMultiSelected(int messageId) {
    if (messageId <= 0 || !mounted) return;
    setState(() {
      if (_multiSelectedMessageIds.contains(messageId)) {
        _multiSelectedMessageIds.remove(messageId);
      } else {
        _multiSelectedMessageIds.add(messageId);
      }
    });
  }

  List<NativeChatMessage> get _multiSelectedMessages {
    if (_multiSelectedMessageIds.isEmpty) return const <NativeChatMessage>[];
    final picked =
        _messages
            .where((m) => _multiSelectedMessageIds.contains(m.id))
            .toList(growable: false)
          ..sort((a, b) => a.id.compareTo(b.id));
    return picked;
  }

  String _messageForwardText(NativeChatMessage message) {
    if (message.kind.toUpperCase() == 'TEXT') return message.bodyText.trim();
    return ChatMessageQuote.previewForMessage(message);
  }

  void _forwardFromSelectedText(
    NativeChatMessage message,
    String selectedText,
  ) {
    final text = selectedText.trim();
    if (text.isEmpty) {
      _forwardMessage(message);
      return;
    }
    final unit = (
      senderName: message.senderName.trim().isEmpty
          ? '用户${message.senderUserId}'
          : message.senderName.trim(),
      timeLabel: InboxFormat.msgTimeLabel(message.createdAt),
      text: text,
      kind: 'TEXT',
      payload: null,
      avatarPreset: message.senderAvatarPreset,
      avatarObjectKey: message.senderAvatarObjectKey,
    );
    unawaited(_startForwardFlow(<_ForwardUnit>[unit], fromMultiSelect: false));
  }

  void _multiFromSelectedText(NativeChatMessage message, String selectedText) {
    if (!_canSelectMessageForMulti(message)) return;
    _enterMessageMultiSelect(initialMessageId: message.id);
  }

  List<_ForwardUnit> _forwardUnitsFromMessages(
    List<NativeChatMessage> messages,
  ) {
    return messages
        .map((m) {
          final text = _messageForwardText(m).trim();
          if (text.isEmpty) return null;
          final kind = m.kind.toUpperCase();
          Map<String, dynamic>? payload;
          if (m.payload != null && kind != 'TEXT') {
            payload = Map<String, dynamic>.from(m.payload!);
          } else if (_isRobotMarkdownPayload(m.payload)) {
            // 保留机器人 Markdown 标识，二次转发后仍按富文本消息渲染。
            payload = Map<String, dynamic>.from(m.payload!);
          } else if (m.payload?['forward'] is Map) {
            payload = <String, dynamic>{
              'forward': Map<String, dynamic>.from(
                m.payload!['forward'] as Map,
              ),
            };
          } else if (WeeklySummaryShare.fromPayload(m.payload) != null) {
            payload = Map<String, dynamic>.from(m.payload!);
          }
          return (
            senderName: m.senderName.trim().isEmpty
                ? '用户${m.senderUserId}'
                : m.senderName.trim(),
            timeLabel: InboxFormat.msgTimeLabel(m.createdAt),
            text: text,
            kind: kind,
            payload: payload,
            avatarPreset: m.senderAvatarPreset,
            avatarObjectKey: m.senderAvatarObjectKey,
          );
        })
        .whereType<_ForwardUnit>()
        .toList(growable: false);
  }

  Future<String?> _pickForwardMode() async {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          decoration: BoxDecoration(
            color: DunesColors.bgApp,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _forwardModeCard(
                      icon: Icons.splitscreen_outlined,
                      title: '逐条转发',
                      subtitle: '每条消息独立发送',
                      onTap: () => Navigator.of(context).pop('separate'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _forwardModeCard(
                      icon: Icons.view_agenda_outlined,
                      title: '合并转发',
                      subtitle: '打包为聊天记录卡片',
                      onTap: () => Navigator.of(context).pop('merged'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _forwardModeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: DunesColors.bgSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: DunesColors.accentDeep),
              const SizedBox(height: 8),
              Text(
                title,
                style: DunesTypography.sans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<int?> _pickForwardConversationId() async {
    final currentId = _conversation?.id ?? 0;
    return showConversationPickerSheet(
      context: context,
      service: _service,
      title: '选择会话',
      highlightConversationId: currentId > 0 ? currentId : null,
    );
  }

  Map<String, dynamic> _buildForwardPayload(List<_ForwardUnit> units) {
    final titleName =
        units.isNotEmpty && units.first.senderName.trim().isNotEmpty
        ? units.first.senderName.trim()
        : '聊天';
    return <String, dynamic>{
      'forward': <String, dynamic>{
        'title': '$titleName的聊天记录',
        'items': units
            .map(
              (u) => <String, dynamic>{
                'senderName': u.senderName,
                'timeLabel': u.timeLabel,
                'text': u.text,
                'kind': u.kind,
                'avatarPreset': u.avatarPreset,
                'avatarObjectKey': u.avatarObjectKey,
                if (u.payload != null) 'payload': u.payload,
              },
            )
            .toList(growable: false),
      },
    };
  }

  Future<void> _sendForwardToConversation({
    required int conversationId,
    required List<_ForwardUnit> units,
    required bool merged,
  }) async {
    if (conversationId <= 0 || units.isEmpty) return;
    await _guardSend(() async {
      if (merged) {
        await _service.sendText(
          conversationId,
          '[聊天记录]',
          payload: _buildForwardPayload(units),
        );
      } else {
        for (final unit in units) {
          final text = unit.text.trim();
          if (text.isEmpty) continue;
          final kind = unit.kind.trim().isEmpty ? 'TEXT' : unit.kind.trim();
          await _service.sendMessageRaw(
            conversationId: conversationId,
            kind: kind,
            bodyText: text,
            payload: unit.payload,
          );
        }
      }
    }, ensureCurrentConversation: false);
    if (_messageMultiSelectMode) _exitMessageMultiSelect();
    if (mounted) {
      _showToast('已转发${units.length}条');
      setState(_clearPendingNewMessages);
      _scrollToPreferredAnchor(force: true);
    }
  }

  Future<void> _startForwardFlow(
    List<_ForwardUnit> units, {
    required bool fromMultiSelect,
  }) async {
    if (units.isEmpty) {
      _showToast('请先选择消息');
      return;
    }
    final allWeekly = units.every(
      (u) => u.kind.toUpperCase() == 'WEEKLY_SUMMARY',
    );
    final mode = allWeekly ? 'separate' : await _pickForwardMode();
    if (mode == null) return;
    final targetConversationId = await _pickForwardConversationId();
    if (targetConversationId == null || targetConversationId <= 0) return;
    final merged = mode == 'merged';
    await _sendForwardToConversation(
      conversationId: targetConversationId,
      units: units,
      merged: merged,
    );
    if (fromMultiSelect && _messageMultiSelectMode) {
      _exitMessageMultiSelect();
    }
  }

  Future<void> _forwardSelectedMessages() async {
    final units = _forwardUnitsFromMessages(_multiSelectedMessages);
    await _startForwardFlow(units, fromMultiSelect: true);
  }

  Future<void> _copySelectedMessages() async {
    final selected = _multiSelectedMessages;
    if (selected.length == 1 && selected.first.kind.toUpperCase() == 'IMAGE') {
      await _copyMessageImage(selected.first);
      return;
    }
    final texts = selected
        .map(_messageForwardText)
        .where((e) => e.trim().isNotEmpty)
        .toList(growable: false);
    if (texts.isEmpty) {
      _showToast('请先选择消息');
      return;
    }
    ChatImageClipboard.clear();
    await Clipboard.setData(ClipboardData(text: texts.join('\n')));
    if (mounted) _showToast('已复制${texts.length}条消息');
  }

  NativeChatMessage? _quoteHintMessage(ChatMessageQuote quote) {
    if (quote.isEmpty) return null;
    return NativeChatMessage(
      id: quote.messageId,
      senderUserId: quote.senderUserId,
      senderName: quote.senderName,
      kind: quote.kind,
      bodyText: quote.bodyText,
      createdAt: null,
    );
  }

  Future<void> _jumpToQuotedMessage(
    int messageId, {
    ChatMessageQuote? quote,
  }) async {
    if (messageId <= 0) return;
    if (_messages.any((m) => m.id == messageId)) {
      final hasNewerLocal = _messages.any((m) => m.id > messageId);
      setState(() {
        _locatedMode = true;
        if (hasNewerLocal) _hasNewer = true;
      });
      _highlightAndScroll(messageId);
      return;
    }
    final conv = _conversation;
    if (conv == null || conv.id <= 0) {
      _showToast('找不到原消息');
      return;
    }
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final page = await _service.fetchMessagesAround(
        conv.id,
        messageId,
        hint: quote != null ? _quoteHintMessage(quote) : null,
      );
      if (!mounted) return;
      final msgs = _enrichMessages(page.items, conv)
        ..sort((a, b) => a.id.compareTo(b.id));
      if (!msgs.any((m) => m.id == messageId)) {
        setState(() => _locating = false);
        _showToast('找不到原消息');
        return;
      }
      setState(() {
        _messages = msgs;
        _hasMore = page.hasMore;
        _hasNewer = page.hasNewer;
        _locatedMode = true;
        _locating = false;
        if (page.peerLastReadMessageId != null) {
          _peerLastReadMessageId = page.peerLastReadMessageId!;
        }
      });
      _highlightAndScroll(messageId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _locating = false);
      _showToast('定位消息失败：${friendlyErrorText(e)}');
    }
  }

  Widget _wrapQuotedContent(NativeChatMessage m, bool mine, Widget child) {
    final quote = ChatMessageQuote.fromPayload(m.payload);
    if (quote.isEmpty) return child;
    return Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: ChatQuoteBlock(
            quote: quote,
            mine: mine,
            onTap: () => _jumpToQuotedMessage(quote.messageId, quote: quote),
          ),
        ),
      ],
    );
  }

  void _showToast(String message, {bool error = false}) {
    if (!mounted) return;
    showDunesToast(
      context,
      message,
      kind: error || dunesToastLooksLikeError(message)
          ? DunesToastKind.error
          : DunesToastKind.normal,
    );
  }

  Future<String> _resolveMediaUrl(String source) {
    if (_mediaUrlCache.containsKey(source)) return _mediaUrlCache[source]!;
    final future = _service.resolveMediaUrl(source);
    _mediaUrlCache[source] = future;
    return future;
  }

  String _voiceAsrKey({required int messageId, Map<String, dynamic>? payload}) {
    final objectKey = ConversationService.mediaObjectKey(payload).trim();
    if (objectKey.isNotEmpty) return 'ok:$objectKey';
    if (messageId > 0) return 'msg:$messageId';
    final url = ConversationService.mediaDirectUrl(payload).trim();
    if (url.isNotEmpty) return 'url:${url.hashCode}';
    return '';
  }

  Future<Uint8List> _loadVoiceBytes(NativeChatMessage m) async {
    if (ConversationService.hasAuthMedia(m.payload)) {
      return _service.loadCachedChatMediaBytes(m.payload);
    }
    final url = ConversationService.mediaDirectUrl(m.payload).trim();
    if (url.isEmpty) throw Exception('语音地址为空');
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('下载语音失败 HTTP ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  Future<void> _transcribeVoiceMessage(NativeChatMessage m) async {
    if (m.kind.toUpperCase() != 'AUDIO') return;
    final key = _voiceAsrKey(messageId: m.id, payload: m.payload);
    if (key.isEmpty) {
      _showToast('无法转写：语音文件缺失', error: true);
      return;
    }
    final existing = VoiceAsrStore.instance.textFor(key);
    if (existing != null && existing.trim().isNotEmpty) {
      // 已有转写结果：气泡下方已展示，无需再弹编辑发送面板。
      _showToast('已转写');
      return;
    }
    if (VoiceAsrStore.instance.isLoading(key)) {
      _showToast('正在转写…');
      return;
    }
    try {
      await VoiceAsrStore.instance.transcribe(
        key: key,
        request: () async {
          final bytes = await _loadVoiceBytes(m);
          return _service.transcribeVoice(
            bytes: bytes,
            fileName: _mediaDownloadFileName(m),
          );
        },
      );
      if (!mounted) return;
      // 已发送语音只在气泡下展示转写，不走「编辑/发送」草稿面板。
      _showToast('转写完成');
    } catch (e) {
      if (mounted) {
        final detail = friendlyErrorText(
          e,
          fallback: e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
        );
        _showToast(
          detail.startsWith('转写') || detail.startsWith('语音')
              ? detail
              : '转写失败：$detail',
          error: true,
        );
      }
    }
  }

  Future<void> _showVoiceTranscriptComposer(
    String transcript, {
    Uint8List? originalBytes,
    String? originalFilePath,
    Future<Uint8List> Function()? loadOriginal,
    required String fileName,
    required String mimeType,
    required int durationSec,
  }) async {
    if (!mounted || transcript.trim().isEmpty) return;
    // 打开转文字面板前先贴底，和聚焦输入框一样把最新消息顶起来。
    await _scrollToLatestForInput();
    if (!mounted) return;
    final result = await showVoiceTranscriptPanel(
      context: context,
      transcript: transcript,
      durationSec: durationSec,
      originalFilePath: originalFilePath,
      originalBytes: originalFilePath == null ? originalBytes : null,
      loadOriginalBytes: originalFilePath == null && originalBytes == null
          ? loadOriginal
          : null,
      fileName: fileName,
    );
    if (!mounted || result == null) return;
    if (result.action == VoiceTranscriptAction.text) {
      await _sendVoiceTranscriptText(result.text);
    } else {
      await _sendOriginalVoice(
        originalBytes: originalBytes,
        loadOriginal: loadOriginal,
        fileName: fileName,
        mimeType: mimeType,
        durationSec: durationSec,
      );
    }
  }

  Future<void> _sendVoiceTranscriptText(String text) async {
    final conv = _conversation;
    final value = text.trim();
    if (conv == null || value.isEmpty || conv.dissolved) return;
    await _guardSend(
      () => _service.sendText(_requireReadyConversationId(), value),
    );
  }

  Future<void> _sendOriginalVoice({
    Uint8List? originalBytes,
    Future<Uint8List> Function()? loadOriginal,
    required String fileName,
    required String mimeType,
    required int durationSec,
  }) async {
    final conv = _conversation;
    if (conv == null || conv.dissolved) return;
    await _guardSend(() async {
      final bytes = originalBytes ?? await loadOriginal!();
      await _service.sendAudio(
        conversationId: _requireReadyConversationId(),
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        durationSec: durationSec,
      );
    });
  }

  String _mediaSource(Map<String, dynamic>? payload) {
    if (payload == null) return '';
    final url = (payload['url'] ?? '').toString().trim();
    if (url.isNotEmpty) return url;
    return (payload['objectKey'] ?? '').toString().trim();
  }

  Future<void> _openMeetingMinutesShare(MeetingMinutesChatShare share) async {
    if (share.meetingId <= 0) {
      _showToast('会议纪要无效', error: true);
      return;
    }
    if (!mounted) return;
    await showNativeMeetingDetail(
      context: context,
      session: widget.session,
      meetingId: share.meetingId,
      summaryOnly: true,
    );
  }

  Future<void> _forwardApprovalToChat() async {
    final conv = _conversation;
    if (conv == null) {
      _showToast('会话未就绪', error: true);
      return;
    }
    final share = await showApprovalPickerSheet(
      context: context,
      session: widget.session,
    );
    if (share == null || !mounted) return;
    try {
      await _service.sendText(
        conv.id,
        share.bodyText,
        payload: share.toMessagePayload(),
      );
      if (mounted) _showToast('已转发审批');
    } catch (e) {
      if (mounted) {
        _showToast(
          '转发失败：${friendlyErrorText(e, fallback: '请稍后重试')}',
          error: true,
        );
      }
    }
  }

  void _openApprovalShare(ApprovalChatShare share) {
    final open = widget.onOpenApprovalShare;
    if (open != null) {
      open(share);
      return;
    }
    _showToast('无法打开审批详情', error: true);
  }

  String _approvalStatusLabel(String status) {
    return detailStatusLabel(status);
  }

  Future<void> _openKbDocShare(KbChatDocShare share) async {
    final docId = share.openDocId;
    if (docId.isEmpty) {
      _showToast('文档无效，无法打开', error: true);
      return;
    }
    try {
      final kb = NativeKbService(session: widget.session);
      final downloaded = await kb.downloadDocumentBytes(
        docId: docId,
        hint: share.toDocument(),
      );
      final fileName = downloaded.fileName.trim().isNotEmpty
          ? downloaded.fileName.trim()
          : (share.fileName.trim().isNotEmpty
                ? share.fileName.trim()
                : share.title);
      final cacheKey = 'kb-forward-$docId';
      final localPath = await file_dl.saveBytesAsCachedFile(
        downloaded.bytes,
        cacheKey,
        fileName,
        conversationId: _chatConversationId,
      );
      if (!mounted) return;
      if (localPath == null || localPath.isEmpty) {
        _showToast('保存文件失败', error: true);
        return;
      }
      final payload = <String, dynamic>{
        'fileName': fileName,
        'mimeType': lookupMimeType(fileName) ?? 'application/octet-stream',
        'size': downloaded.bytes.length,
        ...share.toMessagePayload(),
      };
      await _openKbFileAttachment(
        payload,
        fileName,
        initialLocalPath: localPath,
      );
    } catch (e) {
      if (!mounted) return;
      _showToast(friendlyErrorText(e, fallback: '打开失败，请重新转发该文档'), error: true);
    }
  }

  /// 知识库文件：PDF 预览；其它进 IM 文件详情页（下载 / 用其他应用打开）。
  Future<void> _openKbFileAttachment(
    Map<String, dynamic>? payload,
    String fileName, {
    String? initialLocalPath,
  }) async {
    if (chatPayloadIsPdf(payload, fileName)) {
      await showChatPdfPreview(
        context: context,
        service: _service,
        payload: payload,
        fileName: fileName,
        saveToKbSession: widget.session,
        saveToDriveSession: widget.session,
      );
      return;
    }
    if (!mounted) return;
    await showChatFilePreview(
      context: context,
      service: _service,
      payload: payload,
      fileName: fileName,
      conversationId: _chatConversationId,
      initialLocalPath: initialLocalPath,
      saveToKbSession: widget.session,
      saveToDriveSession: widget.session,
      onDownloaded: () {
        final key = _downloadedKey(payload, fileName);
        if (key.isEmpty || !mounted) return;
        setState(() => _downloadedFileKeys.add(key));
      },
    );
  }

  Future<void> _openFileAttachment(
    Map<String, dynamic>? payload,
    String fileName,
  ) async {
    final kbSession = chatFileSupportsKbUpload(fileName, payload)
        ? widget.session
        : null;
    // PC 上 PDF 与 Excel/Word 等文件保持一致：下载后交给系统默认应用打开，
    // 不再使用应用内 PDF 弹框；移动端仍保留内置预览。
    if (isDesktopCommOnly) {
      await _openOrDownloadFileOnDesktop(payload, fileName);
      return;
    }
    if (chatPayloadIsPdf(payload, fileName)) {
      await showChatPdfPreview(
        context: context,
        service: _service,
        payload: payload,
        fileName: fileName,
        saveToKbSession: kbSession,
        saveToDriveSession: widget.session,
      );
      return;
    }
    // APP：微信式文件页，用其他应用打开。
    if (!mounted) return;
    await showChatFilePreview(
      context: context,
      service: _service,
      payload: payload,
      fileName: fileName,
      conversationId: _chatConversationId,
      saveToKbSession: kbSession,
      saveToDriveSession: widget.session,
      onDownloaded: () {
        final key = _downloadedKey(payload, fileName);
        if (key.isEmpty || !mounted) return;
        setState(() => _downloadedFileKeys.add(key));
      },
    );
  }

  /// 将会话附件存入微盘（可选空间与文件夹）。
  Future<void> _saveChatAttachmentToDrive(
    Map<String, dynamic>? payload,
    String fileName,
  ) async {
    if (_downloadingMedia) {
      _showToast('正在处理，请稍候…');
      return;
    }
    final pick = await pickDriveSaveLocation(
      context: context,
      session: widget.session,
      fileName: fileName,
    );
    if (pick == null || !mounted) return;

    final cacheKey = _fileCacheKey(payload);
    _beginDownload(cacheKey);
    try {
      List<int> bytes;
      if (ConversationService.hasAuthMedia(payload)) {
        bytes = await _service.loadChatMediaBytes(
          payload,
          onProgress: _setDownloadProgress,
          cancelToken: _activeDownloadCancel,
        );
      } else {
        final path = await _saveAttachmentToDisk(
          payload,
          fileName,
          cacheKey: cacheKey,
        );
        if (path == null || path.isEmpty) {
          throw Exception('无法读取文件内容');
        }
        bytes = await XFile(path).readAsBytes();
        _markFileDownloaded(payload, fileName);
      }
      if (bytes.isEmpty) throw Exception('文件内容为空');
      if (!mounted) return;
      final mimeType = (payload?['mimeType'] ?? '').toString().trim();
      final sourceKey = cacheKey;
      final ok = await uploadBytesToDriveLocation(
        context: context,
        session: widget.session,
        location: pick,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType.isEmpty ? null : mimeType,
        sourceKey: sourceKey,
      );
      if (ok && sourceKey.isNotEmpty && mounted) {
        setState(() => _driveSavedFileKeys.add(sourceKey));
      }
    } on ChatDownloadCancelledException {
      if (mounted) _showToast('已取消下载');
    } catch (e) {
      if (_activeDownloadCancel?.isCancelled == true) {
        if (mounted) _showToast('已取消下载');
      } else if (mounted) {
        _showToast(friendlyErrorText(e, fallback: '存入微盘失败，请稍后重试'), error: true);
      }
    } finally {
      _endDownload();
    }
  }

  bool _isDriveSaved(Map<String, dynamic>? payload) {
    final key = _fileCacheKey(payload);
    return key.isNotEmpty && _driveSavedFileKeys.contains(key);
  }

  Future<void> _ensureDriveSavedKnown(Map<String, dynamic>? payload) async {
    final key = _fileCacheKey(payload);
    if (key.isEmpty || _driveSavedFileKeys.contains(key)) return;
    final saved = await isChatFileSavedToDrive(
      session: widget.session,
      sourceKey: key,
    );
    if (!saved || !mounted) return;
    setState(() => _driveSavedFileKeys.add(key));
  }

  /// 将会话附件存入当前用户知识库（文档 / 图片 / 语音等）。
  Future<void> _saveChatAttachmentToKb(
    Map<String, dynamic>? payload,
    String fileName,
  ) async {
    if (!chatFileSupportsKbUpload(fileName, payload)) {
      _showToast('仅支持 $kChatKbUploadSupportLabel', error: true);
      return;
    }
    if (_downloadingMedia) {
      _showToast('正在处理，请稍候…');
      return;
    }
    final title = fileName.trim().isNotEmpty ? fileName.trim() : '文档';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('存入我的知识库'),
        content: Text(
          '将把「$title」存入你的知识库，上传后可检索引用。\n\n是否继续？',
          style: DunesTypography.sans(fontSize: 14, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认存入'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final cacheKey = _fileCacheKey(payload);
    _beginDownload(cacheKey);
    try {
      List<int> bytes;
      if (ConversationService.hasAuthMedia(payload)) {
        bytes = await _service.loadChatMediaBytes(
          payload,
          onProgress: _setDownloadProgress,
          cancelToken: _activeDownloadCancel,
        );
      } else {
        final path = await _saveAttachmentToDisk(
          payload,
          fileName,
          cacheKey: cacheKey,
        );
        if (path == null || path.isEmpty) {
          throw Exception('无法读取文件内容');
        }
        bytes = await XFile(path).readAsBytes();
        _markFileDownloaded(payload, fileName);
      }
      if (bytes.isEmpty) throw Exception('文件内容为空');
      final kb = NativeKbService(session: widget.session);
      await kb.uploadDocument(bytes: bytes, fileName: fileName, title: title);
      KbDocumentCoordinator.instance.notifyChanged();
      if (!mounted) return;
      _showToast('已存入你的知识库，正在后台解析入库');
    } on ChatDownloadCancelledException {
      if (mounted) _showToast('已取消下载');
    } catch (e) {
      if (_activeDownloadCancel?.isCancelled == true) {
        if (mounted) _showToast('已取消下载');
      } else if (mounted) {
        _showToast(
          friendlyErrorText(e, fallback: '存入知识库失败，请稍后重试'),
          error: true,
        );
      }
    } finally {
      _endDownload();
    }
  }

  String _fileCacheKey(Map<String, dynamic>? payload) {
    if (payload == null) return '';
    final objectKey = (payload['objectKey'] ?? '').toString().trim();
    if (objectKey.isNotEmpty) return objectKey;
    return ConversationService.mediaDirectUrl(payload);
  }

  String _downloadedKey(Map<String, dynamic>? payload, String fileName) {
    final cacheKey = _fileCacheKey(payload);
    if (cacheKey.isNotEmpty) return cacheKey;
    return fileName.trim();
  }

  bool _isFileDownloaded(Map<String, dynamic>? payload, String fileName) {
    final key = _downloadedKey(payload, fileName);
    return key.isNotEmpty && _downloadedFileKeys.contains(key);
  }

  int? get _chatConversationId {
    final id = _conversation?.id ?? 0;
    return id > 0 ? id : null;
  }

  Future<void> _refreshDownloadedFileFlags() async {
    if (kIsWeb) return;
    final conversationId = _chatConversationId;
    final next = <String>{};
    for (final m in _messages) {
      if (m.kind.toUpperCase() != 'FILE') continue;
      final fileName = _mediaDownloadFileName(m);
      final cacheKey = _fileCacheKey(m.payload);
      final cached = await file_dl.findCachedChatFile(
        cacheKey,
        fileName,
        conversationId: conversationId,
      );
      if (cached != null && cached.isNotEmpty) {
        final key = _downloadedKey(m.payload, fileName);
        if (key.isNotEmpty) next.add(key);
      }
    }
    if (!mounted) return;
    final changed =
        next.length != _downloadedFileKeys.length ||
        !next.containsAll(_downloadedFileKeys);
    if (!changed) return;
    setState(() {
      _downloadedFileKeys
        ..clear()
        ..addAll(next);
    });
  }

  void _markFileDownloaded(Map<String, dynamic>? payload, String fileName) {
    final key = _downloadedKey(payload, fileName);
    if (key.isEmpty) return;
    if (_downloadedFileKeys.contains(key)) return;
    if (!mounted) {
      _downloadedFileKeys.add(key);
      return;
    }
    setState(() => _downloadedFileKeys.add(key));
  }

  Future<void> _openOrDownloadFileOnDesktop(
    Map<String, dynamic>? payload,
    String fileName,
  ) async {
    final cacheKey = _fileCacheKey(payload);
    final conversationId = _chatConversationId;
    if (cacheKey.isNotEmpty || conversationId != null) {
      final cached = await file_dl.findCachedChatFile(
        cacheKey,
        fileName,
        conversationId: conversationId,
      );
      if (cached != null && cached.isNotEmpty) {
        try {
          await file_dl.openLocalFile(cached);
          _markFileDownloaded(payload, fileName);
          return;
        } catch (_) {
          // 缓存损坏或关联应用失败时重新下载。
        }
      }
    }
    if (_downloadingMedia) {
      _showToast('正在下载，请稍候…');
      return;
    }
    _beginDownload(cacheKey);
    try {
      final savedPath = await _saveAttachmentToDisk(
        payload,
        fileName,
        cacheKey: cacheKey,
      );
      if (!mounted) return;
      if (savedPath == null || savedPath.isEmpty) {
        _showToast('文件已保存，但无法自动打开');
        return;
      }
      _markFileDownloaded(payload, fileName);
      try {
        await file_dl.openLocalFile(savedPath);
      } catch (e) {
        // 已下载成功但系统没有关联应用时，引导用户手动打开。
        if (!mounted) return;
        _showToast('已下载到本地，请用其他应用打开');
        try {
          await file_dl.revealLocalFile(savedPath);
        } catch (_) {}
      }
    } on ChatDownloadCancelledException {
      if (mounted) _showToast('已取消下载');
    } catch (e) {
      if (_activeDownloadCancel?.isCancelled == true) {
        if (mounted) _showToast('已取消下载');
      } else {
        _showToast('打开失败：${friendlyErrorText(e)}', error: true);
      }
    } finally {
      _endDownload();
    }
  }

  /// PC：确保本地有文件后，在资源管理器 / Finder 中选中显示。
  Future<void> _revealFileOnDesktop(
    Map<String, dynamic>? payload,
    String fileName,
  ) async {
    final cacheKey = _fileCacheKey(payload);
    final conversationId = _chatConversationId;
    String? path;
    if (cacheKey.isNotEmpty || conversationId != null) {
      path = await file_dl.findCachedChatFile(
        cacheKey,
        fileName,
        conversationId: conversationId,
      );
    }
    if (path == null || path.isEmpty) {
      if (_downloadingMedia) {
        _showToast('正在下载，请稍候…');
        return;
      }
      _beginDownload(cacheKey);
      try {
        path = await _saveAttachmentToDisk(
          payload,
          fileName,
          cacheKey: cacheKey,
        );
      } on ChatDownloadCancelledException {
        if (mounted) _showToast('已取消下载');
        return;
      } catch (e) {
        if (_activeDownloadCancel?.isCancelled == true) {
          if (mounted) _showToast('已取消下载');
        } else {
          _showToast('下载失败：${friendlyErrorText(e)}', error: true);
        }
        return;
      } finally {
        _endDownload();
      }
    }
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      _showToast('文件未找到', error: true);
      return;
    }
    try {
      await file_dl.revealLocalFile(path);
    } catch (e) {
      _showToast('无法打开文件夹：${friendlyErrorText(e)}', error: true);
    }
  }

  /// PC：拖到桌面 / Finder 前确保本地有一份文件（复制，不删缓存）。
  Future<String?> _resolveChatAttachmentPathForDrag(
    Map<String, dynamic>? payload,
    String fileName,
  ) async {
    if (kIsWeb || !isDesktopCommOnly || payload == null) return null;
    final cacheKey = _fileCacheKey(payload);
    final conversationId = _chatConversationId;
    try {
      final cached = await file_dl.findCachedChatFile(
        cacheKey,
        fileName,
        conversationId: conversationId,
      );
      if (cached != null && cached.isNotEmpty) return cached;
      if (ConversationService.hasAuthMedia(payload)) {
        final bytes = await _service.loadChatMediaBytes(payload);
        if (bytes.isEmpty) return null;
        final path = await file_dl.saveBytesAsCachedFile(
          bytes,
          cacheKey,
          fileName,
          conversationId: conversationId,
        );
        if (path != null && path.isNotEmpty) {
          _markFileDownloaded(payload, fileName);
        }
        return path;
      }
      final url = ConversationService.mediaDirectUrl(payload);
      if (url.isEmpty) return null;
      final path = await file_dl.openUrlAsFile(
        url,
        fileName,
        cacheKey: cacheKey.isEmpty ? null : cacheKey,
        conversationId: conversationId,
      );
      if (path != null && path.isNotEmpty) {
        _markFileDownloaded(payload, fileName);
      }
      return path;
    } catch (_) {
      return null;
    }
  }

  Widget _wrapDesktopFileDrag({
    required Map<String, dynamic>? payload,
    required String fileName,
    required Widget child,
    bool enabled = true,
  }) {
    if (!isDesktopCommOnly || !enabled || _messageMultiSelectMode) {
      return child;
    }
    return ChatDesktopFileDrag(
      fileName: fileName,
      resolveLocalPath: () =>
          _resolveChatAttachmentPathForDrag(payload, fileName),
      child: child,
    );
  }

  Future<String?> _saveAttachmentToDisk(
    Map<String, dynamic>? payload,
    String fileName, {
    String cacheKey = '',
  }) async {
    final conversationId = _chatConversationId;
    final cancel = _activeDownloadCancel;
    if (ConversationService.hasAuthMedia(payload)) {
      final bytes = await _service.loadChatMediaBytes(
        payload,
        onProgress: _setDownloadProgress,
        cancelToken: cancel,
      );
      if (cacheKey.isNotEmpty || conversationId != null) {
        return file_dl.saveBytesAsCachedFile(
          bytes,
          cacheKey,
          fileName,
          conversationId: conversationId,
        );
      }
      return file_dl.saveBytesAsFile(bytes, fileName);
    }
    final url = ConversationService.mediaDirectUrl(payload);
    if (url.isEmpty) {
      throw Exception('附件地址为空');
    }
    return file_dl.openUrlAsFile(
      url,
      fileName,
      onProgress: _setDownloadProgress,
      cacheKey: cacheKey.isEmpty ? null : cacheKey,
      conversationId: conversationId,
      cancelToken: cancel,
    );
  }

  Future<bool> _confirmFileDownload(
    String fileName, {
    Map<String, dynamic>? payload,
  }) async {
    final sizeHint = _fileSizeHint(payload);
    final detail = sizeHint == null ? fileName : '$fileName\n$sizeHint';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载文件'),
        content: Text(
          '确定要下载以下文件吗？\n\n$detail',
          style: DunesTypography.sans(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('下载'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  String? _fileSizeHint(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final size = payload['size'];
    if (size is! num || size <= 0) return null;
    final bytes = size.toInt();
    if (bytes < 1024) return '大小：$bytes B';
    if (bytes < 1024 * 1024) {
      return '大小：${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '大小：${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _downloadFile(
    Map<String, dynamic>? payload,
    String fileName, {
    bool force = false,
    bool showSuccessDialog = true,
  }) async {
    if (_downloadingMedia) {
      _showToast('正在下载，请稍候…');
      return;
    }
    final cacheKey = _fileCacheKey(payload);
    _beginDownload(cacheKey);
    try {
      if (force) {
        await file_dl.deleteCachedChatFile(
          cacheKey,
          fileName,
          conversationId: _chatConversationId,
        );
      }
      final savedPath = await _saveAttachmentToDisk(
        payload,
        fileName,
        cacheKey: cacheKey,
      );
      if (!mounted) return;
      _markFileDownloaded(payload, fileName);
      if (savedPath == null || savedPath.isEmpty) {
        _showToast('已保存 $fileName');
        return;
      }
      if (showSuccessDialog) {
        _showDownloadSuccessDialog(savedPath, fileName);
      } else {
        _showToast(force ? '已重新下载 $fileName' : '已保存 $fileName');
      }
    } on ChatDownloadCancelledException {
      if (mounted) _showToast('已取消下载');
    } catch (e) {
      if (_activeDownloadCancel?.isCancelled == true) {
        if (mounted) _showToast('已取消下载');
      } else {
        _showToast('下载失败：${friendlyErrorText(e)}', error: true);
      }
    } finally {
      _endDownload();
    }
  }

  Future<void> _redownloadFile(
    Map<String, dynamic>? payload,
    String fileName,
  ) async {
    await _downloadFile(
      payload,
      fileName,
      force: true,
      showSuccessDialog: !isDesktopCommOnly,
    );
  }

  String _formatSavedPath(String path) {
    return path.replaceFirst('/storage/emulated/0', '内部存储');
  }

  void _showDownloadSuccessDialog(String savedPath, String fileName) {
    if (!mounted) return;
    final displayPath = _formatSavedPath(savedPath);
    final desktop = isDesktopCommOnly;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('下载完成'),
        content: Text('文件：$fileName\n保存位置：\n$displayPath'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
          if (desktop) ...[
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await file_dl.revealLocalFile(savedPath);
                } catch (e) {
                  if (!mounted) return;
                  _showToast('无法打开文件夹：${friendlyErrorText(e)}', error: true);
                }
              },
              child: const Text('打开文件夹'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await file_dl.openLocalFile(savedPath);
                } catch (e) {
                  if (!mounted) return;
                  _showToast('打开失败：${friendlyErrorText(e)}', error: true);
                }
              },
              child: const Text('打开'),
            ),
          ],
        ],
      ),
    );
  }

  /// PC/手机：打开会话图片图集预览，可左右切换同会话其他图片。
  Future<void> _openChatImageGallery(NativeChatMessage current) async {
    final items = <ChatImagePreviewItem>[];
    var initialIndex = 0;
    for (final m in _messages) {
      if (m.kind.toUpperCase() != 'IMAGE' || m.payload == null) continue;
      if (m.id == current.id) initialIndex = items.length;
      items.add(
        ChatImagePreviewItem(
          payload: m.payload,
          fileName: ConversationService.mediaFileName(
            m.payload,
            fallback: 'image-${m.id}.jpg',
          ),
          messageId: m.id,
        ),
      );
    }
    if (items.isEmpty && current.payload != null) {
      items.add(
        ChatImagePreviewItem(
          payload: current.payload,
          fileName: ConversationService.mediaFileName(
            current.payload,
            fallback: 'image.jpg',
          ),
          messageId: current.id,
        ),
      );
    }
    if (items.isEmpty || !mounted) return;
    await showChatImagePreview(
      context,
      service: _service,
      items: items,
      initialIndex: initialIndex,
      conversationId: _chatConversationId,
    );
  }

  Future<void> _openChatImagePopupPreview(NativeChatMessage current) async {
    if (!mounted || current.payload == null) return;
    await showChatImagePopupPreview(
      context,
      service: _service,
      payload: current.payload,
      fileName: ConversationService.mediaFileName(
        current.payload,
        fallback: 'image-${current.id}.jpg',
      ),
      conversationId: _chatConversationId,
    );
  }

  String _mediaDownloadFileName(NativeChatMessage m) {
    final payload = m.payload;
    final fromPayload = ConversationService.mediaFileName(payload);
    if (fromPayload.isNotEmpty && fromPayload != 'download') return fromPayload;
    final kind = m.kind.toUpperCase();
    if (kind == 'AUDIO') return 'voice-${m.id}.m4a';
    if (kind == 'FILE') {
      final stripped = m.bodyText
          .replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '')
          .trim();
      if (stripped.isNotEmpty) return stripped;
      return 'file-${m.id}';
    }
    if (kind == 'IMAGE') return 'image-${m.id}.jpg';
    return 'download';
  }

  bool _canDownloadMessage(NativeChatMessage m) {
    final kind = m.kind.toUpperCase();
    if (kind != 'FILE' &&
        kind != 'AUDIO' &&
        kind != 'IMAGE' &&
        kind != 'VIDEO') {
      return false;
    }
    final payload = m.payload;
    if (payload == null) return false;
    return ConversationService.hasAuthMedia(payload) ||
        ConversationService.mediaDirectUrl(payload).isNotEmpty;
  }

  Map<int, ({String? preset, String? objectKey})> get _memberAvatarMap =>
      _service.avatarMapFromMembers(_groupMembers);

  List<NativeChatMessage> _enrichMessages(
    List<NativeChatMessage> msgs, [
    NativeConversation? conv,
  ]) {
    final c = conv ?? _conversation;
    return _service.enrichMessagesWithAvatars(
      msgs,
      avatarByUserId: _memberAvatarMap,
      peerAvatarPreset: c?.peerAvatarPreset,
      peerAvatarObjectKey: c?.peerAvatarObjectKey,
      peerUserId: c?.peerUserId,
      selfUserId: widget.session.userId,
      selfAvatarPreset: _selfAvatarPreset,
      selfAvatarObjectKey: _selfAvatarObjectKey,
    );
  }

  ImUserAvatar _avatarForMessage(NativeChatMessage m, {required bool mine}) {
    final conv = _conversation;
    if (mine) {
      final self = widget.session.displayName?.trim();
      final initial = self != null && self.isNotEmpty
          ? self.substring(0, 1)
          : '我';
      return ImUserAvatar(
        initial: initial,
        seed: widget.session.userId,
        size: 45,
        avatarPreset: m.senderAvatarPreset ?? _selfAvatarPreset,
        avatarObjectKey: m.senderAvatarObjectKey ?? _selfAvatarObjectKey,
        avatarUrl: _selfAvatarUrl,
        avatarService: _service,
        borderRadius: 45 * 0.18,
      );
    }
    final name = m.senderName.isNotEmpty
        ? m.senderName
        : (conv?.displayTitle ?? '?');
    final seed = m.senderUserId > 0
        ? m.senderUserId
        : (conv?.peerUserId ?? conv?.id ?? 0);
    final memberAvatars = !_isPrivate && m.senderUserId > 0
        ? _memberAvatarMap[m.senderUserId]
        : null;
    // 群聊的 peerAvatar 只是会话列表里随便取的一名成员，不能回退到消息头像，
    // 否则未设置头像的成员会错用别人的预设/自定义头像。
    final usePeerFallback =
        _isPrivate &&
        (conv?.peerUserId == null ||
            conv!.peerUserId! <= 0 ||
            m.senderUserId == conv.peerUserId);
    final preset =
        m.senderAvatarPreset ??
        memberAvatars?.preset ??
        (usePeerFallback ? conv?.peerAvatarPreset : null);
    final objectKey =
        m.senderAvatarObjectKey ??
        memberAvatars?.objectKey ??
        (usePeerFallback ? conv?.peerAvatarObjectKey : null);
    return ImUserAvatar(
      initial: name.isNotEmpty ? name.substring(0, 1) : '?',
      seed: seed,
      size: 45,
      showOnline: false,
      avatarPreset: preset,
      avatarObjectKey: objectKey,
      avatarService: _service,
      borderRadius: 45 * 0.18,
    );
  }

  Widget _tappableAvatarForMessage(NativeChatMessage m, {required bool mine}) {
    final avatar = _avatarForMessage(m, mine: mine);
    final onOpen = widget.onOpenUser;
    if (onOpen == null && (mine || _messageMultiSelectMode)) return avatar;

    final conv = _conversation;
    final userId = mine
        ? widget.session.userId
        : (m.senderUserId > 0
              ? m.senderUserId
              : (conv?.peerUserId ?? widget.peerUserIdHint ?? 0));
    if (userId <= 0) return avatar;

    final name = mine
        ? (widget.session.displayName?.trim().isNotEmpty == true
              ? widget.session.displayName!.trim()
              : '我')
        : (m.senderName.isNotEmpty ? m.senderName : (conv?.displayTitle ?? ''));
    final canAt =
        !mine &&
        !_isPrivate &&
        !_messageMultiSelectMode &&
        _conversation?.dissolved != true &&
        name.trim().isNotEmpty;
    return GestureDetector(
      onTap: onOpen == null ? null : () => onOpen(userId, name),
      // 只响应对方头像：私聊插入姓名，群聊插入 @姓名；保留点击头像打开资料。
      onLongPress: canAt && !isDesktopCommOnly
          ? () => unawaited(_insertAvatarTarget(name, userId: userId))
          : null,
      onSecondaryTapDown: canAt && isDesktopCommOnly
          ? (details) => unawaited(
              _onAvatarContextMenu(
                details.globalPosition,
                name: name,
                userId: userId,
              ),
            )
          : null,
      behavior: HitTestBehavior.opaque,
      child: avatar,
    );
  }

  Future<void> _onAvatarContextMenu(
    Offset global, {
    required String name,
    required int userId,
  }) async {
    if (!mounted || _isPrivate || _messageMultiSelectMode) return;
    final overlay = Overlay.of(context).context.findRenderObject();
    if (overlay is! RenderBox) return;
    final atLabel = '@${name.trim()}';
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(global.dx, global.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(value: 'at', child: Text(atLabel)),
        if (widget.onOpenUser != null)
          const PopupMenuItem<String>(value: 'profile', child: Text('查看资料')),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'at') {
      await _insertAvatarTarget(name, userId: userId);
      return;
    }
    if (action == 'profile') {
      widget.onOpenUser?.call(userId, name);
    }
  }

  Future<void> _insertAvatarTarget(String rawName, {int userId = 0}) async {
    if (_messageMultiSelectMode || _conversation?.dissolved == true) return;
    var name = rawName.trim();
    if (!_isPrivate && userId > 0) {
      for (final member in _groupMembers) {
        final memberId = (member['userId'] as num?)?.toInt() ?? 0;
        if (memberId != userId) continue;
        final canonical = (member['displayName'] ?? member['name'] ?? '')
            .toString()
            .trim();
        if (canonical.isNotEmpty) name = canonical;
        break;
      }
    }
    if (name.isEmpty) return;
    final current = _inputController.text.trimRight();
    final prefix = current.isEmpty ? '' : '$current ';
    final value = '$prefix${_isPrivate ? name : '@$name'} ';
    _insertingAtMentions = !_isPrivate;
    _inputController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _insertingAtMentions = false;
    _closeEmojiPicker();
    if (!_voiceMode) {
      _inputFocusNode.requestFocus();
    } else if (mounted) {
      setState(() => _voiceMode = false);
      _inputFocusNode.requestFocus();
    }
  }

  bool _isSystemKind(String kind) {
    final k = kind.toUpperCase();
    return k == 'SYSTEM' ||
        k.startsWith('SYSTEM_') ||
        k == 'MESSAGE_RECALLED' ||
        k == 'RECALL';
  }

  Widget _buildMessageWidget(NativeChatMessage m, bool mine) {
    final kind = m.kind.toUpperCase();
    if (_isSystemKind(kind)) {
      return ChatSystemPill(text: m.bodyText.isEmpty ? '[系统消息]' : m.bodyText);
    }
    final forward = _forwardBundleFromPayload(m.payload);
    if (forward != null) {
      return _buildForwardRecordCard(forward, mine: mine);
    }
    final weekly = WeeklySummaryShare.fromPayload(m.payload);
    if (weekly != null) {
      return GestureDetector(
        onTap: () => unawaited(
          showWeeklySummaryDetailSheet(
            context: context,
            session: widget.session,
            data: weekly,
          ),
        ),
        onSecondaryTapDown: isDesktopCommOnly && !_messageMultiSelectMode
            ? (details) =>
                  _onMessageActions(m, mine, anchor: details.globalPosition)
            : null,
        onLongPress: _messageMultiSelectMode
            ? null
            : () => _onMessageActions(m, mine),
        child: WeeklySummaryPoster(data: weekly, compact: true),
      );
    }
    final meetingShare = MeetingMinutesChatShare.fromPayload(m.payload);
    if (meetingShare != null) {
      return ChatMeetingMinutesCard(
        title: meetingShare.title,
        onTap: () => unawaited(_openMeetingMinutesShare(meetingShare)),
        onSecondaryTapDown: isDesktopCommOnly && !_messageMultiSelectMode
            ? (details) =>
                  _onMessageActions(m, mine, anchor: details.globalPosition)
            : null,
      );
    }
    final approvalShare = ApprovalChatShare.fromPayload(m.payload);
    if (approvalShare != null) {
      return ChatApprovalCard(
        title: approvalShare.title,
        statusLabel: _approvalStatusLabel(approvalShare.status),
        subtitle: approvalShare.businessType.toUpperCase() == 'PROPOSAL'
            ? '销售提案'
            : '审批单据',
        onTap: () => _openApprovalShare(approvalShare),
        onSecondaryTapDown: isDesktopCommOnly && !_messageMultiSelectMode
            ? (details) =>
                  _onMessageActions(m, mine, anchor: details.globalPosition)
            : null,
      );
    }
    final kbDoc = KbChatDocShare.fromPayload(m.payload);
    if (kbDoc != null && kind == 'TEXT') {
      // 旧版仅发卡片未带附件：尽量走文件详情；失败再提示。
      return ChatKbDocCard(
        title: kbDoc.title,
        typeLabel: kbDoc.typeLabel,
        sizeLabel: kbDoc.sizeLabel,
        onTap: () => unawaited(_openKbDocShare(kbDoc)),
        onSecondaryTapDown: isDesktopCommOnly && !_messageMultiSelectMode
            ? (details) =>
                  _onMessageActions(m, mine, anchor: details.globalPosition)
            : null,
      );
    }
    final quote = ChatMessageQuote.fromPayload(m.payload);
    final onQuoteTap = quote.isEmpty
        ? null
        : () => _jumpToQuotedMessage(quote.messageId, quote: quote);
    if (kind == 'IMAGE') {
      final imageName = ConversationService.mediaFileName(
        m.payload,
        fallback: 'image-${m.id}.jpg',
      );
      return _wrapQuotedContent(
        m,
        mine,
        _wrapDesktopFileDrag(
          payload: m.payload,
          fileName: imageName,
          child: ChatAuthImageBubble(
            service: _service,
            payload: m.payload,
            mine: mine,
            conversationId: _chatConversationId,
            onTap: () => unawaited(_openChatImageGallery(m)),
          ),
        ),
      );
    }
    if (kind == 'VIDEO') {
      final videoName = ConversationService.mediaFileName(
        m.payload,
        fallback: 'video-${m.id}.mp4',
      );
      return _wrapQuotedContent(
        m,
        mine,
        _wrapDesktopFileDrag(
          payload: m.payload,
          fileName: videoName,
          enabled: _downloadProgressFor(m.payload) == null,
          child: ChatAuthVideoBubble(
            service: _service,
            payload: m.payload,
            mine: mine,
            downloadProgress: _downloadProgressFor(m.payload),
            onCancelDownload: _downloadCancelFor(m.payload),
            onTap: () => unawaited(_openChatVideo(m.payload)),
          ),
        ),
      );
    }
    if (kind == 'FILE') {
      final fileName = ConversationService.mediaFileName(
        m.payload,
        fallback: m.bodyText.isEmpty
            ? '文件'
            : m.bodyText.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), ''),
      );
      final kbDoc = KbChatDocShare.fromPayload(m.payload);
      if (kbDoc != null) {
        return _wrapQuotedContent(
          m,
          mine,
          _wrapDesktopFileDrag(
            payload: m.payload,
            fileName: fileName,
            child: ChatKbDocCard(
              title: kbDoc.title.isNotEmpty ? kbDoc.title : fileName,
              typeLabel: kbDoc.typeLabel,
              sizeLabel: kbDoc.sizeLabel.isNotEmpty
                  ? kbDoc.sizeLabel
                  : _fileSizeHint(m.payload) ?? '',
              onTap: () =>
                  unawaited(_openKbFileAttachment(m.payload, fileName)),
              onSecondaryTapDown: isDesktopCommOnly && !_messageMultiSelectMode
                  ? (details) => _onMessageActions(
                      m,
                      mine,
                      anchor: details.globalPosition,
                    )
                  : null,
            ),
          ),
        );
      }
      // meetingMinutes already handled above for any kind.
      return _wrapQuotedContent(
        m,
        mine,
        _wrapDesktopFileDrag(
          payload: m.payload,
          fileName: fileName,
          enabled: _downloadProgressFor(m.payload) == null,
          child: ChatFileAttach(
            fileName: fileName,
            mine: mine,
            fileSizeBytes: (m.payload?['size'] as num?)?.toInt(),
            downloaded: _isFileDownloaded(m.payload, fileName),
            downloadProgress: _downloadProgressFor(m.payload),
            onCancelDownload: _downloadCancelFor(m.payload),
            onTap: () => _openFileAttachment(m.payload, fileName),
            onSecondaryTapDown: isDesktopCommOnly && !_messageMultiSelectMode
                ? (details) =>
                      _onMessageActions(m, mine, anchor: details.globalPosition)
                : null,
          ),
        ),
      );
    }
    if (kind == 'AUDIO') {
      final sec = (m.payload?['durationSec'] as num?)?.toInt() ?? 0;
      final source = _mediaSource(m.payload);
      return _wrapQuotedContent(
        m,
        mine,
        ChatVoiceBubble(
          playKey: 'msg-${m.id}',
          durationSec: sec,
          mine: mine,
          asrKey: _voiceAsrKey(messageId: m.id, payload: m.payload),
          resolveUrl: () => _resolveMediaUrl(source),
          onPlayError: (message) => _showToast(message, error: true),
        ),
      );
    }
    if (_isRobotMarkdownPayload(m.payload)) {
      final wide = isWideChatLayout(context);
      final screenW = MediaQuery.sizeOf(context).width;
      final preferredMax = wide
          ? (screenW * 0.55).clamp(420.0, 640.0)
          : (screenW - 72).clamp(260.0, 420.0);
      return LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;
          final maxW = available.isFinite && available > 0
              ? (available < preferredMax ? available : preferredMax)
              : preferredMax;
          return Align(
            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: maxW,
              clipBehavior: Clip.hardEdge,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: mine ? DunesColors.accentSoft : DunesColors.bgApp,
                border: Border.all(color: DunesColors.borderSoft),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(mine ? 12 : 4),
                  topRight: Radius.circular(mine ? 4 : 12),
                  bottomLeft: const Radius.circular(12),
                  bottomRight: const Radius.circular(12),
                ),
              ),
              child: RepaintBoundary(
                child: RobotMarkdown(markdown: m.bodyText, selectable: false),
              ),
            ),
          );
        },
      );
    }
    return ChatTextBubble(
      text: m.bodyText.isEmpty ? '[${m.kind}]' : m.bodyText,
      mine: mine,
      quote: quote.isEmpty ? null : quote,
      onQuoteTap: onQuoteTap,
      // 与文件消息同一套深色宫格菜单（PC 右键 / APP 长按）。
      onActionsMenu: (anchor, selectedText) {
        unawaited(
          _onMessageActions(
            m,
            mine,
            anchor: anchor,
            selectedText: selectedText,
          ),
        );
      },
      enableSelection: !_messageMultiSelectMode,
      selectAllOnLongPress: !isDesktopCommOnly,
    );
  }

  _ForwardBundle? _forwardBundleFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final raw = payload['forward'];
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final itemsRaw = map['items'];
    if (itemsRaw is! List) return null;
    final entries = itemsRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .map(
          (e) => _ForwardEntry(
            senderName: (e['senderName'] ?? '').toString().trim(),
            timeLabel: (e['timeLabel'] ?? '').toString().trim(),
            text: (e['text'] ?? '').toString().trim(),
            kind: (e['kind'] ?? 'TEXT').toString().trim().toUpperCase(),
            payload: e['payload'] is Map
                ? Map<String, dynamic>.from(e['payload'] as Map)
                : null,
            avatarPreset: (e['avatarPreset'] ?? '').toString().trim().isEmpty
                ? null
                : (e['avatarPreset'] ?? '').toString().trim(),
            avatarObjectKey:
                (e['avatarObjectKey'] ?? '').toString().trim().isEmpty
                ? null
                : (e['avatarObjectKey'] ?? '').toString().trim(),
          ),
        )
        .where((e) {
          if (e.text.isNotEmpty) return true;
          final k = e.kind.toUpperCase();
          if (k == 'IMAGE' || k == 'FILE' || k == 'AUDIO' || k == 'VIDEO') {
            return e.payload != null;
          }
          return e.payload?['forward'] is Map;
        })
        .toList(growable: false);
    if (entries.isEmpty) return null;
    final title = (map['title'] ?? '').toString().trim();
    return _ForwardBundle(
      title: title.isEmpty ? '聊天记录' : title,
      entries: entries,
    );
  }

  Widget _buildForwardEntryContent(_ForwardEntry e, {required bool mine}) {
    final nested = _forwardBundleFromPayload(e.payload);
    if (nested != null) {
      return _buildForwardRecordCard(nested, mine: false);
    }
    final kind = e.kind.toUpperCase();
    if (kind == 'IMAGE') {
      final imageName = ConversationService.mediaFileName(
        e.payload,
        fallback: 'image.jpg',
      );
      return _wrapDesktopFileDrag(
        payload: e.payload,
        fileName: imageName,
        child: ChatAuthImageBubble(
          service: _service,
          payload: e.payload,
          mine: mine,
          conversationId: _chatConversationId,
        ),
      );
    }
    if (kind == 'VIDEO') {
      final videoName = ConversationService.mediaFileName(
        e.payload,
        fallback: 'video.mp4',
      );
      return _wrapDesktopFileDrag(
        payload: e.payload,
        fileName: videoName,
        enabled: _downloadProgressFor(e.payload) == null,
        child: ChatAuthVideoBubble(
          service: _service,
          payload: e.payload,
          mine: mine,
          onTap: () => unawaited(_openChatVideo(e.payload)),
        ),
      );
    }
    if (kind == 'FILE') {
      final fileName = ConversationService.mediaFileName(
        e.payload,
        fallback:
            e.text.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), '').trim().isEmpty
            ? '文件'
            : e.text.replaceAll(RegExp(r'^\[[^\]]+\]\s*'), ''),
      );
      return _wrapDesktopFileDrag(
        payload: e.payload,
        fileName: fileName,
        enabled: _downloadProgressFor(e.payload) == null,
        child: ChatFileAttach(
          fileName: fileName,
          mine: mine,
          fileSizeBytes: (e.payload?['size'] as num?)?.toInt(),
          downloadProgress: _downloadProgressFor(e.payload),
          onCancelDownload: _downloadCancelFor(e.payload),
          onTap: () => _openFileAttachment(e.payload, fileName),
        ),
      );
    }
    if (kind == 'AUDIO') {
      final sec = (e.payload?['durationSec'] as num?)?.toInt() ?? 0;
      final source = _mediaSource(e.payload);
      final asrKey = _voiceAsrKey(messageId: 0, payload: e.payload);
      return ChatVoiceBubble(
        playKey: 'forward-${e.senderName}-$sec-${source.hashCode}',
        durationSec: sec,
        mine: mine,
        asrKey: asrKey,
        resolveUrl: () => _resolveMediaUrl(source),
        onPlayError: (message) => _showToast(message, error: true),
      );
    }
    if (_isRobotMarkdownPayload(e.payload)) {
      return RepaintBoundary(
        child: RobotMarkdown(markdown: e.text, selectable: false),
      );
    }
    return Text(
      e.text.isEmpty ? '[消息]' : e.text,
      style: DunesTypography.sans(
        fontSize: 14,
        color: DunesColors.text,
        height: 1.5,
      ),
    );
  }

  Widget _buildForwardRecordCard(_ForwardBundle bundle, {required bool mine}) {
    final preview = bundle.entries.take(2).toList(growable: false);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => unawaited(_showForwardBundleDetail(bundle)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFE9E9E9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bundle.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DunesTypography.sans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 5),
              ...preview.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '${e.senderName.isEmpty ? '用户' : e.senderName}: ${e.text}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      color: DunesColors.text3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Divider(height: 1, color: Color(0xFFEFEFEF)),
              const SizedBox(height: 5),
              Text(
                '聊天记录',
                style: DunesTypography.sans(
                  fontSize: 11,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showForwardBundleDetail(_ForwardBundle bundle) async {
    final searchController = TextEditingController();
    var keyword = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.92,
          ),
          decoration: const BoxDecoration(
            color: DunesColors.bgPage,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: StatefulBuilder(
              builder: (context, setModalState) {
                final query = keyword.trim().toLowerCase();
                final entries = query.isEmpty
                    ? bundle.entries
                    : bundle.entries
                          .where(
                            (e) =>
                                e.senderName.toLowerCase().contains(query) ||
                                e.text.toLowerCase().contains(query),
                          )
                          .toList(growable: false);
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: DunesColors.border,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
                      child: Row(
                        children: [
                          Material(
                            color: Colors.white,
                            shape: const CircleBorder(
                              side: BorderSide(color: DunesColors.borderSoft),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => Navigator.of(context).pop(),
                              child: const SizedBox(
                                width: 34,
                                height: 34,
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: DunesColors.text2,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  bundle.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: DunesTypography.sans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: DunesColors.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '共 ${bundle.entries.length} 条记录',
                                  style: DunesTypography.sans(
                                    fontSize: 11,
                                    color: DunesColors.text3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 34),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                      child: TextField(
                        controller: searchController,
                        onChanged: (value) =>
                            setModalState(() => keyword = value),
                        style: DunesTypography.sans(
                          fontSize: 14,
                          color: DunesColors.text,
                        ),
                        cursorColor: DunesColors.accent,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: '搜索聊天记录',
                          hintStyle: DunesTypography.sans(
                            fontSize: 14,
                            color: DunesColors.text3,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: DunesColors.text3,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 42,
                            minHeight: 38,
                          ),
                          suffixIcon: keyword.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    searchController.clear();
                                    setModalState(() => keyword = '');
                                  },
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.cancel_rounded,
                                    size: 18,
                                    color: DunesColors.text3,
                                  ),
                                ),
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 38,
                            minHeight: 38,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: DunesColors.borderSoft,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: DunesColors.borderSoft,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: DunesColors.accentLine,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: entries.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.manage_search_rounded,
                                    size: 40,
                                    color: DunesColors.text3.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '未找到相关记录',
                                    style: DunesTypography.sans(
                                      fontSize: 13,
                                      color: DunesColors.text3,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(14, 2, 14, 18),
                              itemCount: entries.length,
                              itemBuilder: (context, index) =>
                                  _forwardDetailEntryRow(entries[index]),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    ).whenComplete(searchController.dispose);
  }

  Widget _forwardDetailEntryRow(_ForwardEntry e) {
    final name = e.senderName.trim().isEmpty ? '用户' : e.senderName.trim();
    final kind = e.kind.toUpperCase();
    final bareContent =
        kind == 'IMAGE' ||
        kind == 'VIDEO' ||
        kind == 'FILE' ||
        kind == 'AUDIO' ||
        _forwardBundleFromPayload(e.payload) != null;
    final content = _buildForwardEntryContent(e, mine: false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImUserAvatar(
            initial: name.substring(0, 1),
            seed: e.senderName.hashCode & 0x7fffffff,
            size: 36,
            avatarPreset: e.avatarPreset,
            avatarObjectKey: e.avatarObjectKey,
            avatarService: _service,
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
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: DunesColors.text2,
                        ),
                      ),
                    ),
                    if (e.timeLabel.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        e.timeLabel,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerLeft,
                  child: bareContent
                      ? content
                      : Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(14),
                              bottomLeft: Radius.circular(14),
                              bottomRight: Radius.circular(14),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: DunesColors.text.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: content,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _scrollBottom({
    bool animated = false,
    bool force = false,
    bool gentle = false,
  }) {
    if (_locatedMode && !force) return;
    final gen = ++_scrollBottomGen;

    void doScroll() {
      if (!mounted || gen != _scrollBottomGen) return;
      if (!_scrollController.hasClients) return;
      // reverse 列表：0 = 最新消息端（靠近输入框）
      const target = 0.0;
      if (animated) {
        unawaited(
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
          ),
        );
      } else {
        _scrollController.jumpTo(target);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => doScroll());

    if (!gentle) {
      for (final ms in const <int>[50, 150, 350]) {
        Future<void>.delayed(Duration(milliseconds: ms), doScroll);
      }
    }
  }

  bool _isGroupOwner() {
    final me = widget.session.userId;
    return _groupMembers.any((m) {
      final uid = (m['userId'] as num?)?.toInt() ?? 0;
      if (uid != me) return false;
      final role = (m['role'] ?? '').toString().toUpperCase();
      final roleLabel = (m['roleLabel'] ?? '').toString();
      return role == 'OWNER' || roleLabel.contains('主');
    });
  }

  String? _memberAvatarPreset(Map<String, dynamic> member) {
    final value = (member['avatarPreset'] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  String? _memberAvatarObjectKey(Map<String, dynamic> member) {
    final value = (member['avatarObjectKey'] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _insertAtMentions(List<String> names) async {
    final picked = names
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList(growable: false);
    if (picked.isEmpty) return;
    final text = _inputController.text;
    final partial = RegExp(r'^(.*)@[^@\s]*$').firstMatch(text);
    final prefix = partial != null
        ? partial.group(1)!
        : '$text${text.isNotEmpty && !RegExp(r'\s$').hasMatch(text) ? ' ' : ''}';
    final tail = '${picked.map((n) => '@$n').join(' ')} ';
    _insertingAtMentions = true;
    _inputController.text = '$prefix$tail';
    _inputController.selection = TextSelection.collapsed(
      offset: _inputController.text.length,
    );
    _insertingAtMentions = false;
    _closeEmojiPicker();
  }

  String? _partialAtFilter(String text) {
    return RegExp(r'@([^@\s]*)$').firstMatch(text)?.group(1);
  }

  void _syncInputAtFilter(String filter) {
    if (_syncingAtFilter) return;
    final partial = RegExp(r'^(.*)@[^@\s]*$').firstMatch(_inputController.text);
    if (partial == null) return;
    _syncingAtFilter = true;
    final newText = '${partial.group(1)}@$filter';
    _inputController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    _syncingAtFilter = false;
  }

  void _onComposeInputChanged() {
    final text = _inputController.text;
    final previousText = _lastComposeText;
    _lastComposeText = text;
    if (!_restoringComposeDraft) {
      _persistComposeDraft();
    }
    if (_syncingAtFilter ||
        _insertingAtMentions ||
        _isPrivate ||
        _conversation?.dissolved == true) {
      return;
    }
    // 拼音未上屏时不要弹 @ 面板，避免抢走 IME；上屏后仍按原文自动弹出。
    final composing = _inputController.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return;
    }
    final filter = _partialAtFilter(text);
    if (filter != null) {
      if (_atSheetOpen) {
        _syncingAtFilter = true;
        _atFilterNotifier?.value = filter;
        _syncingAtFilter = false;
      } else if (!_atSheetOpening && text.length > previousText.length) {
        // 仅在用户主动输入（文本变长）时唤出选择器；删除已选 @ 成员
        // 退回到 `@张三` 这类完整提及时不应再次弹出。
        unawaited(_openAtMentionPicker(filter: filter));
      }
    } else if (_atSheetOpen && mounted) {
      _closeAtMentionPicker();
    }
  }

  void _closeAtMentionPicker() {
    if (!_atSheetOpen) return;
    _atSheetOpen = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  Future<void> _pickAtMember() async {
    if (!_isPrivate) {
      final text = _inputController.text;
      if (_partialAtFilter(text) == null) {
        final needsSpace = text.isNotEmpty && !RegExp(r'\s$').hasMatch(text);
        final newText = '$text${needsSpace ? ' ' : ''}@';
        _inputController.text = newText;
        _inputController.selection = TextSelection.collapsed(
          offset: newText.length,
        );
      }
    }
    await _openAtMentionPicker(
      filter: _partialAtFilter(_inputController.text) ?? '',
      focusSearch: true,
    );
  }

  Future<void> _openAtMentionPicker({
    String filter = '',
    bool focusSearch = false,
  }) async {
    final conv = _conversation;
    if (conv == null || _isPrivate) return;
    if (_atSheetOpen || _atSheetOpening) {
      _atFilterNotifier?.value = filter;
      return;
    }
    _atSheetOpening = true;
    try {
      final members =
          (_groupMembers.isNotEmpty
                  ? _groupMembers
                  : await _service.fetchConversationMembers(conv.id))
              .where(
                (m) =>
                    ((m['userId'] as num?)?.toInt() ?? 0) !=
                    widget.session.userId,
              )
              .toList(growable: false);
      if (_groupMembers.isEmpty) _groupMembers = members;
      if (members.isEmpty) {
        _showToast('暂无可 @ 成员');
        return;
      }
      if (!mounted) return;
      _atFilterNotifier = ValueNotifier<String>(filter);
      _atSheetOpen = true;
      final names = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => GestureDetector(
          onTap: () => Navigator.pop(sheetContext),
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(color: Colors.black.withValues(alpha: 0.35)),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  onTap: () {},
                  child: _AtMentionSheet(
                    members: members,
                    showAtAll: _isGroupOwner(),
                    avatarService: _service,
                    initialFilter: filter,
                    filterListenable: _atFilterNotifier!,
                    focusSearch: focusSearch,
                    onFilterChanged: _syncInputAtFilter,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      _atSheetOpen = false;
      _atFilterNotifier?.dispose();
      _atFilterNotifier = null;
      if (names != null && names.isNotEmpty) {
        await _insertAtMentions(names);
      }
    } catch (e) {
      _showToast('@ 成员加载失败：${friendlyErrorText(e)}');
    } finally {
      _atSheetOpen = false;
      _atSheetOpening = false;
      _atFilterNotifier?.dispose();
      _atFilterNotifier = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootstrapped && _loading && _conversation == null) {
      return const Scaffold(
        backgroundColor: DunesColors.bgApp,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null && !_bootstrapped && _conversation == null) {
      return Scaffold(
        backgroundColor: DunesColors.bgApp,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: DunesColors.text3)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    final conv = _conversation;
    if (conv == null) {
      return const Scaffold(
        backgroundColor: DunesColors.bgApp,
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final title = conv.displayTitle;
    final locked = conv.dissolved;
    final memberLabel = conv.memberCount > 0 ? '${conv.memberCount} 人' : '';
    final subtitle = _isPrivate
        ? _privateHeaderSubtitle(conv)
        : memberLabel.isEmpty
        ? '群聊'
        : memberLabel;
    final listEntries = _buildListEntries();
    _scheduleUnreadVisibilityCheck();
    final selecting = _messageMultiSelectMode;
    final scrollMetrics = _ChatScrollMetrics.fromScreenHeight(
      MediaQuery.sizeOf(context).height,
    );
    final listCacheExtent = scrollMetrics.cacheExtent;
    final inputHint = locked
        ? '群聊已解散，无法发送消息'
        : _isPrivate
        ? (title.isNotEmpty ? '给$title发消息…' : '输入消息…')
        : '输入消息 · @人时唤出选择器';

    final scaffold = Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: DropTarget(
          // keep-alive 的 Offstage 会话仍会挂载 DropTarget；用 TickerMode
          // 保证切到工作台/微盘时不会把拖入文件误发到 IM。
          enable:
              _supportsDesktopFileDrop &&
              !locked &&
              !selecting &&
              TickerMode.valuesOf(context).enabled,
          onDragEntered: (_) {
            if (!_fileDropHovering) setState(() => _fileDropHovering = true);
          },
          onDragExited: (_) {
            if (_fileDropHovering) setState(() => _fileDropHovering = false);
          },
          onDragDone: (detail) {
            if (!TickerMode.valuesOf(context).enabled) return;
            if (_fileDropHovering) setState(() => _fileDropHovering = false);
            unawaited(_onDesktopFilesDropped(detail));
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  FocusScope.of(context).unfocus();
                  _closeEmojiPicker();
                  // 点会话区域：收起工具栏。
                  if (_toolsOpen) setState(() => _toolsOpen = false);
                },
                child: Column(
                  children: [
                    if (selecting)
                      _buildMultiSelectHeader()
                    else
                      ChatConvHeader(
                        title: title,
                        subtitle: subtitle,
                        onBack: widget.onBack,
                        showBackButton: widget.showBackButton,
                        onTapTitle: _isPrivate
                            ? widget.onOpenProfile
                            : widget.onOpenGroupInfo,
                        showOnlineDot:
                            _isPrivate &&
                            !(_conversation?.isSelfMemo ??
                                widget.conversationHint?.isSelfMemo ??
                                false) &&
                            _peerOnline,
                        leadingAvatar: conv.isSelfMemo
                            ? Container(
                                width: 45,
                                height: 45,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7B5CD8),
                                  borderRadius: BorderRadius.circular(
                                    45 * 0.18,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.folder_copy_outlined,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              )
                            : _isPrivate
                            ? ImUserAvatar(
                                initial: title.isNotEmpty
                                    ? title.substring(0, 1)
                                    : '?',
                                seed: conv.peerUserId ?? conv.id,
                                showOnline: false,
                                avatarPreset: conv.peerAvatarPreset,
                                avatarObjectKey: conv.peerAvatarObjectKey,
                                avatarService: _service,
                                size: 45,
                                borderRadius: 45 * 0.18,
                              )
                            : null,
                        actions: [
                          // 智能总结：私聊 / 群聊头部均保留
                          if (widget.onOpenAiSummary != null)
                            IconButton(
                              tooltip: '智能分析',
                              onPressed: () => widget.onOpenAiSummary!(conv.id),
                              icon: const Icon(
                                Icons.auto_awesome_rounded,
                                size: 20,
                                color: Color(0xFF7B5CD8),
                              ),
                            ),
                          // 私聊：三点进资料（历史/免打扰/置顶在资料页）
                          if (_isPrivate && widget.onOpenProfile != null)
                            IconButton(
                              tooltip: '更多',
                              onPressed: widget.onOpenProfile,
                              icon: const Icon(Icons.more_vert, size: 20),
                            ),
                          // 群聊：三点进群信息（历史/媒体在群资料页内，不占头部）
                          if (!_isPrivate && widget.onOpenGroupInfo != null)
                            IconButton(
                              tooltip: '群信息',
                              onPressed: widget.onOpenGroupInfo,
                              icon: const Icon(Icons.more_vert, size: 20),
                            ),
                        ],
                      ),
                    if (!selecting && _pinnedMessages.isNotEmpty)
                      TapRegion(
                        groupId: 'chat-pinned-bar',
                        onTapOutside: (_) {
                          if (!_pinnedExpanded) return;
                          setState(() => _pinnedExpanded = false);
                        },
                        child: ChatPinnedMessagesBar(
                          items: _pinnedMessages,
                          expanded: _pinnedExpanded,
                          onToggleExpand: () {
                            setState(() => _pinnedExpanded = !_pinnedExpanded);
                          },
                          onTapItem: (pin) {
                            if (_pinnedExpanded) {
                              setState(() => _pinnedExpanded = false);
                            }
                            unawaited(_jumpToPinnedMessage(pin));
                          },
                          onUnpinItem: (pin) {
                            unawaited(_unpinMessage(pin.messageId));
                          },
                        ),
                      ),
                    Expanded(
                      child: Stack(
                        children: [
                          if (!_bootstrapped && _loading)
                            const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else if (_error != null && !_bootstrapped)
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _error!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: DunesColors.text3,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    OutlinedButton(
                                      onPressed: _load,
                                      child: const Text('重试'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            NotificationListener<ScrollNotification>(
                              onNotification: _onMessageListScroll,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final wide = isWideChatLayout(context);
                                  // PC 桌面禁用 shrinkWrap：否则短会话 maxScrollExtent≈0，
                                  // 鼠标滚轮无法驱动 ScrollPosition，「上滑加载」失效。
                                  final useShrinkWrap =
                                      wide && !isDesktopCommOnly;
                                  final list = Listener(
                                    onPointerSignal:
                                        _onMessageListPointerSignal,
                                    child: ListView.builder(
                                      controller: _scrollController,
                                      reverse: true,
                                      // 宽屏 Web 短会话贴顶；桌面端铺满视口以保证滚轮加载历史。
                                      shrinkWrap: useShrinkWrap,
                                      physics: _chatListScrollPhysics(
                                        scrollMetrics,
                                      ),
                                      cacheExtent: listCacheExtent,
                                      addAutomaticKeepAlives: false,
                                      addRepaintBoundaries: true,
                                      findChildIndexCallback:
                                          _findMessageListChildIndex,
                                      keyboardDismissBehavior:
                                          ScrollViewKeyboardDismissBehavior
                                              .onDrag,
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        12,
                                        12,
                                        10,
                                      ),
                                      itemCount:
                                          listEntries.length +
                                          _listFooterCount +
                                          _listHeaderCount,
                                      itemBuilder: (_, index) {
                                        final hasNewerFooter =
                                            _locatedMode && _hasNewer;
                                        if (hasNewerFooter && index == 0) {
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            child: Center(
                                              child: _loadingNewer
                                                  ? const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    )
                                                  : TextButton(
                                                      onPressed: _loadNewer,
                                                      child: const Text(
                                                        '加载更新消息',
                                                      ),
                                                    ),
                                            ),
                                          );
                                        }
                                        final headerIndex =
                                            listEntries.length +
                                            _listFooterCount;
                                        if (_listHeaderCount > 0 &&
                                            index >= headerIndex) {
                                          // 历史顶入口进入可视区时再兜底拉一次。
                                          WidgetsBinding.instance
                                              .addPostFrameCallback((_) {
                                                if (!mounted ||
                                                    !_scrollController
                                                        .hasClients) {
                                                  return;
                                                }
                                                if (_shouldAutoloadOlder(
                                                  _scrollController.position,
                                                )) {
                                                  unawaited(_loadOlder());
                                                }
                                              });
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                            child: Center(
                                              child: _loadingOlder
                                                  ? const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    )
                                                  : TextButton(
                                                      onPressed: _loadOlder,
                                                      child: const Text(
                                                        '加载更早消息',
                                                      ),
                                                    ),
                                            ),
                                          );
                                        }
                                        final entry = _entryForListIndex(
                                          index,
                                          listEntries,
                                        );
                                        if (entry == null) {
                                          return const SizedBox.shrink();
                                        }
                                        if (entry.dividerLabel != null) {
                                          return ChatDateDivider(
                                            key: ValueKey<String>(
                                              'day-${entry.dividerLabel}',
                                            ),
                                            label: entry.dividerLabel!,
                                          );
                                        }
                                        final m = entry.message!;
                                        final mine =
                                            m.senderUserId ==
                                            widget.session.userId;
                                        final highlighted =
                                            _highlightMessageId == m.id;
                                        final timeLabel =
                                            InboxFormat.msgTimeLabel(
                                              m.createdAt,
                                            );
                                        final rowAvatar =
                                            _tappableAvatarForMessage(
                                              m,
                                              mine: mine,
                                            );
                                        Widget row;
                                        if (_isSystemKind(m.kind)) {
                                          row = _buildMessageWidget(m, mine);
                                        } else {
                                          final peerRead = mine && _isPrivate
                                              ? _messagePeerRead(m)
                                              : false;
                                          final desktop = isDesktopCommOnly;
                                          final textMessage =
                                              m.kind.toUpperCase() == 'TEXT';
                                          final isForwardMessage =
                                              _forwardBundleFromPayload(
                                                m.payload,
                                              ) !=
                                              null;
                                          final isRobotMarkdown =
                                              _isRobotMarkdownPayload(
                                                m.payload,
                                              );
                                          // 纯文字气泡由 ChatTextBubble.onActionsMenu
                                          // 走与文件相同的深色宫格，并保留选区信息；
                                          // 行级手势不再接管，避免 PC 右键抢先导致选区丢失。
                                          final useTextBubbleMenu =
                                              textMessage &&
                                              !isForwardMessage &&
                                              !isRobotMarkdown;
                                          final canShowActions =
                                              !_messageMultiSelectMode &&
                                              !_isSystemKind(m.kind);
                                          final enableLongPress =
                                              canShowActions &&
                                              !useTextBubbleMenu;
                                          final enableSecondaryTap =
                                              canShowActions &&
                                              desktop &&
                                              !useTextBubbleMenu;
                                          void openActions(Offset anchor) {
                                            unawaited(
                                              _onMessageActions(
                                                m,
                                                mine,
                                                anchor: anchor,
                                              ),
                                            );
                                          }

                                          row = ChatMessageRow(
                                            message: m,
                                            mine: mine,
                                            showSenderMeta:
                                                entry.showSenderMeta,
                                            showTimeForMine: mine,
                                            timeLabel: timeLabel,
                                            readLabel:
                                                mine &&
                                                    _isPrivate &&
                                                    _conversation?.isSelfMemo !=
                                                        true
                                                ? (peerRead ? '已读' : '未读')
                                                : null,
                                            onLongPress: null,
                                            onLongPressStart: enableLongPress
                                                ? (details) => openActions(
                                                    details.globalPosition,
                                                  )
                                                : null,
                                            onSecondaryTapDown:
                                                enableSecondaryTap
                                                ? (details) => openActions(
                                                    details.globalPosition,
                                                  )
                                                : null,
                                            onReadTap: mine && !_isPrivate
                                                ? () => _showReadReceipts(m)
                                                : null,
                                            readTapLabel:
                                                _groupReadLabelForMessage(
                                                  m,
                                                  mine: mine,
                                                ),
                                            avatar: !mine ? rowAvatar : null,
                                            trailingAvatar: mine
                                                ? rowAvatar
                                                : null,
                                            content: _buildMessageWidget(
                                              m,
                                              mine,
                                            ),
                                          );
                                        }
                                        var rowWidget = highlighted
                                            ? AnimatedContainer(
                                                key: _messageRowKey(m.id),
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: DunesColors.accentSoft
                                                      .withValues(alpha: 0.45),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 2,
                                                    ),
                                                child: row,
                                              )
                                            : KeyedSubtree(
                                                key: _messageRowKey(m.id),
                                                child: row,
                                              );
                                        if (_messageMultiSelectMode &&
                                            _canSelectMessageForMulti(m)) {
                                          final selected =
                                              _multiSelectedMessageIds.contains(
                                                m.id,
                                              );
                                          rowWidget = Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 2,
                                                  right: 6,
                                                  top: 8,
                                                ),
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () =>
                                                      _toggleMessageMultiSelected(
                                                        m.id,
                                                      ),
                                                  child: Icon(
                                                    selected
                                                        ? Icons.check_circle
                                                        : Icons
                                                              .radio_button_unchecked,
                                                    size: 22,
                                                    color: selected
                                                        ? DunesColors.accent
                                                        : DunesColors.text3,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () =>
                                                      _toggleMessageMultiSelected(
                                                        m.id,
                                                      ),
                                                  child: rowWidget,
                                                ),
                                              ),
                                            ],
                                          );
                                        }
                                        return rowWidget;
                                      },
                                    ),
                                  );
                                  // 桌面端列表已铺满视口，无需 shrinkWrap+Align。
                                  if (!wide || isDesktopCommOnly) return list;
                                  return Align(
                                    alignment: Alignment.topCenter,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxHeight: constraints.maxHeight,
                                      ),
                                      child: list,
                                    ),
                                  );
                                },
                              ),
                            ),
                          if (_loadingOlder)
                            const Positioned(
                              top: 8,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Material(
                                  color: Colors.transparent,
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_locating)
                            Positioned(
                              top: 8,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Material(
                                  elevation: 1,
                                  borderRadius: BorderRadius.circular(16),
                                  color: DunesColors.bgApp,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '定位中…',
                                          style: DunesTypography.sans(
                                            fontSize: 11,
                                            color: DunesColors.text3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_showUnreadJumpBadge)
                            Positioned(
                              right: 12,
                              top: 12,
                              child: Material(
                                color: Colors.transparent,
                                elevation: 0,
                                borderRadius: BorderRadius.circular(
                                  isDesktopCommOnly ? 999 : 14,
                                ),
                                child: InkWell(
                                  onTap: () => unawaited(_jumpToFirstUnread()),
                                  borderRadius: BorderRadius.circular(
                                    isDesktopCommOnly ? 999 : 14,
                                  ),
                                  child: Ink(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        isDesktopCommOnly ? 999 : 14,
                                      ),
                                      color: isDesktopCommOnly
                                          ? const Color(0xFF07C160)
                                          : Colors.white,
                                      border: isDesktopCommOnly
                                          ? null
                                          : Border.all(
                                              color: DunesColors.accent
                                                  .withValues(alpha: 0.32),
                                            ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                      vertical: 7,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!isDesktopCommOnly) ...[
                                          const Icon(
                                            Icons.mark_chat_unread_outlined,
                                            size: 15,
                                            color: DunesColors.accentDeep,
                                          ),
                                          const SizedBox(width: 5),
                                        ],
                                        Text(
                                          '${_sessionUnreadCount > 99 ? '99+' : _sessionUnreadCount} 条未读',
                                          style: DunesTypography.sans(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: isDesktopCommOnly
                                                ? Colors.white
                                                : DunesColors.accentDeep,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Icon(
                                          Icons.keyboard_arrow_up_rounded,
                                          size: 16,
                                          color: isDesktopCommOnly
                                              ? Colors.white
                                              : DunesColors.accentDeep,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if ((_awayFromLatest ||
                                  _pendingNewMessageCount > 0) &&
                              !_locatedMode)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 12,
                              child: Center(
                                child: Material(
                                  color: Colors.transparent,
                                  elevation: 0,
                                  borderRadius: BorderRadius.circular(999),
                                  child: InkWell(
                                    onTap: _jumpToPendingMessages,
                                    borderRadius: BorderRadius.circular(999),
                                    child: Ink(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        color: _pendingNewMessageCount > 0
                                            ? const Color(0xFF7E64BD)
                                            : Colors.white,
                                        border: _pendingNewMessageCount > 0
                                            ? null
                                            : Border.all(
                                                color: DunesColors.borderSoft,
                                              ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            size: 16,
                                            color: _pendingNewMessageCount > 0
                                                ? Colors.white
                                                : DunesColors.accentDeep,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _pendingNewMessageCount > 0
                                                ? '${_pendingNewMessageCount > 99 ? '99+' : _pendingNewMessageCount} 条新消息'
                                                : '回到最新',
                                            style: DunesTypography.sans(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: _pendingNewMessageCount > 0
                                                  ? Colors.white
                                                  : DunesColors.accentDeep,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (_locatedMode)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 8,
                              child: Center(
                                child: Material(
                                  elevation: 0,
                                  borderRadius: BorderRadius.circular(20),
                                  color: Colors.white,
                                  child: InkWell(
                                    onTap: _jumpToLatest,
                                    borderRadius: BorderRadius.circular(20),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.arrow_downward,
                                            size: 14,
                                            color: DunesColors.accentDeep,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '回到最新消息',
                                            style: DunesTypography.sans(
                                              fontSize: 12,
                                              color: DunesColors.accentDeep,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (selecting)
                      _buildMultiSelectBottomBar()
                    else
                      SafeArea(
                        top: false,
                        child: _buildComposerDock(
                          locked: locked,
                          inputHint: inputHint,
                        ),
                      ),
                  ],
                ),
              ),
              if (_recording)
                VoiceRecordingOverlay(
                  durationMs: _recordDurationMs,
                  action: _recordHoldAction,
                  transcribeEnabled: !isDesktopCommOnly,
                  focalPoint: _recordFocalPoint,
                ),
              if (_fileDropHovering)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: DunesColors.accent.withValues(alpha: 0.1),
                        border: Border.all(
                          color: DunesColors.accent.withValues(alpha: 0.55),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.file_upload_outlined,
                                size: 22,
                                color: DunesColors.accentDeep,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '松开以发送文件 / 图片',
                                style: DunesTypography.sans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: DunesColors.accentDeep,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (!isDesktopCommOnly) return scaffold;
    // 快捷键由 HardwareKeyboard 处理；这里保留 Shortcuts 作兜底。
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(
          LogicalKeyboardKey.keyA,
          control: true,
          alt: true,
        ): () {
          if (locked || _mediaBusy) return;
          unawaited(_desktopScreenshotAndSend());
        },
      },
      child: scaffold,
    );
  }
}

class _GroupReadPerson {
  const _GroupReadPerson({
    required this.uid,
    required this.name,
    required this.sub,
    this.avatarPreset,
    this.avatarObjectKey,
  });

  final int uid;
  final String name;
  final String sub;
  final String? avatarPreset;
  final String? avatarObjectKey;
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _SheetAvatar extends StatelessWidget {
  const _SheetAvatar({
    required this.initial,
    required this.seed,
    this.avatarPreset,
    this.avatarObjectKey,
    this.avatarService,
  });

  final String initial;
  final int seed;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final ConversationService? avatarService;

  @override
  Widget build(BuildContext context) {
    return ImUserAvatar(
      initial: initial,
      seed: seed,
      size: 40,
      avatarPreset: avatarPreset,
      avatarObjectKey: avatarObjectKey,
      avatarService: avatarService,
      borderRadius: 40 * 0.18,
    );
  }
}

class _AtMentionSheet extends StatefulWidget {
  const _AtMentionSheet({
    required this.members,
    required this.showAtAll,
    required this.avatarService,
    this.initialFilter = '',
    this.filterListenable,
    this.onFilterChanged,
    this.focusSearch = false,
  });

  final List<Map<String, dynamic>> members;
  final bool showAtAll;
  final ConversationService avatarService;
  final String initialFilter;
  final ValueListenable<String>? filterListenable;
  final ValueChanged<String>? onFilterChanged;
  final bool focusSearch;

  static const _atAllLabel = '所有人';

  @override
  State<_AtMentionSheet> createState() => _AtMentionSheetState();
}

class _AtMentionSheetState extends State<_AtMentionSheet> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _selected = <String, bool>{};
  bool _suppressSearchCallback = false;

  @override
  void initState() {
    super.initState();
    _search.text = widget.initialFilter;
    _search.addListener(_onSearchChanged);
    widget.filterListenable?.addListener(_onExternalFilter);
    if (widget.focusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    widget.filterListenable?.removeListener(_onExternalFilter);
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_suppressSearchCallback) return;
    setState(() {});
    widget.onFilterChanged?.call(_search.text);
  }

  void _onExternalFilter() {
    final external = widget.filterListenable?.value ?? '';
    if (_search.text == external) return;
    _suppressSearchCallback = true;
    _search.value = TextEditingValue(
      text: external,
      selection: TextSelection.collapsed(offset: external.length),
    );
    _suppressSearchCallback = false;
    setState(() {});
  }

  int get _selectedCount => _selected.values.where((v) => v).length;

  bool _matchesMember(Map<String, dynamic> member, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    final name = (member['displayName'] ?? member['name'] ?? '')
        .toString()
        .toLowerCase();
    final dept = (member['departmentName'] ?? member['department'] ?? '')
        .toString()
        .toLowerCase();
    final title = (member['title'] ?? member['roleLabel'] ?? '')
        .toString()
        .toLowerCase();
    return name.contains(q) || dept.contains(q) || title.contains(q);
  }

  bool _showAtAllRow(String query) {
    if (!widget.showAtAll) return false;
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return _AtMentionSheet._atAllLabel.contains(q) || '所有人'.contains(q);
  }

  String _memberDeptTitle(Map<String, dynamic> member) {
    final parts = <String>[];
    final dept = (member['department'] ?? member['departmentName'] ?? '')
        .toString()
        .trim();
    final title =
        (member['title'] ?? member['roleLabel'] ?? member['role'] ?? '')
            .toString()
            .trim();
    if (dept.isNotEmpty) parts.add(dept);
    if (title.isNotEmpty) parts.add(title);
    return parts.join(' · ');
  }

  void _toggle(String name, {required bool isAll}) {
    setState(() {
      if (isAll) {
        if (_selected[_AtMentionSheet._atAllLabel] == true) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..[_AtMentionSheet._atAllLabel] = true;
        }
        return;
      }
      _selected.remove(_AtMentionSheet._atAllLabel);
      final on = _selected[name] == true;
      if (on) {
        _selected.remove(name);
      } else {
        _selected[name] = true;
      }
    });
  }

  void _confirm() {
    final names = _selected.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList(growable: false);
    if (names.isEmpty) return;
    final picked = names.contains(_AtMentionSheet._atAllLabel)
        ? const [_AtMentionSheet._atAllLabel]
        : names;
    Navigator.pop(context, picked);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final filtered = widget.members
        .where((m) => _matchesMember(m, query))
        .toList(growable: false);
    final showAll = _showAtAllRow(query);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    final sheetHeight = maxHeight.clamp(320.0, 520.0);

    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: sheetHeight,
          decoration: const BoxDecoration(
            color: DunesColors.bgApp,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1F000000),
                blurRadius: 40,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            children: [
              const _SheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '选择提醒的人',
                    style: DunesTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '可多选成员，支持按姓名、部门、职位搜索',
                    style: DunesTypography.sans(
                      fontSize: 11,
                      color: DunesColors.text3,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: DunesColors.bgSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
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
                          controller: _search,
                          focusNode: _searchFocus,
                          autofocus: false,
                          style: DunesTypography.sans(fontSize: 14),
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: '搜索姓名 / 部门 / 职位',
                            hintStyle: DunesTypography.sans(
                              fontSize: 14,
                              color: DunesColors.text3,
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    if (showAll) _buildAtAllRow(),
                    if (filtered.isEmpty && !showAll)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            '未找到匹配成员',
                            style: DunesTypography.sans(
                              fontSize: 13,
                              color: DunesColors.text3,
                            ),
                          ),
                        ),
                      )
                    else
                      ...filtered.map(_buildMemberRow),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _selectedCount > 0
                            ? const [Color(0xFF7E64BD), Color(0xFF553B96)]
                            : [
                                DunesColors.text3.withValues(alpha: 0.35),
                                DunesColors.text3.withValues(alpha: 0.35),
                              ],
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _selectedCount > 0 ? _confirm : null,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: Text(
                              _selectedCount > 0 ? '完成（$_selectedCount）' : '完成',
                              style: DunesTypography.sans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAtAllRow() {
    final selected = _selected[_AtMentionSheet._atAllLabel] == true;
    return _AtMentionSheetRow(
      selected: selected,
      onTap: () => _toggle(_AtMentionSheet._atAllLabel, isAll: true),
      avatar: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE85D4C), Color(0xFFF07A5A)],
          ),
        ),
        child: Text(
          '@',
          style: DunesTypography.sans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      name: '@${_AtMentionSheet._atAllLabel}',
      subtitle: '提醒群内所有成员',
    );
  }

  Widget _buildMemberRow(Map<String, dynamic> member) {
    final uid = (member['userId'] as num?)?.toInt() ?? 0;
    final name = (member['displayName'] ?? member['name'] ?? '成员').toString();
    final selected = _selected[name] == true;
    final sub = _memberDeptTitle(member);
    return _AtMentionSheetRow(
      selected: selected,
      onTap: () => _toggle(name, isAll: false),
      avatar: _SheetAvatar(
        initial: name.isNotEmpty ? name.substring(0, 1) : '?',
        seed: uid,
        avatarPreset: (member['avatarPreset'] ?? '').toString().trim().isEmpty
            ? null
            : (member['avatarPreset'] ?? '').toString(),
        avatarObjectKey:
            (member['avatarObjectKey'] ?? '').toString().trim().isEmpty
            ? null
            : (member['avatarObjectKey'] ?? '').toString(),
        avatarService: widget.avatarService,
      ),
      name: name,
      subtitle: sub.isEmpty ? '群成员' : sub,
    );
  }
}

class _AtMentionSheetRow extends StatelessWidget {
  const _AtMentionSheetRow({
    required this.selected,
    required this.onTap,
    required this.avatar,
    required this.name,
    required this.subtitle,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget avatar;
  final String name;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? const Color(0x14553B96) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: selected
                  ? Border.all(color: const Color(0x29553B96))
                  : null,
            ),
            child: Row(
              children: [
                _AtMentionCheck(selected: selected),
                const SizedBox(width: 12),
                avatar,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          color: DunesColors.text3,
                        ),
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

class _AtMentionCheck extends StatelessWidget {
  const _AtMentionCheck({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: selected
            ? null
            : Border.all(
                color: Colors.black.withValues(alpha: 0.18),
                width: 1.5,
              ),
        gradient: selected
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF553B96), Color(0xFF7B5CB8)],
              )
            : null,
      ),
      child: selected
          ? const Icon(Icons.check, size: 12, color: Colors.white)
          : null,
    );
  }
}

class _GroupReadSheet extends StatelessWidget {
  const _GroupReadSheet({
    required this.readRows,
    required this.unreadRows,
    required this.avatarService,
  });

  final List<_GroupReadPerson> readRows;
  final List<_GroupReadPerson> unreadRows;
  final ConversationService avatarService;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.68;
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight.clamp(280.0, 480.0)),
        decoration: const BoxDecoration(
          color: DunesColors.bgApp,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${readRows.length}人已读 · ${unreadRows.length}人未读',
                  style: DunesTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                children: [
                  _GroupReadSheetSection(
                    title: '已读（${readRows.length}）',
                    rows: readRows,
                    emptyText: '暂无',
                    avatarService: avatarService,
                  ),
                  _GroupReadSheetSection(
                    title: '未读（${unreadRows.length}）',
                    rows: unreadRows,
                    emptyText: '全部已读',
                    avatarService: avatarService,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupReadSheetSection extends StatelessWidget {
  const _GroupReadSheetSection({
    required this.title,
    required this.rows,
    required this.emptyText,
    required this.avatarService,
  });

  final String title;
  final List<_GroupReadPerson> rows;
  final String emptyText;
  final ConversationService avatarService;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(
            title,
            style: DunesTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: DunesColors.text2,
            ),
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text(
              emptyText,
              style: DunesTypography.sans(
                fontSize: 11,
                color: DunesColors.text3,
              ),
            ),
          )
        else
          ...rows.map(
            (row) =>
                _GroupReadSheetRow(person: row, avatarService: avatarService),
          ),
      ],
    );
  }
}

class _GroupReadSheetRow extends StatelessWidget {
  const _GroupReadSheetRow({required this.person, required this.avatarService});

  final _GroupReadPerson person;
  final ConversationService avatarService;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            _SheetAvatar(
              initial: person.name.isNotEmpty
                  ? person.name.substring(0, 1)
                  : '?',
              seed: person.uid,
              avatarPreset: person.avatarPreset,
              avatarObjectKey: person.avatarObjectKey,
              avatarService: avatarService,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (person.sub.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        person.sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 11,
                          color: DunesColors.text3,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 聊天列表滚动物理：按屏高限制惯性，配合分页实现「一滑一屏左右」手感。
class _ChatScrollPhysics extends ScrollPhysics {
  const _ChatScrollPhysics({
    super.parent,
    this.flingVelocityCap = 2200,
    this.dragDampingFactor = 0.90,
  });

  final double flingVelocityCap;
  final double dragDampingFactor;

  @override
  _ChatScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ChatScrollPhysics(
      parent: buildParent(ancestor),
      flingVelocityCap: flingVelocityCap,
      dragDampingFactor: dragDampingFactor,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    return super.applyPhysicsToUserOffset(position, offset * dragDampingFactor);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final clamped = velocity.clamp(-flingVelocityCap, flingVelocityCap);
    return super.createBallisticSimulation(position, clamped);
  }
}
