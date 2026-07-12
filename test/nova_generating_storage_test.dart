import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/nova/nova_generating_storage.dart';

void main() {
  test('stale local generating state does not keep inbox thinking', () {
    expect(
      shouldPersistNovaGenerating(
        localGen: NovaGeneratingState(
          at: DateTime.now().millisecondsSinceEpoch,
          status: '思考中…',
          afterMessageId: 12,
          conversationId: 3,
        ),
        draft: const NovaStreamDraft(
          at: 1,
          status: '思考中…',
          afterMessageId: 12,
          userText: '问题',
          thinkText: '',
          text: '部分回复',
          streaming: true,
        ),
      ),
      isFalse,
    );
  });

  test('active SSE stream remains generating', () {
    expect(shouldPersistNovaGenerating(streamInFlight: true), isTrue);
  });
}
