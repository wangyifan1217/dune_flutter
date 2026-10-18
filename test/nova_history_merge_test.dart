import 'package:dunes_app/features/nova/native_nova_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime(2026, 10, 17, 0, 2);
  const question = '本月毛利前十的产品';
  final reply = '变凡，下周四北京整体晴好。${'气温适宜。' * 8}**10月22日** 适合出行，注意添衣。';

  test('long markdown reply stored as a user bubble is shown as assistant', () {
    final stolen = NativeNovaMessage(
      id: 1758000000001,
      role: 'user',
      text: reply,
      createdAt: at,
      thinkText: '已对照预报',
    );
    final fixed = sortNovaMessages([
      NativeNovaMessage(
        id: 42,
        role: 'user',
        text: question,
        createdAt: at.subtract(const Duration(seconds: 2)),
      ),
      stolen,
    ]);
    expect(fixed.map((m) => m.role).toList(), ['user', 'assistant']);
    expect(fixed.first.text, question);
    expect(fixed.last.text, reply);
  });

  test('short user questions stay on the right', () {
    final rows = sortNovaMessages([
      NativeNovaMessage(
        id: 7,
        role: 'user',
        text: question,
        createdAt: at,
      ),
    ]);
    expect(rows.single.role, 'user');
  });

  test('temp id and server id of the same question collapse to one', () {
    final temp = NativeNovaMessage(
      id: 1758000000000,
      role: 'user',
      text: question,
      createdAt: at,
    );
    final again = NativeNovaMessage(
      id: 1758000000002,
      role: 'user',
      text: question,
      createdAt: at.add(const Duration(seconds: 1)),
    );
    final server = NativeNovaMessage(
      id: 88,
      role: 'user',
      text: question,
      createdAt: at,
    );
    final merged = mergeNovaHistoryCopies([temp, again], [server]);
    expect(merged.where((m) => m.role == 'user'), hasLength(1));
    expect(merged.single.id, 88);
  });

  test('two server copies of the same question both stay', () {
    final first = NativeNovaMessage(
      id: 10,
      role: 'user',
      text: question,
      createdAt: at,
    );
    final second = NativeNovaMessage(
      id: 11,
      role: 'user',
      text: question,
      createdAt: at.add(const Duration(seconds: 3)),
    );
    final merged = mergeNovaHistoryCopies([first], [second]);
    expect(merged.map((m) => m.id).toList(), [10, 11]);
  });

  test('late lighthouse reply stays on its question, duplicate hello collapses', () {
    final t = DateTime(2026, 10, 17, 19, 59);
    const guide = '现在只查询灯塔。可以说「今天灯塔整体怎么样」，或「本月毛利前十的产品」。';
    const greeting = '你好，奕凡！有什么可以帮你的吗？';
    final fixed = sortNovaMessages([
      NativeNovaMessage(id: 500, role: 'user', text: '测试', createdAt: t),
      NativeNovaMessage(
        id: 1760700000000,
        role: 'user',
        text: '你好',
        createdAt: t.add(const Duration(seconds: 30)),
      ),
      NativeNovaMessage(
        id: 1760700000001,
        role: 'assistant',
        text: greeting,
        createdAt: t.add(const Duration(seconds: 32)),
      ),
      NativeNovaMessage(
        id: 510,
        role: 'user',
        text: '你好',
        createdAt: t.add(const Duration(seconds: 33)),
      ),
      NativeNovaMessage(
        id: 501,
        role: 'assistant',
        text: guide,
        createdAt: t.add(const Duration(seconds: 40)),
      ),
    ]);
    expect(fixed.map((m) => m.text).toList(), ['测试', guide, '你好', greeting]);
    expect(fixed[2].id, 510);
  });

  test('two server copies of hello both stay when each is its own turn', () {
    final t = DateTime(2026, 10, 17, 19, 59);
    final fixed = sortNovaMessages([
      NativeNovaMessage(id: 10, role: 'user', text: '你好', createdAt: t),
      NativeNovaMessage(
        id: 11,
        role: 'assistant',
        text: '你好，奕凡',
        createdAt: t.add(const Duration(seconds: 2)),
      ),
      NativeNovaMessage(
        id: 12,
        role: 'user',
        text: '你好',
        createdAt: t.add(const Duration(seconds: 20)),
      ),
    ]);
    expect(fixed.map((m) => m.role).toList(), ['user', 'assistant', 'user']);
    expect(fixed.where((m) => m.text == '你好').map((m) => m.id).toList(), [
      10,
      12,
    ]);
  });

  test('same id with different roles keeps the question and the reply', () {
    final user = NativeNovaMessage(
      id: 1758000000001,
      role: 'user',
      text: question,
      createdAt: at,
    );
    final assistant = NativeNovaMessage(
      id: 1758000000001,
      role: 'assistant',
      text: reply,
      createdAt: at.add(const Duration(seconds: 1)),
      thinkText: '已对照预报',
    );
    final merged = dedupeNovaHistoryMessages(
      mergeNovaHistoryCopies([user], [assistant]),
    );
    expect(merged.map((m) => m.role).toList(), ['user', 'assistant']);
    expect(merged.first.text, question);
    expect(merged.last.text, reply);
  });
}
