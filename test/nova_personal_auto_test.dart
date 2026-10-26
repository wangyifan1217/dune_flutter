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

http.Response _json(Object data, {int status = 200}) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('未选定板块：一次请求完成路由和查询，不再单独请求 route', () async {
    final paths = <String>[];
    Map<String, dynamic>? personalBody;
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/ai/assistant/personal')) {
        personalBody = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({
          'success': true,
          'data': {'text': '中石化核销率低于中石油', 'capability': 'lighthouse'},
        });
      }
      return _json({'success': false}, status: 404);
    });
    final service = NativeNovaService(session: _session, client: client);
    final reply = await service.askPersonalAuto(
      text: '中石化核销率为什么低于中石油',
      afterLighthouse: true,
    );
    expect(personalBody?['capability'], 'auto');
    expect(personalBody?['afterLighthouse'], isTrue);
    expect(paths.where((p) => p.endsWith('/ai/assistant/route')), isEmpty);
    expect(reply.capability, NovaPersonalCapability.lighthouse);
    expect(reply.text, '中石化核销率低于中石油');
  });

  test('服务端判断为普通对话时返回改道标记', () async {
    final client = MockClient(
      (_) async => _json({
        'success': true,
        'data': {'route': 'chat'},
      }),
    );
    final service = NativeNovaService(session: _session, client: client);
    final reply = await service.askPersonalAuto(text: '帮我写一封邮件');
    expect(reply.routeToChat, isTrue);
  });

  test('旧版服务端不认识 auto：退回先路由、再查询', () async {
    final capabilities = <String>[];
    final client = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/ai/assistant/personal')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final capability = '${body['capability']}';
        capabilities.add(capability);
        if (capability == 'auto') {
          return _json({
            'success': false,
            'message': 'capability 只能是 tasks 或 lighthouse',
          }, status: 400);
        }
        return _json({
          'success': true,
          'data': {'text': '本月利润 12.0万', 'capability': 'lighthouse'},
        });
      }
      if (path.endsWith('/ai/assistant/route')) {
        return _json({
          'success': true,
          'data': {'capability': 'lighthouse'},
        });
      }
      return _json({'success': false}, status: 404);
    });
    final service = NativeNovaService(session: _session, client: client);
    final reply = await service.askPersonalAuto(text: '本月利润怎么样');
    expect(capabilities, ['auto', 'lighthouse']);
    expect(reply.text, '本月利润 12.0万');
  });
}
