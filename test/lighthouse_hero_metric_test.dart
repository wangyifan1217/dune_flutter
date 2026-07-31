import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_hero_metric.dart';

void main() {
  group('lighthouseHeroMastheadKey', () {
    test('always returns profit', () {
      expect(lighthouseHeroMastheadKey(null), 'profit');
      expect(lighthouseHeroMastheadKey(''), 'profit');
      expect(lighthouseHeroMastheadKey('verifiedSales'), 'profit');
      expect(lighthouseHeroMastheadKey('grossMargin'), 'profit');
      expect(lighthouseHeroMastheadKey('rate'), 'profit');
    });
  });

  group('lighthouseHeroMetricValue', () {
    test('reads verifiedSales from totals', () {
      final totals = <String, double>{
        'profit': 23200,
        'verifiedSales': 7388000,
        'revenue': 24100,
      };
      expect(lighthouseHeroMetricValue(totals, 'verifiedSales'), 7388000);
      expect(lighthouseHeroMetricValue(totals, 'profit'), 23200);
    });

    test('aliases costTotal / businessCost', () {
      expect(lighthouseHeroMetricValue({'costTotal': 1}, 'totalCost'), 1);
      expect(lighthouseHeroMetricValue({'businessCost': 2}, 'cost'), 2);
    });
  });

  group('lighthouseHeroMetricLabel', () {
    test('totalCost / costTotal both render 成本合计', () {
      expect(lighthouseHeroMetricLabel('totalCost'), '成本合计');
      expect(lighthouseHeroMetricLabel('costTotal'), '成本合计');
    });
  });

  group('lighthouseHeroMetricPeriodLabel', () {
    test('builds 本日核销额 / 本日毛利润', () {
      expect(lighthouseHeroMetricPeriodLabel('day', 'verifiedSales'), '本日核销额');
      expect(lighthouseHeroMetricPeriodLabel('day', 'profit'), '本日毛利润');
      expect(lighthouseHeroMetricPeriodLabel('month', 'sales'), '本月销售额');
    });
  });

  group('lighthouseHeroMetricIsRate', () {
    test('marks rate metrics', () {
      expect(lighthouseHeroMetricIsRate('rate'), isTrue);
      expect(lighthouseHeroMetricIsRate('grossMargin'), isTrue);
      expect(lighthouseHeroMetricIsRate('verifiedSales'), isFalse);
    });
  });

  test('hero financial board uses three vertical columns', () {
    expect(
      lighthouseHeroVerticalSections.map((section) => section.title).toList(),
      ['规模', '利润', '经营性现金流'],
    );
    expect(lighthouseHeroVerticalSections[0].metricKeys, [
      'sales',
      'verifiedSales',
      'gmv',
    ]);
    expect(lighthouseHeroVerticalSections[1].metricKeys, [
      'profit',
      'netProfit',
      'revenue',
      'spread',
      'totalCost',
      'projectCost',
      'cost',
      'directCost',
      'grossMargin',
      'rate',
    ]);
    expect(lighthouseHeroVerticalSections[2].metricKeys, ['prepaid']);
  });

  test('compact hero keeps KPI and trend side by side', () {
    expect(lighthouseCompactHeroKpiFlex, 3);
    expect(lighthouseCompactHeroTrendFlex, 7);
    expect(lighthouseCompactHeroSparkHeight, 92);
    expect(lighthouseCompactHeroMetricGap, 8);
  });

  group('lighthouseHeroAxisTicks', () {
    test('returns bottom middle top ticks', () {
      expect(lighthouseHeroAxisTicks([20, 40, 80]), [20, 50, 80]);
    });

    test('adds a visible range for flat data', () {
      final ticks = lighthouseHeroAxisTicks([100, 100]);
      expect(ticks.length, 3);
      expect(ticks.first, lessThan(100));
      expect(ticks.last, greaterThan(100));
    });
  });

  group('lighthouseLedgerHighlightKey', () {
    test('is stable for the same business row', () {
      final row = <String, dynamic>{
        'name': '中石油',
        'group': '能源',
        'supplierProductCode': 'CNPC-001',
      };
      expect(
        lighthouseLedgerHighlightKey('supply', row),
        lighthouseLedgerHighlightKey('supply', Map.of(row)),
      );
    });

    test('separates tabs and business identities', () {
      final row = <String, dynamic>{'name': '中石油', 'group': '能源'};
      expect(
        lighthouseLedgerHighlightKey('product', row),
        isNot(lighthouseLedgerHighlightKey('supply', row)),
      );
      expect(
        lighthouseLedgerHighlightKey('supply', row),
        isNot(
          lighthouseLedgerHighlightKey('supply', {
            'name': '中石油',
            'group': '运营商',
          }),
        ),
      );
    });
  });

  group('lighthouseLedgerCellHighlightKey', () {
    final row = <String, dynamic>{
      'name': '中石化现金券',
      'group': '能源',
      'supplierProductCode': 'SINOPEC-001',
    };

    test('is stable for the same row and metric', () {
      expect(
        lighthouseLedgerCellHighlightKey('product', row, 'revenue'),
        lighthouseLedgerCellHighlightKey('product', Map.of(row), 'revenue'),
      );
    });

    test('separates metrics in the same row', () {
      expect(
        lighthouseLedgerCellHighlightKey('product', row, 'revenue'),
        isNot(lighthouseLedgerCellHighlightKey('product', row, 'totalCost')),
      );
    });
  });

  group('lighthouseHeroSparkLabelIndices', () {
    test('returns every data point index', () {
      expect(lighthouseHeroSparkLabelIndices(0), isEmpty);
      expect(lighthouseHeroSparkLabelIndices(1), [0]);
      expect(lighthouseHeroSparkLabelIndices(7), [0, 1, 2, 3, 4, 5, 6]);
    });
  });

  group('lighthouseDetailPeriodCacheKey', () {
    test('write and stale-check formats match', () {
      final key = lighthouseDetailPeriodCacheKey(
        period: 'month',
        periodOffset: 0,
      );
      expect(key, 'month:0::');
      expect(
        lighthouseDetailPeriodCacheKey(period: 'month', periodOffset: 0),
        key,
      );
    });

    test('includes custom range', () {
      final start = DateTime.utc(2026, 7, 1);
      final end = DateTime.utc(2026, 7, 31);
      expect(
        lighthouseDetailPeriodCacheKey(
          period: 'custom',
          periodOffset: 0,
          customStart: start,
          customEnd: end,
        ),
        'custom:0:${start.toIso8601String()}:${end.toIso8601String()}',
      );
    });
  });

  group('lighthouseRestoreScrollOffset', () {
    test('keeps in-range offset', () {
      expect(lighthouseRestoreScrollOffset(320, 1000), 320);
    });

    test('clamps above max and rejects invalids', () {
      expect(lighthouseRestoreScrollOffset(1500, 800), 800);
      expect(lighthouseRestoreScrollOffset(-10, 800), 0);
      expect(lighthouseRestoreScrollOffset(40, -1), 0);
    });
  });

  group('lighthouse trend metric formulas', () {
    test('rate denominator must be positive and above display threshold', () {
      expect(lighthouseValidRateBase(50), 50);
      expect(lighthouseValidRateBase(49.99), 0);
      expect(lighthouseValidRateBase(-100), 0);
    });

    test('gross margin uses verified sales, not revenue', () {
      expect(
        lighthouseGrossMarginSeries(
          profit: [20, 30],
          verifiedSales: [100, 200],
        ),
        [20, 15],
      );
    });

    test('direct cost is total minus project and business cost', () {
      expect(
        lighthouseDirectCostSeries(
          totalCost: [100, 80],
          projectCost: [20, 10],
          businessCost: [5, 4],
        ),
        [75, 66],
      );
    });
  });

  group('lighthouse cross-level trend isolation', () {
    test('L3 never falls back to L2 trend', () {
      expect(lighthouseCanFallbackToRootTrend(isDrill: false), isTrue);
      expect(lighthouseCanFallbackToRootTrend(isDrill: true), isFalse);
    });

    test('detail totals never reuse L1 comparison line', () {
      expect(lighthouseCanUseRootComparison(hasTotalsOverride: false), isTrue);
      expect(lighthouseCanUseRootComparison(hasTotalsOverride: true), isFalse);
    });

    test('period delta is never inferred from trend points', () {
      expect(lighthouseCanInferPeriodDeltaFromTrend(), isFalse);
    });
  });

  group('lighthouseResolvePreferredGroup', () {
    test('keeps preferred when present', () {
      expect(
        lighthouseResolvePreferredGroup(
          preferred: '中石油',
          options: const ['全部', '中石油', '运营商'],
        ),
        '中石油',
      );
    });

    test('falls back to 全部 when preferred missing on day supply', () {
      expect(
        lighthouseResolvePreferredGroup(
          preferred: '中石油',
          options: const ['全部', '运营商', '出行权益金'],
        ),
        '全部',
      );
    });
  });
}
