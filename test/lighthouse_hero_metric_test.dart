import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_data.dart';
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
      expect(lighthouseHeroMetricPeriodLabel('day', 'netTa'), '本日净TA');
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

  test('hero metric expand shows all trend charts without formulas', () {
    expect(lighthouseHeroShowsMetricFormulas, isFalse);
    expect(lighthouseHeroShowsAllMetricTrends, isFalse);
    expect(lighthouseHeroMetricIsOverlay('profit'), isTrue);
    expect(lighthouseHeroMetricIsOverlay('revenue'), isTrue);
    expect(lighthouseHeroMetricIsOverlay('totalCost'), isTrue);
    expect(lighthouseHeroMetricIsOverlay('sales'), isTrue);
    expect(lighthouseHeroMetricIsOverlay('verifiedSales'), isTrue);
    expect(lighthouseHeroMetricIsOverlay('gmv'), isFalse);
    expect(lighthouseHeroMetricIsOverlay('projectCost'), isFalse);
    expect(lighthouseHeroMetricIsOverlay('prepaid'), isFalse);
    expect(lighthouseHeroMetricIsOverlay('netTa'), isFalse);
    expect(lighthouseHeroMetricIsOverlay('netProfit'), isFalse);
    expect(
      lighthouseHeroOverlaySoloSlot(
        metricKey: 'netProfit',
        scaleKey: 'verifiedSales',
        scaleAltKey: 'sales',
      ),
      isNull,
    );
    expect(lighthouseHeroTrendChartSlot('netProfit'), 'profit');
    expect(
      lighthouseHeroOverlaySoloSlot(
        metricKey: 'profit',
        scaleKey: 'verifiedSales',
        scaleAltKey: 'sales',
      ),
      'profit',
    );
    expect(
      lighthouseHeroOverlaySoloSlot(
        metricKey: 'verifiedSales',
        scaleKey: 'verifiedSales',
        scaleAltKey: 'sales',
      ),
      'scale',
    );
    expect(
      lighthouseHeroOverlaySoloSlot(
        metricKey: 'sales',
        scaleKey: 'verifiedSales',
        scaleAltKey: 'sales',
      ),
      'scaleAlt',
    );
    expect(
      lighthouseHeroOverlaySoloSlot(
        metricKey: 'gmv',
        scaleKey: 'verifiedSales',
        scaleAltKey: 'sales',
      ),
      isNull,
    );
    expect(lighthouseHeroTrendFocusAfterTap(null, 'profit'), 'profit');
    expect(lighthouseHeroTrendFocusAfterTap('profit', 'profit'), isNull);
    expect(lighthouseHeroTrendFocusAfterTap('profit', 'gmv'), 'gmv');
    expect(lighthouseHeroMetricTrendKeys(), [
      'sales',
      'verifiedSales',
      'gmv',
      'totalCost',
      'projectCost',
      'cost',
      'prepaid',
      'profit',
      'netProfit',
      'revenue',
      'spread',
      'grossMargin',
      'rate',
    ]);
    expect(lighthouseHeroTrendChartSlot('sales'), 'scale');
    expect(lighthouseHeroTrendChartSlot('prepaid'), 'scale');
    expect(lighthouseHeroTrendChartSlot('revenue'), 'revenue');
    expect(lighthouseHeroTrendChartSlot('cost'), 'cost');
    expect(lighthouseHeroTrendChartSlot('projectCost'), 'cost');
    expect(lighthouseHeroTrendChartSlot('profit'), 'profit');
    expect(lighthouseHeroTrendChartSlot('spread'), 'profit');
    expect(lighthouseHeroTrendChartIsRate('grossMargin'), isTrue);
    expect(lighthouseHeroTrendChartIsRate('rate'), isTrue);
    expect(lighthouseHeroTrendChartIsRate('sales'), isFalse);
    expect(lighthouseHeroMetricLabel('gmv'), 'GMV');
    expect(lighthouseHeroMetricLabel('prepaid'), '预收净增');
    expect(lighthouseHeroMetricLabel('netTa'), '净TA');
  });

  test('trend x-axis labels every point gets a date', () {
    final all = lighthouseTrendXAxisLabels(
      ['8.21', '8.22', '8.23', '8.24', '8.25', '8.26', '8.27'],
      7,
    );
    expect(all.$1, [
      '8.21',
      '8.22',
      '8.23',
      '8.24',
      '8.25',
      '8.26',
      '8.27',
    ]);
    expect(all.$2, [0, 1, 2, 3, 4, 5, 6]);
    expect(
      lighthouseTrendXAxisLabels(
        ['2026.02', '2026.08'],
        2,
      ).$1,
      ['02月', '08月'],
    );
    expect(lighthouseFundPoolExpandTapWidth, 44);
    expect(lighthouseFundPoolExpandIconSize, 22);
    expect(lighthouseFundPoolPreviewChevronSize, 10);
    expect(lighthouseFundPoolPreviewHeight, 43);
    expect(lighthouseFundPoolSectionTitleLineHeight, 1.3);
    expect(lighthouseFundPoolSectionTitleIconGap, 7);
  });

  test('lighthouseTrendShareScaleRange only pairs 核销/销售', () {
    expect(
      lighthouseTrendShareScaleRange(
        scaleLabel: '核销规模',
        scaleAltLabel: '销售规模',
      ),
      isTrue,
    );
    expect(
      lighthouseTrendShareScaleRange(
        scaleLabel: '支付手续费',
        scaleAltLabel: '机构返佣',
      ),
      isFalse,
    );
    expect(
      lighthouseTrendShareScaleRange(
        scaleLabel: '规模',
        scaleAltLabel: '',
      ),
      isFalse,
    );
  });

  test('lighthouseTrendSeriesRange normalizes each series on its own span', () {
    final big = lighthouseTrendSeriesRange([3.0, 5.39, 4.2]);
    final tiny = lighthouseTrendSeriesRange([0.04, 0.06, 0.05]);
    expect(tiny.max - tiny.min, lessThan(big.max - big.min));
    expect(tiny.min, lessThan(0.04));
    expect(tiny.max, greaterThan(0.06));
    final flat = lighthouseTrendSeriesRange([0.05, 0.05, 0.05]);
    expect(flat.min, lessThan(0.05));
    expect(flat.max, greaterThan(0.05));
  });

  test('cost bill L3 types render as extra cost trend charts', () {
    const types = [
      {
        'key': 'service_ap_PTFWF',
        'label': '平台服务费',
        'category': 'PROJECT_COST',
      },
      {
        'key': 'ap_YWCB_GJCH',
        'label': '供给侧H',
        'category': 'BUSINESS_COST',
      },
    ];
    expect(
      lighthouseHeroCostBillTrendKeys(types),
      ['costBill:service_ap_PTFWF', 'costBill:ap_YWCB_GJCH'],
    );
    expect(lighthouseIsCostBillMetric('costBill:service_ap_PTFWF'), isTrue);
    expect(lighthouseIsCostBillMetric('projectCost'), isFalse);
    expect(
      lighthouseCostBillTypeLabel('costBill:service_ap_PTFWF', types),
      '平台服务费',
    );
    expect(
      lighthouseHeroTrendChartSlot('costBill:ap_YWCB_GJCH'),
      'cost',
    );
    expect(
      lighthouseCostBillTypeSeries({
        'service_ap_PTFWF': [1, 2, 3],
      }, 'costBill:service_ap_PTFWF'),
      [1, 2, 3],
    );
    final projectLines = lighthouseCostBillChartLines(
      typesRaw: [
        {
          'key': 'ap_YFFY_JGFY',
          'label': '机构返佣',
          'l2': '返佣',
          'category': 'PROJECT_COST',
        },
        {
          'key': 'ap_YWCB_GJCH',
          'label': '供给侧H',
          'category': 'BUSINESS_COST',
        },
        {
          'key': 'ap_FW_PTF',
          'label': '平台服务费',
          'l2': '服务费',
          'category': 'PROJECT_COST',
        },
        {
          'key': 'service_ap_ZFSXF',
          'label': '支付手续费',
          'category': 'PROJECT_COST',
        },
      ],
      seriesRaw: {
        'ap_FW_PTF': [1, 2, 3],
        'service_ap_ZFSXF': [4, 5, 6],
        'ap_YFFY_JGFY': [7, 8, 9],
        'ap_YWCB_GJCH': [10, 11, 12],
      },
      category: 'PROJECT_COST',
    );
    expect(
      projectLines.map((l) => l.label).toList(),
      ['平台服务费', '支付手续费', '机构返佣'],
    );
    expect(projectLines.first.values, [1, 2, 3]);
    expect(
      lighthouseCostBillChartLines(
        typesRaw: types,
        seriesRaw: {
          'service_ap_PTFWF': [0, 0],
          'ap_YWCB_GJCH': [1, 2],
        },
        category: 'PROJECT_COST',
      ),
      isEmpty,
    );
  });

  test('netTA ledger pinned column is wider so four-character names fit', () {
    expect(lighthouseLedgerPinnedMinWidth, 112);
    expect(lighthouseLedgerNetTAPinnedMinWidth, 136);
    expect(lighthouseLedgerPinnedWidthFor(390, tab: 'product'), 136.5);
    expect(
      lighthouseLedgerPinnedWidthFor(390, tab: 'netTa'),
      greaterThan(lighthouseLedgerPinnedWidthFor(390, tab: 'product')),
    );
    expect(
      lighthouseLedgerPinnedWidthFor(390, tab: 'netTa'),
      lessThanOrEqualTo(lighthouseLedgerPinnedMaxWidth),
    );
    expect(lighthouseLedgerPinnedWidthFor(200, tab: 'netTa'), 136);
  });

  test('ledger rows show four focused metrics in a neutral 2x2 grid', () {
    expect(lighthouseLedgerSummaryColumns, 2);
    expect(lighthouseLedgerNameFontSize, 12.5);
    expect(lighthouseLedgerLongNameFontSize, 11.0);
    expect(lighthouseLedgerProjectNameFontSize, 10.0);
    expect(lighthouseLedgerNameFontSizeForTab('supply'), 12.5);
    expect(lighthouseLedgerNameFontSizeForTab('channel'), 12.5);
    expect(lighthouseLedgerNameFontSizeForTab('product'), 11.0);
    expect(lighthouseLedgerNameFontSizeForTab('productName'), 11.0);
    expect(lighthouseLedgerNameFontSizeForTab('project'), 10.0);
    expect(lighthouseLedgerValueFontSize, 11.5);
    expect(lighthouseLedgerUnitFontSize, 9.0);
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
    expect(lighthouseLedgerSummaryMetricTone('netTa'), 'cash');
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
      'netTa',
    ]);
    expect(lighthouseLedgerSummaryMetricRows, [
      ['sales', 'prepaid'],
      ['verifiedSales', 'profit'],
    ]);
    expect(
      lighthouseLedgerSoloTrendKeys,
      {'sales', 'verifiedSales', 'prepaid', 'profit'},
    );
    expect(lighthouseLedgerMetricOpensSoloTrend('sales'), isTrue);
    expect(lighthouseLedgerMetricOpensSoloTrend('gmv'), isFalse);
    expect(lighthouseLedgerSoloTrendAfterTap(null, 'profit'), 'profit');
    expect(lighthouseLedgerSoloTrendAfterTap('profit', 'profit'), isNull);
    expect(
      lighthouseLedgerSoloTrendAfterTap('sales', 'prepaid'),
      'prepaid',
    );
    expect(lighthouseLedgerSoloTrendAfterTap('sales', 'gmv'), 'sales');
    expect(lighthouseLedgerShowsFundPoolPreview('supply'), isTrue);
    expect(lighthouseLedgerShowsFundPoolPreview('product'), isFalse);
    expect(lighthouseLedgerShowsFundPoolPreview('channel'), isFalse);
    // 两条算式锁在测试里：改了口径就得连这里一起改，避免 UI 和实际取数漂移。
    expect(
      lighthouseFundPoolFormulas.map((f) => [f.result, f.expression]).toList(),
      [
        ['资产合计', '现金·监管户 + 现金·在途 + 期末预付款余额'],
        ['系统差异', '期末预付款余额 − 资金池可用 − 库存/同步券 − 应收资金'],
      ],
    );
    // Hero 五条式子。毛利率 / ROI 与 _rowGrossMarginPct / _rowRoiPct 同口径；
    // 成本合计 / 净利润 是反推的；毛利润那条口径未确认，所以不代入数字。
    expect(
      lighthouseHeroFormulas.map((f) => [f.resultKey, f.expression]).toList(),
      [
        ['totalCost', '项目成本 + 业务成本'],
        ['netProfit', '毛利润 − 业务成本'],
        ['grossMargin', '毛利润 ÷ 核销额'],
        ['rate', '毛利润 ÷ 成本合计'],
        ['profit', '收入 − 成本合计'],
      ],
    );
    expect(lighthouseHeroFormulaForKey('profit')?.substitutes, isFalse);
    expect(lighthouseHeroFormulaForKey('rate')?.substitutes, isTrue);
    expect(lighthouseHeroFormulaForKey('sales'), isNull);
    // 毛利润在 ROI 里是分子、在毛利率里也是分子；成本合计在 ROI 里是分母。
    expect(
      lighthouseHeroTraceRole('rate', 'profit'),
      LighthouseHeroFormulaRole.numerator,
    );
    expect(
      lighthouseHeroTraceRole('rate', 'totalCost'),
      LighthouseHeroFormulaRole.denominator,
    );
    expect(lighthouseHeroTraceRole('rate', 'gmv'), isNull);
    expect(
      lighthouseHeroFormulaRoleBadge(LighthouseHeroFormulaRole.denominator),
      '分母',
    );
    // 压暗：无关格压，来源格和被点的格子不压。
    expect(lighthouseHeroTraceDims('rate', 'gmv'), isTrue);
    expect(lighthouseHeroTraceDims('rate', 'profit'), isFalse);
    expect(lighthouseHeroTraceDims('rate', 'rate'), isFalse);
    expect(lighthouseHeroTraceDims(null, 'gmv'), isFalse);
    expect(lighthouseHeroTraceAfterTap(null, 'rate'), 'rate');
    expect(lighthouseHeroTraceAfterTap('rate', 'rate'), isNull);
    expect(lighthouseHeroTraceAfterTap('rate', 'profit'), 'profit');
    expect(lighthouseHeroTraceAfterTap('rate', 'gmv'), 'rate');

    // 箭头追溯：资产合计点亮 3 格，系统差异点亮 4 格，两条共用期末预付款余额。
    expect(
      lighthouseFundPoolFormulaForKey('totalAssets')?.sourceKeys,
      ['regulatoryAccountBalance', 'inTransitFunds', 'endingPrepaymentBalance'],
    );
    expect(
      lighthouseFundPoolFormulaForKey('systemDifference')?.sourceKeys.length,
      4,
    );
    expect(lighthouseFundPoolFormulaForKey('fundPoolBalance'), isNull);
    expect(
      lighthouseFundPoolMetricIsTraced('totalAssets', 'inTransitFunds'),
      isTrue,
    );
    // 应收资金只进系统差异，不进资产合计 —— 这条最容易看错，锁在测试里。
    expect(
      lighthouseFundPoolMetricIsTraced('totalAssets', 'endingReceivableRebate'),
      isFalse,
    );
    expect(
      lighthouseFundPoolMetricIsTraced(
        'systemDifference',
        'endingReceivableRebate',
      ),
      isTrue,
    );
    expect(lighthouseFundPoolMetricIsTraced(null, 'inTransitFunds'), isFalse);
    expect(
      lighthouseFundPoolTraceAfterTap(null, 'totalAssets'),
      'totalAssets',
    );
    expect(
      lighthouseFundPoolTraceAfterTap('totalAssets', 'totalAssets'),
      isNull,
    );
    expect(
      lighthouseFundPoolTraceAfterTap('totalAssets', 'systemDifference'),
      'systemDifference',
    );
    // 不是结果格的键点不动当前追溯。
    expect(
      lighthouseFundPoolTraceAfterTap('totalAssets', 'fundPoolBalance'),
      'totalAssets',
    );
    expect(
      lighthouseFundPoolPanelFormulas(lighthouseFundPoolPanelInvoice),
      isEmpty,
    );
    expect(
      lighthouseFundPoolPanelFormulas(lighthouseFundPoolPanelAssets).length,
      2,
    );
    // 预览行与 KPI 格等高，冻结列不再需要额外补高。
    expect(lighthouseFundPoolPreviewHeight, 43);
    expect(
      lighthouseFundPoolPreviewRowHeight(summaryCellHeight: 43, scale: 1),
      43,
    );
    expect(
      lighthouseFundPoolPreviewExtraHeight(
        summaryCellHeight: 43,
        scale: 1,
      ),
      0,
    );
    expect(
      lighthouseFundPoolPreviewMetrics()
          .map((m) => [m.key, m.label])
          .toList(),
      [
        ['totalAssets', '总资产金额'],
        ['invoicePreview', '票税'],
      ],
    );

    final byProvince = lighthouseParseFundPoolByProvince({
      '广东省': {
        'endingPrepaymentBalance': 120000,
        'endingReceivableRebate': 230000,
        'fundPoolBalance': 567000,
        'inventoryVoucherBalance': 340000,
        'contractVoucherBalance': 450000,
        'systemDifference': -12000,
        'inTransitFunds': 670000,
        'regulatoryAccountBalance': 780000,
        'totalAssets': 1234000,
        'invoiceToIssue': 890000,
        'invoiceIssued': 120000,
        'invoiceTaxRate': 13,
        'invoiceOriginals': [
          {'url': 'https://cdn.example/a.png'},
          'https://cdn.example/b.png',
        ],
        'advanceVoucherBalance': 45000,
      },
      '__TOTAL__': {'totalAssets': 999, 'fundPoolBalance': 111},
    });
    final guangdong = lighthouseLookupFundPool(byProvince, '广东省');
    expect(guangdong?.totalAssets, 1234000);
    expect(guangdong?.endingPrepaymentBalance, 120000);
    expect(guangdong?.invoiceTaxRate, 13);
    expect(guangdong?.invoiceIssued, 120000);
    expect(guangdong?.advanceVoucherBalance, 45000);
    expect(guangdong?.invoiceOriginals, [
      'https://cdn.example/a.png',
      'https://cdn.example/b.png',
    ]);
    expect(lighthouseLookupFundPool(byProvince, '广东')?.fundPoolBalance, 567000);
    expect(lighthouseLookupFundPool(byProvince, '未知省'), isNull);
    expect(lighthouseFormatFundPoolWan(1234000), '123.4万');
    expect(lighthouseFormatFundPoolWan(123400000), '1.23亿');
    expect(lighthouseFormatFundPoolWan(null), '—');
    expect(lighthouseFormatFundPoolWanParts(1234000), (number: '123.4', unit: '万'));
    expect(lighthouseFormatFundPoolWanParts(123400000), (number: '1.23', unit: '亿'));
    expect(lighthouseFormatFundPoolWanParts(null), (number: '—', unit: ''));
    expect(lighthouseFormatFundPoolRate(13), '13%');
    expect(lighthouseFormatFundPoolRate(13.14), '13.14%');
    expect(lighthouseFundPoolShowsInvoice('day'), isTrue);
    expect(lighthouseFundPoolShowsInvoice('week'), isTrue);
    expect(lighthouseFundPoolShowsInvoice('month'), isTrue);
    expect(lighthouseFundPoolShowsInvoice('quarter'), isTrue);
    expect(lighthouseFundPoolShowsInvoice('year'), isTrue);
    final monthly = lighthouseFundPoolDetailRows(showInvoice: true);
    expect(monthly.first.left.kind, LighthouseFundPoolSectionKind.invoice);
    expect(monthly.first.right?.kind, LighthouseFundPoolSectionKind.assets);
    expect(
      monthly.first.left.metrics.map((m) => m.label).toList(),
      ['发票原件', '应开发票金额', '实开金额'],
    );
    expect(
      monthly[1].left.metrics.map((m) => m.key).toList(),
      [
        'regulatoryAccountBalance',
        'inTransitFunds',
        'endingReceivableRebate',
      ],
    );
    expect(
      monthly[1].right?.metrics.map((m) => m.key).toList(),
      [
        'inventoryVoucherBalance',
        'contractVoucherBalance',
        'advanceVoucherBalance',
      ],
    );
    expect(
      monthly.last.left.metrics.map((m) => m.key).toList(),
      [
        'fundPoolBalance',
        'stockAndSyncVouchers',
        'systemDifference',
        'endingPrepaymentBalance',
      ],
    );
    final daily = lighthouseFundPoolDetailRows(showInvoice: false);
    expect(daily.first.left.kind, LighthouseFundPoolSectionKind.funds);
    expect(daily.last.right?.kind, LighthouseFundPoolSectionKind.assets);
    expect(
      daily.any((row) => row.left.kind == LighthouseFundPoolSectionKind.invoice),
      isFalse,
    );
    expect(
      lighthouseFundPoolStockAndSyncVouchers(
        const LighthouseFundPoolAmounts(
          inventoryVoucherBalance: 10,
          contractVoucherBalance: 5,
        ),
      ),
      15,
    );
    expect(lighthouseLedgerSummaryMetricRowsForTab('supply'), [
      ['sales', 'prepaid'],
      ['verifiedSales', 'profit'],
    ]);
    expect(lighthouseLedgerSummaryMetricRowsForTab('channel'), [
      ['sales', 'prepaid'],
      ['verifiedSales', 'profit'],
    ]);
    expect(lighthouseLedgerSummaryMetricRowsForTab('product'), [
      ['sales', 'prepaid'],
      ['verifiedSales', 'profit'],
    ]);
    expect(lighthouseLedgerSummaryMetricRowsForTab('netTa'), [
      ['inflow', 'netTa'],
      ['outflow', 'sharePct'],
    ]);
  });

  test('fund pool invoice card shows for every period', () {
    for (final period in ['day', 'week', 'month', 'quarter', 'year', 'custom']) {
      expect(lighthouseFundPoolShowsInvoice(period), isTrue);
    }
    final rows = lighthouseFundPoolDetailRows(
      showInvoice: lighthouseFundPoolShowsInvoice('day'),
    );
    expect(rows.first.left.kind, LighthouseFundPoolSectionKind.invoice);
    expect(rows.first.right?.kind, LighthouseFundPoolSectionKind.assets);
  });

  test('netTA hero overlay series maps onto the shared trend slots', () {
    expect(lighthouseNetTAHeroOverlaySlot('netTa'), 'scale');
    expect(lighthouseNetTAHeroOverlaySlot('netTaOperating'), 'revenue');
    expect(lighthouseNetTAHeroOverlaySlot('netTaProjectCost'), 'profit');
    expect(lighthouseNetTAHeroOverlaySlot('netTaBizCost'), 'costAlt');
    expect(lighthouseNetTAHeroMetricFromSlot('profit'), 'netTaProjectCost');
    expect(lighthouseNetTAHeroMetricFromSlot('costAlt'), 'netTaBizCost');
    expect(lighthouseHeroMetricDisplaysMagnitude('netTaOutflow'), isTrue);
    expect(lighthouseHeroMetricDisplaysMagnitude('netTaOpCost'), isTrue);
    expect(lighthouseHeroMetricDisplaysMagnitude('netTaProjectCost'), isTrue);
    expect(lighthouseHeroMetricDisplaysMagnitude('netTaBizCost'), isTrue);
    expect(lighthouseHeroMetricDisplaysMagnitude('netTaFinancing'), isTrue);
    expect(lighthouseHeroMetricDisplayAmount('netTaFinancing', -7656.2e4), 7656.2e4);
    expect(lighthouseHeroMetricDisplayAmount('netTaOutflow', -2.68e8), 2.68e8);
    expect(lighthouseHeroMetricDisplayAmount('netTaOperating', -10), -10);
    expect(lighthouseSeriesSignedDeltaPct([80, 100]), closeTo(25, 0.001));
    expect(lighthouseSeriesSignedDeltaPct([100, 80]), closeTo(-20, 0.001));
    expect(lighthouseSeriesSignedDeltaPct([0, 10]), isNull);

    final fromSeries = lighthouseNetTAHeroTrendFromPayload({
      'total': 15,
      'series': {
        'labels': ['上期', '本期'],
        'title': '走势',
        'rangeLabel': '上期 — 本期',
        'netTa': [25, 15],
        'operating': [80, 100],
        'financing': [-20, -40],
        'operatingCost': [-25, -30],
        'projectCost': [-8, -10],
        'businessCost': [-2, -5],
      },
    });
    expect(fromSeries.netTa, [25, 15]);
    expect(fromSeries.operating, [80, 100]);
    expect(fromSeries.projectCost, [-8, -10]);
    expect(fromSeries.businessCost, [-2, -5]);
    expect(fromSeries.projectAndBusiness, [-10, -15]);

    final fallback = lighthouseNetTAHeroTrendFromPayload({
      'total': 12,
      'categories': [
        {'name': '经营活动', 'netTa': 20},
        {'name': '项目成本', 'netTa': -5},
        {'name': '业务成本', 'netTa': -3},
      ],
    });
    expect(fallback.netTa, [0, 12]);
    expect(fallback.operating, [0, 20]);
    expect(fallback.projectCost, [0, -5]);
    expect(fallback.businessCost, [0, -3]);
    expect(fallback.projectAndBusiness, [0, -8]);

    final merged = <String, dynamic>{};
    lighthouseMergeNetTAHeroTrend(merged, fromSeries);
    expect(merged['netTaSeries'], [25, 15]);
    expect(merged['netTaOperating'], 100);
    expect(merged['netTaProjectCostSeries'], [-8, -10]);
    expect(merged['netTaBizCostSeries'], [-2, -5]);
    expect(merged['netTaSeriesLabels'], ['上期', '本期']);
  });

  test('netTA rows keep five mapped parents and split inflow/outflow', () {
    final rows = lighthousePrepareNetTARows([
      {
        'name': '经营活动',
        'netTa': 100,
        'secondaries': [
          {'name': '项目回款', 'netTa': 80},
          {'name': '分润', 'netTa': 20},
        ],
      },
      {
        'name': '业务成本',
        'netTa': -8,
        'secondaries': [
          {'name': '营销费用', 'netTa': -8},
        ],
      },
    ]);
    expect(rows.map((r) => r['name']).toList(), ['经营活动', '业务成本']);
    expect(rows[0]['inflow'], 100);
    expect(rows[0]['outflow'], 0);
    expect(rows[1]['inflow'], 0);
    expect(rows[1]['outflow'], -8);
    expect(rows[0]['sharePct'], 100);
    expect(rows[1]['sharePct'], 100);
    expect(lighthouseNetTACardMetrics(
      (rows[0]['secondaries'] as List).cast<Map<String, dynamic>>(),
    ).map((e) => e['name']).toList(), [
      '项目回款',
      '分润',
    ]);
    expect(lighthouseNetTAFlowLabel(100), '净流入');
    expect(lighthouseNetTAFlowLabel(-8), '净流出');
    expect(lighthouseNetTAShareLabel(100), '占净流入');
    expect(lighthouseNetTAShareLabel(-8), '占净流出');
    expect(lighthouseNetTASecondaryCount(rows[0]), 2);
    expect(lighthouseNetTASecondaryCount({'name': '项目成本'}), 1);
    expect(
      lighthouseNetTASecondariesOrSeed('经营活动', const []).map((e) => e['name']),
      ['和包出行回款', '项目付款', '项目回款', '应收保证金', '分润', '预收保证金'],
    );
    expect(
      lighthouseNetTACardMetrics([
        for (var i = 0; i < 11; i++) {'name': '项$i', 'netTa': -10.0 * (11 - i)},
      ]).length,
      6,
    );
    expect(
      lighthouseNetTACardMetrics([
        for (var i = 0; i < 11; i++) {'name': '项$i', 'netTa': -10.0 * (11 - i)},
      ]).last['name'],
      '其余 6 项',
    );
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
    expect(lighthouseLedgerPrimaryTabs, [
      'product',
      'supply',
      'channel',
      'netTa',
      'analysis',
    ]);
    expect(lighthouseLedgerPrimaryTabLabels['netTa'], '净TA');
    expect(lighthouseLedgerTabShowsCategoryChips('product'), isTrue);
    expect(lighthouseLedgerTabShowsCategoryChips('netTa'), isFalse);
    expect(lighthouseLedgerTabShowsCategoryChips('analysis'), isFalse);
    expect(lighthouseLedgerPrimaryTabHeight, 44);
    expect(lighthouseLedgerFilterRowHeight, 42);
    expect(lighthouseLedgerFilterChipRadius, 8);
    expect(lighthouseLedgerCentersPrimaryDimensions, isFalse);
    expect(lighthouseLedgerPrimaryDimensionsFillAvailableWidth, isTrue);
    expect(lighthouseLedgerSeparatesAnalysisTab, isFalse);
    expect(lighthouseLedgerPrimaryTabUsesPeriodSegment, isTrue);
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
    expect(lighthouseAppBarTitleColorValue, 0xFF7C5CE6);
    expect(lighthouseAppBarEnglishFontSize, 8.5);
    expect(lighthouseAppBarToolbarHeight, 34);
    expect(lighthouseAppBarToolbarRadius, 11);
    expect(lighthouseAppBarPutsDateOnTitleRow, isFalse);
    expect(
      lighthouseSyncedAtStamp(DateTime(2026, 8, 28, 9, 49)),
      '2026.08.28 09:49',
    );
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

  test('hero summary range matches the selected interval control', () {
    expect(
      lighthouseMdDashRange(DateTime(2026, 8, 1), DateTime(2026, 8, 31)),
      '08.01–08.31',
    );
    expect(
      lighthouseHeroSelectedRangeLabel(
        isCustomRange: true,
        customStart: DateTime(2026, 8, 1),
        customEnd: DateTime(2026, 8, 15),
        periodInstanceDetail: '08.01–08.31',
      ),
      '08.01–08.15',
    );
    expect(
      lighthouseHeroSelectedRangeLabel(
        isCustomRange: false,
        periodInstanceDetail: '08.01–08.31',
      ),
      '08.01–08.31',
    );
    expect(lighthouseHeroSummaryRangeFontSize, 11);
  });

  test('aligned period follows 2026-08 运营会 同期口径', () {
    final aug25 = DateTime(2026, 8, 25);
    final day = lighthouseResolveAlignedPeriod(period: 'day', now: aug25);
    expect(day.currentLabel, '08.25');
    expect(day.prevLabel, '07.25');
    expect(day.deltaVs, 'vs 上月同日');
    expect(day.inProgress, isTrue);

    expect(
      lighthouseSameDayPrevMonth(DateTime(2026, 3, 31)),
      DateTime(2026, 2, 28),
    );
    expect(
      lighthouseSameDayPrevMonth(DateTime(2028, 3, 31)),
      DateTime(2028, 2, 29),
    );

    final monthOpen = lighthouseResolveAlignedPeriod(
      period: 'month',
      now: aug25,
    );
    expect(monthOpen.currentLabel, '08.01–08.25');
    expect(monthOpen.prevLabel, '07.01–07.25');
    expect(monthOpen.deltaVs, 'vs 上月同期');
    expect(monthOpen.inProgress, isTrue);

    final monthDone = lighthouseResolveAlignedPeriod(
      period: 'month',
      now: DateTime(2026, 8, 31),
    );
    expect(monthDone.currentLabel, '08.01–08.31');
    expect(monthDone.prevLabel, '07.01–07.31');
    expect(monthDone.deltaVs, 'vs 上月');
    expect(monthDone.inProgress, isFalse);

    final week = lighthouseResolveAlignedPeriod(period: 'week', now: aug25);
    expect(week.currentLabel, '08.24–08.25');
    expect(week.prevLabel, '08.17–08.18');
    expect(week.deltaVs, 'vs 上周同期');

    final hist = lighthouseResolveAlignedPeriod(
      period: 'month',
      now: DateTime(2026, 8, 25),
      offset: -1,
    );
    expect(hist.currentLabel, '07.01–07.31');
    expect(hist.prevLabel, '06.01–06.30');
    expect(hist.deltaVs, 'vs 上月');
    expect(hist.inProgress, isFalse);

    final year = lighthouseResolveAlignedPeriod(period: 'year', now: aug25);
    expect(year.currentLabel, '2026.01.01–2026.12.31');
    expect(year.deltaVs, 'vs 去年');
    expect(year.inProgress, isTrue);
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

  test(
    'L1 hero shows category logo only when a concrete group is selected',
    () {
      expect(lighthouseHeroShowsCategoryLogo('全部'), isFalse);
      expect(lighthouseHeroShowsCategoryLogo(''), isFalse);
      expect(lighthouseHeroShowsCategoryLogo('中石油'), isTrue);
      expect(lighthouseHeroShowsCategoryLogo('能源'), isTrue);
      expect(lighthouseHeroShowsCategoryLogo('平安'), isTrue);
    },
  );

  test('compact hero keeps KPI and trend side by side on wide screens', () {
    expect(lighthouseCompactHeroKpiFlex, 3);
    expect(lighthouseCompactHeroTrendFlex, 7);
    expect(lighthouseCompactHeroSparkHeight, 180);
    expect(lighthouseCompactHeroSparkHeightNarrow, 216);
    expect(lighthouseCompactHeroChartMaxHeightWide, 84);
    expect(lighthouseCompactHeroChartMaxHeightNarrow, 112);
    expect(lighthouseCompactHeroNarrowBreakpoint, 600);
    expect(lighthouseCompactHeroIsNarrow(599), isTrue);
    expect(lighthouseCompactHeroIsNarrow(600), isFalse);
    expect(lighthouseCompactHeroSparkHeightFor(390), 216);
    expect(lighthouseCompactHeroSparkHeightFor(800), 180);
    expect(lighthouseNetTAHeroSparkHeightFor(390), 216);
    expect(lighthouseNetTAHeroSparkHeightFor(800), 180);
    expect(
      lighthouseNetTAHeroSparkHeightFor(800, hasBankBalance: true),
      180 + lighthouseNetTABankBalanceExtraHeight,
    );
    expect(lighthouseCompactHeroChartMaxHeightFor(390), 112);
    expect(lighthouseCompactHeroChartMaxHeightFor(800), 84);
    expect(lighthouseCompactHeroBlockHeightFor(390), 216 + 16);
    expect(lighthouseCompactHeroBlockHeightFor(800), 180 + 16);
    expect(lighthouseCompactHeroMetricGap, 2);
    expect(lighthouseHeroUsesCategoryTint, isFalse);
    expect(lighthouseHeroUsesAccentRail, isFalse);
    expect(lighthouseHeroShowsEnglishKicker, isFalse);
    expect(lighthouseHeroUsesCardShadow, isFalse);
    expect(lighthouseHeroMetricUsesSansLabel, isTrue);
    expect(lighthouseHeroCardRadius, 12);
    expect(lighthouseHeroCardGap, 8);
    expect(lighthouseHeroCardPadding, 5);
    expect(lighthouseHeroChartUsesCardSurface, isTrue);
    expect(lighthouseHeroChartCardPadding, 8);
    expect(lighthouseHeroSparkShowsAxes, isFalse);
    expect(lighthouseHeroSparkShowsGrid, isFalse);
    expect(lighthouseHeroSparkShowsAverage, isFalse);
    expect(lighthouseHeroSparkShowsEveryPeriodLabel, isFalse);
    expect(lighthouseHeroSparkShowsEveryValue, isFalse);
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

  group('lighthouseHeroTrendPanes', () {
    test('keeps scale and pnl on separate axes', () {
      expect(
        lighthouseHeroTrendPaneIndexes([
          'verifiedSales',
          'sales',
          'revenue',
          'totalCost',
          'profit',
        ]),
        [
          [0],
          [1],
          [2, 3, 4],
        ],
      );
      expect(lighthouseHeroTrendIsScaleKey('verifiedSales'), isTrue);
      expect(lighthouseHeroTrendIsScaleKey('revenue'), isFalse);
      expect(lighthouseHeroTrendPaneFlex(1), 2);
      expect(lighthouseHeroTrendPaneFlex(3), 3);
    });

    test('does not snap near-equal scale down to zero', () {
      expect(
        lighthouseHeroPaneSnapsToZero(min: 1211, max: 1220),
        isFalse,
      );
      expect(
        lighthouseHeroPaneSnapsToZero(min: 6, max: 16.1),
        isTrue,
      );
    });
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
        lighthouseGrossMarginSeries(profit: [412300], verifiedSales: [80]),
        [0],
      );
    });
  });

  group('lighthouse cross-level trend isolation', () {
    test('L3 never falls back to L2 trend', () {
      // L3 必须用 detail 接口下发的 drill.trend；禁止串父级折线。
      expect(lighthouseCanFallbackToRootTrend(isDrill: false), isTrue);
      expect(lighthouseCanFallbackToRootTrend(isDrill: true), isFalse);
      expect(lighthouseCanFallbackToChildTrend(isDrill: true), isTrue);
      expect(lighthouseTrendTabForSubDim('supply'), 'supply');
      expect(lighthouseTrendTabForSubDim('productName'), isNull);
      expect(
        lighthouseTrendMapUsable({
          'sales': [1, 2],
        }),
        isTrue,
      );
      expect(
        lighthouseTrendMapUsable({
          'prepaid': [10, 20],
        }),
        isTrue,
      );
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

  group('lighthouseHeroUseRowAmounts / default group', () {
    test('all tabs default to 全部', () {
      expect(lighthouseDefaultGroupFilter('product'), '全部');
      expect(lighthouseDefaultGroupFilter('supply'), '全部');
      expect(lighthouseDefaultGroupFilter('channel'), '全部');
    });

    test('use backend summary when no filter', () {
      expect(
        lighthouseHeroUseRowAmounts(filterActive: false, hasRows: true),
        isFalse,
      );
      expect(
        lighthouseHeroUseRowAmounts(filterActive: true, hasRows: true),
        isTrue,
      );
      expect(
        lighthouseHeroUseRowAmounts(filterActive: true, hasRows: false),
        isFalse,
      );
    });

    test('stale category summary does not apply after switching tab to 全部', () {
      expect(
        lighthouseHeroSummaryAppliesTo(
          tab: 'supply',
          group: '全部',
          filterTab: 'product',
          filterGroup: '能源',
        ),
        isFalse,
      );
      expect(
        lighthouseHeroSummaryAppliesTo(
          tab: 'supply',
          group: '运营商',
          filterTab: 'product',
          filterGroup: '运营商',
        ),
        isFalse,
      );
      expect(
        lighthouseHeroSummaryAppliesTo(
          tab: 'supply',
          group: '全部',
          filterTab: null,
          filterGroup: null,
        ),
        isTrue,
      );
    });

    test('tab switch falls back to shared 全部 profit, not previous category', () {
      expect(
        lighthouseHeroMetricAmount(
          useRowAmounts: false,
          metricsMatch: false,
          metricsValue: 2.91,
          sharedValue: 10.0,
          rowSum: 8.0,
        ),
        10.0,
      );
      expect(
        lighthouseHeroMetricAmount(
          useRowAmounts: false,
          metricsMatch: false,
          metricsValue: 2.91,
          sharedValue: null,
          rowSum: 8.0,
        ),
        8.0,
      );
      expect(
        lighthouseSharedHeroMetricsSnapshot(const {
          'profit': 10.0,
          'filterGroup': '能源',
          'filterTab': 'product',
        }),
        {'profit': 10.0},
      );
    });

    test('product snapshot restore keeps net TA hero series', () {
      final product = <String, dynamic>{'profit': 10.0, 'profitSeries': [1.0, 2.0]};
      final withNetTa = <String, dynamic>{
        'profit': 10.0,
        'netTa': 3.1,
        'netTaSeries': [1.0, 2.0, 3.1],
        'netTaSeriesLabels': ['D1', 'D2', 'D3'],
        'netTaBankBalance': 15901000.0,
      };
      expect(lighthouseNetTAHeroSeriesReady(product), isFalse);
      expect(lighthouseNetTAHeroSeriesReady(withNetTa), isTrue);

      lighthouseCarryNetTAMetrics(withNetTa, product);
      expect(product['profit'], 10.0);
      expect(product['netTaSeries'], [1.0, 2.0, 3.1]);
      expect(product['netTaSeriesLabels'], ['D1', 'D2', 'D3']);
      expect(product['netTaBankBalance'], 15901000.0);
      expect(lighthouseNetTAHeroSeriesReady(product), isTrue);

      final incoming = <String, dynamic>{
        'profit': 11.0,
        'netTaSeries': <double>[],
      };
      lighthouseCarryNetTAMetrics(withNetTa, incoming);
      expect(incoming['profit'], 11.0);
      expect(incoming['netTaSeries'], [1.0, 2.0, 3.1]);
    });

    test('withSummary does not drop net TA series', () {
      final bundle = LighthouseDataBundle.empty().copyWith(
        metrics: {
          'profit': 10.0,
          'netTaSeries': [1.0, 2.0, 3.1],
          'netTaBankBalance': 100.0,
        },
      );
      final next = bundle.withSummary({
        'metrics': {'profit': 11.0, 'profitSeries': [4.0, 5.0]},
      });
      expect(next.metrics['profit'], 11.0);
      expect(next.metrics['netTaSeries'], [1.0, 2.0, 3.1]);
      expect(next.metrics['netTaBankBalance'], 100.0);
      expect(lighthouseNetTAHeroSeriesReady(next.metrics), isTrue);
    });

    test('tab switch keeps group when the next tab still has it', () {
      expect(
        lighthouseGroupAfterTabSwitch(
          currentGroup: '运营商',
          nextTabOptions: const ['全部', '中石油', '运营商'],
        ),
        '运营商',
      );
      expect(
        lighthouseGroupAfterTabSwitch(
          currentGroup: '能源',
          nextTabOptions: const ['全部', '中石油', '运营商'],
        ),
        '全部',
      );
    });

    test('normalize keeps 全部 and never forces 中石油', () {
      expect(
        lighthouseNormalizeGroupFilter(
          current: '全部',
          options: const ['全部', '中石油'],
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
      for (final key in ['sales', 'verifiedSales', 'profit', 'prepaid', 'netTa']) {
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

  group('lighthouseLedgerDeltaIsUp', () {
    test('上涨为红色方向、下跌为绿色方向，不随指标类型反转', () {
      expect(lighthouseLedgerDeltaIsUp(12), isTrue);
      expect(lighthouseLedgerDeltaIsUp(-12), isFalse);
      expect(lighthouseLedgerDeltaIsUp(null), isNull);
      expect(lighthouseLedgerDeltaIsUp(0.04), isNull);
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
      expect(lighthouseLedgerIsResultMetric('netTa'), isTrue);
      expect(lighthouseLedgerIsResultMetric('sharePct'), isTrue);
      expect(lighthouseLedgerIsResultMetric('inflow'), isFalse);
      expect(lighthouseLedgerIsResultMetric('outflow'), isFalse);
      expect(lighthouseLedgerIsResultMetric('profit'), isTrue);
      expect(lighthouseLedgerIsResultMetric(lighthouseLedgerSummaryBlankKey), isFalse);
      expect(lighthouseLedgerIsResultMetric('sales'), isFalse);
      expect(lighthouseLedgerIsResultMetric('verifiedSales'), isFalse);
      expect(lighthouseLedgerIsResultMetric('costTotal'), isFalse);
    });

    test('结果指标一律落在右列，区块才连得成一片', () {
      for (final tab in ['product', 'supply', 'channel', 'netTa']) {
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
      expect(lighthouseLedgerResultBlockTintAlpha, 38);
      expect(lighthouseLedgerResultBlockAccentValue, 0xFF4A83C4);
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

  group('lighthouseResolveDrillKey', () {
    test('exact name::group hits product_drill style keys', () {
      expect(
        lighthouseResolveDrillKey(
          drillKeys: const {'加油金::中石油', '优惠券::中石化'},
          name: '加油金',
          group: '中石油',
        ),
        '加油金::中石油',
      );
    });

    test('cleared group falls back to unique name:: prefix', () {
      // 供给/渠道二级 → 产品子列表：合并后 group=''，仍应进 L3
      expect(
        lighthouseResolveDrillKey(
          drillKeys: const {'加油金::中石油', '优惠券::中石化'},
          name: '加油金',
          group: '',
        ),
        '加油金::中石油',
      );
    });

    test('ambiguous same-name groups do not guess', () {
      expect(
        lighthouseResolveDrillKey(
          drillKeys: const {'加油金::中石油', '加油金::中石化'},
          name: '加油金',
          group: '',
        ),
        isNull,
      );
    });

    test('name-only supply/channel drills still resolve', () {
      expect(
        lighthouseResolveDrillKey(
          drillKeys: const {'湖北', '湖南'},
          name: '湖北',
          group: '',
        ),
        '湖北',
      );
    });

    test('merged group keeps unique, clears conflict', () {
      expect(lighthouseMergedSubRowGroup('', '中石油'), '中石油');
      expect(lighthouseMergedSubRowGroup('中石油', '中石油'), '中石油');
      expect(lighthouseMergedSubRowGroup('中石油', '中石化'), '');
    });
  });

  group('trend chart profit visibility', () {
    test('pnl accents are distinct from scale and each other', () {
      expect(
        {
          lighthouseScaleAccentValue,
          lighthouseProfitAccentValue,
          lighthouseRevenueAccentValue,
          lighthouseCostAccentValue,
        }.length,
        4,
      );
    });

    test('compact legend keeps 毛利 收入 成本 before optional scaleAlt', () {
      expect(
        lighthouseTrendPnlLegendKeys(
          hasProfit: true,
          hasRevenue: true,
          hasCost: true,
          hasScaleAlt: true,
        ),
        ['profit', 'revenue', 'cost', 'scaleAlt'],
      );
    });

    test('scale joins the legend; status row never carries the hero number', () {
      expect(
        lighthouseTrendPnlLegendKeys(
          hasScale: true,
          hasProfit: true,
          hasRevenue: true,
          hasCost: true,
          hasScaleAlt: true,
        ),
        ['scale', 'profit', 'revenue', 'cost', 'scaleAlt'],
      );
      expect(
        lighthouseTrendPnlLegendKeys(
          hasScale: true,
          hasProfit: true,
          hasCostAlt: true,
          hasRevenue: true,
          hasCost: true,
          hasScaleAlt: true,
        ),
        ['scale', 'profit', 'costAlt', 'revenue', 'cost', 'scaleAlt'],
      );
      expect(lighthouseTrendShowsHeroMetricBesideStatus, isFalse);
    });

    test('legend wraps 环比 to the second line and keeps data on the first', () {
      expect(lighthouseTrendLegendMomOnSecondLine, isTrue);
      expect(lighthouseTrendLegendMinChipWidth, 78);
      expect(lighthouseTrendMomLabel(12.3), '↑ 12.3%');
      expect(lighthouseTrendMomLabel(-85), '↓ 85.0%');
      expect(
        lighthouseTrendLegendShouldWrap(
          width: 220,
          metricCount: 5,
          showAll: true,
        ),
        isTrue,
      );
      expect(
        lighthouseTrendLegendShouldWrap(
          width: 560,
          metricCount: 5,
          showAll: true,
        ),
        isFalse,
      );
      expect(
        lighthouseTrendMomPct(
          periodDeltaPct: 3.9,
          partialPeriod: false,
          selectedIndex: null,
          series: const [2.29, 2.4, 3.83],
        ),
        3.9,
      );
      expect(
        lighthouseTrendMomPct(
          periodDeltaPct: 3.9,
          partialPeriod: false,
          selectedIndex: 0,
          series: const [2.29, 2.4, 3.83],
        ),
        isNull,
      );
      expect(
        lighthouseTrendMomPct(
          periodDeltaPct: 3.9,
          partialPeriod: false,
          selectedIndex: 1,
          series: const [2.29, 2.4, 3.83],
        ),
        closeTo((2.4 - 2.29) / 2.29 * 100, 1e-6),
      );
      expect(
        lighthouseTrendMomPct(
          periodDeltaPct: 3.9,
          partialPeriod: true,
          selectedIndex: 2,
          series: const [2.29, 2.4, 3.83],
        ),
        3.9,
      );
      expect(
        lighthouseTrendMomPct(
          periodDeltaPct: null,
          partialPeriod: true,
          selectedIndex: null,
          series: const [100, 110],
        ),
        isNull,
      );
    });
  });

  group('lighthouseTrendSolo', () {
    test('tap same key restores all, tap another isolates it', () {
      expect(lighthouseTrendSoloAfterTap(null, 'profit'), 'profit');
      expect(lighthouseTrendSoloAfterTap('profit', 'profit'), isNull);
      expect(lighthouseTrendSoloAfterTap('profit', 'revenue'), 'revenue');
      expect(lighthouseTrendSoloAfterTap('revenue', ''), isNull);
    });

    test('solo hides every other series that actually has data', () {
      expect(
        lighthouseTrendVisibleFlags(
          hasRevenue: true,
          hasCost: true,
          hasProfit: true,
          hasScale: true,
          hasScaleAlt: true,
          soloKey: 'profit',
        ),
        [false, false, true, false, false, false],
      );
      expect(
        lighthouseTrendVisibleFlags(
          hasRevenue: true,
          hasCost: true,
          hasProfit: true,
          hasScale: true,
          hasScaleAlt: true,
        ),
        [true, true, true, true, true, false],
      );
      expect(
        lighthouseTrendVisibleFlags(
          hasRevenue: true,
          hasCost: false,
          hasProfit: true,
          hasScale: true,
          hasScaleAlt: false,
          soloKey: 'cost',
        ),
        [true, false, true, true, false, false],
      );
      expect(
        lighthouseTrendVisibleFlags(
          hasRevenue: true,
          hasCost: true,
          hasProfit: true,
          hasScale: true,
          hasScaleAlt: true,
          hasCostAlt: true,
          soloKey: 'costAlt',
        ),
        [false, false, false, false, false, true],
      );
    });

    test('hero index follows scale, then the remaining visible line', () {
      expect(
        lighthouseTrendHeroIndex(const [true, true, true, true, true]),
        3,
      );
      expect(
        lighthouseTrendHeroIndex(const [true, true, true, false, true]),
        4,
      );
      expect(
        lighthouseTrendHeroIndex(const [true, true, true, false, false]),
        2,
      );
      expect(
        lighthouseTrendHeroIndex(const [true, false, false, false, false]),
        0,
      );
      expect(
        lighthouseTrendHeroIndex(const [false, true, false, false, false]),
        1,
      );
    });
  });
}
