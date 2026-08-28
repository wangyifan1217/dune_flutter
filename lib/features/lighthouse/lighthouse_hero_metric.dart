/// Hero masthead metric resolution (shared by page + unit tests).
library;

/// Whether [key] should render as a percentage in the Hero masthead.
bool lighthouseHeroMetricIsRate(String key) =>
    key == 'rate' ||
    key == 'grossMargin' ||
    key == 'spreadRate' ||
    key == 'sharePct';

/// Shared compact Hero geometry for L1/L2/L3.
const int lighthouseCompactHeroKpiFlex = 3;
const int lighthouseCompactHeroTrendFlex = 7;

/// 给左侧 KPI（标签 + 大数 +「↓xx% vs 昨日」）留足高度，避免环比被裁切。
const double lighthouseCompactHeroSparkHeight = 180;

/// 窄屏仍左右并排：走势图略加高，但不把「本日毛利润」整块挪到图上面。
const double lighthouseCompactHeroSparkHeightNarrow = 216;
const double lighthouseCompactHeroChartMaxHeightWide = 84;
const double lighthouseCompactHeroChartMaxHeightNarrow = 112;
const double lighthouseCompactHeroNarrowBreakpoint = 600;

bool lighthouseCompactHeroIsNarrow(double width) =>
    width < lighthouseCompactHeroNarrowBreakpoint;

double lighthouseCompactHeroSparkHeightFor(double width) =>
    lighthouseCompactHeroIsNarrow(width)
        ? lighthouseCompactHeroSparkHeightNarrow
        : lighthouseCompactHeroSparkHeight;

/// 净TA 与产品 Hero 同一高度：项目 / 业务成本叠进总览图，不再垫分图。
/// 左侧再叠银行余额存量块时加高一截，否则「↓xx% vs …」环比行会溢 12px。
const double lighthouseNetTABankBalanceExtraHeight = 24;

double lighthouseNetTAHeroSparkHeightFor(
  double width, {
  bool hasBankBalance = false,
}) =>
    lighthouseCompactHeroSparkHeightFor(width) +
    (hasBankBalance ? lighthouseNetTABankBalanceExtraHeight : 0);

double lighthouseCompactHeroChartMaxHeightFor(double width) =>
    lighthouseCompactHeroIsNarrow(width)
        ? lighthouseCompactHeroChartMaxHeightNarrow
        : lighthouseCompactHeroChartMaxHeightWide;

/// Hero §02 区块总高度（含走势卡 padding）。窄宽都是左右并排。
double lighthouseCompactHeroBlockHeightFor(double width) =>
    lighthouseCompactHeroSparkHeightFor(width) + lighthouseHeroChartCardPadding * 2;

const double lighthouseCompactHeroMetricGap = 6;
const bool lighthouseHeroUsesCategoryTint = false;
const bool lighthouseHeroUsesAccentRail = false;
const bool lighthouseHeroShowsEnglishKicker = false;
const bool lighthouseHeroUsesCardShadow = false;
const bool lighthouseHeroMetricUsesSansLabel = true;
const double lighthouseHeroCardRadius = 12;
const double lighthouseHeroCardGap = 8;
const double lighthouseHeroCardPadding = 8;
const bool lighthouseHeroChartUsesCardSurface = true;
const double lighthouseHeroChartCardPadding = 8;
const bool lighthouseHeroSparkShowsAxes = false;
const bool lighthouseHeroSparkShowsGrid = false;
const bool lighthouseHeroSparkShowsAverage = false;
const bool lighthouseHeroSparkShowsEveryPeriodLabel = false;
const bool lighthouseHeroSparkShowsEveryValue = false;

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
/// 「规模」语义色。hero 规模卡的 accent 和走势图的规模线族（核销主线 /
/// 销售细线 / 两者之间的带 / 月末预测虚线）共用它 —— 两处同色才能让
/// 「规模」在跨屏时是同一个东西，所以抽成一个常量，别再各写各的字面量。
const int lighthouseScaleAccentValue = 0xFF7565C7;

/// 走势图毛利线。不能跟规模 accent 同紫族：规模带一铺，毛利就溶进带里，
/// APP 一级/二级更窄，副行再一截断，毛利数字也会一起消失。
const int lighthouseProfitAccentValue = 0xFFC45C26;

/// 走势图收入线。青 —— 由 #185FA5（冷蓝）换来。
///
/// 换的原因是量过的：蓝 #185FA5 与规模紫 #7565C7 在 OKLab 下正常视力色差只有
/// 12.3（安全线 15），红绿色觉下只有 6.6 —— 它们本来就是一个色团，五条线叠在
/// 一起时收入和规模根本分不开。换成青之后，紫/青/琥珀/橙 四色两两最差色差：
/// 正常视力 13.0、红绿色觉 8.4，紫青这一对提到 20.0。
///
/// 剩下那个 13.0 是「成本琥珀 ↔ 毛利橙」—— 相邻色相，靠调深浅解决不了。它现在
/// 可接受，是因为 v16 的三种排版都不再把线叠在一起：每条线自己一格 / 一条带，
/// 身份由「位置 + 常驻名字和数字」承担，颜色只是辅助。真要把这一对也拉开，
/// 毛利得挪到朱红 #D63F3F（四色全过线）—— 但中国金融色里红=涨，得先确认。
const int lighthouseRevenueAccentValue = 0xFF0E9384;

/// 走势图成本线。琥珀，对应利润恒等式「支出」，不能再跟规模同紫。
const int lighthouseCostAccentValue = 0xFF854F0B;

/// 净TA 业务成本线。钢蓝，与经营成本琥珀、项目成本橙分开。
const int lighthouseNetTABizCostAccentValue = 0xFF3B6E96;

/// 核销 / 销售几乎同量级，叠同一根 Y 会贴成一条线，所以各占一行、各自归一。
/// 收入 / 成本 / 毛利量级接近，仍共用一格。
bool lighthouseHeroTrendIsScaleKey(String key) =>
    key == 'verifiedSales' || key == 'sales';

/// 规模每条单独一格；损益三条合为一格。
List<List<int>> lighthouseHeroTrendPaneIndexes(List<String> keys) {
  final scale = <int>[];
  final pnl = <int>[];
  for (var i = 0; i < keys.length; i++) {
    if (lighthouseHeroTrendIsScaleKey(keys[i])) {
      scale.add(i);
    } else {
      pnl.add(i);
    }
  }
  return [
    for (final i in scale) <int>[i],
    if (pnl.isNotEmpty) pnl,
  ];
}

/// 叠线的损益格多留高度；规模单行矮一档。
int lighthouseHeroTrendPaneFlex(int lineCount) => lineCount >= 3 ? 3 : 2;

/// 格内量级差得开时把下沿收到 0，让收入 / 成本 / 毛利的高低有真实比例。
/// 核销和销售几乎贴在一起，不能收到 0，否则两条都会贴死在格顶。
bool lighthouseHeroPaneSnapsToZero({
  required double min,
  required double max,
}) {
  if (min < -1e-9 || max <= 1e-9) return false;
  return min < max * 0.5;
}

/// APP 窄屏图例必须换行；规模主线也在这一行，不再挂在「本期合计」旁边。
List<String> lighthouseTrendPnlLegendKeys({
  required bool hasProfit,
  required bool hasRevenue,
  required bool hasCost,
  required bool hasScaleAlt,
  bool hasScale = false,
  bool hasCostAlt = false,
}) {
  return [
    if (hasScale) 'scale',
    if (hasProfit) 'profit',
    if (hasCostAlt) 'costAlt',
    if (hasRevenue) 'revenue',
    if (hasCost) 'cost',
    if (hasScaleAlt) 'scaleAlt',
  ];
}

/// 「本期合计」旁边不再挂主指标大数，所有指标只走下方小图例。
const bool lighthouseTrendShowsHeroMetricBesideStatus = false;

/// 环比默认折到第二行；第一行只放名称 + 金额，避免跟环比抢宽度。
const bool lighthouseTrendLegendMomOnSecondLine = true;

/// 手机窄宽时图例按此最小宽度换行，保证「核销规模 463.1万」和环比都能看见。
const double lighthouseTrendLegendMinChipWidth = 78;

const double lighthouseTrendLegendAllSlotWidth = 28;

/// 图例环比文案自身约占宽度；不再跟金额挤在同一列。
const double lighthouseTrendLegendMomWidth = 48;

bool lighthouseTrendLegendShouldWrap({
  required double width,
  required int metricCount,
  bool showAll = false,
}) {
  if (metricCount <= 0) return false;
  final need =
      (showAll ? lighthouseTrendLegendAllSlotWidth : 0) +
      metricCount * lighthouseTrendLegendMinChipWidth;
  return width + 1e-6 < need;
}

