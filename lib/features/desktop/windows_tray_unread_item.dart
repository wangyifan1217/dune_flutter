/// 托盘悬停浮层里的一条未读会话。
class WindowsTrayUnreadItem {
  const WindowsTrayUnreadItem({
    required this.conversationId,
    required this.title,
    required this.unread,
    required this.initial,
    this.preview = '',
    this.color = 0xFF7B5CD8,
  });

  final int conversationId;
  final String title;
  final int unread;
  final String initial;
  final String preview;
  final int color;

  Map<String, Object> toMap() => <String, Object>{
    'id': conversationId,
    'title': title,
    'unread': unread,
    'initial': initial,
    'preview': preview,
    'color': color,
  };
}
