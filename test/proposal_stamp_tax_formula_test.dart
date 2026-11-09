import 'dart:convert';

import 'package:dunes_app/features/proposal_intake/proposal_finance_formula.dart';
import 'package:dunes_app/features/proposal_intake/proposal_finance_formula_board.dart';
import 'package:dunes_app/features/proposal_intake/proposal_intake_select.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _form({String? formula, String ratio = '0.1'}) => {
  'salesScale': 20000,
  'financeFormulaTouched': {'project': true, 'tax': true},
  'taxCostItems': ['印花税'],
  if (formula != null) 'taxCostItemFormulas': {'印花税': formula},
  'skuDetails': [
    for (final id in ['a', 'b'])
      {
        'id': id,
        'productName': '产品$id',
        'settlements': [
          {'id': '$id-income', 'scale': '10000', 'settleRatio': ratio},
        ],
      },
  ],
  'productFormulas': {
    for (final id in ['a', 'b'])
      id: {'revenueFormulaGroup': 'ENERGY', 'revenueFormula': '3'},
  },
};

ProposalFinanceFormulaCatalog _legacyCatalog() {
  final current = ProposalFinanceFormulaCatalog.fallback;
  return ProposalFinanceFormulaCatalog(
    revenueGroups: current.revenueGroups,
    costCategories: [
      for (final category in current.costCategories)
        if (category.key != kProposalCostCategoryTax)
          category
        else
          ProposalCostCategory(
            key: category.key,
            name: category.name,
            namesKey: category.namesKey,
            amountsKey: category.amountsKey,
            totalKey: category.totalKey,
            formulasKey: category.formulasKey,
            items: [
              for (final item in category.items)
                if (item.name != '印花税')
                  item
                else
                  ProposalCostTypeOption(
                    code: item.code,
                    name: item.name,
                    defaultFormula: item.defaultFormula,
                    formulas: [item.formulaOf('TAX_STAMP_SCALE')!],
                  ),
            ],
          ),
    ],
  );
}

void main() {
  final catalog = ProposalFinanceFormulaCatalog.fallback;
  final tax = catalog.category(kProposalCostCategoryTax)!;

  test('existing stamp tax defaults to sales scale', () {
    for (final formula in [null, 'TAX_STAMP_SCALE']) {
      final evaluation = proposalEvaluateFinance(_form(formula: formula));
      final stamp = evaluation.bucket(kProposalCostCategoryTax)!.lines.single;
      expect(stamp.formula?.code, 'TAX_STAMP_SCALE');
      expect(stamp.amount, 12);
    }
  });

  test('revenue choice uses aggregated income once and survives saving', () {
    final original = proposalEvaluateFinance(_form());
    final selected = proposalFinanceWriteItemFormula(
      _form(),
      tax,
      '印花税',
      'TAX_STAMP_REVENUE',
    );
    final saved = proposalApplyFinanceFormulas(selected);
    final restored = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(saved)) as Map,
    );
    final evaluation = proposalEvaluateFinance(restored);
    final stamp = evaluation.bucket(kProposalCostCategoryTax)!.lines.single;
    expect(evaluation.revenue.amount, 2000);
    expect(stamp.formula?.code, 'TAX_STAMP_REVENUE');
    expect(stamp.amount, 1.2);
    expect(saved['taxCost'], 1.2);
    expect(evaluation.profit, closeTo(original.profit + 10.8, 0.001));
    expect(
      proposalEvaluateFinance(
        _form(formula: 'TAX_STAMP_REVENUE', ratio: '0.2'),
      ).total(kProposalCostCategoryTax),
      2.4,
    );
    expect(
      proposalEvaluateFinance(
        _form(formula: 'TAX_STAMP_REVENUE', ratio: '0'),
      ).total(kProposalCostCategoryTax),
      0,
    );
  });

  testWidgets('filler can select revenue in the stamp tax dropdown', (
    tester,
  ) async {
    var form = _form();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              final evaluation = proposalEvaluateFinance(form);
              return SingleChildScrollView(
                child: ProposalFinanceCostPanel(
                  mode: ProposalFinanceCostPanelMode.cost,
                  config: ProposalFinanceBoardConfig(
                    catalog: catalog,
                    evaluation: evaluation,
                    products: evaluation.products,
                    categoryEditable: const {kProposalCostCategoryTax: true},
                    focusKeys: const {'taxCost'},
                    showEstimates: false,
                    onCostFormula: (skuId, category, name, code) {
                      expect(skuId, isEmpty);
                      setState(() {
                        form = proposalFinanceWriteItemFormula(
                          form,
                          category,
                          name,
                          code,
                        );
                      });
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    final picker = find.byWidgetPredicate(
      (widget) =>
          widget is ProposalSelectField<String> && widget.title == '印花税 计算公式',
    );
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('收入 × 0.06%').last);
    await tester.pumpAndSettle();
    expect((form['taxCostItemFormulas'] as Map)['印花税'], 'TAX_STAMP_REVENUE');
    expect(proposalEvaluateFinance(form).total(kProposalCostCategoryTax), 1.2);
    expect(
      tester.widget<ProposalSelectField<String>>(picker).value,
      'TAX_STAMP_REVENUE',
    );
  });

  for (final updatedEstimate in [false, true]) {
    testWidgets(
      'desktop stamp picker uses current estimate despite cached options, updated estimate: $updatedEstimate',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final oldCatalog = _legacyCatalog();
        final evaluation = proposalEvaluateFinance(
          _form(),
          catalog: updatedEstimate ? catalog : oldCatalog,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ProposalFinanceCostPanel(
                  mode: ProposalFinanceCostPanelMode.cost,
                  config: ProposalFinanceBoardConfig(
                    catalog: oldCatalog,
                    evaluation: evaluation,
                    products: evaluation.products,
                    categoryEditable: const {kProposalCostCategoryTax: true},
                    focusKeys: const {'taxCost'},
                    showEstimates: false,
                    onCostFormula: (_, _, _, _) {},
                  ),
                ),
              ),
            ),
          ),
        );
        final picker = find.byWidgetPredicate(
          (widget) =>
              widget is ProposalSelectField<String> &&
              widget.title == '印花税 计算公式',
        );
        expect(picker, findsOneWidget);
        final field = tester.widget<ProposalSelectField<String>>(picker);
        expect(
          field.options.map((option) => option.value),
          updatedEstimate
              ? ['TAX_STAMP_SCALE', 'TAX_STAMP_REVENUE']
              : ['TAX_STAMP_SCALE'],
        );
        expect(
          find.textContaining('暂未获取到按收入计算的公式'),
          updatedEstimate ? findsNothing : findsOneWidget,
        );
      },
    );
  }

  testWidgets('read-only stamp tax does not expose a formula picker', (
    tester,
  ) async {
    final evaluation = proposalEvaluateFinance(_form());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProposalFinanceCostPanel(
              mode: ProposalFinanceCostPanelMode.result,
              config: ProposalFinanceBoardConfig(
                catalog: catalog,
                evaluation: evaluation,
                categoryEditable: const {kProposalCostCategoryTax: true},
                focusKeys: const {'taxCost'},
                showEstimates: false,
                onCostFormula: (_, _, _, _) =>
                    fail('read-only formula changed'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ProposalSelectField<String> && widget.title == '印花税 计算公式',
      ),
      findsNothing,
    );
    expect(find.text('销售规模 × 0.06%'), findsOneWidget);
  });
}
