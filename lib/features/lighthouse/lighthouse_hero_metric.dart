/// Hero masthead metric resolution (shared by page + unit tests).
library;

/// Whether [key] should render as a percentage in the Hero masthead.
bool lighthouseHeroMetricIsRate(String key) =>
    key == 'rate' || key == 'grossMargin' || key == 'spreadRate';

/// Shared compact Hero geometry for L1/L2/L3.
const int lighthouseCompactHeroKpiFlex = 3;
const int lighthouseCompactHeroTrendFlex = 7;
const double lighthouseCompactHeroSparkHeight = 92;
const double lighthouseCompactHeroMetricGap = 6;
const bool lighthouseHeroUsesCategoryTint = false;
const bool lighthouseHeroUsesAccentRail = false;
const bool lighthouseHeroShowsEnglishKicker = false;
const bool lighthouseHeroUsesCardShadow = true;
const bool lighthouseHeroMetricUsesSansLabel = true;
const double lighthouseHeroCardRadius = 10;
const double lighthouseHeroCardGap = 8;
const double lighthouseHeroCardPadding = 8;
const bool lighthouseHeroChartUsesCardSurface = true;
const double lighthouseHeroChartCardPadding = 6;
const bool lighthouseHeroSparkShowsAxes = false;
const bool lighthouseHeroSparkShowsGrid = false;
const bool lighthouseHeroSparkShowsAverage = false;
const bool lighthouseHeroSparkShowsEveryPeriodLabel = true;
const bool lighthouseHeroSparkShowsEveryValue = true;

String lighthouseHeroCompactPeriodLabel(String label) {
  final normalized = label.trim();
  final month = RegExp(r'^\d{4}[.-](\d{2})$').firstMatch(normalized);
  if (month != null) return '${month.group(1)}月';
  return normalized;
}

const double lighthouseHeroSectionIconSize = 18;
const lighthouseHeroSectionIconKeys = <String, String>{
  'scale': 'monitoring',
  'cost': 'receipt',
  'cash': 'wallet',
  'profit': 'trendingUp',
};
const lighthouseHeroSectionAccentValues = <String, int>{
  'scale': 0xFF7565C7,
  'cost': 0xFFB47A32,
  'cash': 0xFF3F7D70,
  'profit': 0xFF5C6FB5,
};
const bool lighthouseHeroShowsSectionAccentDash = false;
const bool lighthouseHeroMastheadLabelAboveNumber = true;
const double lighthouseHeroMastheadLabelFontSize = 11;
const double lighthouseHeroMastheadLabelIconSize = 18;
const double lighthouseHeroMastheadLabelRadius = 8;
const double lighthouseHeroGroupTitleFontSize = 10;
const double lighthouseHeroMastheadFontSize = 29;
const double lighthouseHeroMetricValueFontSize = 13;
const double lighthouseHeroMetricLabelFontSize = 9;
const double lighthouseHeroMetricDeltaFontSize = 8;
const int lighthouseHeroScaleColumnFlex = 10;
const int lighthouseHeroCostColumnFlex = 14;
const int lighthouseHeroResultColumnFlex = 15;
const double lighthouseLedgerExpandArrowVerticalOffset = 5;
const double lighthouseLedgerExpandArrowLayoutHeight = 18;
const bool lighthouseChannelDetailIncludesProvince = false;
const bool lighthouseChannelRootIncludesProvinceFilter = false;

/// Three Y-axis ticks used by the compact Hero chart.
List<double> lighthouseHeroAxisTicks(List<double> values) {
  if (values.isEmpty) return const <double>[0, 0.5, 1];
  var minValue = values.first;
  var maxValue = values.first;
  for (final value in values.skip(1)) {
    if (value < minValue) minValue = value;
    if (value > maxValue) maxValue = value;
  }
  if ((maxValue - minValue).abs() < 1e-9) {
    final proportional = minValue.abs() * 0.1;
    final padding = proportional > 1 ? proportional : 1.0;
    minValue -= padding;
    maxValue += padding;
  }
  return <double>[minValue, (minValue + maxValue) / 2, maxValue];
}

/// Stable persisted identity for a ledger row.
String lighthouseLedgerHighlightKey(String tab, Map<String, dynamic> row) {
  const identityFields = <String>[
    'name',
    'group',
    'key',
    'productCode',
    'supplierProductCode',
    'channelProductId',
    'projectId',
  ];
  String clean(Object? value) =>
      (value?.toString().trim() ?? '').replaceAll('\u001f', ' ');
  return <String>[
    clean(tab),
    for (final field in identityFields) clean(row[field]),
  ].join('\u001f');
}

/// Stable persisted identity for one metric cell in a ledger row.
String lighthouseLedgerCellHighlightKey(
  String tab,
  Map<String, dynamic> row,
  String metricKey,
) => '${lighthouseLedgerHighlightKey(tab, row)}\u001f${metricKey.trim()}';

class LighthouseHeroVerticalSection {
  const LighthouseHeroVerticalSection(this.key, this.title, this.metricKeys);

