import '../conversation/comm_unread_notifier.dart';
import '../conversation/conversation_models.dart';
import 'windows_tray_unread_item.dart';

/// 把当前会话列表压成托盘悬停浮层数据（最多 6 条）。
List<WindowsTrayUnreadItem> windowsTrayUnreadItemsFromConversations({
  required List<NativeConversation> rows,
  required CommUnreadNotifier commUnread,
  int viewingId = 0,
}) {
  final unread = <NativeConversation>[];
  for (final conversation in rows) {
    if (conversation.id <= 0 || conversation.id == viewingId) continue;
    if (!conversation.isListedInInbox) continue;
    if (commUnread.effectiveUnreadCount(conversation) <= 0) continue;
    unread.add(conversation);
  }
  unread.sort((a, b) => b.sortTimestamp.compareTo(a.sortTimestamp));
  return [
    for (final conversation in unread.take(6))
      WindowsTrayUnreadItem(
        conversationId: conversation.id,
        title: _trayTitle(conversation),
        unread: commUnread.effectiveUnreadCount(conversation),
        initial: _trayInitial(conversation),
        preview: _trayPreview(conversation),
      ),
  ];
}

String _trayTitle(NativeConversation conversation) {
  final title = conversation.displayTitle.trim();
  return title.isEmpty ? '会话' : title;
}

String _trayInitial(NativeConversation conversation) {
  if (conversation.isSelfMemo) return '备';
  final title = _trayTitle(conversation);
  if (title.isEmpty) return '?';
  return String.fromCharCodes(title.runes.take(1));
}

String _trayPreview(NativeConversation conversation) {
  var preview = conversation.preview.trim().replaceAll('\n', ' ');
  if (preview.isEmpty) return '有未读消息';
  if (preview.runes.length <= 40) return preview;
  return '${String.fromCharCodes(preview.runes.take(40))}…';
}