/// 环比永远跟在金额后面（含点选某日）；优先后端口径（上月同日 / 上月同期）。
double? lighthouseTrendMomPct({
  required double? periodDeltaPct,
  required bool partialPeriod,
  required bool isSelected,
  required List<double> series,
}) {
  if (periodDeltaPct != null) return periodDeltaPct;
  if (isSelected || partialPeriod || series.length < 2) return null;
  final prev = series[series.length - 2];
  if (prev.abs() <= 1e-6) return null;
  return (series.last - prev) / prev.abs() * 100;
}

/// 图例环比文案：箭头表达方向，数字用绝对值，避免「↓ -12%」。
/// 固定 1 位小数，四项列宽才齐。
String lighthouseTrendMomLabel(double pct) {
  return '${pct >= 0 ? '↑' : '↓'} ${pct.abs().toStringAsFixed(1)}%';
}

/// `_TrendChart` 六条序列在 `available` 里的下标。
/// [revenue, cost, profit, scale, scaleAlt, costAlt]
const lighthouseTrendSeriesKeys = <String>[
  'revenue',
  'cost',
  'profit',
  'scale',
  'scaleAlt',
  'costAlt',
];

/// 点图例：再点当前项（或点「全部」）恢复全显；点另一项只留该项。
String? lighthouseTrendSoloAfterTap(String? current, String tapped) {
  if (tapped.isEmpty) return null;
  return current == tapped ? null : tapped;
}

/// 应用 solo 后的可见性，长度恒为 6。solo 指向没有数据的项时保持原样。
List<bool> lighthouseTrendVisibleFlags({
  required bool hasRevenue,
  required bool hasCost,
  required bool hasProfit,
  required bool hasScale,
  required bool hasScaleAlt,
  bool hasCostAlt = false,
  String? soloKey,
}) {
  final base = <bool>[
    hasRevenue,
    hasCost,
    hasProfit,
    hasScale,
    hasScaleAlt,
    hasCostAlt,
  ];
  if (soloKey == null || soloKey.isEmpty) return base;
  final i = lighthouseTrendSeriesKeys.indexOf(soloKey);
  if (i < 0 || !base[i]) return base;
  return <bool>[
    for (var k = 0; k < 6; k++) k == i,
  ];
}

/// 粗线 / 填充 / MAX·MIN 跟哪条走：规模在场时归规模，否则第一条可见的
/// 规模副线 / 毛利 / 收入 / 成本。
int lighthouseTrendHeroIndex(List<bool> available) {
  const order = <int>[3, 4, 2, 0, 1, 5];
  for (final i in order) {
    if (i < available.length && available[i]) return i;
  }
  return 2;
}

/// 核销 / 销售才共用一根 Y（看未核销差额）。项目成本三级量级差百倍，必须各自归一。
bool lighthouseTrendShareScaleRange({
  required String scaleLabel,
  required String scaleAltLabel,
}) {
  bool isSalesFamily(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    return s.contains('核销') || s.contains('销售') || s == '规模';
  }

  return isSalesFamily(scaleLabel) && isSalesFamily(scaleAltLabel);
}

/// 单条走势自己的值域：上下留 8% 边，全点相等时扩一截以免贴成一条边。
({double min, double max}) lighthouseTrendSeriesRange(List<double> values) {
  if (values.isEmpty) return (min: 0.0, max: 1.0);
  var mn = values.first;
  var mx = values.first;
  for (final v in values) {
    if (v < mn) mn = v;
    if (v > mx) mx = v;
  }
  final span = mx - mn;
  if (span.abs() < 1e-9) {
    final pad = mx.abs() * 0.1;
    final floor = pad < 1e-9 ? 1.0 : pad;
    return (min: mn - floor, max: mx + floor);
  }
  final pad = span * 0.08;
  return (min: mn - pad, max: mx + pad);
}

const lighthouseHeroSectionAccentValues = <String, int>{
  'scale': lighthouseScaleAccentValue,
  'cost': 0xFFB47A32,
  'cash': 0xFF7B5CD8,
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

/// v18 · 展开箭头下移到冻结列最后一行（毛利率行）。
/// 它和名称行的穿透箭头 › 之间隔着「分类」「占比/走势」两整行，
/// 视觉与热区都彻底分离，不再需要靠 Transform 偏移来躲。
const double lighthouseLedgerExpandArrowVerticalOffset = 3;
const double lighthouseLedgerExpandArrowLayoutHeight = 14;
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
  ]),
  LighthouseHeroVerticalSection('cash', '经营性净现金流', ['prepaid']),
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

/// 点 Hero 格子不再出公式面板；走势图用与账本总图同一套 `_TrendChart`。
const bool lighthouseHeroShowsMetricFormulas = false;

/// 底下不再堆每条指标一张图；点格子只改顶部那一张。
const bool lighthouseHeroShowsAllMetricTrends = false;

/// 顶部总图上的五条线：核销 / 销售 / 收入 / 成本合计 / 毛利。
/// 点这些格子 = 总图里只留这一条；点其他格子 = 整张图换成该指标。
const Set<String> lighthouseHeroOverlayMetricKeys = <String>{
  'sales',
  'verifiedSales',
  'revenue',
  'totalCost',
  'costTotal',
  'profit',
};

bool lighthouseHeroMetricIsOverlay(String key) =>
    lighthouseHeroOverlayMetricKeys.contains(key);

/// 点同一格回到总图；点另一格切到那一项。
String? lighthouseHeroTrendFocusAfterTap(String? current, String tapped) {
  if (tapped.trim().isEmpty) return current;
  return current == tapped ? null : tapped;
}

/// 总图五条线对应 `_TrendChart` 的 slot。不是这五条时返回 null，由调用方换整张图。
String? lighthouseHeroOverlaySoloSlot({
  required String? metricKey,
  required String scaleKey,
  required String scaleAltKey,
  bool hasScale = true,
  bool hasScaleAlt = true,
}) {
  if (metricKey == null || metricKey.isEmpty) return null;
  switch (metricKey) {
    case 'profit':
      return 'profit';
    case 'revenue':
      return 'revenue';
    case 'totalCost':
    case 'costTotal':
      return 'cost';
    case 'sales':
    case 'verifiedSales':
      if (metricKey == scaleKey) return hasScale ? 'scale' : null;
      if (metricKey == scaleAltKey) return hasScaleAlt ? 'scaleAlt' : null;
      return hasScale ? 'scale' : (hasScaleAlt ? 'scaleAlt' : null);
    default:
      return null;
  }
}

List<String> lighthouseHeroMetricTrendKeys() => [
  for (final section in lighthouseHeroVerticalSections) ...section.metricKeys,
];

const String lighthouseCostBillMetricPrefix = 'costBill:';

String lighthouseCostBillMetricKey(String code) =>
    '$lighthouseCostBillMetricPrefix${code.trim()}';

bool lighthouseIsCostBillMetric(String key) =>
    key.startsWith(lighthouseCostBillMetricPrefix) &&
    key.length > lighthouseCostBillMetricPrefix.length;

String? lighthouseCostBillCode(String key) {
  if (!lighthouseIsCostBillMetric(key)) return null;
  final code = key.substring(lighthouseCostBillMetricPrefix.length).trim();
  return code.isEmpty ? null : code;
}

List<Map<String, String>> lighthouseParseCostBillTypes(dynamic raw) {
  if (raw is! List) return const [];
  final out = <Map<String, String>>[];
  final seen = <String>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final key = '${item['key'] ?? item['code'] ?? ''}'.trim();
    final label = '${item['label'] ?? item['name'] ?? key}'.trim();
    final category = '${item['category'] ?? ''}'.trim();
    if (key.isEmpty || !seen.add(key)) continue;
    out.add({
      'key': key,
      'label': label.isEmpty ? key : label,
      'category': category,
      'l1': '${item['l1'] ?? item['billTypeL1Name'] ?? ''}'.trim(),
      'l2': '${item['l2'] ?? item['billTypeL2Name'] ?? ''}'.trim(),
    });
  }
  return out;
}

List<String> lighthouseHeroCostBillTrendKeys(dynamic raw) => [
  for (final item in lighthouseParseCostBillTypes(raw))
    lighthouseCostBillMetricKey(item['key']!),
];

String lighthouseCostBillTypeLabel(String metricKey, dynamic typesRaw) {
  final code = lighthouseCostBillCode(metricKey);
  if (code == null) return lighthouseHeroMetricLabel(metricKey);
  for (final item in lighthouseParseCostBillTypes(typesRaw)) {
    if (item['key'] == code) return item['label'] ?? code;
  }
  return code;
}

List<double> lighthouseCostBillTypeSeries(dynamic seriesRaw, String metricKey) {
  final code = lighthouseCostBillCode(metricKey);
  if (code == null || seriesRaw is! Map) return const <double>[];
  final raw = seriesRaw[code] ?? seriesRaw[metricKey];
  if (raw is! List || raw.isEmpty) return const <double>[];
  return [
    for (final e in raw) (e is num) ? e.toDouble() : 0.0,
  ];
}

