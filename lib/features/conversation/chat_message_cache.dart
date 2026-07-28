import 'conversation_models.dart';

/// 会话消息内存缓存：双栏切换 / 离开再进时先展示，后台再静默刷新。
class ChatMessageCache {
  ChatMessageCache._();

  static final ChatMessageCache instance = ChatMessageCache._();

  static const int maxConversations = 16;
  static const int maxMessagesPerConversation = 80;

  final Map<int, List<NativeChatMessage>> _byConv =
      <int, List<NativeChatMessage>>{};
  final List<int> _lru = <int>[];

  List<NativeChatMessage>? peek(int conversationId) {
    if (conversationId <= 0) return null;
    final list = _byConv[conversationId];
    if (list == null || list.isEmpty) return null;
    return List<NativeChatMessage>.unmodifiable(list);
  }

  void put(int conversationId, List<NativeChatMessage> messages) {
    if (conversationId <= 0) return;
    final positive = <NativeChatMessage>[
      for (final m in messages)
        if (m.id > 0) m,
    ];
    if (positive.isEmpty) {
      remove(conversationId);
      return;
    }
    final trimmed = positive.length > maxMessagesPerConversation
        ? positive.sublist(positive.length - maxMessagesPerConversation)
        : positive;
    _byConv[conversationId] = List<NativeChatMessage>.from(trimmed);
    _lru.remove(conversationId);
    _lru.add(conversationId);
    while (_lru.length > maxConversations) {
      final old = _lru.removeAt(0);
      _byConv.remove(old);
    }
  }

  void remove(int conversationId) {
    if (conversationId <= 0) return;
    _byConv.remove(conversationId);
    _lru.remove(conversationId);
  }

  void clear() {
    _byConv.clear();
    _lru.clear();
  }
}
