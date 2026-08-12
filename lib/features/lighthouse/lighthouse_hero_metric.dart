/// Hero masthead metric resolution (shared by page + unit tests).
library;

/// Whether [key] should render as a percentage in the Hero masthead.
bool lighthouseHeroMetricIsRate(String key) =>
    key == 'rate' || key == 'grossMargin' || key == 'spreadRate';

/// Shared compact Hero geometry for L1/L2/L3.
const int lighthouseCompactHeroKpiFlex = 3;
const int lighthouseCompactHeroTrendFlex = 7;

/// 给左侧 KPI（标签 + 大数 +「↓xx% vs 昨日」）留足高度，避免环比被裁切。
const double lighthouseCompactHeroSparkHeight = 100;
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
const lighthouseHeroSectionAccentValues = <String, int>{
  'scale': 0xFF7565C7,
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

const int lighthouseLedgerSummaryColumns = 2;

/// 名称略大于右侧核心数字，数字不压过业务名称。
const double lighthouseLedgerNameFontSize = 12.5;

/// 产品等偏长名称：列表冻结列用更小字号，少截断。
const double lighthouseLedgerLongNameFontSize = 11.0;

/// 二级「项目」名称更长，再降一档。
const double lighthouseLedgerProjectNameFontSize = 10.0;
const double lighthouseLedgerValueFontSize = 11.5;
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

const lighthouseLedgerSummaryMetricKeys = <String>[
  'sales',
  'verifiedSales',
  'prepaid',
  'profit',
  'costTotal',
];

/// 产品 / 供给 / 渠道统一四核心：左列规模，右列经营结果。
const lighthouseLedgerSummaryMetricRows = <List<String>>[
  ['sales', 'prepaid'],
  ['verifiedSales', 'profit'],
];

/// 保留产品专用名称供既有调用使用，三维实际共用同一布局。
const lighthouseProductLedgerSummaryMetricRows =
    lighthouseLedgerSummaryMetricRows;

/// 供给卡片追加资金池预览；产品 / 渠道维度不展示。
/// 数值来自 `/lighthouse/fund-pool`（资管标签二：资产合计 / 资金池余额）。
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
    this.invoiceTaxRate,
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
  final double? invoiceTaxRate;

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
      invoiceTaxRate: _asOptionalDouble(raw['invoiceTaxRate']),
    );
  }
}

double? _asOptionalDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
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
  if (amount == null) return '—';
  final sign = amount < 0 ? '-' : '';
  final wan = amount.abs() / 10000;
  if (wan >= 10000) {
    return '$sign${(wan / 10000).toStringAsFixed(2)}亿';
  }
  if (wan >= 1000) return '$sign${wan.toStringAsFixed(0)}万';
  if (wan >= 1) return '$sign${wan.toStringAsFixed(1)}万';
  return '$sign${wan.toStringAsFixed(2)}万';
}

String lighthouseFormatFundPoolRate(double? rate) {
  if (rate == null) return '—';
  return '${rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 2)}%';
}

String lighthouseLedgerSummaryMetricTone(String key) => switch (key) {
  'prepaid' => 'cash',
  'profit' => 'profit',
  _ => 'neutral',
};

/// 「结果」指标 —— 经营性净现金流 + 毛利润。老板真正要盯的两个。
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

List<List<String>> lighthouseLedgerSummaryMetricRowsForTab(String tab) =>
    lighthouseLedgerSummaryMetricRows;

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