const lighthouseProjectCostPreferredLabels = [
  '平台服务费',
  '支付手续费',
  '机构返佣',
];

class LighthouseCostBillChartLine {
  const LighthouseCostBillChartLine({
    required this.key,
    required this.label,
    required this.category,
    required this.values,
  });
  final String key;
  final String label;
  final String category;
  final List<double> values;
}

String lighthouseCostBillChartLabel(Map<String, String> item) {
  final l3 = (item['label'] ?? '').trim();
  return l3.isEmpty ? (item['key'] ?? '') : l3;
}

/// 趋势图 X 轴：每个数据点都标日期，不做稀疏采样（避免 8.22 / 8.25 等中间日期空白）。
(List<String>, List<int>) lighthouseTrendXAxisLabels(
  List<String> labels,
  int pointCount,
) {
  final count = labels.length;
  if (count == 0 || pointCount == 0) {
    return (const <String>[], const <int>[]);
  }
  return (
    [
      for (final label in labels) lighthouseHeroCompactPeriodLabel(label),
    ],
    List<int>.generate(count, (i) => i),
  );
}

/// 供给卡片资金池展开：右侧独立全高点击条（不缩放，保证手机好点）。
const double lighthouseFundPoolExpandTapWidth = 44;
const double lighthouseFundPoolExpandIconSize = 22;

/// 票税收起格有应开 / 实开 / 原件三行，必须高于普通 KPI 格（43），否则会 overflow。
// 预览行高。票税不再是三行的异形格之后，这里只需要和普通指标格一样高；
// 实际取值是 max(这个数, summaryCellHeight)，所以给一个不会顶高整行的下限。
const double lighthouseFundPoolPreviewHeight = 44;

double lighthouseFundPoolPreviewRowHeight({
  required double summaryCellHeight,
  required double scale,
}) {
  final scaled = (lighthouseFundPoolPreviewHeight * scale).roundToDouble();
  return scaled < summaryCellHeight ? summaryCellHeight : scaled;
}

double lighthouseFundPoolPreviewExtraHeight({
  required double summaryCellHeight,
  required double scale,
}) {
  return lighthouseFundPoolPreviewRowHeight(
        summaryCellHeight: summaryCellHeight,
        scale: scale,
      ) -
      summaryCellHeight;
}

bool lighthouseSeriesHasVisibleData(List<double> series) {
  if (series.length < 2) return false;
  for (final v in series) {
    if (v.abs() > 1e-9) return true;
  }
  return false;
}

int lighthouseProjectCostLineRank(String label) {
  for (var i = 0; i < lighthouseProjectCostPreferredLabels.length; i++) {
    if (label.contains(lighthouseProjectCostPreferredLabels[i])) return i;
  }
  return lighthouseProjectCostPreferredLabels.length;
}

/// 项目成本图：资管 PROJECT_COST 三级各一条，优先平台服务费 / 支付手续费 / 机构返佣。
List<LighthouseCostBillChartLine> lighthouseCostBillChartLines({
  required dynamic typesRaw,
  required dynamic seriesRaw,
  required String category,
  int maxLines = 5,
}) {
  final wanted = category.trim();
  final lines = <LighthouseCostBillChartLine>[];
  for (final item in lighthouseParseCostBillTypes(typesRaw)) {
    if (wanted.isNotEmpty && item['category'] != wanted) continue;
    final key = item['key'] ?? '';
    if (key.isEmpty) continue;
    final values = lighthouseCostBillTypeSeries(
      seriesRaw,
      lighthouseCostBillMetricKey(key),
    );
    if (!lighthouseSeriesHasVisibleData(values)) continue;
    lines.add(
      LighthouseCostBillChartLine(
        key: key,
        label: lighthouseCostBillChartLabel(item),
        category: item['category'] ?? '',
        values: values,
      ),
    );
  }
  lines.sort((a, b) {
    final rank = lighthouseProjectCostLineRank(
      a.label,
    ).compareTo(lighthouseProjectCostLineRank(b.label));
    return rank != 0 ? rank : 0;
  });
  if (lines.length <= maxLines) return lines;
  return lines.take(maxLines).toList(growable: false);
}

/// 单条 Hero 走势落在 `_TrendChart` 哪一条槽，决定线色。
String lighthouseHeroTrendChartSlot(String key) {
  if (lighthouseIsCostBillMetric(key)) return 'cost';
  switch (key) {
    case 'revenue':
      return 'revenue';
    case 'totalCost':
    case 'costTotal':
    case 'projectCost':
    case 'cost':
    case 'businessCost':
      return 'cost';
    case 'profit':
    case 'netProfit':
    case 'spread':
      return 'profit';
    default:
      return 'scale';
  }
}

bool lighthouseHeroTrendChartIsRate(String key) =>
    key == 'rate' || key == 'grossMargin' || key == 'spreadRate';

const int lighthouseLedgerSummaryColumns = 2;

/// 名称略大于右侧核心数字，数字不压过业务名称。
const double lighthouseLedgerNameFontSize = 12.5;

/// 产品等偏长名称：列表冻结列用更小字号，少截断。
const double lighthouseLedgerLongNameFontSize = 11.0;

/// 二级「项目」名称更长，再降一档。
const double lighthouseLedgerProjectNameFontSize = 10.0;
const double lighthouseLedgerValueFontSize = 11.5;
/// 金额单位（万/亿/%）相对数字略小一档，与摘要格历史口径一致；字重用常规体。
const double lighthouseLedgerUnitFontSize = 9.0;
const double lighthouseLedgerMetricLabelFontSize = 10;
const double lighthouseLedgerDeltaFontSize = 9;

/// 供给/渠道用标准名称字号；产品用长名字号；项目更小。
double lighthouseLedgerNameFontSizeForTab(String tab) {
  switch (tab) {
    case 'project':
      return lighthouseLedgerProjectNameFontSize;
    case 'product':
    case 'productName':
      return lighthouseLedgerLongNameFontSize;
    default:
      return lighthouseLedgerNameFontSize;
  }
}

/// 「越低越好」的指标 —— 成本类。其余（规模 / 利润 / 现金流 / 率）越高越好。
const Set<String> lighthouseLedgerLowerIsBetterKeys = <String>{
  'costTotal',
  'totalCost',
  'projectCost',
  'cost',
  'businessCost',
};

/// 环比变化是否「向好」。返回 null = 无变化 / 数据缺失，应走中性色。
///
/// 颜色表达的是**好坏**而不是**涨跌**：方向已经由 ↑↓ 箭头和正负号表达了两遍，
/// 再用颜色重复编码一次方向没有信息量。旧口径无条件「涨红跌绿」，
/// 会把销售额 −50%、毛利润 −86% 渲染成一片绿色 —— 崩盘看起来像向好。
bool? lighthouseLedgerDeltaIsFavorable(String key, double? delta) {
  if (delta == null || delta.abs() < 0.05) return null;
  return lighthouseLedgerLowerIsBetterKeys.contains(key)
      ? delta < 0
      : delta > 0;
}

/// 环比颜色只表达方向：中国金融色，上涨红、下跌绿。
bool? lighthouseLedgerDeltaIsUp(double? delta) {
  if (delta == null || delta.abs() < 0.05) return null;
  return delta > 0;
}

/// 收起态核心数字 / 排序列用黑体（700）；展开态普通列略轻（600）。
/// 返回 FontWeight 的 numeric value，避免本文件依赖 Flutter painting。
int lighthouseLedgerValueWeightValue({
  required bool missing,
  required bool emphasized,
}) {
  if (missing) return 500;
  return emphasized ? 700 : 600;
}

const double lighthouseLedgerPinnedWidthRatio = 0.35;
const double lighthouseLedgerPinnedMaxWidth = 164;
const double lighthouseLedgerPinnedMinWidth = 112;

/// 净TA 五类名只有四字，但收起态还要给 01 和展开箭头留位；左栏再宽一截，
/// 避免「经营活动 / 经营成本」被箭头和右边指标卡挡住，看起来像同一个词出现两次。
const double lighthouseLedgerNetTAPinnedWidthRatio = 0.42;
const double lighthouseLedgerNetTAPinnedMinWidth = 136;

double lighthouseLedgerPinnedWidthFor(double width, {required String tab}) {
  final ratio = tab == 'netTa'
      ? lighthouseLedgerNetTAPinnedWidthRatio
      : lighthouseLedgerPinnedWidthRatio;
  final min = tab == 'netTa'
      ? lighthouseLedgerNetTAPinnedMinWidth
      : lighthouseLedgerPinnedMinWidth;
  return (width * ratio).clamp(min, lighthouseLedgerPinnedMaxWidth).toDouble();
}

