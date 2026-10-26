import 'dart:async';
import 'dart:convert';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/nova/native_nova_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dunes_app/features/nova/nova_web_storage.dart';

class _RecordingService extends NativeNovaService {
  _RecordingService({required super.session, required super.client});
  int? savedConversation;
  String? savedReply;
  Map<String, dynamic>? savedPayload;

  @override
  Future<void> persistAssistantTurn({
    required int conversationId,
    required int messageId,
    required String userMessage,
    required String assistantMessage,
    String thinkText = '',
    Map<String, dynamic>? userPayload,
    List<NativeNovaMessage> existingMessages = const [],
  }) async {
    savedConversation = conversationId;
    savedReply = assistantMessage;
    savedPayload = userPayload;
  }
}

void main() {
  const session = AuthSession(
    token: 'test',
    userId: 1,
    phone: '',
    apiBase: 'https://example.invalid',
    roles: [],
  );

  test(
    'personal query belongs to its conversation and saves without a page callback',
    () async {
      SharedPreferences.setMockInitialValues({});
      final started = Completer<void>();
      final events = StreamController<List<int>>();
      final service = _RecordingService(
        session: session,
        client: MockClient.streaming((_, _) async {
          started.complete();
          return http.StreamedResponse(
            events.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      final reply = service.askPersonalCapability(
        capability: 'lighthouse',
        text: '本月利润',
        conversationId: 11,
        userMessageId: 100,
        existingMessages: [
          NativeNovaMessage(
            id: 100,
            role: 'user',
            text: '本月利润',
            createdAt: null,
            payload: {'nova_personal_capability': 'lighthouse'},
          ),
        ],
      );
      await started.future;
      expect(service.isReplyInFlightFor(11), isTrue);
      expect(service.isReplyInFlightFor(12), isFalse);
      events.add(
        utf8.encode(
          'data: {"type":"done","data":{"text":"利润完成","state":{"period":"month"}}}\n\n',
        ),
      );
      await events.close();
      await reply;
      expect(service.isReplyInFlightFor(11), isFalse);
      expect(service.savedConversation, 11);
      expect(service.savedReply, '利润完成');
      expect(service.savedPayload?['nova_lighthouse_state'], {
        'period': 'month',
      });
      final storage = await NovaWebStorage.load(session.userId);
      expect(storage['dunes_nova_msgs_11'], contains('nova_lighthouse_state'));
    },
  );

  test(
    'stopping personal query releases busy state and ignores late progress',
    () async {
      final started = Completer<void>();
      final events = StreamController<List<int>>();
      var progress = 0;
      final service = NativeNovaService(
        session: session,
        client: MockClient.streaming((_, _) async {
          started.complete();
          return http.StreamedResponse(
            events.stream,
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      final reply = service.askPersonalCapability(
        capability: 'lighthouse',
        text: '本月利润',
        onProgress: (_) => progress++,
      );
      final checked = expectLater(reply, throwsException);
      await started.future;
      service.cancelActiveStream();
      await checked;
      expect(service.isPersonalQueryInFlight, isFalse);
      events.add(utf8.encode('data: {"type":"progress","text":"迟到的进度"}\n\n'));
      events.add(
        utf8.encode('data: {"type":"done","data":{"text":"迟到的结果"}}\n\n'),
      );
      await events.close();
      expect(progress, 0);
    },
  );

  for (final fail in [false, true]) {
    test(
      'personal query stays active through progress and clears on ${fail ? 'error' : 'completion'}',
      () async {
        final events = StreamController<List<int>>();
        final started = Completer<void>();
        final progressed = Completer<void>();
        final service = NativeNovaService(
          session: session,
          client: MockClient.streaming((_, _) async {
            started.complete();
            return http.StreamedResponse(
              events.stream,
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          }),
        );
        expect(service.isPersonalQueryInFlight, isFalse);
        final reply = service.askPersonalCapability(
          capability: 'lighthouse',
          text: '本月利润',
          onProgress: (_) => progressed.complete(),
        );
        final checked = fail
            ? expectLater(reply, throwsException)
            : expectLater(reply.then((value) => value.text), completion('完成'));
        await started.future;
        expect(service.isPersonalQueryInFlight, isTrue);
        events.add(
          utf8.encode('data: {"type":"progress","text":"正在分析数据"}\n\n'),
        );
        await progressed.future;
        expect(service.isPersonalQueryInFlight, isTrue);
        events.add(
          utf8.encode(
            fail
                ? 'data: {"type":"error","message":"查询失败"}\n\n'
                : 'data: {"type":"done","data":{"text":"完成"}}\n\n',
          ),
        );
        await events.close();
        await checked;
        expect(service.isPersonalQueryInFlight, isFalse);
      },
    );
  }
}
