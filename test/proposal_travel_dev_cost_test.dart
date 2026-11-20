import 'package:dunes_app/features/proposal_intake/proposal_cost_estimate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('应付出行-开发费累加全部18条独立结算', () {
    final prices = [
      500000,
      100000,
      600000,
      760000,
      300000,
      50000,
      223000,
      200000,
      200000,
      450000,
      200000,
      1200000,
      800000,
      250000,
      200000,
      600000,
      300000,
      95000,
    ];
    final form = <String, dynamic>{
      'salesScale': '1352.5',
      'productScaleManual': true,
      'skuDetails': [
        {
          'id': 'sku-1',
          'productName': '出行项目',
          'faceValue': '13525000',
          'annualScale': '1352.5',
          'settlements': [
            for (var i = 0; i < prices.length; i++)
              {
                'id': 'dev-$i',
                'kind': 'cost',
                'billType': '应付出行-开发费',
                'priceMode': 'unit',
                'settleUnitPrice': '${prices[i]}',
                'formula': '按核销统计结算单价',
                'taxRate': '6%',
              },
          ],
        },
      ],
    };
    expect(
      proposalPayableProjectCostHits(form, costNames: ['应付出行-开发费']).length,
      18,
    );
    expect(
      proposalEstimateProjectCostAmount(
        form,
        '应付出行-开发费',
        costNames: ['应付出行-开发费'],
      ),
      closeTo(702.8, 0.001),
    );
  });

  for (final name in ['应付出行-开发费', '平台交易服务费']) {
    test('$name 独立结算范围与共享结算优先规则', () {
      Map<String, dynamic> row(String id) => {
        'id': id,
        'kind': 'cost',
        'billType': name,
        'settleRatio': '10%',
      };
      final form = <String, dynamic>{
        'salesScale': '100',
        'skuDetails': [
          {
            'id': 'sku-1',
            'productName': '项目',
            'settlements': [row('one'), row('two'), row('one')],
          },
        ],
      };
      final want = name == '应付出行-开发费' ? 2 : 1;
      expect(
        proposalPayableProjectCostHits(form, costNames: [name]).length,
        want,
      );
      form['sharedSettlements'] = [
        {
          'skuIds': ['sku-1'],
          ...row('shared-terms'),
          'id': 'shared-one',
        },
      ];
      expect(proposalPayableProjectCostHits(form, costNames: [name]).length, 1);
      (form['sharedSettlements'] as List).add({
        'skuIds': ['sku-1'],
        ...row('shared-other'),
        'id': 'shared-two',
      });
      expect(
        proposalPayableProjectCostHits(form, costNames: [name]).length,
        want,
      );
    });
  }
}
