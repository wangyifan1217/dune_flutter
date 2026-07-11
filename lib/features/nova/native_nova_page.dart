import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'native_nova_service.dart';
import 'nova_background_coordinator.dart';
import 'nova_draft.dart';
import 'nova_generating_storage.dart';
import 'nova_history_utils.dart';
import 'nova_image_utils.dart';
import 'nova_media.dart';
import 'nova_meeting_prd.dart';
import 'nova_models_service.dart';
import 'nova_web_storage.dart';
import 'nova_stream_parser.dart';
import 'nova_widgets.dart';

class NativeNovaPage extends StatefulWidget {
  const NativeNovaPage({
    super.key,
    required this.session,
    required this.onBack,
    this.onHistory,
    this.onOpenKb,
    this.onOpenMeeting,
    this.focusConversationId,
    this.focusMessageId,
    this.onClearHistoryFocus,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final VoidCallback? onHistory;
  final VoidCallback? onOpenKb;
  final VoidCallback? onOpenMeeting;
  final int? focusConversationId;
  final int? focusMessageId;
  final VoidCallback? onClearHistoryFocus;

  @override
  State<NativeNovaPage> createState() => _NativeNovaPageState();
}

class _NativeNovaPageState extends State<NativeNovaPage>
    with WidgetsBindingObserver {
  late final NativeNovaService _service;
  late final NativeKbService _kbService;
  late final ConversationService _avatarService;
  late final NovaMediaResolver _mediaResolver;
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _messageKeys = <int, GlobalKey>{};

  bool _loading = true;
  bool _sending = false;
  bool _serverGenerating = false;
  bool _novaReady = true;
  bool _voiceMode = false;
  bool _quickActionsOpen = false;
  bool _recording = false;
  bool _recordWillCancel = false;
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
  List<NativeNovaMessage> _messages = const <NativeNovaMessage>[];
  List<String> _chatModels = const <String>[];
  String _selectedModel = '';
  List<NovaModelCatalogEntry> _modelCatalog = const <NovaModelCatalogEntry>[];
  List<NovaDraftAttachment> _drafts = const <NovaDraftAttachment>[];
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
    _avatarService = ConversationService(session: widget.session);
    _mediaResolver = NovaMediaResolver(widget.session, service: _service);
    _inputFocusNode.addListener(_onInputFocusChanged);
    userAvatarRefresh.addListener(_onSelfAvatarUpdated);
    _load();
    MeetingLiveController.instance.active.addListener(
      _onMeetingLiveActiveChanged,
    );
    NovaBackgroundCoordinator.instance.addListener(_onNovaBackgroundUpdate);
    NovaBackgroundCoordinator.instance.setNovaPageActive(true);
  }

  @override
  void activate() {
    super.activate();
    NovaBackgroundCoordinator.instance.setNovaPageActive(true);
    NovaBackgroundCoordinator.instance.clearPendingCommBadgeBump();
  }

  void _onNovaBackgroundUpdate() {
    if (!mounted || _conversationId <= 0) return;
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

  @override
  void didUpdateWidget(covariant NativeNovaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldConv = oldWidget.focusConversationId ?? 0;
    final newConv = widget.focusConversationId ?? 0;
    final oldMsg = oldWidget.focusMessageId ?? 0;
    final newMsg = widget.focusMessageId ?? 0;
    if (oldConv != newConv || oldMsg != newMsg) {
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
    _streamDraftTimer?.cancel();
    _genPollTimer?.cancel();
    _recordTicker?.cancel();
    unawaited(_discardAsrPcmCapture());
    unawaited(_flushOnLeave());
    if (_recording) {
      unawaited(NativeAudioRecorder.instance.cancel());
    }
    _inputFocusNode.removeListener(_onInputFocusChanged);
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
      unawaited(_flushOnAppBackground());
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    unawaited(_onAppResumed());
  }

  Future<void> _flushOnAppBackground() async {
    if (_conversationId <= 0) return;
    final stopped = _service.userStoppedStream || _isStoppedStatus(_busyHint);
    if (stopped) return;
    final active =
        _sending ||
        _serverGenerating ||
        _hasActiveAssistantStream() ||
        _service.isStreamInFlight;
    if (!active) return;

    final status = _busyHint.isNotEmpty ? _busyHint : kNovaInputBusyHint;
    if (_genAfterMessageId <= 0) {
      final user = _messages.cast<NativeNovaMessage?>().lastWhere(
        (m) => m?.role == 'user',
        orElse: () => null,
      );
      if (user != null && user.id > 0) _genAfterMessageId = user.id;
    }
    await _markGenerating(status: status, afterMessageId: _genAfterMessageId);
    final assistant = _messages.cast<NativeNovaMessage?>().lastWhere(
      (m) => m?.role == 'assistant' && (m?.streaming ?? false),
      orElse: () => null,
    );
    if (assistant != null) {
      await persistNovaStreamDraftState(
        userId: widget.session.userId,
        conversationId: _conversationId,
        status: status,
        afterMessageId: _genAfterMessageId,
        userText: _lastUserDisplayText,
        thinkText: assistant.thinkText,
        text: assistant.text,
        streaming: assistant.streaming,
      );
    } else if (_lastUserDisplayText.trim().isNotEmpty) {
      await persistNovaStreamDraftState(
        userId: widget.session.userId,
        conversationId: _conversationId,
        status: status,
        afterMessageId: _genAfterMessageId,
        userText: _lastUserDisplayText,
        streaming: true,
      );
    }
    NovaBackgroundCoordinator.instance.ensurePoll(
      widget.session,
      conversationId: _conversationId,
    );
  }

  Future<void> _onAppResumed() async {
    if (!mounted || _conversationId <= 0) return;
    final storage = await NovaWebStorage.load(widget.session.userId);
    final draft = readNovaStreamDraftFromStorage(storage, _conversationId);
    final localGen = readNovaGeneratingFromStorage(
      storage,
      convId: _conversationId,
      activeConvId: _conversationId,
    );
    final hadActiveGeneration = _isGenerating || _service.isStreamInFlight;
    final draftRecoverable =
        draft != null &&
        novaStreamDraftHasContent(draft) &&
        !_hasAiReplyAfter(_messages, draft.afterMessageId);

    if (!hadActiveGeneration && !draftRecoverable && localGen == null) return;

    try {
      final history = await _service.fetchFullHistory(_conversationId);
      if (!mounted) return;
      final resolved = _resolveGeneratingState(
        msgs: history.messages,
        serverGenerating: history.assistantGenerating,
        generatingStatus: history.generatingStatus,
        generatingAfter: history.generatingAfterMessageId,
        localGen: localGen,
        draft: draft,
      );
      var generating = resolved.generating;
      if (!generating && draftRecoverable) {
        generating = true;
      }
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
        _sending = generating;
        _busyHint = generating
            ? (resolved.status.isNotEmpty
                  ? resolved.status
                  : (draft?.status ?? kNovaInputBusyHint))
            : '';
      });
      if (generating) {
        if (_service.isStreamInFlight) {
          _startStreamDraftWatcher();
        } else {
          unawaited(_pollGenerating());
        }
      } else if (draftRecoverable) {
        final msgs = await _recoverMessagesIfNeeded(
          _withWelcome(history.messages),
          draft: draft,
        );
        if (!mounted) return;
        setState(() => _messages = msgs);
      }
    } catch (_) {
      if (!mounted || !draftRecoverable || draft == null) return;
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
        _sending = true;
        _busyHint = recoverDraft.status.isNotEmpty
            ? recoverDraft.status
            : kNovaInputBusyHint;
      });
      _startGeneratingPoll();
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _banner = null;
      _busyHint = '';
      _serverGenerating = false;
    });
    _stopGeneratingPoll();
    await Future.wait<void>([_loadModels(), _loadUserAvatar()]);
    try {
      final readiness = await _service.checkReadiness();
      if (!mounted) return;
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
        setState(() {
          _novaReady = false;
          _conversationId = 0;
          _messages = [_welcomeMessage()];
          _busyHint = readiness.message ?? 'NOVA账号尚未开通，请稍后再试';
          _loading = false;
        });
        return;
      }

      final focusedConvId = widget.focusConversationId ?? 0;
      if (focusedConvId > 0) {
        convId = focusedConvId;
        if (kDebugMode) {
          debugPrint('[NativeNovaPage] open focused convId=$convId');
        }
        await _service.persistActiveConversationId(convId);
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
          );
          msgs = history.messages;
          serverGenerating = history.assistantGenerating;
          generatingStatus = history.generatingStatus;
          generatingAfter = history.generatingAfterMessageId;
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
          unawaited(
            clearNovaStreamDraftState(
              userId: widget.session.userId,
              conversationId: convId,
            ),
          );
          unawaited(_service.stripStreamingFromSession(convId));
        } else if (!serverGenerating) {
          unawaited(_service.stripStreamingFromSession(convId));
        }
        if (!serverGenerating && _service.isStreamInFlight) {
          serverGenerating = true;
          if (generatingStatus.isEmpty) generatingStatus = kNovaInputBusyHint;
        }
      }

      if (!mounted) return;
      setState(() {
        _novaReady = true;
        _conversationId = convId;
        _genAfterMessageId = generatingAfter;
        _messages = _mergeGeneratingAndDraft(
          rows: _withWelcome(msgs),
          generating: serverGenerating,
          status: generatingStatus,
          afterMessageId: generatingAfter,
          draft: streamDraft,
        );
        _serverGenerating = serverGenerating;
        _sending = serverGenerating;
        _busyHint = serverGenerating
            ? (generatingStatus.isNotEmpty
                  ? generatingStatus
                  : kNovaInputBusyHint)
            : '';
        _banner = banner;
        _loading = false;
      });
      if (serverGenerating) {
        if (_service.isStreamInFlight) {
          NovaBackgroundCoordinator.instance.stopPoll();
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
      unawaited(_maybeResumePrdGeneration());
      final focusId = widget.focusMessageId;
      if (focusId != null && focusId > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _focusMessage(focusId),
        );
      } else {
        _scrollBottom();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _novaReady = true;
        _conversationId = 0;
        _messages = [_welcomeMessage()];
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
  }) {
    var generating = serverGenerating;
    var status = generatingStatus;
    var after = generatingAfter;
    var clearLocal = false;

    if (generating && after > 0 && _hasAiReplyAfter(msgs, after)) {
      generating = false;
      clearLocal = true;
    }

    if (localGen != null) {
      if (_isStoppedStatus(localGen.status)) {
        generating = false;
        clearLocal = true;
        status = '';
        after = 0;
      } else if (!shouldPersistNovaGenerating(
        localGen: localGen,
        draft: draft,
        streamInFlight: _service.isStreamInFlight,
        hasAiReplyAfter: _hasAiReplyAfter(msgs, localGen.afterMessageId),
      )) {
        generating = false;
        clearLocal = true;
        status = '';
        after = 0;
      } else {
        final afterId = localGen.afterMessageId;
        if (afterId > 0 && _hasAiReplyAfter(msgs, afterId)) {
          generating = false;
          clearLocal = true;
        } else if (!generating) {
          generating = true;
          status = localGen.status;
          after = afterId;
        } else if (status.isEmpty) {
          status = localGen.status;
        }
        if (!clearLocal && after <= 0) after = afterId;
      }
    } else if (!generating &&
        draft != null &&
        novaStreamDraftHasContent(draft) &&
        !_hasAiReplyAfter(msgs, draft.afterMessageId)) {
      generating = true;
      status = draft.status;
      after = draft.afterMessageId;
    }

    return (
      generating: generating,
      status: status,
      afterMessageId: after,
      clearLocal: clearLocal,
    );
  }

  List<NativeNovaMessage> _finalizeMergedMessages(
    List<NativeNovaMessage> rows, {
    bool repair = false,
  }) {
    final deduped = sortNovaMessages(dedupeNovaHistoryMessages(rows));
    return repair ? repairNovaConversationMessages(deduped) : deduped;
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
      final hasUser = novaHasMatchingUserMessage(
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
      if (draft != null &&
          novaStreamDraftHasContent(draft) &&
          effectiveAfter > 0 &&
          !_hasAiReplyAfter(out, effectiveAfter)) {
        final draftText = draft.text;
        final draftThink = draft.thinkText;
        final draftStatus = draft.status.trim();
        final thinkStatus = draftStatus.isNotEmpty ? draftStatus : '正在生成…';
        final streamingIdx = out.indexWhere(
          (m) => m.role == 'assistant' && m.streaming,
        );
        if (streamingIdx >= 0) {
          final current = out[streamingIdx];
          out[streamingIdx] = current.copyWith(
            text: draftText.isNotEmpty ? draftText : current.text,
            thinkText: draftThink.isNotEmpty ? draftThink : current.thinkText,
            thinkStatus: thinkStatus,
            streaming: draft.streaming,
          );
        } else {
          out.add(
            NativeNovaMessage(
              id: draft.text.isNotEmpty
                  ? effectiveAfter + 1
                  : DateTime.now().millisecondsSinceEpoch + 1,
              role: 'assistant',
              text: draftText,
              thinkText: draftThink,
              createdAt: DateTime.now(),
              streaming: draft.streaming,
              thinkStatus: thinkStatus,
              kind: 'AI_ASSISTANT',
            ),
          );
        }
      }
      return _finalizeMergedMessages(out, repair: true);
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

    final pendingId = draft != null && draft.text.isNotEmpty
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

  Future<void> _persistSessionNow() async {
    if (_conversationId <= 0) return;
    final rows = _messages.where((m) => !m.isWelcome).toList(growable: false);
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
    int? userMsgId,
    bool skipUserBubble = false,
    bool skipAssistantPersist = false,
    String replyText = '',
  }) async {
    await _clearGeneratingMarkers();
    var thinkText = '';
    if (mounted) {
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
            thinkStatus: doneThink ? '已完成思考' : cur.thinkStatus,
          );
          _messages = repairNovaConversationMessages(
            sortNovaMessages(dedupeNovaHistoryMessages(copy)),
          );
        }
      });
      _releaseGeneratingUi(clearStreamingFlags: false);
    }

    final reply = replyText.trim();
    if (_conversationId > 0 &&
        reply.isNotEmpty &&
        !skipUserBubble &&
        !skipAssistantPersist) {
      final rows = _messages.where((m) => !m.isWelcome).toList(growable: false);
      NativeNovaMessage? preferredUser;
      if (userMsgId != null && userMsgId > 0) {
        for (final m in rows) {
          if (m.id == userMsgId) {
            preferredUser = m;
            break;
          }
        }
      }
      final effectiveUser = await _resolveHistoryUser(
        rows,
        preferred: preferredUser,
      );
      if (effectiveUser != null) {
        final existingMessages = mounted
            ? rows
            : (await _service.fetchFullHistory(_conversationId)).messages;
        await _service.persistAssistantTurn(
          conversationId: _conversationId,
          messageId: userMsgId ?? _genAfterMessageId,
          userMessage: effectiveUser.text,
          assistantMessage: reply,
          thinkText: thinkText,
          userPayload: effectiveUser.payload,
          existingMessages: existingMessages,
        );
      }
    }

    List<NativeNovaMessage> rows;
    if (mounted) {
      rows = _messages.where((m) => !m.isWelcome).toList(growable: false);
    } else {
      try {
        rows = (await _service.fetchFullHistory(_conversationId)).messages;
        if (reply.isNotEmpty &&
            !rows.any((m) => m.role == 'assistant' && m.text.trim() == reply)) {
          await _service.commitAssistantReplyToSession(
            _conversationId,
            replyText: reply,
            thinkText: thinkText,
          );
          rows = (await _service.fetchFullHistory(_conversationId)).messages;
        }
      } catch (_) {
        rows = const <NativeNovaMessage>[];
      }
    }
    if (_conversationId > 0 && rows.isNotEmpty) {
      unawaited(_service.persistSession(_conversationId, rows));
      unawaited(_service.flushConvToLocalHistory(_conversationId, rows));
    }
    if (_conversationId > 0) {
      if (mounted) {
        NovaBackgroundCoordinator.instance.stopPoll();
        NovaBackgroundCoordinator.instance.markReplySeen(_conversationId);
      } else {
        unawaited(
          NovaBackgroundCoordinator.instance.onGenerationComplete(
            session: widget.session,
            conversationId: _conversationId,
            messages: rows,
          ),
        );
      }
      NovaBackgroundCoordinator.instance.notifyInboxRefresh();
      if (!mounted) {
        NovaBackgroundCoordinator.instance.markPendingCommBadgeBump(
          conversationId: _conversationId,
        );
      }
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

  Future<void> _flushOnLeave() async {
    if (_conversationId <= 0) return;
    final stopped = _service.userStoppedStream || _isStoppedStatus(_busyHint);
    final streamAlive = _service.isStreamInFlight;
    final hadPendingAssistant =
        !stopped &&
        (_sending || _serverGenerating || _hasActiveAssistantStream());
    if (!stopped && hadPendingAssistant) {
      final storage = await NovaWebStorage.load(widget.session.userId);
      final prdJob = readNovaPrdPendingJob(storage, _conversationId);
      if (prdJob != null && !_prdNovaSendStarted) {
        // PRD 文档离线生成阶段：只落盘会话与任务，不触发 NOVA 后台轮询。
        await persistNovaPrdPendingJob(
          userId: widget.session.userId,
          conversationId: _conversationId,
          job: prdJob,
        );
        await _persistSessionNow();
        await _service.flushConvToLocalHistory(
          _conversationId,
          _messages.where((m) => !m.isWelcome).toList(growable: false),
        );
      } else {
        final status = _busyHint.isNotEmpty ? _busyHint : kNovaInputBusyHint;
        if (_genAfterMessageId <= 0) {
          final user = _messages.cast<NativeNovaMessage?>().lastWhere(
            (m) => m?.role == 'user',
            orElse: () => null,
          );
          if (user != null && user.id > 0) _genAfterMessageId = user.id;
        }
        await _markGenerating(
          status: status,
          afterMessageId: _genAfterMessageId,
        );
        final assistant = _messages.cast<NativeNovaMessage?>().lastWhere(
          (m) => m?.role == 'assistant' && (m?.streaming ?? false),
          orElse: () => null,
        );
        if (assistant != null) {
          await persistNovaStreamDraftState(
            userId: widget.session.userId,
            conversationId: _conversationId,
            status: status,
            afterMessageId: _genAfterMessageId,
            userText: _lastUserDisplayText,
            thinkText: assistant.thinkText,
            text: assistant.text,
            streaming: assistant.streaming,
          );
        } else if (_lastUserDisplayText.trim().isNotEmpty) {
          await persistNovaStreamDraftState(
            userId: widget.session.userId,
            conversationId: _conversationId,
            status: status,
            afterMessageId: _genAfterMessageId,
            userText: _lastUserDisplayText,
            streaming: true,
          );
        }
        NovaBackgroundCoordinator.instance.ensurePoll(
          widget.session,
          conversationId: _conversationId,
        );
      }
    } else if (stopped) {
      await _clearGeneratingMarkers();
      await clearNovaStreamDraftState(
        userId: widget.session.userId,
        conversationId: _conversationId,
      );
    } else {
      final storage = await NovaWebStorage.load(widget.session.userId);
      final local = readNovaGeneratingFromStorage(
        storage,
        convId: _conversationId,
        activeConvId: _conversationId,
      );
      final draft = readNovaStreamDraftFromStorage(storage, _conversationId);
      if (local != null &&
          shouldPersistNovaGenerating(
            localGen: local,
            draft: draft,
            streamInFlight: streamAlive,
          )) {
        NovaBackgroundCoordinator.instance.ensurePoll(
          widget.session,
          conversationId: _conversationId,
        );
      } else if (draft != null && novaStreamDraftHasContent(draft)) {
        NovaBackgroundCoordinator.instance.ensurePoll(
          widget.session,
          conversationId: _conversationId,
        );
      } else {
        await _clearGeneratingMarkers();
      }

      if (hadPendingAssistant && !streamAlive) {
        try {
          final history = await _service.fetchFullHistory(_conversationId);
          final rows = history.messages
              .where((m) => !m.isWelcome)
              .toList(growable: false);
          if (rows.isNotEmpty) {
            await _service.persistSession(_conversationId, rows);
            await _service.flushConvToLocalHistory(_conversationId, rows);
            await _registerLastTurnFromRows(
              rows,
              userMsgId: _genAfterMessageId > 0 ? _genAfterMessageId : null,
            );
            if (!_hasAiReplyAfter(_messages, _genAfterMessageId)) {
              NovaBackgroundCoordinator.instance.markPendingCommBadgeBump(
                conversationId: _conversationId,
              );
            }
            NovaBackgroundCoordinator.instance.notifyInboxRefresh();
          }
        } catch (_) {}
      }
    }
    await _persistSessionNow();
    await _service.persistActiveConversationId(_conversationId);
    final rows = _messages
        .where(
          (m) =>
              !m.isWelcome &&
              !(m.role == 'assistant' && m.streaming && m.text.trim().isEmpty),
        )
        .toList(growable: false);
    if (rows.isNotEmpty) {
      await _service.flushConvToLocalHistory(_conversationId, rows);
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
    int? userMsgId,
    String fallbackUserText = '',
    String fallbackAssistantText = '',
    String fallbackThinkText = '',
  }) async {
    if (rows.isEmpty && fallbackAssistantText.trim().isEmpty) return;

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

    final effectiveUser = await _resolveHistoryUser(rows, preferred: user);
    if (effectiveUser == null) return;

    var assistantText = (assistant?.text ?? '').trim();
    if (assistantText.isEmpty || assistantText == effectiveUser.text.trim()) {
      assistantText = fallbackAssistantText.trim();
    }
    if (assistantText.isEmpty) return;

    await _service.persistAssistantTurn(
      conversationId: _conversationId,
      messageId:
          userMsgId ??
          (effectiveUser.id > 0
              ? effectiveUser.id
              : (_genAfterMessageId > 0
                    ? _genAfterMessageId
                    : DateTime.now().millisecondsSinceEpoch)),
      userMessage: effectiveUser.text,
      assistantMessage: assistantText,
      thinkText: assistant?.thinkText ?? fallbackThinkText,
      userPayload: effectiveUser.payload,
      existingMessages: rows,
    );
  }

  Future<NativeNovaMessage?> _resolveHistoryUser(
    List<NativeNovaMessage> rows, {
    NativeNovaMessage? preferred,
  }) async {
    if (preferred != null && preferred.text.trim().isNotEmpty) return preferred;
    for (var i = rows.length - 1; i >= 0; i--) {
      final m = rows[i];
      if (m.role != 'assistant' && m.text.trim().isNotEmpty) return m;
    }
    if (_conversationId > 0) {
      final storage = await NovaWebStorage.load(widget.session.userId);
      final draft = readNovaStreamDraftFromStorage(storage, _conversationId);
      final text = (draft?.userText ?? _lastUserDisplayText).trim();
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
    if (!mounted || _conversationId <= 0) return;
    final storage = await NovaWebStorage.load(widget.session.userId);
    final draft = readNovaStreamDraftFromStorage(storage, _conversationId);
    if (draft == null || !novaStreamDraftHasContent(draft)) {
      if (!_service.isStreamInFlight && !_serverGenerating) {
        _stopStreamDraftWatcher();
      }
      return;
    }
    final after = draft.afterMessageId > 0
        ? draft.afterMessageId
        : _genAfterMessageId;
    if (!_service.isStreamInFlight &&
        !_serverGenerating &&
        after > 0 &&
        _hasAiReplyAfter(_messages, after)) {
      _stopStreamDraftWatcher();
      return;
    }
    setState(() {
      _busyHint = draft.status.isNotEmpty ? draft.status : kNovaInputBusyHint;
      _messages = _mergeGeneratingAndDraft(
        rows: _withWelcome(
          _messages
              .where((m) => !(m.role == 'assistant' && m.streaming))
              .toList(),
        ),
        generating: true,
        status: draft.status,
        afterMessageId: after,
        draft: draft,
      );
    });
  }

  Future<List<NativeNovaMessage>> _recoverMessagesIfNeeded(
    List<NativeNovaMessage> msgs, {
    NovaStreamDraft? draft,
  }) async {
    final after = _genAfterMessageId;
    if (after <= 0 || _hasAiReplyAfter(msgs, after)) return msgs;

    final draftText = (draft?.text ?? '').trim();
    if (draftText.isNotEmpty) {
      final hasSameAssistant = msgs.any(
        (m) =>
            m.role == 'assistant' && !m.streaming && m.text.trim() == draftText,
      );
      if (hasSameAssistant) return msgs;
      return [
        ...msgs,
        NativeNovaMessage(
          id: after + 1,
          role: 'assistant',
          text: draftText,
          thinkText: draft?.thinkText ?? '',
          thinkStatus: (draft?.thinkText ?? '').trim().isNotEmpty
              ? '已完成思考'
              : '',
          createdAt: DateTime.now(),
          kind: 'AI_ASSISTANT',
        ),
      ];
    }

    try {
      final fromApi = await _service.fetchHistory(_conversationId, size: 40);
      if (_hasAiReplyAfter(fromApi, after)) return fromApi;
    } catch (_) {}
    return msgs;
  }

  Future<void> _pollGenerating() async {
    if (_conversationId <= 0 || !_serverGenerating) return;
    try {
      final history = await _service.fetchFullHistory(_conversationId);
      if (!mounted) return;
      final storage = await NovaWebStorage.load(widget.session.userId);
      final draft = readNovaStreamDraftFromStorage(storage, _conversationId);
      final localGen = readNovaGeneratingFromStorage(
        storage,
        convId: _conversationId,
        activeConvId: _conversationId,
      );
      final resolved = _resolveGeneratingState(
        msgs: history.messages,
        serverGenerating: history.assistantGenerating,
        generatingStatus: history.generatingStatus,
        generatingAfter: history.generatingAfterMessageId,
        localGen: localGen,
        draft: draft,
      );

      if (resolved.generating) {
        if (!_service.isStreamInFlight) {
          if (draft != null && novaStreamDraftHasContent(draft)) {
            await NovaBackgroundCoordinator.instance.onGenerationComplete(
              session: widget.session,
              conversationId: _conversationId,
              messages: history.messages
                  .where((m) => !m.isWelcome)
                  .toList(growable: false),
            );
            if (!mounted) return;
            final refreshed = await _service.fetchFullHistory(_conversationId);
            setState(() {
              _messages = _withWelcome(refreshed.messages);
            });
            _releaseGeneratingUi(clearStreamingFlags: false);
            _scrollBottom();
            return;
          }
          NovaBackgroundCoordinator.instance.ensurePoll(
            widget.session,
            conversationId: _conversationId,
          );
        }
        setState(() {
          _busyHint = resolved.status.isNotEmpty
              ? resolved.status
              : kNovaInputBusyHint;
          _genAfterMessageId = resolved.afterMessageId > 0
              ? resolved.afterMessageId
              : _genAfterMessageId;
          _messages = _mergeGeneratingAndDraft(
            rows: _withWelcome(history.messages),
            generating: true,
            status: resolved.status,
            afterMessageId: _genAfterMessageId,
            draft: draft,
          );
        });
        return;
      }

      _stopGeneratingPoll();
      await _clearGeneratingMarkers();
      var msgs = await _recoverMessagesIfNeeded(
        _withWelcome(history.messages),
        draft: draft,
      );
      if (_conversationId > 0) {
        final rows = msgs.where((m) => !m.isWelcome).toList(growable: false);
        unawaited(_service.flushConvToLocalHistory(_conversationId, rows));
        NovaBackgroundCoordinator.instance.notifyInboxRefresh();
      }
      if (mounted) _releaseGeneratingUi(clearStreamingFlags: false);
      if (!mounted) return;
      setState(() => _messages = msgs);
      if (_conversationId > 0 &&
          msgs.any((m) => m.role == 'assistant' && m.text.trim().isNotEmpty)) {
        unawaited(
          _service.persistSession(
            _conversationId,
            msgs.where((m) => !m.isWelcome).toList(growable: false),
          ),
        );
      }
      _scrollBottom();
    } catch (_) {}
  }

  Future<void> _focusMessage(int messageId) async {
    setState(() => _highlightMessageId = messageId);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx != null) {
      await Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
    Future<void>.delayed(const Duration(milliseconds: 2600), () {
      if (mounted && _highlightMessageId == messageId) {
        setState(() => _highlightMessageId = null);
      }
    });
  }

  Future<void> _ensureConversationId() async {
    if (_conversationId > 0) return;
    _conversationId = await _service.ensureConversation();
  }

  Future<bool> _tryRecoverAssistantAfterSendFailure({
    required int userMsgId,
    required int assistantMsgId,
  }) async {
    if (_conversationId <= 0) return false;
    try {
      final history = await _service.fetchFullHistory(_conversationId);
      if (!_hasAiReplyAfter(history.messages, userMsgId)) return false;
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
        userMsgId: userMsgId,
        replyText: assistant.text,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _failAssistantTurnInChat({
    required int assistantMsgId,
    required String message,
  }) async {
    final err = message.trim().isNotEmpty ? message.trim() : 'NOVA 请求失败，请稍后重试';
    if (mounted) {
      setState(() {
        _busyHint = '';
        final idx = _messages.indexWhere((m) => m.id == assistantMsgId);
        if (idx >= 0) {
          final copy = [..._messages];
          copy[idx] = copy[idx].copyWith(
            streaming: false,
            text: err,
            thinkStatus: '',
          );
          _messages = copy;
        }
        _banner = err;
      });
    }
    await _clearGeneratingMarkers();
    if (_conversationId > 0) {
      await clearNovaStreamDraftState(
        userId: widget.session.userId,
        conversationId: _conversationId,
      );
      unawaited(_persistSessionNow());
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
    if (!_novaReady || _sending) return;
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
    if (!_novaReady || _sending) return;
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
    if (!_novaReady || _sending) return;
    final file = await openFile();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final fileName = file.name;
    final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
    _addDraft(
      NovaDraftAttachment(
        id: 'draft-${++_draftSeq}',
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
        isImage: mimeType.startsWith('image/'),
      ),
    );
  }

  Future<void> _submitInput() async {
    if (_sending) {
      _stopGeneration();
      return;
    }
    final text = _inputController.text.trim();
    if (text.isEmpty && _drafts.isEmpty) return;
    if (!_novaReady) return;

    final drafts = [..._drafts];
    _inputController.clear();
    setState(() => _drafts = const <NovaDraftAttachment>[]);
    await _sendMessage(text: text, drafts: drafts);
  }

  void _onInputFocusChanged() {
    if (!_inputFocusNode.hasFocus) return;
    _scrollToLatestAfterKeyboard();
  }

  void _scrollToLatestAfterKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollBottom();
      Future<void>.delayed(const Duration(milliseconds: 280), () {
        if (mounted) _scrollBottom();
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

  Future<void> _sendMessage({
    required String text,
    String? novaPrompt,
    List<NovaDraftAttachment> drafts = const <NovaDraftAttachment>[],
    bool skipUserBubble = false,
    bool userAlreadyPersisted = false,
    String? assistantThinkStatus,
    int? existingUserMsgId,
    int? existingAssistantMsgId,
  }) async {
    final reusingTurn =
        existingUserMsgId != null && existingAssistantMsgId != null;
    if (_sending && !reusingTurn) return;
    if (_sending && reusingTurn) {
      setState(() => _sending = false);
    }

    if (reusingTurn) {
      _prdNovaSendStarted = true;
    }

    final promptSource = novaPrompt ?? text;
    final prompt = novaDraftPrompt(promptSource, drafts);
    final displayText = text.isNotEmpty
        ? text
        : (novaAttachmentSummary(drafts).isNotEmpty
              ? novaAttachmentSummary(drafts)
              : prompt);
    _lastUserDisplayText = displayText;

    final userMsgId =
        existingUserMsgId ?? DateTime.now().millisecondsSinceEpoch;
    final assistantMsgId = existingAssistantMsgId ?? userMsgId + 1;
    final draftAttachments = _attachmentsFromDrafts(drafts);

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

    try {
      await _ensureConversationId();
      if (_conversationId <= 0) {
        throw Exception('无法创建NOVA会话，请稍后重试');
      }
      final genStatus =
          assistantThinkStatus ?? (drafts.isNotEmpty ? '正在分析…' : '正在生成…');
      if (!skipUserBubble || reusingTurn) {
        _genAfterMessageId = userMsgId;
        NovaBackgroundCoordinator.instance.clearFinalizedConversation(
          _conversationId,
        );
        await _markGenerating(status: genStatus, afterMessageId: userMsgId);
        await _persistSessionNow();
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

      var userPersistedToServer = skipUserBubble || userAlreadyPersisted;
      if (!skipUserBubble && !reusingTurn && drafts.isEmpty) {
        final earlyContent = text.isNotEmpty ? text : prompt;
        final savedConvId = await _service.persistUserMessage(
          conversationId: _conversationId,
          messageId: userMsgId,
          content: earlyContent,
        );
        if (savedConvId > 0 && savedConvId != _conversationId && mounted) {
          setState(() => _conversationId = savedConvId);
        }
        userPersistedToServer = true;
        if (kDebugMode) {
          debugPrint(
            '[NativeNovaPage] user persisted before stream conv=$_conversationId id=$userMsgId',
          );
        }
      }

      for (final d in drafts) {
        if (d.payload != null) continue;
        setState(() {
          d.uploading = true;
          d.uploadProgress = 1;
        });
        // 图片上传前压缩（最长边 1568px / JPEG 82%），减小体积与流量；文件保持原样。
        var uploadBytes = d.bytes;
        var uploadName = d.fileName;
        var uploadMime = d.mimeType;
        if (d.isImage) {
          try {
            final normalized = await normalizeImageForVision(
              d.bytes,
              fileName: d.fileName,
            );
            if (normalized.bytes.isNotEmpty &&
                normalized.bytes.length < d.bytes.length) {
              uploadBytes = normalized.bytes;
              uploadName = normalized.fileName;
              uploadMime = normalized.mimeType;
            }
          } catch (_) {}
        }
        final uploaded = await _service.uploadAttachment(
          conversationId: _conversationId,
          bytes: uploadBytes,
          fileName: uploadName,
          onProgress: (p) {
            if (mounted) setState(() => d.uploadProgress = p);
          },
        );
        d.payload = _service.buildUploadedAttachmentPayload(
          url: uploaded.url,
          objectKey: uploaded.objectKey,
          fileName: uploadName,
          mimeType: uploadMime,
          kind: d.kind,
        );
        d.uploading = false;
      }

      final attachments = drafts
          .where((d) => d.payload != null)
          .map((d) => NovaMessageAttachment.fromJson(d.payload!))
          .toList();

      if ((!skipUserBubble || reusingTurn) && attachments.isNotEmpty) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == userMsgId);
          if (idx >= 0) {
            final copy = [..._messages];
            final payload = <String, dynamic>{
              'attachments': attachments.map((a) => a.toJson()).toList(),
            };
            copy[idx] = copy[idx].copyWith(
              attachments: attachments
                  .asMap()
                  .entries
                  .map(
                    (e) => e.value.copyWith(
                      previewBytes: e.key < drafts.length
                          ? drafts[e.key].bytes
                          : null,
                    ),
                  )
                  .toList(growable: false),
              kind: 'TEXT',
              payload: payload,
            );
            _messages = copy;
          }
        });
        unawaited(_persistSessionNow());
      }

      final userMetadata = attachments.isEmpty
          ? null
          : <String, dynamic>{
              'attachments': attachments.map((a) => a.toJson()).toList(),
            };

      if ((!skipUserBubble || reusingTurn) &&
          attachments.isNotEmpty &&
          !userAlreadyPersisted) {
        final savedConvId = await _service.persistUserMessage(
          conversationId: _conversationId,
          messageId: userMsgId,
          content: displayText,
          metadata: userMetadata,
        );
        if (savedConvId > 0 && savedConvId != _conversationId && mounted) {
          setState(() => _conversationId = savedConvId);
        }
        userPersistedToServer = true;
      }

      final userContent = drafts.isEmpty
          ? (promptSource.trim().isNotEmpty
                ? promptSource.trim()
                : (text.isNotEmpty ? text : prompt))
          : await _service.buildMultimodalContent(
              text: prompt,
              attachments: drafts,
              model: _selectedModel,
            );

      var reply = await _service.sendAndReplyStream(
        conversationId: _conversationId,
        userContent: userContent,
        displayText: displayText,
        userMetadata: userMetadata,
        userMessageId: userMsgId,
        skipUserPersist: userPersistedToServer,
        onConversationId: (id) {
          if (!mounted || id <= 0 || id == _conversationId) return;
          setState(() => _conversationId = id);
        },
        onUpdate: (update) {
          if (_service.userStoppedStream) return;
          final convId = _conversationId;
          if (convId > 0) {
            unawaited(
              persistNovaStreamDraftState(
                userId: widget.session.userId,
                conversationId: convId,
                status: update.thinkStatus.isNotEmpty
                    ? update.thinkStatus
                    : kNovaInputBusyHint,
                afterMessageId: _genAfterMessageId,
                userText: displayText,
                thinkText: update.thinkText,
                text: update.replyText,
                streaming: true,
              ),
            );
          }
          if (!mounted) return;
          setState(() {
            _busyHint = update.thinkStatus.isNotEmpty
                ? update.thinkStatus
                : kNovaInputBusyHint;
            final idx = _messages.indexWhere((m) => m.id == assistantMsgId);
            final assistant = NativeNovaMessage(
              id: assistantMsgId,
              role: 'assistant',
              text: update.replyText,
              createdAt: DateTime.now(),
              thinkText: update.thinkText,
              thinkStatus: update.thinkStatus,
              streaming: true,
              ragUsed: update.ragUsed,
            );
            if (idx >= 0) {
              final copy = [..._messages];
              copy[idx] = assistant;
              _messages = copy;
            } else if (!skipUserBubble) {
              _messages = [..._messages, assistant];
            }
          });
          _scrollBottom();
        },
      );

      await _completeAssistantStream(
        assistantMsgId: assistantMsgId,
        userMsgId: skipUserBubble ? null : userMsgId,
        skipUserBubble: skipUserBubble,
        replyText: reply,
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
        final idx = _messages.indexWhere((m) => m.id == assistantMsgId);
        final streamed = idx >= 0 ? _messages[idx].text.trim() : '';
        final streamedThink = idx >= 0 ? _messages[idx].thinkText.trim() : '';
        final partial = streamed.isNotEmpty ? streamed : streamedThink;
        if (partial.isNotEmpty && partial != displayText.trim()) {
          await _completeAssistantStream(
            assistantMsgId: assistantMsgId,
            userMsgId: skipUserBubble ? null : userMsgId,
            skipUserBubble: skipUserBubble,
            replyText: partial,
          );
          if (_conversationId > 0) {
            unawaited(
              clearNovaPrdPendingJob(
                userId: widget.session.userId,
                conversationId: _conversationId,
              ),
            );
          }
        } else {
          await _failAssistantTurnInChat(
            assistantMsgId: assistantMsgId,
            message: NativeNovaService.friendlyError(e),
          );
        }
      } else if (convId > 0) {
        await _clearGeneratingMarkers();
        await clearNovaStreamDraftState(
          userId: widget.session.userId,
          conversationId: convId,
        );
        await _service.stripStreamingFromSession(convId);
      }
    } finally {
      if (_conversationId > 0 && _messages.isNotEmpty) {
        unawaited(_service.persistSession(_conversationId, _messages));
      }
      if (mounted && !_hasActiveAssistantStream()) {
        setState(() {
          _sending = false;
          _serverGenerating = false;
          _busyHint = '';
        });
      }
    }
  }

  void _handleBack() {
    Future<void>(() async {
      if (_conversationId > 0 &&
          _messages.any(
            (message) =>
                message.role == 'assistant' &&
                !message.streaming &&
                message.text.trim().isNotEmpty,
          )) {
        NovaBackgroundCoordinator.instance.markReplySeen(_conversationId);
      }
      await _flushOnLeave();
      if (mounted) widget.onBack();
    });
  }

  void _stopGeneration() {
    _service.cancelActiveStream();
    _stopGeneratingPoll();
    _stopStreamDraftWatcher();
    unawaited(_clearGeneratingMarkers());
    if (_conversationId > 0) {
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
  }

  Future<void> _startNewChat() async {
    if (_isGenerating) return;
    _stopGeneratingPoll();
    final prevConvId = _conversationId;
    final uid = widget.session.userId;
    if (_sending || _serverGenerating || _busyHint.isNotEmpty) {
      await _clearGeneratingMarkers();
    }
    if (prevConvId > 0) {
      await _service.flushConvToLocalHistory(prevConvId, _messages);
    }
    await _service.resetNovaNewChatPlaceholder(
      userId: uid,
      previousConversationId: prevConvId,
    );
    widget.onClearHistoryFocus?.call();
    setState(() {
      _loading = false;
      _banner = null;
      _busyHint = '';
      _serverGenerating = false;
      _sending = false;
      _drafts = const <NovaDraftAttachment>[];
      _conversationId = 0;
      _genAfterMessageId = 0;
      _messages = [_welcomeMessage()];
    });
    _scrollBottom();

    final convId = await _service.createNovaServerConversation(forceNew: true);
    if (!mounted) return;
    if (convId > 0) {
      await _service.applyNovaNewChatStorage(
        userId: uid,
        conversationId: convId,
        previousConversationId: prevConvId,
      );
      setState(() => _conversationId = convId);
    } else if (prevConvId > 0 &&
        await _service.validateNovaConversationId(prevConvId)) {
      final recovered = await _service.applyNewChatLocalFallback(
        userId: uid,
        previousConversationId: prevConvId,
      );
      if (recovered > 0) setState(() => _conversationId = recovered);
      await NovaWebStorage.removeKeys(uid, ['dunes_nova_view_since']);
    } else if (uid > 0) {
      await NovaWebStorage.removeKeys(uid, ['dunes_nova_view_since']);
    }
    _toast('已开启新对话，上一段可在右上角「历史」查看');
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
    header.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
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
        _recordWillCancel = false;
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
    if (_recordWillCancel) {
      await _cancelHoldRecord(showHint: true);
      return;
    }
    _recordTicker?.cancel();
    setState(() {
      _recording = false;
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
      _recordWillCancel = false;
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
    final overlayTop =
        MediaQuery.sizeOf(context).height - kVoiceRecordingOverlayHeight;
    final shouldCancel = details.globalPosition.dy < overlayTop;
    setState(() {
      _recordWillCancel = shouldCancel;
      _recordFocalPoint = details.globalPosition;
    });
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
    // 历史里的图片/富文本异步撑高后高度才稳定，单次跳转会停在中间；
    // 入场后再做几次兜底贴底，确保展示到最底部（用户已主动上滑则不打扰）。
    for (final ms in const [60, 120, 240, 480, 800, 1200]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (!mounted || !_scrollController.hasClients) return;
        final max = _scrollController.position.maxScrollExtent;
        if ((_scrollController.offset - max).abs() > 2) {
          _scrollController.jumpTo(max);
        }
      });
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

    _prdResumeInFlight = true;
    try {
      _applySelectedChatModel(job.prdModel);
      await _continuePrdGeneration(job);
    } finally {
      _prdResumeInFlight = false;
    }
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
      await _ensureKbAndSendPrdToNova(job: job);
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
      await _service.persistUserMessage(
        conversationId: _conversationId,
        messageId: job.userMsgId,
        content: displayText,
      );
      userPersisted = true;
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

  Future<void> _openMeetingPrdFlow() async {
    if (!_novaReady || _isGenerating || _sending) return;
    int? prdAssistantMsgId;
    try {
      final meetingService = NativeMeetingService(session: widget.session);
      setState(() => _busyHint = '正在加载可生成 PRD 的会议纪要…');
      final meetings = await meetingService.fetchList(page: 0, size: 50);
      await _kbService.ensureNovaReady();
      final exportable = meetings
          .where(MeetingMinutesExport.isListItemLikelyExportable)
          .toList(growable: false);
      final kbIndexedMeetings = await _kbService.filterMeetingsWithIndexedKb(
        exportable,
      );
      if (!mounted) return;
      setState(() => _busyHint = '');

      final picked = await showMeetingMinutesPickerDialog(
        context,
        meetings: kbIndexedMeetings,
      );
      if (picked == null || !mounted) return;

      final detail = await meetingService.fetchDetail(picked.meetingId);
      if (!mounted) return;
      if (!MeetingMinutesExport.canExport(detail)) {
        _toast('该会议纪要尚未生成完成', error: true);
        return;
      }

      final kbDoc = await _kbService.findIndexedMeetingMinutesDocument(
        meetingId: detail.meetingId,
        kbFileName: MeetingMinutesExport.kbUploadFileName(detail),
        kbTitle: MeetingMinutesExport.kbUploadTitle(detail),
      );
      if (kbDoc == null) {
        _toast('该会议纪要尚未在知识库中完成索引，请稍后再试', error: true);
        return;
      }

      final prdModel = await _pickPrdGenerationModel();
      if (!mounted || prdModel == null || prdModel.trim().isEmpty) return;

      final meetingTitle = detail.title.trim().isNotEmpty
          ? detail.title.trim()
          : '未命名会议';
      final confirmed = await showMeetingPrdConfirmDialog(
        context,
        meetingTitle: meetingTitle,
        modelName: novaModelDisplayName(prdModel),
      );
      if (!confirmed || !mounted) return;

      _applySelectedChatModel(prdModel);

      if (detail.summary.trim().isEmpty) {
        _toast('该会议纪要尚无摘要，无法生成 PRD', error: true);
        return;
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
      prdAssistantMsgId = assistantMsgId;
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
      if (!mounted) return;

      _prdResumeInFlight = true;
      try {
        await _ensureKbAndSendPrdToNova(job: pendingJob, detail: detail);
      } finally {
        _prdResumeInFlight = false;
      }
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

  @override
  Widget build(BuildContext context) {
    final inputEnabled = _novaReady;
    final inputHint = !_novaReady ? 'NOVA尚未就绪' : kNovaInputPlaceholder;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
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
                NovaPageHeader(
                  onBack: _handleBack,
                  onNewChat: _novaReady ? _startNewChat : null,
                  onHistory: widget.onHistory,
                  onOpenKb: widget.onOpenKb,
                  actionsEnabled: !_isGenerating,
                ),
                if (_loading)
                  const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Expanded(
                    child: NovaC4MessageStream(
                      child: ListView(
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                        children: [
                          if (_banner != null)
                            NovaStatusBanner(message: _banner!, onRetry: _load),
                          if (_isEmptyConversation)
                            const SizedBox(
                              height: 360,
                              child: NovaC4EmptyState(),
                            )
                          else
                            ..._buildMessageList(),
                        ],
                      ),
                    ),
                  ),
                NovaC4BusyHint(text: _busyHint),
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
                      sending: _sending,
                      enabled: inputEnabled,
                      hintText: inputHint,
                      onToggleVoice: voiceBlocked
                          ? () {
                              if (meetingLive) {
                                _toast('会议录音进行中，暂无法发送语音');
                              }
                            }
                          : () => setState(() => _voiceMode = !_voiceMode),
                      onSend: _submitInput,
                      onPickModel: _pickModel,
                      modelLabel: novaModelDisplayName(_selectedModel),
                      quickActionsOpen: _quickActionsOpen,
                      onToggleQuickActions: () {
                        setState(() => _quickActionsOpen = !_quickActionsOpen);
                      },
                      onStop: _stopGeneration,
                      onCamera: _pickCamera,
                      onAlbum: _pickAlbum,
                      onOpenMeeting: widget.onOpenMeeting,
                      onMeetingPrd: _openMeetingPrdFlow,
                      onAttach:
                          inputEnabled && NovaConfig.fileUploadInChatEnabled
                          ? _pickFile
                          : null,
                      recording: _recording,
                      recordWillCancel: _recordWillCancel,
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
                ),
                if (_recording)
                  VoiceRecordingOverlay(
                    durationMs: _recordDurationMs,
                    willCancel: _recordWillCancel,
                    focalPoint: _recordFocalPoint,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMessageList() {
    final widgets = <Widget>[];
    DateTime? prevAt;
    for (final m in _messages) {
      if (!m.isWelcome) {
        final label = historyDayDividerLabel(m.createdAt, prevAt);
        if (label != null) {
          widgets.add(NovaMsgDateDivider(label: label));
        }
        prevAt = m.createdAt;
      }
      widgets.add(_buildMessageRow(m));
    }
    return widgets;
  }

  bool get _isEmptyConversation =>
      _messages.isEmpty || _messages.every((message) => message.isWelcome);

  Widget _buildMessageRow(NativeNovaMessage m) {
    final mine = m.role == 'user';
    final time = m.isWelcome ? '' : novaMsgTimeLabel(m.createdAt);
    final thinking =
        !mine &&
        m.text.isEmpty &&
        m.streaming &&
        (_sending ||
            _serverGenerating ||
            m.thinkStatus.isNotEmpty ||
            m.thinkText.isNotEmpty);
    final key = m.id > 0 ? _messageKeys.putIfAbsent(m.id, GlobalKey.new) : null;
    return KeyedSubtree(
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
      ),
    );
  }
}
