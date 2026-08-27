import 'package:dunes_app/features/conversation/conversation_inbox_merge.dart';
import 'package:dunes_app/features/conversation/conversation_inbox_realtime.dart';
import 'package:dunes_app/features/conversation/conversation_models.dart';
import 'package:dunes_app/features/conversation/inbox_hidden_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NativeConversation conv({
    String preview = '旧消息',
    DateTime? updatedAt,
  }) {
    return NativeConversation(
      id: 299,
      kind: 'PRIVATE',
      title: '李凡伊',
      unreadCount: 0,
      preview: preview,
      updatedAt: updatedAt ?? DateTime.utc(2026, 8, 27, 2, 21),
    );
  }

  test('conversation_updated 不会把测试.jpg 覆盖成发送了一张图片', () {
    final afterMessage = ConversationInboxRealtime.applyEvent(
      items: [conv()],
      event: ConversationRealtimeEventLike(
        type: 'message',
        conversationId: 299,
        raw: const {},
        message: const {
          'kind': 'TEXT',
          'bodyText': '测试.jpg',
          'createdAt': '2026-08-27T02:23:00.000Z',
          'sender': {'userId': 1, 'displayName': '王奕凡'},
        },
      ),
      selfUserId: 1,
      selfDisplayName: '王奕凡',
    );
    expect(afterMessage.single.preview, '测试.jpg');

    final afterUpdated = ConversationInboxRealtime.applyEvent(
      items: afterMessage,
      event: const ConversationRealtimeEventLike(
        type: 'conversation_updated',
        conversationId: 299,
        raw: {'lastMessagePreview': '发送了一张图片'},
      ),
      selfUserId: 1,
    );
    expect(afterUpdated.single.preview, '测试.jpg');
  });

  test('静默刷新时保留本地原文预览，不被服务端误压的图片摘要覆盖', () {
    final at = DateTime.utc(2026, 8, 27, 2, 23);
    final merged = mergeInboxConversations(
      [conv(preview: '测试.jpg', updatedAt: at)],
      [conv(preview: '发送了一张图片', updatedAt: at)],
    );
    expect(merged.single.preview, '测试.jpg');
  });
}
