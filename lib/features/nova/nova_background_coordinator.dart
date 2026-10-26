import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import 'native_nova_service.dart';
import 'nova_generating_storage.dart';
import 'nova_inbox_preview.dart';
import 'nova_web_storage.dart';

/// 对齐 WebView `onLeave` + `startNovaGeneratingPoll`：离开 C4 后继续在后台轮询生成状态，
/// 完成后刷新 C1 预览/未读（通过 [notifyListeners] 触发列表重载）。
class NovaBackgroundCoordinator extends ChangeNotifier {
  NovaBackgroundCoordinator._();

  @visibleForTesting
  NovaBackgroundCoordinator.forTesting(
    AuthSession session,
    NativeNovaService service,
  ) : _session = session,
      _service = service;

  static final NovaBackgroundCoordinator instance =
      NovaBackgroundCoordinator._();

  AuthSession? _session;
  NativeNovaService? _service;
  Timer? _pollTimer;
  int _pollConvId = 0;
  int _pollEpoch = 0;
  final Set<int> _pollConversations = {};
  final Set<int> _pollsInFlight = {};
  bool _pollStarting = false;
  bool _pendingCommBadgeBump = false;
  bool _novaPageActive = false;
  int _visibleConversationId = 0;
  final Set<int> _finalizedConvIds = <int>{};
  final Set<int> _seenReplyConversationIds = <int>{};
  final Set<int> _unreadReplyConversationIds = <int>{};

  /// C4 页面可见时为 true；用于区分「用户已在 NOVA 内看到回复」与「后台完成需通知」。
  void setNovaPageActive(bool active, {int conversationId = 0}) {
    _novaPageActive = active;
    _visibleConversationId = active ? conversationId : 0;
  }

  bool isConversationVisible(int conversationId) =>
      _novaPageActive &&
      conversationId > 0 &&
      _visibleConversationId == conversationId;

  void clearFinalizedConversation(int conversationId) {
    if (conversationId > 0) {
      _finalizedConvIds.remove(conversationId);
      _seenReplyConversationIds.remove(conversationId);
      _unreadReplyConversationIds.remove(conversationId);
    }
  }

  /// NOVA 会话是否有用户尚未进入会话查看的最终回复。
  bool hasUnreadReplyFor(int conversationId) =>
      conversationId > 0 &&
      _unreadReplyConversationIds.contains(conversationId);

  bool get hasUnreadReply => _unreadReplyConversationIds.isNotEmpty;
  int? get latestUnreadConversationId => _unreadReplyConversationIds.lastOrNull;

  bool get isNovaPageActive => _novaPageActive;

  bool takePendingCommBadgeBump() {
    if (!_pendingCommBadgeBump) return false;
    _pendingCommBadgeBump = false;
    return true;
  }

  void markPendingCommBadgeBump({int conversationId = 0}) {
    // 已读只针对上一轮已完成回复。不能因为用户看过同一会话的旧消息，
    // 就抑制下一轮在后台完成时的提醒。
    if (isConversationVisible(conversationId)) return;
    var changed = !_pendingCommBadgeBump;
    _pendingCommBadgeBump = true;
    if (conversationId > 0) {
      changed = _unreadReplyConversationIds.add(conversationId) || changed;
    }
    if (changed) notifyListeners();
  }

  void clearPendingCommBadgeBump() {
    _pendingCommBadgeBump = false;
  }

  /// 页面已展示该会话的回答；之后离开不会再将同一回答标成未读。
  void markReplySeen(int conversationId) {
    if (conversationId > 0) {
      _seenReplyConversationIds.add(conversationId);
    }
    _unreadReplyConversationIds.remove(conversationId);
    _pendingCommBadgeBump = _unreadReplyConversationIds.isNotEmpty;
    notifyListeners();
  }

