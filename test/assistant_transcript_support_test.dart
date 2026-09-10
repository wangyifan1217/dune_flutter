import 'package:dunes_app/features/chat/assistant_transcript_support.dart';
import 'package:dunes_app/features/conversation/conversation_models.dart';
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
}
