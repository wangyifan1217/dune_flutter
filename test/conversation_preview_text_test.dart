import 'package:dunes_app/features/conversation/conversation_inbox_merge.dart';
import 'package:dunes_app/features/conversation/conversation_inbox_realtime.dart';
import 'package:dunes_app/features/conversation/conversation_mention_utils.dart';
import 'package:dunes_app/features/conversation/conversation_models.dart';
import 'package:dunes_app/features/conversation/inbox_hidden_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NativeConversation conv({
    String preview = '旧消息',
    DateTime? updatedAt,
    String kind = 'PRIVATE',
    int unreadCount = 0,
    bool hasUnreadMention = false,
    bool hasUnreadAtAll = false,
  }) {
    return NativeConversation(
      id: 299,
      kind: kind,
      title: kind == 'WORKGROUP' ? '测试群' : '李凡伊',
      unreadCount: unreadCount,
      preview: preview,
      updatedAt: updatedAt ?? DateTime.utc(2026, 8, 27, 2, 21),
      hasUnreadMention: hasUnreadMention,
      hasUnreadAtAll: hasUnreadAtAll,
    );
  }

  ConversationRealtimeEventLike mentionEvent() {
    return const ConversationRealtimeEventLike(
      type: 'message',
      conversationId: 299,
      raw: {},
      message: {
        'kind': 'TEXT',
        'bodyText': '记得回复一下 @李凡伊',
        'createdAt': '2026-08-27T02:23:00.000Z',
        'sender': {'userId': 2, 'displayName': '王奕凡'},
        'payload': {
          'mentionUserIds': [1],
        },
      },
    );
  }

  ConversationRealtimeEventLike followUpEvent() {
    return const ConversationRealtimeEventLike(
      type: 'message',
      conversationId: 299,
      raw: {},
      message: {
        'kind': 'TEXT',
        'bodyText': '好的 领导',
        'createdAt': '2026-08-27T02:24:00.000Z',
        'sender': {'userId': 1, 'displayName': '李凡伊'},
      },
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

  test('群聊 @我 后后续消息仍保留 [@了你]，进会话才清', () {
    final afterMention = ConversationInboxRealtime.applyEvent(
      items: [conv(kind: 'WORKGROUP')],
      event: mentionEvent(),
      selfUserId: 1,
      selfDisplayName: '李凡伊',
    );
    expect(afterMention.single.hasUnreadMention, isTrue);
    expect(afterMention.single.unreadMentionLabel, '[@了你]');
    expect(afterMention.single.preview, contains('记得回复一下'));

    final afterFollowUp = ConversationInboxRealtime.applyEvent(
      items: afterMention,
      event: followUpEvent(),
      selfUserId: 1,
      selfDisplayName: '李凡伊',
    );
    expect(afterFollowUp.single.hasUnreadMention, isTrue);
    expect(afterFollowUp.single.unreadMentionLabel, '[@了你]');
    expect(afterFollowUp.single.preview, contains('好的 领导'));

    final afterRead = ConversationInboxRealtime.applyEvent(
      items: afterFollowUp,
      event: const ConversationRealtimeEventLike(
        type: 'read',
        conversationId: 299,
        raw: {'userId': 1},
      ),
      selfUserId: 1,
      selfDisplayName: '李凡伊',
    );
    expect(afterRead.single.hasUnreadMention, isFalse);
    expect(afterRead.single.unreadMentionLabel, isNull);
    expect(afterRead.single.unreadCount, 0);
  });

  test('静默刷新未读仍在时保留本地 [@了你]', () {
    final merged = mergeInboxConversations(
      [
        conv(
          kind: 'WORKGROUP',
          unreadCount: 2,
          hasUnreadMention: true,
          preview: '好的 领导',
        ),
      ],
      [
        conv(
          kind: 'WORKGROUP',
          unreadCount: 2,
          preview: '好的 领导',
        ),
      ],
    );
    expect(merged.single.hasUnreadMention, isTrue);
    expect(merged.single.unreadMentionLabel, '[@了你]');
  });

  test('@所有人 显示 [@所有人] 而不是 [@了你]', () {
    const event = ConversationRealtimeEventLike(
      type: 'message',
      conversationId: 299,
      raw: {},
      message: {
        'kind': 'TEXT',
        'bodyText': '@所有人 记得回消息',
        'createdAt': '2026-08-27T02:23:00.000Z',
        'sender': {'userId': 2, 'displayName': '王奕凡'},
        'payload': {
          'mentionAll': true,
          'mentionUserIds': [1, 3, 4],
        },
      },
    );
    expect(
      ConversationMentionUtils.eventMentionKind(
        event: event,
        selfUserId: 1,
        selfDisplayName: '李凡伊',
      ),
      ConversationMentionKind.atAll,
    );
    final after = ConversationInboxRealtime.applyEvent(
      items: [conv(kind: 'WORKGROUP')],
      event: event,
      selfUserId: 1,
      selfDisplayName: '李凡伊',
    );
    expect(after.single.hasUnreadAtAll, isTrue);
    expect(after.single.hasUnreadMention, isFalse);
    expect(after.single.unreadMentionLabel, '[@所有人]');
  });
}