/// 占比继续显示为文字与走势，不再用整行底色重复编码。
const bool lighthouseLedgerShowsShareWash = false;
const bool lighthouseLedgerCollapsedShowsShare = false;
const bool lighthouseLedgerCollapsedShowsSparkline = false;
const bool lighthouseLedgerCollapsedShowsGroup = false;
const bool lighthouseLedgerCollapsedShowsGrossMargin = true;

/// 分组文字关掉之后，冻结列那条 3px 彩条就没有图例可以解码了 ——
/// 六种颜色对用户等价于噪点。跟着 ShowsGroup 一起关；要恢复请两个一起开。
const bool lighthouseLedgerCollapsedShowsGroupColorBar =
    lighthouseLedgerCollapsedShowsGroup;

/// 摘要网格标题 —— 列数是数据驱动的（整列空值会被摘掉），标题跟着变。
String lighthouseLedgerSummaryTitle(int count) {
  const cn = ['零', '一', '二', '三', '四', '五', '六', '七', '八'];
  final n = count >= 0 && count < cn.length ? cn[count] : '$count';
  return '$n项核心指标';
}

const lighthouseLedgerPrimaryTabs = <String>[
  'product',
  'supply',
  'channel',
  'netTa',
  'analysis',
];

const lighthouseLedgerPrimaryTabLabels = <String, String>{
  'product': '产品',
  'supply': '供给方',
  'channel': '渠道',
  'netTa': '净TA',
  'analysis': '分析',
};

bool lighthouseLedgerTabShowsCategoryChips(String tab) =>
    tab == 'product' || tab == 'supply' || tab == 'channel';

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
const bool lighthouseLedgerSeparatesAnalysisTab = false;
const bool lighthouseLedgerPrimaryTabUsesPeriodSegment = true;
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
const int lighthouseAppBarTitleColorValue = 0xFF7C5CE6;
const double lighthouseAppBarEnglishFontSize = 8.5;
const double lighthouseAppBarToolbarHeight = 34;
const double lighthouseAppBarToolbarRadius = 11;

/// 日期与同步状态跟「灯塔 LIGHTHOUSE」同一行，不再单独占一行。
const bool lighthouseAppBarPutsDateOnTitleRow = false;
const bool lighthouseHeroShowsLiveMetadata = false;

/// 同步胶囊时间戳：日期 + 时分，强制由调用方传入 CST 时刻。
String lighthouseSyncedAtStamp(DateTime t) {
  final y = t.year.toString();
  final mo = t.month.toString().padLeft(2, '0');
  final dd = t.day.toString().padLeft(2, '0');
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '$y.$mo.$dd $hh:$mm';
}
const double lighthouseHeroSummaryTitleFontSize = 13.5;
const double lighthouseHeroSummaryIconSize = 20;
const double lighthouseHeroSummaryIconRadius = 6;

String lighthouseHeroSummaryIconKey(String title) {
  final normalized = title.trim();
  // 一级「xx汇总」、二级/三级「产品|供给|渠道 · 实体」都按前缀/关键字识别。
  if (normalized.startsWith('产品') ||
      (normalized.contains('汇总') && normalized.contains('产品'))) {
    return 'product';
  }
  if (normalized.startsWith('供给') ||
      normalized.startsWith('供应') ||
      (normalized.contains('汇总') &&
          (normalized.contains('供给') || normalized.contains('供应')))) {
    return 'supply';
  }
  if (normalized.startsWith('渠道') ||
      (normalized.contains('汇总') && normalized.contains('渠道'))) {
    return 'channel';
  }
  if (normalized.startsWith('净TA') ||
      normalized.contains('净TA') ||
      normalized.toLowerCase().contains('netta')) {
    return 'netTa';
  }
  if (normalized.contains('分析')) return 'analysis';
  return 'overview';
}

const double lighthouseCategoryLogoSize = 14;
const double lighthouseHeroCategoryLogoSize = 18;

/// L1 选中具体分类时，主 Hero 标题位与分类字样旁展示该分类 logo。
bool lighthouseHeroShowsCategoryLogo(String groupFilter) {
  final normalized = groupFilter.trim();
  return normalized.isNotEmpty && normalized != '全部';
}

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

const lighthouseLedgerSummaryBlankKey = '_blank';

/// Flatten 净TA 五类映射为列表行：父行带流入/流出/占比，二级分类留在 secondaries。
List<Map<String, dynamic>> lighthousePrepareNetTARows(
  List<Map<String, dynamic>> categories,
) {
  final parents = <Map<String, dynamic>>[];
  for (final raw in categories) {
    final cat = Map<String, dynamic>.from(raw);
    final name = cat['name']?.toString() ?? '';
    if (name.isEmpty) continue;
    final secondaries = (cat['secondaries'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['name']?.toString() ?? '').isNotEmpty)
        .toList();
    final net = (cat['netTa'] as num?)?.toDouble() ?? 0;
    var inflow = (cat['inflow'] as num?)?.toDouble();
    var outflow = (cat['outflow'] as num?)?.toDouble();
    if (inflow == null || outflow == null) {
      var inf = 0.0;
      var out = 0.0;
      if (secondaries.isEmpty) {
        if (net > 0) {
          inf = net;
        } else if (net < 0) {
          out = net;
        }
      } else {
        for (final sub in secondaries) {
          final v = (sub['netTa'] as num?)?.toDouble() ?? 0;
          if (v > 0) inf += v;
          if (v < 0) out += v;
        }
      }
      inflow ??= inf;
      outflow ??= out;
    }
    parents.add({
      ...cat,
      'group': cat['group'] ?? name,
      'netTa': net,
      'inflow': inflow,
      'outflow': outflow,
      'secondaries': secondaries,
    });
  }
  var pos = 0.0;
  var negAbs = 0.0;
  for (final row in parents) {
    final n = (row['netTa'] as num?)?.toDouble() ?? 0;
    if (n > 0) pos += n;
    if (n < 0) negAbs += n.abs();
  }
  for (final row in parents) {
    final n = (row['netTa'] as num?)?.toDouble() ?? 0;
    final share = n >= 0
        ? (pos == 0 ? 0.0 : n / pos * 100)
        : (negAbs == 0 ? 0.0 : n.abs() / negAbs * 100);
    row['sharePct'] = share;
    row['flow'] = n >= 0 ? 'in' : 'out';
  }
  return parents;
}


const lighthouseNetTASecondariesByMapped = <String, List<String>>{
  '经营活动': ['和包出行回款', '项目付款', '项目回款', '应收保证金', '分润', '预收保证金'],
  '筹资活动': ['往来款', '亚洲保理', '应付贷款', '应收往来款'],
  '经营成本': [
    '财务费用',
    '车辆使用费',
    '费用报销',
    '利息收入',
    '其他收入',
    '人员费用',
    '税费缴纳',
    '退税',
    '行政支出',
    '研发成本',
    '政府补贴',
  ],
  '项目成本': <String>[],
  '业务成本': ['营销费用'],
};

List<Map<String, dynamic>> lighthouseNetTASecondariesOrSeed(
  String mappedName,
  List<Map<String, dynamic>> secondaries,
) {
  if (secondaries.isNotEmpty) return secondaries;
  return [
    for (final name in lighthouseNetTASecondariesByMapped[mappedName] ?? const <String>[])
      {'name': name, 'netTa': 0.0},
  ];
}

/// 分组卡格子：超过 [maxCells] 时收成「其余 N 项」。
List<Map<String, dynamic>> lighthouseNetTACardMetrics(
  List<Map<String, dynamic>> secondaries, {
  int maxCells = 6,
}) {
  final items = [
    for (final raw in secondaries)
      if ((raw['name']?.toString() ?? '').isNotEmpty) Map<String, dynamic>.from(raw),
  ];
  if (items.length <= maxCells) return items;
  final ranked = [...items]..sort((a, b) {
    final aa = ((a['netTa'] as num?)?.toDouble() ?? 0).abs();
    final bb = ((b['netTa'] as num?)?.toDouble() ?? 0).abs();
    return bb.compareTo(aa);
  });
  final head = ranked.take(maxCells - 1).toList();
  final rest = ranked.skip(maxCells - 1).toList();
  var restSum = 0.0;
  for (final row in rest) {
    restSum += (row['netTa'] as num?)?.toDouble() ?? 0;
  }
  return [
    ...head,
    {'name': '其余 ${rest.length} 项', 'netTa': restSum},
  ];
}

String lighthouseNetTAFlowLabel(num? netTa) =>
    (netTa ?? 0) >= 0 ? '净流入' : '净流出';

String lighthouseNetTAShareLabel(num? netTa) =>
    (netTa ?? 0) >= 0 ? '占净流入' : '占净流出';

