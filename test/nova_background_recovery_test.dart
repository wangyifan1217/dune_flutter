import 'dart:async';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/nova/native_nova_service.dart';
import 'package:dunes_app/features/nova/nova_background_coordinator.dart';
import 'package:dunes_app/features/nova/nova_generating_storage.dart';
import 'package:dunes_app/features/nova/nova_web_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _HistoryService extends NativeNovaService {
  _HistoryService(AuthSession session) : super(session: session);
  final result = Completer<NovaHistoryLoadResult>();
  int calls = 0;

  @override
  Future<NovaHistoryLoadResult> fetchFullHistory(
    int conversationId, {
    int? aroundMessageId,
    bool restoreFromHistory = false,
    bool applyViewSinceFilter = true,
  }) {
    calls++;
    return result.future;
  }
}

void main() {
  const session = AuthSession(
    phone: '',
    userId: 77,
    token: 't',
    apiBase: 'https://example.invalid',
    roles: [],
  );

  test('viewing one conversation does not clear another unread completion', () {
    final coordinator = NovaBackgroundCoordinator.forTesting(
      session,
      _HistoryService(session),
    );
    coordinator.setNovaPageActive(true, conversationId: 3);
    coordinator.markPendingCommBadgeBump(conversationId: 4);
    coordinator.markReplySeen(3);
    expect(coordinator.hasUnreadReplyFor(4), isTrue);
    coordinator.markPendingCommBadgeBump(conversationId: 3);
    expect(coordinator.hasUnreadReplyFor(3), isFalse);
    coordinator.markReplySeen(4);
    expect(coordinator.hasUnreadReply, isFalse);
    coordinator.dispose();
  });

  testWidgets(
    'stopping one conversation leaves other background polls active',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final service = _HistoryService(session);
      final coordinator = NovaBackgroundCoordinator.forTesting(
        session,
        service,
      );
      coordinator.ensurePoll(session, conversationId: 3);
      coordinator.ensurePoll(session, conversationId: 4);
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      expect(service.calls, 2);
      coordinator.stopPoll(conversationId: 3);
      expect(coordinator.isThinking, isTrue);
      service.result.complete(
        const NovaHistoryLoadResult(messages: [], assistantGenerating: true),
      );
      await tester.pump();
      coordinator.stopPoll(conversationId: 4);
      expect(coordinator.isThinking, isFalse);
      coordinator.dispose();
    },
  );

  for (final state in ['generating', 'interrupted', 'offline']) {
    testWidgets('background $state preserves drafts until state is confirmed', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final service = _HistoryService(session);
      final coordinator = NovaBackgroundCoordinator.forTesting(
        session,
        service,
      );
      await persistNovaGeneratingState(
        userId: 77,
        conversationId: 3,
        status: '生成中',
        afterMessageId: 100,
      );
      await persistNovaStreamDraftState(
        userId: 77,
        conversationId: 3,
        status: '生成中',
        afterMessageId: 100,
        userText: '问题',
        text: '部分回复',
      );
      coordinator.ensurePoll(session, conversationId: 3);
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));
      expect(
        service.calls,
        1,
        reason: 'slow history requests must not overlap',
      );
      var storage = await NovaWebStorage.load(77);
      expect(storage[novaGeneratingStorageKey(3)], isNotNull);
      expect(storage[novaStreamDraftStorageKey(3)], isNotNull);
      service.result.complete(
        NovaHistoryLoadResult(
          messages: const [],
          assistantGenerating: state == 'generating',
          serverStateKnown: state != 'offline',
        ),
      );
      await tester.pump();
      await tester.pump();
      storage = await NovaWebStorage.load(77);
      expect(storage[novaStreamDraftStorageKey(3)], isNotNull);
      expect(
        storage[novaGeneratingStorageKey(3)],
        state == 'interrupted' ? isNull : isNotNull,
      );
      expect(coordinator.isThinking, state != 'interrupted');
      coordinator.stopPoll();
      coordinator.dispose();
    });
  }
}
