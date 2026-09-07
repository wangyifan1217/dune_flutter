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

  ConversationService service() => ConversationService(
    session: session(),
    client: MockClient((_) async => http.Response('{}', 200)),
  );

  test('发送体 data 即消息时能解析出 id', () {
    final svc = service();
    final msg = svc.tryMapSentMessage(<String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'id': 88,
        'kind': 'TEXT',
        'bodyText': '你好',
        'senderUserId': 1,
      },
    });
    expect(msg, isNotNull);
    expect(msg!.id, 88);
    expect(msg.bodyText, '你好');
    svc.close();
  });

  test('发送体 data.message 嵌套时也能解析', () {
    final svc = service();
    final msg = svc.tryMapSentMessage(<String, dynamic>{
      'success': true,
      'data': <String, dynamic>{
        'message': <String, dynamic>{
          'id': 91,
          'kind': 'TEXT',
          'bodyText': '嵌套',
        },
      },
    });
    expect(msg, isNotNull);
    expect(msg!.id, 91);
    svc.close();
  });

  test('解不出消息时返回 null，不抛错', () {
    final svc = service();
    expect(svc.tryMapSentMessage(<String, dynamic>{'success': true}), isNull);
    expect(
      svc.tryMapSentMessage(<String, dynamic>{
        'success': true,
        'data': <String, dynamic>{'ok': true},
      }),
      isNull,
    );
    expect(
      svc.tryMapSentMessage(<String, dynamic>{'success': false, 'data': <String, dynamic>{'id': 1}}),
      isNull,
    );
    svc.close();
  });
}
