import 'package:dunes_app/features/robots/dunes_weekly_report_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders week totals and province bars in a narrow IM card', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 266,
              child: DunesWeeklyReportCard(
                markdown: """
# 沙丘经营周报
2026.11.16 – 11.22

## 灯塔资管
流入 **1260.00 万元**　流出 **1080.00 万元**　净流入 **180.00 万元**

渠道应收 **820.00 万元**

## 提案进展
| 类型 | 新建 | 通过／完成 | 当前审批中 |
| --- | ---: | ---: | ---: |
| 资金 | 2 | 1 | 2 |

## 成本审批
通过 **23 笔**

## 会议纪要
已生成 **13 份**

## 差旅
已入库费用 **6.80 万元**
- 广东 **2.40 万元**
- 北京 **1.60 万元**
- 上海 **1.10 万元**
- 其他 **1.70 万元**

用车 0.30 万元（4 单）
""",
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('净流入'), findsOneWidget);
    expect(find.text('+180万'), findsOneWidget);
    expect(find.text('广东'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'renders proposal metrics and a full-width table, keeping the footer while submitting',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var forwarded = 0;
      Future<void> render({required bool busy}) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: SizedBox(
                width: 300,
                child: DunesWeeklyReportCard(
                  deliveryLabel: '周六 18:10',
                  scheduledDelivery: true,
                  forwardBusy: busy,
                  onForward: () => forwarded++,
                  markdown: """
# 沙丘经营周报
2026.11.16 – 11.22

## 提案进展
新建 **12 笔**　通过／完成 **8 笔**　当前审批中 **9 笔**

| 类型 | 新建 | 通过／完成 | 当前审批中 |
| --- | ---: | ---: | ---: |
| 资金 | 2 | 1 | 2 |

**销售提案 · 上周完成 4 笔**

预计年化总规模 **8600.00 万元** · 覆盖 4／4 笔
- 三桶油 4 笔 · **8600.00 万元**

## 成本审批
通过 **3 笔**　归集获批金额 **36.00 万元**

| 类别 | 笔数 | 金额 |
| --- | ---: | ---: |
| 项目 | 2 | 24.00 万元 |
| 业务 | 1 | 12.00 万元 |

## 会议纪要
录入 **8 场**　已生成 **6 份**

纪要覆盖率 **75%**

| 部门 | 会议场数 | 已生成 | 覆盖率 |
| --- | ---: | ---: | ---: |
| 市场 | 8 场 | 6 份 | 75% |
""",
                ),
              ),
            ),
          ),
        ),
      );

      await render(busy: false);
      expect(find.text('周一 08:30'), findsOneWidget);
      expect(
        find.byTooltip('北京时间每周一 08:30 自动投递 · 实际收到 周六 18:10'),
        findsOneWidget,
      );
      expect(find.text('12'), findsOneWidget);
      expect(find.byType(Table), findsNWidgets(2));
      expect(find.text('8,600万'), findsOneWidget);
      expect(find.text('项目 24万'), findsOneWidget);
      final coverage = find.descendant(
        of: find.byType(Table).last,
        matching: find.byType(LinearProgressIndicator),
      );
      expect(tester.widget<LinearProgressIndicator>(coverage).value, 0.75);
      final forward = find.text('转发');
      await tester.ensureVisible(forward);
      final footerY = tester.getCenter(forward).dy;
      await tester.tap(forward);
      expect(forwarded, 1);
      await render(busy: true);
      expect(tester.getCenter(forward).dy, closeTo(footerY, 0.1));
      await tester.tap(forward);
      expect(forwarded, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a forwarded report opens directly from chat without a weekly subscription',
    (tester) async {
      const payload = {
        'robotKey': 'r_dunes_weekly_report',
        'robotMarkdown': true,
        'forwardedFromRobot': true,
      };
      expect(isForwardedDunesWeeklyReport(payload), isTrue);
      expect(isForwardedDunesWeeklyReport({'robotMarkdown': true}), isFalse);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DunesWeeklyReportShareTile(
              markdown: """
# 沙丘经营周报
2026.11.16 – 11.22

## 灯塔资管
流入 **10746.66 万元**　流出 **9.00 万元**　净流入 **10737.66 万元**
""",
            ),
          ),
        ),
      );
      await tester.tap(find.text('沙丘经营周报'));
      await tester.pumpAndSettle();
      expect(find.text('流入'), findsOneWidget);
      final inflow = tester.widget<Text>(find.text('10,746.66万'));
      final outflow = tester.widget<Text>(find.text('9万'));
      expect(inflow.style!.fontSize, 16);
      expect(outflow.style!.fontSize, inflow.style!.fontSize);
      expect(find.text('转发'), findsNothing);
      await tester.tap(find.byTooltip('关闭周报'));
      await tester.pumpAndSettle();
      expect(find.text('流入'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('forwarded report adapts to a narrow screen and large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const Scaffold(
          body: DunesWeeklyReportShareTile(
            markdown: """
# 沙丘经营周报
2026.11.16 – 11.22

## 灯塔资管
流入 **10746.66 万元**　流出 **9.00 万元**　净流入 **10737.66 万元**

## 部门一览
| 部门 | 提案完成 | 成本获批 | 纪要 | 差旅 |
| --- | ---: | ---: | ---: | ---: |
| 企业服务与运营管理部 | 15 笔 | 536.22 万元 | 31 份 | 19.25 万元 |
""",
          ),
        ),
      ),
    );
    await tester.tap(find.text('沙丘经营周报'));
    await tester.pumpAndSettle();

    final report = find.byType(DunesWeeklyReportCard);
    expect(tester.getSize(report).width, greaterThanOrEqualTo(296));
    final inflow = find.text('10,746.66万');
    final outflow = find.text('9万');
    expect(
      tester.getTopLeft(outflow).dy,
      greaterThan(tester.getTopLeft(inflow).dy),
    );
    expect(tester.widget<Text>(inflow).style!.fontSize, 16);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
