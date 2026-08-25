import 'dart:async';

import '../auth/auth_session.dart';
import '../conversation/comm_unread_notifier.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import 'windows_desktop_tray.dart';
import 'windows_tray_unread_avatars.dart';

int _pushGen = 0;

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
        avatarPng: windowsTrayCachedAvatarPng(conversation),
      ),
  ];
}

/// 先立刻推送未读列表（有缓存则带 IM 头像），再异步补齐头像后更新浮层。
void windowsTrayPushUnreadFromConversations({
  required List<NativeConversation> rows,
  required CommUnreadNotifier commUnread,
  int viewingId = 0,
  AuthSession? session,
  ConversationService? avatarService,
}) {
  final items = windowsTrayUnreadItemsFromConversations(
    rows: rows,
    commUnread: commUnread,
    viewingId: viewingId,
  );
  windowsTrayUpdateUnreadItems(items);
  if (items.isEmpty) return;
  final gen = ++_pushGen;
  unawaited(() async {
    final hydrated = await windowsTrayHydrateUnreadAvatars(
      items: items,
      conversations: rows,
      session: session,
      avatarService: avatarService,
    );
    if (gen != _pushGen) return;
    if (_sameAvatars(items, hydrated)) return;
    windowsTrayUpdateUnreadItems(hydrated);
  }());
}

bool _sameAvatars(
  List<WindowsTrayUnreadItem> a,
  List<WindowsTrayUnreadItem> b,
) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].conversationId != b[i].conversationId) return false;
    final left = a[i].avatarPng;
    final right = b[i].avatarPng;
    if (identical(left, right)) continue;
    if (left == null || right == null) return false;
    if (left.length != right.length) return false;
  }
  return true;
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
