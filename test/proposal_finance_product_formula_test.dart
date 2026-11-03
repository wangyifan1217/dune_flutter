import 'package:dunes_app/features/proposal_intake/proposal_cost_estimate.dart';
import 'package:dunes_app/features/proposal_intake/proposal_finance_formula.dart';
import 'package:dunes_app/features/proposal_intake/proposal_finance_formula_board.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sku(
  String id,
  String name,
  String scale, {
  bool payable = false,
}) => {
  'id': id,
  'productName': name,
  'settlements': [
    {'id': '$id-st', 'scale': scale, 'settleRatio': '0.9', 'taxRate': '6%'},
    if (payable)
      {
        'id': '$id-promotion',
        'kind': 'cost',
        'billType': '应付账单 / 服务费 / 推广费',
        'settleRatio': '0.01',
      },
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
      'skuDetails': [
        _sku('a', '产品A', '1200', payable: true),
        _sku('b', '产品B', '600'),
      ],
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
    final lines = eval.buckets[kProposalCostCategoryProject]?.lines ?? const [];
    expect(lines.map((line) => line.name), isNot(contains('推广费')));
  });

  test('each product uses only the first promoter plan', () {
    final eval = proposalEvaluateFinance({
      'skuDetails': [_sku('a', '产品A', '1200', payable: true)],
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

  test('product cost formulas must be reviewed before finance approval', () {
    final keys = proposalIntakeFinanceReviewKeys({
      'skuDetails': [_sku('a', '产品A', '1200')],
      'childProducts': [_sku('c', '子产品C', '100')],
    });
    for (final kind in kProposalProductFormulaReviewKinds) {
      expect(keys, contains(proposalIntakeProductFormulaReviewKey('a', kind)));
      expect(keys, contains(proposalIntakeProductFormulaReviewKey('c', kind)));
    }
    expect(keys, isNot(contains('profit')));
    expect(keys, isNot(contains('margin')));
    expect(keys, isNot(contains('operatingCost')));
  });

  testWidgets('finance board hides estimate amounts and lists products', (
    tester,
  ) async {
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
                showEstimates: false,
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

  test('copying a product copies the income formula it shows', () {
    final form = {
      'skuDetails': [
        _sku('sku-1', '原产品', '100'),
        _sku('sku-2', '原产品（副本）', '100'),
      ],
      kProposalProductFormulasKey: {
        'sku-1': {
          kProposalRevenueFormulaKey: '15',
          kProposalRevenueFormulaGroupKey: 'OPERATOR',
          'costItems': ['推广费'],
        },
      },
    };
    final copied = proposalIntakeAssignCopiedProductFormulas(
      form,
      newToSource: const {'sku-2': 'sku-1'},
    );
    final entries = copied[kProposalProductFormulasKey] as Map;
    final source = Map<String, dynamic>.from(entries['sku-1'] as Map);
    final target = Map<String, dynamic>.from(entries['sku-2'] as Map);
    expect(target[kProposalRevenueFormulaKey], '15');
    expect(target[kProposalRevenueFormulaGroupKey], 'OPERATOR');
    expect(target['costItems'], ['推广费']);
    (target['costItems'] as List).add('支付手续费');
    expect(source['costItems'], ['推广费']);

    final pasted = proposalIntakeAssignCopiedProductFormulas(
      form,
      newToSource: const {'sku-2': 'sku-1'},
      fields: const ['revenueFormula', 'revenueFormulaGroup'],
    );
    final pastedTarget = (pasted[kProposalProductFormulasKey] as Map)['sku-2'];
    expect(pastedTarget['revenueFormula'], '15');
    expect(pastedTarget['costItems'], isNull);
  });

  test('收入公式里的利差取收入类型为利差的结算', () {
    Map<String, dynamic> form({required bool spread}) => {
      'salesScale': 100,
      'skuDetails': [
        {
          'id': 'sku-1',
          'productName': '会员包',
          'settlements': [
            {'id': 'in', 'scale': '100', 'settleRatio': '1'},
            if (spread)
              {'id': 'spread', 'billType': '利差', 'settleRatio': '0.2'},
            {
              'id': 'promo',
              'kind': 'cost',
              'billType': '推广费',
              'settleRatio': '0.1',
            },
          ],
        },
      ],
      kProposalProductFormulasKey: {
        'sku-1': {
          kProposalRevenueFormulaKey: '15',
          kProposalRevenueFormulaGroupKey: 'OPERATOR',
        },
      },
    };

    final without = proposalEvaluateFinance(
      form(spread: false),
      catalog: ProposalFinanceFormulaCatalog.fallback,
    ).revenue;
    final withSpread = proposalEvaluateFinance(
      form(spread: true),
      catalog: ProposalFinanceFormulaCatalog.fallback,
    ).revenue;
    expect(proposalSpreadIncomeAmount(form(spread: false)), isNull);
    expect(proposalSpreadIncomeAmount(form(spread: true)), closeTo(20, 0.05));
    expect(without.missing, contains('利差'));
    expect(withSpread.missing, isNot(contains('利差')));
    expect(withSpread.amount, isNot(closeTo(without.amount, 0.01)));
  });
}