/// 净TA 主 Hero 总览图六槽：净TA / 经营活动 / 筹资活动 / 经营成本 / 项目成本 / 业务成本。
/// 项目成本、业务成本与其余指标叠在同一张图，各自一条线。
const lighthouseNetTAHeroOverlaySlots = <String, String>{
  'netTa': 'scale',
  'netTaOperating': 'revenue',
  'netTaFinancing': 'scaleAlt',
  'netTaOpCost': 'cost',
  'netTaProjectCost': 'profit',
  'netTaBizCost': 'costAlt',
};

/// 净TA 主 Hero 指标栏。三列与产品 / 供给方 / 渠道的
/// 规模 → 成本 → 利润 一一对应：进了多少 → 出了多少 → 净了多少。
/// flex 沿用 lighthouseHeroScaleColumnFlex / Cost / Result（10 : 14 : 15），不另开一套。
const lighthouseNetTAHeroSections = <LighthouseHeroVerticalSection>[
  LighthouseHeroVerticalSection('scale', '资金流入', [
    'netTaInflow',
    'netTaOperatingInflow',
    'netTaOtherInflow',
  ]),
  LighthouseHeroVerticalSection('cost', '资金流出', [
    'netTaOutflow',
    'netTaOperatingOutflow',
    'netTaFinancingOutflow',
    'netTaCostOutflow',
  ]),
  // 净TA 总额是 hero 大数，不进指标栏；未映射走列表顶部提示条，不占一张卡。
  LighthouseHeroVerticalSection('profit', '五类净额', [
    'netTaOperating',
    'netTaFinancing',
    'netTaOpCost',
    'netTaProjectCost',
    'netTaBizCost',
  ]),
];

const lighthouseNetTAHeroColumnSectionKeys = <List<String>>[
  ['scale'],
  ['cost'],
  ['profit'],
];

/// Hero 指标栏用到的全部键，_loadTab 按它把后端 `hero` 摊进 metrics。
List<String> lighthouseNetTAHeroMetricKeys() => [
  for (final section in lighthouseNetTAHeroSections) ...section.metricKeys,
];

String? lighthouseNetTAHeroOverlaySlot(String? metricKey) {
  if (metricKey == null || metricKey.isEmpty) return null;
  return lighthouseNetTAHeroOverlaySlots[metricKey];
}

String? lighthouseNetTAHeroMetricFromSlot(String? slot) {
  switch (slot) {
    case 'scale':
      return 'netTa';
    case 'revenue':
      return 'netTaOperating';
    case 'scaleAlt':
      return 'netTaFinancing';
    case 'cost':
      return 'netTaOpCost';
    case 'profit':
      return 'netTaProjectCost';
    case 'costAlt':
      return 'netTaBizCost';
    default:
      return null;
  }
}

class LighthouseNetTAHeroTrend {
  const LighthouseNetTAHeroTrend({
    required this.labels,
    required this.title,
    required this.rangeLabel,
    required this.netTa,
    required this.operating,
    required this.financing,
    required this.operatingCost,
    required this.projectCost,
    required this.businessCost,
    required this.projectAndBusiness,
  });

  final List<String> labels;
  final String title;
  final String rangeLabel;
  final List<double> netTa;
  final List<double> operating;
  final List<double> financing;
  final List<double> operatingCost;
  final List<double> projectCost;
  final List<double> businessCost;
  final List<double> projectAndBusiness;
}

List<double> lighthouseReadNumberSeries(dynamic raw) {
  if (raw is! List || raw.isEmpty) return const <double>[];
  return [
    for (final e in raw) (e is num) ? e.toDouble() : 0.0,
  ];
}

List<double> _lighthouseSumSeries(List<double> a, List<double> b) {
  if (a.isEmpty && b.isEmpty) return const <double>[];
  final n = a.length > b.length ? a.length : b.length;
  return [
    for (var i = 0; i < n; i++)
      (i < a.length ? a[i] : 0.0) + (i < b.length ? b[i] : 0.0),
  ];
}

double lighthouseNetTANamedAmount(
  List<Map<String, dynamic>> categories,
  String name,
) {
  for (final row in categories) {
    if (row['name']?.toString() == name) {
      return (row['netTa'] as num?)?.toDouble() ?? 0;
    }
  }
  return 0;
}

