import 'package:dunes_app/features/search/global_search_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('message search hit keeps its sender avatar fields', () {
    const hit = GlobalMessageHit(
      conversationId: 1,
      conversationTitle: '项目群',
      messageId: 2,
      senderName: '张三',
      senderUserId: 7,
      senderAvatarPreset: 'blue',
      senderAvatarObjectKey: 'avatars/7.png',
      senderAvatarUrl: 'https://example.test/avatars/7.png',
      bodyText: '测试消息',
      kind: 'TEXT',
    );

    expect(hit.senderUserId, 7);
    expect(hit.senderAvatarPreset, 'blue');
    expect(hit.senderAvatarObjectKey, 'avatars/7.png');
    expect(hit.senderAvatarUrl, 'https://example.test/avatars/7.png');
  });
}
