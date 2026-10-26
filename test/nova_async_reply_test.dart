import 'dart:async';
import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/nova/native_nova_service.dart';
import 'package:dunes_app/features/nova/nova_background_coordinator.dart';
import 'package:dunes_app/features/nova/nova_generating_storage.dart';
import 'package:dunes_app/features/nova/nova_web_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _session = AuthSession(
  phone: '',
  userId: 81,
  token: 't1',
  apiBase: 'https://example.invalid',
  roles: [],
);

const _refreshed = AuthSession(
  phone: '',
  userId: 81,
  token: 't2',
  apiBase: 'https://example.invalid',
  roles: [],
);

const _otherUser = AuthSession(
  phone: '',
  userId: 82,
  token: 't3',
  apiBase: 'https://example.invalid',
  roles: [],
);

http.StreamedResponse _bytes(String body, {String type = 'application/json'}) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': type},
    );

void main() {
  test('登录 token 刷新时沿用同一个 service，不打断进行中的回复', () {
    final service = NativeNovaService(session: _session);
    final coordinator = NovaBackgroundCoordinator.forTesting(_session, service);
    expect(identical(coordinator.serviceFor(_refreshed), service), isTrue);
    expect(service.session.token, 't2');
    expect(service.userStoppedStream, isFalse);
    expect(identical(coordinator.serviceFor(_otherUser), service), isFalse);
  });

  test('updateSession 只接受同一用户、同一服务地址', () {
    final service = NativeNovaService(session: _session);
    expect(service.updateSession(_otherUser), isFalse);
    expect(service.session.userId, 81);
    expect(service.updateSession(_refreshed), isTrue);
    expect(service.session.token, 't2');
  });

  test('页面切走后在后台发出普通对话，并且从一开始就算作进行中', () async {
    SharedPreferences.setMockInitialValues({});
    final release = Completer<void>();
    final client = MockClient.streaming((request, _) async {
      if (request.url.path.endsWith('/me/nova-credentials')) {
        return _bytes(
          jsonEncode({
            'data': {'ready': true, 'apiKey': 'k'},
          }),
        );
      }
      if (request.url.path.endsWith('/ai/assistant/messages')) {
        await release.future;
        return _bytes(
          'data: {"event":"user_message","data":{"conversationId":5,"messageId":900}}\n\n'
          'data: {"event":"delta","data":{"text":"邮件草稿"}}\n\n'
          'data: {"event":"done","data":{"conversationId":5,"messageId":901,"text":"邮件草稿"}}\n\n',
          type: 'text/event-stream',
        );
      }
      return _bytes('{}');
    });
    // 流式请求内部会新建 http.Client()，用 runWithClient 让它也走模拟客户端。
    await http.runWithClient(() async {
      final service = NativeNovaService(session: _session, client: client);

      final sending = service.sendChatInBackground(
        conversationId: 5,
        text: '帮我写封邮件',
        userMessageId: 1700000000000,
      );
      // 发出前就登记：页面在这段空档里回来，也不会误判回复已结束。
      expect(service.isReplyInFlightFor(5), isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      final pending = await NovaWebStorage.load(81);
      expect(pending[novaGeneratingStorageKey(5)], isNotNull);
      expect(pending[novaStreamDraftStorageKey(5)], isNotNull);

      release.complete();
      await sending;
      expect(service.isReplyInFlightFor(5), isFalse);
      final done = await NovaWebStorage.load(81);
      expect(done[novaGeneratingStorageKey(5)], isNull);
      expect(done[novaStreamDraftStorageKey(5)], isNull);
    }, () => client);
  });
}
