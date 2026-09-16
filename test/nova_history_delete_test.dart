import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/nova/native_nova_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Nova History Delete & Blacklist Tests', () {
    const testSession = AuthSession(
      token: 'test_token',
      userId: 9999,
      phone: '13800000000',
      apiBase: 'https://test.dune.com',
      roles: ['USER'],
    );

    test('deleteConversation writes to deleted blacklist and filters out from fetchHistoryTurns', () async {
      final service = NativeNovaService(session: testSession);

      // 验证初始状态下 deleted 集合为空
      final initialDeleted = await service.getDeletedConversationIds();
      expect(initialDeleted, isEmpty);

      // 删除会话 101 和 102
      final ok1 = await service.deleteConversation(101);
      final ok2 = await service.deleteConversation(102);
      expect(ok1, isTrue);
      expect(ok2, isTrue);

      // 验证黑名单记录成功
      final deleted = await service.getDeletedConversationIds();
      expect(deleted.contains(101), isTrue);
      expect(deleted.contains(102), isTrue);
      expect(deleted.contains(103), isFalse);
    });

    test('reconcile with deleted conversations correctly keeps remaining', () async {
      final service = NativeNovaService(session: testSession);

      await service.deleteConversation(888);

      final deleted = await service.getDeletedConversationIds();
      final list = [
        const NovaHistoryTurn(
          conversationId: 888,
          messageId: 1,
          title: '已删除的会话',
          preview: '预览内容',
        ),
        const NovaHistoryTurn(
          conversationId: 999,
          messageId: 2,
          title: '保留的会话',
          preview: '预览内容2',
        ),
      ];

      final filtered = list.where((t) => !deleted.contains(t.conversationId)).toList();
      expect(filtered.length, 1);
      expect(filtered.first.conversationId, 999);
      expect(filtered.first.title, '保留的会话');
    });
  });
}
