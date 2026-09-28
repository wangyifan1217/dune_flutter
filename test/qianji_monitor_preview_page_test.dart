import 'package:dunes_app/features/qianji/native_qianji_monitor_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('task preview lists overdue subtasks and filters by department', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeQianjiMonitorPreviewPage(
          kind: QianjiMonitorPreviewKind.task,
          onBack: () {},
          initialFrom: DateTime(2026, 9, 1),
          initialTo: DateTime(2026, 9, 30),
        ),
      ),
    );

    expect(find.text('只看逾期还没办结的子任务'), findsOneWidget);
    expect(find.text('逾期子任务'), findsOneWidget);
    expect(find.text('林嘉宁 · 销售部'), findsOneWidget);
    expect(find.text('跟进华东柴油合同'), findsOneWidget);
    expect(find.text('主目标 · Q3 销售回款'), findsWidgets);
    expect(find.textContaining('整理下月预算草稿'), findsNothing);

    await tester.tap(find.text('研发部'));
    await tester.pump();
    expect(find.text('林嘉宁 · 销售部'), findsNothing);
    expect(find.text('周致远 · 研发部'), findsOneWidget);
    expect(find.text('孙浩 · 研发部'), findsOneWidget);
  });

  testWidgets('daily report preview lists missing days in the selected range', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeQianjiMonitorPreviewPage(
          kind: QianjiMonitorPreviewKind.dailyReport,
          onBack: () {},
          initialFrom: DateTime(2026, 9, 1),
          initialTo: DateTime(2026, 9, 30),
        ),
      ),
    );

    expect(find.text('所选时间内还没交的人'), findsOneWidget);
    expect(find.text('未交天数'), findsOneWidget);
    expect(find.text('未交 2 天'), findsOneWidget);

    await tester.tap(find.text('财务部'));
    await tester.pump();
    expect(find.text('陈丽 · 财务部'), findsOneWidget);
    expect(find.text('林嘉宁 · 销售部'), findsNothing);
    expect(find.text('9月8日'), findsOneWidget);
    expect(find.text('10月3日'), findsNothing);
  });
}
