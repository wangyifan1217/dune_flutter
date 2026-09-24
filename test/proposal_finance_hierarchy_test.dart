import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/proposal_intake/native_proposal_intake_page.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_service.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_ui.dart';
import 'package:dunes_app/features/proposal_intake/settlement_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness({
  ProposalIntakeRow? row,
}) {
  final auth = AuthSession.fromJson(const {'userId': 11, 'displayName': '王奕凡'});
  final service = ProposalIntakeService(session: auth);
  final options = ProposalIntakeOptions.fromJson({
    'market': {
      'sectors': ['数字营销事业部'],
      'proposalTypes': ['新增业务提案'],
      'products': [
        {'value': '智能投放平台', 'projects': ['华东项目']},
      ],
      'supplies': ['头部媒体供给'],
      'channels': ['直客渠道'],
      'institutions': [
        {'label': '卓悦C', 'code': 'ZYC'},
      ],
      'profitModes': ['返点差价'],
      'supplyBrands': ['中石油'],
      'rebateModes': ['消费返'],
    },
    'technology': {
      'platforms': [
        {'value': '数据平台', 'capabilities': ['圈选']},
      ],
      'outputForms': ['API 接口'],
      'developmentTypes': ['全新开发'],
      'financeInterfaces': [
        {'key': 'invoice', 'label': '开票接口', 'required': true},
      ],
    },
    'finance': {
      'costItems': kProposalProjectCostItems,
      'businessCostItems': ['员工提成'],
      'rollbackOptions': ['不回滚'],
      'settleModes': ['预付款'],
      'settleCycles': ['现金 D+2'],
    },
    'rules': {'minimumScale': 500, 'minimumMargin': 4.5},
  });

  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1440,
        child: ProposalIntakeForm(
          row: row ??
              ProposalIntakeRow.fromJson({
                'id': 1,
                'code': 'TA-2026-0001',
                'title': '测试提案',
                'status': 'filling',
                'createdBy': 11,
                'form': {
                  'skuDetails': [
                    {'id': 'sku-1', 'productName': '测试油品', 'faceValue': '100'},
                  ],
                },
                'review': <String, dynamic>{},
              }),
          session: auth,
          options: options,
          people: const [],
          contracts: const [],
          saving: false,
          service: service,
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

Future<void> _scrollUntil(WidgetTester tester, String label) async {
  for (var i = 0; i < 20; i++) {
    if (find.text(label).evaluate().isNotEmpty) return;
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -420),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets('finance section adheres to subdued 3-tier hierarchy', (tester) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pump();

    // Switch to finance tab
    await tester.tap(find.byKey(const ValueKey('proposal-nav-finance')));
    await tester.pumpAndSettle();

    // Scroll down to finance section
    await _scrollUntil(tester, '开始逐条复核');
    expect(find.text('开始逐条复核'), findsOneWidget);

    // 1. Block title sits one step below the panel eyebrow label, so it must
    // not outgrow it: 12px w600 in the darkest ink.
    final groupTitleFinder = find.text('业务产品合计');
    expect(groupTitleFinder, findsOneWidget);
    final groupTitle = tester.widget<Text>(groupTitleFinder);
    expect(groupTitle.style?.fontSize, 12);
    expect(groupTitle.style?.fontWeight, FontWeight.w600);
    expect(groupTitle.style?.color, ProposalPalette.text);

    // 2. Secondary section title "业务产品财务复核"
    final reviewTitleFinder = find.text('业务产品财务复核');
    expect(reviewTitleFinder, findsOneWidget);
    final reviewTitle = tester.widget<Text>(reviewTitleFinder);
    expect(reviewTitle.style?.fontSize, 12);
    expect(reviewTitle.style?.fontWeight, FontWeight.w600);
    expect(reviewTitle.style?.color, ProposalPalette.text2);

    // 3. Status text is quiet 11px gray text, not large purple status chip
    final statusFinder = find.text('待财务部负责人二逐项复核');
    expect(statusFinder, findsOneWidget);
    final statusText = tester.widget<Text>(statusFinder);
    expect(statusText.style?.fontSize, 11);
    expect(statusText.style?.color, ProposalPalette.text3);
    expect(
      find.ancestor(of: statusFinder, matching: find.byType(ProposalStatusChip)),
      findsNothing,
      reason: 'Status should be quiet text, not heavy ProposalStatusChip',
    );

    // 4. Secondary section title "产品结算" in header
    final settleTitleFinder = find.text('产品结算');
    expect(settleTitleFinder, findsWidgets); // Can appear in sheet group and header
    // The one inside _skuSettlementsReviewHeader has hint below it
    final headerTitleFinder = find.ancestor(
      of: find.textContaining('每个产品一套结算'),
      matching: find.byType(Row),
    );
    expect(headerTitleFinder, findsOneWidget);
    final headerTitle = tester.widget<Text>(
      find.descendant(of: headerTitleFinder, matching: find.text('产品结算')),
    );
    expect(headerTitle.style?.fontSize, 12);
    expect(headerTitle.style?.fontWeight, FontWeight.w600);
    expect(headerTitle.style?.color, ProposalPalette.text2);

    // 5. Action buttons in product card are compact with fontSize 11
    final copyButtonFinder = find.widgetWithText(TextButton, '复制结算');
    expect(copyButtonFinder, findsOneWidget);
    final copyButton = tester.widget<TextButton>(copyButtonFinder);
    final copyTextStyle = copyButton.style?.textStyle?.resolve({});
    expect(copyTextStyle?.fontSize, 11);
  });

  testWidgets('finance captions are trimmed and share one caption style', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('proposal-nav-finance')));
    await tester.pumpAndSettle();
    await _scrollUntil(tester, '开始逐条复核');

    const captions = [
      '本组独立核算，不与其他产品组合并。',
      '先核产品结算，再核合计收入成本。',
      '每个产品一套结算，可再加明细；复核整块完成。',
    ];
    for (final caption in captions) {
      final finder = find.text(caption);
      expect(finder, findsOneWidget, reason: caption);
      final style = tester.widget<Text>(finder).style;
      expect(style?.fontSize, 11, reason: caption);
      expect(style?.color, ProposalPalette.text3, reason: caption);
      expect(style?.height, 1.45, reason: caption);
    }

    // The verbose originals must be gone.
    expect(find.textContaining('及复核均在本组内独立核算'), findsNothing);
    expect(find.textContaining('产品结算和财务字段旁会出现复核按钮'), findsNothing);
    expect(find.textContaining('整块复核，不必进结算详情'), findsNothing);
  });
}
