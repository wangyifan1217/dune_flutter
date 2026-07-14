import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/nova/nova_stream_parser.dart';

void main() {
  test('parses canonical conversation id from im-svc user_message', () {
    final event = parseNovaOpenAiSseJson(<String, dynamic>{
      'event': 'user_message',
      'data': <String, dynamic>{'conversationId': 512, 'messageId': 88},
    });

    expect(event?.conversationId, 512);
  });
}
