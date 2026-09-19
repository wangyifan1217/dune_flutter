import 'package:dunes_app/features/nova/native_nova_service.dart';
import 'package:dunes_app/features/nova/nova_affinity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty history stays at intimacy 1', () {
    final snapshot = computeNovaAffinity(const []);
    expect(snapshot.level, 1);
    expect(snapshot.conversationCount, 0);
    expect(snapshot.intoLevel, 0);
    expect(snapshot.progress, 0);
    expect(snapshot.skills.where((s) => s.unlocked), isEmpty);
  });

  test('unique conversations drive level and Dune skills', () {
    final snapshot = computeNovaAffinity(const [
      NovaHistoryTurn(
        conversationId: 1,
        messageId: 1,
        title: '帮我在知识库里找相关资料',
        preview: '知识库里有 3 份制度文档',
      ),
      NovaHistoryTurn(
        conversationId: 1,
        messageId: 2,
        title: '同一段对话',
        preview: '补充',
      ),
      NovaHistoryTurn(
        conversationId: 2,
        messageId: 3,
        title: '总结一下知识库里最近的文档',
        preview: '提炼了关键要点',
      ),
      NovaHistoryTurn(
        conversationId: 3,
        messageId: 4,
        title: '根据会议纪要列出要点',
        preview: '会议待办',
      ),
    ]);
    expect(snapshot.conversationCount, 3);
    expect(snapshot.level, 1);
    expect(snapshot.intoLevel, 3);
    expect(snapshot.skills.firstWhere((s) => s.id == 'chat').unlocked, isTrue);
    expect(snapshot.skills.firstWhere((s) => s.id == 'kb').unlocked, isTrue);
    expect(
      snapshot.skills.firstWhere((s) => s.id == 'summary').unlocked,
      isTrue,
    );
    expect(
      snapshot.skills.firstWhere((s) => s.id == 'meeting').unlocked,
      isTrue,
    );
  });

  test('five conversations reach level 2', () {
    final turns = List<NovaHistoryTurn>.generate(
      5,
      (i) => NovaHistoryTurn(
        conversationId: i + 1,
        messageId: i + 1,
        title: '你好',
        preview: '小饕',
      ),
    );
    final snapshot = computeNovaAffinity(turns);
    expect(snapshot.level, 2);
    expect(snapshot.intoLevel, 0);
    expect(snapshot.progress, 0);
  });
}
