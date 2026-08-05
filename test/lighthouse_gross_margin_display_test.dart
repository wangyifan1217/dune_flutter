import 'package:dunes_app/features/lighthouse/lighthouse_hero_metric.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors native_lighthouse_page gross-margin display gate.
double? rowGrossMarginDisplay(Map<String, dynamic> r) {
  final verified = (r['verifiedSales'] as num?)?.toDouble() ??
      (r['woa'] as num?)?.toDouble() ??
      0.0;
  final profit = (r['profit'] as num?)?.toDouble() ?? 0;
  return lighthouseGrossMarginDisplayPct(
    profit: profit,
    verifiedSales: verified,
  );
}

void main() {
  test('month product rows from live API shape show sensible margins', () {
    final rows = <Map<String, dynamic>>[
      {'name': '小套-出行会员', 'profit': 1178648.1, 'verifiedSales': 2134816.5, 'woa': 2134816.5},
      {'name': '小套-加油会员', 'profit': 412262.1463, 'verifiedSales': 80, 'woa': 80},
      {'name': '中石油现金券', 'profit': 345451.0847, 'verifiedSales': 19014700, 'woa': 19014700},
      {'name': '中石油返费', 'profit': 120442.69, 'verifiedSales': 13825109, 'woa': 13825109},
      {'name': '中石化现金券', 'profit': 62100.0, 'verifiedSales': 10462000, 'woa': 10462000},
    ];
    final out = {for (final r in rows) r['name'] as String: rowGrossMarginDisplay(r)};
    expect(out['小套-出行会员'], closeTo(55.21, 0.1));
    expect(out['小套-加油会员'], isNull); // absurd
    expect(out['中石油现金券'], closeTo(1.82, 0.1));
    expect(out['中石油返费'], closeTo(0.87, 0.1));
    expect(out['中石化现金券'], closeTo(0.59, 0.1));
  });
}
