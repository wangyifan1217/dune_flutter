import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/nova/native_nova_service.dart';
import 'package:dunes_app/features/nova/nova_stream_parser.dart';

void main() {
  group('im-svc SSE 回传服务端消息 ID', () {
    test('user_message 带回提问的服务端 ID', () {
      final event = parseNovaOpenAiSseJson(<String, dynamic>{
        'event': 'user_message',
        'data': <String, dynamic>{'conversationId': 512, 'messageId': 88},
      });
      expect(event?.conversationId, 512);
      expect(event?.userMessageId, 88);
      expect(event?.text, isEmpty);
    });

    test('done 带回回复 ID 与最终正文，但不追加正文', () {
      final event = parseNovaOpenAiSseJson(<String, dynamic>{
        'event': 'done',
        'data': <String, dynamic>{
          'conversationId': 512,
          'messageId': 89,
          'text': '完整回复',
        },
      });
      expect(event?.assistantMessageId, 89);
      expect(event?.finalText, '完整回复');
      expect(event?.text, isEmpty);
      expect(event?.think, isEmpty);
    });

    test('被停止的 done（无 messageId）不产生事件', () {
      final event = parseNovaOpenAiSseJson(<String, dynamic>{
        'event': 'done',
        'data': <String, dynamic>{'conversationId': 512, 'stopped': true},
      });
      expect(event, isNull);
    });
  });

  group('remapNovaTurnMessageIds', () {
    final sentAt = DateTime(2026, 10, 26, 10);
    final localUserId = sentAt.millisecondsSinceEpoch;
    final localUser = NativeNovaMessage(
      id: localUserId,
      role: 'user',
      text: '帮我写一份周报',
      createdAt: sentAt,
    );
    final localReply = NativeNovaMessage(
      id: localUserId + 1,
      role: 'assistant',
      text: '本周完成了以下工作：\n\n1. 小饕优化',
      createdAt: sentAt.add(const Duration(milliseconds: 1)),
      thinkText: '先梳理本周事项',
    );

    test('没有服务端 ID 时原样返回', () {
      final rows = [localUser, localReply];
      expect(identical(remapNovaTurnMessageIds(rows), rows), isTrue);
    });

    test('本地临时 ID 换成服务端 ID', () {
      final out = remapNovaTurnMessageIds(
        [localUser, localReply],
        localUserId: localUserId,
        serverUserId: 88,
        localAssistantId: localUserId + 1,
        serverAssistantId: 89,
      );
      expect(out.map((m) => m.id), [88, 89]);
      expect(out.last.thinkText, '先梳理本周事项');
    });

    test('已有服务端同 ID 副本时合成一条', () {
      final serverUser = NativeNovaMessage(
        id: 88,
        role: 'user',
        text: '帮我写一份周报',
        createdAt: sentAt.add(const Duration(seconds: 2)),
      );
      final out = remapNovaTurnMessageIds(
        [serverUser, localUser, localReply],
        localUserId: localUserId,
        serverUserId: 88,
        localAssistantId: localUserId + 1,
        serverAssistantId: 89,
      );
      expect(out.where((m) => m.role == 'user').length, 1);
      expect(out.where((m) => m.role == 'assistant').length, 1);
    });

    test('生成超过 3 分钟、正文规范化有差异时，对齐后合并为一轮', () {
      // 服务端回复在完成时落库（比本地占位晚 5 分钟），正文首行多了空行规范化差异。
      final serverRows = [
        NativeNovaMessage(
          id: 88,
          role: 'user',
          text: '帮我写一份周报',
          createdAt: sentAt.add(const Duration(seconds: 1)),
        ),
        NativeNovaMessage(
          id: 89,
          role: 'assistant',
          text: '本周完成了以下工作：\n1. 小饕优化',
          createdAt: sentAt.add(const Duration(minutes: 5)),
        ),
      ];
      final local = [localUser, localReply];

      // 改造前：本地临时副本与服务端副本无法合并，会出现两轮。
      final before = mergeNovaHistoryCopies(serverRows, local);
      expect(before.where((m) => m.role == 'assistant').length, 2);

      final aligned = remapNovaTurnMessageIds(
        local,
        localUserId: localUserId,
        serverUserId: 88,
        localAssistantId: localUserId + 1,
        serverAssistantId: 89,
      );
      final after = mergeNovaHistoryCopies(serverRows, aligned);
      expect(after.where((m) => m.role == 'user').length, 1);
      expect(after.where((m) => m.role == 'assistant').length, 1);
    });
  });
}
