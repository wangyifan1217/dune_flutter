import 'package:dunes_app/features/lighthouse/lighthouse_hero_metric.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('资管返利字段沿用接口正式名称', () {
    final rebate = lighthouseFundPoolFundsSection.metrics.singleWhere(
      (metric) => metric.key == 'endingReceivableRebate',
    );
    expect(rebate.label, '期末应收返利');
    expect(
      lighthouseFundPoolFormulaForKey('systemDifference')?.expression,
      '期末预付 − 可动用额度 − 券资产 − 期末应收返利',
    );
  });
}
