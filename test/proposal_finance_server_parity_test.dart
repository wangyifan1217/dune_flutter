import 'dart:convert';
import 'dart:io';
import 'package:dunes_app/features/proposal_intake/proposal_finance_formula.dart';
import 'package:flutter_test/flutter_test.dart';
import 'proposal_finance_formula_mock_test.dart' show mockProposal;

Map<String, Object?> amounts(ProposalFinanceEvaluation e) => {
  'scale': e.salesScale, 'revenue': e.revenue.amount, 'profit': e.profit,
  'project': e.total('project'), 'business': e.total('business'), 'tax': e.total('tax'),
  'products': [for (final p in e.products) amounts(p.evaluation)],
};

void main() {
  test('export repeatable baseline for server migration', () {
    final cases = <Map<String, Object?>>[];
    for (final g in ProposalFinanceFormulaCatalog.fallback.revenueGroups) {
      for (final formula in g.formulas) {
        final form = mockProposal(revenueGroup: g.key, revenueFormula: formula.code);
        cases.add({'name': '${g.key}/${formula.code}', 'form': form,
          'expected': amounts(proposalEvaluateFinance(form))});
      }
    }
    for (final redacted in [false, true]) {
      final form = {...mockProposal(), 'businessCostRedacted': redacted};
      cases.add({'name': 'redacted/$redacted', 'form': form,
        'expected': amounts(proposalEvaluateFinance(form))});
    }
    for (final mode in ['whole', 'excess']) {
      final form = Map<String, dynamic>.from(jsonDecode(jsonEncode(mockProposal())) as Map);
      final sku = (form['skuDetails'] as List).single as Map;
      (sku['settlements'] as List).add({
        'id': 'tier', 'kind': 'cost', 'billType': '推广费', 'settleMode': '按阶梯价格', 'priceMode': 'tier',
        'tierPlans': [{'strategy': 'annual', 'segments': [{'mode': mode, 'tiers': [
          {'from': 0, 'rate': 0.01}, {'from': 300, 'rate': 0.02},
        ]}]}],
      });
      cases.add({'name': 'tiers/$mode', 'form': form,
        'expected': amounts(proposalEvaluateFinance(form))});
    }
    final path = Platform.environment['PROPOSAL_PARITY_OUTPUT'];
    if (path != null) File(path).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(cases));
    expect(cases.length, greaterThan(10));
  });
}
