import 'package:dunes_app/features/proposal_intake/proposal_finance_formula.dart';
import 'package:dunes_app/features/proposal_intake/proposal_finance_formula_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProposalPromotionTierPlan _monthSeq({
  String promoter = '广州巧思信息科技有限公司',
  List<ProposalPromotionSegment>? segments,
}) => ProposalPromotionTierPlan(
  id: 'p1',
  promoter: promoter,
  strategy: kProposalPromotionStrategyMonthSeq,
  segments:
      segments ??
      [
        const ProposalPromotionSegment(
          fromMonth: 1,
          toMonth: 3,
          tiers: [
            ProposalPromotionTier(from: 0, rate: 0.5),
            ProposalPromotionTier(from: 3000, rate: 0.6),
            ProposalPromotionTier(from: 10000, rate: 0.7),
            ProposalPromotionTier(from: 20000, rate: 0.8),
          ],
        ),
        const ProposalPromotionSegment(fromMonth: 4, type: 'fixed', rate: 0.5),
      ],
);

void main() {
  test('legacy percent rates become decimals and keep the old amount', () {
    final plan = ProposalPromotionTierPlan.fromJson({
      'basis': 'monthly',
      'mode': 'whole',
      'tiers': [
        {'from': 0, 'rate': 50},
      ],
    });
    expect(plan.promoter, '');
    expect(plan.strategy, kProposalPromotionStrategyMonthSeq);
    expect(plan.segments.single.tiers.single.rate, 0.5);
    expect(plan.evaluate(1200).amount, 600);
  });

  test('legacy annual tiers fold into monthly starts', () {
    final plan = ProposalPromotionTierPlan.fromJson({
      'basis': 'annual',
      'mode': 'whole',
      'tiers': [
        {'from': 12000, 'rate': 50},
      ],
    });
    expect(plan.segments.single.tiers.single.from, 1000);
    expect(plan.evaluate(12000).amount, 6000);
    expect(plan.evaluate(11999).amount, 0);
  });

  test('fixed strategy is annual scale times decimal rate', () {
    final plan = ProposalPromotionTierPlan(
      promoter: '贵州多彩新媒体股份有限公司',
      strategy: kProposalPromotionStrategyFixed,
      segments: const [ProposalPromotionSegment(type: 'fixed', rate: 0.8)],
    );
    final result = plan.evaluate(1000);
    expect(result.amount, 800);
    expect(result.substitution, contains('0.8'));
  });

  test('month-seq uses early-month tiers and later fixed rate', () {
    final result = _monthSeq().evaluate(12000);
    expect(result.amount, 6000);
    expect(result.substitution, contains('第 1–3 个月'));
    expect(result.substitution, contains('第 4 个月及以后'));
  });

  test('month-seq hits a higher tier when monthly scale is larger', () {
    // 年化 48000 万 → 月规模 4000 万，落在 3000 档 0.6
    // 1–3 月：4000 × 0.6 × 3 = 7200
    // 4–12 月：4000 × 0.5 × 9 = 18000
    final result = _monthSeq().evaluate(48000);
    expect(result.amount, 25200);
  });

  test('excess tiers add each band instead of using the last rate', () {
    final plan = _monthSeq(
      segments: const [
        ProposalPromotionSegment(
          fromMonth: 1,
          toMonth: 12,
          mode: 'excess',
          tiers: [
            ProposalPromotionTier(from: 0, rate: 0.5),
            ProposalPromotionTier(from: 1000, rate: 0.6),
          ],
        ),
      ],
    );
    // 月规模 1500：1000 × 0.5 + 500 × 0.6 = 800，×12 = 9600
    expect(plan.evaluate(18000).amount, 9600);
  });

  test('annual ladder uses yearly scale once', () {
    final plan = ProposalPromotionTierPlan(
      promoter: '年阶梯推广商',
      strategy: kProposalPromotionStrategyAnnual,
      segments: const [
        ProposalPromotionSegment(
          mode: 'whole',
          tiers: [
            ProposalPromotionTier(from: 0, rate: 0.5),
            ProposalPromotionTier(from: 10000, rate: 0.6),
          ],
        ),
      ],
    );
    // 年化 12000 落在 ≥10000 的 0.6，整年 12000 × 0.6 = 7200。
    final hit = plan.evaluate(12000);
    expect(hit.amount, 7200);
    expect(hit.substitution, contains('年化规模'));
    expect(plan.evaluate(9999).amount, 4999.5);
    final json = plan.toJson();
    expect(json['strategy'], kProposalPromotionStrategyAnnual);
    expect(
      ProposalPromotionTierPlan.fromJson(json).evaluate(12000).amount,
      7200,
    );
  });

  test('annual excess ladder adds each yearly band', () {
    final plan = ProposalPromotionTierPlan(
      strategy: kProposalPromotionStrategyAnnual,
      segments: const [
        ProposalPromotionSegment(
          mode: 'excess',
          tiers: [
            ProposalPromotionTier(from: 0, rate: 0.5),
            ProposalPromotionTier(from: 1000, rate: 0.6),
          ],
        ),
      ],
    );
    // 1500：1000 × 0.5 + 500 × 0.6 = 800。
    expect(plan.evaluate(1500).amount, 800);
  });

  test('new plans store promoter, decimal rate and 万元 starts', () {
    final json = _monthSeq().toJson();
    expect(json['promoter'], '广州巧思信息科技有限公司');
    expect(json['strategy'], kProposalPromotionStrategyMonthSeq);
    final first = (json['segments'] as List).first as Map;
    expect(first['fromMonth'], 1);
    expect(first['toMonth'], 3);
    expect((first['tiers'] as List).first, {'from': 0, 'rate': 0.5});
    final restored = ProposalPromotionTierPlan.fromJson(json);
    expect(restored.evaluate(12000).amount, 6000);
  });

  test('one product keeps a single promoter plan when writing', () {
    final entry = proposalFinanceWritePromotionPlans({}, [
      _monthSeq(),
      _monthSeq(promoter: '不该写入的第二家'),
    ]);
    final plans = proposalPromotionPlansOf(entry);
    expect(plans, hasLength(1));
    expect(plans.single.promoter, '广州巧思信息科技有限公司');
  });

  testWidgets('promotion editor shows promoter and month-seq fields', (
    tester,
  ) async {
    final eval = proposalEvaluateFinance({
      'skuDetails': [
        {
          'id': 'a',
          'productName': '产品A',
          'settlements': [
            {
              'id': 'a-st',
              'kind': 'cost',
              'billType': '推广费',
              'scale': '12000',
              'settleRatio': '0.9',
            },
          ],
        },
      ],
      kProposalFinanceFormulaTouchedKey: {'project': true, 'tax': true},
      kProposalProductFormulasKey: {
        'a': {
          'costItems': ['推广费'],
          kProposalPromotionPlansKey: [_monthSeq().toJson()],
        },
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProposalFinanceCostPanel(
              config: ProposalFinanceBoardConfig(
                evaluation: eval,
                catalog: ProposalFinanceFormulaCatalog.fallback,
                products: eval.products,
                categoryEditable: const {kProposalCostCategoryProject: true},
                onPromotionPlans: (_, _) {},
                onCostItemsChanged: (_, _, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('推广商'), findsWidgets);
    expect(find.text('连续月序配置'), findsOneWidget);
    expect(find.text('年阶梯'), findsOneWidget);
    expect(find.text('阶梯比例'), findsWidgets);
    expect(find.text('固定比例'), findsWidgets);
    expect(find.text('添加月份段'), findsOneWidget);
    expect(find.text('配置推广商'), findsNothing);
    expect(find.textContaining('月规模 ≥（万元）'), findsOneWidget);
  });
}
