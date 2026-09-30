import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/conversation/inbox_widgets.dart';

void main() {
  test('marked unread shows a dot only when there is no unread count', () {
    expect(
      chatInboxMarkedUnreadDot(unreadCount: 0, markedUnread: true),
      isTrue,
    );
    expect(
      chatInboxMarkedUnreadDot(unreadCount: 3, markedUnread: true),
      isFalse,
    );
    expect(
      chatInboxMarkedUnreadDot(unreadCount: 0, markedUnread: false),
      isFalse,
    );
  });
}
