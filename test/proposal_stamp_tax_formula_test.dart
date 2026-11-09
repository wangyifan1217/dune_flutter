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
}
