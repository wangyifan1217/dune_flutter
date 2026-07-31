import '../ai_summary/ai_summary_models.dart';
import 'conversation_models.dart';
import 'notification_service.dart';

/// 会话列表内存快照：主 Tab 来回切换时先展示，再静默拉新。
class ConversationInboxSnapshot {
  const ConversationInboxSnapshot({
    required this.conversations,
    required this.notif,
    required this.novaStorage,
    required this.aiSummaryPreview,
    required this.aiSummaryUnread,
  });

  final List<NativeConversation> conversations;
  final NativeNotificationSummary notif;
  final Map<String, String> novaStorage;
  final AiSummaryItem? aiSummaryPreview;
  final int aiSummaryUnread;
}

class ConversationInboxCache {
  ConversationInboxCache._();

  static final ConversationInboxCache instance = ConversationInboxCache._();

  int? _userId;
  ConversationInboxSnapshot? _snapshot;

  /// 会话列表滚动偏移（进会话再返回时恢复用）。
  double _scrollOffset = 0;

  ConversationInboxSnapshot? peek(int userId) {
    if (userId <= 0) return null;
    if (_userId != userId) return null;
    final snap = _snapshot;
    if (snap == null || snap.conversations.isEmpty) return null;
    return ConversationInboxSnapshot(
      conversations: List<NativeConversation>.unmodifiable(snap.conversations),
      notif: snap.notif,
      novaStorage: Map<String, String>.unmodifiable(snap.novaStorage),
      aiSummaryPreview: snap.aiSummaryPreview,
      aiSummaryUnread: snap.aiSummaryUnread,
    );
  }

  double peekScrollOffset(int userId) {
    if (userId <= 0 || _userId != userId) return 0;
    return _scrollOffset;
  }

  void saveScrollOffset({required int userId, required double offset}) {
    if (userId <= 0) return;
    if (_userId != null && _userId != userId) return;
    _userId ??= userId;
    _scrollOffset = offset < 0 ? 0 : offset;
  }

  void put({
    required int userId,
    required List<NativeConversation> conversations,
    required NativeNotificationSummary notif,
    required Map<String, String> novaStorage,
    AiSummaryItem? aiSummaryPreview,
    int aiSummaryUnread = 0,
  }) {
    if (userId <= 0) return;
    if (_userId != null && _userId != userId) {
      _scrollOffset = 0;
    }
    _userId = userId;
    _snapshot = ConversationInboxSnapshot(
      conversations: List<NativeConversation>.unmodifiable(conversations),
      notif: notif,
      novaStorage: Map<String, String>.unmodifiable(novaStorage),
      aiSummaryPreview: aiSummaryPreview,
      aiSummaryUnread: aiSummaryUnread,
    );
  }

  void clear() {
    _userId = null;
    _snapshot = null;
    _scrollOffset = 0;
  }
}
