import 'package:dunes_app/features/nova/native_nova_service.dart';
import 'package:dunes_app/features/nova/nova_generating_storage.dart';
import 'package:dunes_app/features/nova/nova_web_storage.dart';
import 'package:dunes_app/features/nova/nova_personal_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('pending task preview can be restored without executing a write', () {
    final preview = novaTaskPreviewFromPayload({
      'kind': 'progress',
      'summary': '进度改为40',
      'taskId': 9,
      'body': {'progressPct': 40},
    });
    expect(preview?.taskId, 9);
    expect(preview?.body['progressPct'], 40);
    expect(novaTaskPreviewFromPayload({'kind': 'unknown', 'body': {}}), isNull);
  });
  final now = DateTime.now().millisecondsSinceEpoch;
  NovaGeneratingState marker({String status = '正在生成'}) => NovaGeneratingState(
    at: now,
    status: status,
    afterMessageId: now,
    conversationId: 3,
  );
  NovaStreamDraft draft({bool streaming = true, String text = '部分正文'}) =>
      NovaStreamDraft(
        at: now,
        status: '正在生成',
        afterMessageId: now,
        userText: '当前问题',
        thinkText: '思考内容',
        text: text,
        streaming: streaming,
      );

  test(
    'server generation survives stale local marker after process restart',
    () {
      final state = resolveNovaGeneratingState(
        serverGenerating: true,
        streamInFlight: false,
        localGen: marker(),
        draft: draft(),
      );
      expect(state.generating, isTrue);
      expect(state.clearLocal, isFalse);
    },
  );

  test('a disconnected draft alone never resumes an endless spinner', () {
    final state = resolveNovaGeneratingState(
      serverGenerating: false,
      streamInFlight: false,
      localGen: marker(),
      draft: draft(),
    );
    expect(state.generating, isFalse);
    expect(state.clearLocal, isTrue);
  });

  test('live stream wins over a delayed historical reply', () {
    expect(
      resolveNovaGeneratingState(
        serverGenerating: false,
        streamInFlight: true,
        hasAiReplyAfter: true,
      ).generating,
      isTrue,
    );
    expect(
      resolveNovaGeneratingState(
        serverGenerating: true,
        streamInFlight: false,
        hasAiReplyAfter: true,
      ).generating,
      isFalse,
    );
  });

  test('stopped reply is not restarted by the remote generating flag', () {
    expect(
      resolveNovaGeneratingState(
        serverGenerating: true,
        streamInFlight: false,
        localGen: marker(status: '已停止生成'),
      ).generating,
      isFalse,
    );
  });

  test('partial draft is visibly interrupted, retryable, and deduplicated', () {
    final rows = [
      NativeNovaMessage(id: now, role: 'user', text: '当前问题', createdAt: null),
    ];
    final recovered = recoverNovaInterruptedDraft(
      rows,
      draft: draft(),
      afterMessageId: now,
    );
    expect(recovered.last.text, '部分正文');
    expect(recovered.last.streaming, isFalse);
    expect(recovered.last.thinkStatus, '回复已中断');
    expect(recovered.last.payload?['nova_retryable'], isTrue);
    final again = recoverNovaInterruptedDraft(
      recovered,
      draft: draft(),
      afterMessageId: now,
    );
    expect(again.length, 2);
  });

  test('draft waiting for first token offers retry after disconnection', () {
    final recovered = recoverNovaInterruptedDraft(
      [],
      draft: draft(text: ''),
      afterMessageId: now,
    );
    expect(recovered.single.streaming, isFalse);
    expect(recovered.single.text, contains('重试'));
  });

  test(
    'canonical IDs replace temporary IDs without duplicate interrupted reply',
    () {
      final rows = [
        NativeNovaMessage(
          id: 42,
          role: 'user',
          text: '当前问题',
          createdAt: DateTime.fromMillisecondsSinceEpoch(now),
        ),
        NativeNovaMessage(
          id: 43,
          role: 'assistant',
          text: '完整正文',
          createdAt: null,
        ),
      ];
      expect(
        novaHasReplyForDraft(rows, afterMessageId: now, draft: draft()),
        isTrue,
      );
      expect(
        recoverNovaInterruptedDraft(
          rows,
          draft: draft(),
          afterMessageId: now,
        ).length,
        2,
      );
    },
  );

  test(
    'an older answer does not count as completion of the latest question',
    () {
      final rows = [
        NativeNovaMessage(id: 1, role: 'user', text: '以前的问题', createdAt: null),
        NativeNovaMessage(
          id: 2,
          role: 'assistant',
          text: '以前的回复',
          createdAt: null,
        ),
        NativeNovaMessage(id: now, role: 'user', text: '当前问题', createdAt: null),
      ];
      expect(
        novaHasReplyForDraft(rows, afterMessageId: now, draft: draft()),
        isFalse,
      );
    },
  );

  test(
    'concurrent draft, generation and history writes preserve every key',
    () async {
      SharedPreferences.setMockInitialValues({});
      await Future.wait([
        persistNovaGeneratingState(
          userId: 7,
          conversationId: 3,
          status: '正在生成',
        ),
        persistNovaStreamDraftState(
          userId: 7,
          conversationId: 3,
          status: '生成中',
          text: '正文',
        ),
        NovaWebStorage.merge(7, {'dunes_nova_msgs_3': '[历史]'}),
      ]);
      final storage = await NovaWebStorage.load(7);
      expect(storage[novaGeneratingStorageKey(3)], isNotNull);
      expect(storage[novaStreamDraftStorageKey(3)], isNotNull);
      expect(storage['dunes_nova_msgs_3'], '[历史]');
    },
  );

  test('clearing markers does not erase simultaneous history writes', () async {
    SharedPreferences.setMockInitialValues({});
    await persistNovaGeneratingState(
      userId: 8,
      conversationId: 3,
      status: '生成中',
    );
    await Future.wait([
      clearNovaGeneratingState(userId: 8, conversationId: 3),
      NovaWebStorage.merge(8, {'dunes_nova_msgs_3': '[最终回复]'}),
    ]);
    final storage = await NovaWebStorage.load(8);
    expect(storage[novaGeneratingStorageKey(3)], isNull);
    expect(storage['dunes_nova_msgs_3'], '[最终回复]');
  });

  test(
    'removing the last storage key really persists an empty state',
    () async {
      SharedPreferences.setMockInitialValues({});
      await NovaWebStorage.merge(9, {'dunes_nova_conv_id': '3'});
      await NovaWebStorage.removeKeys(9, ['dunes_nova_conv_id']);
      expect(await NovaWebStorage.load(9), isEmpty);
    },
  );
}
