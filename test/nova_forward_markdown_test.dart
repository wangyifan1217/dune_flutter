import 'package:dunes_app/features/nova/nova_deliverable.dart';
import 'package:dunes_app/features/robots/robot_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('novaTextHasMarkdown', () {
    test('纯文字回复按普通消息转发', () {
      for (final text in [
        '奕凡，晚上好！😊有什么我可以帮你的吗？',
        '本月营收 3070.80 元，环比 -5%。',
        '价格是 3*4=12，2024-10-26 完成',
      ]) {
        expect(novaTextHasMarkdown(text), isFalse, reason: text);
      }
    });

    test('带排版的回复仍按富文本卡片转发', () {
      for (final text in [
        '## 周报\n本周完成',
        '本周完成：\n1. 小饕优化\n2. IM 修复',
        '- 第一项\n- 第二项',
        '这是 **重点** 内容',
        '| 指标 | 值 |\n|---|---|\n| 营收 | 1 |',
        '运行 `flutter analyze`',
        '详见 [文档](https://example.com/a)',
      ]) {
        expect(novaTextHasMarkdown(text), isTrue, reason: text);
      }
    });
  });

  testWidgets('fitToContent 时短内容不撑满最大宽度', (tester) async {
    const key = Key('bubble');
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              key: key,
              constraints: BoxConstraints(maxWidth: 400),
              child: RobotMarkdown(
                markdown: '你好',
                selectable: false,
                fitToContent: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byKey(key)).width, lessThan(200));
    expect(tester.takeException(), isNull);
  });
}
