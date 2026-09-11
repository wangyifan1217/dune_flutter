import 'package:dunes_app/features/chat/assistant_transcript_support.dart';
import 'package:dunes_app/features/conversation/conversation_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NativeChatMessage _msg(int id, {String body = ''}) {
  return NativeChatMessage(
    id: id,
    senderUserId: 0,
    senderName: '任务助手',
    kind: 'TEXT',
    bodyText: body.isEmpty ? 'm$id' : body,
    createdAt: DateTime.fromMillisecondsSinceEpoch(id * 1000),
  );
}

void main() {
  test('assistantTranscriptUnchanged ignores identical streams', () {
    final a = [_msg(1), _msg(2)];
    expect(assistantTranscriptUnchanged(a, a), isTrue);
    expect(assistantTranscriptUnchanged(a, [_msg(1), _msg(2)]), isTrue);
  });

  test('assistantTranscriptUnchanged detects new or edited notices', () {
    expect(assistantTranscriptUnchanged([_msg(1)], [_msg(1), _msg(2)]), isFalse);
    expect(
      assistantTranscriptUnchanged([_msg(1, body: 'a')], [_msg(1, body: 'b')]),
      isFalse,
    );
  });

  testWidgets('reverse list treats pixels=0 as latest', (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 400,
          child: ListView.builder(
            controller: controller,
            reverse: true,
            itemCount: 12,
            itemBuilder: (_, i) => SizedBox(height: 120, child: Text('i$i')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, closeTo(0, 1));
    expect(
      assistantIsAwayFromLatest(controller.position, reverse: true),
      isFalse,
    );

    controller.jumpTo(80);
    await tester.pump();
    expect(
      assistantIsAwayFromLatest(controller.position, reverse: true),
      isTrue,
    );
    expect(
      assistantShouldLoadOlder(
        hasMore: true,
        loadingOlder: false,
        pos: controller.position,
        reverse: true,
      ),
      isFalse,
    );

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(
      assistantShouldLoadOlder(
        hasMore: true,
        loadingOlder: false,
        pos: controller.position,
        reverse: true,
      ),
      isTrue,
    );
  });
}
