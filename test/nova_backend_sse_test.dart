import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/nova/nova_stream_parser.dart';

void main() {
  test('parses im-svc wrapped assistant deltas', () {
    final event = parseNovaOpenAiSseJson(<String, dynamic>{
      'event': 'delta',
      'data': <String, dynamic>{'text': '后端回复'},
    });

    expect(event?.text, '后端回复');
    expect(event?.error, isNull);
  });

  test('parses im-svc wrapped error', () {
    final event = parseNovaOpenAiSseJson(<String, dynamic>{
      'event': 'error',
      'data': <String, dynamic>{'message': '服务繁忙'},
    });

    expect(event?.error, '服务繁忙');
  });
}
