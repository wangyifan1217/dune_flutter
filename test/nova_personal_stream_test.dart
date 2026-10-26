import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/nova/native_nova_service.dart';
import 'package:dunes_app/features/nova/nova_personal_query.dart';

const _session = AuthSession(
  token: 't',
  userId: 1,
  phone: '13800000000',
  apiBase: 'https://test.dune.com',
  roles: ['USER'],
);

void main() {
  test(
    'personal query reports SSE progress and returns the final reply',
    () async {
      final client = MockClient.streaming((request, _) async {
        expect(request.headers['Accept'], contains('text/event-stream'));
        final events = [
          'data: {"type":"progress","text":"正在读取灯塔：指标汇总"}\n\n',
          ': ping\n\n',
          'data: {"type":"progress","text":"正在分析数据"}\n\n',
          'data: {"type":"done","data":{"text":"本月利润 12.0万","capability":"lighthouse","state":{"tool":"lighthouse_analyze"},"suggestions":["本月中石化为什么下降"," ",""]}}\n\n',
        ];
        return http.StreamedResponse(
          Stream.fromIterable(events.map(utf8.encode)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final service = NativeNovaService(session: _session, client: client);
      final progress = <String>[];
      final reply = await service.askPersonalCapability(
        capability: 'lighthouse',
        text: '本月利润为什么下降',
        onProgress: progress.add,
      );
      expect(progress, ['正在读取灯塔：指标汇总', '正在分析数据']);
      expect(reply.text, '本月利润 12.0万');
      expect(reply.capability, NovaPersonalCapability.lighthouse);
      expect(reply.state?['tool'], 'lighthouse_analyze');
    expect(reply.suggestions, ['本月中石化为什么下降']);
    },
  );

  test('personal query still accepts a plain JSON reply', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'success': true,
          'data': {'route': 'chat'},
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final service = NativeNovaService(session: _session, client: client);
    final reply = await service.askPersonalCapability(
      capability: 'lighthouse',
      text: '写首诗',
    );
    expect(reply.routeToChat, isTrue);
  });

  test('personal query surfaces a streamed error', () async {
    final client = MockClient.streaming(
      (_, _) async => http.StreamedResponse(
        Stream.value(
          utf8.encode('data: {"type":"error","message":"小饕这次没有完成查询"}\n\n'),
        ),
        200,
        headers: {'content-type': 'text/event-stream'},
      ),
    );
    final service = NativeNovaService(session: _session, client: client);
    expect(
      service.askPersonalCapability(capability: 'lighthouse', text: '本月利润'),
      throwsA(isA<Exception>()),
    );
  });
}
