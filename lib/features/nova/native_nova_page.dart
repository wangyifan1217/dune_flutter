import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/config/nova_config.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/util/native_permissions.dart';
import '../../core/widgets/cached_network_image.dart';
import '../auth/auth_session.dart';
import '../chat/native_audio_recorder.dart';
import '../chat/chat_image_batch_preview.dart';
import '../chat/chat_image_editor.dart';
import '../chat/voice_recording_overlay.dart';
import '../meeting/meeting_live_controller.dart';
import '../meeting/meeting_minutes_export.dart';
import '../meeting/native_meeting_models.dart';
import '../meeting/native_meeting_service.dart';
import '../kb/native_kb_models.dart';
import '../kb/native_kb_service.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_service.dart';
import '../qianji/digital_auto/digital_employee_service.dart';
import '../shell/dunes_toast.dart';
import 'native_nova_service.dart';
import 'nova_background_coordinator.dart';
import 'nova_chart_card.dart';
import 'nova_draft.dart';
import 'nova_file_utils.dart';
import 'nova_generating_storage.dart';
import 'nova_history_utils.dart';
import 'nova_image_utils.dart';
import 'nova_mcp_services_view.dart';
import 'nova_media.dart';
import 'nova_meeting_prd.dart';
import 'nova_model_utils.dart';
import 'nova_models_service.dart';
import 'nova_personal_query.dart';
import 'nova_side_drawer.dart';
import 'nova_source_picker.dart';
import 'nova_source_scope.dart';
import 'nova_stream_parser.dart';
import 'nova_web_storage.dart';
import 'nova_welcome_view.dart';
import 'nova_deliverable.dart';
import 'nova_widgets.dart';
import 'voice_call/tau_voice_call_page.dart';

