import 'package:dunes_app/features/qianji/native_qianji_lookup_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, QianjiLookupKind kind) {
    return tester.pumpWidget(
      MaterialApp(
        home: NativeQianjiLookupPreviewPage(
          kind: kind,
          onBack: () {},
          initialFrom: DateTime(2026, 9, 1),
          initialTo: DateTime(2026, 9, 30),
        ),
      ),
    );
  }

  testWidgets('group reply preview shows unreplied mentions', (tester) async {
    await pump(tester, QianjiLookupKind.groupReply);
    expect(find.text('工作群里被 @ 后的已读和回复'), findsOneWidget);
    expect(find.text('华东销售群'), findsWidgets);
    expect(find.text('已读未回复 6 小时'), findsOneWidget);
    expect(find.textContaining('门店巡检'), findsNothing);

    await tester.tap(find.text('研发值班群').first);
    await tester.pump();
    expect(find.text('赵敏 · 被林嘉宁 @'), findsNothing);
    expect(find.text('孙浩 · 被周致远 @'), findsOneWidget);
  });

  testWidgets('monthly opinion preview filters by bill type', (tester) async {
    await pump(tester, QianjiLookupKind.monthlyOpinion);
    expect(find.text('按月结日期看确认意见'), findsOneWidget);
    expect(find.text('9月12日 · 供给月结'), findsOneWidget);
    expect(find.text('有异议'), findsWidgets);
    expect(find.text('10 月账单刚生成'), findsNothing);

    await tester.tap(find.text('供给'));
    await tester.pump();
    expect(find.text('9月5日 · 渠道月结'), findsNothing);
    expect(find.text('供给差异 1.2 万还没说明'), findsOneWidget);
  });

  testWidgets('proposal review preview shows fill and review lines', (
    tester,
  ) async {
    await pump(tester, QianjiLookupKind.proposalReview);
    expect(find.text('提案各板块的填写和审核'), findsOneWidget);
    expect(find.text('华东柴油采购'), findsOneWidget);
    expect(find.text('财务部 · 已驳回'), findsOneWidget);
    expect(find.text('规模还没填完'), findsNothing);

    await tester.tap(find.text('科技'));
    await tester.pump();
    expect(find.text('市场部 · 已填写'), findsNothing);
    expect(find.text('科技部 · 待审核'), findsOneWidget);
    expect(find.text('科技部 · 已通过'), findsOneWidget);
  });
}