  NativeNovaService serviceFor(AuthSession session) {
    if (_session?.userId != session.userId ||
        _session?.token != session.token ||
        _session?.apiBase != session.apiBase) {
      stopPoll();
      _service?.cancelActiveStream();
      _finalizedConvIds.clear();
      _seenReplyConversationIds.clear();
      _unreadReplyConversationIds.clear();
      _pendingCommBadgeBump = false;
      _service = NativeNovaService(session: session);
      _session = session;
    }
    _service ??= NativeNovaService(session: session);
    _session = session;
    return _service!;
  }

  void onNovaPageLeave({
    required AuthSession session,
    required int conversationId,
    required bool generating,
    int afterMessageId = 0,
  }) {
    if (!generating || conversationId <= 0) return;
    ensurePoll(session, conversationId: conversationId);
  }

  void ensurePoll(AuthSession session, {int conversationId = 0}) {
    final svc = serviceFor(session);
    if (conversationId > 0) {
      _pollConvId = conversationId;
      _pollConversations.add(conversationId);
    }
    if (_pollTimer != null) {
      if (conversationId > 0)
        unawaited(_pollTick(svc, session, conversationId, _pollEpoch));
      return;
    }
    if (!_pollStarting) unawaited(_startPoll(session));
  }

  bool get isThinking =>
      _pollTimer != null ||
      (_service?.isStreamInFlight ?? false) ||
      (_service?.isPersonalQueryInFlight ?? false);

