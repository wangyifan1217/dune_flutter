import 'package:dunes_app/features/proposal_intake/proposal_finance_formula.dart';
import 'package:dunes_app/features/proposal_intake/proposal_finance_formula_board.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _input(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byType(TextField),
);

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(_input(key)).controller!.text;

void main() {
  testWidgets('editing tier rows keeps every row on its own data', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var plans = [
      const ProposalPromotionTierPlan(
        id: 'p1',
        promoter: 'A推广',
        segments: [
          ProposalPromotionSegment(
            fromMonth: 1,
            toMonth: 3,
            tiers: [
              ProposalPromotionTier(from: 0, rate: 0.1),
              ProposalPromotionTier(from: 1000, rate: 0.2),
            ],
          ),
          ProposalPromotionSegment(fromMonth: 4, type: 'fixed', rate: 0.05),
        ],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => ProposalPromotionPlanField(
                plans: plans,
                promoterOptions: const ['A推广'],
                onChanged: (next) => setState(() => plans = next),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const prefix = 'promotion-p1-0-2';
    // 第一档起点改得比第二档大：以前会当场重排，后面的输入写到另一档上。
    await tester.enterText(_input('$prefix-from-0-2'), '2000');
    await tester.pump();
    await tester.enterText(_input('$prefix-rate-0-2'), '0.3');
    await tester.pump();
    // 再加一档、改第三档。
    await tester.tap(find.text('添加档位'));
    await tester.pumpAndSettle();
    await tester.enterText(_input('$prefix-rate-2-3'), '0.4');
    await tester.pump();
    // 改到期月份时删空再输，不应变成「及以后」。
    await tester.enterText(_input('$prefix-to-month'), '');
    await tester.pump();
    expect(_input('$prefix-to-month'), findsOneWidget);
    await tester.enterText(_input('$prefix-to-month'), '6');
    await tester.pump();

    final segment = plans.single.segments.first;
    expect(segment.toMonth, 6);
    expect(segment.tiers, hasLength(3));
    expect(segment.tiers[0].from, 2000);
    expect(segment.tiers[0].rate, 0.3);
    expect(segment.tiers[1].from, 1000);
    expect(segment.tiers[1].rate, 0.2);
    expect(segment.tiers[2].from, 3000);
    expect(segment.tiers[2].rate, 0.4);
    expect(plans.single.segments[1].rate, 0.05);

    // 失焦后框里的字和数据一致。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(_text(tester, '$prefix-from-0-3'), '2000');
    expect(_text(tester, '$prefix-rate-1-3'), '0.2');

    // 删掉中间一档，剩下两行显示各自的值。
    await tester.tap(find.byTooltip('删除这一档').at(1));
    await tester.pumpAndSettle();
    expect(plans.single.segments.first.tiers, hasLength(2));
    expect(_text(tester, '$prefix-from-0-2'), '2000');
    expect(_text(tester, '$prefix-rate-1-2'), '0.4');
    expect(tester.takeException(), isNull);
  });

  test('settle terms with only a tier plan are not blank', () {
    const terms = ProposalFinanceSettleTerms(
      tierPlans: [
        ProposalPromotionTierPlan(
          id: 'p1',
          segments: ProposalPromotionTierPlan.monthSeqSegments,
        ),
      ],
    );
    expect(terms.isBlank, isFalse);
    expect(const ProposalFinanceSettleTerms().isBlank, isTrue);
  });

  test('copied product points its own settle refs and supply links at the copy', () {
    const source = ProposalSkuDetailRow(
      id: 'sku-1',
      productName: '主产品',
      settlements: [
        ProposalSkuSettleRow(
          id: 'st-1',
          terms: ProposalFinanceSettleTerms(
            settleRatio: '0.9',
            skuIds: ['sku-1', 'child-1', 'other'],
          ),
        ),
      ],
    );
    const child = ProposalSkuDetailRow(
      id: 'child-1',
      productName: '关联',
      parentSkuId: 'sku-1',
    );
    final copied = proposalIntakeCopyBusinessProducts(
      source: source,
      count: 1,
      mains: const [source],
      children: const [child],
      quantities: const {},
      idSeed: 1,
    );
    final main = copied.mains[1];
    final copiedChild = copied.children.firstWhere(
      (row) => row.parentSkuId == main.id,
    );
    expect(main.settlements.single.terms.skuIds, [
      main.id,
      copiedChild.id,
      'other',
    ]);
    expect(source.settlements.single.terms.skuIds, [
      'sku-1',
      'child-1',
      'other',
    ]);

    final form = <String, dynamic>{
      'supplyProducts': [
        {
          'id': 'sp-1',
          'supplierCode': 'S1',
          'settlements': [
            {
              'id': 'ss-1',
              'kind': 'cost',
              'settleRatio': '0.8',
              'skuIds': ['sku-1'],
            },
            {
              'id': 'ss-2',
              'kind': 'cost',
              'settleRatio': '0.7',
              'skuIds': ['sku-9'],
            },
          ],
        },
      ],
    };
    final linked = proposalIntakeLinkCopiedSupplySkus(
      form,
      newToSource: copied.formulaSources,
    );
    final settlements = proposalIntakeSupplySettlements(
      proposalIntakeSupplyProducts(linked).single,
    );
    expect(settlements[0].terms.skuIds, ['sku-1', main.id]);
    expect(settlements[1].terms.skuIds, ['sku-9']);
  });
}
