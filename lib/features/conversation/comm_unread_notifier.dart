import 'package:flutter/foundation.dart';

import 'conversation_models.dart';

/// 通讯 Tab 红点：会话未读 + 系统通知未读。
class CommUnreadNotifier extends ChangeNotifier {
  int _total = 0;
  final Map<int, int> _mutedMentionUnread = <int, int>{};

  int get total => _total;

  int mutedMentionUnreadFor(int conversationId) => _mutedMentionUnread[conversationId] ?? 0;

  void update(int total) {
    final next = total < 0 ? 0 : total;
    if (_total == next) return;
    _total = next;
    notifyListeners();
  }

  void bump([int delta = 1]) {
    if (delta <= 0) return;
    update(_total + delta);
  }

  void recordMutedMention(int conversationId, {int delta = 1}) {
    if (conversationId <= 0 || delta <= 0) return;
    _mutedMentionUnread[conversationId] = mutedMentionUnreadFor(conversationId) + delta;
    bump(delta);
  }

  void clearMutedMention(int conversationId) {
    if (conversationId <= 0) return;
    final prev = _mutedMentionUnread.remove(conversationId) ?? 0;
    if (prev > 0) update(_total - prev);
  }

  int effectiveUnreadCount(NativeConversation conversation) {
    final unread = conversation.unreadCount;
    if (!_isMutedGroup(conversation)) return unread;
    final mentionUnread = mutedMentionUnreadFor(conversation.id);
    return unread > mentionUnread ? unread : mentionUnread;
  }

  int sumConversationUnread({
    required List<NativeConversation> rows,
    required int notifUnread,
  }) {
    var total = notifUnread;
    for (final conversation in rows) {
      if (!conversation.isVisible) continue;
      total += effectiveUnreadCount(conversation);
    }
    return total;
  }

  static bool isMutedGroup(NativeConversation conversation) {
    return conversation.muted &&
        (conversation.isGroup || conversation.isWorkgroupApproval);
  }

  bool _isMutedGroup(NativeConversation conversation) => isMutedGroup(conversation);
}