LighthouseNetTAHeroTrend lighthouseNetTAHeroTrendFromPayload(
  Map<String, dynamic> payload,
) {
  const labels = ['上期', '本期'];
  const title = '走势';
  const range = '上期 — 本期';
  final series = payload['series'];
  if (series is Map) {
    final m = Map<String, dynamic>.from(series);
    final parsedLabels = (m['labels'] is List && (m['labels'] as List).isNotEmpty)
        ? [
            for (final e in m['labels'] as List)
              if (e.toString().trim().isNotEmpty) e.toString().trim(),
          ]
        : labels;
    final projectCost = lighthouseReadNumberSeries(m['projectCost']);
    final businessCost = lighthouseReadNumberSeries(m['businessCost']);
    var projectAndBusiness = lighthouseReadNumberSeries(m['projectAndBusiness']);
    if (projectAndBusiness.isEmpty &&
        (projectCost.isNotEmpty || businessCost.isNotEmpty)) {
      projectAndBusiness = _lighthouseSumSeries(projectCost, businessCost);
    }
    return LighthouseNetTAHeroTrend(
      labels: parsedLabels,
      title: (m['title']?.toString().trim().isNotEmpty ?? false)
          ? m['title'].toString().trim()
          : title,
      rangeLabel: (m['rangeLabel']?.toString().trim().isNotEmpty ?? false)
          ? m['rangeLabel'].toString().trim()
          : range,
      netTa: lighthouseReadNumberSeries(m['netTa']),
      operating: lighthouseReadNumberSeries(m['operating']),
      financing: lighthouseReadNumberSeries(m['financing']),
      operatingCost: lighthouseReadNumberSeries(m['operatingCost']),
      projectCost: projectCost,
      businessCost: businessCost,
      projectAndBusiness: projectAndBusiness,
    );
  }
  final cats = (payload['categories'] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  final total = (payload['total'] as num?)?.toDouble() ?? 0;
  final projectCost = lighthouseNetTANamedAmount(cats, '项目成本');
  final businessCost = lighthouseNetTANamedAmount(cats, '业务成本');
  return LighthouseNetTAHeroTrend(
    labels: labels,
    title: title,
    rangeLabel: range,
    netTa: [0, total],
    operating: [0, lighthouseNetTANamedAmount(cats, '经营活动')],
    financing: [0, lighthouseNetTANamedAmount(cats, '筹资活动')],
    operatingCost: [0, lighthouseNetTANamedAmount(cats, '经营成本')],
    projectCost: [0, projectCost],
    businessCost: [0, businessCost],
    projectAndBusiness: [0, projectCost + businessCost],
  );
}

/// 主 Hero 折线最少两点才画得出来。
bool lighthouseNetTAHeroSeriesReady(Map<String, dynamic>? metrics) {
  final raw = metrics?['netTaSeries'];
  return raw is List && raw.length >= 2;
}

/// 产品 summary / 「全部」Hero 快照会整表替换 metrics，把净TA 走势冲掉。
/// 切回净TA 时若仍走「已加载」短路，主图就会空着。把 `netTa*` 键补回去。
void lighthouseCarryNetTAMetrics(
  Map<String, dynamic> from,
  Map<String, dynamic> into,
) {
  from.forEach((key, value) {
    if (!key.startsWith('netTa')) return;
    final existing = into[key];
    if (existing == null) {
      into[key] = value;
      return;
    }
    if (existing is List &&
        existing.isEmpty &&
        value is List &&
        value.isNotEmpty) {
      into[key] = value;
    }
  });
}

void lighthouseMergeNetTAHeroTrend(
  Map<String, dynamic> metrics,
  LighthouseNetTAHeroTrend trend,
) {
  double last(List<double> s) => s.isEmpty ? 0 : s.last;
  metrics['netTaSeries'] = trend.netTa;
  metrics['netTaOperatingSeries'] = trend.operating;
  metrics['netTaFinancingSeries'] = trend.financing;
  metrics['netTaOpCostSeries'] = trend.operatingCost;
  metrics['netTaProjectCostSeries'] = trend.projectCost;
  metrics['netTaBizCostSeries'] = trend.businessCost;
  metrics['netTaProjectBizSeries'] = trend.projectAndBusiness;
  metrics['netTaSeriesLabels'] = trend.labels;
  metrics['netTaSeriesTitle'] = trend.title;
  metrics['netTaSeriesRangeLabel'] = trend.rangeLabel;
  metrics['netTaOperating'] = last(trend.operating);
  metrics['netTaFinancing'] = last(trend.financing);
  metrics['netTaOpCost'] = last(trend.operatingCost);
  metrics['netTaProjectBiz'] = last(trend.projectAndBusiness);
}

double? lighthouseSeriesSignedDeltaPct(List<double> series) {
  if (series.length < 2) return null;
  final prev = series[series.length - 2];
  final cur = series.last;
  if (prev.abs() < 1e-9) return null;
  return (cur - prev) / prev.abs() * 100;
}

int lighthouseNetTASecondaryCount(Map<String, dynamic> row) {
  final secondaries = (row['secondaries'] as List? ?? const [])
      .whereType<Map>()
      .where((e) => (e['name']?.toString() ?? '').isNotEmpty)
      .length;
  return secondaries == 0 ? 1 : secondaries;
}

const lighthouseLedgerSummaryMetricKeys = <String>[
  'sales',
  'verifiedSales',
  'prepaid',
  'profit',
  'costTotal',
  'netTa',
];

/// 产品 / 供给 / 渠道统一四核心：左列规模，右列经营结果。
const lighthouseLedgerSummaryMetricRows = <List<String>>[
  ['sales', 'prepaid'],
  ['verifiedSales', 'profit'],
];

/// 账本摘要格可点开单条走势的四个指标。
const lighthouseLedgerSoloTrendKeys = <String>{
  'sales',
  'verifiedSales',
  'prepaid',
  'profit',
};

bool lighthouseLedgerMetricOpensSoloTrend(String key) =>
    lighthouseLedgerSoloTrendKeys.contains(key);

/// 点同一格收起；点另一格切换到那一条。
String? lighthouseLedgerSoloTrendAfterTap(String? current, String tapped) {
  if (!lighthouseLedgerMetricOpensSoloTrend(tapped)) return current;
  return current == tapped ? null : tapped;
}

/// 保留产品专用名称供既有调用使用，三维实际共用同一布局。
const lighthouseProductLedgerSummaryMetricRows =
    lighthouseLedgerSummaryMetricRows;

/// 供给卡片追加资金池预览；产品 / 渠道维度不展示。
/// 收起行：总资产金额 | 票税（资管标签二应开/实开/原件）。展开明细仍按日清/月结决定是否含发票块。
bool lighthouseLedgerShowsFundPoolPreview(String tab) => tab.trim() == 'supply';

/// 标签二的一行省份资金数据。金额单位沿用接口的「元」，税率为百分数。
class LighthouseFundPoolAmounts {
  const LighthouseFundPoolAmounts({
    this.endingPrepaymentBalance,
    this.endingReceivableRebate,
    this.fundPoolBalance,
    this.inventoryVoucherBalance,
    this.contractVoucherBalance,
    this.systemDifference,
    this.inTransitFunds,
    this.regulatoryAccountBalance,
    this.totalAssets,
    this.invoiceToIssue,
    this.invoiceIssued,
    this.invoiceTaxRate,
    this.invoiceOriginals = const [],
    this.advanceVoucherBalance,
  });

  final double? endingPrepaymentBalance;
  final double? endingReceivableRebate;
  final double? fundPoolBalance;
  final double? inventoryVoucherBalance;
  final double? contractVoucherBalance;
  final double? systemDifference;
  final double? inTransitFunds;
  final double? regulatoryAccountBalance;
  final double? totalAssets;
  final double? invoiceToIssue;
  final double? invoiceIssued;
  final double? invoiceTaxRate;
  final List<String> invoiceOriginals;
  final double? advanceVoucherBalance;

  static LighthouseFundPoolAmounts? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    return LighthouseFundPoolAmounts(
      endingPrepaymentBalance: _asOptionalDouble(
        raw['endingPrepaymentBalance'],
      ),
      endingReceivableRebate: _asOptionalDouble(raw['endingReceivableRebate']),
      fundPoolBalance: _asOptionalDouble(raw['fundPoolBalance']),
      inventoryVoucherBalance: _asOptionalDouble(
        raw['inventoryVoucherBalance'],
      ),
      contractVoucherBalance: _asOptionalDouble(raw['contractVoucherBalance']),
      systemDifference: _asOptionalDouble(raw['systemDifference']),
      inTransitFunds: _asOptionalDouble(raw['inTransitFunds']),
      regulatoryAccountBalance: _asOptionalDouble(
        raw['regulatoryAccountBalance'],
      ),
      totalAssets: _asOptionalDouble(raw['totalAssets']),
      invoiceToIssue: _asOptionalDouble(raw['invoiceToIssue']),
      invoiceIssued: _asOptionalDouble(raw['invoiceIssued']),
      invoiceTaxRate: _asOptionalDouble(raw['invoiceTaxRate']),
      invoiceOriginals: _asStringList(raw['invoiceOriginals']),
      advanceVoucherBalance: _asOptionalDouble(raw['advanceVoucherBalance']),
    );
  }
}

double? _asOptionalDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

List<String> _asStringList(dynamic v) {
  if (v == null) return const [];
  if (v is String) return _splitUrlText(v);
  if (v is Map) {
    final one = _urlFromMap(v);
    return one == null ? const [] : [one];
  }
  if (v is! List) return const [];
  return [
    for (final item in v)
      ..._asStringList(item),
  ];
}

