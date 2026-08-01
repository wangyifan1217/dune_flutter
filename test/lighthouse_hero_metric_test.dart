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

  test('hero financial board balances four sections across three columns', () {
    expect(
      lighthouseHeroVerticalSections.map((section) => section.title).toList(),
      ['规模', '成本', '经营性现金流', '利润'],
    );
    expect(lighthouseHeroColumnSectionKeys, [
      ['scale'],
      ['cost'],
      ['cash', 'profit'],
    ]);
    expect(lighthouseHeroVerticalSections[0].metricKeys, [
      'sales',
      'verifiedSales',
      'gmv',
    ]);
    expect(lighthouseHeroVerticalSections[1].metricKeys, [
      'totalCost',
      'projectCost',
      'cost',
      'directCost',
    ]);
    expect(lighthouseHeroVerticalSections[2].metricKeys, ['prepaid']);
    expect(lighthouseHeroVerticalSections[3].metricKeys, [
      'profit',
      'netProfit',
      'revenue',
      'spread',
      'grossMargin',
      'rate',
    ]);
  });

  test('ledger rows show four focused metrics in a neutral 2x2 grid', () {
    expect(lighthouseLedgerSummaryColumns, 2);
    expect(lighthouseLedgerNameFontSize, 11.5);
    expect(lighthouseLedgerPinnedWidthRatio, 0.35);
    expect(lighthouseLedgerPinnedMaxWidth, 164);
    expect(lighthouseLedgerSummaryMetricKeys, [
      'sales',
      'verifiedSales',
      'profit',
      'costTotal',
    ]);
    expect(lighthouseLedgerSummaryMetricRows, [
      ['sales', 'verifiedSales'],
      ['profit', 'costTotal'],
    ]);
  });

  test('ledger navigation uses three distinct professional control levels', () {
    expect(lighthouseLedgerNavigationLevels, [
      'primaryTab',
      'filterChip',
      'subSegment',
    ]);
    expect(lighthouseLedgerPrimaryTabHeight, 44);
    expect(lighthouseLedgerFilterRowHeight, 42);
    expect(lighthouseLedgerFilterChipRadius, 8);
    expect(lighthouseLedgerCentersPrimaryDimensions, isFalse);
    expect(lighthouseLedgerPrimaryDimensionsFillAvailableWidth, isTrue);
    expect(lighthouseLedgerSeparatesAnalysisTab, isTrue);
    expect(lighthouseLedgerUsesLavenderPanelFrame, isTrue);
    expect(lighthouseLedgerPanelBorderWidth, 0.8);
    expect(lighthouseLedgerPanelRadius, 12);
    expect(lighthouseLedgerPanelShadowBlur, 12);
  });

  test('period selector uses a floating rounded segmented control', () {
    expect(lighthousePeriodUsesFloatingSegment, isTrue);
    expect(lighthousePeriodTrackHeight, 44);
    expect(lighthousePeriodTrackRadius, 12);
    expect(lighthousePeriodSelectedRadius, 8);
    expect(lighthousePeriodStatusDotSize, 4);
    expect(lighthousePeriodAnimationMs, 180);
  });

  test('lighthouse header uses refined chrome without LIVE metadata', () {
    expect(lighthouseAppBarTitleFontSize, 18);
    expect(lighthouseAppBarEnglishFontSize, 8.5);
    expect(lighthouseAppBarToolbarHeight, 34);
    expect(lighthouseAppBarToolbarRadius, 11);
    expect(lighthouseHeroShowsLiveMetadata, isFalse);
    expect(lighthouseHeroSummaryTitleFontSize, 13.5);
    expect(lighthouseHeroSummaryIconSize, 20);
    expect(lighthouseHeroSummaryIconRadius, 6);
    expect(lighthouseHeroSummaryIconKey('产品汇总'), 'product');
    expect(lighthouseHeroSummaryIconKey('供给方汇总'), 'supply');
    expect(lighthouseHeroSummaryIconKey('渠道汇总'), 'channel');
    expect(lighthouseHeroSummaryIconKey('分析总览'), 'analysis');
    expect(lighthouseHeroSummaryIconKey('某产品详情'), 'overview');
  });

  test('category chips resolve official brand logos with generic fallback', () {
    expect(lighthouseCategoryBrandAsset('中石油'), 'assets/brands/petrochina.svg');
    expect(lighthouseCategoryBrandAsset('中石化'), 'assets/brands/sinopec.svg');
    expect(lighthouseCategoryBrandAsset('平安'), 'assets/brands/ping_an.svg');
    expect(
      lighthouseCategoryBrandAsset('中国移动'),
      'assets/brands/china_mobile.svg',
    );
    expect(
      lighthouseCategoryBrandAsset('中国电信'),
      'assets/brands/china_telecom.svg',
    );
    expect(
      lighthouseCategoryBrandAsset('中国联通'),
      'assets/brands/china_unicom.svg',
    );
    expect(lighthouseCategoryBrandAsset('银联'), 'assets/brands/unionpay.svg');
    expect(lighthouseCategoryBrandAsset('民营'), isNull);
    expect(lighthouseCategoryLogoSize, 14);
  });

  test('compact hero keeps KPI and trend side by side', () {
    expect(lighthouseCompactHeroKpiFlex, 3);
    expect(lighthouseCompactHeroTrendFlex, 7);
    expect(lighthouseCompactHeroSparkHeight, 92);
    expect(lighthouseCompactHeroMetricGap, 6);
    expect(lighthouseHeroUsesCategoryTint, isFalse);
    expect(lighthouseHeroUsesAccentRail, isFalse);
    expect(lighthouseHeroShowsEnglishKicker, isFalse);
    expect(lighthouseHeroUsesCardShadow, isTrue);
    expect(lighthouseHeroMetricUsesSansLabel, isTrue);
    expect(lighthouseHeroCardRadius, 10);
    expect(lighthouseHeroCardGap, 8);
    expect(lighthouseHeroCardPadding, 8);
    expect(lighthouseHeroChartUsesCardSurface, isTrue);
    expect(lighthouseHeroChartCardPadding, 6);
    expect(lighthouseHeroSparkShowsAxes, isFalse);
    expect(lighthouseHeroSparkShowsGrid, isFalse);
    expect(lighthouseHeroSparkShowsAverage, isFalse);
    expect(lighthouseHeroSparkShowsEveryPeriodLabel, isTrue);
    expect(lighthouseHeroSparkShowsEveryValue, isTrue);
    expect(lighthouseHeroCompactPeriodLabel('2026.08'), '08月');
    expect(lighthouseHeroCompactPeriodLabel('2026-02'), '02月');
    expect(lighthouseHeroCompactPeriodLabel('08.01'), '08.01');
    expect(lighthouseHeroSectionIconSize, 18);
    expect(lighthouseHeroSectionIconKeys, {
      'scale': 'monitoring',
      'cost': 'receipt',
      'cash': 'wallet',
      'profit': 'trendingUp',
    });
    expect(lighthouseHeroSectionAccentValues.keys, {
      'scale',
      'cost',
      'cash',
      'profit',
    });
    expect(lighthouseHeroShowsSectionAccentDash, isFalse);
    expect(lighthouseHeroMastheadLabelAboveNumber, isTrue);
    expect(lighthouseHeroMastheadLabelFontSize, 11);
    expect(lighthouseHeroMastheadLabelIconSize, 18);
    expect(lighthouseHeroMastheadLabelRadius, 8);
    expect(lighthouseHeroGroupTitleFontSize, 10);
    expect(lighthouseHeroMastheadFontSize, 29);
    expect(lighthouseHeroMetricValueFontSize, 13);
    expect(lighthouseHeroMetricLabelFontSize, 9);
    expect(lighthouseHeroMetricDeltaFontSize, 8);
    expect(
      [
        lighthouseHeroScaleColumnFlex,
        lighthouseHeroCostColumnFlex,
        lighthouseHeroResultColumnFlex,
      ],
      [9, 14, 16],
    );
  });

  test('ledger highlight tool has one compact label for each mode', () {
    expect(
      lighthouseLedgerHighlightModeLabel(rowMode: false, cellMode: false),
      '标记',
    );
    expect(
      lighthouseLedgerHighlightModeLabel(rowMode: true, cellMode: false),
      '行标记',
    );
    expect(
      lighthouseLedgerHighlightModeLabel(rowMode: false, cellMode: true),
      '格标记',
    );
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
