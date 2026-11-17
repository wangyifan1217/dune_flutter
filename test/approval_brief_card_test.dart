import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'package:dunes_app/features/approval_assistant/approval_brief_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('简报显示完整数据并可打开列表 dark=$dark', (tester) async {
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? DunesTheme.dark() : DunesTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 240,
                  child: ApprovalBriefCard(
                    payload: const {
                      'pendingCount': 12,
                      'initiatedCount': 5,
                      'overdue24hCount': 3,
                      'overdue1wCount': 1,
                      'pendingTypeCounts': [
                        {'type': '电子报销及其他较长名称的审批类型', 'count': 9},
                        {'type': '采购', 'count': 3},
                      ],
                      'initiatedTypeCounts': [
                        {'name': '提案', 'count': 5},
                      ],
                    },
                    fallback: '',
                    onOpenAll: () => opened = true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('今日审批简报'), findsOneWidget);
      expect(find.text('超24小时 3'), findsOneWidget);
      expect(find.text('超1周 1'), findsOneWidget);
      expect(find.text('电子报销及其他较长名称的审批类型'), findsNothing);
      expect(find.text('展开明细'), findsOneWidget);
      await tester.tap(find.text('展开明细'));
      await tester.pump();
      expect(find.text('电子报销及其他较长名称的审批类型'), findsOneWidget);
      expect(find.text('提案'), findsOneWidget);
      await tester.ensureVisible(find.text('收起明细'));
      await tester.tap(find.text('收起明细'));
      await tester.pump();
      expect(find.text('提案'), findsNothing);
      await tester.ensureVisible(find.text('查看列表'));
      await tester.tap(find.text('查看列表'));
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('空数据保留服务端提示和入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ApprovalBriefCard(
            payload: const {},
            fallback: '暂无待审',
            onOpenAll: () {},
          ),
        ),
      ),
    );
    expect(find.text('暂无待审'), findsOneWidget);
    expect(find.text('查看列表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
