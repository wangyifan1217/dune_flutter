import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/conversation/conversation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  AuthSession session() => const AuthSession(
        phone: '13800000000',
        userId: 1,
        token: 'test',
        apiBase: 'http://127.0.0.1/api/v1',
        roles: <String>[],
      );

  Map<String, dynamic> okPayload(List<Map<String, dynamic>> rows) =>
      <String, dynamic>{
        'success': true,
        'data': rows,
      };

  Map<String, dynamic> conv({
    required int id,
    String title = '会话',
    Object? extraId,
  }) {
    return <String, dynamic>{
      'id': extraId ?? id,
      'kind': 'PRIVATE',
      'title': title,
      'unreadCount': 0,
      'preview': 'hello',
      'updatedAt': '2026-08-27T02:00:00.000Z',
      'peer': <String, dynamic>{
        'userId': 2,
        'displayName': title,
      },
    };
  }

  test('HTML 网关页会重试，第二次 JSON 成功则列出会话', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      if (calls == 1) {
        return http.Response(
          '<html><body>502 Bad Gateway</body></html>',
          200,
          headers: const {'content-type': 'text/html; charset=utf-8'},
        );
      }
      return http.Response(
        jsonEncode(okPayload([conv(id: 11, title: '李凡伊')])),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = ConversationService(session: session(), client: client);
    final rows = await service.fetchConversations();
    expect(calls, 2);
    expect(rows, hasLength(1));
    expect(rows.single.title, '李凡伊');
    service.close();
  });

  test('单条会话字段异常时跳过该行，不让整个列表解析失败', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(
          okPayload([
            conv(id: 11, title: '正常'),
            <String, dynamic>{
              'id': <String>['bad'],
              'kind': 'PRIVATE',
              'members': 'not-a-list',
            },
            conv(id: 12, title: '也正常'),
          ]),
        ),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = ConversationService(session: session(), client: client);
    final rows = await service.fetchConversations();
    expect(rows.map((c) => c.id), [11, 12]);
    service.close();
  });

  test('UTF-8 截断 JSON 两次都失败时给出中文解析错误', () async {
    final client = MockClient((request) async {
      return http.Response(
        '{"success":true,"data":[{"id":1,"title":"未闭合',
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = ConversationService(session: session(), client: client);
    expect(
      service.fetchConversations(),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('数据解析失败'),
        ),
      ),
    );
    service.close();
  });
}
