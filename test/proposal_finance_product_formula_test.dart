import 'package:dunes_app/features/proposal_intake/proposal_finance_formula.dart';
import 'package:dunes_app/features/proposal_intake/proposal_finance_formula_board.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sku(String id, String name, String scale) => {
  'id': id,
  'productName': name,
  'settlements': [
    {'id': '$id-st', 'scale': scale, 'settleRatio': '0.9', 'taxRate': '6%'},
  ],
};

Map<String, dynamic> _plan(
  String id, {
  String basis = 'annual',
  double rate = 1,
}) => {
  'id': id,
  'name': '方案$id',
  'basis': basis,
  'mode': 'whole',
  'tiers': [
    {'from': 0, 'rate': rate},
  ],
};

const _touched = {'project': true, 'tax': true};

void main() {
  test('each product evaluates its own formulas and totals add up', () {
    final eval = proposalEvaluateFinance({
      'skuDetails': [_sku('a', '产品A', '1200'), _sku('b', '产品B', '600')],
      kProposalFinanceFormulaTouchedKey: _touched,
      kProposalProductFormulasKey: {
        'a': {
          'costItems': ['推广费'],
          kProposalPromotionPlansKey: [_plan('1')],
        },
        'b': {'costItems': <String>[]},
      },
    });
    expect(eval.products.map((p) => p.skuId), ['a', 'b']);
    final a = eval.products[0].evaluation;
    final b = eval.products[1].evaluation;
    expect(a.total(kProposalCostCategoryProject), 12);
    expect(b.total(kProposalCostCategoryProject), 0);
    expect(eval.total(kProposalCostCategoryProject), 12);
    expect(
      eval.revenue.amount,
      closeTo(a.revenue.amount + b.revenue.amount, 0.011),
    );
  });

  test('promotion plans only count when 推广费 is selected', () {
    final eval = proposalEvaluateFinance({
      'skuDetails': [_sku('a', '产品A', '1200')],
      kProposalFinanceFormulaTouchedKey: _touched,
      kProposalProductFormulasKey: {
        'a': {
          'costItems': ['技术对接费'],
          kProposalPromotionPlansKey: [_plan('1')],
        },
      },
    });
    final lines =
        eval.buckets[kProposalCostCategoryProject]?.lines ?? const [];
    expect(lines.map((line) => line.name), isNot(contains('推广费')));
  });

  test('each product uses only the first promoter plan', () {
    final eval = proposalEvaluateFinance({
      'skuDetails': [_sku('a', '产品A', '1200')],
      kProposalFinanceFormulaTouchedKey: _touched,
      kProposalProductFormulasKey: {
        'a': {
          'costItems': ['推广费'],
          kProposalPromotionPlansKey: [
            // 月规模 100 万 × 1% = 1 万/月 → 12 万/年
            _plan('1', basis: 'monthly', rate: 1),
            _plan('2', basis: 'annual', rate: 0.5),
          ],
        },
      },
    });
    final line = eval.buckets[kProposalCostCategoryProject]!.lines.singleWhere(
      (line) => line.name == '推广费',
    );
    expect(line.amount, 12);
  });

  test('operating cost is types only and stays out of profit', () {
    final eval = proposalEvaluateFinance({
      'skuDetails': [_sku('a', '产品A', '1200')],
      kProposalFinanceFormulaTouchedKey: _touched,
      kProposalOperatingCostItemsKey: ['差旅成本', '招待费'],
      kProposalProductFormulasKey: {
        'a': {
          'costItems': <String>[],
          'taxCostItems': ['印花税'],
        },
      },
    });
    expect(eval.total(kProposalCostCategoryOperating), 0);
    expect(
      eval.profit,
      closeTo(
        eval.revenue.amount -
            eval.total(kProposalCostCategoryProject) -
            eval.total(kProposalCostCategoryBusiness) -
            eval.total(kProposalCostCategoryTax),
        0.011,
      ),
    );
    final operating = ProposalFinanceFormulaCatalog.fallback.category(
      kProposalCostCategoryOperating,
    );
    for (final item in operating?.items ?? const <ProposalCostTypeOption>[]) {
      expect(item.formulas, isEmpty, reason: item.name);
    }
  });

  test('legacy group promotion tiers migrate into the first product plan', () {
    final form = proposalMaterializeProductFormulas({
      'skuDetails': [_sku('a', '产品A', '1200')],
      'costItems': ['推广费'],
      kProposalPromotionTiersKey: {
        'basis': 'annual',
        'mode': 'whole',
        'tiers': [
          {'from': 0, 'rate': 1},
        ],
      },
    });
    final entry = proposalProductFormulaRawEntry(form, 'a');
    expect(entry['owner'], kProposalProductFinanceMain);
    expect(entry['costItems'], ['推广费']);
    final plans = proposalPromotionPlansOf(entry);
    expect(plans, hasLength(1));
    expect(plans.single.name, '方案1');
    expect(plans.single.strategy, kProposalPromotionStrategyMonthSeq);
    expect(plans.single.segments, hasLength(1));
    expect(plans.single.segments.single.tiers.single.rate, 0.01);
  });

  test('materialize drops formulas of removed products', () {
    final form = proposalMaterializeProductFormulas({
      'skuDetails': [_sku('a', '产品A', '1200')],
      kProposalProductFormulasKey: {
        'a': {'revenueFormula': 'R1'},
        'gone': {'revenueFormula': 'R2'},
      },
    });
    final entries = form[kProposalProductFormulasKey] as Map;
    expect(entries.keys, ['a']);
    expect((entries['a'] as Map)['revenueFormula'], 'R1');
  });

  test('cost is auto-estimated: per product formula reviews are not required', () {
    final keys = proposalIntakeFinanceReviewKeys({
      'skuDetails': [_sku('a', '产品A', '1200')],
      'childProducts': [_sku('c', '子产品C', '100')],
    });
    for (final kind in kProposalProductFormulaReviewKinds) {
      expect(keys, isNot(contains(proposalIntakeProductFormulaReviewKey('a', kind))));
      expect(keys, isNot(contains(proposalIntakeProductFormulaReviewKey('c', kind))));
    }
    expect(keys, isNot(contains('profit')));
    expect(keys, isNot(contains('margin')));
  });

  testWidgets('finance board hides estimate amounts and lists products', (
    tester,
  ) async {
    expect(kProposalFinanceShowEstimates, isFalse);
    final eval = proposalEvaluateFinance({
      'skuDetails': [_sku('a', '产品A', '1200'), _sku('b', '产品B', '600')],
      kProposalFinanceFormulaTouchedKey: _touched,
      kProposalProductFormulasKey: {
        'a': {
          'costItems': ['推广费'],
          kProposalPromotionPlansKey: [_plan('1')],
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
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('共 2 个产品'), findsOneWidget);
    expect(find.textContaining('产品A'), findsWidgets);
    expect(find.textContaining('产品B'), findsWidgets);
    expect(find.textContaining('万元'), findsNothing);
  });
}
