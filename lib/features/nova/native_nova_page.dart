import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../chat/native_audio_recorder.dart';
import '../chat/chat_widgets.dart';
import '../shell/dunes_toast.dart';
import 'native_nova_service.dart';
import 'nova_background_coordinator.dart';
import 'nova_draft.dart';
import 'nova_generating_storage.dart';
import 'nova_history_utils.dart';
import 'nova_image_utils.dart';
import 'nova_media.dart';
import 'nova_models_service.dart';
import 'nova_web_storage.dart';
import 'nova_widgets.dart';

class NativeNovaPage extends StatefulWidget {
  const NativeNovaPage({
    super.key,
    required this.session,
    required this.onBack,
    this.onHistory,
    this.onOpenKb,
    this.focusConversationId,
    this.focusMessageId,
    this.onClearHistoryFocus,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final VoidCallback? onHistory;
  final VoidCallback? onOpenKb;
  final int? focusConversationId;
  final int? focusMessageId;
  final VoidCallback? onClearHistoryFocus;

  @override
  State<NativeNovaPage> createState() => _NativeNovaPageState();
}

class _NativeNovaPageState extends State<NativeNovaPage> {
  late final NativeNovaService _service;
  late final NovaMediaResolver _mediaResolver;
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _messageKeys = <int, GlobalKey>{};

  bool _loading = true;
  bool _sending = false;
  bool _serverGenerating = false;
  bool _novaReady = true;
  bool _voiceMode = false;
  bool _recording = false;
  bool _recordWillCancel = false;
  int _recordDurationMs = 0;
  int? _highlightMessageId;
  Timer? _recordTicker;
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
  String _userAvatarPreset = '';
  String _userAvatarUrl = '';

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
    _service = NovaBackgroundCoordinator.instance.serviceFor(widget.session);
    _mediaResolver = NovaMediaResolver(widget.session, service: _service);
    _load();
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
    unawaited(_flushOnLeave());
    super.deactivate();
  }

  @override
  void dispose() {
    _streamDraftTimer?.cancel();
    _genPollTimer?.cancel();
    _recordTicker?.cancel();
    unawaited(_flushOnLeave());
    unawaited(NativeAudioRecorder.instance.cancel());
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
    try {
      final avatar = await _service.fetchCurrentUserAvatar();
      if (!mounted) return;
      setState(() {
        _userAvatarPreset = avatar.avatarPreset;
        _userAvatarUrl = avatar.avatarUrl;
      });
    } catch (_) {}
  }

  Future<void> _loadModels() async {
    try {
      final payload = await NovaModelsService().fetchModels(
        apiBase: widget.session.apiBase,
        token: widget.session.token,
      );
      if (!mounted) return;
      final stored = widget.session.novaLocalStorage?['dunes_nova_chat_model']?.trim();
      final selected = (stored != null && stored.isNotEmpty && payload.chatModels.contains(stored))
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
    await Future.wait<void>([
      _loadModels(),
      _loadUserAvatar(),
    ]);
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
        await NovaWebStorage.removeKeys(widget.session.userId, ['dunes_nova_view_since']);
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
          unawaited(clearNovaGeneratingState(
            userId: widget.session.userId,
            conversationId: convId,
          ));
          unawaited(clearNovaStreamDraftState(
            userId: widget.session.userId,
            conversationId: convId,
          ));
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
            ? (generatingStatus.isNotEmpty ? generatingStatus : kNovaInputBusyHint)
            : '';
        _banner = banner;
        _loading = false;
      });
      if (serverGenerating) {
        NovaBackgroundCoordinator.instance.stopPoll();
        _startGeneratingPoll();
        unawaited(_pollGenerating());
        if (_service.isStreamInFlight) _startStreamDraftWatcher();
      }
      final focusId = widget.focusMessageId;
      if (focusId != null && focusId > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusMessage(focusId));
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
  ({
    bool generating,
    String status,
    int afterMessageId,
    bool clearLocal,
  }) _resolveGeneratingState({
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
    }

    return (
      generating: generating,
      status: status,
      afterMessageId: after,
      clearLocal: clearLocal,
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
    final effectiveAfter = afterMessageId > 0 ? afterMessageId : (draft?.afterMessageId ?? 0);
    final draftUserText = (draft?.userText ?? '').trim();

    if (draftUserText.isNotEmpty && effectiveAfter > 0) {
      final hasUser = out.any((m) => m.id == effectiveAfter);
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

    if (!generating) return repairNovaConversationMessages(sortNovaMessages(out));

    final draftText = draft?.text ?? '';
    final draftThink = draft?.thinkText ?? '';
    final draftStatus = (draft?.status ?? '').trim();
    final thinkStatus = draftStatus.isNotEmpty
        ? draftStatus
        : (status.isNotEmpty ? status : '正在生成…');

    final streamingIdx = out.indexWhere((m) => m.role == 'assistant' && m.streaming);
    if (streamingIdx >= 0) {
      final current = out[streamingIdx];
      out[streamingIdx] = current.copyWith(
        text: draftText.isNotEmpty ? draftText : current.text,
        thinkText: draftThink.isNotEmpty ? draftThink : current.thinkText,
        thinkStatus: thinkStatus,
        streaming: true,
      );
      return sortNovaMessages(out);
    }

    if (effectiveAfter > 0 && _hasAiReplyAfter(out, effectiveAfter)) {
      return repairNovaConversationMessages(sortNovaMessages(out));
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
    return sortNovaMessages(out);
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

  Future<void> _markGenerating({required String status, required int afterMessageId}) async {
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
          _messages = repairNovaConversationMessages(copy);
        }
      });
      _releaseGeneratingUi(clearStreamingFlags: false);
    }

    final reply = replyText.trim();
    if (_conversationId > 0 && reply.isNotEmpty && !skipUserBubble) {
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
      final effectiveUser = await _resolveHistoryUser(rows, preferred: preferredUser);
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
        NovaBackgroundCoordinator.instance.markPendingCommBadgeBump();
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

  bool _isStoppedStatus(String status) => status.trim().contains('停止');

  Future<void> _flushOnLeave() async {
    if (_conversationId <= 0) return;
    final stopped = _service.userStoppedStream || _isStoppedStatus(_busyHint);
    final streamAlive = _service.isStreamInFlight;
    final hadPendingAssistant =
        !stopped && (_sending || _serverGenerating || _hasActiveAssistantStream());
    final generating = !stopped &&
        streamAlive &&
        (_sending || _serverGenerating || _hasActiveAssistantStream());
    if (generating) {
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
      }
      NovaBackgroundCoordinator.instance.onNovaPageLeave(
        session: widget.session,
        conversationId: _conversationId,
        generating: true,
        afterMessageId: _genAfterMessageId,
      );
    } else {
      if (stopped) {
        await _clearGeneratingMarkers();
        await clearNovaStreamDraftState(
          userId: widget.session.userId,
          conversationId: _conversationId,
        );
      }
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
      } else {
        await _clearGeneratingMarkers();
      }

      // 兜底：离开时若原本在生成、但此刻流已结束，补做一次收口与历史入库。
      if (hadPendingAssistant) {
        try {
          final history = await _service.fetchFullHistory(_conversationId);
          final rows = history.messages.where((m) => !m.isWelcome).toList(growable: false);
          if (rows.isNotEmpty) {
            await _service.persistSession(_conversationId, rows);
            await _service.flushConvToLocalHistory(_conversationId, rows);
            await _registerLastTurnFromRows(
              rows,
              userMsgId: _genAfterMessageId > 0 ? _genAfterMessageId : null,
            );
            NovaBackgroundCoordinator.instance.markPendingCommBadgeBump();
            NovaBackgroundCoordinator.instance.notifyInboxRefresh();
          }
        } catch (_) {}
      }
    }
    await _persistSessionNow();
    await _service.persistActiveConversationId(_conversationId);
    final rows = _messages
        .where((m) => !m.isWelcome && !(m.role == 'assistant' && m.streaming && m.text.trim().isEmpty))
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
      if (assistant == null && m.role == 'assistant' && !m.streaming && m.text.trim().isNotEmpty) {
        assistant = m;
      } else if (user == null && m.role == 'user') {
        user = m;
      }
      if (assistant != null && user != null) break;
    }

    final effectiveUser = await _resolveHistoryUser(
      rows,
      preferred: user,
    );
    if (effectiveUser == null) return;

    var assistantText = (assistant?.text ?? '').trim();
    if (assistantText.isEmpty || assistantText == effectiveUser.text.trim()) {
      assistantText = fallbackAssistantText.trim();
    }
    if (assistantText.isEmpty) return;

    await _service.persistAssistantTurn(
      conversationId: _conversationId,
      messageId: userMsgId ??
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
    _genPollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) => _pollGenerating());
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
    if (!_service.isStreamInFlight) {
      _stopStreamDraftWatcher();
      return;
    }
    final storage = await NovaWebStorage.load(widget.session.userId);
    final draft = readNovaStreamDraftFromStorage(storage, _conversationId);
    if (draft == null || !novaStreamDraftHasContent(draft)) return;
    setState(() {
      _busyHint = draft.status.isNotEmpty ? draft.status : kNovaInputBusyHint;
      _messages = _mergeGeneratingAndDraft(
        rows: _withWelcome(
          _messages.where((m) => !(m.role == 'assistant' && m.streaming)).toList(),
        ),
        generating: true,
        status: draft.status,
        afterMessageId: draft.afterMessageId > 0 ? draft.afterMessageId : _genAfterMessageId,
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
        (m) => m.role == 'assistant' && !m.streaming && m.text.trim() == draftText,
      );
      if (hasSameAssistant) return msgs;
      return [
        ...msgs,
        NativeNovaMessage(
          id: after + 1,
          role: 'assistant',
          text: draftText,
          thinkText: draft?.thinkText ?? '',
          thinkStatus: (draft?.thinkText ?? '').trim().isNotEmpty ? '已完成思考' : '',
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
        setState(() {
          _busyHint = resolved.status.isNotEmpty ? resolved.status : kNovaInputBusyHint;
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
      if (_conversationId > 0 && msgs.any((m) => m.role == 'assistant' && m.text.trim().isNotEmpty)) {
        unawaited(_service.persistSession(
          _conversationId,
          msgs.where((m) => !m.isWelcome).toList(growable: false),
        ));
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

  void _addDraft(NovaDraftAttachment draft) {
    setState(() => _drafts = [..._drafts, draft]);
  }

  void _removeDraft(String id) {
    setState(() => _drafts = _drafts.where((d) => d.id != id).toList());
  }

  Future<void> _pickCamera() async {
    if (!_novaReady || _sending) return;
    if (!kIsWeb) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) {
        _toast('请先允许相机权限');
        return;
      }
    }
    final picked = await _imagePicker.pickImage(source: ImageSource.camera);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final fileName = picked.name.isNotEmpty ? picked.name : 'photo-${DateTime.now().millisecondsSinceEpoch}.jpg';
    _addDraft(NovaDraftAttachment(
      id: 'draft-${++_draftSeq}',
      bytes: bytes,
      fileName: fileName,
      mimeType: lookupMimeType(fileName) ?? 'image/jpeg',
      isImage: true,
    ));
  }

  Future<void> _pickAlbum() async {
    if (!_novaReady || _sending) return;
    final picked = await _imagePicker.pickMultiImage();
    if (picked.isEmpty) return;
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      final fileName = file.name.isNotEmpty ? file.name : 'image-${DateTime.now().millisecondsSinceEpoch}.jpg';
      _addDraft(NovaDraftAttachment(
        id: 'draft-${++_draftSeq}',
        bytes: bytes,
        fileName: fileName,
        mimeType: lookupMimeType(fileName) ?? 'image/jpeg',
        isImage: true,
      ));
    }
  }

  Future<void> _pickFile() async {
    if (!_novaReady || _sending) return;
    final file = await openFile();
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final fileName = file.name;
    final mimeType = lookupMimeType(fileName) ?? 'application/octet-stream';
    _addDraft(NovaDraftAttachment(
      id: 'draft-${++_draftSeq}',
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      isImage: mimeType.startsWith('image/'),
    ));
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
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _drafts = const <NovaDraftAttachment>[]);
    await _sendMessage(text: text, drafts: drafts);
  }

  Future<void> _sendMessage({
    required String text,
    List<NovaDraftAttachment> drafts = const <NovaDraftAttachment>[],
    bool skipUserBubble = false,
  }) async {
    if (_sending) return;

    final prompt = novaDraftPrompt(text, drafts);
    final displayText = text.isNotEmpty
        ? text
        : (novaAttachmentSummary(drafts).isNotEmpty ? novaAttachmentSummary(drafts) : prompt);
    _lastUserDisplayText = displayText;

    final userMsgId = DateTime.now().millisecondsSinceEpoch;
    final assistantMsgId = userMsgId + 1;
    final draftAttachments = drafts
        .map(
          (d) => NovaMessageAttachment(
            url: '',
            objectKey: '',
            fileName: d.fileName,
            mimeType: d.mimeType,
            kind: d.kind,
            previewBytes: d.bytes,
          ),
        )
        .toList(growable: false);

    if (!skipUserBubble) {
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
                    'attachments': draftAttachments.map((a) => a.toJson()).toList(),
                  }
                : null,
          ),
          NativeNovaMessage(
            id: assistantMsgId,
            role: 'assistant',
            text: '',
            createdAt: DateTime.fromMillisecondsSinceEpoch(userMsgId).add(const Duration(milliseconds: 1)),
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
            createdAt: DateTime.fromMillisecondsSinceEpoch(assistantMsgId - 1)
                .add(const Duration(milliseconds: 1)),
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
      final genStatus = drafts.isNotEmpty ? '正在分析…' : '正在生成…';
      if (!skipUserBubble) {
        _genAfterMessageId = userMsgId;
        NovaBackgroundCoordinator.instance.clearFinalizedConversation(_conversationId);
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
          debugPrint('[NativeNovaPage] seeded draft conv=$_conversationId after=$userMsgId');
        }
        if (mounted) {
          setState(() {
            _serverGenerating = true;
            _busyHint = genStatus;
          });
        }
      }

      var userPersistedToServer = skipUserBubble;
      if (!skipUserBubble && drafts.isEmpty) {
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
          debugPrint('[NativeNovaPage] user persisted before stream conv=$_conversationId id=$userMsgId');
        }
      }

      for (final d in drafts) {
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
            final normalized = await normalizeImageForVision(d.bytes, fileName: d.fileName);
            if (normalized.bytes.isNotEmpty && normalized.bytes.length < d.bytes.length) {
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

      if (!skipUserBubble && attachments.isNotEmpty) {
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
                      previewBytes: e.key < drafts.length ? drafts[e.key].bytes : null,
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
          : <String, dynamic>{'attachments': attachments.map((a) => a.toJson()).toList()};

      if (!skipUserBubble && attachments.isNotEmpty) {
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
          ? (text.isNotEmpty ? text : prompt)
          : await _service.buildMultimodalContent(
              text: prompt,
              attachments: drafts,
              model: _selectedModel,
            );

      final reply = await _service.sendAndReplyStream(
        conversationId: _conversationId,
        userContent: userContent,
        displayText: displayText,
        userMetadata: userMetadata,
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
                status: update.thinkStatus.isNotEmpty ? update.thinkStatus : kNovaInputBusyHint,
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
            _busyHint = update.thinkStatus.isNotEmpty ? update.thinkStatus : kNovaInputBusyHint;
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
      if (!mounted) return;
      _scrollBottom();
    } catch (e) {
      final convId = _conversationId;
      if (_service.userStoppedStream) {
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere((m) => m.role == 'assistant' && m.streaming);
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
      } else {
        if (mounted) {
          setState(() => _banner = NativeNovaService.friendlyError(e));
          _releaseGeneratingUi();
        } else if (convId > 0) {
          await _clearGeneratingMarkers();
          await _service.stripStreamingFromSession(convId);
        }
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
      final idx = _messages.indexWhere((m) => m.role == 'assistant' && m.streaming);
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
    if (_sending && _hasActiveAssistantStream()) return;
    _stopGeneratingPoll();
    final prevConvId = _conversationId;
    final uid = widget.session.userId;
    if (_sending || _serverGenerating || _busyHint.isNotEmpty) {
      await _clearGeneratingMarkers();
    }
    if (prevConvId > 0) {
      await _service.flushConvToLocalHistory(prevConvId, _messages);
      await _registerLastTurnIfComplete();
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
    } else if (prevConvId > 0 && await _service.validateNovaConversationId(prevConvId)) {
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

  Future<void> _startHoldRecord() async {
    if (_sending || _recording || !_novaReady) return;
    if (!NativeAudioRecorder.isSupported) {
      _toast('当前环境不支持录音');
      return;
    }
    if (!kIsWeb) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        _toast('请先允许麦克风权限');
        return;
      }
    }
    try {
      await NativeAudioRecorder.instance.start();
      _recordTicker?.cancel();
      setState(() {
        _recording = true;
        _recordWillCancel = false;
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
      _toast('录音启动失败: $e');
    }
  }

  Future<void> _finishHoldRecord() async {
    if (!_recording) return;
    if (_recordWillCancel) {
      await _cancelHoldRecord(showHint: true);
      return;
    }
    _recordTicker?.cancel();
    setState(() => _recording = false);
    try {
      final recorded = await NativeAudioRecorder.instance.stop();
      if (recorded == null) return;
      if (recorded.durationMs < 500) {
        _toast('录音时间太短');
        return;
      }
      final bytes = await XFile(recorded.path).readAsBytes();
      final fileName = 'voice-${DateTime.now().millisecondsSinceEpoch}.wav';
      // 语音用于转写为文字（非语音消息），气泡直接以文本展示，避免出现不可播放的空语音气泡。
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
      final transcript = await _service.transcribeAudio(bytes, fileName);
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
      _toast('语音识别失败: $e');
    }
  }

  Future<void> _cancelHoldRecord({required bool showHint}) async {
    if (!_recording) return;
    _recordTicker?.cancel();
    setState(() {
      _recording = false;
      _recordWillCancel = false;
      _recordDurationMs = 0;
    });
    try {
      await NativeAudioRecorder.instance.cancel();
    } catch (_) {}
    if (showHint) _toast('已取消发送');
  }

  void _onRecordMove(LongPressMoveUpdateDetails details) {
    if (!_recording) return;
    final shouldCancel = details.offsetFromOrigin.dy < -56;
    if (shouldCancel == _recordWillCancel) return;
    setState(() => _recordWillCancel = shouldCancel);
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
        _service.setSelectedChatModel(id);
        setState(() => _selectedModel = id);
      },
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
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NovaPageHeader(
              onBack: _handleBack,
              onNewChat: _novaReady ? _startNewChat : null,
              onHistory: widget.onHistory,
              onOpenKb: widget.onOpenKb,
              actionsEnabled: !(_sending && _hasActiveAssistantStream()),
            ),
            NovaC4ModelPicker(
              models: _chatModels,
              selected: _selectedModel,
              modelCatalog: _modelCatalog,
              onTap: _pickModel,
              enabled: !(_sending || _serverGenerating),
            ),
            if (_loading)
              const Expanded(
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
                      ..._buildMessageList(),
                    ],
                  ),
                ),
              ),
            NovaC4BusyHint(text: _busyHint),
            NovaDraftTray(items: _drafts, onRemove: _removeDraft),
            NovaC4QuickActions(
              enabled: inputEnabled && !(_sending && _hasActiveAssistantStream()),
              onCamera: _pickCamera,
              onAlbum: _pickAlbum,
              onNewChat: _startNewChat,
            ),
            ChatInputBar(
              controller: _inputController,
              voiceMode: _voiceMode,
              sending: _sending,
              enabled: inputEnabled,
              hintText: inputHint,
              onToggleVoice: () => setState(() => _voiceMode = !_voiceMode),
              onSend: _submitInput,
              onStop: _stopGeneration,
              onEmoji: inputEnabled ? _pickFile : null,
              secondaryIcon: Icons.attach_file,
              recording: _recording,
              recordWillCancel: _recordWillCancel,
              recordDurationMs: _recordDurationMs,
              onVoiceHoldStart: (_) => _startHoldRecord(),
              onVoiceHoldMove: _onRecordMove,
              onVoiceHoldEnd: (_) => _finishHoldRecord(),
              onVoiceHoldCancel: () => _cancelHoldRecord(showHint: false),
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

  Widget _buildMessageRow(NativeNovaMessage m) {
    final mine = m.role == 'user';
    final time = m.isWelcome ? '' : novaMsgTimeLabel(m.createdAt);
    final thinking = !mine &&
        m.text.isEmpty &&
        m.streaming &&
        (_sending || _serverGenerating || m.thinkStatus.isNotEmpty || m.thinkText.isNotEmpty);
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
        userAvatarUrl: _userAvatarUrl,
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
