import 'dart:async';

import 'package:flutter/foundation.dart';

import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';

/// 机器人「正在分析」跨页状态：离开会话后列表头像仍可动画，再进会话可恢复等待态。
class RobotAnalyzingCoordinator extends ChangeNotifier {
  RobotAnalyzingCoordinator._();

  static final RobotAnalyzingCoordinator instance =
      RobotAnalyzingCoordinator._();

  final Map<int, _RobotAnalyzingEntry> _byConv = <int, _RobotAnalyzingEntry>{};
  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  AuthSession? _session;
  Timer? _pollTimer;

  bool isAnalyzing(int conversationId) =>
      conversationId > 0 && _byConv.containsKey(conversationId);

  DateTime? startedAtFor(int conversationId) =>
      _byConv[conversationId]?.startedAt;

  String? robotKeyFor(int conversationId) =>
      _byConv[conversationId]?.robotKey;

  Iterable<int> get analyzingConversationIds => _byConv.keys;

  void bindSession(AuthSession session) {
    if (_session?.userId == session.userId &&
        _session?.token == session.token) {
      return;
    }
    _session = session;
    _rtSub?.cancel();
    _rtSub = ConversationRealtimeHub.instance.of(session).events.listen(_onRt);
  }

  void markAnalyzing({
    required int conversationId,
    required String robotKey,
    String? question,
  }) {
    if (conversationId <= 0) return;
    final key = robotKey.trim();
    final prev = _byConv[conversationId];
    final already = prev != null;
    _byConv[conversationId] = _RobotAnalyzingEntry(
      robotKey: key.isNotEmpty ? key : (prev?.robotKey ?? ''),
      question: (question ?? prev?.question ?? '').trim(),
      startedAt: prev?.startedAt ?? DateTime.now(),
    );
    _ensurePoll();
    // 已在分析中时不再反复 notify，避免列表「正在分析」闪烁。
    if (!already) notifyListeners();
  }

  void clear(int conversationId) {
    if (conversationId <= 0) return;
    if (_byConv.remove(conversationId) == null) return;
    if (_byConv.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
    notifyListeners();
  }

  void clearAll() {
    if (_byConv.isEmpty) return;
    _byConv.clear();
    _pollTimer?.cancel();
    _pollTimer = null;
    notifyListeners();
  }

  /// 用消息列表推断：末条为用户文本且其后无 ROBOT_REPLY → 仍在分析。
  bool syncFromMessages({
    required int conversationId,
    required String robotKey,
    required List<NativeChatMessage> messages,
    required int selfUserId,
  }) {
    if (conversationId <= 0) return false;
    final started = startedAtFor(conversationId);
    if (hasFreshRobotReply(messages, after: started)) {
      clear(conversationId);
      return false;
    }
    final waiting = detectWaiting(messages, selfUserId);
    if (waiting || isAnalyzing(conversationId)) {
      final q = _lastUserQuestion(messages, selfUserId);
      markAnalyzing(
        conversationId: conversationId,
        robotKey: robotKey,
        question: q,
      );
      return true;
    }
    return false;
  }

  /// 是否出现「开始分析之后」的机器人回复（完成信号）。
  static bool hasFreshRobotReply(
    List<NativeChatMessage> messages, {
    DateTime? after,
  }) {
    if (messages.isEmpty) return false;
    final last = messages.last;
    if (last.kind.toUpperCase() != 'ROBOT_REPLY') return false;
    if (after == null) return true;
    final at = last.createdAt;
    if (at == null) return true;
    // 允许数秒时钟偏差
    return !at.isBefore(after.subtract(const Duration(seconds: 2)));
  }

  static bool detectWaiting(
    List<NativeChatMessage> messages,
    int selfUserId,
  ) {
    if (messages.isEmpty) return false;
    final last = messages.last;
    final kind = last.kind.toUpperCase();
    if (kind == 'ROBOT_REPLY') return false;
    if (kind != 'TEXT') return false;
    if (last.senderUserId != selfUserId && last.id >= 0) return false;
    final pending = last.payload?['consultPending'] == true;
    // 有 consultPending 更稳；没有则仍按「末条是我的文本」推断。
    return pending || last.senderUserId == selfUserId || last.id < 0;
  }

  static String? _lastUserQuestion(
    List<NativeChatMessage> messages,
    int selfUserId,
  ) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.kind.toUpperCase() != 'TEXT') continue;
      if (m.senderUserId == selfUserId || m.id < 0) {
        final t = m.bodyText.trim();
        return t.isEmpty ? null : t;
      }
    }
    return null;
  }

  void _onRt(ConversationRealtimeEvent event) {
    if (event.type != 'message' && event.type != 'conversation_updated') {
      return;
    }
    final convId = event.conversationId ?? 0;
    if (convId <= 0 || !_byConv.containsKey(convId)) return;
    final msg = event.raw['message'];
    if (msg is Map) {
      final kind = (msg['kind'] ?? '').toString().toUpperCase();
      if (kind == 'ROBOT_REPLY') {
        clear(convId);
        return;
      }
      // 用户追问落库：保持分析态（不因其它事件误清）
      if (kind == 'TEXT') {
        _ensurePoll();
        return;
      }
    }
    _ensurePoll();
  }

  void _ensurePoll() {
    if (_byConv.isEmpty) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_pollOnce());
    });
  }

  Future<void> _pollOnce() async {
    final session = _session;
    if (session == null || _byConv.isEmpty) return;
    final service = ConversationService(session: session);
    final ids = List<int>.from(_byConv.keys);
    for (final convId in ids) {
      final started = startedAtFor(convId);
      try {
        final page = await service.fetchMessages(convId, size: 30);
        // 仅在确认「分析开始后的 ROBOT_REPLY」时清除；消息短暂不全时保持分析态，防闪烁。
        if (hasFreshRobotReply(page, after: started)) {
          clear(convId);
        }
      } catch (_) {
        // best-effort
      }
    }
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }
}

class _RobotAnalyzingEntry {
  const _RobotAnalyzingEntry({
    required this.robotKey,
    required this.question,
    required this.startedAt,
  });

  final String robotKey;
  final String question;
  final DateTime startedAt;
}