  final String key;
  final String title;
  final List<String> metricKeys;
}

const lighthouseHeroVerticalSections = <LighthouseHeroVerticalSection>[
  LighthouseHeroVerticalSection('scale', '规模', [
    'sales',
    'verifiedSales',
    'gmv',
  ]),
  LighthouseHeroVerticalSection('cost', '成本', [
    'totalCost',
    'projectCost',
    'cost',
    'directCost',
  ]),
  LighthouseHeroVerticalSection('cash', '经营性现金流', ['prepaid']),
  LighthouseHeroVerticalSection('profit', '利润', [
    'profit',
    'netProfit',
    'revenue',
    'spread',
    'grossMargin',
    'rate',
  ]),
];

const lighthouseHeroColumnSectionKeys = <List<String>>[
  ['scale'],
  ['cost', 'cash'],
  ['profit'],
];

const int lighthouseLedgerSummaryColumns = 2;
const double lighthouseLedgerNameFontSize = 11.5;
const double lighthouseLedgerPinnedWidthRatio = 0.35;
const double lighthouseLedgerPinnedMaxWidth = 164;
const lighthouseLedgerNavigationLevels = <String>[
  'primaryTab',
  'filterChip',
  'subSegment',
];
const double lighthouseLedgerPrimaryTabHeight = 44;
const double lighthouseLedgerFilterRowHeight = 42;
const double lighthouseLedgerFilterChipRadius = 8;
const bool lighthouseLedgerCentersPrimaryDimensions = false;
const bool lighthouseLedgerPrimaryDimensionsFillAvailableWidth = true;
const bool lighthouseLedgerSeparatesAnalysisTab = true;
const bool lighthouseLedgerUsesLavenderPanelFrame = true;
const double lighthouseLedgerPanelBorderWidth = 0.8;
const double lighthouseLedgerPanelRadius = 12;
const double lighthouseLedgerPanelShadowBlur = 12;
const bool lighthousePeriodUsesFloatingSegment = true;
const double lighthousePeriodTrackHeight = 44;
const double lighthousePeriodTrackRadius = 12;
const double lighthousePeriodSelectedRadius = 8;
const double lighthousePeriodStatusDotSize = 4;
const int lighthousePeriodAnimationMs = 180;
const double lighthouseAppBarTitleFontSize = 18;
const double lighthouseAppBarEnglishFontSize = 8.5;
const double lighthouseAppBarToolbarHeight = 34;
const double lighthouseAppBarToolbarRadius = 11;
const bool lighthouseHeroShowsLiveMetadata = false;
const double lighthouseHeroSummaryTitleFontSize = 13.5;
const double lighthouseHeroSummaryIconSize = 20;
const double lighthouseHeroSummaryIconRadius = 6;

String lighthouseHeroSummaryIconKey(String title) {
  final normalized = title.trim();
  if (normalized.contains('汇总')) {
    if (normalized.contains('产品')) return 'product';
    if (normalized.contains('供给') || normalized.contains('供应')) {
      return 'supply';
    }
    if (normalized.contains('渠道')) return 'channel';
  }
  if (normalized.contains('分析')) return 'analysis';
  return 'overview';
}

const double lighthouseCategoryLogoSize = 14;

String? lighthouseCategoryBrandAsset(String label) {
  final normalized = label.trim();
  if (normalized.contains('中石油') || normalized.contains('中国石油')) {
    return 'assets/brands/petrochina.svg';
  }
  if (normalized.contains('中石化') || normalized.contains('中国石化')) {
    return 'assets/brands/sinopec.svg';
  }
  if (normalized.contains('平安')) return 'assets/brands/ping_an.svg';
  if (normalized.contains('移动')) return 'assets/brands/china_mobile.svg';
  if (normalized.contains('电信')) return 'assets/brands/china_telecom.svg';
  if (normalized.contains('联通')) return 'assets/brands/china_unicom.svg';
  if (normalized.contains('银联')) return 'assets/brands/unionpay.svg';
  return null;
}

const lighthouseLedgerSummaryMetricKeys = <String>[
  'sales',
  'verifiedSales',
  'prepaid',
  'profit',
  'costTotal',
];
const lighthouseLedgerSummaryMetricRows = <List<String>>[
  ['sales', 'verifiedSales'],
  ['profit', 'costTotal'],
];
const lighthouseProductLedgerSummaryMetricRows = <List<String>>[
  ['sales', 'prepaid'],
  ['verifiedSales', 'profit'],
];

List<List<String>> lighthouseLedgerSummaryMetricRowsForTab(String tab) =>
    tab == 'product'
    ? lighthouseProductLedgerSummaryMetricRows
    : lighthouseLedgerSummaryMetricRows;

String lighthouseLedgerHighlightModeLabel({
  required bool rowMode,
  required bool cellMode,
}) {
  if (rowMode) return '行标记';
  if (cellMode) return '格标记';
  return '标记';
}

