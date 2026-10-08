import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/proposal_intake/native_proposal_intake_page.dart';
import 'package:dunes_app/features/proposal_intake/proposal_estimate_summary.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_service.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_ui.dart';
import 'package:dunes_app/features/proposal_intake/settlement_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProposalIntakeOptions _options() => ProposalIntakeOptions.fromJson({
  'rules': {'minimumScale': 500, 'minimumMargin': 0.5},
});

Widget _form(ProposalIntakeRow row, {double width = 1440}) {
  final auth = AuthSession.fromJson(const {
    'userId': 11,
    'displayName': '王奕凡',
  });
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: ProposalIntakeForm(
          row: row,
          session: auth,
          options: _options(),
          people: const [],
          contracts: const [],
          saving: false,
          service: ProposalIntakeService(session: auth),
          catalog: SettlementCatalogService.offline(),
          enableComments: false,
          onChanged: (_) {},
          onSaved: (_) {},
          onSubmit: (_) {},
          onError: (_) {},
        ),
      ),
    ),
  );
}

ProposalIntakeRow _row({
  String kind = 'sales',
  String status = 'filling',
  Map<String, dynamic> form = const {},
}) => ProposalIntakeRow.fromJson({
  'id': 1,
  'code': 'TA-2026-0001',
  'title': '测试提案',
  'kind': kind,
  'status': status,
  'version': 1,
  'createdBy': 11,
  'form': form,
  'review': <String, dynamic>{},
});

const _filledForm = <String, dynamic>{
  'salesScale': 1200,
  'revenue': 100,
  'revenueManual': true,
  'couponProcurementCost': 80,
  'projectCost': 6,
  'turnoverTimes': 4,
};

/// 顶部测算用 RichText 画字，按整段文字找。
Finder _rich(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText() == text,
  description: 'RichText "$text"',
);

const _prototypeData = ProposalEstimateSummaryData(
  rating: 'S',
  ratingRule: '≥ 5,000万',
  scale: 90000,
  revenue: 89100,
  procurement: 87120,
  projectCost: 1080,
  businessCost: 0,
  profit: 900,
  margin: 1.0,
  turnoverCash: 1875,
  turnoverTimes: 4,
  skuCount: 30,
  faceRange: '面值 10–500 元',
);

