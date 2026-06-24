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

  static final NovaBackgroundCoordinator instance = NovaBackgroundCoordinator._();

  AuthSession? _session;
  NativeNovaService? _service;
  Timer? _pollTimer;
  int _pollConvId = 0;
  bool _pendingCommBadgeBump = false;
  final Set<int> _finalizedConvIds = <int>{};

  void clearFinalizedConversation(int conversationId) {
    if (conversationId > 0) _finalizedConvIds.remove(conversationId);
  }

  bool takePendingCommBadgeBump() {
    if (!_pendingCommBadgeBump) return false;
    _pendingCommBadgeBump = false;
    return true;
  }

  void markPendingCommBadgeBump() {
    _pendingCommBadgeBump = true;
  }

  NativeNovaService serviceFor(AuthSession session) {
    if (_session?.userId != session.userId) {
      stopPoll();
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
    if (conversationId > 0) _pollConvId = conversationId;
    if (!generating || conversationId <= 0) return;
    ensurePoll(session, conversationId: conversationId);
  }

  void ensurePoll(AuthSession session, {int conversationId = 0}) {
    if (conversationId > 0) _pollConvId = conversationId;
    if (_pollTimer != null) return;
    unawaited(_startPoll(session));
  }

  Future<void> _startPoll(AuthSession session) async {
    if (_pollTimer != null) return;
    var convId = _pollConvId;
    if (convId <= 0) {
      final storage = await NovaWebStorage.load(session.userId);
      convId = novaActiveConvIdFromStorage(storage);
    }
    if (convId <= 0) return;
    _pollConvId = convId;
    final svc = serviceFor(session);
    _pollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      unawaited(_pollTick(svc, session, convId));
    });
    unawaited(_pollTick(svc, session, convId));
  }

  Future<void> _pollTick(
    NativeNovaService svc,
    AuthSession session,
    int convId,
  ) async {
    final storage = await NovaWebStorage.load(session.userId);
    final localGen = readNovaGeneratingFromStorage(
      storage,
      convId: convId,
      activeConvId: convId,
    );
    final draft = readNovaStreamDraftFromStorage(storage, convId);
    if (!shouldPersistNovaGenerating(
      localGen: localGen,
      draft: draft,
      streamInFlight: svc.isStreamInFlight,
    )) {
      if (localGen != null) {
        await clearNovaGeneratingState(
          userId: session.userId,
          conversationId: convId,
        );
        await clearNovaStreamDraftState(
          userId: session.userId,
          conversationId: convId,
        );
      }
      try {
        final history = await svc.fetchFullHistory(convId);
        if (!history.assistantGenerating) {
          stopPoll();
        }
      } catch (_) {}
      notifyListeners();
      return;
    }
    if (localGen == null) {
      try {
        final history = await svc.fetchFullHistory(convId);
        if (!history.assistantGenerating) {
          stopPoll();
        }
      } catch (_) {}
      return;
    }
    if (_isStoppedStatus(localGen.status)) {
      await clearNovaGeneratingState(
        userId: session.userId,
        conversationId: convId,
      );
      await clearNovaStreamDraftState(
        userId: session.userId,
        conversationId: convId,
      );
      stopPoll();
      notifyListeners();
      return;
    }

    try {
      final history = await svc.fetchFullHistory(convId);
      final after = localGen.afterMessageId;
      if (history.assistantGenerating && !_hasAiReplyAfter(history.messages, after)) {
        notifyListeners();
        return;
      }
      if (_hasAiReplyAfter(history.messages, after)) {
        if (svc.isStreamInFlight) {
          notifyListeners();
          return;
        }
        await onGenerationComplete(
          session: session,
          conversationId: convId,
          messages: history.messages,
        );
        return;
      }
      if (!history.assistantGenerating) {
        if (svc.isStreamInFlight) {
          notifyListeners();
          return;
        }
        if ((draft?.text ?? '').trim().isNotEmpty) {
          if (kDebugMode) {
            debugPrint('[NovaBackground] finalize from draft-only conv=$convId');
          }
          await onGenerationComplete(
            session: session,
            conversationId: convId,
            messages: history.messages,
          );
          return;
        }
        if (history.messages.any((m) => m.role == 'assistant' && !m.streaming && m.text.trim().isNotEmpty)) {
          if (svc.isStreamInFlight) {
            notifyListeners();
            return;
          }
          await onGenerationComplete(
            session: session,
            conversationId: convId,
            messages: history.messages,
          );
        } else {
          await clearNovaGeneratingState(
            userId: session.userId,
            conversationId: convId,
          );
          await clearNovaStreamDraftState(
            userId: session.userId,
            conversationId: convId,
          );
          stopPoll();
          notifyListeners();
        }
      }
    } catch (_) {
      notifyListeners();
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
    if (svc.isStreamInFlight) return;
    final storage = await NovaWebStorage.load(session.userId);
    final draft = readNovaStreamDraftFromStorage(storage, conversationId);
    final draftUserText = (draft?.userText ?? '').trim();
    final draftReplyText = (draft?.text ?? '').trim();
    final draftThinkText = (draft?.thinkText ?? '').trim();

    final initialRows = messages.where((m) => !m.isWelcome).toList(growable: false);
    final needsFinalize = (draftReplyText.isNotEmpty &&
            !initialRows.any((m) => m.role == 'assistant' && m.text.trim() == draftReplyText)) ||
        (draftUserText.isNotEmpty &&
            !initialRows.any((m) => m.role == 'user' && m.text.trim() == draftUserText));

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
        resolvedRows = refreshed.messages.where((m) => !m.isWelcome).toList(growable: false);
      } catch (_) {}
    }
    resolvedRows = await _ensureRecoverableRows(
      svc,
      conversationId,
      resolvedRows,
      draftUserText: draftUserText,
      draftReplyText: draftReplyText,
      draftThinkText: draftThinkText,
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
          userPayload: user.payload,
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

    await clearNovaGeneratingState(
      userId: session.userId,
      conversationId: conversationId,
    );
    final rows = resolvedRows;
    if (rows.isNotEmpty) {
      await svc.persistSession(conversationId, rows);
      await svc.flushConvToLocalHistory(conversationId, rows);
      await svc.flushHistorySyncQueue();
    }
    await NovaWebStorage.removeKeys(
      session.userId,
      [novaStreamDraftStorageKey(conversationId)],
    );
    stopPoll();
    _finalizedConvIds.add(conversationId);
    _pendingCommBadgeBump = true;
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
  }
  ) async {
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
          debugPrint('[NovaBackground] skip history sync: no assistant conv=$conversationId');
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
        debugPrint('[NovaBackground] skip history sync: no user conv=$conversationId');
      }
      return;
    }
    await svc.registerHistoryTurn(
      conversationId: conversationId,
      messageId: effectiveUser.id > 0
          ? effectiveUser.id
          : (assistant.id > 0 ? assistant.id : DateTime.now().millisecondsSinceEpoch),
      userMessage: effectiveUser.text,
      assistantMessage: assistant.text,
      lastMessageAt: (assistant.createdAt ?? effectiveUser.createdAt ?? DateTime.now())
          .toUtc()
          .toIso8601String(),
      userPayload: effectiveUser.payload,
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
        debugPrint('[NovaBackground] recovered user from persisted session conv=$conversationId');
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
  }) async {
    final out = [...rows];
    final hasUser = out.any((m) => m.role == 'user' && m.text.trim().isNotEmpty);
    final hasAssistant = out.any((m) => m.role == 'assistant' && m.text.trim().isNotEmpty);
    if (!hasUser) {
      final recovered = await svc.resolveLatestUserMessage(
        conversationId,
        fallbackText: draftUserText,
      );
      if (recovered != null) {
        if (kDebugMode) {
          debugPrint('[NovaBackground] injected recovered user conv=$conversationId');
        }
        out.insert(0, recovered);
      }
    }
    if (!hasAssistant && draftReplyText.trim().isNotEmpty) {
      if (kDebugMode) {
        debugPrint('[NovaBackground] injected draft assistant conv=$conversationId');
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

  bool _hasAiReplyAfter(List<NativeNovaMessage> rows, int afterMessageId) {
    if (afterMessageId <= 0) return false;
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

  bool _isStoppedStatus(String status) => status.trim().contains('停止');

  void notifyInboxRefresh() => notifyListeners();

  void stopPoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void resetForUser(int userId) {
    if (_session?.userId != userId) return;
    stopPoll();
    _pollConvId = 0;
    _finalizedConvIds.clear();
  }
}