/// Resolve a totals value with key aliases used across L1/L2 payloads.
double? lighthouseHeroMetricValue(Map<String, double> totals, String key) {
  switch (key) {
    case 'totalCost':
    case 'costTotal':
      return totals['totalCost'] ?? totals['costTotal'];
    case 'cost':
    case 'businessCost':
      return totals['cost'] ?? totals['businessCost'];
    default:
      return totals[key];
  }
}

/// Human label for a metric key (fallback = key).
String lighthouseHeroMetricLabel(String key) {
  const labels = <String, String>{
    'sales': '销售额',
    'verifiedSales': '核销额',
    'revenue': '收入',
    'spread': '利差',
    'profit': '毛利润',
    'netProfit': '净利润',
    'totalCost': '成本合计',
    'costTotal': '成本合计',
    'projectCost': '项目成本',
    'cost': '业务成本',
    'businessCost': '业务成本',
    'directCost': '直接成本',
    'grossMargin': '毛利率',
    'rate': 'ROI',
    'spreadRate': '利差率',
  };
  return labels[key] ?? key;
}

/// Period-prefixed masthead label, e.g. 本日核销额 / 本月毛利润.
String lighthouseHeroMetricPeriodLabel(String period, String metricKey) {
  final metric = lighthouseHeroMetricLabel(metricKey);
  final prefix = switch (period) {
    'day' => '本日',
    'week' => '本周',
    'month' => '本月',
    'quarter' => '本季',
    'year' => '本年',
    _ => '',
  };
  return prefix.isEmpty ? metric : '$prefix$metric';
}

/// Masthead key is always 毛利润.
///
/// Expanded metric cells / 核销·销售 chips only drive the sparkline panel or
/// efficiency denominators (ROI / 毛利率); they must not change the hero number.
String lighthouseHeroMastheadKey(String? expandedTrendKey) {
  // Keep the parameter so call sites stay stable; intentionally unused.
  // ignore: unused_parameter
  final _ = expandedTrendKey;
  return 'profit';
}

/// Every Hero sparkline point must receive a visible value label.
List<int> lighthouseHeroSparkLabelIndices(int count) =>
    count <= 0 ? const <int>[] : List<int>.generate(count, (index) => index);

/// Period cache key for L2 detail payloads (write + stale check must match).
String lighthouseDetailPeriodCacheKey({
  required String period,
  required int periodOffset,
  DateTime? customStart,
  DateTime? customEnd,
}) =>
    '$period:$periodOffset:${customStart?.toIso8601String() ?? ''}:${customEnd?.toIso8601String() ?? ''}';

/// Clamp a saved L1 list offset into the valid range after returning from L2.
double lighthouseRestoreScrollOffset(double saved, double maxExtent) {
  if (saved.isNaN || saved.isInfinite || saved < 0) return 0;
  if (maxExtent.isNaN || maxExtent.isInfinite || maxExtent < 0) return 0;
  return saved > maxExtent ? maxExtent : saved;
}

double lighthouseValidRateBase(double value, {double minimumBase = 50}) =>
    value >= minimumBase ? value : 0;

/// 毛利率走势 = 毛利润 ÷ 核销额，单位为百分点。
List<double> lighthouseGrossMarginSeries({
  required List<double> profit,
  required List<double> verifiedSales,
  double minimumBase = 50,
}) {
  final count = profit.length < verifiedSales.length
      ? profit.length
      : verifiedSales.length;
  return List<double>.generate(count, (index) {
    final base = verifiedSales[index];
    final validBase = lighthouseValidRateBase(base, minimumBase: minimumBase);
    return validBase > 0 ? profit[index] / validBase * 100 : 0;
  }, growable: false);
}

/// 直接成本走势兜底：成本合计 − 项目成本 − 业务成本。
/// 有后端 directCost（cost_gross_profit）序列时优先直读，不必走此公式。
List<double> lighthouseDirectCostSeries({
  required List<double> totalCost,
  required List<double> projectCost,
  required List<double> businessCost,
}) {
  final count = [
    totalCost.length,
    projectCost.length,
    businessCost.length,
  ].reduce((a, b) => a < b ? a : b);
  return List<double>.generate(
    count,
    (index) => totalCost[index] - projectCost[index] - businessCost[index],
    growable: false,
  );
}

bool lighthouseCanFallbackToRootTrend({required bool isDrill}) => !isDrill;

bool lighthouseCanUseRootComparison({required bool hasTotalsOverride}) =>
    !hasTotalsOverride;

/// 环比必须来自明确的本期/上期窗口，禁止用走势图相邻点推断。
bool lighthouseCanInferPeriodDeltaFromTrend() => false;

/// 解析 L1 默认分类：精确匹配 → 模糊包含 → 不存在则回退「全部」。
/// 避免日维度供给无「中石油」时仍锁默认分类导致列表被滤空。
String lighthouseResolvePreferredGroup({
  required String preferred,
  required List<String> options,
}) {
  final want = preferred.trim().isEmpty ? '全部' : preferred.trim();
  if (want == '全部') return '全部';
  if (options.contains(want)) return want;
  final idx = options.indexWhere((g) => g != '全部' && g.contains(want));
  if (idx >= 0) return options[idx];
  return '全部';
}