List<String> _splitUrlText(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];
  if (!text.contains(',')) return [text];
  return [
    for (final part in text.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

String? _urlFromMap(Map raw) {
  for (final key in const [
    'url',
    'fileUrl',
    'file_url',
    'originalUrl',
    'photoUrl',
    'src',
    'path',
  ]) {
    final value = raw[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  for (final nested in const ['file', 'image', 'photo', 'original']) {
    final value = raw[nested];
    if (value is Map) {
      final inner = _urlFromMap(value);
      if (inner != null) return inner;
    }
  }
  return null;
}

/// 将 `/fund-pool` 的 `byProvince` 解析为可匹配 map。
Map<String, LighthouseFundPoolAmounts> lighthouseParseFundPoolByProvince(
  dynamic raw,
) {
  if (raw is! Map) return const {};
  final out = <String, LighthouseFundPoolAmounts>{};
  raw.forEach((key, value) {
    final name = key?.toString().trim() ?? '';
    if (name.isEmpty) return;
    final amounts = LighthouseFundPoolAmounts.fromJson(value);
    if (amounts != null) out[name] = amounts;
  });
  return out;
}

/// 供给行名 → 标签二省份：精确匹配，再双向包含模糊匹配；合计行不参与模糊。
LighthouseFundPoolAmounts? lighthouseLookupFundPool(
  Map<String, LighthouseFundPoolAmounts> byProvince,
  String rowName,
) {
  final name = rowName.trim();
  if (name.isEmpty || byProvince.isEmpty) return null;
  final exact = byProvince[name];
  if (exact != null) return exact;
  for (final entry in byProvince.entries) {
    if (entry.key == '__TOTAL__') continue;
    final key = entry.key.trim();
    if (key.isEmpty) continue;
    if (key.contains(name) || name.contains(key)) return entry.value;
  }
  return null;
}

/// 标签二返回元；灯塔统一展示为 `12.3万` / `1.20亿`。
String lighthouseFormatFundPoolWan(double? amount) {
  final parts = lighthouseFormatFundPoolWanParts(amount);
  return '${parts.number}${parts.unit}';
}

/// 拆成数字 / 单位，便于与上方指标格一样：数字加粗、单位常规字重。
({String number, String unit}) lighthouseFormatFundPoolWanParts(double? amount) {
  if (amount == null) return (number: '—', unit: '');
  final sign = amount < 0 ? '-' : '';
  final wan = amount.abs() / 10000;
  if (wan >= 10000) {
    return (number: '$sign${(wan / 10000).toStringAsFixed(2)}', unit: '亿');
  }
  if (wan >= 1000) {
    return (number: '$sign${wan.toStringAsFixed(0)}', unit: '万');
  }
  if (wan >= 1) {
    return (number: '$sign${wan.toStringAsFixed(1)}', unit: '万');
  }
  return (number: '$sign${wan.toStringAsFixed(2)}', unit: '万');
}

String lighthouseFormatFundPoolRate(double? rate) {
  if (rate == null) return '—';
  return '${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 2)}%';
}

/// 日清表不含票税；月结 / 季 / 年才把发票块放在资产上方。
bool lighthouseFundPoolShowsInvoice(String period) {
  switch (period.trim()) {
    case 'month':
    case 'quarter':
    case 'year':
      return true;
    default:
      return false;
  }
}

enum LighthouseFundPoolSectionKind { invoice, assets, funds, vouchers, recon }

class LighthouseFundPoolMetricSpec {
  const LighthouseFundPoolMetricSpec(this.key, this.label);
  final String key;
  final String label;
}

class LighthouseFundPoolSectionSpec {
  const LighthouseFundPoolSectionSpec({
    required this.kind,
    required this.title,
    required this.metrics,
  });
  final LighthouseFundPoolSectionKind kind;
  final String title;
  final List<LighthouseFundPoolMetricSpec> metrics;
}

class LighthouseFundPoolRowSpec {
  const LighthouseFundPoolRowSpec(this.left, [this.right]);
  final LighthouseFundPoolSectionSpec left;
  final LighthouseFundPoolSectionSpec? right;
}

class LighthouseFundPoolPreviewMetric {
  const LighthouseFundPoolPreviewMetric(this.key, this.label);
  final String key;
  final String label;
}

/// 收起行两块并列：左总资产、右票税（不进资产等式；数据来自资管标签二）。
List<LighthouseFundPoolPreviewMetric> lighthouseFundPoolPreviewMetrics() {
  return const [
    LighthouseFundPoolPreviewMetric('totalAssets', '总资产金额'),
    // 票税收成单值格：预览行里只放应开发票金额，和左边总资产同一个形状。
    // 实开 / 发票原件在展开的「发票」分区里有，预览行不必挤三行。
    LighthouseFundPoolPreviewMetric('invoiceToIssue', '票税 · 应开'),
  ];
}

const lighthouseFundPoolInvoiceSection = LighthouseFundPoolSectionSpec(
  kind: LighthouseFundPoolSectionKind.invoice,
  title: '发票',
  metrics: [
    LighthouseFundPoolMetricSpec('invoiceOriginals', '发票原件'),
    LighthouseFundPoolMetricSpec('invoiceToIssue', '应开发票金额'),
    LighthouseFundPoolMetricSpec('invoiceIssued', '实开金额'),
  ],
);

const lighthouseFundPoolAssetsSection = LighthouseFundPoolSectionSpec(
  kind: LighthouseFundPoolSectionKind.assets,
  title: '资产',
  metrics: [
    LighthouseFundPoolMetricSpec('totalAssets', '资产合计'),
  ],
);

const lighthouseFundPoolFundsSection = LighthouseFundPoolSectionSpec(
  kind: LighthouseFundPoolSectionKind.funds,
  title: '资金',
  metrics: [
    LighthouseFundPoolMetricSpec('regulatoryAccountBalance', '现金 · 监管户'),
    LighthouseFundPoolMetricSpec('inTransitFunds', '现金 · 在途'),
    LighthouseFundPoolMetricSpec('endingReceivableRebate', '应收资金'),
    // 占位：口径和数据源都还没定，先把格子留出来，取不到值显示「—」。
    LighthouseFundPoolMetricSpec('turnoverDays', '周转周期'),
  ],
);

const lighthouseFundPoolVouchersSection = LighthouseFundPoolSectionSpec(
  kind: LighthouseFundPoolSectionKind.vouchers,
  title: '券',
  metrics: [
    LighthouseFundPoolMetricSpec('inventoryVoucherBalance', '库存券'),
    LighthouseFundPoolMetricSpec('contractVoucherBalance', '同步券'),
    LighthouseFundPoolMetricSpec('advanceVoucherBalance', '预支券'),
  ],
);

const lighthouseFundPoolReconSection = LighthouseFundPoolSectionSpec(
  kind: LighthouseFundPoolSectionKind.recon,
  title: '期末预付款对账',
  metrics: [
    LighthouseFundPoolMetricSpec('fundPoolBalance', '资金池可用'),
    LighthouseFundPoolMetricSpec('stockAndSyncVouchers', '库存/同步券'),
    LighthouseFundPoolMetricSpec('systemDifference', '系统差异'),
    LighthouseFundPoolMetricSpec('endingPrepaymentBalance', '期末预付款余额'),
  ],
);

/// 月结：发票与资产并列且发票在上；下面资金 → 券 → 对账。
/// 日清：不含发票，资金 → 券 → 对账，资产放等式最后。
List<LighthouseFundPoolRowSpec> lighthouseFundPoolDetailRows({
  required bool showInvoice,
}) {
  if (showInvoice) {
    return const [
      LighthouseFundPoolRowSpec(
        lighthouseFundPoolInvoiceSection,
        lighthouseFundPoolAssetsSection,
      ),
      LighthouseFundPoolRowSpec(
        lighthouseFundPoolFundsSection,
        lighthouseFundPoolVouchersSection,
      ),
      LighthouseFundPoolRowSpec(lighthouseFundPoolReconSection),
    ];
  }
  return const [
    LighthouseFundPoolRowSpec(
      lighthouseFundPoolFundsSection,
      lighthouseFundPoolVouchersSection,
    ),
    LighthouseFundPoolRowSpec(
      lighthouseFundPoolReconSection,
      lighthouseFundPoolAssetsSection,
    ),
  ];
}

double? lighthouseFundPoolStockAndSyncVouchers(
  LighthouseFundPoolAmounts? amounts,
) {
  if (amounts == null) return null;
  final inventory = amounts.inventoryVoucherBalance;
  final sync = amounts.contractVoucherBalance;
  if (inventory == null && sync == null) return null;
  return (inventory ?? 0) + (sync ?? 0);
}

double? lighthouseFundPoolAmountByKey(
  LighthouseFundPoolAmounts? amounts,
  String key,
) {
  if (amounts == null) return null;
  return switch (key) {
    'endingPrepaymentBalance' => amounts.endingPrepaymentBalance,
    'endingReceivableRebate' => amounts.endingReceivableRebate,
    'fundPoolBalance' => amounts.fundPoolBalance,
    'inventoryVoucherBalance' => amounts.inventoryVoucherBalance,
    'contractVoucherBalance' => amounts.contractVoucherBalance,
    'advanceVoucherBalance' => amounts.advanceVoucherBalance,
    'systemDifference' => amounts.systemDifference,
    'inTransitFunds' => amounts.inTransitFunds,
    'regulatoryAccountBalance' => amounts.regulatoryAccountBalance,
    'totalAssets' => amounts.totalAssets,
    'invoiceToIssue' => amounts.invoiceToIssue,
    'invoiceIssued' => amounts.invoiceIssued,
    'stockAndSyncVouchers' => lighthouseFundPoolStockAndSyncVouchers(amounts),
    _ => null,
  };
}

String lighthouseLedgerSummaryMetricTone(String key) => switch (key) {
  'prepaid' || 'netTa' || 'sharePct' => 'cash',
  'profit' => 'profit',
  _ => 'neutral',
};

/// 「结果」指标 —— 经营性净现金流 / 净TA / 毛利润。
bool lighthouseLedgerIsResultMetric(String key) =>
    lighthouseLedgerSummaryMetricTone(key) != 'neutral';

/// v19 · 结果区分块。
///
/// 旧版靠给单个数字换色相来强调（现金流紫 / 毛利润蓝），但这两个色比左边
/// 规模数字用的近黑更浅、对比度更低 —— 想突出的反而更轻，层级是反的。
/// 而且 11.5px 下色相只表达「另一类」，不表达「更重要」。
///
/// 改成分区：右半列整体铺一层极淡底 + 左缘一条竖轨，把「结果」从「规模」里
/// 切出来。强调由区块承担，字号一律不动。
const bool lighthouseLedgerUsesResultBlock = true;

/// 竖轨与底色同一支蓝。原来的 0xFF5C6FB5 偏灰靛，铺淡了只剩一层脏灰；
/// 这支蓝饱和度够，12% 就能读出「淡蓝」而不是「白里带脏」。
const int lighthouseLedgerResultBlockAccentValue = 0xFF4A83C4;

/// 底色不透明度（0–255）。38 ≈ 15%，压在白底上约 #E4EDF6。
/// 往下 30 ≈ #EAF0F8（偏淡），往上 46 ≈ #DEE9F4 就开始跟数字抢注意力了。
const int lighthouseLedgerResultBlockTintAlpha = 38;
const double lighthouseLedgerResultBlockRailWidth = 2;

/// 区块已经在分区了，数字再上色就是重复编码 —— 关掉，数值回到中性墨色。
/// 想恢复紫/蓝两色数字，把这个改回 true 即可。
const bool lighthouseLedgerResultBlockKeepsMetricTint = false;

List<List<String>> lighthouseLedgerSummaryMetricRowsForTab(String tab) {
  if (tab.trim() == 'netTa') {
    return const [
      ['inflow', 'netTa'],
      ['outflow', 'sharePct'],
    ];
  }
  return lighthouseLedgerSummaryMetricRows;
}

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
    'grossMargin': '毛利率',
    'rate': 'ROI',
    'spreadRate': '利差率',
    'gmv': 'GMV',
    'prepaid': '预收净增',
    'netTa': '净TA',
    'inflow': '流入',
    'outflow': '流出',
    'sharePct': '占比',
    'netTaInflow': '流入合计',
    'netTaOperatingInflow': '经营活动流入',
    'netTaOtherInflow': '其他流入',
    'netTaOutflow': '流出合计',
    'netTaOperatingOutflow': '经营性流出',
    'netTaFinancingOutflow': '筹资流出',
    'netTaCostOutflow': '项目+业务成本',
    'netTaOperating': '经营活动',
    'netTaFinancing': '筹资活动',
    'netTaOpCost': '经营成本',
    'netTaProjectCost': '项目成本',
    'netTaBizCost': '业务成本',
    'netTaProjectBiz': '项目+业务成本',
    'netTaUnmapped': '未映射金额',
  };
  return labels[key] ?? key;
}

/// 净TA 流出 / 成本 / 筹资活动：栏目已标明方向，数字只报规模，不带负号。
/// 净TA、经营活动仍保留正负（可进可出）。
const lighthouseNetTAMagnitudeMetricKeys = <String>{
  'outflow',
  'netTaOutflow',
  'netTaOperatingOutflow',
  'netTaFinancingOutflow',
  'netTaCostOutflow',
  'netTaOpCost',
  'netTaProjectCost',
  'netTaBizCost',
  'netTaProjectBiz',
  'netTaFinancing',
};

bool lighthouseHeroMetricDisplaysMagnitude(String key) =>
    lighthouseNetTAMagnitudeMetricKeys.contains(key);

double lighthouseHeroMetricDisplayAmount(String key, double value) =>
    lighthouseHeroMetricDisplaysMagnitude(key) ? value.abs() : value;

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

/// 比率展示上限：只用于拦住「核销极小 → 毛利率爆炸」的脏数。
/// 正常经营毛利率（哪怕到一两百 %）不应被挡掉。
const double lighthouseMaxDisplayRatePct = 1000;

/// 过滤 NaN / Infinity / 异常放大的比率；不合格返回 null。
double? lighthouseDisplayRatePct(
  double? pct, {
  double maxAbs = lighthouseMaxDisplayRatePct,
}) {
  if (pct == null) return null;
  if (pct.isNaN || pct.isInfinite) return null;
  if (pct.abs() > maxAbs) return null;
  return pct;
}

/// 列表/Hero 共用的毛利率展示值：毛利润 ÷ 核销额 × 100%。
/// 核销过小或结果爆炸时返回 null（UI 显示 —）。
double? lighthouseGrossMarginDisplayPct({
  required double profit,
  required double verifiedSales,
  double minimumVerified = 50,
  double maxAbsPct = lighthouseMaxDisplayRatePct,
}) {
  final base = lighthouseValidRateBase(
    verifiedSales,
    minimumBase: minimumVerified,
  );
  if (base <= 0) return null;
  return lighthouseDisplayRatePct(profit / base * 100, maxAbs: maxAbsPct);
}

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
    if (validBase <= 0) return 0;
    final pct = profit[index] / validBase * 100;
    return lighthouseDisplayRatePct(pct) ?? 0;
  }, growable: false);
}

