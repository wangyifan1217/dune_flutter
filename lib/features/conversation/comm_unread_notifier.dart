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
    if (!isMutedConversation(conversation)) return unread;
    // 免打扰：Tab 角标只计 @ 我；私聊通常无 @，角标为 0。
    return mutedMentionUnreadFor(conversation.id);
  }

  int sumConversationUnread({
    required List<NativeConversation> rows,
    required int notifUnread,
    int aiSummaryUnread = 0,
    Set<int> treatAsReadIds = const <int>{},
  }) {
    var total = notifUnread + aiSummaryUnread;
    for (final conversation in rows) {
      if (!conversation.isVisible) continue;
      if (treatAsReadIds.contains(conversation.id)) continue;
      total += effectiveUnreadCount(conversation);
    }
    return total;
  }

  /// 免打扰会话：群 / 审批工作群 / 私聊（与资料页开关一致）。
  static bool isMutedConversation(NativeConversation conversation) {
    if (!conversation.muted) return false;
    return conversation.isGroup ||
        conversation.isWorkgroupApproval ||
        conversation.isPrivate;
  }

  /// 兼容旧调用名；语义同 [isMutedConversation]。
  static bool isMutedGroup(NativeConversation conversation) =>
      isMutedConversation(conversation);
}