  Future<void> _startPoll(AuthSession session) async {
    if (_pollTimer != null || _pollStarting) return;
    // serviceFor 可能切换账号，先处理，防止旧账号的启动覆盖新账号。
    final svc = serviceFor(session);
    final epoch = _pollEpoch;
    _pollStarting = true;
    try {
      var convId = _pollConvId;
      if (convId <= 0) {
        final storage = await NovaWebStorage.load(session.userId);
        convId = novaActiveConvIdFromStorage(storage);
      }
      if (convId <= 0 || epoch != _pollEpoch) return;
      _pollConvId = convId;
      _pollConversations.add(convId);
      _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
        for (final target in _pollConversations.toList()) {
          unawaited(_pollTick(svc, session, target, epoch));
        }
      });
      notifyListeners();
      unawaited(_pollTick(svc, session, convId, epoch));
    } finally {
      if (epoch == _pollEpoch) _pollStarting = false;
    }
  }

  Future<void> _pollTick(
    NativeNovaService svc,
    AuthSession session,
    int convId,
    int epoch,
  ) async {
    if (_pollsInFlight.contains(convId) ||
        epoch != _pollEpoch ||
        !_pollConversations.contains(convId))
      return;
    _pollsInFlight.add(convId);
    bool current() =>
        epoch == _pollEpoch &&
        _session?.userId == session.userId &&
        _pollConversations.contains(convId);
    try {
      // 本地流（含灯塔/任务）由原请求负责落盘，不能被历史快照提前判为结束。
      if (svc.isReplyInFlightFor(convId)) return;
      final history = await svc.fetchFullHistory(convId);
      if (!current() ||
          svc.isReplyInFlightFor(convId) ||
          !history.serverStateKnown)
        return;
      if (history.assistantGenerating) {
        notifyListeners();
        return;
      }
      final storage = await NovaWebStorage.load(session.userId);
      if (!current() || svc.isReplyInFlightFor(convId)) return;
      final draft = readNovaStreamDraftFromStorage(storage, convId);
      final local = readNovaGeneratingFromStorage(storage, convId: convId);
      if (local != null && isNovaStoppedGeneratingStatus(local.status)) {
        stopPoll(conversationId: convId);
        return;
      }
      final hasReply = novaHasReplyForDraft(
        history.messages,
        afterMessageId: local?.afterMessageId ?? draft?.afterMessageId ?? 0,
        draft: draft,
      );
      if (hasReply || (draft != null && !draft.streaming)) {
        await onGenerationComplete(
          session: session,
          conversationId: convId,
          messages: history.messages,
        );
      } else {
        // 保留断线草稿供页面显示“已中断”，不要把半截正文落库成完整回答。
        await clearNovaGeneratingState(
          userId: session.userId,
          conversationId: convId,
        );
        if (!current()) return;
        stopPoll(conversationId: convId);
        notifyListeners();
      }
    } catch (_) {
      // 离线时保留缓存，后续轮询/恢复继续确认；不凭网络失败清空任务状态。
    } finally {
      if (epoch == _pollEpoch) _pollsInFlight.remove(convId);
    }
  }

  Future<void> onGenerationComplete({
    required AuthSession session,
    required int conversationId,
    required List<NativeNovaMessage> messages,
  }) async {
    if (conversationId <= 0) return;
    if (_finalizedConvIds.contains(conversationId)) return;
    final svc = serviceFor(session);
    if (svc.isReplyInFlightFor(conversationId)) return;
    final storage = await NovaWebStorage.load(session.userId);
    final draft = readNovaStreamDraftFromStorage(storage, conversationId);
    final localGen = readNovaGeneratingFromStorage(
      storage,
      convId: conversationId,
    );
    if (localGen != null && isNovaStoppedGeneratingStatus(localGen.status))
      return;
    final after =
        localGen?.afterMessageId ??
        draft?.afterMessageId ??
        messages.where((m) => m.role == 'user').lastOrNull?.id ??
        0;
    final draftUserText = (draft?.userText ?? '').trim();
    final draftReplyText = draft?.streaming == false
        ? (draft?.text ?? '').trim()
        : '';
    final draftThinkText = (draft?.thinkText ?? '').trim();

    final initialRows = messages
        .where((m) => !m.isWelcome)
        .toList(growable: false);
    if (!novaHasReplyForDraft(
          initialRows,
          afterMessageId: after,
          draft: draft,
        ) &&
        draftReplyText.isEmpty)
      return;
    final needsFinalize =
        (draftReplyText.isNotEmpty &&
            !initialRows.any(
              (m) => m.role == 'assistant' && m.text.trim() == draftReplyText,
            )) ||
        (draftUserText.isNotEmpty &&
            !initialRows.any(
              (m) => m.role == 'user' && m.text.trim() == draftUserText,
            ));

    if (needsFinalize) {
      if (kDebugMode) {
        debugPrint(
          '[NovaBackground] finalize draft conv=$conversationId '
          'user=${draftUserText.isNotEmpty} reply=${draftReplyText.isNotEmpty}',
        );
      }
      await svc.finalizeBackgroundCompletion(
        conversationId,
        userText: draftUserText,
        assistantText: draftReplyText,
        thinkText: draftThinkText,
        existingMessages: initialRows,
      );
    }

    List<NativeNovaMessage> resolvedRows = initialRows;
    if (needsFinalize) {
      try {
        final refreshed = await svc.fetchFullHistory(
          conversationId,
          applyViewSinceFilter: false,
        );
        resolvedRows = refreshed.messages
            .where((m) => !m.isWelcome)
            .toList(growable: false);
      } catch (_) {}
    }
    resolvedRows = await _ensureRecoverableRows(
      svc,
      conversationId,
      resolvedRows,
      draftUserText: draftUserText,
      draftReplyText: draftReplyText,
      draftThinkText: draftThinkText,
      draftAfterMessageId: after,
      completedDraft: draft,
    );

    if (draftReplyText.isNotEmpty) {
      final alreadyHasAssistant = resolvedRows.any(
        (m) => m.role == 'assistant' && m.text.trim() == draftReplyText,
      );
      final user = await _resolveHistoryUser(
        svc,
        session,
        conversationId,
        resolvedRows,
        fallbackText: draftUserText,
      );
      if (user != null && !alreadyHasAssistant) {
        await svc.persistAssistantTurn(
          conversationId: conversationId,
          messageId: user.id > 0 ? user.id : (draft?.afterMessageId ?? 0),
          userMessage: user.text,
          assistantMessage: draftReplyText,
          thinkText: draftThinkText,
          userPayload: svc.historyUserPayloadFromMessage(user),
          existingMessages: resolvedRows,
        );
      } else if (user != null) {
        await _registerLastTurnIfComplete(
          svc,
          session,
          conversationId,
          resolvedRows,
          fallbackUserText: draftUserText,
          fallbackAssistantText: draftReplyText,
          fallbackThinkText: draftThinkText,
        );
      }
    }

    final rows = resolvedRows;
    if (!novaHasReplyForDraft(rows, afterMessageId: after, draft: draft) ||
        svc.isReplyInFlightFor(conversationId))
      return;
    await svc.persistSession(conversationId, rows);
    final savedRows = await svc.loadPersistedConversation(conversationId);
    if (!novaHasReplyForDraft(savedRows, afterMessageId: after, draft: draft))
      return;
    await clearNovaGeneratingState(
      userId: session.userId,
      conversationId: conversationId,
    );
    await svc.flushConvToLocalHistory(conversationId, savedRows);
    unawaited(svc.flushHistorySyncQueue());
    await NovaWebStorage.removeKeys(session.userId, [
      novaStreamDraftStorageKey(conversationId),
    ]);
    stopPoll(conversationId: conversationId);
    _finalizedConvIds.add(conversationId);
    markPendingCommBadgeBump(conversationId: conversationId);
    notifyListeners();
    if (kDebugMode) {
      debugPrint('[NovaBackground] generation complete conv=$conversationId');
    }
  }

  Future<void> _registerLastTurnIfComplete(
    NativeNovaService svc,
    AuthSession session,
    int conversationId,
    List<NativeNovaMessage> rows, {
    String fallbackUserText = '',
    String fallbackAssistantText = '',
    String fallbackThinkText = '',
  }) async {
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
    if (assistant == null) {
      final reply = fallbackAssistantText.trim();
      if (reply.isNotEmpty) {
        assistant = NativeNovaMessage(
          id: DateTime.now().millisecondsSinceEpoch,
          role: 'assistant',
          text: reply,
          thinkText: fallbackThinkText,
          createdAt: DateTime.now(),
        );
      } else {
        if (kDebugMode) {
          debugPrint(
            '[NovaBackground] skip history sync: no assistant conv=$conversationId',
          );
        }
        return;
      }
    }
    final effectiveUser = await _resolveHistoryUser(
      svc,
      session,
      conversationId,
      rows,
      preferred: user,
      fallbackText: fallbackUserText,
    );
    if (effectiveUser == null) {
      if (kDebugMode) {
        debugPrint(
          '[NovaBackground] skip history sync: no user conv=$conversationId',
        );
      }
      return;
    }
    await svc.registerHistoryTurn(
      conversationId: conversationId,
      messageId: effectiveUser.id > 0
          ? effectiveUser.id
          : (assistant.id > 0
                ? assistant.id
                : DateTime.now().millisecondsSinceEpoch),
      userMessage: effectiveUser.text,
      assistantMessage: assistant.text,
      lastMessageAt:
          (assistant.createdAt ?? effectiveUser.createdAt ?? DateTime.now())
              .toUtc()
              .toIso8601String(),
      userPayload: svc.historyUserPayloadFromMessage(effectiveUser),
    );
    if (kDebugMode) {
      debugPrint(
        '[NovaBackground] history sync requested conv=$conversationId '
        'msg=${effectiveUser.id > 0 ? effectiveUser.id : assistant.id}',
      );
    }
  }

  Future<NativeNovaMessage?> _resolveHistoryUser(
    NativeNovaService svc,
    AuthSession session,
    int conversationId,
    List<NativeNovaMessage> rows, {
    NativeNovaMessage? preferred,
    String fallbackText = '',
  }) async {
    if (preferred != null && preferred.text.trim().isNotEmpty) return preferred;
    for (var i = rows.length - 1; i >= 0; i--) {
      final m = rows[i];
      if (m.role != 'assistant' && m.text.trim().isNotEmpty) return m;
    }
    final persisted = await svc.resolveLatestUserMessage(
      conversationId,
      fallbackText: fallbackText,
    );
    if (persisted != null) {
      if (kDebugMode) {
        debugPrint(
          '[NovaBackground] recovered user from persisted session conv=$conversationId',
        );
      }
      return persisted;
    }
    final storage = await NovaWebStorage.load(session.userId);
    final draft = readNovaStreamDraftFromStorage(storage, conversationId);
    final text = (draft?.userText ?? '').trim();
    if (text.isEmpty) return null;
    return NativeNovaMessage(
      id: draft?.afterMessageId ?? 0,
      role: 'user',
      text: text,
      createdAt: DateTime.now(),
    );
  }

  Future<List<NativeNovaMessage>> _ensureRecoverableRows(
    NativeNovaService svc,
    int conversationId,
    List<NativeNovaMessage> rows, {
    String draftUserText = '',
    String draftReplyText = '',
    String draftThinkText = '',
    int draftAfterMessageId = 0,
    NovaStreamDraft? completedDraft,
  }) async {
    final out = [...rows];
    final hasUser = novaHasMatchingUserMessage(
      out,
      afterMessageId: draftAfterMessageId,
      userText: draftUserText,
    );
    final hasAssistant = novaHasReplyForDraft(
      out,
      afterMessageId: draftAfterMessageId,
      draft: completedDraft,
    );
    if (!hasUser) {
      final recovered = draftUserText.isNotEmpty && draftAfterMessageId > 0
          ? NativeNovaMessage(
              id: draftAfterMessageId,
              role: 'user',
              text: draftUserText,
              createdAt: DateTime.now(),
            )
          : await svc.resolveLatestUserMessage(
              conversationId,
              fallbackText: draftUserText,
            );
      if (recovered != null) {
        if (kDebugMode) {
          debugPrint(
            '[NovaBackground] injected recovered user conv=$conversationId',
          );
        }
        out.insert(0, recovered);
      }
    }
    if (!hasAssistant && draftReplyText.trim().isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[NovaBackground] injected draft assistant conv=$conversationId',
        );
      }
      out.add(
        NativeNovaMessage(
          id: DateTime.now().millisecondsSinceEpoch,
          role: 'assistant',
          text: draftReplyText.trim(),
          thinkText: draftThinkText.trim(),
          createdAt: DateTime.now(),
        ),
      );
    }
    out.sort((a, b) {
      final ta = a.createdAt?.millisecondsSinceEpoch ?? a.id;
      final tb = b.createdAt?.millisecondsSinceEpoch ?? b.id;
      return ta.compareTo(tb);
    });
    return out;
  }

  void notifyInboxRefresh() => notifyListeners();

  void stopPoll({int? conversationId}) {
    if (conversationId != null) {
      _pollConversations.remove(conversationId);
      _pollsInFlight.remove(conversationId);
      if (_pollConversations.isNotEmpty) {
        notifyListeners();
        return;
      }
    }
    _pollConversations.clear();
    _pollsInFlight.clear();
    _pollEpoch++;
    _pollStarting = false;
    final wasPolling = _pollTimer != null;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (wasPolling) notifyListeners();
  }

  void resetForUser(int userId) {
    if (_session?.userId != userId) return;
    stopPoll();
    _service?.cancelActiveStream();
    _service = null;
    _session = null;
    _novaPageActive = false;
    _pendingCommBadgeBump = false;
    _pollConvId = 0;
    _finalizedConvIds.clear();
    _seenReplyConversationIds.clear();
    _unreadReplyConversationIds.clear();
  }
}
