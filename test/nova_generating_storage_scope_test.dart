import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/nova/nova_generating_storage.dart';

void main() {
  test('readNovaGeneratingFromStorage only reads target conversation', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final storage = <String, String>{
      'dunes_nova_conv_id': '99',
      novaGeneratingStorageKey(12):
          '{"at":$now,"status":"思考中","after":3}',
      novaGeneratingStorageKey(99):
          '{"at":$now,"status":"别的会话","after":4}',
    };

    final state = readNovaGeneratingFromStorage(storage, convId: 12);
    expect(state?.conversationId, 12);
    expect(state?.status, '思考中');
  });
}