void main() {
  test('groups thousands and keeps decimals', () {
    expect(proposalEstimateGrouped('1980'), '1,980');
    expect(proposalEstimateGrouped('90000.5'), '90,000.5');
    expect(proposalEstimateGrouped('-1080'), '-1,080');
    expect(proposalEstimateGrouped('12'), '12');
    expect(proposalEstimateGrouped('abc'), 'abc');
    expect(proposalEstimateWan(90000), '90,000.0');
    expect(proposalEstimateWan(null), '—');
  });

  test('list figures follow the same estimate as the detail page', () {
    expect(proposalEstimateListFigures(const {}), (scale: '', margin: ''));
    // 利润 = 100 − 80 − 6 = 14；14 ÷ 1200 = 1.17%。
    expect(
      proposalEstimateListFigures(_filledForm),
      (scale: '1200', margin: '1.17'),
    );
    // 只有规模、收入还算不出来时不显示毛利率。
    expect(
      proposalEstimateListFigures(const {'salesScale': 860}),
      (scale: '860', margin: ''),
    );
  });

  for (final width in [1440.0, 390.0]) {
    testWidgets('summary matches the prototype layout at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ProposalIntakeNavSection? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProposalEstimateSummary(
                data: _prototypeData,
                onOpenSection: (section) => opened = section,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      // 左：年化利润 · 测算
      expect(_rich('年化利润 · 测算'), findsOneWidget);
      expect(_rich('900.0 万'), findsOneWidget);
      expect(_rich('1.0% 毛利率 · 利润÷规模'), findsOneWidget);
      expect(_rich('= 收入 1,980.0 − 项目成本 1,080.0'), findsOneWidget);
      expect(_rich('S 按年化规模自动 · ≥ 5,000万'), findsOneWidget);
      // 右：测算合计 + 瀑布图
      expect(_rich('测算合计   年化 · 万元'), findsOneWidget);
      expect(_rich('收入（利差）'), findsNWidgets(2));
      expect(_rich('2.2%'), findsOneWidget);
      expect(_rich('7,500.0'), findsOneWidget);
      expect(_rich('4次/月'), findsOneWidget);
      expect(_rich('−1,080.0'), findsOneWidget);
      // 下：规模 / 成本 / 利润
      expect(_rich('售价 →'), findsOneWidget);
      expect(_rich('99.0%'), findsOneWidget);
      expect(_rich('30个'), findsOneWidget);
      expect(_rich('面值 10–500 元'), findsOneWidget);
      expect(_rich('规模 × 2.2% 利差'), findsOneWidget);
      expect(_rich('每月周转 4 次'), findsOneWidget);
      expect(_rich('75.0万'), findsOneWidget);

      final link = _rich('来自 市场部 · 规模 ›');
      await tester.ensureVisible(link);
      await tester.tap(link);
      expect(opened, ProposalIntakeNavSection.market);
    });
  }

  testWidgets('form shows estimate summary once finance numbers exist', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_form(_row(form: _filledForm)));
    await tester.pump();

    final card = find.byKey(const ValueKey('proposal-estimate-summary'));
    expect(card, findsOneWidget);
    // 利润 = 收入 100 − 采购 80 − 项目 6；利差 = 20；周转资金 = 1200 ÷ 12 ÷ 4。
    expect(
      find.descendant(of: card, matching: _rich('14.0 万')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: _rich('= 收入 20.0 − 项目成本 6.0')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: _rich('1,200.0万')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: _rich('25.0万')),
      findsOneWidget,
    );
  });

  testWidgets('estimate link switches to the finance tab', (tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _form(_row(status: 'pending_president', form: _filledForm)),
    );
    await tester.pump();
    // 填报内容默认收起，财务部字段不显示。
    expect(find.text('收入（万元）'), findsNothing);

    final link = _rich('来自 财务部 · 项目成本 ›');
    await tester.ensureVisible(link);
    await tester.pump();
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.text('收入（万元）'), findsOneWidget);
  });

  testWidgets('estimate summary stays read-only in pending president', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _form(_row(status: 'pending_president', form: _filledForm), width: 390),
    );
    await tester.pump();

    final card = find.byKey(const ValueKey('proposal-estimate-summary'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.byType(TextField)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and purchase proposals keep the old layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_form(_row()));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('proposal-estimate-summary')),
      findsNothing,
    );

    await tester.pumpWidget(_form(_row(kind: 'purchase', form: _filledForm)));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('proposal-estimate-summary')),
      findsNothing,
    );
  });

  testWidgets('estimate summary recalculates while typing the scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_form(_row(form: _filledForm)));
    await tester.pump();

    final card = find.byKey(const ValueKey('proposal-estimate-summary'));
    expect(
      find.descendant(of: card, matching: _rich('1,200.0万')),
      findsOneWidget,
    );

    final scaleInput = find.descendant(
      of: find.ancestor(
        of: find.text('规模（万元）'),
        matching: find.byType(ProposalField),
      ),
      matching: find.byType(EditableText),
    );
    await tester.ensureVisible(scaleInput.first);
    await tester.enterText(scaleInput.first, '2400');
    await tester.pump();

    // 填写中是原型填写页的实时测算：年化规模、周转资金（2400 ÷ 12 ÷ 4）、毛利率（14 ÷ 2400 ≈ 0.58%）跟着变。
    expect(
      find.descendant(of: card, matching: _rich('2,400.0万')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: _rich('50.0万')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: _rich('0.58%')),
      findsOneWidget,
    );
  });

  testWidgets('read-only values get the dashed underline only when viewing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const viewForm = <String, dynamic>{
      ..._filledForm,
      'proposalName': '平安石化产险保证金提案',
    };

    await tester.pumpWidget(_form(_row(form: viewForm)));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('proposal-view-underline')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _form(_row(status: 'pending_president', form: viewForm)),
    );
    await tester.pump();
    // 原型：只读时填报内容默认收起，先展开。
    await tester.tap(
      find.byKey(const ValueKey('proposal-simple-content-toggle')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('proposal-view-underline')),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('flow card follows the prototype states', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProposalFlowCard(
            steps: [
              ProposalIntakeProgressStep(
                id: 'review_market',
                title: '市场部负责人一 王一凡',
                role: '市场部负责人一',
                name: '王一凡',
                time: '06-18',
                state: ProposalIntakeProgressState.done,
              ),
              ProposalIntakeProgressStep(
                id: 'review_contract',
                title: '财务部负责人二 刘畅',
                role: '财务部负责人二',
                name: '刘畅',
                statusText: '进行中',
                time: '当前',
                state: ProposalIntakeProgressState.current,
              ),
              ProposalIntakeProgressStep(
                id: 'president',
                title: '总裁',
                role: '最终确认人',
                state: ProposalIntakeProgressState.pending,
              ),
            ],
          ),
        ),
      ),
    );
    expect(_rich('流程'), findsOneWidget);
    expect(_rich('卡 · 刘畅'), findsOneWidget);
    expect(_rich('✓'), findsOneWidget);
    expect(_rich('王一凡 · 06-18'), findsOneWidget);
    expect(_rich('进行中'), findsOneWidget);
    expect(_rich('—'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('header shows prototype badge and status pill when viewing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_form(_row(form: _filledForm)));
    await tester.pump();
    // 填写中：原型填写页标题旁显示「填写中」，没有「流程」格子。
    expect(
      find.byKey(const ValueKey('proposal-status-pill-filling')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('proposal-flow-card')), findsNothing);
    expect(find.text('平安石化产险保证金提案'), findsNothing);
    expect(find.text('测试提案'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _form(_row(status: 'pending_president', form: _filledForm)),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('proposal-status-pill-pending_president')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('proposal-top-rating')), findsOneWidget);
    expect(find.byKey(const ValueKey('proposal-flow-card')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read-only proposal collapses filled content into simple rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const viewForm = <String, dynamic>{
      ..._filledForm,
      'proposalName': '平安石化产险保证金提案',
      'sector': '能源',
    };
    await tester.pumpWidget(
      _form(_row(status: 'pending_president', form: viewForm)),
    );
    await tester.pump();

    final box = find.byKey(const ValueKey('proposal-simple-content'));
    expect(box, findsOneWidget);
    // 原型：默认收起，只看顶部测算。
    expect(find.text('展开 ▾'), findsOneWidget);
    expect(find.text('业务板块'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('proposal-simple-content-toggle')));
    await tester.pump();
    expect(find.text('收起 ▴'), findsOneWidget);
    expect(find.text('业务板块'), findsOneWidget);
    expect(find.text('能源'), findsWidgets);
    // 板块大标题不再重复。
    expect(find.text('MARKET'), findsNothing);
    expect(tester.takeException(), isNull);

    // 收起后点板块标签会自动展开。
    await tester.tap(find.byKey(const ValueKey('proposal-simple-content-toggle')));
    await tester.pump();
    expect(find.text('业务板块'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('proposal-nav-tech')));
    await tester.pumpAndSettle();
    expect(find.text('收起 ▴'), findsOneWidget);
  });

  testWidgets('filling and reviewing keep the original form', (tester) async {
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final status in ['filling', 'reviewing']) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_form(_row(status: status, form: _filledForm)));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('proposal-simple-content')),
        findsNothing,
        reason: status,
      );
    }
  });
}
