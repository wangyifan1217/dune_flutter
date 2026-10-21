import 'package:dunes_app/features/proposal_intake/proposal_estimate_audit.dart';
import 'package:dunes_app/features/proposal_intake/proposal_remote_finance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _evaluation({
  required double scale,
  required double revenue,
  required double coupon,
  List<Map<String, dynamic>> products = const [],
}) => {
  'salesScale': scale,
  'revenue': {'name': '收入', 'amount': revenue, 'substitution': '8000 × 0.98 − 用券成本 $coupon'},
  'procurement': {'name': '用券成本', 'amount': coupon},
  'buckets': {
    'project': {
      'category': {'key': 'project', 'name': '项目成本'},
      'lines': [
        {'name': '推广费', 'amount': 0, 'pending': true, 'missing': ['计算公式']},
      ],
      'total': 0,
    },
    'tax': {
      'category': {'key': 'tax', 'name': '税务成本'},
      'lines': [
        {'name': '印花税', 'amount': 2.4, 'substitution': '8000 × 0.0003'},
      ],
      'total': 2.4,
    },
  },
  'profit': revenue - 2.4,
  'summary': {'formulaVersion': 'proposal-finance-v1', 'costTotal': 2.4, 'spread': revenue - 2.4, 'monthlyScale': scale / 12},
  'products': products,
};

void main() {
  testWidgets('audit shows every step and flags a coupon cost that eats the revenue', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sku = {
      'id': 'sku-1',
      'productName': '中石油现金券',
      'faceValue': '200',
      'settlements': [
        {'id': 'in-1', 'kind': 'income', 'settleRatio': '0.98', 'formula': '核销面值*结算比例'},
        {'id': 'in-1-coupon', 'kind': 'cost', 'billType': '券使用成本', 'settleRatio': '0.97'},
      ],
    };
    final product = {
      'sku': sku,
      'owner': 'main',
      'evaluation': _evaluation(scale: 8000, revenue: 80, coupon: 7760),
    };
    final result = ProposalRemoteFinanceResult.fromJson({
      'engineVersion': 'proposal-finance-v1',
      'main': _evaluation(scale: 8000, revenue: 80, coupon: 7760, products: [product]),
      'total': _evaluation(scale: 8000, revenue: 80, coupon: 7760, products: [product]),
      'settlements': {
        'sku-1:in-1': {'scale': 8000, 'share': 0.98, 'amount': 7840, 'perUnit': 196, 'substitution': '8000 × 0.98 = 7840 万元/年'},
        'sku-1:in-1-coupon': {'scale': 8000, 'share': 0.97, 'amount': 7760, 'perUnit': 194, 'substitution': '8000 × 0.97 = 7760 万元/年'},
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProposalEstimateAudit(
            result: result,
            form: {'skuDetails': [sku]},
            title: '中石油现金券-北京中抚',
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    for (final title in ['自动核对', '规模', '每条结算', '收入', '成本', '汇总']) {
      expect(find.text(title), findsWidgets);
    }
    expect(find.textContaining('用券成本占结算收入'), findsOneWidget);
    expect(find.textContaining('行没算完整'), findsOneWidget);
    expect(find.text('8000 × 0.97 = 7760 万元/年'), findsOneWidget);

    // 测算合计「算法」按指标分开：点收入看收入，点成本看成本。
    final steps = proposalEstimateCalcSteps(result, {'skuDetails': [sku]});
    expect(steps.keys, containsAll(['年化规模', '收入', '成本', '月均规模', '周转资金']));
    final income = steps['收入']!.firstWhere((s) => s.label == '收入');
    expect(income.formula, '结算收入 7,840 − 用券成本 7,760');
    expect(income.warn, isTrue);
    expect(steps['成本']!.last.label, '成本');
    expect(steps['成本']!.any((s) => s.label.contains('印花税')), isTrue);
    expect(steps['年化规模']!.last.value, '8,000');
    // 每一行点开能看到怎么算的：没填规模的产品按平摊，结算 = 规模 × 份额。
    final productScale = steps['年化规模']!.first;
    expect(productScale.formula, '平摊');
    expect(productScale.detail, contains('÷ 没填规模的 1 个产品 = 8,000 万'));
    // 收入按产品列（和后端每个产品的收入一致），点开有这个产品每条结算怎么算。
    final productRevenue = steps['收入']!.first;
    expect(productRevenue.label, '中石油现金券');
    expect(productRevenue.value, '7,840');
    expect(productRevenue.detail, contains('结算比例 0.98，即 98%'));
    expect(productRevenue.detail, contains('8000 × 0.98 = 7840 万元/年'));
    expect(steps['成本']!.every((s) => s.detail.isNotEmpty), isTrue);
  });
}
