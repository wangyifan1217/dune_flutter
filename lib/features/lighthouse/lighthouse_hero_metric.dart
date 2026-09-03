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
/// 左侧再叠银行余额存量块时加高一截。块里有迷你走势和「vs 上月末」时，
/// 24px 不够，「本月净TA」的环比行会 BOTTOM OVERFLOW ~13px。
const double lighthouseNetTABankBalanceExtraHeight = 40;

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
    lighthouseCompactHeroSparkHeightFor(width) +
    lighthouseHeroChartCardPadding * 2;

// 指标格自己带了 2 的上下内边距（追溯方框用），格间距相应从 6 收到 2，
// 视觉上的行距还是 6。
const double lighthouseCompactHeroMetricGap = 2;
const bool lighthouseHeroUsesCategoryTint = false;
const bool lighthouseHeroUsesAccentRail = false;
const bool lighthouseHeroShowsEnglishKicker = false;
const bool lighthouseHeroUsesCardShadow = false;
const bool lighthouseHeroMetricUsesSansLabel = true;
const double lighthouseHeroCardRadius = 12;
const double lighthouseHeroCardGap = 8;
// 指标格自己带了 4 的左内边距，卡片这边从 8 收到 5，文字左缩进仍是 9。
const double lighthouseHeroCardPadding = 5;
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
bool lighthouseHeroPaneSnapsToZero({required double min, required double max}) {
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
  bool hasStock = false,
}) {
  return [
    if (hasScale) 'scale',
    if (hasStock) 'stock',
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

/// 环比：未点选用后端本期值；点选某一期用该点对前一点（2月对1月）。
/// 点在未走完的最后一期时仍用后端同期值，避免 MTD 去对上期整期。
double? lighthouseTrendMomPct({
  required double? periodDeltaPct,
  required bool partialPeriod,
  required List<double> series,
  int? selectedIndex,
}) {
  if (selectedIndex != null) {
    if (partialPeriod && selectedIndex == series.length - 1) {
      return periodDeltaPct;
    }
    if (selectedIndex <= 0 || selectedIndex >= series.length) return null;
    final prev = series[selectedIndex - 1];
    if (prev.abs() <= 1e-6) return null;
    return (series[selectedIndex] - prev) / prev.abs() * 100;
  }
  if (periodDeltaPct != null) return periodDeltaPct;
  if (partialPeriod || series.length < 2) return null;
  final prev = series[series.length - 2];
  if (prev.abs() <= 1e-6) return null;
  return (series.last - prev) / prev.abs() * 100;
}

/// 图例环比文案：箭头表达方向，数字用绝对值，避免「↓ -12%」。
/// 固定 1 位小数，四项列宽才齐。
String lighthouseTrendMomLabel(double pct) {
  return '${pct >= 0 ? '↑' : '↓'} ${pct.abs().toStringAsFixed(1)}%';
}

/// `_TrendChart` 序列在 `available` 里的下标。
/// [revenue, cost, profit, scale, scaleAlt, costAlt, stock]
const lighthouseTrendSeriesKeys = <String>[
  'revenue',
  'cost',
  'profit',
  'scale',
  'scaleAlt',
  'costAlt',
  'stock',
];

/// 点图例：再点当前项（或点「全部」）恢复全显；点另一项只留该项。
String? lighthouseTrendSoloAfterTap(String? current, String tapped) {
  if (tapped.isEmpty) return null;
  return current == tapped ? null : tapped;
}

/// 应用 solo 后的可见性，长度恒为 6。solo 指向没有数据的项时保持原样。
/// v21 · 默认画全部五条线（产品要求恢复）。
///
/// 单线版关掉了 —— 把 [lighthouseTrendDrawsSingleLine] 改回 true 即可切换，
/// 其余代码不用动。
///
/// 五条各自归一化叠在一张图里，纵轴根本不是同一个：交叉点和相对高低都不表示
/// 任何事，更要命的是**波动被伪造** —— 每条都拉满整个图高，成本环比 +1.4%
/// 在图上和翻倍一样起伏剧烈。那不是「看不清」，是「看错」。
///
/// 100pt 高、300pt 宽的卡里也放不下五条可读的线。所以默认只画主线，其余四条
/// 退成图例里的数字，点图例换线 —— 「一条走势 + 四个数」的信息量比
/// 「五条不可比的线」高。
///
/// 唯一保留的双线例外是核销 + 销售：它们 [lighthouseTrendShareScaleRange]
/// 时共用同一根 Y，两线之间的面积就是未核销差额，是真实可读的量。
const bool lighthouseTrendDrawsSingleLine = false;

/// 「哪几条有数据」。图例的可点性看这个，不受单线规则影响 ——
/// 没画在图上不等于点不了，恰恰相反：点它就是为了把它换上去。
List<bool> lighthouseTrendBaseFlags({
  required bool hasRevenue,
  required bool hasCost,
  required bool hasProfit,
  required bool hasScale,
  required bool hasScaleAlt,
  bool hasCostAlt = false,
  bool hasStock = false,
}) => <bool>[
    hasRevenue,
    hasCost,
    hasProfit,
    hasScale,
    hasScaleAlt,
  hasCostAlt,
  hasStock,
];

List<bool> lighthouseTrendVisibleFlags({
  required bool hasRevenue,
  required bool hasCost,
  required bool hasProfit,
  required bool hasScale,
  required bool hasScaleAlt,
  bool hasCostAlt = false,
  bool hasStock = false,
  String? soloKey,
  bool pairScale = false,
}) {
  final base = lighthouseTrendBaseFlags(
    hasRevenue: hasRevenue,
    hasCost: hasCost,
    hasProfit: hasProfit,
    hasScale: hasScale,
    hasScaleAlt: hasScaleAlt,
    hasCostAlt: hasCostAlt,
    hasStock: hasStock,
  );
  final n = lighthouseTrendSeriesKeys.length;
  final i = soloKey == null || soloKey.isEmpty
      ? -1
      : lighthouseTrendSeriesKeys.indexOf(soloKey);
  final soloValid = i >= 0 && i < base.length && base[i];
  if (soloValid) {
    return <bool>[for (var k = 0; k < n; k++) k == i];
  }
  if (!lighthouseTrendDrawsSingleLine) return base;
  final hero = lighthouseTrendHeroIndex(base);
  // 核销 + 销售共用真轴，两条一起画才看得出未核销差额。
  final keepsPair = pairScale && (hero == 3 || hero == 4) && base[3] && base[4];
  return <bool>[
    for (var k = 0; k < n; k++) keepsPair ? (k == 3 || k == 4) : k == hero,
  ];
}

/// 粗线 / 填充 / MAX·MIN 跟哪条走：规模在场时归规模，否则第一条可见的
/// 规模副线 / 毛利 / 收入 / 成本。银行余额是存量，不当主线。
int lighthouseTrendHeroIndex(List<bool> available) {
  const order = <int>[3, 4, 2, 0, 1, 5, 6];
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

/// 四个分区色 —— 跑过对比度 / 色盲分离校验。
///
/// 旧的现金流紫 0xFF7B5CD8 和利润蓝 0xFF5C6FB5 正常视力下只差 ΔE 8.7（门槛
/// 15），当 14px 图标片时没人计较，铺成彩带就是两条分不开的带子。
/// 换成紫 / 琥珀 / 绿 / 品红这一组，和资金池面板同一套色系。
///
/// 绿只给现金流：这个 App 里涨红跌绿，绿是状态色，给规模或利润会和它们格子里
/// 那一片 ↓ 环比抢同一个含义；现金流只有一个指标，且「现金 = 绿」是通识。
const lighthouseHeroSectionAccentValues = <String, int>{
  'scale': 0xFF7B5CD8,
  'cost': 0xFFC4791C,
  'cash': 0xFF1E9E72,
  'profit': 0xFFB8478F,
};

/// 分区靠整卡淡色底区分，不用彩带 —— 2.5px 的一道杠又细又硬，
/// 四张卡顶上四条不同颜色的线，看着像贴了四条胶带。
const bool lighthouseHeroShowsSectionBand = false;
const double lighthouseHeroSectionBandHeight = 0;

int lighthouseHeroSectionBandAlpha({required bool tracing}) =>
    tracing ? 55 : 255;

/// 标题 chip 底色 —— 试过「颜色只给标题一小块」，最后选了整卡淡底，
/// 这套值留着备用，当前不接。
const lighthouseHeroSectionChipValues = <String, int>{
  'scale': 0xFFEAE3FA,
  'cost': 0xFFF6EADA,
  'cash': 0xFFDDF0E7,
  'profit': 0xFFF7E5F0,
};

/// 分区卡底色 —— 整张卡吃一层淡色，颜色铺满才有分组感。
///
/// 查表取固定值，不用 accent.withAlpha：透明度叠色压在白底上会掉彩度，
/// 四张卡会一起发灰，那正是「淡」和「脏」的区别。
const lighthouseHeroSectionTintValues = <String, int>{
  'scale': 0xFFF6F3FD,
  'cost': 0xFFFCF6EC,
  'cash': 0xFFEDF8F3,
  'profit': 0xFFFBF1F7,
};

const lighthouseHeroSectionEdgeValues = <String, int>{
  'scale': 0xFFDCD1F5,
  'cost': 0xFFEDDCC2,
  'cash': 0xFFC6E7D9,
  'profit': 0xFFEFD2E4,
};

const lighthouseHeroSectionTitleValues = <String, int>{
  'scale': 0xFF5B3FB0,
  'cost': 0xFF8F550F,
  'cash': 0xFF146B4E,
  'profit': 0xFF8E3169,
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

/// 主 Hero 底部「成本合计 = 项目成本 + 业务成本 …」口径条。关掉，只留格子和走势。
const bool lighthouseHeroShowsFormulaBar = false;

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
  return [for (final e in raw) (e is num) ? e.toDouble() : 0.0];
}

const lighthouseProjectCostPreferredLabels = ['平台服务费', '支付手续费', '机构返佣'];

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
    [for (final label in labels) lighthouseHeroCompactPeriodLabel(label)],
    List<int>.generate(count, (i) => i),
  );
}

/// 供给卡片资金池展开：右侧独立全高点击条（不缩放，保证手机好点）。
const double lighthouseFundPoolExpandTapWidth = 44;
const double lighthouseFundPoolExpandIconSize = 22;

/// 预览格内箭头。跟标签同高一档：再大就把标签行顶高，整行跟着变高。
const double lighthouseFundPoolPreviewChevronSize = 10;

/// 预览行与上方 KPI 格等高 —— 两者都是「标签 + 数字」两行，内边距也一致，
/// 43 装得下；高出一截只会让资金摘要看起来不属于同一张表。
const double lighthouseFundPoolPreviewHeight = 43;

/// 分区标题（资金 / 券 / 期末预付款对账 / 资产）：行高 1.0 时中文 w600
/// 的字脚超出 TextPainter 盒，被 LhScrollText 的 clipRect 切掉。
const double lighthouseFundPoolSectionTitleLineHeight = 1.3;

/// 图标片和标题之间的空隙；再贴会挡住「资」「券」左侧笔画。
const double lighthouseFundPoolSectionTitleIconGap = 7;

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
const double lighthouseHeroSummaryRangeFontSize = 11;

String lighthouseTwoDigit(int n) => n.toString().padLeft(2, '0');

/// 与底部「选区间」同一写法：`08.01–08.31`。
String lighthouseMdDashRange(DateTime start, DateTime end) =>
    '${lighthouseTwoDigit(start.month)}.${lighthouseTwoDigit(start.day)}'
    '–${lighthouseTwoDigit(end.month)}.${lighthouseTwoDigit(end.day)}';

/// 单日 `08.25`，跨日 `08.01–08.25`。与后端 `rangeLabel` 一致。
String lighthouseRangeLabel(DateTime start, DateTime end) {
  final a = lighthouseDateOnly(start);
  final b = lighthouseDateOnly(end);
  if (a.year == b.year && a.month == b.month && a.day == b.day) {
    return '${lighthouseTwoDigit(b.month)}.${lighthouseTwoDigit(b.day)}';
  }
  return lighthouseMdDashRange(a, b);
}

DateTime lighthouseDateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// 上个月同一天；3/31 → 2/28（闰年 2/29），不会滚到 3/3。
DateTime lighthouseSameDayPrevMonth(DateTime ref) {
  final day = lighthouseDateOnly(ref);
  final prevFirst = DateTime(day.year, day.month - 1, 1);
  final lastDay = DateTime(prevFirst.year, prevFirst.month + 1, 0).day;
  final d = day.day > lastDay ? lastDay : day.day;
  return DateTime(prevFirst.year, prevFirst.month, d);
}

(DateTime start, DateTime end) lighthouseWeekBounds(DateTime ref) {
  final day = lighthouseDateOnly(ref);
  final start = day.subtract(Duration(days: day.weekday - 1));
  return (start, start.add(const Duration(days: 6)));
}

(DateTime start, DateTime end) lighthouseQuarterBounds(DateTime ref) {
  final day = lighthouseDateOnly(ref);
  final q0 = (day.month - 1) ~/ 3;
  final start = DateTime(day.year, q0 * 3 + 1, 1);
  final end = DateTime(start.year, start.month + 3, 0);
  return (start, end);
}

class LighthouseAlignedPeriod {
  const LighthouseAlignedPeriod({
    required this.currentLabel,
    required this.prevLabel,
    required this.deltaVs,
    required this.inProgress,
  });

  final String currentLabel;
  final String prevLabel;
  final String deltaVs;
  final bool inProgress;
}

/// 2026-08 运营会：环比必须同期对同期。
/// 日 = 上月同日；月/周/季未走完 = 已过天数对齐；年仍是整年对整年。
LighthouseAlignedPeriod lighthouseResolveAlignedPeriod({
  required String period,
  required DateTime now,
  int offset = 0,
}) {
  final today = lighthouseDateOnly(now);
  switch (period) {
    case 'day':
      final cur = today.add(Duration(days: offset));
      final prev = lighthouseSameDayPrevMonth(cur);
      return LighthouseAlignedPeriod(
        currentLabel: lighthouseRangeLabel(cur, cur),
        prevLabel: lighthouseRangeLabel(prev, prev),
        deltaVs: 'vs 上月同日',
        inProgress: offset == 0,
      );
    case 'week':
      var (start, end) = lighthouseWeekBounds(today);
      if (offset != 0) {
        start = start.add(Duration(days: offset * 7));
        end = start.add(const Duration(days: 6));
      }
      return _alignElapsed(
        start: start,
        end: end,
        today: today,
        offset: offset,
        completeVs: 'vs 上周',
        inProgressVs: 'vs 上周同期',
      );
    case 'quarter':
      var (start, end) = lighthouseQuarterBounds(today);
      if (offset != 0) {
        start = DateTime(start.year, start.month + offset * 3, 1);
        end = DateTime(start.year, start.month + 3, 0);
      }
      return _alignElapsed(
        start: start,
        end: end,
        today: today,
        offset: offset,
        completeVs: 'vs 上季',
        inProgressVs: 'vs 上季同期',
      );
    case 'year':
      final y = today.year + offset;
      final last = DateTime(y, 12, 31);
      return LighthouseAlignedPeriod(
        currentLabel: '$y.01.01–$y.12.31',
        prevLabel: '${y - 1}.01.01–${y - 1}.12.31',
        deltaVs: 'vs 去年',
        inProgress: offset == 0 && today.isBefore(last),
      );
    default:
      final monthStart = DateTime(today.year, today.month + offset, 1);
      final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
      return _alignElapsed(
        start: monthStart,
        end: monthEnd,
        today: today,
        offset: offset,
        completeVs: 'vs 上月',
        inProgressVs: 'vs 上月同期',
      );
  }
}

LighthouseAlignedPeriod _alignElapsed({
  required DateTime start,
  required DateTime end,
  required DateTime today,
  required int offset,
  required String completeVs,
  required String inProgressVs,
}) {
  var currentEnd = end;
  var inProgress = false;
  if (offset == 0 && !today.isBefore(start) && today.isBefore(end)) {
    currentEnd = today;
    inProgress = true;
  }
  final elapsed = currentEnd.difference(start).inDays;
  var prevStart = DateTime(start.year, start.month, start.day);
  // 上一窗口：周 = 往前 7 天；月 = 上个月 1 号；季 = 上季首日。
  if (completeVs == 'vs 上周') {
    prevStart = start.subtract(const Duration(days: 7));
  } else if (completeVs == 'vs 上季') {
    prevStart = DateTime(start.year, start.month - 3, 1);
  } else {
    prevStart = DateTime(start.year, start.month - 1, 1);
  }
  var prevEnd = prevStart.add(Duration(days: elapsed));
  DateTime prevLimit;
  if (completeVs == 'vs 上周') {
    prevLimit = start.subtract(const Duration(days: 1));
  } else if (completeVs == 'vs 上季') {
    prevLimit = DateTime(prevStart.year, prevStart.month + 3, 0);
  } else {
    prevLimit = DateTime(start.year, start.month, 0);
  }
  if (prevEnd.isAfter(prevLimit)) prevEnd = prevLimit;
  return LighthouseAlignedPeriod(
    currentLabel: lighthouseRangeLabel(start, currentEnd),
    prevLabel: lighthouseRangeLabel(prevStart, prevEnd),
    deltaVs: inProgress ? inProgressVs : completeVs,
    inProgress: inProgress,
  );
}

/// Hero「产品汇总 / 供给方汇总」右侧的区间，必须和列表控制条选中的窗口一致。
String lighthouseHeroSelectedRangeLabel({
  required bool isCustomRange,
  DateTime? customStart,
  DateTime? customEnd,
  required String periodInstanceDetail,
}) {
  if (isCustomRange && customStart != null && customEnd != null) {
    return lighthouseMdDashRange(customStart, customEnd);
  }
  return periodInstanceDetail.trim();
}

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
    for (final name
        in lighthouseNetTASecondariesByMapped[mappedName] ?? const <String>[])
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
      if ((raw['name']?.toString() ?? '').isNotEmpty)
        Map<String, dynamic>.from(raw),
  ];
  if (items.length <= maxCells) return items;
  final ranked = [...items]
    ..sort((a, b) {
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

/// 净TA 主 Hero 总览图：净TA / 经营活动 / 筹资活动 / 经营成本 / 项目成本 / 业务成本 / 银行余额。
const lighthouseNetTAHeroOverlaySlots = <String, String>{
  'netTa': 'scale',
  'netTaOperating': 'revenue',
  'netTaFinancing': 'scaleAlt',
  'netTaOpCost': 'cost',
  'netTaProjectCost': 'profit',
  'netTaBizCost': 'costAlt',
  'netTaBankBalance': 'stock',
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
    case 'stock':
      return 'netTaBankBalance';
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
  return [for (final e in raw) (e is num) ? e.toDouble() : 0.0];
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
    final parsedLabels =
        (m['labels'] is List && (m['labels'] as List).isNotEmpty)
        ? [
            for (final e in m['labels'] as List)
              if (e.toString().trim().isNotEmpty) e.toString().trim(),
          ]
        : labels;
    final projectCost = lighthouseReadNumberSeries(m['projectCost']);
    final businessCost = lighthouseReadNumberSeries(m['businessCost']);
    var projectAndBusiness = lighthouseReadNumberSeries(
      m['projectAndBusiness'],
    );
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
  'revenue',
  'netTa',
];

/// 产品 / 供给 / 渠道统一四核心：左列规模，右列经营结果。
/// 第三行对齐主 Hero 总图：成本合计 / 收入，点开后走同一套 `_TrendChart`。
const lighthouseLedgerSummaryMetricRows = <List<String>>[
  ['sales', 'prepaid'],
  ['verifiedSales', 'profit'],
  ['costTotal', 'revenue'],
];

/// 账本格可点开走势的指标，与主 Hero 格子同一批。
const lighthouseLedgerSoloTrendKeys = <String>{
  'sales',
  'verifiedSales',
  'gmv',
  'totalCost',
  'costTotal',
  'projectCost',
  'cost',
  'prepaid',
  'profit',
  'netProfit',
  'revenue',
  'spread',
  'grossMargin',
  'rate',
};

bool lighthouseLedgerMetricOpensSoloTrend(String key) =>
    lighthouseLedgerSoloTrendKeys.contains(key);

/// 点同一格收起；点另一格切换到那一条。
String? lighthouseLedgerSoloTrendAfterTap(String? current, String tapped) {
  if (!lighthouseLedgerMetricOpensSoloTrend(tapped)) return current;
  return current == tapped ? null : tapped;
}

/// Hero 用 `totalCost`、账本摘要用 `costTotal`，点开后要当成同一格。
bool lighthouseLedgerMetricKeysMatch(String? a, String b) {
  if (a == null || a.isEmpty) return false;
  if (a == b) return true;
  return lighthouseHeroFormulaCanonicalKey(a) ==
      lighthouseHeroFormulaCanonicalKey(b);
}

/// 总图槽位 → 账本格 key。成本槽用账本的 `costTotal`（Hero 格子是 `totalCost`）。
String? lighthouseLedgerMetricFromTrendSlot(
  String? slot, {
  required String scaleKey,
  required String scaleAltKey,
}) {
  switch (slot) {
    case 'profit':
      return 'profit';
    case 'revenue':
      return 'revenue';
    case 'cost':
      return 'costTotal';
    case 'scale':
      return scaleKey;
    case 'scaleAlt':
      return scaleAltKey.isEmpty ? scaleKey : scaleAltKey;
    default:
      return null;
  }
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
  return [for (final item in v) ..._asStringList(item)];
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
({String number, String unit}) lighthouseFormatFundPoolWanParts(
  double? amount,
) {
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

/// 日 / 周 / 月 / 季 / 年 / 自定义区间展开区都带发票块（原件、应开、实开）。
bool lighthouseFundPoolShowsInvoice(String _) => true;

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
    this.flowStartIndex,
  });
  final LighthouseFundPoolSectionKind kind;
  final String title;
  final List<LighthouseFundPoolMetricSpec> metrics;

  /// 从第几格开始是**流量**（一段时间的增量），前面的都是**存量**（时点余额）。
  ///
  /// null = 整张卡同一种量，不画分隔。只有资产卡是混的：资产合计是余额，
  /// 两条新增利润是区间累计。存量能相加（资产合计就是几项余额之和），
  /// 流量加不进去 —— 中间一条细线 + 一个「期间新增」的小字，
  /// 比给七个存量格各挂一个「存量」角标省事得多，也不用教用户会计名词。
  final int? flowStartIndex;
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

/// 资产卡 = 存量 + 增量。
///
/// 原来只有资产合计一个数，和左边四格的对账卡并排，整张卡三分之二是空的。
/// 更重要的是：这两条利润是**流量**（一段时间赚了多少），其余七个数全是
/// **存量**（某一时点的余额）——混在资金卡里，读的人会以为它也是余额。
/// 放在资产合计旁边，一张卡回答「手上有多少 / 最近赚了多少」，两种量各就各位。
const lighthouseFundPoolAssetsSection = LighthouseFundPoolSectionSpec(
  kind: LighthouseFundPoolSectionKind.assets,
  title: '资产',
  metrics: [
    LighthouseFundPoolMetricSpec('totalAssets', '资产合计'),
    LighthouseFundPoolMetricSpec('profitMonth', '本月新增利润'),
    LighthouseFundPoolMetricSpec('profitDay', '本日新增利润'),
  ],
  flowStartIndex: 1,
);

/// 分隔线上的小字。用「期间新增」不用「流量」—— 会计名词对着数字读没人懂。
const String lighthouseFundPoolFlowDividerLabel = '期间新增';

/// 按「增长」显示的格子：数字前挂 ↑ / ↓，正负吃涨跌色。
///
/// 其余格子都是余额，是中性的量，染色只会把「负数」和「变差」搞混；
/// 这两条本身就是增量，方向才是它要说的事。
const lighthouseFundPoolGrowthMetricKeys = <String>{'profitMonth', 'profitDay'};

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

/// 值不来自 `/fund-pool` 的格子 —— 由调用方按省份另行喂进来。
const lighthouseFundPoolExternalMetricKeys = <String>{
  'profitMonth',
  'profitDay',
};

/// 供给行名 → 省份 map 的取值，口径和 [lighthouseLookupFundPool] 一致：
/// 先精确，再双向包含模糊匹配，合计行不参与模糊。
double? lighthouseLookupProvinceAmount(
  Map<String, double> byProvince,
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

/// ── Hero 指标格的关联关系 ────────────────────────────────────────────
///
/// 13 个格子都能点：走势切到这一项，有口径的同时打开底部公式行。
/// 算出来的格子会点亮来源、压暗无关格；取数项只出式子，不压暗别人。
enum LighthouseHeroFormulaRole { plus, minus, numerator, denominator }

/// 角标文案 —— ROI 和毛利率都点亮「毛利润」，一个当分子一个当分母，
/// 光靠点亮分不出谁除谁。
String lighthouseHeroFormulaRoleBadge(LighthouseHeroFormulaRole role) =>
    switch (role) {
      LighthouseHeroFormulaRole.plus => '+',
      LighthouseHeroFormulaRole.minus => '−',
      LighthouseHeroFormulaRole.numerator => '分子',
      LighthouseHeroFormulaRole.denominator => '分母',
    };

class LighthouseHeroFormulaSource {
  const LighthouseHeroFormulaSource(this.key, this.role);
  final String key;
  final LighthouseHeroFormulaRole role;
}

class LighthouseHeroFormula {
  const LighthouseHeroFormula({
    required this.resultKey,
    required this.result,
    required this.expression,
    required this.sources,
    this.substitutes = true,
  });

  final String resultKey;
  final String result;

  /// 空格分词，运算符单独成词。
  final String expression;
  final List<LighthouseHeroFormulaSource> sources;

  /// 底部那行右边是否把数代进去。
  ///
  /// 毛利润这条按口径挂上，但代进去是 `收入 − 成本合计 = 147.7`，
  /// 而格子里写着 140.5 —— 界面自己打自己。口径确认前只显示式子。
  final bool substitutes;
}

const lighthouseHeroFormulas = <LighthouseHeroFormula>[
  LighthouseHeroFormula(
    resultKey: 'sales',
    result: '销售额',
    expression: '下单张数 × 面值',
    sources: [],
    substitutes: false,
  ),
  LighthouseHeroFormula(
    resultKey: 'verifiedSales',
    result: '核销额',
    expression: '核销张数 × 面值',
    sources: [],
    substitutes: false,
  ),
  LighthouseHeroFormula(
    resultKey: 'gmv',
    result: 'GMV',
    expression: '撮合交易额',
    sources: [],
    substitutes: false,
  ),
  LighthouseHeroFormula(
    resultKey: 'totalCost',
    result: '成本合计',
    expression: '项目成本 + 业务成本',
    sources: [
      LighthouseHeroFormulaSource(
        'projectCost',
        LighthouseHeroFormulaRole.plus,
      ),
      LighthouseHeroFormulaSource('cost', LighthouseHeroFormulaRole.plus),
    ],
  ),
  LighthouseHeroFormula(
    resultKey: 'projectCost',
    result: '项目成本',
    expression: '毛利润对应成本',
    sources: [],
    substitutes: false,
  ),
  LighthouseHeroFormula(
    resultKey: 'cost',
    result: '业务成本',
    expression: '账单三级 BUSINESS_COST',
    sources: [],
    substitutes: false,
  ),
  LighthouseHeroFormula(
    resultKey: 'prepaid',
    result: '预收净增',
    // 「销售额 − 核销额」是会上的业务定义，但现网数字对不上：
    // 供给维 销售额 1575.0万 − 核销额 762.5万 = 812.5万，而预收净增显示 22.63万，
    // 差 36 倍；换一组（438.1 − 321.7 = 116.4 vs 5.74）差 20 倍，不是偶然。
    // 代码里也只是直读 prepaid 字段，没有做这个减法。
    //
    // 把那条式子写在界面上，用户拿旁边两个格子一减就能发现对不上 ——
    // 界面自己打自己。口径核清楚之前如实标「待核」。
    expression: '后端直给 prepaid · 口径待核',
    sources: [
      LighthouseHeroFormulaSource('sales', LighthouseHeroFormulaRole.plus),
      LighthouseHeroFormulaSource(
        'verifiedSales',
        LighthouseHeroFormulaRole.minus,
      ),
    ],
    substitutes: false,
  ),
  LighthouseHeroFormula(
    resultKey: 'profit',
    result: '毛利润',
    expression: '收入 − 成本合计',
    sources: [
      LighthouseHeroFormulaSource('revenue', LighthouseHeroFormulaRole.plus),
      LighthouseHeroFormulaSource('totalCost', LighthouseHeroFormulaRole.minus),
    ],
    substitutes: false,
  ),
  LighthouseHeroFormula(
    resultKey: 'netProfit',
    result: '净利润',
    expression: '毛利润 − 业务成本',
    sources: [
      LighthouseHeroFormulaSource('profit', LighthouseHeroFormulaRole.plus),
      LighthouseHeroFormulaSource('cost', LighthouseHeroFormulaRole.minus),
    ],
  ),
  LighthouseHeroFormula(
    resultKey: 'revenue',
    result: '收入',
    expression: '核销额 × 利差率',
    sources: [],
    substitutes: false,
  ),
  LighthouseHeroFormula(
    resultKey: 'spread',
    result: '利差',
    expression: '已核销利差',
    sources: [],
    substitutes: false,
  ),
  LighthouseHeroFormula(
    resultKey: 'grossMargin',
    result: '毛利率',
    expression: '毛利润 ÷ 核销额',
    sources: [
      LighthouseHeroFormulaSource(
        'profit',
        LighthouseHeroFormulaRole.numerator,
      ),
      LighthouseHeroFormulaSource(
        'verifiedSales',
        LighthouseHeroFormulaRole.denominator,
      ),
    ],
  ),
  LighthouseHeroFormula(
    resultKey: 'rate',
    result: 'ROI',
    expression: '毛利润 ÷ 成本合计',
    sources: [
      LighthouseHeroFormulaSource(
        'profit',
        LighthouseHeroFormulaRole.numerator,
      ),
      LighthouseHeroFormulaSource(
        'totalCost',
        LighthouseHeroFormulaRole.denominator,
      ),
    ],
  ),
];

String lighthouseHeroFormulaCanonicalKey(String metricKey) =>
    switch (metricKey) {
      'costTotal' => 'totalCost',
      'businessCost' => 'cost',
      _ => metricKey,
    };

LighthouseHeroFormula? lighthouseHeroFormulaForKey(String metricKey) {
  final canonical = lighthouseHeroFormulaCanonicalKey(metricKey);
  for (final f in lighthouseHeroFormulas) {
    if (f.resultKey == canonical) return f;
  }
  return null;
}

/// 点格子：走势和口径一起切；再点同一格收起。
({String? focus, String? trace}) lighthouseHeroMetricActivateAfterTap(
  String? currentFocus,
  String tapped,
) {
  final focus = lighthouseHeroTrendFocusAfterTap(currentFocus, tapped);
  if (focus == null) return (focus: null, trace: null);
  final hasFormula = lighthouseHeroFormulaForKey(tapped) != null;
  return (focus: focus, trace: hasFormula ? tapped : null);
}

/// 追溯中这一格扮演什么角色；不参与返回 null。
LighthouseHeroFormulaRole? lighthouseHeroTraceRole(
  String? traced,
  String metricKey,
) {
  if (traced == null) return null;
  final formula = lighthouseHeroFormulaForKey(traced);
  if (formula == null) return null;
  for (final source in formula.sources) {
    if (source.key == metricKey) return source.role;
  }
  return null;
}

/// 追溯时无关的格子压暗 —— 只加亮的话，13 个里亮 2 个还是要找。
/// 取数项没有来源格，压暗整屏没有信息量，只出式子。
bool lighthouseHeroTraceDims(String? traced, String metricKey) {
  if (traced == null) return false;
  if (traced == metricKey) return false;
  final formula = lighthouseHeroFormulaForKey(traced);
  if (formula == null || formula.sources.isEmpty) return false;
  return lighthouseHeroTraceRole(traced, metricKey) == null;
}

/// 点同一格收起；点另一个结果格切过去；点没有公式的键不动。
String? lighthouseHeroTraceAfterTap(String? current, String tappedKey) {
  if (lighthouseHeroFormulaForKey(tappedKey) == null) return current;
  return current == tappedKey ? null : tappedKey;
}

/// ── 标签对账状态 ────────────────────────────────────────────────
///
/// 对账**全部在资管后台做**，灯塔只呈现结果，不提供任何确认操作 ——
/// 这是会上唯一被明确否掉的方案（「沙丘前端应该是呈现不能去操作」）。
///
/// 状态不是布尔。对账按笔（或按财务项目）进行，标签是聚合的：一个省下 200 笔，
/// 对完 3 笔是「有对账」，全对完也是「有对账」，一个绿勾分不出来。
/// 参照银行流水子表现网分布（已拆分仅占 1%），按「有没有对账记录」打勾会绿成
/// 一片而绝大部分钱没对 —— 那比不显示还糟。所以必须带金额覆盖率。
/// 四态。`overdue` 是 D+N 账期机制存在的全部理由 ——
/// 「还在账期内正常等」和「超期没到」必须分开，否则等于没有这把尺子。
///
/// 原话可以当验收标准：「为什么同意他在 D+2 之内不显示风险事项」。
/// 账期内不报风险，超期才报，两者共用一个颜色就把这句话作废了。
/// 资管侧的一条对账备注。灯塔**只读**——会上唯一被否掉的方案就是让灯塔去操作，
/// 所以这里没有输入框、没有回复、没有已读。
///
/// 它回答的是 chip 回答不了的那个问题：为什么没对完。
/// 「未对账 2」只说有事，不说什么事；「对方账单未出，等下午再核」是能直接
/// 拿去问人的东西。差异的解释本来就写在资管里，搬过来看一眼，别让人再登一次。
class LighthouseReconComment {
  const LighthouseReconComment({
    required this.content,
    this.author = '',
    this.time = '',
    this.source = '资管',
    this.targetName = '',
    this.stage = '',
    this.isReject = false,
  });

  final String content;
  final String author;

  /// 后端给已格式化的串（`HH:mm` 或 `MM-dd HH:mm`）。
  /// 灯塔不做时区和相对时间的换算 —— 换算错了比不显示更糟。
  final String time;
  final String source;

  /// 备注指向的对象，例如「中智关爱通」。省内多个主体时靠它区分。
  final String targetName;

  /// 哪一环节写的：财务 / 业务 / 运营。标签三的新接口才有，标签二为空。
  final String stage;

  /// 这条是不是**驳回**。
  ///
  /// 新标签三接口不给超期数据，界面上的红色就只剩这一个来源 ——
  /// 驳回是「有人不认这笔账」，它替代不了「钱该到没到」，但它是目前
  /// 唯一能说「这里出事了」的信号。
  final bool isReject;

  bool get isEmpty => content.trim().isEmpty;

  /// 「资管 · 王艳丽 · 10:12」，缺项自动省略，不留空的分隔点。
  String get headline =>
      [source, author, time].where((s) => s.trim().isNotEmpty).join(' · ');

  String get body =>
      targetName.trim().isEmpty ? content : '${targetName.trim()}：$content';
}

/// `recon.comments` → 列表。非列表、空内容、超过上限的都丢掉。
///
/// 上限 5：面板里只露最新一条 + 「还有 N 条」，全量在资管里。
/// 不设上限的话，一个省挂几十条备注会把整个 JSON 撑起来，而界面一条都不会多显示。
List<LighthouseReconComment> lighthouseParseReconComments(dynamic raw) {
  if (raw is! List) return const [];
  final out = <LighthouseReconComment>[];
  for (final item in raw) {
    if (item is! Map) continue;
    // 资管那边先给的 demo 用的是 snake_case，正式契约走 camelCase。
    // 两种都收：联调期少一次来回，代价只是几个 ?? 。
    String pick(String camel, String snake) =>
        (item[camel] ?? item[snake])?.toString().trim() ?? '';
    final content = pick('content', 'comment_content');
    if (content.isEmpty) continue;
    out.add(
      LighthouseReconComment(
        content: content,
        author: pick('author', 'comment_author'),
        time: pick('time', 'comment_time'),
        source: () {
          final s = pick('source', 'comment_source');
          return s.isEmpty ? '资管' : s;
        }(),
        targetName: pick('targetName', 'target_name'),
        stage: pick('stage', 'stage_label'),
        isReject: item['isReject'] == true || item['is_reject'] == true,
      ),
    );
    if (out.length >= lighthouseReconCommentMax) break;
  }
  return out;
}

const int lighthouseReconCommentMax = 5;

enum LighthouseReconState { none, partial, done, overdue }

/// 结算周期。D+N 按天，M+N 按月（月回款渠道不按天判超期）。
enum LighthouseSettlementKind { day, month }

/// 这一行现在归谁 —— 没对完的时候「找谁」。
///
/// 和 [LighthouseReconStatus.confirmedBy] 是两个人：owner 是「现在归谁、催谁」，
/// confirmedBy 是「谁签的字」。已对账的行两个都有值很正常。
///
/// 会上定的标签三颗粒度是「按财务颗粒度打包分人」—— 分人是这一维的组织方式，
/// 所以人不是附加信息，是标签三的主键之一。
class LighthouseReconOwner {
  const LighthouseReconOwner({this.name = '', this.role = '', this.phone = ''});

  final String name;

  /// 运营 / 财务 / 业务。空串就只显示名字。
  final String role;
  final String phone;

  bool get isEmpty => name.trim().isEmpty;

  /// 「王艳丽 · 运营」。没有角色就只有名字。
  String get label {
    final n = name.trim();
    if (n.isEmpty) return '';
    final r = role.trim();
    return r.isEmpty ? n : '$n · $r';
  }
}

LighthouseReconOwner? lighthouseParseReconOwner(dynamic raw) {
  if (raw is! Map) return null;
  String pick(String key) => raw[key]?.toString().trim() ?? '';
  final owner = LighthouseReconOwner(
    name: pick('name'),
    role: pick('role'),
    phone: pick('phone'),
  );
  // 只有角色没有名字等于没给人 —— 界面上「· 运营」比空着更难看。
  return owner.isEmpty ? null : owner;
}

class LighthouseReconStatus {
  const LighthouseReconStatus({
    required this.state,
    this.coveredAmount = 0,
    this.totalAmount = 0,
    this.confirmedBy = '',
    this.confirmedAt = '',
    this.deepLink = '',
    this.crossCoveredPct,
    this.settlementKind,
    this.settlementDays,
    this.settlementFromProposal = true,
    this.overdueCount = 0,
    this.overdueAmount = 0,
    this.comments = const [],
    this.owner,
    this.confirmedCount = 0,
    this.totalCount = 0,
    this.pendingStageLabel = '',
  });

  final LighthouseReconState state;
  final double coveredAmount;
  final double totalAmount;
  final String confirmedBy;
  final String confirmedAt;

  /// 这行现在归谁。资管没给就是 null，界面上整块不显示 ——
  /// 和 recon 本身一样：没给不等于「没人负责」，不编一个「未分配」出来。
  final LighthouseReconOwner? owner;

  /// 项目数分数 —— **不是金额覆盖率**。
  ///
  /// 资管的新标签三接口（AM-LH-SHUCAI-TAG3V2-RECON-001）不给金额，
  /// 所以「对账 86%」那种金额口径没有数据源了。退而求其次数项目个数：
  /// 一个渠道行下 10 个项目确认完 9 个 = 9/10。
  ///
  /// 界面上必须写「已确认 9/10」，**不能写 90%** —— 百分号在这一屏的
  /// 其它地方全是金额，会被读成钱。
  ///
  /// 标签二（供给）如果将来给金额，仍然走 coveredAmount/totalAmount，
  /// 两种口径共存，靠哪个字段有值决定显示哪种。
  final int confirmedCount;
  final int totalCount;

  /// 卡在哪一步：财务 / 业务 / 运营。全过了或没数据为空串。
  final String pendingStageLabel;

  /// 有没有项目数口径可用。
  bool get hasProjectScore => totalCount > 0;

  /// 有没有驳回。红色的唯一来源（新标签三没有超期数据）。
  bool get hasReject => comments.any((c) => c.isReject);

  /// 「找谁」这句话有没有答案。
  bool get hasOwner => owner != null && !owner!.isEmpty;

  /// 资管后台对应页面。老板明确要的「前面页面映射到后台那个页面」——
  /// 状态只读，但入口在灯塔：看到没对完的，从这里点进去对。
  final String deepLink;

  /// 仅标签二：销售侧（标签三）已覆盖比例，**参考值，不改变自身状态**。
  ///
  /// 会上老板主张「标签三点完就等于标签二点完」，业务侧反对，没有结论。
  /// 两边各对一半：覆盖上老板对（三个标签是同一批交易的三个切面，标签三全确认
  /// 等于所有交易都被摸过一遍）；内容上业务侧对（标签三按**销售额**确认渠道应收，
  /// 标签二按**核销额**确认供给核销和折扣，是两个不同的检查项，中间差着预收和
  /// 供给侧折扣）。所以这里只传导「已被覆盖」，不传导「已确认」。
  final double? crossCoveredPct;

  /// 账期。来自提案的财务板块（结算模式 / 结算周期），对账时不允许另行判断。
  /// 同一个渠道方下不同渠道可能不同（平安有的 D+1 有的 D+2），所以挂在行上。
  final LighthouseSettlementKind? settlementKind;
  final int? settlementDays;

  /// 账期是不是从采购/合作协议自动带出的。
  ///
  /// 会上问过「这个是手填的吗？如果手填，数据会不会不准」——当场没答。
  /// 手填的账期一旦填错，超期判定跟着错，而界面上看不出来。所以这里留一个位：
  /// 非自动带出的，chip 上要能标出来，别让一个手填的 D+5 冒充事实。
  final bool settlementFromProposal;

  /// 超账期仍未到账的笔数与金额。这才是要报红的东西。
  final int overdueCount;
  final double overdueAmount;

  /// 资管侧写的对账备注，最新的在前。只读。
  final List<LighthouseReconComment> comments;

  bool get hasComments => comments.isNotEmpty;

  /// 覆盖率。总额为 0 时返回 null —— 没有分母的百分比不能显示。
  double? get coveredPct {
    if (totalAmount.abs() < 1e-9) return null;
    return coveredAmount / totalAmount * 100;
  }

  double get pendingAmount => totalAmount - coveredAmount;
  bool get hasDeepLink => deepLink.trim().isNotEmpty;
  bool get hasOverdue => overdueCount > 0 || overdueAmount.abs() > 1e-9;

  /// 账期文案：`D+2` / `M+1`。没有账期返回空串。
  String get settlementLabel {
    final days = settlementDays;
    final kind = settlementKind;
    if (days == null || kind == null) return '';
    final prefix = kind == LighthouseSettlementKind.month ? 'M' : 'D';
    return '$prefix+$days';
  }

  /// 主状态只看人对完没有。超期是钱的尺子，不挡「已对账」。
  bool get showsGreen => state == LighthouseReconState.done;
}

LighthouseReconState lighthouseParseReconState(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'done':
    case 'confirmed':
      return LighthouseReconState.done;
    case 'partial':
      return LighthouseReconState.partial;
    case 'overdue':
      return LighthouseReconState.overdue;
  }
  return LighthouseReconState.none;
}

LighthouseSettlementKind? lighthouseParseSettlementKind(String raw) {
  switch (raw.trim().toUpperCase()) {
    case 'D':
    case 'DAY':
      return LighthouseSettlementKind.day;
    case 'M':
    case 'MONTH':
      return LighthouseSettlementKind.month;
  }
  return null;
}

/// 行上的 `recon` 字段 → 状态。字段缺失返回 null，界面上整块不渲染 ——
/// 和银行余额同一套处理：拿不到就当没有，不显示「未对账」。
///
/// 「没有状态」和「未对账」是两件事：前者是资管还没接，后者是接了但没对。
/// 混成一个会让所有行在联调前全变红。
LighthouseReconStatus? lighthouseParseReconStatus(dynamic raw) {
  if (raw is! Map) return null;
  final stateRaw = raw['state']?.toString() ?? '';
  if (stateRaw.trim().isEmpty) return null;
  double num0(String key) => (raw[key] as num?)?.toDouble() ?? 0;
  int int0(String key) => (raw[key] as num?)?.toInt() ?? 0;
  final daysRaw = raw['settlementDays'];
  final crossRaw = raw['crossCoveredPct'];
  return LighthouseReconStatus(
    state: lighthouseParseReconState(stateRaw),
    coveredAmount: num0('coveredAmount'),
    totalAmount: num0('totalAmount'),
    confirmedBy: raw['confirmedBy']?.toString().trim() ?? '',
    confirmedAt: raw['confirmedAt']?.toString().trim() ?? '',
    deepLink: raw['deepLink']?.toString().trim() ?? '',
    crossCoveredPct: crossRaw is num ? crossRaw.toDouble() : null,
    settlementKind: lighthouseParseSettlementKind(
      raw['settlementKind']?.toString() ?? '',
    ),
    settlementDays: daysRaw is num ? daysRaw.toInt() : null,
    settlementFromProposal: raw['settlementFromProposal'] != false,
    overdueCount: int0('overdueCount'),
    overdueAmount: num0('overdueAmount'),
    comments: lighthouseParseReconComments(raw['comments']),
    owner: lighthouseParseReconOwner(raw['owner']),
    confirmedCount: int0('confirmedCount'),
    totalCount: int0('totalCount'),
    pendingStageLabel: raw['pendingStageLabel']?.toString().trim() ?? '',
  );
}

/// 只有供给（标签二）和渠道（标签三）有对账状态。产品维（标签一）不对账。
bool lighthouseTabHasRecon(String tab) {
  final t = tab.trim();
  return t == 'supply' || t == 'channel';
}

const lighthouseUnconfirmedRecon = LighthouseReconStatus(
  state: LighthouseReconState.none,
);

/// 供给 / 渠道缺 `recon` 时按未对账呈现。资管未接真数据前全部如此。
LighthouseReconStatus? lighthouseReconStatusForRow(String tab, Object? raw) {
  if (!lighthouseTabHasRecon(tab)) return null;
  return lighthouseParseReconStatus(raw) ?? lighthouseUnconfirmedRecon;
}

/// 本地 debug 预览对账 chip / 对账人 / 驳回。发版 `kDebugMode` 为 false，不会带上。
/// 看完改回 `false`。
const bool lighthouseReconUsesLocalPreview = true;

const lighthouseReconPreviewFixtures = <Map<String, dynamic>>[
  {
    'state': 'partial',
    'confirmedCount': 9,
    'totalCount': 10,
    'pendingStageLabel': '业务',
    'owner': {'name': '卢笛', 'role': '业务'},
    'comments': [
      {
        'content': '渠道账单未出，等下午再核。',
        'author': '卢笛',
        'time': '09-03 10:12',
        'stage': '业务',
      },
    ],
  },
  {
    'state': 'overdue',
    'confirmedCount': 9,
    'totalCount': 10,
    'pendingStageLabel': '业务',
    'owner': {'name': '卢笛', 'role': '业务'},
    'comments': [
      {
        'content': '折扣对不上，驳回。',
        'author': '卢笛',
        'time': '09-02 16:40',
        'stage': '业务',
        'isReject': true,
      },
      {
        'content': '财务已确认金额。',
        'author': '刘雨滴',
        'time': '09-02 10:12',
        'stage': '财务',
      },
    ],
  },
  {
    'state': 'done',
    'confirmedCount': 8,
    'totalCount': 8,
    'owner': {'name': 'LBZ', 'role': '运营'},
    'confirmedBy': 'LBZ',
    'comments': [
      {
        'content': '三步都过了。',
        'author': 'LBZ',
        'time': '09-03 09:01',
        'stage': '运营',
      },
    ],
  },
  {
    'state': 'none',
    'confirmedCount': 0,
    'totalCount': 6,
    'pendingStageLabel': '财务',
    'owner': {'name': '刘雨滴', 'role': '财务'},
  },
  {
    'state': 'partial',
    'coveredAmount': 860000,
    'totalAmount': 1000000,
    'owner': {'name': '王艳丽', 'role': '运营'},
    'comments': [
      {'content': '核销差 2 笔，等供应商补单。', 'author': '王艳丽', 'time': '11:08'},
    ],
  },
  {'state': 'none'},
];

Map<String, dynamic> lighthouseReconPreviewRaw(int index) {
  final n = lighthouseReconPreviewFixtures.length;
  return Map<String, dynamic>.from(lighthouseReconPreviewFixtures[index % n]);
}

/// 行上已有 `recon` 不覆盖。预览关掉或产品维原样返回。
Object? lighthouseReconRawOrPreview({
  required String tab,
  required int index,
  Object? raw,
  bool preview = false,
}) {
  if (!lighthouseTabHasRecon(tab)) return raw;
  if (raw != null) return raw;
  if (!preview) return raw;
  return lighthouseReconPreviewRaw(index);
}

/// chip 上的短文案。
///
/// `done` 不显示百分比 —— 已对账就是 100%，再写个数字是噪音。
/// `partial` 必须显示百分比，这是整个设计的要点。
String lighthouseReconChipLabel(LighthouseReconStatus status) {
  // 驳回优先于一切。新标签三接口没有超期数据，红色只剩这一个来源 ——
  // 一行 10 个项目确认完 9 个，只要有一条驳回也得先说驳回：
  // 老板会上要的是「有不通过的把那个问题暴露出来」。
  if (status.hasReject) return '有驳回';
  switch (status.state) {
    case LighthouseReconState.done:
      return '已对账';
    case LighthouseReconState.partial:
    case LighthouseReconState.overdue:
      // 金额口径优先（标签二）；没有金额才退到项目数口径（标签三）。
      final pct = status.coveredPct;
      if (pct != null) {
        return '对账 ${pct.toStringAsFixed(pct >= 10 ? 0 : 1)}%';
      }
      if (status.hasProjectScore) {
        return '已确认 ${status.confirmedCount}/${status.totalCount}';
      }
      return '对账中';
    case LighthouseReconState.none:
      // 有分数就说分数：「0/10」比「未对账」多告诉一件事 —— 一共有多少个。
      if (status.hasProjectScore) {
        return '已确认 ${status.confirmedCount}/${status.totalCount}';
      }
      return '未对账';
  }
}

/// 「卡在谁那儿」。资管给的是**三个人 + 卡在哪一步**，组合起来才是答案：
/// 「待业务确认 · 卢笛」。这比一个孤立的 owner 准确 —— 老板看到没对完，
/// 下一个动作是找人，要的正是这一句。
///
/// 没有环节或没配人返回空串，界面上整块不显示。
String lighthouseReconPendingWho(LighthouseReconStatus status) {
  final stage = status.pendingStageLabel.trim();
  final who = status.owner?.name.trim() ?? '';
  if (stage.isEmpty && who.isEmpty) return '';
  if (stage.isEmpty) return who;
  if (who.isEmpty) return '待$stage确认';
  return '待$stage确认 · $who';
}

/// 行状态旁始终显示评论条数；没有就是 0。正文只在只读弹层里。
int lighthouseReconCommentEntryCount(LighthouseReconStatus status) =>
    status.comments.length;

/// 账期一句话。界面上只印一个「D+2」，看的人无从知道它在说什么 ——
/// 实际被问到的原话就是「对账周期和 D+2 到底什么关系，不是回款吗」。
///
/// 是回款。D+N 不是对账的周期，是**钱应该什么时候到**的约定：
/// 对账做的是「该到的钱到没到、金额对不对」，D+N 只提供那把尺子 ——
/// 没有它，「还没到账」既可能是正常在途，也可能是出事了，分不出来。
/// 所以这句话要写在界面上，不能指望看的人自己接上。
///
/// 没有账期返回空串。
String lighthouseSettlementExplain(LighthouseReconStatus status) {
  final days = status.settlementDays;
  final kind = status.settlementKind;
  if (days == null || kind == null) return '';
  final when = kind == LighthouseSettlementKind.month
      ? (days == 1 ? '次月结算' : '第 $days 个月结算')
      : '交易后第 $days 天到账';
  final base = '账期 ${status.settlementLabel} · $when，超过未到才算超期';
  // 手填的账期：这句话的可信度取决于它是不是从提案带出来的。
  return status.settlementFromProposal ? base : '$base（人工填写，未核）';
}

/// 一屏行里的超期汇总。
///
/// 会上原话：「如果有不通过的，把那个问题给我暴露出来，是一个还是两个，
/// 在这里面就能看到」。逐行看要翻几十行，所以在列表顶上收一条。
///
/// 只统计**有 recon 数据**的行：字段没接的行不算「没问题」，也不算「有问题」。
class LighthouseReconOverview {
  const LighthouseReconOverview({
    required this.rowsWithStatus,
    required this.overdueRows,
    required this.overdueCount,
    required this.overdueAmount,
    required this.doneRows,
    this.noSettlementRows = 0,
    this.manualSettlementRows = 0,
  });

  final int rowsWithStatus;

  /// 有超期的行数（几个省 / 几个渠道出问题），不是笔数。
  final int overdueRows;

  /// 超期笔数与金额合计。
  final int overdueCount;
  final double overdueAmount;

  /// 已对账行数 —— 与 [LighthouseReconStatus.showsGreen] 同一口径。
  final int doneRows;

  /// 没有账期的行数。会上问的是「D+2 之内不显示风险」，可没有账期的行
  /// 连「之内」都无从算起 —— 它们既不绿也不红，是尺子本身缺了一段。
  final int noSettlementRows;

  /// 账期是人工手填的行数（`settlementFromProposal == false`）。
  /// 会上问过「手填的数据会不会不准」，当场没答。超期判定完全建立在这个数上，
  /// 手填的多，红点的可信度就低 —— 这个数得能被看见。
  final int manualSettlementRows;

  bool get hasAny => rowsWithStatus > 0;
  bool get hasOverdue => overdueRows > 0;
  bool get allGreen => hasAny && doneRows == rowsWithStatus;
}

LighthouseReconOverview lighthouseSummarizeRecon(
  Iterable<LighthouseReconStatus?> statuses,
) {
  var rows = 0, overdueRows = 0, overdueCount = 0, doneRows = 0;
  var noSettlement = 0, manualSettlement = 0;
  var overdueAmount = 0.0;
  for (final s in statuses) {
    if (s == null) continue;
    rows++;
    if (s.settlementLabel.isEmpty) {
      noSettlement++;
    } else if (!s.settlementFromProposal) {
      manualSettlement++;
    }
    if (s.hasOverdue || s.state == LighthouseReconState.overdue) {
      overdueRows++;
      overdueCount += s.overdueCount;
      overdueAmount += s.overdueAmount;
    }
    if (s.showsGreen) doneRows++;
  }
  return LighthouseReconOverview(
    rowsWithStatus: rows,
    overdueRows: overdueRows,
    overdueCount: overdueCount,
    overdueAmount: overdueAmount,
    doneRows: doneRows,
    noSettlementRows: noSettlement,
    manualSettlementRows: manualSettlement,
  );
}

/// 汇总条右侧的账期成色。空串 = 账期这块没什么要说的。
///
/// 和左边的超期分开写：左边说「对账做到哪了」，右边说「这把尺子准不准」。
/// 一个 100% 绿、但一半的行没账期的列表，绿得没有意义 —— 那才是要露出来的。
String lighthouseReconSettlementNote(LighthouseReconOverview o) {
  if (!o.hasAny) return '';
  final parts = <String>[];
  if (o.noSettlementRows > 0) parts.add('${o.noSettlementRows} 个无账期');
  if (o.manualSettlementRows > 0) parts.add('${o.manualSettlementRows} 个手填');
  return parts.join(' · ');
}

/// 顶栏不再报超期。进度已经写在每一行上。
String lighthouseReconOverviewLabel(LighthouseReconOverview overview) {
  return '';
}

/// 发版不再灌假对账 / 假日清。缺字段的行由 [lighthouseReconStatusForRow] 显示未对账。
List<Map<String, dynamic>> lighthouseAttachDemoRecon(
  String tab,
  List<Map<String, dynamic>> rows, {
  DateTime? now,
}) {
  return rows;
}

/// ── 日清明细 ──────────────────────────────────────────────────
///
/// 老板白板上就两行：**上日** 和 **当月累计**，各看规模和利润。
/// 「月回款的项目就两行，第一行前一天、第二行当月累计」是同一个要求。
/// 所以这里不做长表，就是 2×2 四个数。
///
/// 灯塔上只呈现，不填、不确认、不复核 ——
/// 「填一次一刀切全部结束」「只要出现人工复核，就代表系统逻辑不成立」。
enum LighthouseApprovalStep { pending, done }

class LighthouseDailyCloseRow {
  const LighthouseDailyCloseRow({
    required this.scale,
    required this.profit,
    this.label = '',
  });
  final double? scale;
  final double? profit;

  /// 日期范围文案，如 `9/1` 或 `9/1 – 9/2`。
  final String label;
}

class LighthouseDailyClose {
  const LighthouseDailyClose({
    required this.lastDay,
    required this.monthToDate,
    this.finance = LighthouseApprovalStep.pending,
    this.business = LighthouseApprovalStep.pending,
    this.operation = LighthouseApprovalStep.pending,
  });

  final LighthouseDailyCloseRow lastDay;
  final LighthouseDailyCloseRow monthToDate;

  /// 三步审批，顺序固定：财务先填 → 业务填 → 运营确认。
  final LighthouseApprovalStep finance;
  final LighthouseApprovalStep business;
  final LighthouseApprovalStep operation;

  bool get allApproved =>
      finance == LighthouseApprovalStep.done &&
      business == LighthouseApprovalStep.done &&
      operation == LighthouseApprovalStep.done;

  /// 卡在谁那儿。全过返回空串。
  String get pendingStepLabel {
    if (finance != LighthouseApprovalStep.done) return '财务';
    if (business != LighthouseApprovalStep.done) return '业务';
    if (operation != LighthouseApprovalStep.done) return '运营';
    return '';
  }
}

LighthouseApprovalStep lighthouseParseApprovalStep(String raw) =>
    raw.trim().toLowerCase() == 'done'
    ? LighthouseApprovalStep.done
    : LighthouseApprovalStep.pending;

/// 行上的 `daily` 字段 → 日清明细。缺失返回 null，整块不渲染。
LighthouseDailyClose? lighthouseParseDailyClose(dynamic raw) {
  if (raw is! Map) return null;
  LighthouseDailyCloseRow? row(dynamic v, String Function(Map) label) {
    if (v is! Map) return null;
    final scale = (v['scale'] as num?)?.toDouble();
    final profit = (v['profit'] as num?)?.toDouble();
    if (scale == null && profit == null) return null;
    return LighthouseDailyCloseRow(
      scale: scale,
      profit: profit,
      label: label(v),
    );
  }

  final last = row(raw['lastDay'], (m) => lighthouseShortDate(m['date']));
  final mtd = row(raw['monthToDate'], (m) {
    final from = lighthouseShortDate(m['from']);
    final to = lighthouseShortDate(m['to']);
    if (from.isEmpty || to.isEmpty) return from.isEmpty ? to : from;
    return from == to ? from : '$from – $to';
  });
  if (last == null && mtd == null) return null;

  final approval = raw['approval'];
  String step(String key) =>
      approval is Map ? (approval[key]?.toString() ?? '') : '';
  return LighthouseDailyClose(
    lastDay: last ?? const LighthouseDailyCloseRow(scale: null, profit: null),
    monthToDate:
        mtd ?? const LighthouseDailyCloseRow(scale: null, profit: null),
    finance: lighthouseParseApprovalStep(step('finance')),
    business: lighthouseParseApprovalStep(step('business')),
    operation: lighthouseParseApprovalStep(step('operation')),
  );
}

/// `2026-09-01` → `9/1`。冻结列和明细里都放不下完整日期。
String lighthouseShortDate(dynamic raw) {
  final t = raw?.toString().trim() ?? '';
  final m = RegExp(r'^\d{4}-(\d{2})-(\d{2})').firstMatch(t);
  if (m == null) return t;
  final mm = int.tryParse(m.group(1)!) ?? 0;
  final dd = int.tryParse(m.group(2)!) ?? 0;
  if (mm == 0 || dd == 0) return t;
  return '$mm/$dd';
}

/// 规模这一列的表头。
///
/// 供给维百分之百按**核销额**确认，渠道维大部分按**销售额** —— 两个 tab 用同一个
/// 「规模」标签却取不同的数，看表的人不可能知道。所以标签写死，不用含糊词。
String lighthouseDailyScaleLabel(String tab) =>
    tab.trim() == 'supply' ? '核销额' : '销售额';

/// ── 银行余额日序列 ────────────────────────────────────────────────
///
/// 余额是存量，日间波动主要由付款批次决定，跟昨天比噪音大过信号。
/// 跟上月末比才对应「这个月账上是多了还是少了」，也和旁边的本月净TA 同一个窗口。
///
/// [dates] 与 [totals] 按日期升序一一对应，格式 `yyyy-MM-dd`。

/// 末点所在年月之前、最后一个点的余额 = 上月末。取不到返回 null。
double? lighthouseBankBalancePrevMonthEnd(
  List<String> dates,
  List<double> totals,
) {
  final n = dates.length < totals.length ? dates.length : totals.length;
  if (n < 2) return null;
  String monthOf(String date) {
    final t = date.trim();
    return t.length >= 7 ? t.substring(0, 7) : t;
  }

  final lastMonth = monthOf(dates[n - 1]);
  if (lastMonth.isEmpty) return null;
  for (var i = n - 2; i >= 0; i--) {
    final m = monthOf(dates[i]);
    if (m.isNotEmpty && m.compareTo(lastMonth) < 0) return totals[i];
  }
  return null;
}

/// 环比 = (末点 − 上月末) ÷ |上月末| × 100。
///
/// 上月末缺失或为 0 时返回 null —— 除以 0 得到的百分比没有意义，
/// 界面上这一行直接不渲染，不显示 0%。
/// 新接口请用 [lighthouseBankBalanceChangeFromPayload]：按日/周/月/季/年
/// 给出「涨了多少钱」，这条只在旧后端没下发 change 时兜底。
double? lighthouseBankBalanceMomPct(List<String> dates, List<double> totals) {
  final prev = lighthouseBankBalancePrevMonthEnd(dates, totals);
  if (prev == null || prev.abs() < 1e-9) return null;
  final n = dates.length < totals.length ? dates.length : totals.length;
  if (n < 2) return null;
  return (totals[n - 1] - prev) / prev.abs() * 100;
}

/// 银行余额这一期相对上一期期末涨了多少钱。
///
/// 存量比的是「账上多了还是少了」，不是把本期流水加总。
/// `amount` 是元；`vs` 是对照文案（vs 昨日 / 上周末 / 上月末 / 上季末 / 年初）。
class LighthouseBankBalanceChange {
  const LighthouseBankBalanceChange({
    required this.amount,
    required this.vs,
    this.pct,
  });

  final double amount;
  final String vs;
  final double? pct;
}

LighthouseBankBalanceChange? lighthouseBankBalanceChangeFromPayload(
  dynamic raw,
) {
  if (raw is! Map) return null;
  final amount = (raw['amount'] as num?)?.toDouble();
  final vs = raw['vs']?.toString().trim() ?? '';
  if (amount == null || vs.isEmpty) return null;
  final pct = (raw['pct'] as num?)?.toDouble();
  return LighthouseBankBalanceChange(amount: amount, vs: vs, pct: pct);
}

String lighthouseBankBalanceSeriesLabel(String raw) {
  final t = raw.trim();
  if (t.contains('Q')) return t.replaceAll('-', '.');
  final day = RegExp(r'^\d{4}-(\d{2})-(\d{2})$').firstMatch(t);
  if (day != null) return '${day.group(1)}.${day.group(2)}';
  final month = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(t);
  if (month != null) return '${month.group(1)}.${month.group(2)}';
  return t;
}

/// 银行余额走势线颜色。跟左侧存量卡同一支绿，不跟净TA 紫抢身份。
const int lighthouseStockAccentValue = 0xFF1E9E72;

/// 存量图例：用这一期时点，不许把近 N 期余额加总冒充「本期合计」。
double lighthouseTrendStockLegendValue({
  required List<double> series,
  double? periodStock,
}) {
  if (periodStock != null) return periodStock;
  return series.isEmpty ? 0.0 : series.last;
}

/// 把银行余额点对到净TA 图的横轴。缺的月份沿用上一期存量，不补 0。
List<double> lighthouseAlignSeriesToLabels({
  required List<String> axisLabels,
  required List<String> seriesLabels,
  required List<double> values,
}) {
  if (axisLabels.isEmpty) return const [];
  final n = seriesLabels.length < values.length
      ? seriesLabels.length
      : values.length;
  if (n <= 0) return List<double>.filled(axisLabels.length, 0);
  final byKey = <String, double>{};
  for (var i = 0; i < n; i++) {
    byKey[lighthouseHeroCompactPeriodLabel(
          lighthouseBankBalanceSeriesLabel(seriesLabels[i]),
        )] =
        values[i];
  }
  var matched = 0;
  double? last;
  final out = <double>[];
  for (final label in axisLabels) {
    final key = lighthouseHeroCompactPeriodLabel(
      lighthouseBankBalanceSeriesLabel(label),
    );
    final hit = byKey[key];
    if (hit != null) {
      last = hit;
      matched++;
      out.add(hit);
    } else {
      out.add(last ?? 0);
    }
  }
  if (matched == 0 && values.length == axisLabels.length) return values;
  return out;
}

/// 把 /net-ta 的 `bankBalance.companies` 摊成界面用的行。
///
/// 账户必须跟着走：合并时只留公司名和总额的话，展开箭头永远出不来。
List<Map<String, dynamic>> lighthouseNetTABankBalanceCompanies(dynamic list) {
  if (list is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final e in list.whereType<Map>()) {
    final name = e['company']?.toString().trim() ?? '';
    if (name.isEmpty) continue;
    final accounts = <Map<String, dynamic>>[];
    final rawAccounts = e['accounts'];
    if (rawAccounts is List) {
      for (final a in rawAccounts.whereType<Map>()) {
        final label = a['account']?.toString().trim() ?? '';
        if (label.isEmpty) continue;
        accounts.add({
          'account': label,
          'balance': (a['balance'] as num?)?.toDouble() ?? 0.0,
        });
      }
    }
    out.add({
      'company': name,
      'balance': (e['balance'] as num?)?.toDouble() ?? 0.0,
      'accounts': accounts,
    });
  }
  return out;
}

/// 资金池预览两格各自点开自己的面板：
/// 总资产金额 → 资金 / 券 / 期末预付款对账 / 资产；票税 · 应开 → 发票。
const lighthouseFundPoolPanelAssets = 'assets';
const lighthouseFundPoolPanelInvoice = 'invoice';

/// 预览格 key → 它点开的面板；不认识的 key 不展开。
String? lighthouseFundPoolPanelForPreviewKey(String key) {
  switch (key) {
    case 'totalAssets':
      return lighthouseFundPoolPanelAssets;
    case 'invoiceToIssue':
      return lighthouseFundPoolPanelInvoice;
  }
  return null;
}

/// 点同一格收起；点另一格直接换到那个面板。
String? lighthouseFundPoolPanelAfterTap(String? current, String tappedKey) {
  final panel = lighthouseFundPoolPanelForPreviewKey(tappedKey);
  if (panel == null) return current;
  return current == panel ? null : panel;
}

/// 展开面板底部的口径条。
///
/// 八个数里只有两个是「算出来的」——资产合计和系统差异，其余都是取数。
/// 这两条关系不写出来就只能靠猜，而且最容易猜错的是「应收资金」：它长在
/// 资金卡里，实际进的是系统差异那条，不进资产合计。
class LighthouseFundPoolFormula {
  const LighthouseFundPoolFormula({
    required this.kind,
    required this.resultKey,
    required this.result,
    required this.expression,
    required this.sourceKeys,
  });

  /// 取哪张卡的颜色 —— 口径条的配色跟着结果所在的卡走。
  final LighthouseFundPoolSectionKind kind;

  /// 结果格自己的 metric key，箭头挂在这一格上。
  final String resultKey;
  final String result;

  /// 用空格分词，运算符单独成词，方便按 token 分色。
  final String expression;

  /// 点箭头时要点亮的加数格，顺序与 [expression] 一致。
  final List<String> sourceKeys;
}

const lighthouseFundPoolFormulas = <LighthouseFundPoolFormula>[
  LighthouseFundPoolFormula(
    kind: LighthouseFundPoolSectionKind.assets,
    resultKey: 'totalAssets',
    result: '资产合计',
    expression: '现金·监管户 + 现金·在途 + 期末预付款余额',
    sourceKeys: [
      'regulatoryAccountBalance',
      'inTransitFunds',
      'endingPrepaymentBalance',
    ],
  ),
  LighthouseFundPoolFormula(
    kind: LighthouseFundPoolSectionKind.recon,
    resultKey: 'systemDifference',
    result: '系统差异',
    expression: '期末预付款余额 − 资金池可用 − 库存/同步券 − 应收资金',
    sourceKeys: [
      'endingPrepaymentBalance',
      'fundPoolBalance',
      'stockAndSyncVouchers',
      'endingReceivableRebate',
    ],
  ),
];

/// 这一格是不是「算出来的」—— 是就挂一个箭头，点开点亮它的加数。
LighthouseFundPoolFormula? lighthouseFundPoolFormulaForKey(String metricKey) {
  for (final f in lighthouseFundPoolFormulas) {
    if (f.resultKey == metricKey) return f;
  }
  return null;
}

/// 当前追溯的是哪条式子；`traced` 为空表示没点开。
bool lighthouseFundPoolMetricIsTraced(String? traced, String metricKey) {
  if (traced == null) return false;
  final formula = lighthouseFundPoolFormulaForKey(traced);
  if (formula == null) return false;
  return formula.sourceKeys.contains(metricKey);
}

/// 点同一个箭头收起；点另一个直接换过去。
String? lighthouseFundPoolTraceAfterTap(String? current, String tappedKey) {
  if (lighthouseFundPoolFormulaForKey(tappedKey) == null) return current;
  return current == tappedKey ? null : tappedKey;
}

/// 票税面板没有算式，三个数都是直接取的。
List<LighthouseFundPoolFormula> lighthouseFundPoolPanelFormulas(String panel) {
  if (panel == lighthouseFundPoolPanelInvoice) {
    return const <LighthouseFundPoolFormula>[];
  }
  return lighthouseFundPoolFormulas;
}

/// 展开区按面板取分区：票税只有发票块；总资产是资金 → 券 → 对账 → 资产。
List<LighthouseFundPoolRowSpec> lighthouseFundPoolPanelRows(String panel) {
  if (panel == lighthouseFundPoolPanelInvoice) {
    return const [LighthouseFundPoolRowSpec(lighthouseFundPoolInvoiceSection)];
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

/// 展开：发票与资产并列且发票在上；下面资金 → 券 → 对账。
/// showInvoice=false 仅留给单测对照旧日清四宫格。
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
