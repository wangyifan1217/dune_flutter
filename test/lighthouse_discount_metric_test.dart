import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_discount_metric.dart';

void main() {
  test('折扣率小数按百分比展示', () {
    expect(lighthouseDiscountRateLabel(0.03), '3%');
    expect(lighthouseDiscountRateLabel(0.025), '2.5%');
    expect(lighthouseDiscountRateLabel(0.0001), '0.01%');
    expect(lighthouseDiscountRateLabel(null), '—');
  });

  test('calc_record 账期时间压缩为月日区间', () {
    expect(
      lighthouseDiscountDateRange(
        '2026-07-01T00:00:00+08:00',
        '2026-07-31T00:00:00+08:00',
      ),
      '07.01–07.31',
    );
    expect(lighthouseDiscountDateRange(null, null), null);
  });

  test('折扣区直接吃 discounts map，不依赖供给行挂载', () {
    final rows = lighthouseDiscountRowsFromMap({
      '山西': {
        'currentCumSales': 1500000,
        'rebate': 20000,
        'discountRate': 0.02,
        'calcMode': 1,
        'base': '核销额',
        'mode': '超额累进',
        'province': '山西',
      },
    });
    expect(rows, hasLength(1));
    expect(rows.first['province'], '山西');
    expect(rows.first['rebate'], 20000);
  });
}
