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
      ['规模', '成本', '经营性净现金流', '利润'],
    );
    expect(lighthouseHeroColumnSectionKeys, [
      ['scale'],
      ['cost', 'cash'],
      ['profit'],
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
    expect(lighthouseLedgerNameFontSize, 12.5);
    expect(lighthouseLedgerValueFontSize, 11.5);
    expect(lighthouseLedgerMetricLabelFontSize, 10);
    expect(lighthouseLedgerDeltaFontSize, 9);
    expect(lighthouseLedgerPinnedWidthRatio, 0.35);
    expect(lighthouseLedgerPinnedMaxWidth, 164);
    expect(lighthouseLedgerShowsShareWash, isFalse);
    expect(lighthouseLedgerCollapsedShowsShare, isFalse);
    expect(lighthouseLedgerCollapsedShowsSparkline, isFalse);
    expect(lighthouseLedgerCollapsedShowsGroup, isFalse);
    expect(lighthouseLedgerCollapsedShowsGrossMargin, isTrue);
    expect(lighthouseLedgerSummaryMetricTone('prepaid'), 'cash');
    expect(lighthouseLedgerSummaryMetricTone('profit'), 'profit');
    expect(lighthouseLedgerSummaryMetricTone('sales'), 'neutral');
    // v18: 展开箭头移到冻结列最后一行，不再靠 Transform 偏移躲开穿透箭头。
    expect(lighthouseLedgerExpandArrowVerticalOffset, 3);
    expect(lighthouseLedgerExpandArrowLayoutHeight, 14);
    expect(lighthouseLedgerSummaryMetricKeys, [
      'sales',
      'verifiedSales',
      'prepaid',
      'profit',
      'costTotal',
    ]);
    expect(lighthouseLedgerSummaryMetricRows, [
      ['sales', 'verifiedSales'],
      ['costTotal', 'profit'],
    ]);
    expect(lighthouseLedgerSummaryMetricRowsForTab('supply'), [
      ['sales', 'verifiedSales'],
      ['costTotal', 'profit'],
    ]);
    expect(lighthouseLedgerSummaryMetricRowsForTab('channel'), [
      ['sales', 'verifiedSales'],
      ['costTotal', 'profit'],
    ]);
    expect(lighthouseLedgerSummaryMetricRowsForTab('product'), [
      ['sales', 'prepaid'],
      ['verifiedSales', 'profit'],
    ]);
  });

  test('channel detail removes the redundant province column', () {
    expect(lighthouseChannelDetailIncludesProvince, isFalse);
  });

  test('channel root removes the province category row', () {
    expect(lighthouseChannelRootIncludesProvinceFilter, isFalse);
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
    expect(lighthouseHeroSummaryIconKey('产品 · 中石油现金券'), 'product');
    expect(lighthouseHeroSummaryIconKey('供给 · 广东省'), 'supply');
    expect(lighthouseHeroSummaryIconKey('渠道 · 产险'), 'channel');
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
    expect(lighthouseHeroCategoryLogoSize, 18);
  });

  test('L1 hero shows category logo only when a concrete group is selected', () {
    expect(lighthouseHeroShowsCategoryLogo('全部'), isFalse);
    expect(lighthouseHeroShowsCategoryLogo(''), isFalse);
    expect(lighthouseHeroShowsCategoryLogo('中石油'), isTrue);
    expect(lighthouseHeroShowsCategoryLogo('能源'), isTrue);
    expect(lighthouseHeroShowsCategoryLogo('平安'), isTrue);
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
      [10, 14, 15],
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

    test('absurd rate pct from tiny denominator is not displayable', () {
      // 毛利 41.23 万 / 核销 0.01 万 ≈ 515415%，应显示 —
      expect(lighthouseDisplayRatePct(515415.2), isNull);
      expect(lighthouseDisplayRatePct(1000), 1000);
      expect(lighthouseDisplayRatePct(12.5), 12.5);
      expect(lighthouseDisplayRatePct(double.infinity), isNull);
    });

    test('normal product margins remain displayable', () {
      expect(
        lighthouseGrossMarginDisplayPct(
          profit: 1178648.1,
          verifiedSales: 2134816.5,
        ),
        closeTo(55.21, 0.1),
      );
      expect(
        lighthouseGrossMarginDisplayPct(
          profit: 345451.0,
          verifiedSales: 19014700,
        ),
        closeTo(1.82, 0.1),
      );
      expect(
        lighthouseGrossMarginDisplayPct(profit: 412262, verifiedSales: 80),
        isNull,
      );
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

    test('gross margin series zeros out absurd magnified rates', () {
      expect(
        lighthouseGrossMarginSeries(
          profit: [412300],
          verifiedSales: [80],
        ),
        [0],
      );
    });

  });

  group('lighthouse cross-level trend isolation', () {
    test('L3 never falls back to L2 trend', () {
      // L3 必须用 detail 接口下发的 drill.trend；禁止串父级折线。
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

  group('lighthouseLedgerValueWeightValue', () {
    test('summary and sorted numbers are bold', () {
      expect(
        lighthouseLedgerValueWeightValue(missing: false, emphasized: true),
        700,
      );
      expect(
        lighthouseLedgerValueWeightValue(missing: false, emphasized: false),
        600,
      );
      expect(
        lighthouseLedgerValueWeightValue(missing: true, emphasized: true),
        500,
      );
    });
  });

  group('lighthouseLedgerDeltaIsFavorable', () {
    test('规模 / 利润 / 现金流：跌为坏，涨为好', () {
      for (final key in ['sales', 'verifiedSales', 'profit', 'prepaid']) {
        expect(
          lighthouseLedgerDeltaIsFavorable(key, -86.0),
          isFalse,
          reason: key,
        );
        expect(
          lighthouseLedgerDeltaIsFavorable(key, 19.0),
          isTrue,
          reason: key,
        );
      }
    });

    test('成本类：跌为好，涨为坏', () {
      for (final key in lighthouseLedgerLowerIsBetterKeys) {
        expect(
          lighthouseLedgerDeltaIsFavorable(key, -12.0),
          isTrue,
          reason: key,
        );
        expect(
          lighthouseLedgerDeltaIsFavorable(key, 12.0),
          isFalse,
          reason: key,
        );
      }
    });

    test('毛利率跟随「越高越好」', () {
      expect(lighthouseLedgerDeltaIsFavorable('grossMargin', 2.0), isTrue);
      expect(lighthouseLedgerDeltaIsFavorable('grossMargin', -2.0), isFalse);
    });

    test('空值与阈值内的抖动走中性色', () {
      expect(lighthouseLedgerDeltaIsFavorable('sales', null), isNull);
      expect(lighthouseLedgerDeltaIsFavorable('sales', 0.0), isNull);
      expect(lighthouseLedgerDeltaIsFavorable('sales', 0.04), isNull);
      expect(lighthouseLedgerDeltaIsFavorable('sales', -0.04), isNull);
      expect(lighthouseLedgerDeltaIsFavorable('sales', 0.05), isTrue);
    });
  });

  group('lighthouseLedgerSummaryTitle', () {
    test('标题随实际列数变化', () {
      expect(lighthouseLedgerSummaryTitle(4), '四项核心指标');
      expect(lighthouseLedgerSummaryTitle(3), '三项核心指标');
      expect(lighthouseLedgerSummaryTitle(2), '二项核心指标');
    });
  });

  group('结果区分块', () {
    test('现金流与毛利润是结果指标，规模与成本不是', () {
      expect(lighthouseLedgerIsResultMetric('prepaid'), isTrue);
      expect(lighthouseLedgerIsResultMetric('profit'), isTrue);
      expect(lighthouseLedgerIsResultMetric('sales'), isFalse);
      expect(lighthouseLedgerIsResultMetric('verifiedSales'), isFalse);
      expect(lighthouseLedgerIsResultMetric('costTotal'), isFalse);
    });

    test('结果指标一律落在右列，区块才连得成一片', () {
      for (final tab in ['product', 'supply', 'channel']) {
        final flat = lighthouseLedgerSummaryMetricRowsForTab(
          tab,
        ).expand((r) => r).toList();
        for (var i = 0; i < flat.length; i++) {
          if (!lighthouseLedgerIsResultMetric(flat[i])) continue;
          expect(
            i % lighthouseLedgerSummaryColumns,
            lighthouseLedgerSummaryColumns - 1,
            reason: '$tab / ${flat[i]}',
          );
        }
      }
    });

    test('强调交给区块，数字不再单独上色', () {
      expect(lighthouseLedgerUsesResultBlock, isTrue);
      expect(lighthouseLedgerResultBlockKeepsMetricTint, isFalse);
      expect(lighthouseLedgerResultBlockRailWidth, 2);
      expect(lighthouseLedgerResultBlockTintAlpha, 12);
    });

    test('字号维持原状 —— 层级由分区承担，不放大数字', () {
      expect(lighthouseLedgerValueFontSize, 11.5);
      expect(lighthouseLedgerMetricLabelFontSize, 10);
    });
  });

  group('分组色条', () {
    test('分组文字关掉时色条也必须关掉（否则颜色无图例可解码）', () {
      expect(
        lighthouseLedgerCollapsedShowsGroupColorBar,
        lighthouseLedgerCollapsedShowsGroup,
      );
    });
  });
}