class NativeNovaPage extends StatefulWidget {
  const NativeNovaPage({
    super.key,
    required this.session,
    required this.onBack,
    this.onHistory,
    this.onOpenKb,
    this.onOpenMeeting,
    this.onOpenDigitalEmployee,
    this.focusConversationId,
    this.focusMessageId,
    this.onClearHistoryFocus,
    this.initialPrompt,
    this.onInitialPromptConsumed,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final VoidCallback? onHistory;
  final VoidCallback? onOpenKb;
  final VoidCallback? onOpenMeeting;
  final ValueChanged<DigitalEmployeeItem>? onOpenDigitalEmployee;
  final int? focusConversationId;
  final int? focusMessageId;
  final VoidCallback? onClearHistoryFocus;
  final String? initialPrompt;
  final VoidCallback? onInitialPromptConsumed;

  @override
  State<NativeNovaPage> createState() => _NativeNovaPageState();
}

class _NativeNovaPageState extends State<NativeNovaPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final NativeNovaService _service;
  late final NativeKbService _kbService;
  late final NativeMeetingService _meetingService;
  late final ConversationService _avatarService;
  late final NovaMediaResolver _mediaResolver;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _messageKeys = <int, GlobalKey>{};
  late final TabController _tabController;

  static const _novaChatTabIndex = 1;

  bool _loading = true;
  bool _sending = false;
  bool _serverGenerating = false;
  bool _novaReady = true;
  bool _voiceMode = false;
  bool _quickActionsOpen = false;
  bool _stickToBottom = true;
  bool _showJumpToLatest = false;
  bool _recording = false;
  VoiceHoldAction _recordAction = VoiceHoldAction.none;
  Offset? _recordFocalPoint;
  int _recordDurationMs = 0;
  int? _highlightMessageId;
  Timer? _recordTicker;
  StreamSubscription<Uint8List>? _asrPcmSubscription;
  BytesBuilder? _asrPcmBytes;
  Timer? _genPollTimer;
  Timer? _streamDraftTimer;
  int _genAfterMessageId = 0;
  String _lastUserDisplayText = '';
  String? _banner;
  String _busyHint = '';
  int _conversationId = 0;
  int _loadedSourceConversationId = 0;
  NovaPersonalCapability? _personalMode;

  /// 未手动选定板块时，上一句自动路由实际走的板块（只用于输入框显示，不锁定）。
  /// 下一句仍由服务端重新判断；问别的会回到「通用」。
  NovaPersonalCapability? _autoPersonalMode;
  bool _resendPreparing = false;
  NovaTaskPreview? _taskPreview;
  int? _previewMessageId;
  NovaInsight? _insight;
  int _loadToken = 0;
  bool _startingNewChat = false;
  bool _initialPromptConsumed = false;
  bool _scrollJumpQueued = false;

  /// 当前发送轮次的「立即刷新节流中的流式内容」，停止时先刷新再取部分回复。
  VoidCallback? _flushPendingStreamUpdate;

  /// 当前轮次用户提问的本地临时 ID 与服务端真实 ID（SSE user_message 回传），
  /// 停止时用于把本地气泡对齐到服务端消息。
  int _turnLocalUserMsgId = 0;
  int _turnServerUserMsgId = 0;
  static const _streamFlushIntervalMs = 80;
  bool _generationPollInFlight = false;
  int _generationPollConversation = 0;
  int _generationPollEpoch = 0;
  Future<void>? _leaveFlush;
  int _personalTurnToken = 0;
  List<NativeNovaMessage> _messages = const <NativeNovaMessage>[];
  List<String> _chatModels = const <String>[];
  String _selectedModel = '';
  List<NovaModelCatalogEntry> _modelCatalog = const <NovaModelCatalogEntry>[];
  List<NovaDraftAttachment> _drafts = const <NovaDraftAttachment>[];
  List<NovaAnalysisSource> _analysisSources = const <NovaAnalysisSource>[];
  int _draftSeq = 0;
  bool _prdResumeInFlight = false;
  bool _prdNovaSendStarted = false;
  String _userAvatarPreset = '';
  String _userAvatarObjectKey = '';
  String _userAvatarUrl = '';
  String _userAvatarSignature = '';
  int _userAvatarRefreshVersion = 0;

  String get _userName => (widget.session.displayName ?? '').trim().isNotEmpty
      ? widget.session.displayName!.trim()
      : '我';

  String get _userInitial {
    final name = _userName;
    if (name.isEmpty) return '?';
    return String.fromCharCode(name.runes.first);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = NovaBackgroundCoordinator.instance.serviceFor(widget.session);
    _kbService = NativeKbService(session: widget.session);
    _meetingService = NativeMeetingService(session: widget.session);
    _avatarService = ConversationService(session: widget.session);
    _mediaResolver = NovaMediaResolver(widget.session, service: _service);
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _novaChatTabIndex,
    );
    _tabController.addListener(_onNovaTabChanged);
    _inputFocusNode.addListener(_onInputFocusChanged);
    _scrollController.addListener(_onChatScroll);
    userAvatarRefresh.addListener(_onSelfAvatarUpdated);
    _load();
    unawaited(_loadInsight());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Tooltip.dismissAllToolTips();
    });
    MeetingLiveController.instance.active.addListener(
      _onMeetingLiveActiveChanged,
    );
    NovaBackgroundCoordinator.instance.addListener(_onNovaBackgroundUpdate);
    NovaBackgroundCoordinator.instance.setNovaPageActive(
      true,
      conversationId: _conversationId,
    );
  }

  @override
  void activate() {
    super.activate();
    NovaBackgroundCoordinator.instance.setNovaPageActive(
      true,
      conversationId: _conversationId,
    );
    NovaBackgroundCoordinator.instance.clearPendingCommBadgeBump();
  }

  void _onNovaBackgroundUpdate() {
    if (!mounted || _conversationId <= 0) return;
    if (_sending || _service.isReplyInFlightFor(_conversationId)) return;
    if (!_serverGenerating && !_sending && !_hasActiveAssistantStream()) return;
    if (!_serverGenerating && !_sending && _hasActiveAssistantStream()) {
      return;
    }
    unawaited(_pollGenerating());
  }

  void _onMeetingLiveActiveChanged() {
    if (!MeetingLiveController.instance.isActive || !_voiceMode || !mounted) {
      return;
    }
    setState(() => _voiceMode = false);
  }

  void _onNovaTabChanged() {
    Tooltip.dismissAllToolTips();
    if (!mounted || _tabController.indexIsChanging) return;
    if (_tabController.index != _novaChatTabIndex) {
      FocusScope.of(context).unfocus();
    }
    NovaBackgroundCoordinator.instance.setNovaPageActive(
      _isNovaChatTab,
      conversationId: _conversationId,
    );
    if (_isNovaChatTab) unawaited(_onAppResumed());
    setState(() {});
  }

  bool get _isNovaChatTab => _tabController.index == _novaChatTabIndex;

  void _showNovaChatTab() {
    if (_tabController.index != _novaChatTabIndex) {
      _tabController.animateTo(_novaChatTabIndex);
    }
  }

  @override
  void didUpdateWidget(covariant NativeNovaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldConv = oldWidget.focusConversationId ?? 0;
    final newConv = widget.focusConversationId ?? 0;
    final oldMsg = oldWidget.focusMessageId ?? 0;
    final newMsg = widget.focusMessageId ?? 0;
    if (newConv > 0 && (oldConv != newConv || oldMsg != newMsg)) {
      _personalMode = null;
      _autoPersonalMode = null;
      _taskPreview = null;
      _previewMessageId = null;
      unawaited(_load());
    }
  }

  @override
  void deactivate() {
    NovaBackgroundCoordinator.instance.setNovaPageActive(false);
    unawaited(_flushOnLeave());
    super.deactivate();
  }

  @override
  void dispose() {
    NovaBackgroundCoordinator.instance.setNovaPageActive(false);
    WidgetsBinding.instance.removeObserver(this);
    userAvatarRefresh.removeListener(_onSelfAvatarUpdated);
    MeetingLiveController.instance.active.removeListener(
      _onMeetingLiveActiveChanged,
    );
    NovaBackgroundCoordinator.instance.removeListener(_onNovaBackgroundUpdate);
    _tabController.removeListener(_onNovaTabChanged);
    _tabController.dispose();
    _streamDraftTimer?.cancel();
    _genPollTimer?.cancel();
    _recordTicker?.cancel();
    unawaited(_discardAsrPcmCapture());
    unawaited(_flushOnLeave());
    if (_recording) {
      unawaited(NativeAudioRecorder.instance.cancel());
    }
    _inputFocusNode.removeListener(_onInputFocusChanged);
    _scrollController.removeListener(_onChatScroll);
    _inputFocusNode.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  NativeNovaMessage _welcomeMessage() {
    return NativeNovaMessage(
      id: 0,
      role: 'assistant',
      text: kNovaIntro,
      createdAt: DateTime.now(),
      isWelcome: true,
    );
  }

  List<NativeNovaMessage> _withWelcome(List<NativeNovaMessage> rows) {
    if (rows.any((m) => m.isWelcome)) return rows;
    if (rows.isEmpty) return [_welcomeMessage()];
    return rows;
  }

  Future<void> _loadUserAvatar() async {
    final cached = userAvatarRefresh.snapshotFor(widget.session.userId);
    if (cached != null && mounted) {
      _applyAvatarSnapshot(cached);
      return;
    }
    try {
      final avatar = await _service.fetchCurrentUserAvatar();
      if (!mounted) return;
      final snapshot = UserAvatarSnapshot(
        userId: widget.session.userId,
        avatarPreset: avatar.avatarPreset,
        avatarObjectKey: avatar.avatarObjectKey,
        avatarUrl: avatar.avatarUrl,
      );
      userAvatarRefresh.remember(snapshot);
      _applyAvatarSnapshot(snapshot);
    } catch (_) {}
  }

  void _onSelfAvatarUpdated() {
    final snap = userAvatarRefresh.snapshotFor(widget.session.userId);
    if (snap == null || !mounted) return;
    _applyAvatarSnapshot(snap, forceRefresh: true);
  }

  void _applyAvatarSnapshot(
    UserAvatarSnapshot snap, {
    bool forceRefresh = false,
  }) {
    var url = snap.avatarUrl.trim();
    final objectKey = snap.avatarObjectKey.trim();
    if (url.isEmpty && objectKey.isNotEmpty) {
      url = _avatarService.mediaProxyUrl(objectKey, bucket: 'user-avatars');
    }
    final signature = snap.sourceSignature;
    if (forceRefresh || signature != _userAvatarSignature) {
      _userAvatarRefreshVersion += 1;
    }
    if (url.isNotEmpty) {
      url = _withAvatarRefreshToken(url, _userAvatarRefreshVersion);
    }
    setState(() {
      _userAvatarPreset = snap.avatarPreset;
      _userAvatarObjectKey = objectKey;
      _userAvatarUrl = url;
      _userAvatarSignature = signature;
    });
  }

  String _withAvatarRefreshToken(String url, int version) {
    if (url.isEmpty) return url;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}dunes_avatar_v=$version';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      NovaBackgroundCoordinator.instance.setNovaPageActive(false);
      unawaited(_flushOnAppBackground());
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    NovaBackgroundCoordinator.instance.setNovaPageActive(
      _isNovaChatTab,
      conversationId: _conversationId,
    );

    unawaited(_onAppResumed());
  }

  Future<void> _flushOnAppBackground() => _flushOnLeave();

  Future<void> _onAppResumed() async {
    if (!mounted || _conversationId <= 0) return;
    // PC 切换窗口也会 resumed。活跃请求继续更新当前气泡，无需用旧历史恢复。
    if (_service.isPersonalQueryInFlight ||
        _service.isReplyInFlightFor(_conversationId))
      return;
    final conversationId = _conversationId;
    final requestToken = _loadToken;
    final messagesBeforeResume = _messages;
    final storage = await NovaWebStorage.load(widget.session.userId);
    if (!mounted ||
        requestToken != _loadToken ||
        !identical(_messages, messagesBeforeResume) ||
        conversationId != _conversationId ||
        _service.isPersonalQueryInFlight ||
        _service.isReplyInFlightFor(_conversationId)) {
      return;
    }
    final draft = readNovaStreamDraftFromStorage(storage, _conversationId);
    final localGen = readNovaGeneratingFromStorage(
      storage,
      convId: _conversationId,
      activeConvId: _conversationId,
    );
    final hadActiveGeneration =
        _isGenerating || _service.isReplyInFlightFor(_conversationId);
    final draftRecoverable =
        draft != null &&
        novaStreamDraftHasContent(draft) &&
        !_hasAiReplyAfter(_messages, draft.afterMessageId);

    if (!hadActiveGeneration && !draftRecoverable && localGen == null) return;

    try {
      final history = await _service.fetchFullHistory(_conversationId);
      if (!mounted ||
          requestToken != _loadToken ||
          !identical(_messages, messagesBeforeResume) ||
          conversationId != _conversationId ||
          _service.isPersonalQueryInFlight ||
          _service.isReplyInFlightFor(_conversationId)) {
        return;
      }
      if (!history.serverStateKnown) {
        setState(() => _banner = '网络暂时不可用，恢复后会继续确认回复状态');
        return;
      }
      final resolved = _resolveGeneratingState(
        msgs: history.messages,
        serverGenerating: history.assistantGenerating,
        generatingStatus: history.generatingStatus,
        generatingAfter: history.generatingAfterMessageId,
        localGen: localGen,
        draft: draft,
      );
      var generating = resolved.generating;
      if (generating) {
        NovaBackgroundCoordinator.instance.ensurePoll(
          widget.session,
          conversationId: _conversationId,
        );
        _startGeneratingPoll();
      }
      setState(() {
        _genAfterMessageId = resolved.afterMessageId > 0
            ? resolved.afterMessageId
            : (draft?.afterMessageId ?? _genAfterMessageId);
        _messages = _mergeGeneratingAndDraft(
          rows: _withWelcome(history.messages),
          generating: generating,
          status: resolved.status.isNotEmpty
              ? resolved.status
              : (draft?.status ?? kNovaInputBusyHint),
          afterMessageId: _genAfterMessageId,
          draft: draft,
        );
        _serverGenerating = generating;
        _sending = false;
        _busyHint = generating
            ? (resolved.status.isNotEmpty
                  ? resolved.status
                  : (draft?.status ?? kNovaInputBusyHint))
            : '';
      });
      _markCurrentReplyRead();
      if (generating) {
        if (_service.isReplyInFlightFor(_conversationId)) {
          _startStreamDraftWatcher();
        } else {
          unawaited(_pollGenerating());
        }
      } else {
        _stopGeneratingPoll();
        _stopStreamDraftWatcher();
      }
    } catch (_) {
      if (!mounted ||
          requestToken != _loadToken ||
          !identical(_messages, messagesBeforeResume) ||
          conversationId != _conversationId ||
          _service.isPersonalQueryInFlight ||
          _service.isReplyInFlightFor(_conversationId) ||
          !draftRecoverable) {
        return;
      }
      final recoverDraft = draft;
      setState(() {
        _messages = _mergeGeneratingAndDraft(
          rows: _messages,
          generating: true,
          status: recoverDraft.status.isNotEmpty
              ? recoverDraft.status
              : kNovaInputBusyHint,
          afterMessageId: recoverDraft.afterMessageId > 0
              ? recoverDraft.afterMessageId
              : _genAfterMessageId,
          draft: recoverDraft,
        );
        _serverGenerating = true;
        _sending = false;
        _busyHint = '正在恢复回复…';
        _banner = '暂时无法确认生成状态，请联网后重试';
      });
      _startGeneratingPoll();
    }
  }

  void _markCurrentReplyRead() {
    if (!_isNovaChatTab || _conversationId <= 0) return;
    final user = _messages.where((m) => m.role == 'user').lastOrNull;
    if (user != null &&
        novaHasReplyForDraft(_messages, afterMessageId: user.id)) {
      NovaBackgroundCoordinator.instance.markReplySeen(_conversationId);
      if (_loadedSourceConversationId > 0 &&
          _loadedSourceConversationId != _conversationId) {
        NovaBackgroundCoordinator.instance.markReplySeen(
          _loadedSourceConversationId,
        );
      }
    }
  }

  Future<void> _loadModels() async {
    try {
      final payload = await NovaModelsService().fetchModels(
        apiBase: widget.session.apiBase,
        token: widget.session.token,
      );
      if (!mounted) return;
      final uid = widget.session.userId;
      final webStorage = uid > 0
          ? await NovaWebStorage.load(uid)
          : const <String, String>{};
      final stored =
          (webStorage['dunes_nova_chat_model'] ??
                  widget.session.novaLocalStorage?['dunes_nova_chat_model'])
              ?.trim();
      final selected =
          (stored != null &&
              stored.isNotEmpty &&
              payload.chatModels.contains(stored))
          ? stored
          : payload.defaultModel;
      _service.setSelectedChatModel(selected);
      _service.setAvailableChatModels(payload.chatModels);
      setState(() {
        _chatModels = payload.chatModels;
        _selectedModel = selected;
        _modelCatalog = payload.modelCatalog;
      });
    } catch (_) {
      if (!mounted) return;
      final fallback = _service.selectedModel;
      setState(() {
        _chatModels = fallback.isEmpty ? const <String>[] : [fallback];
        _selectedModel = fallback;
      });
    }
  }

  Future<void> _load({int? targetConversationId}) async {
    final loadToken = ++_loadToken;
    setState(() {
      _loading = true;
      _banner = null;
      _busyHint = '';
      _serverGenerating = false;
    });
    _stopGeneratingPoll();
    // 历史恢复不等待模型目录和头像网络请求，先让会话可见。
    unawaited(_loadModels());
    unawaited(_loadUserAvatar());
    if (!mounted || loadToken != _loadToken) return;
    try {
      final readiness = await _service.checkReadiness();
      if (!mounted || loadToken != _loadToken) return;
      await _service.sanitizeNovaConvStorage();
      // 对齐 WebView onScreen(C4)：重试历史同步队列。
      unawaited(_service.flushHistorySyncQueue());

      var convId = 0;
      List<NativeNovaMessage> msgs = const <NativeNovaMessage>[];
      String? banner;
      var serverGenerating = false;
      var generatingStatus = '';
      var generatingAfter = 0;

      if (!readiness.ready) {
        banner = readiness.message ?? '小饕暂时无法发送新消息，仍可查看已有回复';
      }
      final focusedConvId =
          targetConversationId ??
          widget.focusConversationId ??
          ((widget.initialPrompt?.trim().isEmpty ?? true)
              ? NovaBackgroundCoordinator.instance.latestUnreadConversationId
              : null) ??
          0;
      if (focusedConvId > 0) {
        convId = focusedConvId;
        try {
          final ensured = await _service.sessionEnsure(
            legacyConversationId: focusedConvId,
          );
          if (ensured.conversationId > 0) convId = ensured.conversationId;
        } catch (_) {
          // 服务端暂时不可达时，仍使用提醒对应的本地会话读取已保存内容。
        }
        if (kDebugMode) {
          debugPrint(
            '[NativeNovaPage] open focused legacy=$focusedConvId canonical=$convId',
          );
        }
      } else {
        convId = await _service.ensureConversation();
      }

      NovaStreamDraft? streamDraft;
      Map<String, String> novaStorage = const {};
      if (convId > 0) {
        novaStorage = await NovaWebStorage.load(widget.session.userId);
        // 对齐 WebView onScreen(C4)：有 convId 时清除 view-since，展示完整历史。
        await NovaWebStorage.removeKeys(widget.session.userId, [
          'dunes_nova_view_since',
        ]);
        novaStorage = await NovaWebStorage.load(widget.session.userId);
        try {
          final focusId = widget.focusMessageId;
          final history = await _service.fetchFullHistory(
            convId,
            aroundMessageId: focusId != null && focusId > 0 ? focusId : null,
            restoreFromHistory: focusedConvId > 0,
          );
          msgs = history.messages;
          serverGenerating = history.assistantGenerating;
          generatingStatus = history.generatingStatus;
          generatingAfter = history.generatingAfterMessageId;
          // 历史页也顺手回填一次审计，修复旧版本用临时 ID 写入的缺失轮次。
          if (!serverGenerating && msgs.isNotEmpty) {
            unawaited(_service.syncCanonicalHistoryTurns(convId));
          }
        } catch (e) {
          final hint = NativeNovaService.friendlyError(e);
          if (hint.isNotEmpty) banner ??= hint;
        }
        streamDraft = readNovaStreamDraftFromStorage(novaStorage, convId);
        final localGen = readNovaGeneratingFromStorage(
          novaStorage,
          convId: convId,
          activeConvId: convId,
        );
        final resolved = _resolveGeneratingState(
          msgs: msgs,
          conversationId: convId,
          serverGenerating: serverGenerating,
          generatingStatus: generatingStatus,
          generatingAfter: generatingAfter,
          localGen: localGen,
          draft: streamDraft,
        );
        serverGenerating = resolved.generating;
        generatingStatus = resolved.status;
        generatingAfter = resolved.afterMessageId;
        if (resolved.clearLocal) {
          unawaited(
            clearNovaGeneratingState(
              userId: widget.session.userId,
              conversationId: convId,
            ),
          );
          unawaited(_service.stripStreamingFromSession(convId));
        } else if (!serverGenerating) {
          unawaited(_service.stripStreamingFromSession(convId));
        }
        if (!serverGenerating && _service.isReplyInFlightFor(convId)) {
          serverGenerating = true;
          if (generatingStatus.isEmpty) generatingStatus = kNovaInputBusyHint;
        }
      }

      if (!mounted || loadToken != _loadToken) return;
      setState(() {
        _novaReady = readiness.ready;
        _conversationId = convId;
        _loadedSourceConversationId = focusedConvId;
        _genAfterMessageId = generatingAfter;
        _messages = _mergeGeneratingAndDraft(
          rows: _withWelcome(msgs),
          generating: serverGenerating,
          status: generatingStatus,
          afterMessageId: generatingAfter,
          draft: streamDraft,
        );
        _serverGenerating = serverGenerating;
        _sending = false;
        _busyHint = serverGenerating
            ? (generatingStatus.isNotEmpty
                  ? generatingStatus
                  : kNovaInputBusyHint)
            : '';
        _banner = banner;
        _analysisSources = convId > 0
            ? decodeNovaConversationScope(
                novaStorage[novaKbScopeStorageKey(convId)],
              )
            : const <NovaAnalysisSource>[];
        _loading = false;
      });
      _restorePendingTaskPreview();
      final foreground =
          WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
      NovaBackgroundCoordinator.instance.setNovaPageActive(
        foreground && _isNovaChatTab,
        conversationId: convId,
      );
      if (foreground) _markCurrentReplyRead();
      if (serverGenerating) {
        if (_service.isReplyInFlightFor(_conversationId)) {
          NovaBackgroundCoordinator.instance.stopPoll(
            conversationId: _conversationId,
          );
          _startStreamDraftWatcher();
        } else {
          NovaBackgroundCoordinator.instance.ensurePoll(
            widget.session,
            conversationId: convId,
          );
        }
        _startGeneratingPoll();
        unawaited(_pollGenerating());
      }
      // 旧会话首次打开时补建；新会话则会立即持久化，后续请求始终复用此 UUID。
      if (convId > 0) {
        unawaited(_service.novaChatSessionId(convId));
      }
      unawaited(_maybeResumePrdGeneration());
      final initialPrompt = widget.initialPrompt?.trim() ?? '';
      if (initialPrompt.isNotEmpty && !_initialPromptConsumed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_novaReady || _initialPromptConsumed) return;
          _initialPromptConsumed = true;
          widget.onInitialPromptConsumed?.call();
          _inputController.text = initialPrompt;
          // 已有任务正在恢复时保留为输入草稿，不把预填问题当成“停止生成”。
          if (!_isGenerating) unawaited(_submitInput());
        });
      }
      final focusId = widget.focusMessageId;
      if (focusId != null && focusId > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _focusMessage(focusId),
        );
      } else {
        if (_isEmptyConversation) {
          _scrollTop();
        } else {
          _scrollBottom();
        }
      }
    } catch (e) {
      if (!mounted || loadToken != _loadToken) return;
      setState(() {
        _novaReady = true;
        _conversationId = 0;
        _messages = [_welcomeMessage()];
        _analysisSources = const <NovaAnalysisSource>[];
        _banner = NativeNovaService.friendlyError(e);
        _loading = false;
      });
    }
  }

  /// 对齐 WebView `applyNovaGeneratingState`：仅以服务端标记 + 本地持久化 generating 为准。
  ({bool generating, String status, int afterMessageId, bool clearLocal})
  _resolveGeneratingState({
    required List<NativeNovaMessage> msgs,
    required bool serverGenerating,
    required String generatingStatus,
    required int generatingAfter,
    NovaGeneratingState? localGen,
    NovaStreamDraft? draft,
    int? conversationId,
  }) {
    final after = generatingAfter > 0
        ? generatingAfter
        : (localGen?.afterMessageId ?? draft?.afterMessageId ?? 0);
    return resolveNovaGeneratingState(
      serverGenerating: serverGenerating,
      streamInFlight: _service.isReplyInFlightFor(
        conversationId ?? _conversationId,
      ),
      status: generatingStatus,
      afterMessageId: after,
      localGen: localGen,
      draft: draft,
      hasAiReplyAfter: novaHasReplyForDraft(
        msgs,
        afterMessageId: after,
        draft: draft,
      ),
    );
  }

  List<NativeNovaMessage> _finalizeMergedMessages(
    List<NativeNovaMessage> rows, {
    bool repair = true,
  }) {
    final deduped = dedupeNovaHistoryMessages(rows);
    return collapseNovaStreamingPlaceholders(
      repairNovaConversationMessages(deduped),
    );
  }

  List<NativeNovaMessage> _mergeGeneratingAndDraft({
    required List<NativeNovaMessage> rows,
    required bool generating,
    required String status,
    required int afterMessageId,
    NovaStreamDraft? draft,
  }) {
    var out = [...rows];
    final effectiveAfter = afterMessageId > 0
        ? afterMessageId
        : (draft?.afterMessageId ?? 0);
    final draftUserText = (draft?.userText ?? '').trim();

    if (draftUserText.isNotEmpty && effectiveAfter > 0) {
      // 后端 IM 分配的 message ID 与前端临时 afterMessageId 不同。重入
      // 流式会话时，只要当前会话已有同文本用户消息就不能再插入一次。
      final hasUser =
          out.any(
            (m) =>
                m.role == 'user' &&
                (m.text.trim() == draftUserText ||
                    isNovaPrdDisplayAndPromptPair(m.text, draftUserText)),
          ) ||
          novaHasMatchingUserMessage(
            out,
            afterMessageId: effectiveAfter,
            userText: draftUserText,
          );
      if (!hasUser) {
        final userMsg = NativeNovaMessage(
          id: effectiveAfter,
          role: 'user',
          text: draftUserText,
          createdAt: DateTime.fromMillisecondsSinceEpoch(effectiveAfter),
          kind: 'TEXT',
        );
        var insertAt = out.length;
        for (var i = 0; i < out.length; i++) {
          final m = out[i];
          if (m.isWelcome) continue;
          final key = m.createdAt?.millisecondsSinceEpoch ?? m.id;
          if (key > effectiveAfter) {
            insertAt = i;
            break;
          }
        }
        out.insert(insertAt, userMsg);
      }
    }

    if (!generating) {
      return _finalizeMergedMessages(
        recoverNovaInterruptedDraft(
          out,
          draft: draft,
          afterMessageId: effectiveAfter,
        ),
        repair: true,
      );
    }

    final draftText = draft?.text ?? '';
    final draftThink = draft?.thinkText ?? '';
    final draftStatus = (draft?.status ?? '').trim();
    final thinkStatus = draftStatus.isNotEmpty
        ? draftStatus
        : (status.isNotEmpty ? status : '正在生成…');

    final streamingIdx = out.indexWhere(
      (m) => m.role == 'assistant' && m.streaming,
    );
    if (streamingIdx >= 0) {
      final current = out[streamingIdx];
      out[streamingIdx] = current.copyWith(
        text: draftText.isNotEmpty ? draftText : current.text,
        thinkText: draftThink.isNotEmpty ? draftThink : current.thinkText,
        thinkStatus: thinkStatus,
        streaming: true,
      );
      return _finalizeMergedMessages(out);
    }

    if (effectiveAfter > 0 && _hasAiReplyAfter(out, effectiveAfter)) {
      return _finalizeMergedMessages(out, repair: true);
    }

    final pendingId = effectiveAfter > 0
        ? effectiveAfter + 1
        : DateTime.now().millisecondsSinceEpoch + 1;
    out.add(
      NativeNovaMessage(
        id: pendingId,
        role: 'assistant',
        text: draftText,
        thinkText: draftThink,
        createdAt: DateTime.now(),
        streaming: true,
        thinkStatus: thinkStatus,
        kind: 'AI_ASSISTANT',
      ),
    );
    return _finalizeMergedMessages(out);
  }

  bool _hasAiReplyAfter(List<NativeNovaMessage> rows, int afterMessageId) {
    var seen = false;
    for (final m in rows) {
      if (m.isWelcome) continue;
      if (m.id == afterMessageId) {
        seen = true;
        continue;
      }
      if (!seen) continue;
      if (m.streaming) continue;
      if (m.role == 'assistant' && m.text.trim().isNotEmpty) return true;
    }
    return false;
  }

  /// 可落盘的消息：去掉欢迎语。
  List<NativeNovaMessage> _persistableMessages() =>
      _messages.where((m) => !m.isWelcome).toList(growable: false);

  Future<void> _persistSessionNow() async {
    if (_conversationId <= 0) return;
    final rows = _persistableMessages();
    if (rows.isEmpty) return;
    await _service.persistSession(_conversationId, rows);
  }

  Future<void> _markGenerating({
    required String status,
    required int afterMessageId,
  }) async {
    if (_conversationId <= 0) return;
    _genAfterMessageId = afterMessageId;
    await persistNovaGeneratingState(
      userId: widget.session.userId,
      conversationId: _conversationId,
      status: status,
      afterMessageId: afterMessageId,
    );
  }

  Future<void> _clearGeneratingMarkers() async {
    if (_conversationId <= 0) return;
    await clearNovaGeneratingState(
      userId: widget.session.userId,
      conversationId: _conversationId,
    );
  }

  /// 流式结束：无论页面是否仍 mounted，都清理 generating 并落盘（对齐 WebView 后台流结束）。
  Future<void> _completeAssistantStream({
    required int assistantMsgId,
    bool skipUserBubble = false,
    String replyText = '',
    int? conversationId,
    int? requestToken,
    int localUserMsgId = 0,
    int serverUserMsgId = 0,
    int serverAssistantMsgId = 0,
  }) async {
    // 服务端已回传本轮真实 ID：说明 im-svc 已把问答落库，客户端不再补写。
    final serverPersisted = serverAssistantMsgId > 0;
    List<NativeNovaMessage> alignIds(List<NativeNovaMessage> input) =>
        remapNovaTurnMessageIds(
          input,
          localUserId: localUserMsgId,
          serverUserId: serverUserMsgId,
          localAssistantId: assistantMsgId,
          serverAssistantId: serverAssistantMsgId,
        );
    final convId = conversationId ?? _conversationId;
    bool isCurrentCompletion() =>
        mounted && (requestToken == null || requestToken == _loadToken);
    if (convId > 0) {
      await clearNovaGeneratingState(
        userId: widget.session.userId,
        conversationId: convId,
      );
    }
    if (requestToken != null && !isCurrentCompletion()) return;
    var thinkText = '';
    if (isCurrentCompletion()) {
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == assistantMsgId);
        if (idx >= 0) {
          final copy = [..._messages];
          final cur = copy[idx];
          thinkText = cur.thinkText;
          final doneThink = cur.thinkText.trim().isNotEmpty;
          copy[idx] = cur.copyWith(
            streaming: false,
            text: replyText.isNotEmpty ? replyText : cur.text,
            thinkStatus: doneThink ? '已完成思考' : '',
          );
          _messages = sortNovaMessages(copy);
        }
      });
      _releaseGeneratingUi(clearStreamingFlags: false);
      if (serverUserMsgId > 0 || serverAssistantMsgId > 0) {
        setState(() => _messages = alignIds(_messages));
      }
      if (serverUserMsgId > 0) _genAfterMessageId = serverUserMsgId;
    }

    final reply = replyText.trim();
    List<NativeNovaMessage> rows;
    if (isCurrentCompletion()) {
      rows = _messages.where((m) => !m.isWelcome).toList(growable: false);
    } else {
      try {
        rows = alignIds((await _service.fetchFullHistory(convId)).messages);
        if (requestToken != null && !isCurrentCompletion()) return;
        if (reply.isNotEmpty &&
            !rows.any((m) => m.role == 'assistant' && m.text.trim() == reply)) {
          await _service.commitAssistantReplyToSession(
            convId,
            replyText: reply,
            thinkText: thinkText,
          );
          if (requestToken != null && !isCurrentCompletion()) return;
          rows = alignIds((await _service.fetchFullHistory(convId)).messages);
          if (requestToken != null && !isCurrentCompletion()) return;
        }
      } catch (_) {
        rows = const <NativeNovaMessage>[];
      }
    }
    // 发完后从 IM 刷新一次：服务端为本轮分配的真实消息 ID 才是审计 upsert
    // 的主键。这样重发/连续同文案不会把客户端临时 ID 写进工作台。
    // 先把对齐后的消息写回本地缓存：审计补登会合并本地缓存，留着临时 ID 的
    // 副本会被当成另一轮写进审计表，重进会话就变成两条。
    if (convId > 0 && rows.isNotEmpty && (serverUserMsgId > 0 || serverPersisted)) {
      await _service.persistSession(convId, rows);
      if (requestToken != null && !isCurrentCompletion()) return;
    }
    if (convId > 0 && reply.isNotEmpty) {
      try {
        final canonicalRows = await _service.syncCanonicalHistoryTurns(convId);
        if (requestToken != null && !isCurrentCompletion()) return;
        if (canonicalRows.isNotEmpty) {
          final syncHasReply = canonicalRows.any(
            (m) =>
                m.role == 'assistant' &&
                !m.streaming &&
                m.text.trim().isNotEmpty &&
                ((serverPersisted && m.id == serverAssistantMsgId) ||
                    m.text.trim() == reply ||
                    (reply.length >= 24 &&
                        m.text.contains(reply.substring(0, 24)))),
          );
          if (syncHasReply) {
            rows = repairNovaConversationMessages(canonicalRows);
            if (isCurrentCompletion()) {
              setState(() {
                _messages = _withWelcome(rows);
              });
            }
          } else if (serverPersisted) {
            // 服务端已落库（有真实回复 ID），只是本次快照没带上：保留本地气泡，
            // 不再补写 IM/审计，否则服务端会多出一条重复的提问和回复。
          } else {
            // IM 尚未回显本轮（PRD / 慢落库常见）：保留本地气泡并强制写 IM+审计，
            // 避免用旧快照冲掉刚生成的回复，导致「对话记录看不到」。
            if (kDebugMode) {
              debugPrint(
                '[NativeNovaPage] IM sync missing latest reply, '
                'force-persist turn conv=$convId',
              );
            }
            await _registerLastTurnFromRows(
              rows,
              conversationId: convId,
              userMsgId: _genAfterMessageId > 0 ? _genAfterMessageId : null,
              fallbackAssistantText: reply,
              fallbackThinkText: thinkText,
            );
            if (requestToken != null && !isCurrentCompletion()) return;
          }
        } else if (!serverPersisted) {
          await _registerLastTurnFromRows(
            rows,
            conversationId: convId,
            userMsgId: _genAfterMessageId > 0 ? _genAfterMessageId : null,
            fallbackAssistantText: reply,
            fallbackThinkText: thinkText,
          );
          if (requestToken != null && !isCurrentCompletion()) return;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[NativeNovaPage] canonical history sync skipped: $e');
        }
        // 服务端已落库时，审计轮次会在下次进入会话时按服务端 ID 补齐。
        if (!serverPersisted) {
          try {
            await _registerLastTurnFromRows(
              rows,
              conversationId: convId,
              userMsgId: _genAfterMessageId > 0 ? _genAfterMessageId : null,
              fallbackAssistantText: reply,
              fallbackThinkText: thinkText,
            );
            if (requestToken != null && !isCurrentCompletion()) return;
          } catch (_) {}
        }
      }
    }
    if (requestToken != null && !isCurrentCompletion()) return;
    if (convId > 0 && rows.isNotEmpty) {
      await _service.persistSession(convId, rows);
      unawaited(_service.flushConvToLocalHistory(convId, rows));
    }
    if (convId > 0) {
      final replyVisible = NovaBackgroundCoordinator.instance
          .isConversationVisible(convId);
      if (replyVisible) {
        NovaBackgroundCoordinator.instance.stopPoll(
          conversationId: _conversationId,
        );
        NovaBackgroundCoordinator.instance.markReplySeen(convId);
      } else {
        await NovaBackgroundCoordinator.instance.onGenerationComplete(
          session: widget.session,
          conversationId: convId,
          messages: rows,
        );
      }
      NovaBackgroundCoordinator.instance.notifyInboxRefresh();
    }
  }

  /// 流式结束或轮询确认完成后，统一释放 UI / 本地 generating 状态。
  void _releaseGeneratingUi({bool clearStreamingFlags = true}) {
    _stopGeneratingPoll();
    _stopStreamDraftWatcher();
    if (!mounted) return;
    setState(() {
      _serverGenerating = false;
      _sending = false;
      _busyHint = '';
      if (clearStreamingFlags) {
        _messages = [
          for (final m in _messages)
            if (m.streaming) m.copyWith(streaming: false) else m,
        ];
      }
    });
  }

  bool _hasActiveAssistantStream() {
    return _messages.any((m) => m.role == 'assistant' && m.streaming);
  }

  /// 是否处于生成中（本地发送 / 服务端生成 / 本地流式任一为真）。
  /// 与 `_flushOnLeave` 口径一致，确保退出重进后按钮仍按生成态禁用。
  bool get _isGenerating =>
      _sending || _serverGenerating || _hasActiveAssistantStream();

  bool _isStoppedStatus(String status) => status.trim().contains('停止');

  Future<void> _flushOnLeave() {
    final existing = _leaveFlush;
    if (existing != null) return existing;
    final operation = _flushLeavingConversation();
    _leaveFlush = operation;
    return operation.whenComplete(() {
      if (identical(_leaveFlush, operation)) _leaveFlush = null;
    });
  }

  Future<void> _flushLeavingConversation() async {
    // 所有字段在第一次 await 前固定，避免切换会话后将旧草稿写进新会话。
    final convId = _conversationId;
    if (convId <= 0) return;
    final uid = widget.session.userId;
    final rows = _persistableMessages();
    final user = rows.where((m) => m.role == 'user').lastOrNull;
    final assistant = rows
        .where((m) => m.role == 'assistant' && m.streaming)
        .lastOrNull;
    final after = _genAfterMessageId > 0 ? _genAfterMessageId : user?.id ?? 0;
    final userText = _lastUserDisplayText.isNotEmpty
        ? _lastUserDisplayText
        : user?.text ?? '';
    final status = _busyHint.isNotEmpty ? _busyHint : kNovaInputBusyHint;
    final stopped = _service.wasStoppedFor(convId) || _isStoppedStatus(status);
    final active =
        !stopped && (_isGenerating || _service.isReplyInFlightFor(convId));
    final hadLocalRequest = _service.isReplyInFlightFor(convId);
    final prdSendStarted = _prdNovaSendStarted;
    try {
      if (rows.isNotEmpty) await _service.persistSession(convId, rows);
      await _service.persistActiveConversationId(convId);
      if (stopped) {
        await persistNovaGeneratingState(
          userId: uid,
          conversationId: convId,
          status: '已停止生成',
          afterMessageId: after,
        );
        await clearNovaStreamDraftState(userId: uid, conversationId: convId);
      } else if (active &&
          (!hadLocalRequest || _service.isReplyInFlightFor(convId))) {
        final storage = await NovaWebStorage.load(uid);
        final prdJob = readNovaPrdPendingJob(storage, convId);
        if (prdJob != null && !prdSendStarted) {
          await persistNovaPrdPendingJob(
            userId: uid,
            conversationId: convId,
            job: prdJob,
          );
        } else {
          await persistNovaGeneratingState(
            userId: uid,
            conversationId: convId,
            status: status,
            afterMessageId: after,
          );
          await persistNovaStreamDraftState(
            userId: uid,
            conversationId: convId,
            status: status,
            afterMessageId: after,
            userText: userText,
            thinkText: assistant?.thinkText ?? '',
            text: assistant?.text ?? '',
            streaming: true,
          );
          NovaBackgroundCoordinator.instance.ensurePoll(
            widget.session,
            conversationId: convId,
          );
        }
      } else if (active) {
        // 原请求恰好在离开过程中完成：交给历史确认，不能重新写入旧生成标记。
        NovaBackgroundCoordinator.instance.ensurePoll(
          widget.session,
          conversationId: convId,
        );
      }
      if (rows.isNotEmpty) await _service.flushConvToLocalHistory(convId, rows);
    } catch (_) {
      // 页面离开不能被临时缓存/网络错误阻塞；服务端生成不依赖页面存在。
    }
  }

  /// 对齐 WebView `persistNovaAssistantReply` → `registerNovaHistoryTurn`。
  Future<void> _registerLastTurnIfComplete({int? userMsgId}) async {
    if (_conversationId <= 0) return;
    final rows = _messages.where((m) => !m.isWelcome).toList(growable: false);
    await _registerLastTurnFromRows(rows, userMsgId: userMsgId);
  }

  Future<void> _registerLastTurnFromRows(
    List<NativeNovaMessage> rows, {
    int? conversationId,
    int? userMsgId,
    String fallbackUserText = '',
    String fallbackAssistantText = '',
    String fallbackThinkText = '',
  }) async {
    if (rows.isEmpty && fallbackAssistantText.trim().isEmpty) return;
    final convId = conversationId ?? _conversationId;
    final afterMessageId = userMsgId ?? _genAfterMessageId;
    final lastUserText = _lastUserDisplayText;

    NativeNovaMessage? assistant;
    NativeNovaMessage? user;
    for (var i = rows.length - 1; i >= 0; i--) {
      final m = rows[i];
      if (assistant == null &&
          m.role == 'assistant' &&
          !m.streaming &&
          m.text.trim().isNotEmpty) {
        assistant = m;
      } else if (user == null && m.role == 'user') {
        user = m;
      }
      if (assistant != null && user != null) break;
    }

    final effectiveUser = await _resolveHistoryUser(
      rows,
      preferred: user,
      conversationId: convId,
      fallbackUserText: fallbackUserText.isNotEmpty
          ? fallbackUserText
          : lastUserText,
    );
    if (effectiveUser == null) return;

    var assistantText = (assistant?.text ?? '').trim();
    if (assistantText.isEmpty || assistantText == effectiveUser.text.trim()) {
      assistantText = fallbackAssistantText.trim();
    }
    if (assistantText.isEmpty) return;

    await _service.persistAssistantTurn(
      conversationId: convId,
      messageId: afterMessageId > 0
          ? afterMessageId
          : (effectiveUser.id > 0
                ? effectiveUser.id
                : DateTime.now().millisecondsSinceEpoch),
      userMessage: effectiveUser.text,
      assistantMessage: assistantText,
      thinkText: assistant?.thinkText ?? fallbackThinkText,
      userPayload:
          effectiveUser.payload != null || effectiveUser.attachments.isNotEmpty
          ? _service.historyUserPayloadFromMessage(effectiveUser)
          : effectiveUser.payload,
      existingMessages: rows,
    );
  }

  Future<NativeNovaMessage?> _resolveHistoryUser(
    List<NativeNovaMessage> rows, {
    NativeNovaMessage? preferred,
    int? conversationId,
    String fallbackUserText = '',
  }) async {
    final convId = conversationId ?? _conversationId;
    bool usable(NativeNovaMessage m) =>
        m.role == 'user' &&
        (m.text.trim().isNotEmpty || m.attachments.isNotEmpty);
    if (preferred != null && usable(preferred)) return preferred;
    for (var i = rows.length - 1; i >= 0; i--) {
      final m = rows[i];
      if (usable(m)) return m;
    }
    if (convId > 0) {
      final storage = await NovaWebStorage.load(widget.session.userId);
      final draft = readNovaStreamDraftFromStorage(storage, convId);
      final text = (draft?.userText ?? fallbackUserText).trim();
      if (text.isNotEmpty) {
        return NativeNovaMessage(
          id: draft?.afterMessageId ?? _genAfterMessageId,
          role: 'user',
          text: text,
          createdAt: DateTime.now(),
        );
      }
    }
    return null;
  }

  void _startGeneratingPoll() {
    if (_genPollTimer != null || _conversationId <= 0) return;
    _genPollTimer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) => _pollGenerating(),
    );
  }

  void _stopGeneratingPoll() {
    _genPollTimer?.cancel();
    _genPollTimer = null;
  }

  /// 后台 SSE 仍在跑时，周期性从 storage 拉草稿恢复 UI。
  void _startStreamDraftWatcher() {
    _streamDraftTimer?.cancel();
    _streamDraftTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      unawaited(_syncStreamDraftFromStorage());
    });
  }

  void _stopStreamDraftWatcher() {
    _streamDraftTimer?.cancel();
    _streamDraftTimer = null;
  }

  Future<void> _syncStreamDraftFromStorage() async {
    if (!mounted || _conversationId <= 0 || _sending) return;
    final convId = _conversationId;
    final token = _loadToken;
    final storage = await NovaWebStorage.load(widget.session.userId);
    if (!mounted ||
        token != _loadToken ||
        convId != _conversationId ||
        _sending)
      return;
    if (!_service.isReplyInFlightFor(convId)) {
      _stopStreamDraftWatcher();
      unawaited(_pollGenerating());
      return;
    }
    final draft = readNovaStreamDraftFromStorage(storage, convId);
    if (draft == null) return;
    setState(() {
      _busyHint = draft.status.isNotEmpty ? draft.status : kNovaInputBusyHint;
      _messages = _mergeGeneratingAndDraft(
        rows: _messages,
        generating: true,
        status: _busyHint,
        afterMessageId: draft.afterMessageId,
        draft: draft,
      );
    });
    _scrollBottom(settle: false);
  }

  Future<void> _pollGenerating() async {
    if (!mounted ||
        _conversationId <= 0 ||
        !_serverGenerating ||
        _sending ||
        _service.isReplyInFlightFor(_conversationId) ||
        (_generationPollInFlight &&
            _generationPollConversation == _conversationId))
      return;
    final convId = _conversationId;
    final token = _loadToken;
    final messages = _messages;
    bool current() =>
        mounted &&
        token == _loadToken &&
        convId == _conversationId &&
        !_sending &&
        !_service.isReplyInFlightFor(convId) &&
        identical(messages, _messages);
    _generationPollInFlight = true;
    _generationPollConversation = convId;
    final pollEpoch = ++_generationPollEpoch;
    try {
      final history = await _service.fetchFullHistory(convId);
      if (!current() || !history.serverStateKnown) return;
      final storage = await NovaWebStorage.load(widget.session.userId);
      if (!current()) return;
      final draft = readNovaStreamDraftFromStorage(storage, convId);
      final localGen = readNovaGeneratingFromStorage(storage, convId: convId);
      final resolved = _resolveGeneratingState(
        msgs: history.messages,
        serverGenerating: history.assistantGenerating,
        generatingStatus: history.generatingStatus,
        generatingAfter: history.generatingAfterMessageId,
        localGen: localGen,
        draft: draft,
      );
      setState(() {
        _serverGenerating = resolved.generating;
        _busyHint = resolved.status;
        _genAfterMessageId = resolved.afterMessageId;
        _messages = _mergeGeneratingAndDraft(
          rows: _withWelcome(history.messages),
          generating: resolved.generating,
          status: resolved.status,
          afterMessageId: resolved.afterMessageId,
          draft: draft,
        );
      });
      if (!resolved.generating) {
        _restorePendingTaskPreview();
        _stopGeneratingPoll();
        _stopStreamDraftWatcher();
        if (localGen == null ||
            !isNovaStoppedGeneratingStatus(localGen.status)) {
          await clearNovaGeneratingState(
            userId: widget.session.userId,
            conversationId: convId,
          );
        }
        // 已确认有完整回复：清掉流式草稿，避免之后再被当成「回复已中断」补一条。
        if (draft != null &&
            novaHasReplyForDraft(
              history.messages,
              afterMessageId: draft.afterMessageId,
              draft: draft,
            )) {
          await clearNovaStreamDraftState(
            userId: widget.session.userId,
            conversationId: convId,
          );
        }
        if (!mounted || token != _loadToken || convId != _conversationId)
          return;
        await _service.persistSession(convId, _messages);
        NovaBackgroundCoordinator.instance.notifyInboxRefresh();
      }
      _scrollBottom(settle: !resolved.generating);
    } catch (_) {
      // 一次网络失败不等于任务完成；保持状态，下一次轮询继续确认。
    } finally {
      if (pollEpoch == _generationPollEpoch) _generationPollInFlight = false;
    }
  }

  Future<void> _focusMessage(int messageId) async {
    setState(() => _highlightMessageId = messageId);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    Future<void> ensureVisibleIfBuilt() async {
      final key = _messageKeys[messageId];
      final ctx = key?.currentContext;
      if (ctx == null) return;
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }

    await ensureVisibleIfBuilt();
    // ListView.builder 可能尚未构建目标项：先按序号粗定位，再精确 ensureVisible。
    if (_messageKeys[messageId]?.currentContext == null &&
        _scrollController.hasClients) {
      final items = _messageListItems();
      final idx = items.indexWhere((e) => e.message?.id == messageId);
      if (idx >= 0) {
        final pos = _scrollController.position;
        final denom = (items.length - 1).clamp(1, 1 << 30);
        final target = (idx / denom) * pos.maxScrollExtent;
        _scrollController.jumpTo(target.clamp(0.0, pos.maxScrollExtent));
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (!mounted) return;
        await ensureVisibleIfBuilt();
      }
    }

    Future<void>.delayed(const Duration(milliseconds: 2600), () {
      if (mounted && _highlightMessageId == messageId) {
        setState(() => _highlightMessageId = null);
      }
    });
  }

  Future<void> _ensureConversationId({int? requestToken}) async {
    if (_conversationId > 0) return;
    final conversationId = await _service.ensureConversation();
    if (requestToken != null && requestToken != _loadToken) return;
    _conversationId = conversationId;
  }

  Future<bool> _tryRecoverAssistantAfterSendFailure({
    required int userMsgId,
    required int assistantMsgId,
    int? requestToken,
  }) async {
    if (_conversationId <= 0) return false;
    final convId = _conversationId;
    try {
      final history = await _service.fetchFullHistory(convId);
      if (!mounted || (requestToken != null && requestToken != _loadToken))
        return false;
      if (history.assistantGenerating || !history.serverStateKnown) {
        setState(() {
          _sending = false;
          _serverGenerating = true;
          _busyHint = '正在恢复回复…';
        });
        _startGeneratingPoll();
        NovaBackgroundCoordinator.instance.ensurePoll(
          widget.session,
          conversationId: convId,
        );
        return true;
      }
      final storage = await NovaWebStorage.load(widget.session.userId);
      if (!mounted || (requestToken != null && requestToken != _loadToken))
        return false;
      if (!novaHasReplyForDraft(
        history.messages,
        afterMessageId: userMsgId,
        draft: readNovaStreamDraftFromStorage(storage, convId),
      ))
        return false;
      NativeNovaMessage? assistant;
      for (final m in history.messages.reversed) {
        if (m.isWelcome || m.role != 'assistant') continue;
        if (m.text.trim().isEmpty) continue;
        assistant = m;
        break;
      }
      if (assistant == null) return false;
      if (mounted) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == assistantMsgId);
          if (idx >= 0) {
            final copy = [..._messages];
            copy[idx] = assistant!.copyWith(
              id: assistantMsgId,
              streaming: false,
              thinkStatus: '',
            );
            _messages = copy;
          }
        });
      }
      await _completeAssistantStream(
        assistantMsgId: assistantMsgId,
        replyText: assistant.text,
        conversationId: convId,
        requestToken: requestToken,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _failAssistantTurnInChat({
    required int assistantMsgId,
    required String message,
    int? requestToken,
  }) async {
    if (requestToken != null && requestToken != _loadToken) return;
    final convId = _conversationId;
    final err = message.trim().isNotEmpty ? message.trim() : 'NOVA 请求失败，请稍后重试';
    if (mounted) {
      setState(() {
        _busyHint = '';
        final idx = _messages.indexWhere((m) => m.id == assistantMsgId);
        if (idx >= 0) {
          final copy = [..._messages];
          final cur = copy[idx];
          copy[idx] = cur.copyWith(
            text: cur.text.trim().isNotEmpty ? cur.text : '回复已中断，请重试',
            streaming: false,
            thinkStatus: '回复已中断',
            payload: {...?cur.payload, 'nova_retryable': true},
          );
          _messages = repairNovaConversationMessages(copy);
        }
        // 错误已在气泡（可重试）和 toast 中提示，不再额外挂常驻横幅。
      });
      _toast(err);
    }
    if (convId > 0) {
      await clearNovaGeneratingState(
        userId: widget.session.userId,
        conversationId: convId,
      );
    }
    if (requestToken != null && requestToken != _loadToken) return;
    if (convId > 0) {
      await clearNovaStreamDraftState(
        userId: widget.session.userId,
        conversationId: convId,
      );
      if (requestToken != null && requestToken != _loadToken) return;
      unawaited(_service.persistSession(convId, _messages));
    }
    _releaseGeneratingUi(clearStreamingFlags: false);
  }

  void _addDraft(NovaDraftAttachment draft) {
    setState(() => _drafts = [..._drafts, draft]);
  }

  void _removeDraft(String id) {
    setState(() => _drafts = _drafts.where((d) => d.id != id).toList());
  }

  Future<void> _pickCamera() async {
    if (!_novaReady || _isGenerating) return;
    if (!kIsWeb) {
      if (!await ensureCameraPermission()) {
        _toast(cameraPermissionHint(await Permission.camera.status));
        return;
      }
    }
    final picked = await _imagePicker.pickImage(source: ImageSource.camera);
    if (picked == null) return;
    await _addNovaImageDraft(picked, fallbackName: 'photo');
  }

  Future<void> _pickAlbum() async {
    if (!_novaReady || _isGenerating) return;
    if (!kIsWeb && !await ensurePhotosPermission()) {
      _toast(photosPermissionHint(await Permission.photos.status));
      return;
    }
    final picked = await _imagePicker.pickMultiImage();
    if (picked.isEmpty) return;
    final imageDrafts = <ChatImageDraft>[];
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      final fileName = file.name.isNotEmpty
          ? file.name
          : 'image-${DateTime.now().millisecondsSinceEpoch}.jpg';
      imageDrafts.add(ChatImageDraft(bytes: bytes, fileName: fileName));
    }
    if (!mounted || imageDrafts.isEmpty) return;

    // 与 IM 相同：多选时先进入预览页，可逐张编辑、删除后再确认。
    final confirmed = await openChatImageBatchPreview(
      context,
      drafts: imageDrafts,
    );
    if (!mounted || confirmed == null || confirmed.isEmpty) return;
    for (final draft in confirmed) {
      final fileName = draft.fileName;
      _addDraft(
        NovaDraftAttachment(
          id: 'draft-${++_draftSeq}',
          bytes: draft.bytes,
          fileName: fileName,
          mimeType: lookupMimeType(fileName) ?? 'image/jpeg',
          isImage: true,
        ),
      );
    }
  }

  /// NOVA 单张拍照与 IM 使用同一编辑器：涂鸦、文字、裁剪、马赛克。
  Future<void> _addNovaImageDraft(
    XFile file, {
    required String fallbackName,
  }) async {
    var bytes = await file.readAsBytes();
    var fileName = file.name.isNotEmpty
        ? file.name
        : '$fallbackName-${DateTime.now().millisecondsSinceEpoch}.jpg';
    var mimeType = lookupMimeType(fileName) ?? 'image/jpeg';
    if (!chatImageShouldSkipEditor(fileName: fileName, mimeType: mimeType)) {
      if (!mounted) return;
      final edited = await openChatImageEditor(context, bytes: bytes);
      if (edited == null || !mounted) return;
      bytes = edited;
      fileName = chatImageEditedFileName(fileName);
      mimeType = 'image/jpeg';
    }
    _addDraft(
      NovaDraftAttachment(
        id: 'draft-${++_draftSeq}',
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        isImage: true,
      ),
    );
  }

  Future<void> _pickFile() async {
    if (!_novaReady || _isGenerating) return;
    final file = await openFile();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final fileName = file.name;
    final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
    final isImage =
        mimeType.startsWith('image/') ||
        RegExp(
          r'\.(jpe?g|png|gif|webp|bmp|heic|heif)$',
          caseSensitive: false,
        ).hasMatch(fileName);
    if (!isImage) {
      final reject = novaChatAttachmentRejectReason(
        fileName: fileName,
        byteLength: bytes.length,
      );
      if (reject != null) {
        _toast(reject);
        return;
      }
    } else if (bytes.length > kNovaChatAttachmentMaxBytes) {
      _toast('文件超过 15MB，请压缩后再试');
      return;
    }
    _addDraft(
      NovaDraftAttachment(
        id: 'draft-${++_draftSeq}',
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        isImage: isImage,
      ),
    );
  }

  void _handlePromptCardTapped(String prompt) {
    if (!_novaReady || _isGenerating) return;
    HapticFeedback.selectionClick();
    _inputController.text = prompt;
    unawaited(_submitInput());
  }

  /// 任务和灯塔入口。查询由后端决定，结果写入当前小饕会话。
  /// [capability] 为 null 表示未选定板块：服务端先判断走灯塔、任务还是普通对话。
  Future<void> _handlePersonalCapability(
    NovaPersonalCapability capability,
    String prompt,
  ) async => _runPersonalCapability(capability, prompt);

  Future<void> _runPersonalCapability(
    NovaPersonalCapability? capability,
    String prompt, {
    NovaTaskPreview? pendingPreview,
  }) async {
    if (!_novaReady || _isGenerating) return;
    HapticFeedback.selectionClick();
    final session = widget.session;
    var turnConversationId = 0;
    final history = _personalContextHistory();
    // 必须在插入本轮提问之前判断：上一轮是否刚由灯塔回答（短追问继续查灯塔）。
    final afterLighthouse = capability == null && _lastTurnWasRecentLighthouse();
    final requestToken = ++_loadToken;
    final personalToken = ++_personalTurnToken;
    final userMsgId = DateTime.now().millisecondsSinceEpoch;
    final assistantMsgId = userMsgId + 1;
    final previousPreviewMessageId = _previewMessageId;
    final status = switch (capability) {
      null => '正在理解你的问题',
      NovaPersonalCapability.tasks => '正在查询你的任务',
      NovaPersonalCapability.lighthouse => '正在读取灯塔数据',
    };
    _lastUserDisplayText = prompt;
    _genAfterMessageId = userMsgId;
    _inputController.clear();
    setState(() {
      _sending = true;
      _busyHint = status;
      _quickActionsOpen = false;
      _stickToBottom = true;
      _showJumpToLatest = false;
      _messages = [
        ..._messages,
        NativeNovaMessage(
          id: userMsgId,
          role: 'user',
          text: prompt,
          createdAt: DateTime.now(),
          // 未选定板块时要等服务端判断后才知道走哪里，结果回来再写入。
          payload: capability == null
              ? null
              : <String, dynamic>{
                  'nova_personal_capability':
                      capability == NovaPersonalCapability.tasks
                      ? 'tasks'
                      : 'lighthouse',
                },
        ),
        NativeNovaMessage(
          id: assistantMsgId,
          role: 'assistant',
          text: '',
          createdAt: DateTime.now(),
          streaming: true,
          thinkStatus: status,
        ),
      ];
    });
    _scrollBottom();
    NovaPersonalReply result;
    var requestFailed = false;
    try {
      await _ensureConversationId(requestToken: requestToken);
      if (!mounted ||
          requestToken != _loadToken ||
          personalToken != _personalTurnToken)
        return;
      if (_conversationId <= 0) throw Exception('无法创建小饕会话，请稍后重试');
      turnConversationId = _conversationId;
      NovaBackgroundCoordinator.instance.clearFinalizedConversation(
        _conversationId,
      );
      void onProgress(String status) {
        if (!mounted ||
            requestToken != _loadToken ||
            personalToken != _personalTurnToken)
          return;
        setState(() {
          _busyHint = status;
          final index = _messages.indexWhere((m) => m.id == assistantMsgId);
          if (index >= 0 && _messages[index].streaming) {
            final copy = [..._messages];
            copy[index] = copy[index].copyWith(thinkStatus: status);
            _messages = copy;
          }
        });
      }

      result = capability == null
          ? await _service.askPersonalAuto(
              conversationId: _conversationId,
              userMessageId: userMsgId,
              existingMessages: List.of(_messages),
              text: prompt,
              history: novaPersonalContextTurns(history),
              lastQuery: _lastLighthouseState(),
              afterLighthouse: afterLighthouse,
              onProgress: onProgress,
            )
          : await _service.askPersonalCapability(
              conversationId: _conversationId,
              userMessageId: userMsgId,
              existingMessages: List.of(_messages),
              capability: capability == NovaPersonalCapability.tasks
                  ? 'tasks'
                  : 'lighthouse',
              text: prompt,
              history: novaPersonalContextTurns(history),
              pendingPreview: pendingPreview,
              lastQuery: _lastLighthouseState(),
              onProgress: onProgress,
            );
    } catch (error) {
      requestFailed = true;
      result = NovaPersonalReply(friendlyErrorText(error));
    }
    if (!mounted ||
        requestToken != _loadToken ||
        personalToken != _personalTurnToken) {
      // 页面已切走（离开小饕、切到别的会话）：判定为普通对话的这一句在后台接着发出，
      // 回来时按「生成中」恢复，完成后照常落库并提示未读。被停止或新建对话时不再发。
      // 灯塔 / 任务的结果已由 service 自己落盘，这里不用处理。
      if (result.routeToChat &&
          !requestFailed &&
          turnConversationId > 0 &&
          !_service.userStoppedStream) {
        NovaBackgroundCoordinator.instance.ensurePoll(
          session,
          conversationId: turnConversationId,
        );
        unawaited(
          _service.sendChatInBackground(
            conversationId: turnConversationId,
            text: prompt,
            userMessageId: userMsgId,
          ),
        );
      }
      return;
    }
    if (result.routeToChat) {
      await _continueAsChat(prompt, userMsgId, assistantMsgId);
      return;
    }
    final handledBy =
        result.capability ?? capability ?? NovaPersonalCapability.lighthouse;
    final handledName = handledBy == NovaPersonalCapability.tasks
        ? 'tasks'
        : 'lighthouse';
    final replyExtras = <String, dynamic>{
      if (result.suggestions.isNotEmpty) ...{
        novaSuggestionsPayloadKey: result.suggestions,
        novaSuggestionsCapabilityPayloadKey: handledName,
      },
      if (result.chart != null) novaChartPayloadKey: result.chart,
    };
    final userPayload = <String, dynamic>{
      'nova_personal_capability': handledName,
      if (result.state != null) novaLighthouseStatePayloadKey: result.state,
      if (requestFailed) 'nova_retryable': true,
      ...replyExtras,
    };
    if (pendingPreview != null && result.preview == null) {
      result = NovaPersonalReply(
        '${result.text}\n待确认的任务草稿仍保留；要修改它，请直接说要改的字段，或说“取消”。',
      );
    }
    setState(() {
      _sending = false;
      _serverGenerating = false;
      _busyHint = '';
      // 只有用户在输入框里选定能力才保持；自动路由的一句不锁定模式，追问靠 afterLighthouse 接上。
      if (_personalMode != null) _personalMode = handledBy;
      // 自动路由：输入框显示这一句实际走的板块（灯塔 / 任务），但不锁定。
      if (capability == null && !requestFailed) _autoPersonalMode = handledBy;
      _taskPreview = result.preview ?? pendingPreview;
      _previewMessageId = result.preview != null
          ? assistantMsgId
          : (pendingPreview != null ? previousPreviewMessageId : null);
      final index = _messages.indexWhere((m) => m.id == assistantMsgId);
      final userIndex = _messages.indexWhere((m) => m.id == userMsgId);
      if (userIndex >= 0) {
        final copy = [..._messages];
        copy[userIndex] = copy[userIndex].copyWith(
          payload: <String, dynamic>{
            ...?copy[userIndex].payload,
            ...userPayload,
          },
        );
        _messages = copy;
      }
      if (index >= 0) {
        final copy = [..._messages];
        copy[index] = copy[index].copyWith(
          text: result.text,
          streaming: false,
          thinkStatus: '',
          payload: requestFailed || replyExtras.isNotEmpty
              ? <String, dynamic>{
                  if (requestFailed) 'nova_retryable': true,
                  ...replyExtras,
                }
              : null,
        );
        _messages = copy;
      }
    });
    _scrollBottom();
    NovaBackgroundCoordinator.instance.notifyInboxRefresh();
    if (!requestFailed) return;
    try {
      await _ensureConversationId(requestToken: requestToken);
      if (!mounted || requestToken != _loadToken || _conversationId <= 0) {
        return;
      }
      await _service.persistAssistantTurn(
        conversationId: _conversationId,
        messageId: userMsgId,
        userMessage: prompt,
        assistantMessage: result.text,
        userPayload: userPayload,
        existingMessages: _messages,
      );
    } catch (_) {}
  }

  /// 后端判断这句话不属于任务或灯塔：退出选定能力，用已经显示的这一轮走普通对话。
  Future<void> _continueAsChat(
    String prompt,
    int userMsgId,
    int assistantMsgId,
  ) async {
    setState(() {
      _personalMode = null;
      _autoPersonalMode = null;
      final userIndex = _messages.indexWhere((m) => m.id == userMsgId);
      if (userIndex >= 0) {
        final copy = [..._messages];
        final payload = <String, dynamic>{...?copy[userIndex].payload}
          ..remove('nova_personal_capability');
        copy[userIndex] = copy[userIndex].copyWith(payload: payload);
        _messages = copy;
      }
    });
    await _sendMessage(
      text: prompt,
      existingUserMsgId: userMsgId,
      existingAssistantMsgId: assistantMsgId,
      markPrdSendStarted: false,
    );
  }

  /// 最近一次灯塔查询的条件，存在用户消息 payload 里，重新打开会话也能接着问。
  Map<String, dynamic>? _lastLighthouseState() {
    for (final message in _messages.reversed) {
      if (message.role != 'user') continue;
      final state = message.payload?[novaLighthouseStatePayloadKey];
      if (state is Map) return Map<String, dynamic>.from(state);
    }
    return null;
  }

  /// 最后一轮是不是刚由灯塔回答，用来让「那上周呢」这类追问继续查灯塔。
  bool _lastTurnWasRecentLighthouse() {
    for (final message in _messages.reversed) {
      if (message.role != 'user' || message.isWelcome) continue;
      final at = message.createdAt;
      return message.payload?['nova_personal_capability'] == 'lighthouse' &&
          at != null &&
          DateTime.now().difference(at) < novaLighthouseFollowUpWindow;
    }
    return false;
  }

  /// 最后一条灯塔回答对应的用户提问；回答之后已有新提问时返回 null。
  NativeNovaMessage? _latestLighthouseQuestion() {
    for (final message in _messages.reversed) {
      if (message.role != 'user' || message.isWelcome) continue;
      return message.payload?['nova_personal_capability'] == 'lighthouse'
          ? message
          : null;
    }
    return null;
  }

  /// 回答对应的提问：紧挨在它前面的用户消息。中间隔着别的回答时没有配对。
  NativeNovaMessage? _questionOf(NativeNovaMessage reply) {
    final index = _messages.indexWhere((m) => m.id == reply.id);
    for (var i = index - 1; i >= 0; i--) {
      final message = _messages[i];
      if (message.isWelcome) continue;
      return message.role == 'user' ? message : null;
    }
    return null;
  }

  void _restorePendingTaskPreview() {
    NovaTaskPreview? preview;
    int? replyId;
    for (var i = _messages.length - 1; i >= 0; i--) {
      final message = _messages[i];
      if (message.role != 'user') continue;
      preview = novaTaskPreviewFromPayload(
        message.payload?[novaTaskPreviewPayloadKey],
      );
      if (preview != null) {
        for (final reply in _messages.skip(i + 1)) {
          if (reply.role == 'assistant' && !reply.streaming) {
            replyId = reply.id;
            break;
          }
        }
      }
      break;
    }
    setState(() {
      _taskPreview = preview;
      _previewMessageId = replyId;
    });
  }

  /// 回答自己的 payload 优先；重新打开会话后回答 payload 不在，从提问的 payload 取。
  Object? _replyPayloadValue(NativeNovaMessage reply, String key) {
    final own = reply.payload?[key];
    if (own != null) return own;
    return _questionOf(reply)?.payload?[key];
  }

  List<String> _suggestionsOf(NativeNovaMessage message) {
    final raw = _replyPayloadValue(message, novaSuggestionsPayloadKey);
    if (raw is! List) return const <String>[];
    return [
      for (final item in raw)
        if ('$item'.trim().isNotEmpty) '$item'.trim(),
    ];
  }

  NovaChart? _chartOf(NativeNovaMessage message) =>
      NovaChart.fromJson(_replyPayloadValue(message, novaChartPayloadKey));

  /// 点追问或选项：直接交给产生它的能力，不再走一遍路由。
  Future<void> _askSuggestion(NativeNovaMessage reply, String text) async {
    if (_sending || !_novaReady) return;
    final capability =
        novaPersonalCapabilityFromName(
          '${_replyPayloadValue(reply, novaSuggestionsCapabilityPayloadKey) ?? ''}',
        ) ??
        NovaPersonalCapability.lighthouse;
    await _runPersonalCapability(capability, text);
  }

  Future<void> _loadInsight() async {
    if (!widget.session.effectiveLighthouseAccess) return;
    final insight = await _service.dailyInsight();
    if (!mounted || insight == null) return;
    setState(() => _insight = insight);
  }

  void _dismissInsight() {
    setState(() => _insight = null);
    unawaited(_service.markInsightSeen());
  }

  Future<void> _askInsight(String text) async {
    if (_sending || !_novaReady) return;
    _dismissInsight();
    await _runPersonalCapability(NovaPersonalCapability.lighthouse, text);
  }

  Future<void> _answerAsChat(NativeNovaMessage question) async {
    if (_sending || !_novaReady) return;
    final text = question.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _personalMode = null;
      _autoPersonalMode = null;
    });
    await _sendMessage(text: text);
  }

  Future<void> _appendPersonalTurn(
    String userText,
    NovaPersonalReply reply,
  ) async {
    final userMsgId = DateTime.now().millisecondsSinceEpoch;
    final assistantMsgId = userMsgId + 1;
    setState(() {
      if (reply.preview != null) {
        _taskPreview = reply.preview;
        _previewMessageId = assistantMsgId;
      }
      _stickToBottom = true;
      _messages = [
        ..._messages,
        NativeNovaMessage(
          id: userMsgId,
          role: 'user',
          text: userText,
          createdAt: DateTime.now(),
        ),
        NativeNovaMessage(
          id: assistantMsgId,
          role: 'assistant',
          text: reply.text,
          createdAt: DateTime.now(),
        ),
      ];
    });
    try {
      await _ensureConversationId();
      await _service.persistAssistantTurn(
        conversationId: _conversationId,
        messageId: userMsgId,
        userMessage: userText,
        assistantMessage: reply.text,
        existingMessages: _messages,
      );
    } catch (_) {}
  }

  Future<void> _confirmTaskPreview() async {
    final preview = _taskPreview;
    if (preview == null || _sending) return;
    setState(() {
      _sending = true;
      _busyHint = '正在写入';
    });
    String text;
    var written = false;
    try {
      text = await NovaPersonalQuery.execute(widget.session, preview);
      written = true;
    } catch (error) {
      text = friendlyErrorText(error);
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _busyHint = '';
      if (written) {
        _taskPreview = null;
        _previewMessageId = null;
      }
    });
    await _appendPersonalTurn('确认执行', NovaPersonalReply(text));
  }

  void _cancelTaskPreview() {
    if (_sending || _taskPreview == null) return;
    setState(() {
      _taskPreview = null;
      _previewMessageId = null;
    });
    unawaited(_appendPersonalTurn('取消', const NovaPersonalReply('已取消，没有写入。')));
  }

  Future<void> _submitInput() async {
    if (_isGenerating) {
      // 生成中输入框仍可编辑：回车只保留草稿，停止只走停止按钮，避免误触打断回复。
      if (_inputController.text.trim().isNotEmpty) {
        _toast('小饕正在回复，完成后再发送，或先点击停止');
      }
      return;
    }
    final userText = _inputController.text.trim();
    if (userText.isEmpty && _drafts.isEmpty && _analysisSources.isEmpty) return;
    if (!_novaReady) return;
    if ((_service.isStreamInFlight || _service.isPersonalQueryInFlight) &&
        !_service.isReplyInFlightFor(_conversationId)) {
      _toast('另一个会话正在回复，请先等待它完成');
      return;
    }
    final pinned = _personalMode;
    if (_drafts.isEmpty &&
        _analysisSources.isEmpty &&
        (pinned != null || _taskPreview != null)) {
      final command = userText.toLowerCase().replaceAll(
        RegExp(r'[\s，。！？!?、]'),
        '',
      );
      if (_taskPreview != null && const {'确认', '确认执行'}.contains(command)) {
        _inputController.clear();
        await _confirmTaskPreview();
        return;
      }
      if (_taskPreview != null &&
          const {'取消', '取消执行', '先不做', '算了'}.contains(command)) {
        _inputController.clear();
        _cancelTaskPreview();
        return;
      }
      final pending = _taskPreview;
      await _runPersonalCapability(
        pending != null ? NovaPersonalCapability.tasks : pinned!,
        userText,
        pendingPreview: pending,
      );
      return;
    }

    if (_drafts.isEmpty && _analysisSources.isEmpty && userText.isNotEmpty) {
      // 未选定板块：服务端在同一个请求里判断走灯塔、任务还是普通对话并接着查询。
      // 提问立即上屏；判断为普通对话时用这一轮继续走普通对话（_continueAsChat）。
      await _runPersonalCapability(null, userText);
      return;
    }

    final drafts = [..._drafts];
    if (!_ensureVisionModelForDrafts(drafts)) return;

    HapticFeedback.lightImpact();
    _inputController.clear();
    setState(() {
      _autoPersonalMode = null;
      _drafts = const <NovaDraftAttachment>[];
      _quickActionsOpen = false;
      _stickToBottom = true;
      _showJumpToLatest = false;
    });
    await _sendMessage(
      text: novaSourceDisplayQuestion(
        userText: userText,
        sources: _analysisSources,
      ),
      drafts: drafts,
    );
  }

  /// 选中任务或灯塔后，把原话交给后端。前端不决定查哪张表。
  List<({String role, String text})> _personalContextHistory() => _messages
      .where(
        (message) =>
            !message.isWelcome &&
            !message.streaming &&
            message.text.trim().isNotEmpty &&
            (message.role == 'user' || message.role == 'assistant'),
      )
      .map((message) => (role: message.role, text: message.text))
      .toList(growable: false);

  /// 有图片时要求用户手动切换到视觉模型，不再静默改派。
  bool _ensureVisionModelForDrafts(List<NovaDraftAttachment> drafts) {
    final hasImages = drafts.any((d) => d.isImage);
    if (!hasImages) return true;
    if (novaModelSupportsVision(_selectedModel)) return true;
    _toast('当前模型不支持图片识别，请先切换到 GPT5.5 等视觉模型');
    _pickModel();
    return false;
  }

  Future<void> _resendUserMessage(NativeNovaMessage message) async {
    if (_isGenerating ||
        _resendPreparing ||
        !_novaReady ||
        message.role != 'user') {
      return;
    }
    _resendPreparing = true;
    final requestToken = _loadToken;
    try {
      final drafts = await _draftsFromMessage(message);
      if (!mounted || requestToken != _loadToken) return;
      if (!_ensureVisionModelForDrafts(drafts)) return;
      final text = message.text.trim();
      final prompt = text.isNotEmpty
          ? text
          : (drafts.isNotEmpty ? novaDraftPrompt('', drafts) : '');
      if (prompt.isEmpty && drafts.isEmpty) {
        _toast('无法重新发送：缺少消息内容');
        return;
      }

      // 能力模式属于原消息，不能依赖当前输入框的模式选择来推断。
      final capability = novaPersonalCapabilityFromMessagePayload(
        message.payload,
      );
      if (capability != null && drafts.isEmpty) {
        await _runPersonalCapability(capability, prompt);
        return;
      }

      // 重新发送 = 在会话末尾追加一轮新提问，不改写原用户气泡/原回复。
      await _sendMessage(text: prompt, drafts: drafts);
    } finally {
      _resendPreparing = false;
    }
  }

  Future<List<NovaDraftAttachment>> _draftsFromMessage(
    NativeNovaMessage message,
  ) async {
    final out = <NovaDraftAttachment>[];
    final payloadAttIds = <String>[];
    final rawIds = message.payload?['attachment_ids'];
    if (rawIds is List) {
      for (final id in rawIds) {
        final s = id.toString().trim();
        if (s.isNotEmpty) payloadAttIds.add(s);
      }
    }
    var fileIndex = 0;
    for (final a in message.attachments) {
      var bytes = a.previewBytes ?? Uint8List(0);
      if (bytes.isEmpty &&
          (a.url.trim().isNotEmpty || a.objectKey.trim().isNotEmpty)) {
        try {
          bytes = await _avatarService.downloadAttachmentBytes(
            objectKey: a.objectKey.trim().isNotEmpty ? a.objectKey : a.url,
            fileName: a.fileName,
          );
        } catch (_) {
          try {
            final loaded = await _mediaResolver.loadAttachmentImageBytes(
              url: a.url,
              objectKey: a.objectKey,
            );
            if (loaded != null && loaded.isNotEmpty) bytes = loaded;
          } catch (_) {}
        }
      }
      if (bytes.isEmpty) continue;
      final isImage =
          a.kind.toUpperCase() == 'IMAGE' ||
          a.mimeType.startsWith('image/') ||
          RegExp(
            r'\.(jpe?g|png|gif|webp|bmp|heic|heif)$',
            caseSensitive: false,
          ).hasMatch(a.fileName);
      String? novaAttId;
      if (!isImage && fileIndex < payloadAttIds.length) {
        novaAttId = payloadAttIds[fileIndex];
      }
      if (!isImage) fileIndex += 1;
      out.add(
        NovaDraftAttachment(
          id: 'resend-${++_draftSeq}',
          bytes: bytes,
          fileName: a.fileName.isNotEmpty ? a.fileName : 'file',
          mimeType: a.mimeType.isNotEmpty
              ? a.mimeType
              : (isImage ? 'image/jpeg' : 'application/octet-stream'),
          isImage: isImage,
          novaAttachmentId: novaAttId,
        ),
      );
    }
    return out;
  }

  void _onInputFocusChanged() {
    if (!_inputFocusNode.hasFocus) return;
    _scrollToLatestAfterKeyboard();
  }

  void _onChatScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    final nearBottom = (pos.maxScrollExtent - pos.pixels) <= 96;
    final showJump = !nearBottom && !_isEmptyConversation;
    if (nearBottom == _stickToBottom && showJump == _showJumpToLatest) return;
    setState(() {
      _stickToBottom = nearBottom;
      _showJumpToLatest = showJump;
    });
  }

  void _scrollToLatestAfterKeyboard() {
    // 用户正在上翻阅读历史时，点输入框不再把位置拉回底部。
    if (!_stickToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollBottom(animate: true);
      Future<void>.delayed(const Duration(milliseconds: 280), () {
        if (mounted) _scrollBottom(animate: true);
      });
    });
  }

  List<NovaMessageAttachment> _attachmentsFromDrafts(
    List<NovaDraftAttachment> drafts,
  ) {
    return drafts
        .map((d) {
          if (d.payload != null) {
            return NovaMessageAttachment.fromJson(
              d.payload!,
            ).copyWith(previewBytes: d.bytes);
          }
          return NovaMessageAttachment(
            url: '',
            objectKey: '',
            fileName: d.fileName,
            mimeType: d.mimeType,
            kind: d.kind,
            previewBytes: d.bytes,
          );
        })
        .toList(growable: false);
  }

  Future<void> _applyUploadedFileToUserTurn({
    required int userMsgId,
    required int assistantMsgId,
    required String displayText,
    required NovaMessageAttachment attachment,
    required Map<String, dynamic> userMetadata,
    String assistantThinkStatus = '正在分析…',
  }) async {
    if (!mounted) return;
    setState(() {
      _busyHint = assistantThinkStatus;
      final userIdx = _messages.indexWhere((m) => m.id == userMsgId);
      final assistantIdx = _messages.indexWhere((m) => m.id == assistantMsgId);
      final copy = [..._messages];
      if (userIdx >= 0) {
        copy[userIdx] = copy[userIdx].copyWith(
          text: displayText,
          attachments: [attachment],
          kind: 'TEXT',
          payload: userMetadata,
        );
      }
      if (assistantIdx >= 0) {
        copy[assistantIdx] = copy[assistantIdx].copyWith(
          streaming: true,
          text: '',
          thinkStatus: assistantThinkStatus,
        );
      }
      _messages = copy;
    });
    _scrollBottom();
    await _persistSessionNow();
  }

  Future<List<NovaAnalysisSource>> _resolveScopedSources(
    List<NovaAnalysisSource> sources,
  ) async {
    final out = <NovaAnalysisSource>[];
    for (final source in sources) {
      if (source.kind == NovaSourceKind.kbFile ||
          source.kind == NovaSourceKind.kbFolder) {
        var ids = [...source.documentIds];
        var ragIds = [...source.ragflowDocIds];
        if (source.kind == NovaSourceKind.kbFolder &&
            ids.isEmpty &&
            ragIds.isEmpty) {
          final folderDocs = await _loadKbFolderDocuments(source.id);
          ids = novaKbLocalIds(folderDocs);
          ragIds = novaKbRagflowIds(folderDocs);
        }
        final resolved = await _kbService.resolveLocalDocumentIds(
          documentIds: ids,
          ragflowDocIds: ragIds,
          fallbackId: source.id,
        );
        out.add(
          source.copyWith(
            documentIds: resolved.isNotEmpty ? resolved : ids,
            ragflowDocIds: ragIds,
          ),
        );
        continue;
      }
      if (source.documentIds.isNotEmpty ||
          source.kind != NovaSourceKind.meetingFile) {
        out.add(source);
        continue;
      }
      final meetingId = int.tryParse(source.id) ?? 0;
      if (meetingId <= 0) {
        out.add(source);
        continue;
      }
      final doc = await _kbService.findMeetingMinutesDocument(
        meetingId: meetingId,
        kbFileName: MeetingMinutesExport.kbUploadFileNameFromSummary(
          NativeMeetingSummary(
            meetingId: meetingId,
            title: source.title,
            meetingDate: '',
            createdAt: '',
            updatedAt: '',
            status: '',
            asrProgress: 0,
          ),
        ),
        kbTitle: source.title,
      );
      final localId = int.tryParse(doc?.dunesDocumentId ?? '') ?? 0;
      out.add(
        source.copyWith(
          documentIds: localId > 0 ? <int>[localId] : source.documentIds,
          ragflowDocIds: doc != null
              ? novaKbRagflowIds([doc])
              : source.ragflowDocIds,
        ),
      );
    }
    return out;
  }

  Future<List<NativeKbDocument>> _loadKbFolderDocuments(String folderId) async {
    final id = folderId.trim().isEmpty ? 'uncategorized' : folderId.trim();
    try {
      final page = await _kbService.listDocuments(
        folderId: id,
        page: 0,
        size: 80,
      );
      return page.items
          .where((doc) => novaKbDocumentAllowedInPicker(doc))
          .toList(growable: false);
    } catch (_) {
      return const <NativeKbDocument>[];
    }
  }

  Future<List<NativeKbChunk>> _retrieveScopedChunks({
    required String query,
    required List<int> ids,
  }) async {
    if (ids.isEmpty) return const <NativeKbChunk>[];
    Future<List<NativeKbChunk>> run(String q) async {
      try {
        return await _kbService.retrieveScoped(query: q, documentIds: ids);
      } catch (_) {
        return const <NativeKbChunk>[];
      }
    }

    var chunks = await run(query);
    if (chunks.isEmpty && query != '总结要点、结论和待办') {
      chunks = await run('总结要点、结论和待办');
    }
    if (chunks.isEmpty) {
      chunks = await _kbService.fetchDocumentInlineChunks(documentIds: ids);
    }
    return chunks;
  }

  Future<({String prompt, Map<String, dynamic> payload, String displayText})>
  _bindConversationScope(String userText, {int? requestToken}) async {
    bool isCurrentRequest() =>
        mounted && (requestToken == null || requestToken == _loadToken);
    if (isCurrentRequest()) {
      setState(() => _busyHint = '正在按所选材料检索…');
    }
    var sources = [..._analysisSources];
    try {
      sources = await _resolveScopedSources(
        sources,
      ).timeout(const Duration(seconds: 8), onTimeout: () => sources);
      if (requestToken != null && !isCurrentRequest()) {
        return (prompt: '', payload: <String, dynamic>{}, displayText: '');
      }
      if (isCurrentRequest()) _replaceAnalysisSources(sources);
    } catch (_) {}
    final ids = novaSourceDocumentIds(sources);
    final query = userText.trim().isEmpty ? '总结要点、结论和待办' : userText.trim();
    var chunks = const <NativeKbChunk>[];
    try {
      chunks = await _retrieveScopedChunks(query: query, ids: ids).timeout(
        const Duration(seconds: 8),
        onTimeout: () => const <NativeKbChunk>[],
      );
    } catch (_) {}
    if (requestToken != null && !isCurrentRequest()) {
      return (prompt: '', payload: <String, dynamic>{}, displayText: '');
    }
    var prompt = composeNovaRestrictedPrompt(
      userText: userText,
      sources: sources,
      chunks: chunks,
    );
    if (prompt.isEmpty) {
      prompt = composeNovaAnalysisPrompt(userText: userText, sources: sources);
    }
    if (prompt.isEmpty) {
      prompt = userText.trim().isEmpty ? '请分析这些材料' : userText.trim();
    }
    return (
      prompt: prompt,
      payload: <String, dynamic>{
        'kbRestricted': true,
        if (ids.isNotEmpty) 'kbDocumentIds': ids,
      },
      displayText: novaSourceDisplayQuestion(
        userText: userText,
        sources: sources,
      ),
    );
  }

  void _replaceAnalysisSources(List<NovaAnalysisSource> sources) {
    if (!mounted) return;
    setState(() => _analysisSources = sources);
    unawaited(_persistAnalysisSources());
  }

  Future<void> _persistAnalysisSources() async {
    await persistNovaConversationScope(
      userId: widget.session.userId,
      conversationId: _conversationId,
      sources: _analysisSources,
    );
  }

  Future<void> _sendMessage({
    required String text,
    String? novaPrompt,
    List<NovaDraftAttachment> drafts = const <NovaDraftAttachment>[],
    Map<String, dynamic>? extraPayload,
    bool skipUserBubble = false,
    bool userAlreadyPersisted = false,
    String? assistantThinkStatus,
    int? existingUserMsgId,
    int? existingAssistantMsgId,
    // 复用已显示的一轮时是否视为 PRD 续发。普通对话复用（_continueAsChat）传 false，
    // 避免把待续发的 PRD 任务误标为「已发出」。
    bool markPrdSendStarted = true,
  }) async {
    final reusingTurn =
        existingUserMsgId != null && existingAssistantMsgId != null;
    if (_isGenerating && !reusingTurn) return;
    if (_sending && reusingTurn) {
      setState(() => _sending = false);
    }

    final sendToken = ++_loadToken;
    bool isCurrentSend() => mounted && sendToken == _loadToken;

    if (reusingTurn && markPrdSendStarted) {
      _prdNovaSendStarted = true;
      unawaited(_markPrdPendingSendStarted());
    }

    if (!_ensureVisionModelForDrafts(drafts)) return;

    var scopedPrompt = novaPrompt;
    var scopedPayload = extraPayload;
    var scopedText = text;
    var promptSource = scopedPrompt ?? scopedText;
    var prompt = novaDraftPrompt(promptSource, drafts);
    final displayText = scopedText.isNotEmpty
        ? scopedText
        : (novaAttachmentSummary(drafts).isNotEmpty
              ? novaAttachmentSummary(drafts)
              : prompt);
    _lastUserDisplayText = displayText;

    final userMsgId =
        existingUserMsgId ?? DateTime.now().millisecondsSinceEpoch;
    final assistantMsgId = existingAssistantMsgId ?? userMsgId + 1;
    final draftAttachments = _attachmentsFromDrafts(drafts);
    // im-svc 回传的本轮真实消息 ID；完成时用来把本地临时气泡对齐到服务端。
    var serverUserMsgId = 0;
    var serverAssistantMsgId = 0;
    _turnLocalUserMsgId = userMsgId;
    _turnServerUserMsgId = 0;

    if (reusingTurn) {
      final genStatus =
          assistantThinkStatus ?? (drafts.isNotEmpty ? '正在分析…' : '正在生成…');
      setState(() {
        _sending = true;
        _busyHint = genStatus;
        final assistantIdx = _messages.indexWhere(
          (m) => m.id == assistantMsgId,
        );
        if (assistantIdx >= 0) {
          final copy = [..._messages];
          copy[assistantIdx] = copy[assistantIdx].copyWith(
            streaming: true,
            text: '',
            thinkStatus: genStatus,
          );
          _messages = copy;
        }
        if (draftAttachments.isNotEmpty) {
          final userIdx = _messages.indexWhere((m) => m.id == userMsgId);
          if (userIdx >= 0) {
            final copy = [..._messages];
            copy[userIdx] = copy[userIdx].copyWith(
              text: displayText,
              attachments: draftAttachments,
              payload: <String, dynamic>{
                'attachments': draftAttachments.map((a) => a.toJson()).toList(),
              },
            );
            _messages = copy;
          }
        }
        _banner = null;
      });
      _scrollBottom();
    } else if (!skipUserBubble) {
      setState(() {
        _sending = true;
        _busyHint = kNovaInputBusyHint;
        _messages = [
          ..._messages.where((m) => !m.isWelcome),
          NativeNovaMessage(
            id: userMsgId,
            role: 'user',
            text: displayText,
            createdAt: DateTime.fromMillisecondsSinceEpoch(userMsgId),
            kind: draftAttachments.isNotEmpty ? 'TEXT' : 'TEXT',
            attachments: draftAttachments,
            payload: draftAttachments.isNotEmpty
                ? <String, dynamic>{
                    'attachments': draftAttachments
                        .map((a) => a.toJson())
                        .toList(),
                  }
                : null,
          ),
          NativeNovaMessage(
            id: assistantMsgId,
            role: 'assistant',
            text: '',
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              userMsgId,
            ).add(const Duration(milliseconds: 1)),
            streaming: true,
            thinkStatus: drafts.isNotEmpty ? '正在分析…' : '正在生成…',
          ),
        ];
        _banner = null;
      });
      _scrollBottom();
    } else {
      setState(() {
        _sending = true;
        _busyHint = kNovaInputBusyHint;
        _messages = [
          ..._messages,
          NativeNovaMessage(
            id: assistantMsgId,
            role: 'assistant',
            text: '',
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              assistantMsgId - 1,
            ).add(const Duration(milliseconds: 1)),
            streaming: true,
            thinkStatus: '正在生成…',
          ),
        ];
        _banner = null;
      });
      _scrollBottom();
    }

    // 流式分片很密：按固定间隔合并刷新，避免每个分片都重建整页和整段 Markdown。
    // 每次更新携带的是完整累计文本，丢弃中间分片不会丢内容。
    NovaStreamUpdate? pendingStreamUpdate;
    Timer? streamFlushTimer;
    var lastStreamFlushAt = 0;

    void applyStreamUpdate(NovaStreamUpdate update) {
      setState(() {
        _busyHint = update.thinkStatus.isNotEmpty
            ? update.thinkStatus
            : kNovaInputBusyHint;
        var idx = _messages.indexWhere((m) => m.id == assistantMsgId);
        if (idx < 0) {
          idx = _messages.lastIndexWhere(
            (m) => m.role == 'assistant' && m.streaming,
          );
        }
        // 保留原 createdAt，避免流式/重新发送把回复刷到「现在」导致整段乱序。
        final prevAt = idx >= 0 ? _messages[idx].createdAt : null;
        final keepId = idx >= 0 ? _messages[idx].id : assistantMsgId;
        final assistant = NativeNovaMessage(
          id: keepId,
          role: 'assistant',
          text: update.replyText,
          createdAt: prevAt ?? DateTime.now(),
          thinkText: update.thinkText,
          thinkStatus: update.thinkStatus,
          streaming: true,
          ragUsed: update.ragUsed,
        );
        if (idx >= 0) {
          final copy = [..._messages];
          copy[idx] = assistant;
          _messages = collapseNovaStreamingPlaceholders(copy);
        } else if (!skipUserBubble) {
          _messages = collapseNovaStreamingPlaceholders([
            ..._messages,
            assistant,
          ]);
        }
      });
      _scrollBottom(settle: false);
    }

    void flushStreamUpdate() {
      streamFlushTimer?.cancel();
      streamFlushTimer = null;
      final update = pendingStreamUpdate;
      pendingStreamUpdate = null;
      if (update == null) return;
      if (!isCurrentSend() || _service.userStoppedStream) return;
      lastStreamFlushAt = DateTime.now().millisecondsSinceEpoch;
      applyStreamUpdate(update);
    }

    _flushPendingStreamUpdate = flushStreamUpdate;

    try {
      if (_analysisSources.isNotEmpty && novaPrompt == null) {
        final bound = await _bindConversationScope(
          text,
          requestToken: sendToken,
        );
        if (!isCurrentSend()) return;
        scopedPrompt = bound.prompt;
        scopedPayload = bound.payload;
        scopedText = bound.displayText;
        promptSource = scopedPrompt;
        prompt = novaDraftPrompt(promptSource, drafts);
      }
      await _ensureConversationId();
      if (!isCurrentSend()) return;
      if (_conversationId <= 0) {
        throw Exception('无法创建NOVA会话，请稍后重试');
      }
      if (_analysisSources.isNotEmpty) {
        unawaited(_persistAnalysisSources());
      }
      final genStatus =
          assistantThinkStatus ?? (drafts.isNotEmpty ? '正在分析…' : '正在生成…');
      if (!skipUserBubble || reusingTurn) {
        _genAfterMessageId = userMsgId;
        NovaBackgroundCoordinator.instance.clearFinalizedConversation(
          _conversationId,
        );
        await _markGenerating(status: genStatus, afterMessageId: userMsgId);
        if (!isCurrentSend()) return;
        await _persistSessionNow();
        if (!isCurrentSend()) return;
        await persistNovaStreamDraftState(
          userId: widget.session.userId,
          conversationId: _conversationId,
          status: genStatus,
          afterMessageId: userMsgId,
          userText: displayText,
          thinkText: '',
          text: '',
          streaming: true,
        );
        if (!isCurrentSend()) return;
        if (kDebugMode) {
          debugPrint(
            '[NativeNovaPage] seeded draft conv=$_conversationId after=$userMsgId',
          );
        }
        if (mounted) {
          setState(() {
            _serverGenerating = true;
            _busyHint = genStatus;
          });
        }
      }

      // `/ai/assistant/messages` persists the user turn atomically before
      // starting NOVA. Persisting here as well used to create duplicate turns
      // when the user navigated away during a stream.
      var userPersistedToServer = skipUserBubble || userAlreadyPersisted;

      final previewByDraftId = <String, Uint8List>{};
      for (final d in drafts) {
        if (d.payload != null &&
            (d.isImage || (d.novaAttachmentId ?? '').trim().isNotEmpty)) {
          if (d.bytes.isNotEmpty) previewByDraftId[d.id] = d.bytes;
          continue;
        }
        setState(() {
          d.uploading = true;
          d.uploadProgress = 1;
        });
        // 图片上传前压缩；文档走 Nova 当轮抽文本接口。
        var uploadBytes = d.bytes;
        var uploadName = d.fileName;
        var uploadMime = d.mimeType;
        if (d.isImage) {
          try {
            final normalized = await normalizeImageForVision(
              d.bytes,
              fileName: d.fileName,
            );
            if (!isCurrentSend()) return;
            if (normalized.bytes.isNotEmpty) {
              previewByDraftId[d.id] = normalized.bytes;
              uploadBytes = normalized.bytes;
              uploadName = normalized.fileName;
              uploadMime = normalized.mimeType;
            }
          } catch (_) {}
        } else {
          final novaAtt = await _service.uploadNovaChatAttachment(
            bytes: d.bytes,
            fileName: d.fileName,
            onProgress: (p) {
              if (isCurrentSend()) {
                setState(() {
                  d.uploadProgress = (p * 0.6).clamp(1, 60).toDouble();
                });
              }
            },
          );
          if (!isCurrentSend()) return;
          d.novaAttachmentId = novaAtt.attachmentId;
          d.textPreview = novaAtt.preview;
          if (novaAtt.truncated) {
            _toast('文件较长，已截取部分内容用于提问');
          }
        }
        if (!previewByDraftId.containsKey(d.id) && d.bytes.isNotEmpty) {
          previewByDraftId[d.id] = d.bytes;
        }
        // 同步上传到沙丘存储，供气泡展示/历史回看。
        final uploaded = await _service.uploadAttachment(
          conversationId: _conversationId,
          bytes: uploadBytes,
          fileName: uploadName,
          onProgress: (p) {
            if (!isCurrentSend()) return;
            final base = d.isImage ? 0.0 : 60.0;
            setState(() {
              d.uploadProgress = (base + p * (d.isImage ? 1 : 0.4))
                  .clamp(1, 100)
                  .toDouble();
            });
          },
        );
        if (!isCurrentSend()) return;
        d.payload = _service.buildUploadedAttachmentPayload(
          url: uploaded.url,
          objectKey: uploaded.objectKey,
          fileName: uploadName,
          mimeType: uploadMime,
          kind: d.kind,
        );
        if ((d.novaAttachmentId ?? '').trim().isNotEmpty) {
          d.payload = <String, dynamic>{
            ...?d.payload,
            'novaAttachmentId': d.novaAttachmentId,
            if (d.textPreview.trim().isNotEmpty) 'preview': d.textPreview,
          };
        }
        d.uploading = false;
      }

      final attachments = drafts
          .where((d) => d.payload != null)
          .map((d) => NovaMessageAttachment.fromJson(d.payload!))
          .toList();
      final novaAttachmentIds = _service.collectNovaAttachmentIds(drafts);

      if ((!skipUserBubble || reusingTurn) && attachments.isNotEmpty) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == userMsgId);
          if (idx >= 0) {
            final copy = [..._messages];
            final payload = <String, dynamic>{
              'attachments': attachments.map((a) => a.toJson()).toList(),
              if (novaAttachmentIds.isNotEmpty)
                'attachment_ids': novaAttachmentIds,
            };
            // 按 payload 对应回 drafts，避免 where 过滤后 index 错位丢掉 previewBytes。
            final withPreview = <NovaMessageAttachment>[];
            for (final d in drafts) {
              if (d.payload == null) continue;
              final preview =
                  previewByDraftId[d.id] ??
                  (d.bytes.isNotEmpty ? d.bytes : null);
              withPreview.add(
                NovaMessageAttachment.fromJson(
                  d.payload!,
                ).copyWith(previewBytes: preview),
              );
            }
            copy[idx] = copy[idx].copyWith(
              attachments: dedupeNovaMessageAttachments(
                withPreview.isNotEmpty ? withPreview : attachments,
              ),
              kind: 'TEXT',
              payload: payload,
            );
            _messages = copy;
          }
        });
        unawaited(_persistSessionNow());
      }

      final userMetadata = <String, dynamic>{
        if (attachments.isNotEmpty)
          'attachments': attachments.map((a) => a.toJson()).toList(),
        if (novaAttachmentIds.isNotEmpty) 'attachment_ids': novaAttachmentIds,
        ...?scopedPayload,
      };
      final effectiveMetadata = userMetadata.isEmpty ? null : userMetadata;

      final userContent = drafts.isEmpty
          ? (promptSource.trim().isNotEmpty
                ? promptSource.trim()
                : (text.isNotEmpty ? text : prompt))
          : await _service.buildMultimodalContent(
              text: prompt,
              attachments: drafts,
              model: _selectedModel,
            );
      if (!isCurrentSend()) return;

      // 仅有文档 attachment_ids、无图片 parts 时，保证 content 至少是问题文本。
      final effectiveContent =
          (userContent is String &&
              userContent.toString().trim().isEmpty &&
              novaAttachmentIds.isNotEmpty)
          ? prompt
          : userContent;

      var reply = await _service.sendAndReplyStream(
        conversationId: _conversationId,
        userContent: effectiveContent,
        displayText: displayText,
        userMetadata: effectiveMetadata,
        attachmentIds: novaAttachmentIds,
        userMessageId: userMsgId,
        skipUserPersist: userPersistedToServer,
        onServerMessageIds: (serverUserId, serverAssistantId) {
          if (serverUserId > 0) serverUserMsgId = serverUserId;
          if (serverAssistantId > 0) serverAssistantMsgId = serverAssistantId;
          if (isCurrentSend() && serverUserId > 0) {
            _turnServerUserMsgId = serverUserId;
          }
        },
        onConversationId: (id) {
          if (!isCurrentSend() || id <= 0 || id == _conversationId) return;
          final previous = _conversationId;
          unawaited(_service.remapConversationId(previous, id));
          setState(() => _conversationId = id);
          unawaited(_persistAnalysisSources());
        },
        onUpdate: (update) {
          if (!isCurrentSend() || _service.userStoppedStream) return;
          pendingStreamUpdate = update;
          final elapsed =
              DateTime.now().millisecondsSinceEpoch - lastStreamFlushAt;
          if (elapsed >= _streamFlushIntervalMs) {
            flushStreamUpdate();
          } else {
            streamFlushTimer ??= Timer(
              Duration(milliseconds: _streamFlushIntervalMs - elapsed),
              flushStreamUpdate,
            );
          }
        },
      );
      // 把节流中尚未刷新的最后一段（含思考内容）先落到气泡，再做收尾。
      flushStreamUpdate();
      if (!isCurrentSend()) return;
      if (_service.userStoppedStream) {
        await _persistSessionNow();
        return;
      }

      await _completeAssistantStream(
        assistantMsgId: assistantMsgId,
        skipUserBubble: skipUserBubble,
        replyText: reply,
        conversationId: _conversationId,
        requestToken: sendToken,
        localUserMsgId: userMsgId,
        serverUserMsgId: serverUserMsgId,
        serverAssistantMsgId: serverAssistantMsgId,
      );
      if (_conversationId > 0) {
        unawaited(
          clearNovaPrdPendingJob(
            userId: widget.session.userId,
            conversationId: _conversationId,
          ),
        );
      }
      if (!mounted) return;
      _scrollBottom();
    } catch (e) {
      if (!isCurrentSend()) return;
      if (kDebugMode) {
        debugPrint('[NativeNovaPage] sendMessage failed: $e');
      }
      final convId = _conversationId;
      if (_service.userStoppedStream) {
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere(
              (m) => m.role == 'assistant' && m.streaming,
            );
            if (idx >= 0) {
              final copy = [..._messages];
              final partial = copy[idx].text.trim();
              copy[idx] = copy[idx].copyWith(
                streaming: false,
                text: partial.isEmpty ? '已停止生成' : partial,
                thinkStatus: '已停止生成',
              );
              _messages = copy;
            }
          });
          _releaseGeneratingUi(clearStreamingFlags: false);
          await _registerLastTurnIfComplete(userMsgId: userMsgId);
        } else if (convId > 0) {
          await _clearGeneratingMarkers();
          await _service.stripStreamingFromSession(convId);
        }
      } else if (!_service.userStoppedStream &&
          await _tryRecoverAssistantAfterSendFailure(
            userMsgId: userMsgId,
            assistantMsgId: assistantMsgId,
            requestToken: sendToken,
          )) {
        if (_conversationId > 0) {
          unawaited(
            clearNovaPrdPendingJob(
              userId: widget.session.userId,
              conversationId: _conversationId,
            ),
          );
        }
      } else if (mounted) {
        await _failAssistantTurnInChat(
          assistantMsgId: assistantMsgId,
          message: NativeNovaService.friendlyError(e),
          requestToken: sendToken,
        );
      } else if (convId > 0) {
        await _clearGeneratingMarkers();
        await clearNovaStreamDraftState(
          userId: widget.session.userId,
          conversationId: convId,
        );
        await _service.stripStreamingFromSession(convId);
      }
    } finally {
      streamFlushTimer?.cancel();
      streamFlushTimer = null;
      if (identical(_flushPendingStreamUpdate, flushStreamUpdate)) {
        _flushPendingStreamUpdate = null;
      }
      if (isCurrentSend()) {
        if (_conversationId > 0) {
          unawaited(_service.persistActiveConversationId(_conversationId));
        }
        if (_conversationId > 0 && _messages.isNotEmpty) {
          unawaited(_service.persistSession(_conversationId, _messages));
        }
        if (!_hasActiveAssistantStream()) {
          setState(() {
            _sending = false;
            _serverGenerating = false;
            _busyHint = '';
          });
        }
      }
    }
  }

  void _handleBack() {
    Future<void>(() async {
      await _flushOnLeave();
      if (mounted) widget.onBack();
    });
  }

  void _stopGeneration() {
    // 先把节流中尚未上屏的内容刷出来，停止后展示与服务端落库的是同一段文本。
    _flushPendingStreamUpdate?.call();
    final streamingIdx = _messages.indexWhere(
      (m) => m.role == 'assistant' && m.streaming,
    );
    final partialText = streamingIdx >= 0
        ? _messages[streamingIdx].text.trim()
        : '';
    final stopConvId = _conversationId;
    final localAssistantId = streamingIdx >= 0 ? _messages[streamingIdx].id : 0;
    final localUserId = _turnLocalUserMsgId;
    final serverUserId = _turnServerUserMsgId;
    _loadToken++;
    _personalTurnToken++;
    _service.cancelActiveStream();
    // 服务端生成不随连接断开而停止，需显式通知；失败不影响本地停止。
    // 停止成功后服务端按原文落库部分回复，把本地气泡对齐到它的真实 ID。
    unawaited(
      _service
          .requestServerStop(stopConvId, partialText: partialText)
          .then((result) {
            if (!mounted || stopConvId != _conversationId) return;
            final aligned = remapNovaTurnMessageIds(
              _messages,
              localUserId: localUserId,
              serverUserId: serverUserId,
              localAssistantId: localAssistantId,
              serverAssistantId: result.assistantMessageId,
            );
            if (identical(aligned, _messages)) return;
            setState(() => _messages = aligned);
            unawaited(_persistSessionNow());
          }),
    );
    _stopGeneratingPoll();
    _stopStreamDraftWatcher();
    if (_conversationId > 0) {
      unawaited(
        persistNovaGeneratingState(
          userId: widget.session.userId,
          conversationId: _conversationId,
          status: '已停止生成',
          afterMessageId: _genAfterMessageId,
        ),
      );
      unawaited(
        clearNovaStreamDraftState(
          userId: widget.session.userId,
          conversationId: _conversationId,
        ),
      );
    }
    setState(() {
      final idx = _messages.indexWhere(
        (m) => m.role == 'assistant' && m.streaming,
      );
      if (idx >= 0) {
        final copy = [..._messages];
        final partial = copy[idx].text.trim();
        copy[idx] = copy[idx].copyWith(
          streaming: false,
          text: partial.isEmpty ? '已停止生成' : partial,
          thinkStatus: '已停止生成',
        );
        _messages = copy;
      }
      _sending = false;
      _serverGenerating = false;
      _busyHint = '已停止生成';
    });
    unawaited(_persistSessionNow());
  }

  Future<void> _openConversationFromDrawer(int targetConvId) async {
    _showNovaChatTab();
    if (targetConvId <= 0) return;
    if (targetConvId == _conversationId && _messages.any((m) => !m.isWelcome)) {
      return;
    }
    await _flushOnLeave();
    if (!mounted) return;
    _loadToken += 1;
    final token = _loadToken;
    _stopGeneratingPoll();
    _stopStreamDraftWatcher();
    final prevConvId = _conversationId;
    if (prevConvId > 0 && _messages.isNotEmpty) {
      await _service.flushConvToLocalHistory(prevConvId, _messages);
    }
    setState(() {
      _loading = true;
      _conversationId = targetConvId;
      _messages = const [];
      _personalMode = null;
      _autoPersonalMode = null;
      _taskPreview = null;
      _previewMessageId = null;
      _analysisSources = const <NovaAnalysisSource>[];
      _banner = null;
      _busyHint = '';
      _sending = false;
      _serverGenerating = false;
      _quickActionsOpen = false;
      _stickToBottom = true;
      _showJumpToLatest = false;
    });
    try {
      var convId = targetConvId;
      try {
        final ensured = await _service.sessionEnsure(
          legacyConversationId: targetConvId,
        );
        if (ensured.conversationId > 0) convId = ensured.conversationId;
      } catch (_) {}
      if (!mounted || _loadToken != token) return;
      _conversationId = convId;
      await _service.persistActiveConversationId(convId);
      if (!mounted || _loadToken != token) return;
      await _load(targetConversationId: convId);
      if (_isEmptyConversation) {
        _scrollTop();
      } else {
        _scrollBottom(force: true);
      }
    } catch (e) {
      if (!mounted || _loadToken != token) return;
      setState(() {
        _loading = false;
        _banner = NativeNovaService.friendlyError(e);
      });
      _toast(_banner ?? '无法打开历史会话');
    }
  }

  Future<void> _startNewChat({
    NovaAnalysisSource? scopedSource,
    bool announce = true,
  }) async {
    _showNovaChatTab();
    if (_startingNewChat) return;
    _startingNewChat = true;
    // 先让旧请求失效，再取消流，避免旧回复写入新会话。
    final token = ++_loadToken;
    final wasGenerating =
        _isGenerating || _service.isReplyInFlightFor(_conversationId);
    if (wasGenerating) _service.cancelActiveStream();
    _stopGeneratingPoll();
    _stopStreamDraftWatcher();
    final prevConvId = _conversationId;
    final uid = widget.session.userId;
    final previousMessages = List<NativeNovaMessage>.of(_messages);
    if (prevConvId > 0 && wasGenerating) {
      unawaited(
        clearNovaGeneratingState(userId: uid, conversationId: prevConvId),
      );
      unawaited(
        clearNovaStreamDraftState(userId: uid, conversationId: prevConvId),
      );
    }
    widget.onClearHistoryFocus?.call();
    setState(() {
      _loading = false;
      _banner = null;
      _busyHint = '';
      _serverGenerating = false;
      _sending = false;
      _drafts = const <NovaDraftAttachment>[];
      _analysisSources = scopedSource == null
          ? const <NovaAnalysisSource>[]
          : <NovaAnalysisSource>[scopedSource];
      _conversationId = 0;
      _personalMode = null;
      _autoPersonalMode = null;
      _taskPreview = null;
      _previewMessageId = null;
      _genAfterMessageId = 0;
      _messages = [_welcomeMessage()];
      _quickActionsOpen = false;
      _stickToBottom = true;
      _showJumpToLatest = false;
    });
    // 新建会话默认展示最顶部（完整呈现大头像与问候语）
    _scrollTop();
    try {
      if (prevConvId > 0) {
        await _service.flushConvToLocalHistory(prevConvId, previousMessages);
        if (!mounted || token != _loadToken) return;
      }
      await _service.resetNovaNewChatPlaceholder(
        userId: uid,
        previousConversationId: prevConvId,
      );
      if (!mounted || token != _loadToken) return;
      final convId = await _service.createNovaServerConversation(
        forceNew: true,
      );
      if (!mounted || token != _loadToken) return;
      if (convId > 0) {
        await _service.applyNovaNewChatStorage(
          userId: uid,
          conversationId: convId,
          previousConversationId: prevConvId,
        );
        await _service.novaChatSessionId(convId);
        if (!mounted || token != _loadToken) return;
        setState(() => _conversationId = convId);
        unawaited(_persistAnalysisSources());
      } else if (prevConvId > 0 &&
          await _service.validateNovaConversationId(prevConvId)) {
        final recovered = await _service.applyNewChatLocalFallback(
          userId: uid,
          previousConversationId: prevConvId,
        );
        if (!mounted || token != _loadToken) return;
        if (recovered > 0) {
          setState(() => _conversationId = recovered);
          unawaited(_persistAnalysisSources());
        }
        await NovaWebStorage.removeKeys(uid, ['dunes_nova_view_since']);
      } else {
        if (uid > 0) {
          await NovaWebStorage.removeKeys(uid, ['dunes_nova_view_since']);
        }
        if (mounted && token == _loadToken) {
          setState(() => _banner = '新对话已就绪，首次发送时会自动创建会话');
        }
      }
      if (announce && mounted && token == _loadToken) {
        _toast('已开启新对话，上一段可在右上角「历史」查看');
      }
    } catch (_) {
      if (mounted && token == _loadToken) {
        setState(() => _banner = '新对话已就绪，首次发送时会自动创建会话');
      }
    } finally {
      _startingNewChat = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _startAsrPcmCapture() async {
    await _discardAsrPcmCapture();
    final pcmBytes = BytesBuilder(copy: false);
    _asrPcmBytes = pcmBytes;
    _asrPcmSubscription = NativeAudioRecorder.instance.pcmStream().listen(
      pcmBytes.add,
      onError: (_, _) {},
      cancelOnError: false,
    );
  }

  Future<void> _discardAsrPcmCapture() async {
    final subscription = _asrPcmSubscription;
    _asrPcmSubscription = null;
    _asrPcmBytes = null;
    await subscription?.cancel();
  }

  Future<Uint8List> _takeAsrWavBytes() async {
    // 原生端通过 EventChannel 推送 PCM；停止后给主线程一个短暂窗口送达最后一帧。
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final subscription = _asrPcmSubscription;
    _asrPcmSubscription = null;
    await subscription?.cancel();
    final pcm = _asrPcmBytes?.takeBytes() ?? Uint8List(0);
    _asrPcmBytes = null;
    if (pcm.isEmpty) return pcm;
    return _pcm16MonoToWav(pcm);
  }

  Uint8List _pcm16MonoToWav(Uint8List pcm) {
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;
    final wav = Uint8List(44 + pcm.length);
    final header = ByteData.sublistView(wav);
    void writeAscii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        header.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + pcm.length, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(
      28,
      sampleRate * channels * bitsPerSample ~/ 8,
      Endian.little,
    );
    header.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, pcm.length, Endian.little);
    wav.setRange(44, wav.length, pcm);
    return wav;
  }

  Future<void> _startHoldRecord(Offset focalPoint) async {
    if (_sending || _recording || !_novaReady) return;
    if (MeetingLiveController.instance.isActive) {
      _toast('会议录音进行中，暂无法发送语音');
      return;
    }
    if (!NativeAudioRecorder.isSupported) {
      _toast('当前环境不支持录音');
      return;
    }
    if (!kIsWeb) {
      final mic = await ensureMicrophonePermission();
      if (!mic) {
        _toast('请先允许麦克风权限');
        return;
      }
    }
    try {
      await _startAsrPcmCapture();
      await NativeAudioRecorder.instance.start();
      _recordTicker?.cancel();
      setState(() {
        _recording = true;
        _recordAction = VoiceHoldAction.none;
        _recordFocalPoint = focalPoint;
        _recordDurationMs = 0;
      });
      _recordTicker = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (!mounted || !_recording) return;
        setState(() => _recordDurationMs += 120);
        // glm-asr-2512 仅支持 ≤30 秒，到点自动结束并发送。
        if (_recordDurationMs >= 30000) {
          _recordTicker?.cancel();
          _toast('已达最长 30 秒，自动发送');
          unawaited(_finishHoldRecord());
        }
      });
    } catch (e) {
      await _discardAsrPcmCapture();
      if (e is NativeAudioRecorderBusyException) {
        _toast(e.message);
        return;
      }
      _toast('录音启动失败：${friendlyErrorText(e)}');
    }
  }

  Future<void> _finishHoldRecord() async {
    if (!_recording) return;
    if (_recordAction == VoiceHoldAction.cancel) {
      await _cancelHoldRecord(showHint: true);
      return;
    }
    _recordTicker?.cancel();
    setState(() {
      _recording = false;
      _recordAction = VoiceHoldAction.none;
      _recordFocalPoint = null;
    });
    try {
      final recorded = await NativeAudioRecorder.instance.stop();
      final wavBytes = await _takeAsrWavBytes();
      if (recorded == null) return;
      if (recorded.durationMs < 500) {
        _toast('录音时间太短');
        return;
      }
      if (wavBytes.length <= 44) {
        throw Exception('未获取到可识别的语音数据');
      }
      final fileName = 'voice-${DateTime.now().millisecondsSinceEpoch}.wav';
      // 原生端推送的就是 16kHz / 单声道 / PCM16；封装 WAV 后可被 ASR
      // 稳定识别，避免 AAC/M4A 容器在部分模型端不兼容。
      setState(() {
        _messages = [
          ..._messages.where((m) => !m.isWelcome),
          NativeNovaMessage(
            id: DateTime.now().millisecondsSinceEpoch,
            role: 'user',
            text: '正在识别语音…',
            createdAt: DateTime.now(),
            kind: 'TEXT',
          ),
        ];
      });
      _scrollBottom();
      final transcript = await _service.transcribeAudio(wavBytes, fileName);
      if (!mounted) return;
      setState(() {
        final idx = _messages.lastIndexWhere((m) => m.role == 'user');
        if (idx >= 0) {
          final copy = [..._messages];
          copy[idx] = copy[idx].copyWith(text: transcript, kind: 'TEXT');
          _messages = copy;
        }
      });
      await _sendMessage(text: transcript, skipUserBubble: true);
    } catch (e) {
      await _discardAsrPcmCapture();
      if (mounted) {
        setState(() {
          final idx = _messages.lastIndexWhere(
            (m) => m.role == 'user' && m.text == '正在识别语音…',
          );
          if (idx >= 0) {
            final copy = [..._messages];
            copy.removeAt(idx);
            _messages = copy;
          }
        });
      }
      _toast('语音识别失败：${friendlyErrorText(e)}');
    }
  }

  Future<void> _cancelHoldRecord({required bool showHint}) async {
    if (!_recording) return;
    _recordTicker?.cancel();
    setState(() {
      _recording = false;
      _recordAction = VoiceHoldAction.none;
      _recordFocalPoint = null;
      _recordDurationMs = 0;
    });
    await _discardAsrPcmCapture();
    try {
      await NativeAudioRecorder.instance.cancel();
    } catch (_) {}
    if (showHint) _toast('已取消发送');
  }

  void _onRecordMove(LongPressMoveUpdateDetails details) {
    if (!_recording) return;
    // Nova 不支持转文字，操作面板只有「发送 / 取消」两个圆圈。
    final action = resolveVoiceHoldAction(
      details.globalPosition,
      MediaQuery.sizeOf(context),
      transcribeEnabled: false,
    );
    setState(() {
      _recordAction = action;
      _recordFocalPoint = details.globalPosition;
    });
  }

  void _scrollTop() {
    void jump() {
      if (!mounted || !_scrollController.hasClients) return;
      final phase = SchedulerBinding.instance.schedulerPhase;
      if (phase == SchedulerPhase.persistentCallbacks ||
          phase == SchedulerPhase.midFrameMicrotasks) {
        WidgetsBinding.instance.addPostFrameCallback((_) => jump());
        return;
      }
      final position = _scrollController.position;
      if (!position.hasContentDimensions || !position.hasPixels) return;
      if (position.pixels > 0) {
        position.jumpTo(0.0);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => jump());
    for (final ms in const [60, 120, 240, 480]) {
      Future.delayed(Duration(milliseconds: ms), jump);
    }
  }

  /// [settle] 为 true 时追加几次延时跳转，等图片/富文本撑高后再贴底（首次加载、
  /// 回复完成等场景）。流式刷新传 false：只在下一帧跳一次，且同一帧内合并。
  void _scrollBottom({
    bool force = false,
    bool animate = false,
    bool settle = true,
  }) {
    if (!force && !_stickToBottom) return;
    if (force) {
      _stickToBottom = true;
      if (_showJumpToLatest && mounted) {
        _showJumpToLatest = false;
      }
    }

    void jump() {
      if (!mounted || !_scrollController.hasClients) return;
      if (!force && !_stickToBottom) return;
      final phase = SchedulerBinding.instance.schedulerPhase;
      if (phase == SchedulerPhase.persistentCallbacks ||
          phase == SchedulerPhase.midFrameMicrotasks) {
        WidgetsBinding.instance.addPostFrameCallback((_) => jump());
        return;
      }
      final position = _scrollController.position;
      if (!position.hasContentDimensions || !position.hasPixels) return;
      final max = position.maxScrollExtent;
      if ((position.pixels - max).abs() <= 2) return;
      if (animate) {
        position.animateTo(
          max,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      } else {
        position.jumpTo(max);
      }
    }

    if (!settle && !force) {
      if (_scrollJumpQueued) return;
      _scrollJumpQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollJumpQueued = false;
        jump();
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => jump());
    // 历史里的图片/富文本异步撑高后高度才稳定，单次跳转会停在中间；
    // 用户已主动上滑阅读时不再强行贴底。
    if (force || _stickToBottom) {
      for (final ms in const [60, 120, 240, 480, 800, 1200]) {
        Future.delayed(Duration(milliseconds: ms), jump);
      }
    }
  }

  void _pickModel() {
    if (_chatModels.length <= 1) return;
    // 生成中禁止切换模型。
    if (_sending || _serverGenerating) return;
    showNovaModelSheet(
      context,
      models: _chatModels,
      selected: _selectedModel,
      modelCatalog: _modelCatalog,
      onPick: (id) {
        _service.setSelectedChatModel(id, persist: true);
        setState(() => _selectedModel = id);
      },
    );
  }

  Future<String?> _pickPrdGenerationModel() async {
    if (_chatModels.isEmpty) {
      return _selectedModel.trim().isNotEmpty ? _selectedModel : null;
    }
    var picked = _selectedModel.trim().isNotEmpty
        ? _selectedModel
        : _chatModels.first;
    await showNovaModelSheet(
      context,
      title: '选择 NOVA 模型',
      models: _chatModels,
      selected: picked,
      modelCatalog: _modelCatalog,
      onPick: (id) => picked = id,
    );
    return picked.trim().isNotEmpty ? picked : null;
  }

  void _applySelectedChatModel(String modelId) {
    final id = modelId.trim();
    if (id.isEmpty) return;
    _service.setSelectedChatModel(id, persist: true);
    if (!mounted) return;
    setState(() => _selectedModel = id);
  }

  Future<void> _persistPrdPendingTurn({
    required int userMsgId,
    required int assistantMsgId,
    required String displayText,
    required NovaPrdPendingJob pendingJob,
  }) async {
    _lastUserDisplayText = displayText;
    _genAfterMessageId = userMsgId;
    _prdNovaSendStarted = false;
    await _ensureConversationId();
    if (!mounted || _conversationId <= 0) return;

    NovaBackgroundCoordinator.instance.clearFinalizedConversation(
      _conversationId,
    );
    await persistNovaPrdPendingJob(
      userId: widget.session.userId,
      conversationId: _conversationId,
      job: pendingJob,
    );
    await _persistSessionNow();
    await _service.persistActiveConversationId(_conversationId);
    await _service.flushConvToLocalHistory(
      _conversationId,
      _messages.where((m) => !m.isWelcome).toList(growable: false),
    );
  }

  Future<void> _markPrdPendingSendStarted() async {
    if (_conversationId <= 0) return;
    try {
      final storage = await NovaWebStorage.load(widget.session.userId);
      final job = readNovaPrdPendingJob(storage, _conversationId);
      if (job == null || job.sendStarted) return;
      await persistNovaPrdPendingJob(
        userId: widget.session.userId,
        conversationId: _conversationId,
        job: job.copyWith(sendStarted: true),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NativeNovaPage] mark PRD sendStarted failed: $e');
      }
    }
  }

  Future<void> _maybeResumePrdGeneration() async {
    if (!mounted || _conversationId <= 0 || _prdResumeInFlight || _sending) {
      return;
    }

    final storage = await NovaWebStorage.load(widget.session.userId);
    final job = readNovaPrdPendingJob(storage, _conversationId);
    if (job == null || _prdResumeInFlight) return;
    if (_hasAiReplyAfter(_messages, job.userMsgId)) {
      await clearNovaPrdPendingJob(
        userId: widget.session.userId,
        conversationId: _conversationId,
      );
      return;
    }

    // 本地短文案 + 服务端长指令可能并存；先合并再决定是否续发。
    _collapsePrdDuplicateUserBubbles();

    // 已对 NOVA 发起过请求：只靠 generating/poll 续流，禁止再发一轮。
    if (job.sendStarted ||
        _prdNovaSendStarted ||
        _serverGenerating ||
        _service.isReplyInFlightFor(_conversationId) ||
        _hasActiveAssistantStream()) {
      return;
    }

    _prdResumeInFlight = true;
    try {
      _applySelectedChatModel(job.prdModel);
      await _continuePrdGeneration(job);
    } finally {
      _prdResumeInFlight = false;
    }
  }

  void _collapsePrdDuplicateUserBubbles() {
    if (!mounted) return;
    final next = dedupeNovaHistoryMessages(_messages);
    if (identical(next, _messages) || next.length == _messages.length) {
      // 长度相同也可能替换了文案；比对末尾用户气泡文本。
      var changed = next.length != _messages.length;
      if (!changed) {
        for (var i = 0; i < next.length; i++) {
          if (next[i].id != _messages[i].id ||
              next[i].text != _messages[i].text) {
            changed = true;
            break;
          }
        }
      }
      if (!changed) return;
    }
    setState(() => _messages = next);
  }

  Future<void> _continuePrdGeneration(NovaPrdPendingJob job) async {
    if (!mounted || _sending) return;
    final hasReply = _hasAiReplyAfter(_messages, job.userMsgId);
    if (hasReply) {
      await clearNovaPrdPendingJob(
        userId: widget.session.userId,
        conversationId: _conversationId,
      );
      return;
    }

    try {
      if (job.meetingId <= 0) {
        final displayText = buildMeetingPrdDisplayText(job.kbFileName);
        final novaPrompt = job.messageText.trim().isNotEmpty
            ? job.messageText.trim()
            : buildMeetingPrdNovaMessage(
                kbFileName: job.kbFileName,
                prdFileName: job.prdFileName,
              );
        await _sendPrdFromKbFileName(
          job: job,
          displayText: displayText,
          novaPrompt: novaPrompt,
        );
      } else {
        await _ensureKbAndSendPrdToNova(job: job);
      }
    } catch (e) {
      if (mounted) {
        final err = NativeNovaService.friendlyError(e);
        _failPrdTurnInChat(assistantMsgId: job.assistantMsgId, message: err);
        if (err.isNotEmpty) _toast(err, error: true);
      }
      await clearNovaPrdPendingJob(
        userId: widget.session.userId,
        conversationId: _conversationId,
      );
    }
  }

  void _updatePrdAssistantThinkStatus(int assistantMsgId, String status) {
    if (!mounted) return;
    setState(() {
      _busyHint = status;
      final idx = _messages.indexWhere((m) => m.id == assistantMsgId);
      if (idx >= 0) {
        final copy = [..._messages];
        copy[idx] = copy[idx].copyWith(thinkStatus: status);
        _messages = copy;
      }
    });
  }

  Future<NativeKbDocument> _requireIndexedKbDocument({
    required NativeMeetingDetail detail,
    required int assistantMsgId,
  }) async {
    await _kbService.ensureNovaReady();
    final kbFileName = MeetingMinutesExport.kbUploadFileName(detail);
    final kbTitle = MeetingMinutesExport.kbUploadTitle(detail);

    _updatePrdAssistantThinkStatus(assistantMsgId, '正在确认知识库文档…');
    final doc = await _kbService.findMeetingMinutesDocument(
      meetingId: detail.meetingId,
      kbFileName: kbFileName,
      kbTitle: kbTitle,
    );
    if (doc == null) {
      throw Exception('该会议纪要未在知识库中找到，请先在会议详情页上传至知识库');
    }
    if (!nativeKbDocumentIndexed(doc)) {
      throw Exception('该会议纪要尚未完成知识库索引，请稍后再试');
    }
    return doc;
  }

  /// 引用已索引的知识库文档，以纯文字发给 NOVA 生成 PRD。
  Future<void> _ensureKbAndSendPrdToNova({
    required NovaPrdPendingJob job,
    NativeMeetingDetail? detail,
  }) async {
    await _ensureConversationId();
    if (!mounted || _conversationId <= 0) {
      throw Exception('无法创建 NOVA 会话，请稍后重试');
    }

    final meetingService = NativeMeetingService(session: widget.session);
    final resolvedDetail =
        detail ??
        (job.meetingId > 0
            ? await meetingService.fetchDetail(job.meetingId)
            : null);
    if (resolvedDetail == null) {
      throw Exception('无法加载会议纪要，请稍后重试');
    }

    final kbDoc = await _requireIndexedKbDocument(
      detail: resolvedDetail,
      assistantMsgId: job.assistantMsgId,
    );
    if (!mounted) return;

    final resolvedKbFileName = kbDoc.fileName.trim().isNotEmpty
        ? kbDoc.fileName.trim()
        : job.kbFileName.trim();
    final novaPrompt = buildMeetingPrdNovaMessage(
      kbFileName: resolvedKbFileName,
      prdFileName: job.prdFileName,
    );
    final displayText = buildMeetingPrdDisplayText(resolvedKbFileName);

    _updatePrdAssistantThinkStatus(job.assistantMsgId, '正在生成 PRD…');
    if (mounted) {
      setState(() {
        final userIdx = _messages.indexWhere((m) => m.id == job.userMsgId);
        if (userIdx >= 0) {
          final copy = [..._messages];
          copy[userIdx] = copy[userIdx].copyWith(text: displayText);
          _messages = copy;
        }
      });
    }

    var userPersisted = false;
    try {
      // `_saveLocalMessage` 已停用 messages/local，这里只更新本地缓存，不能算「已落库」。
      await _service.persistUserMessage(
        conversationId: _conversationId,
        messageId: job.userMsgId,
        content: displayText,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NativeNovaPage] PRD user persist skipped: $e');
      }
    }

    await _sendMessage(
      text: displayText,
      novaPrompt: novaPrompt,
      existingUserMsgId: job.userMsgId,
      existingAssistantMsgId: job.assistantMsgId,
      userAlreadyPersisted: userPersisted,
      assistantThinkStatus: '正在生成 PRD…',
    );
  }

  void _showPrdPendingTurnInChat({
    required int userMsgId,
    required int assistantMsgId,
    required String displayText,
  }) {
    setState(() {
      _busyHint = '正在检查知识库…';
      _messages = [
        ..._messages.where((m) => !m.isWelcome),
        NativeNovaMessage(
          id: userMsgId,
          role: 'user',
          text: displayText,
          createdAt: DateTime.fromMillisecondsSinceEpoch(userMsgId),
          kind: 'TEXT',
        ),
        NativeNovaMessage(
          id: assistantMsgId,
          role: 'assistant',
          text: '',
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            userMsgId,
          ).add(const Duration(milliseconds: 1)),
          streaming: true,
          thinkStatus: '正在检查知识库…',
        ),
      ];
      _banner = null;
    });
    _scrollBottom();
  }

  void _failPrdTurnInChat({
    required int assistantMsgId,
    required String message,
  }) {
    setState(() {
      _busyHint = '';
      final idx = _messages.indexWhere((m) => m.id == assistantMsgId);
      if (idx >= 0) {
        final copy = [..._messages];
        copy[idx] = copy[idx].copyWith(
          streaming: false,
          text: message,
          thinkStatus: '',
        );
        _messages = copy;
      }
    });
  }

  Future<void> _openKbSourcePicker() async {
    if (!_novaReady || _isGenerating || _sending) return;
    FocusScope.of(context).unfocus();
    final source = await showNovaKbSourcePicker(
      context,
      kbService: _kbService,
      meetingService: _meetingService,
      onOpenLibrary: widget.onOpenKb,
    );
    if (!mounted || source == null) return;
    await _enterScopedConversation(source);
  }

  Future<void> _openMeetingSourcePicker() async {
    if (!_novaReady || _isGenerating || _sending) return;
    FocusScope.of(context).unfocus();
    final source = await showNovaMeetingSourcePicker(
      context,
      meetingService: _meetingService,
      onOpenLibrary: widget.onOpenMeeting,
    );
    if (!mounted || source == null) return;
    await _enterScopedConversation(source);
  }

  Future<void> _enterScopedConversation(NovaAnalysisSource source) async {
    _showNovaChatTab();
    if (_messages.any((m) => !m.isWelcome)) {
      await _startNewChat(scopedSource: source, announce: false);
      return;
    }
    _replaceAnalysisSources(mergeNovaAnalysisSources(_analysisSources, source));
  }

  void _removeAnalysisSource(NovaAnalysisSource source) {
    _replaceAnalysisSources(
      _analysisSources
          .where((item) => item.scopeKey != source.scopeKey)
          .toList(growable: false),
    );
  }

  Future<void> _openMeetingPrdFlow() async {
    if (!_novaReady || _isGenerating || _sending) return;
    int? prdAssistantMsgId;
    try {
      final meetingService = NativeMeetingService(session: widget.session);
      setState(() => _busyHint = '正在加载可生成 PRD 的知识库文档…');
      final meetings = await meetingService.fetchList(page: 0, size: 50);
      await _kbService.ensureNovaReady();
      final exportable = meetings
          .where(MeetingMinutesExport.isListItemLikelyExportable)
          .toList(growable: false);
      final kbIndexedMeetings = await _kbService.filterMeetingsWithIndexedKb(
        exportable,
      );
      final kbDocs = await _kbService.listIndexedDocumentsForPrd();
      if (!mounted) return;
      setState(() => _busyHint = '');

      // 优先会议列表；若无匹配会议则回退展示知识库已索引文档。
      if (kbIndexedMeetings.isNotEmpty) {
        final picked = await showMeetingMinutesPickerDialog(
          context,
          meetings: kbIndexedMeetings,
        );
        if (picked == null || !mounted) return;
        prdAssistantMsgId = await _startPrdFromMeeting(
          meetingService: meetingService,
          meetingId: picked.meetingId,
        );
        return;
      }

      if (kbDocs.isEmpty) {
        await showMeetingMinutesPickerDialog(
          context,
          meetings: const <NativeMeetingSummary>[],
        );
        return;
      }

      final kbPicked = await showKbDocumentPickerDialog(
        context,
        documents: kbDocs,
      );
      if (kbPicked == null || !mounted) return;
      prdAssistantMsgId = await _startPrdFromKbDocument(kbPicked);
    } catch (e) {
      if (mounted) {
        final err = NativeNovaService.friendlyError(e);
        if (prdAssistantMsgId != null) {
          _failPrdTurnInChat(assistantMsgId: prdAssistantMsgId, message: err);
        }
        if (err.isNotEmpty) _toast(err, error: true);
      }
    }
  }

  Future<int?> _startPrdFromMeeting({
    required NativeMeetingService meetingService,
    required int meetingId,
  }) async {
    final detail = await meetingService.fetchDetail(meetingId);
    if (!mounted) return null;
    if (!MeetingMinutesExport.canExport(detail)) {
      _toast('该会议纪要尚未生成完成', error: true);
      return null;
    }

    final kbDoc = await _kbService.findIndexedMeetingMinutesDocument(
      meetingId: detail.meetingId,
      kbFileName: MeetingMinutesExport.kbUploadFileName(detail),
      kbTitle: MeetingMinutesExport.kbUploadTitle(detail),
    );
    if (kbDoc == null) {
      _toast('该会议纪要尚未在知识库中完成索引，请稍后再试', error: true);
      return null;
    }

    final prdModel = await _pickPrdGenerationModel();
    if (!mounted || prdModel == null || prdModel.trim().isEmpty) return null;

    final meetingTitle = detail.title.trim().isNotEmpty
        ? detail.title.trim()
        : '未命名会议';
    final confirmed = await showMeetingPrdConfirmDialog(
      context,
      meetingTitle: meetingTitle,
      modelName: novaModelDisplayName(prdModel),
    );
    if (!confirmed || !mounted) return null;

    _applySelectedChatModel(prdModel);

    if (detail.summary.trim().isEmpty) {
      _toast('该会议纪要尚无摘要，无法生成 PRD', error: true);
      return null;
    }

    final kbFileName = kbDoc.fileName.trim().isNotEmpty
        ? kbDoc.fileName.trim()
        : MeetingMinutesExport.kbUploadFileName(detail);
    final kbTitle = MeetingMinutesExport.kbUploadTitle(detail);
    final prdFileName = MeetingMinutesExport.prdFileName(detail);
    final displayText = buildMeetingPrdDisplayText(kbFileName);
    final messageText = buildMeetingPrdNovaMessage(
      kbFileName: kbFileName,
      prdFileName: prdFileName,
    );

    final userMsgId = DateTime.now().millisecondsSinceEpoch;
    final assistantMsgId = userMsgId + 1;
    final pendingJob = NovaPrdPendingJob(
      at: DateTime.now().millisecondsSinceEpoch,
      meetingId: detail.meetingId,
      prdModel: prdModel,
      userMsgId: userMsgId,
      assistantMsgId: assistantMsgId,
      messageText: messageText,
      kbFileName: kbFileName,
      kbTitle: kbTitle,
      prdFileName: prdFileName,
      meetingTitle: meetingTitle,
    );
    _showPrdPendingTurnInChat(
      userMsgId: userMsgId,
      assistantMsgId: assistantMsgId,
      displayText: displayText,
    );
    await _persistPrdPendingTurn(
      userMsgId: userMsgId,
      assistantMsgId: assistantMsgId,
      displayText: displayText,
      pendingJob: pendingJob,
    );
    if (!mounted) return assistantMsgId;

    _prdResumeInFlight = true;
    try {
      await _ensureKbAndSendPrdToNova(job: pendingJob, detail: detail);
    } finally {
      _prdResumeInFlight = false;
    }
    return assistantMsgId;
  }

  Future<int?> _startPrdFromKbDocument(NativeKbDocument kbDoc) async {
    final prdModel = await _pickPrdGenerationModel();
    if (!mounted || prdModel == null || prdModel.trim().isEmpty) return null;

    final title = kbDoc.title.trim().isNotEmpty
        ? kbDoc.title.trim()
        : (kbDoc.fileName.trim().isNotEmpty ? kbDoc.fileName.trim() : '知识库文档');
    final confirmed = await showMeetingPrdConfirmDialog(
      context,
      meetingTitle: title,
      modelName: novaModelDisplayName(prdModel),
    );
    if (!confirmed || !mounted) return null;

    _applySelectedChatModel(prdModel);

    final kbFileName = kbDoc.fileName.trim().isNotEmpty
        ? kbDoc.fileName.trim()
        : title;
    final safeBase = title.replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_');
    final prdFileName = 'PRD-$safeBase.md';
    final displayText = buildMeetingPrdDisplayText(kbFileName);
    final messageText = buildMeetingPrdNovaMessage(
      kbFileName: kbFileName,
      prdFileName: prdFileName,
    );

    final userMsgId = DateTime.now().millisecondsSinceEpoch;
    final assistantMsgId = userMsgId + 1;
    final pendingJob = NovaPrdPendingJob(
      at: DateTime.now().millisecondsSinceEpoch,
      meetingId: 0,
      prdModel: prdModel,
      userMsgId: userMsgId,
      assistantMsgId: assistantMsgId,
      messageText: messageText,
      kbFileName: kbFileName,
      kbTitle: title,
      prdFileName: prdFileName,
      meetingTitle: title,
    );
    _showPrdPendingTurnInChat(
      userMsgId: userMsgId,
      assistantMsgId: assistantMsgId,
      displayText: displayText,
    );
    await _persistPrdPendingTurn(
      userMsgId: userMsgId,
      assistantMsgId: assistantMsgId,
      displayText: displayText,
      pendingJob: pendingJob,
    );
    if (!mounted) return assistantMsgId;

    _prdResumeInFlight = true;
    try {
      await _sendPrdFromKbFileName(
        job: pendingJob,
        displayText: displayText,
        novaPrompt: messageText,
      );
    } finally {
      _prdResumeInFlight = false;
    }
    return assistantMsgId;
  }

  Future<void> _sendPrdFromKbFileName({
    required NovaPrdPendingJob job,
    required String displayText,
    required String novaPrompt,
  }) async {
    await _ensureConversationId();
    if (!mounted || _conversationId <= 0) {
      throw Exception('无法创建 NOVA 会话，请稍后重试');
    }

    _updatePrdAssistantThinkStatus(job.assistantMsgId, '正在生成 PRD…');
    if (mounted) {
      setState(() {
        final userIdx = _messages.indexWhere((m) => m.id == job.userMsgId);
        if (userIdx >= 0) {
          final copy = [..._messages];
          copy[userIdx] = copy[userIdx].copyWith(text: displayText);
          _messages = copy;
        }
      });
    }

    var userPersisted = false;
    try {
      // `_saveLocalMessage` 已停用 messages/local，这里只更新本地缓存，不能算「已落库」。
      await _service.persistUserMessage(
        conversationId: _conversationId,
        messageId: job.userMsgId,
        content: displayText,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NativeNovaPage] PRD user persist skipped: $e');
      }
    }

    await _sendMessage(
      text: displayText,
      novaPrompt: novaPrompt,
      existingUserMsgId: job.userMsgId,
      existingAssistantMsgId: job.assistantMsgId,
      userAlreadyPersisted: userPersisted,
      assistantThinkStatus: '正在生成 PRD…',
    );
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    showDunesToast(
      context,
      msg,
      kind: error || dunesToastLooksLikeError(msg)
          ? DunesToastKind.error
          : DunesToastKind.normal,
    );
  }

  Future<void> _openTauVoiceCall() async {
    if (!_novaReady) return;
    if (MeetingLiveController.instance.isActive) {
      _toast('会议录音进行中，暂无法使用 τ 电话');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => TauVoiceCallPage(
          session: widget.session,
          onProfessionalPrompt: (heardText) async {
            if (_isTauIdentityQuestion(heardText)) return '我是韬';
            await _sendMessage(text: heardText);
            final assistant = _messages.lastWhere(
              (message) => message.role == 'assistant',
              orElse: () => const NativeNovaMessage(
                id: 0,
                role: 'assistant',
                text: '',
                createdAt: null,
              ),
            );
            return assistant.text.trim();
          },
        ),
      ),
    );
  }

  bool _isTauIdentityQuestion(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    return compact.contains('你是谁') ||
        compact.contains('你叫什么') ||
        compact.contains('你的名字') ||
        compact.contains('你是哪个') ||
        compact.contains('你是小智') ||
        compact.contains('是不是小智') ||
        compact.contains('叫小智');
  }

  @override
  Widget build(BuildContext context) {
    final inputEnabled = _novaReady && !_startingNewChat;
    final inputHint = !_novaReady
        ? 'NOVA尚未就绪'
        : switch (_personalMode) {
            NovaPersonalCapability.tasks => '只问任务...',
            NovaPersonalCapability.lighthouse => '只问灯塔...',
            null => switch (_autoPersonalMode) {
              NovaPersonalCapability.tasks => '继续问任务，或问其他问题...',
              NovaPersonalCapability.lighthouse => '继续问灯塔，或问其他问题...',
              null => kNovaInputPlaceholder,
            },
          };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: DunesColors.resolve(
          context,
          const Color(0xFFF6F8FC),
          role: DunesColorRole.surface,
        ),
        drawer: SizedBox(
          width: MediaQuery.sizeOf(context).width < 450
              ? MediaQuery.sizeOf(context).width * 0.82
              : 360,
          child: NovaSideDrawer(
            session: widget.session,
            userName: _userName,
            userAvatarUrl: _userAvatarUrl,
            currentConversationId: _conversationId,
            onNewChat: () {
              if (_novaReady) _startNewChat();
            },
            onOpenConversation: (cid, mid, title, preview) {
              _openConversationFromDrawer(cid);
            },
            onOpenHistoryAll: () {
              widget.onHistory?.call();
            },
            onOpenKb: widget.onOpenKb,
            onCurrentConversationDeleted: () {
              if (_novaReady) _startNewChat();
            },
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: MeetingLiveController.instance.active,
                      builder: (context, meetingLive, _) {
                        return NovaPageHeader(
                          tabController: _tabController,
                          onBack: _handleBack,
                          onNewChat: _novaReady ? _startNewChat : null,
                          onHistory: widget.onHistory,
                          onOpenKb: widget.onOpenKb,
                          onVoiceCall: _novaReady ? _openTauVoiceCall : null,
                          onOpenDrawer: () =>
                              _scaffoldKey.currentState?.openDrawer(),
                          actionsEnabled: true,
                          voiceCallBlocked: meetingLive,
                        );
                      },
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _NovaTabKeepAlive(
                            child: NovaMcpServicesView(
                              session: widget.session,
                              onOpenDigitalEmployee:
                                  widget.onOpenDigitalEmployee,
                            ),
                          ),
                          _NovaTabKeepAlive(
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : _buildNovaChatPane(),
                          ),
                        ],
                      ),
                    ),
                    if (_isNovaChatTab) ...[
                      // 思考气泡里已经显示进度时不再在输入框上方重复一行。
                      NovaC4BusyHint(
                        text: _hasActiveAssistantStream() ? '' : _busyHint,
                      ),
                      if (_insight != null && !_sending)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                          child: NovaInsightCard(
                            insight: _insight!,
                            enabled: _novaReady,
                            dark:
                                Theme.of(context).brightness == Brightness.dark,
                            onAsk: (text) => unawaited(_askInsight(text)),
                            onDismiss: _dismissInsight,
                          ),
                        ),
                      NovaSourceChipTray(
                        sources: _analysisSources,
                        onRemove: _removeAnalysisSource,
                      ),
                      NovaDraftTray(items: _drafts, onRemove: _removeDraft),
                      ValueListenableBuilder<bool>(
                        valueListenable: MeetingLiveController.instance.active,
                        builder: (context, meetingLive, _) {
                          final voiceBlocked = !inputEnabled || meetingLive;
                          final effectiveVoiceMode = voiceBlocked
                              ? false
                              : _voiceMode;
                          return NovaC4InputBar(
                            controller: _inputController,
                            focusNode: _inputFocusNode,
                            onInputFocused: _scrollToLatestAfterKeyboard,
                            voiceMode: effectiveVoiceMode,
                            sending: _isGenerating,
                            enabled: inputEnabled,
                            hintText: inputHint,
                            onToggleVoice: voiceBlocked
                                ? () {
                                    if (meetingLive) {
                                      _toast('会议录音进行中，暂无法发送语音');
                                    }
                                  }
                                : () =>
                                      setState(() => _voiceMode = !_voiceMode),
                            onSend: _submitInput,
                            // 手动选定的板块优先；否则显示上一句自动路由走的板块。
                            capability: _personalMode ?? _autoPersonalMode,
                            onCapabilityChanged: (mode) {
                              setState(() {
                                _personalMode = mode;
                                _autoPersonalMode = null;
                              });
                            },
                            onPickModel: _pickModel,
                            modelLabel: novaModelDisplayName(_selectedModel),
                            quickActionsOpen: _quickActionsOpen,
                            onToggleQuickActions: () {
                              setState(
                                () => _quickActionsOpen = !_quickActionsOpen,
                              );
                            },
                            onStop: _stopGeneration,
                            onCamera: _pickCamera,
                            onAlbum: _pickAlbum,
                            onOpenMeeting: _openMeetingSourcePicker,
                            onMeetingPrd: _openMeetingPrdFlow,
                            onOpenKb: _openKbSourcePicker,
                            onVoiceCall: _novaReady ? _openTauVoiceCall : null,
                            onNewChat: _novaReady ? _startNewChat : null,
                            onHistory: widget.onHistory,
                            voiceCallBlocked: meetingLive,
                            onAttach:
                                inputEnabled &&
                                    NovaConfig.fileUploadInChatEnabled
                                ? _pickFile
                                : null,
                            recording: _recording,
                            recordWillCancel:
                                _recordAction == VoiceHoldAction.cancel,
                            recordDurationMs: _recordDurationMs,
                            onVoiceHoldStart: voiceBlocked
                                ? null
                                : (details) =>
                                      _startHoldRecord(details.globalPosition),
                            onVoiceHoldMove: _onRecordMove,
                            onVoiceHoldEnd: (_) => _finishHoldRecord(),
                            onVoiceHoldCancel: () =>
                                _cancelHoldRecord(showHint: false),
                          );
                        },
                      ),
                    ],
                  ],
                ),
                if (_recording)
                  VoiceRecordingOverlay(
                    durationMs: _recordDurationMs,
                    action: _recordAction,
                    transcribeEnabled: false,
                    focalPoint: _recordFocalPoint,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNovaChatPane() {
    return NovaC4MessageStream(
      child: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            layoutBuilder: (currentChild, _) =>
                currentChild ?? const SizedBox.shrink(),
            child: _isEmptyConversation
                ? _buildWelcomeList()
                : _buildMessageList(),
          ),
          if (_showJumpToLatest)
            Positioned(
              right: 16,
              bottom: 12,
              child: _NovaJumpToLatestButton(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _scrollBottom(force: true, animate: true);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWelcomeList() {
    return ListView(
      key: const ValueKey('nova-welcome'),
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 24),
      children: [
        if (_banner != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: NovaStatusBanner(message: _banner!, onRetry: _load),
          ),
        NovaAiPartnerWelcomeView(
          name: '小饕',
          subtitle: '你在沙丘上的AI全能伙伴',
          onSelectPrompt: _handlePromptCardTapped,
          onSelectCapability: (capability, prompt) {
            unawaited(_handlePersonalCapability(capability, prompt));
          },
          onSubmitFeedback: (kind, content) =>
              _service.submitFeedback(kind: kind, content: content),
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    final items = _messageListItems();
    final bannerOffset = _banner != null ? 1 : 0;
    final scopeOffset = _analysisSources.isNotEmpty ? 1 : 0;
    return ListView.builder(
      key: const ValueKey('nova-messages'),
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      addAutomaticKeepAlives: false,
      itemCount: bannerOffset + scopeOffset + items.length,
      itemBuilder: (context, index) {
        if (_banner != null && index == 0) {
          return NovaStatusBanner(message: _banner!, onRetry: _load);
        }
        if (_analysisSources.isNotEmpty && index == bannerOffset) {
          return NovaConversationScopeCard(
            sources: _analysisSources,
            margin: const EdgeInsets.only(bottom: 12),
          );
        }
        final item = items[index - bannerOffset - scopeOffset];
        if (item.dividerLabel != null) {
          return NovaMsgDateDivider(label: item.dividerLabel!);
        }
        return _buildMessageRow(item.message!);
      },
    );
  }

  List<_NovaTimelineItem> _messageListItems() {
    final items = <_NovaTimelineItem>[];
    DateTime? prevAt;
    for (final m in collapseNovaStreamingPlaceholders(_messages)) {
      if (m.isWelcome) {
        if (_analysisSources.isNotEmpty) continue;
      } else {
        final label = historyDayDividerLabel(m.createdAt, prevAt);
        if (label != null) {
          items.add(_NovaTimelineItem.divider(label));
        }
        prevAt = m.createdAt;
      }
      items.add(_NovaTimelineItem.message(m));
    }
    return items;
  }

  bool get _isEmptyConversation => novaShouldShowWelcome(
    hasRealTurns: _messages.any((message) => !message.isWelcome),
    hasSources: _analysisSources.isNotEmpty,
  );

  bool _canResendUserMessage(NativeNovaMessage m) {
    if (m.role != 'user') return false;
    if (_sending ||
        _resendPreparing ||
        _serverGenerating ||
        _hasActiveAssistantStream()) {
      return false;
    }
    final idx = _messages.indexWhere((x) => x.id == m.id);
    if (idx < 0) return false;
    for (var i = idx + 1; i < _messages.length; i++) {
      final n = _messages[i];
      if (n.isWelcome) continue;
      if (n.role == 'user') return true;
      if (n.role == 'assistant') {
        final hasBody =
            n.text.trim().isNotEmpty ||
            n.thinkText.trim().isNotEmpty ||
            n.streaming ||
            n.attachments.isNotEmpty;
        if (hasBody &&
            n.payload?['nova_retryable'] != true &&
            m.payload?['nova_retryable'] != true) {
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _copyAssistantReply(NativeNovaMessage m) async {
    final value = novaAssistantCopyText(m.text);
    if (value.isEmpty) {
      showDunesToast(context, '暂无可复制内容');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) showDunesToast(context, '已复制');
    } catch (_) {
      if (mounted) {
        showDunesToast(context, '复制失败，请重试', kind: DunesToastKind.error);
      }
    }
  }

  Future<void> _forwardAssistantReply(NativeNovaMessage m) async {
    final value = novaAssistantCopyText(m.text);
    if (value.isEmpty) {
      showDunesToast(context, '暂无可转发内容');
      return;
    }
    final conversationId = await showConversationPickerSheet(
      context: context,
      service: _avatarService,
      title: '转发到 IM',
    );
    if (conversationId == null || conversationId <= 0 || !mounted) return;
    try {
      await _avatarService.sendText(
        conversationId,
        value,
        payload: <String, dynamic>{
          'forwardedFromNova': true,
          // 纯文字按普通消息发（宽度自适应、可选取复制）；
          // 只有确实含 Markdown 排版时才按富文本卡片渲染。
          if (novaTextHasMarkdown(value)) 'robotMarkdown': true,
        },
      );
      if (mounted) showDunesToast(context, '已转发到会话');
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          '转发失败：${friendlyErrorText(e, fallback: '请稍后重试')}',
          kind: DunesToastKind.error,
        );
      }
    }
  }

  Widget _messageBubble(NativeNovaMessage m) {
    final mine = m.role == 'user';
    final time = m.isWelcome ? '' : novaMsgTimeLabel(m.createdAt);
    final thinking =
        !mine &&
        m.text.isEmpty &&
        m.streaming &&
        (_sending || _serverGenerating);
    final key = m.id > 0 ? _messageKeys.putIfAbsent(m.id, GlobalKey.new) : null;
    return KeyedSubtree(
      key: ValueKey('nova-msg-${m.id}-${m.role}'),
      child: RepaintBoundary(
        key: key,
        child: NovaC4MessageRow(
          mine: mine,
          text: m.text,
          messageId: m.id,
          time: time,
          userName: mine ? _userName : '',
          userInitial: _userInitial,
          userSeed: widget.session.userId,
          userAvatarPreset: _userAvatarPreset,
          userAvatarObjectKey: _userAvatarObjectKey,
          userAvatarUrl: _userAvatarUrl,
          avatarService: _avatarService,
          thinking: thinking,
          showAiBadge: true,
          thinkText: m.thinkText,
          thinkStatus: m.thinkStatus,
          streaming: m.streaming,
          attachments: m.attachments,
          kind: m.kind,
          durationSec: m.durationSec,
          mediaResolver: _mediaResolver,
          highlighted: m.id > 0 && m.id == _highlightMessageId,
          ragUsed: m.ragUsed,
          onRetryReply:
              !_isGenerating &&
                  m.payload?['nova_retryable'] == true &&
                  _questionOf(m) != null
              ? () => unawaited(_resendUserMessage(_questionOf(m)!))
              : null,
          onResend: _canResendUserMessage(m)
              ? () => unawaited(_resendUserMessage(m))
              : null,
          onCopyReply: !mine && !thinking
              ? () => unawaited(_copyAssistantReply(m))
              : null,
          onForwardReply: !mine && !thinking
              ? () => unawaited(_forwardAssistantReply(m))
              : null,
        ),
      ),
    );
  }

  Widget _buildMessageRow(NativeNovaMessage m) {
    final row = _messageBubble(m);
    final finishedReply =
        m.role == 'assistant' && !m.streaming && m.text.trim().isNotEmpty;
    final latestReply =
        finishedReply && _messages.isNotEmpty && _messages.last.id == m.id;
    final chart = finishedReply ? _chartOf(m) : null;
    final lighthouseQuestion = latestReply ? _latestLighthouseQuestion() : null;
    final suggestions = latestReply && _taskPreview == null
        ? _suggestionsOf(m)
        : const <String>[];
    final showPreview = _taskPreview != null && m.id == _previewMessageId;
    if (chart == null &&
        lighthouseQuestion == null &&
        suggestions.isEmpty &&
        !showPreview) {
      return row;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        if (chart != null)
          Padding(
            padding: const EdgeInsets.only(left: 48, right: 16, bottom: 8),
            child: NovaChartCard(
              key: ValueKey('nova-chart-${m.id}'),
              chart: chart,
              dark: Theme.of(context).brightness == Brightness.dark,
            ),
          ),
        if (suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 48, right: 16, bottom: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final suggestion in suggestions)
                  ActionChip(
                    key: ValueKey('nova-suggestion-$suggestion'),
                    label: Text(
                      suggestion,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onPressed: _sending
                        ? null
                        : () => unawaited(_askSuggestion(m, suggestion)),
                  ),
              ],
            ),
          ),
        if (lighthouseQuestion != null)
          Padding(
            padding: const EdgeInsets.only(left: 48, bottom: 8),
            child: TextButton(
              key: const ValueKey('nova-lighthouse-as-chat'),
              style: TextButton.styleFrom(
                foregroundColor: DunesColors.resolve(
                  context,
                  DunesColors.text3,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 12),
              ),
              onPressed: _sending
                  ? null
                  : () => unawaited(_answerAsChat(lighthouseQuestion)),
              child: const Text('改用通用问答'),
            ),
          ),
        if (showPreview)
          Padding(
            padding: const EdgeInsets.only(left: 48, bottom: 8),
            child: Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _sending
                      ? null
                      : () => unawaited(_confirmTaskPreview()),
                  child: const Text('确认执行'),
                ),
                TextButton(
                  onPressed: _sending ? null : _cancelTaskPreview,
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _NovaTimelineItem {
  const _NovaTimelineItem._({this.dividerLabel, this.message});

  factory _NovaTimelineItem.divider(String label) =>
      _NovaTimelineItem._(dividerLabel: label);

  factory _NovaTimelineItem.message(NativeNovaMessage message) =>
      _NovaTimelineItem._(message: message);

  final String? dividerLabel;
  final NativeNovaMessage? message;
}

class _NovaJumpToLatestButton extends StatelessWidget {
  const _NovaJumpToLatestButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      elevation: 3,
      shadowColor: const Color(0x3318274B),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.arrow_downward_rounded,
                size: 15,
                color: DunesColors.resolveNullable(context, Color(0xFF6B3FE2)),
              ),
              SizedBox(width: 4),
              Text(
                '回到最新',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolveNullable(
                    context,
                    Color(0xFF6B3FE2),
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

class _NovaTabKeepAlive extends StatefulWidget {
  const _NovaTabKeepAlive({required this.child});

  final Widget child;

  @override
  State<_NovaTabKeepAlive> createState() => _NovaTabKeepAliveState();
}

class _NovaTabKeepAliveState extends State<_NovaTabKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
