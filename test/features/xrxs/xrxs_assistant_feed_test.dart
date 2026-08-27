import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/conversation/conversation_models.dart';
import 'package:dunes_app/features/xrxs/native_xrxs_assistant_page.dart';

NativeChatMessage _msg(int id) {
  return NativeChatMessage(
    id: id,
    senderUserId: 0,
    senderName: '薪人薪事',
    kind: 'TEXT',
    bodyText: '$id',
    createdAt: DateTime.fromMillisecondsSinceEpoch(id * 1000),
  );
}

void main() {
  test('xrxsAssistantFeedMessages puts newest first', () {
    final feed = xrxsAssistantFeedMessages([_msg(1), _msg(2), _msg(3)]);
    expect(feed.map((m) => m.id), [3, 2, 1]);
  });

  test('xrxsAssistantFeedMessages keeps empty and single lists', () {
    expect(xrxsAssistantFeedMessages(const []), isEmpty);
    expect(xrxsAssistantFeedMessages([_msg(9)]).single.id, 9);
  });

  test('static preview is already newest-first', () {
    final preview = xrxsAssistantStaticPreviewMessages();
    expect(preview, isNotEmpty);
    for (var i = 1; i < preview.length; i++) {
      final newer = preview[i - 1].createdAt;
      final older = preview[i].createdAt;
      expect(newer, isNotNull);
      expect(older, isNotNull);
      expect(
        newer!.isAfter(older!) || newer.isAtSameMomentAs(older),
        isTrue,
      );
    }
  });
}
