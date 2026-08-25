import 'dart:typed_data';

/// 托盘悬停浮层里的一条未读会话。
class WindowsTrayUnreadItem {
  const WindowsTrayUnreadItem({
    required this.conversationId,
    required this.title,
    required this.unread,
    required this.initial,
    this.preview = '',
    this.color = 0xFF7B5CD8,
    this.avatarPng,
  });

  final int conversationId;
  final String title;
  final int unread;
  final String initial;
  final String preview;
  final int color;

  /// IM 头像的 PNG 字节；为空时原生层画色块+首字。
  final Uint8List? avatarPng;

  WindowsTrayUnreadItem copyWith({Uint8List? avatarPng}) {
    return WindowsTrayUnreadItem(
      conversationId: conversationId,
      title: title,
      unread: unread,
      initial: initial,
      preview: preview,
      color: color,
      avatarPng: avatarPng ?? this.avatarPng,
    );
  }

  Map<String, Object> toMap() {
    final map = <String, Object>{
      'id': conversationId,
      'title': title,
      'unread': unread,
      'initial': initial,
      'preview': preview,
      'color': color,
    };
    final png = avatarPng;
    if (png != null && png.isNotEmpty) {
      map['avatarPng'] = png;
    }
    return map;
  }
}