bool lighthouseCanFallbackToRootTrend({required bool isDrill}) => !isDrill;

/// L3 可以用「本实体在交叉维上的走势」，不能用 L2 父级走势冒充。
bool lighthouseCanFallbackToChildTrend({required bool isDrill}) => isDrill;

/// 子维对应哪张走势缓存。没有一级 tab 的维（SKU）返回 null，只吃详情 payload。
String? lighthouseTrendTabForSubDim(String dim) {
  switch (dim) {
    case 'product':
    case 'supply':
    case 'channel':
    case 'province':
    case 'project':
      return dim;
    default:
      return null;
  }
}

bool lighthouseTrendMapUsable(Map<String, dynamic> t) {
  bool longEnough(Object? raw) {
    if (raw is! List) return false;
    var n = 0;
    for (final item in raw) {
      if (item is num) n++;
    }
    return n >= 2;
  }

  return longEnough(t['profit']) ||
      longEnough(t['points']) ||
      longEnough(t['revenue']) ||
      longEnough(t['sales']) ||
      longEnough(t['verifiedSales']) ||
      longEnough(t['prepaid']) ||
      longEnough(t['totalCost']) ||
      longEnough(t['cost']);
}

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

/// L1 Hero：无分类 / HUN / 异常时走后端共享 summary；有本地筛再按列表行加总。
///
/// 产品 / 供给 / 渠道在「全部」下应对齐同一套全量汇总，不能各自加维内列表。
bool lighthouseHeroUseRowAmounts({
  required bool filterActive,
  required bool hasRows,
}) => filterActive && hasRows;

/// summary 是否对应当前 Tab + 分类。切维后上一档的 filterGroup 不能再喂给「本日毛利润」。
bool lighthouseHeroSummaryAppliesTo({
  required String tab,
  required String group,
  String? filterTab,
  String? filterGroup,
}) {
  final g = group.trim().isEmpty ? '全部' : group.trim();
  final fg = (filterGroup ?? '').trim();
  if (g == '全部') return fg.isEmpty;
  if (fg != g) return false;
  final ft = (filterTab ?? '').trim();
  return ft.isEmpty || ft == tab;
}

/// 切回「全部」时剥掉分类标记，才能立刻用上一份全量 Hero，不必等接口。
Map<String, dynamic> lighthouseSharedHeroMetricsSnapshot(
  Map<String, dynamic> metrics,
) {
  final next = Map<String, dynamic>.from(metrics);
  next.remove('filterGroup');
  next.remove('filterTab');
  return next;
}

/// Hero 金额：分类筛用列表加总；匹配的 summary 优先；切维串档则回退全量快照。
/// 串档时禁止再用上一维的 metricsValue 冒充「本日毛利润」。
double lighthouseHeroMetricAmount({
  required bool useRowAmounts,
  required bool metricsMatch,
  double? metricsValue,
  double? sharedValue,
  required double rowSum,
}) {
  if (useRowAmounts) return rowSum;
  if (metricsMatch && metricsValue != null) return metricsValue;
  if (!metricsMatch) return sharedValue ?? rowSum;
  return metricsValue ?? sharedValue ?? rowSum;
}

/// 切产品 / 供给 / 渠道时带着当前分类走；新维没有该项才回「全部」。
String lighthouseGroupAfterTabSwitch({
  required String currentGroup,
  required List<String> nextTabOptions,
}) => lighthouseNormalizeGroupFilter(
  current: currentGroup,
  options: nextTabOptions,
);

/// L1 切维默认分类：三维一律「全部」（中石油 / 平安仅置顶，不默认选中）。
String lighthouseDefaultGroupFilter(String tab) {
  switch (tab) {
    case 'product':
    case 'supply':
    case 'channel':
      return '全部';
    default:
      return '全部';
  }
}

/// 校正当前 L1 分类：用户选的「全部」必须保留；仅选项失效时回退。
/// 切维 / 展开分类条时用，禁止再把「全部」偷偷改成中石油、平安。
String lighthouseNormalizeGroupFilter({
  required String current,
  required List<String> options,
  String fallback = '全部',
}) {
  final cur = current.trim().isEmpty ? '全部' : current.trim();
  if (cur == '全部') return '全部';
  if (options.contains(cur)) return cur;
  return fallback;
}

/// L2 行 → drill map 主键（有 group 时为 `name::group`）。
String lighthouseDetailRowDrillKey({required String name, String group = ''}) {
  final g = group.trim();
  if (g.isEmpty) return name;
  return '$name::$g';
}

/// 按 name 合并子行时保留 group；同名多 group 则清空，避免误挂分类。
String lighthouseMergedSubRowGroup(String? existing, String? incoming) {
  final e = (existing ?? '').trim();
  final i = (incoming ?? '').trim();
  if (e.isEmpty) return i;
  if (i.isEmpty) return e;
  if (e == i) return e;
  return '';
}

/// 解析 L2→L3 drill 键。
///
/// 供给/渠道二级默认子 Tab 是「产品」，后端 `product_drill` / `sku_drill`
/// 键多为 `name::group`；v12 列表按 name 合并后 group 常被清空，需在
/// drill map 中唯一命中 `name` 或 `name::*` 时回退，才能进三级页。
String? lighthouseResolveDrillKey({
  required Iterable<String> drillKeys,
  required String name,
  String group = '',
}) {
  final keys = drillKeys is Set<String> ? drillKeys : drillKeys.toSet();
  if (keys.isEmpty || name.isEmpty) return null;

  final primary = lighthouseDetailRowDrillKey(name: name, group: group);
  if (keys.contains(primary)) return primary;
  if (keys.contains(name)) return name;

  final g = group.trim();
  if (g.isNotEmpty) {
    final alt = '$name::$g';
    if (keys.contains(alt)) return alt;
  }

  final prefix = '$name::';
  final matches = <String>[
    for (final k in keys)
      if (k == name || k.startsWith(prefix)) k,
  ];
  if (matches.length == 1) return matches.first;
  return null;
}
