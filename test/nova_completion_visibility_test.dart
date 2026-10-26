import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/nova/native_nova_service.dart';
import 'package:dunes_app/features/nova/nova_background_coordinator.dart';
import 'package:dunes_app/features/nova/nova_generating_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dunes_app/features/nova/nova_web_storage.dart';

const _session = AuthSession(
  phone: '',
  userId: 88,
  token: 't',
  apiBase: 'https://example.invalid',
  roles: [],
);

class _SavedReplyService extends NativeNovaService {
  _SavedReplyService({this.dropWrites = false}) : super(session: _session);
  final bool dropWrites;
  @override
  Future<void> persistSession(
    int conversationId,
    List<NativeNovaMessage> messages,
  ) async {
    if (!dropWrites) await super.persistSession(conversationId, messages);
  }

  @override
  Future<void> flushConvToLocalHistory(
    int conversationId,
    List<NativeNovaMessage> messages,
  ) async {}
  @override
  Future<void> flushHistorySyncQueue() async {}
}

void main() {
  for (final emptyDestination in [true, false]) {
    test(
      'canonical ID adoption keeps completed reply when destination ${emptyDestination ? 'is empty' : 'has older content'}',
      () async {
        SharedPreferences.setMockInitialValues({});
        final service = _SavedReplyService();
        await service.persistSession(3, [
          const NativeNovaMessage(
            id: 100,
            role: 'user',
            text: '新问题',
            createdAt: null,
          ),
          const NativeNovaMessage(
            id: 101,
            role: 'assistant',
            text: '已完成的完整回复',
            createdAt: null,
          ),
        ]);
        if (emptyDestination) {
          await NovaWebStorage.merge(88, {'dunes_nova_msgs_9': '[]'});
        } else {
          await service.persistSession(9, [
            const NativeNovaMessage(
              id: 10,
              role: 'user',
              text: '旧问题',
              createdAt: null,
            ),
            const NativeNovaMessage(
              id: 11,
              role: 'assistant',
              text: '旧答案',
              createdAt: null,
            ),
          ]);
        }
        await service.remapConversationId(3, 9);
        final restored = await service.loadPersistedConversation(9);
        expect(restored.any((m) => m.text == '已完成的完整回复'), isTrue);
        if (!emptyDestination)
          expect(restored.any((m) => m.text == '旧答案'), isTrue);
        expect(await service.ensureConversation(), 9);
        expect((await NovaWebStorage.load(88))['dunes_nova_msgs_3'], isNull);
      },
    );
  }
  List<NativeNovaMessage> rows({String? reply, bool streaming = false}) => [
    const NativeNovaMessage(
      id: 100,
      role: 'user',
      text: '这轮问题',
      createdAt: null,
    ),
    if (reply != null)
      NativeNovaMessage(
        id: 101,
        role: 'assistant',
        text: reply,
        createdAt: null,
        streaming: streaming,
      ),
  ];

  for (final scenario in [
    'empty',
    'user-only',
    'streaming',
    'dropped-save',
    'saved',
  ]) {
    test(
      'completion notification requires readable saved reply: $scenario',
      () async {
        SharedPreferences.setMockInitialValues({});
        final service = _SavedReplyService(
          dropWrites: scenario == 'dropped-save',
        );
        final coordinator = NovaBackgroundCoordinator.forTesting(
          _session,
          service,
        );
        final messages = scenario == 'empty'
            ? <NativeNovaMessage>[]
            : rows(
                reply: scenario == 'user-only' ? null : '完整回复',
                streaming: scenario == 'streaming',
              );
        await coordinator.onGenerationComplete(
          session: _session,
          conversationId: 3,
          messages: messages,
        );
        expect(coordinator.hasUnreadReplyFor(3), scenario == 'saved');
        if (scenario == 'saved') {
          final saved = await service.loadPersistedConversation(3);
          expect(saved.last.text, '完整回复');
          expect(coordinator.latestUnreadConversationId, 3);
        }
        coordinator.dispose();
      },
    );
  }

  test('partial draft is not announced as a finished reply', () async {
    SharedPreferences.setMockInitialValues({});
    await persistNovaStreamDraftState(
      userId: 88,
      conversationId: 3,
      status: '正在回复',
      afterMessageId: 100,
      userText: '这轮问题',
      text: '半截正文',
      streaming: true,
    );
    final coordinator = NovaBackgroundCoordinator.forTesting(
      _session,
      _SavedReplyService(),
    );
    await coordinator.onGenerationComplete(
      session: _session,
      conversationId: 3,
      messages: rows(),
    );
    expect(coordinator.hasUnreadReply, isFalse);
    coordinator.dispose();
  });

  test(
    'opening latest unread does not select an unrelated active conversation',
    () {
      final coordinator = NovaBackgroundCoordinator.forTesting(
        _session,
        _SavedReplyService(),
      );
      coordinator.markPendingCommBadgeBump(conversationId: 3);
      coordinator.markPendingCommBadgeBump(conversationId: 9);
      expect(coordinator.latestUnreadConversationId, 9);
      coordinator.markReplySeen(9);
      expect(coordinator.latestUnreadConversationId, 3);
      coordinator.dispose();
    },
  );
}
