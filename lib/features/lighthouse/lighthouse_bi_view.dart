import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'lighthouse_hero_metric.dart';
import 'lighthouse_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 灯塔 · BI 视图 (v2 · 并入灯塔视觉体系)
//
//   入口：列表控制条「选区间」右侧的 BI 视图按钮 → 全屏 push。
//
//   v2 的全部工作是「不要看起来像另一个 App」。所有壳子级 token 直接引用
//   lighthouse_hero_metric.dart 里 Hero 已经定好的那套，一个都不新造：
//     · 卡片圆角          lighthouseHeroCardRadius (12)
//     · 分区图标块        lighthouseHeroSectionIconSize (18) + 圆角 5
//     · 分区四色          lighthouseHeroSectionAccentValues  紫/琥珀/绿/品红
//     · 分区淡底 / 描边 / 标题色
//       lighthouseHeroSectionTintValues / EdgeValues / TitleValues
//     · 指标格三段        标签 sans 9 · 数值 number 13 · 单位 sans 7.5 ·
//                        环比 mono 8，且沿用灯塔的涨红跌绿
//   紫（_LhPlum.primary）在这一页同样只做「线」和「字」，唯一的有色面是
//   顶部那张 hero 卡 —— 与主页 v14.1 的结论一致。
//
//   图表配色也不是另起炉灶：环形图那四个色就是 Hero 走势图的
//   紫 / 琥珀 / 绿 / 品红（lighthouseHeroSectionAccentValues 原值），
//   过了 CVD 校验（明度带 / 彩度下限 / 对比度全 PASS，相邻最差 ΔE 7.4
//   落在 6–8 带内 —— 图例每片都直标了名称和数值，二次编码到位）。
//   盈亏发散图用「紫 ↔ 珊瑚」双极而不是绿红：这个 App 里绿是「跌」和
//   「现金流」的语义色，拿它表示盈利会和格子里的 ↓ 环比撞含义。
// ═══════════════════════════════════════════════════════════════════════════

/// 与 native_lighthouse_page 的 `_LhPlum` 同值 —— 那个类是 page 私有的，
/// 这里镜像一份，改色时两处一起改。
abstract final class LhBiPlum {
  static const Color primary = Color(0xFF7B5CD8);
  static const Color deep = Color(0xFF5A458F);
  static const Color heroNum = Color(0xFF4A3A7A);
  static const Color lavender = Color(0xFFF0ECF6);
  static const Color mist = Color(0xFFF5F2FA);
  static const Color line = Color(0xFFE4DCF4);
  static const Color heroFill = Color(0xFFF7F3FC);
  static const Color heroEdge = Color(0xFFE2D8F0);
}

/// 分区 token 取用口 —— 全部转发到 Hero 已有的常量表，不新造值。
abstract final class LhBiSection {
  static Color accent(String key) =>
      Color(lighthouseHeroSectionAccentValues[key] ?? 0xFF7B5CD8);
  static Color tint(String key) =>
      Color(lighthouseHeroSectionTintValues[key] ?? 0xFFF6F3FD);
  static Color edge(String key) =>
      Color(lighthouseHeroSectionEdgeValues[key] ?? 0xFFDCD1F5);
  static Color title(String key) =>
      Color(lighthouseHeroSectionTitleValues[key] ?? 0xFF5B3FB0);

  static IconData icon(String key) => switch (key) {
    'scale' => Icons.show_chart_rounded,
    'cost' => Icons.receipt_long_rounded,
    'cash' => Icons.account_balance_wallet_outlined,
    _ => Icons.trending_up_rounded,
  };
}

/// 环形图分类槽 —— 与 Hero 走势图同一组四色，按序循环，不再折进「其他」。
abstract final class LhBiPalette {
  static const List<Color> cat = <Color>[
    Color(0xFF7B5CD8), // 紫 · scale
    Color(0xFFC4791C), // 琥珀 · cost
    Color(0xFF1E9E72), // 绿 · cash
    Color(0xFFB8478F), // 品红 · profit
  ];

  /// 旧「其他」聚合片仍用中性灰，避免跟真实实体抢色。
  static const Color other = Color(0xFF9A988E);

  /// 盈亏双极：暖冷对立 + 中性零点。绿留给「跌 / 现金流」。
  static const Color gain = Color(0xFF7B5CD8);
  static const Color loss = LhColors.neg;

  static Color slot(int i) => cat[i % cat.length];
}

/// 当前维要看清的另外三维。产品 / 供给 / 渠道 / 人效是同一套账本换分组键，
/// 点开任何一个实体，另外三个都该在这儿切得出来。
///
/// 净TA 给空：它是资金流水的五类映射，跟业务账本不同源也不同粒度，
/// 硬拆只会拆出看着像真的假数 —— 宁可不给，也不给编的。
const lhBiLedgerCrossDims = <({String key, String label})>[
  (key: 'product', label: '产品'),
  (key: 'supply', label: '供给'),
  (key: 'channel', label: '渠道'),
  (key: 'people', label: '人效'),
];

List<({String key, String label})> lhBiCrossDims(String dim) {
  if (dim == 'netTa') return const [];
  return [
    for (final d in lhBiLedgerCrossDims)
      if (d.key != dim) d,
  ];
}

/// BI 视图能选的一个指标。
@immutable
class LhBiMetric {
  const LhBiMetric({
    required this.key,
    required this.label,
    this.isRate = false,
  });

  final String key;
  final String label;
  final bool isRate;
}

/// 一个维度上的一条实体读数。
@immutable
class _BiItem {
  const _BiItem({
    required this.name,
    required this.value,
    required this.scale,
    required this.profit,
    this.group = '',
    this.delta,
    this.profitDelta,
  });

  final String name;

  /// 所属分类（能源 / 运营商 …），排行榜用它做二级标识。
  final String group;

  /// 当前指标的环比（%）。null = 后端没给同期对齐值。
  final double? delta;

  /// 净利环比（%）。
  final double? profitDelta;

  /// 当前选中指标的值。
  final double value;

  /// 规模口径的值（构成图用；选中指标是比率时，占比只能按规模算）。
  final double scale;

  /// 净利，构成图例亏损项和净TA 二级科目用。
  final double profit;
}

// ── 数字格式（与 Hero 同口径：数值和单位分开排，单位小一号且发灰）─────────

({String text, String unit}) lhBiParts(double v, {required bool isRate}) {
  if (isRate) return (text: v.toStringAsFixed(2), unit: '%');
  final abs = v.abs();
  if (abs >= 1e8) return (text: (v / 1e8).toStringAsFixed(2), unit: '亿');
  final wan = v / 1e4;
  if (wan == 0) return (text: '0', unit: '');
  if (wan.abs() >= 100) return (text: wan.toStringAsFixed(0), unit: '万');
  if (wan.abs() >= 1) return (text: wan.toStringAsFixed(1), unit: '万');
  return (text: wan.toStringAsFixed(2), unit: '万');
}

String lhBiMoney(double v) {
  final p = lhBiParts(v, isRate: false);
  return '${p.text}${p.unit}';
}

String lhBiLegendKey(String name, int index) => 'bi-legend-$index-$name';

/// BI 水平边距跟一级灯塔同一条竖直参考线，不能自己另起一套。
///
///   · 顶栏 16 —— 与 `_buildAppBar` 相同
///   · 日周月季年 22 —— 与 `_buildPanel` 期间条相同
///   · 图卡 12 —— 与 `_buildHeroShell` 非拍平版相同
const double lhBiChromePad = 16;
const double lhBiPeriodPad = 22;
const double lhBiCardPad = 12;

/// BI 切日周月后该拉哪一维：当前正在看的视角，没有就退回打开时那一维。
/// 不能用主列表 `_tab`：人在 BI 里已经切到渠道/人效/净TA 时，主列表可能还停在产品。
String lighthouseBiDimToLoad({
  required String? biDim,
  required String fallback,
}) {
  final dim = (biDim ?? '').trim();
  return dim.isEmpty ? fallback : dim;
}

/// 构成图圆心与 Hero 合计同口径：全部项带符号加总。
/// 环形只能画正值，亏损不入扇区，所以 [lhBiBuildCompositionSlices] 的加总
/// 可能比这个数大。
double lhBiSignedTotal(Iterable<double> values) {
  var total = 0.0;
  for (final value in values) {
    total += value;
  }
  return total;
}

/// 按名字加总某指标。构成图合同名合并，本日/本月新增也要同一套。
double? lhBiLookupNamedMetric(
  Iterable<Map<String, dynamic>> rows,
  String name,
  double Function(Map<String, dynamic> row) valueOf,
) {
  final want = name.trim();
  if (want.isEmpty) return null;
  var total = 0.0;
  var hit = false;
  for (final row in rows) {
    final n = row['name']?.toString().trim() ?? '';
    if (n != want) continue;
    total += valueOf(row);
    hit = true;
  }
  return hit ? total : null;
}

/// 构成图按名字合并规模。同名（常见是「未分类」）合成一片，避免图例撞 key。
/// 默认列出全部实体，不再把尾巴折进「其他 N 项」。
List<({String name, double value})> lhBiBuildCompositionSlices(
  Iterable<({String name, double scale})> items, {
  int? maxSlice,
}) {
  final merged = <String, double>{};
  for (final item in items) {
    if (item.scale <= 0) continue;
    final name = item.name.trim().isEmpty ? '未分类' : item.name.trim();
    merged[name] = (merged[name] ?? 0) + item.scale;
  }
  final ranked = merged.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (ranked.isEmpty) return const [];

  final limit = maxSlice ?? ranked.length;
  final slices = <({String name, double value})>[];
  for (var i = 0; i < ranked.length && i < limit; i++) {
    slices.add((name: ranked[i].key, value: ranked[i].value));
  }
  if (maxSlice != null && ranked.length > maxSlice) {
    final rest = ranked.skip(maxSlice).fold<double>(0, (s, e) => s + e.value);
    slices.add((name: '其他 ${ranked.length - maxSlice} 项', value: rest));
  }
  return slices;
}

String lhBiValue(double v, {required bool isRate}) {
  final p = lhBiParts(v, isRate: isRate);
  return '${p.text}${p.unit}';
}

String lhBiPct(double v) => '${v.toStringAsFixed(1)}%';

/// 轴刻度：只到「万 / 亿」，不带小数尾巴。
String lhBiTick(double v, {required bool isRate}) {
  if (isRate) return v.toStringAsFixed(0);
  final abs = v.abs();
  if (abs >= 1e8) return '${(v / 1e8).toStringAsFixed(1)}亿';
  if (abs >= 1e4) return '${(v / 1e4).toStringAsFixed(0)}万';
  if (abs == 0) return '0';
  return v.toStringAsFixed(0);
}

/// 环比文案 —— 沿用灯塔的涨红跌绿。
Color lhBiDeltaColor(double pct) => pct >= 0 ? LhColors.neg : LhColors.pos;

String lhBiDeltaText(double pct, {bool pp = false}) {
  final a = pct.abs();
  return '${pct >= 0 ? '↑' : '↓'}'
      '${a.toStringAsFixed(a >= 10 ? 0 : 1)}'
      '${pp ? 'pp' : '%'}';
}

// ── 画笔小工具 ──────────────────────────────────────────────────────────────

TextPainter _tp(
  String text,
  TextStyle style, {
  double maxWidth = double.infinity,
}) {
  final p = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  );
  p.layout(maxWidth: maxWidth);
  return p;
}

TextStyle _mono({
  double size = 9,
  Color color = LhColors.mute2,
  FontWeight weight = FontWeight.w600,
  double spacing = 0.2,
}) => LhTypography.mono(
  size: size,
  color: color,
  weight: weight,
  letterSpacing: spacing,
  height: 1.0,
);

TextStyle _sans({
  double size = 11,
  Color color = LhColors.ink,
  FontWeight weight = FontWeight.w600,
  double spacing = 0,
}) => LhTypography.sans(
  size: size,
  color: color,
  weight: weight,
  letterSpacing: spacing,
  height: 1.1,
);

// ═══════════════════════════════════════════════════════════════════════════
// 页面
// ═══════════════════════════════════════════════════════════════════════════

class LhBiViewPage extends StatefulWidget {
  const LhBiViewPage({
    super.key,
    required this.initialDim,
    this.dims,
    required this.initialMetric,
    required this.rangeLabel,
    required this.periodLabel,
    required this.rowsFor,
    required this.metricsFor,
    required this.metricValue,
    required this.dimLabel,
    required this.categoriesFor,
    required this.metricDelta,
    required this.breakdownFor,
    this.requestBreakdown,
    this.seriesFor,
    this.onDimChanged,
    this.onClose,
    this.topChrome,
    this.periodBar,
    this.loading = false,
    this.windowRowsFor,
  });

  /// 打开时停在哪个维度。
  final String initialDim;

  /// 顶部出哪几个视角。宿主按权限裁（没有净TA权限就不该出现净TA视角）。
  /// 不传则五个全出。
  final List<String>? dims;

  /// 打开时选中哪个指标（跟随主列表的排序字段）。
  final String initialMetric;

  /// 「09.01–09.08」这类区间文案，直接复用主页口径。
  final String rangeLabel;

  /// 「本月 · 2026.09」这类周期文案。
  final String periodLabel;

  final List<Map<String, dynamic>> Function(String dim) rowsFor;
  final List<LhBiMetric> Function(String dim) metricsFor;
  final double Function(Map<String, dynamic> row, String key) metricValue;
  final String Function(String dim) dimLabel;

  /// 该维度下的分类（能源 / 公共出行 / 运营商 / 未分类…），与主列表同一份。
  final List<String> Function(String dim) categoriesFor;

  /// 单行某指标的环比。返回 null = 后端没给同期对齐的值，显示「—」而不是编一个。
  final ({double pct, bool isUp})? Function(Map<String, dynamic> row, String key)
  metricDelta;

  /// 某个实体拆到交叉维（产品/供给/渠道）。[breakKey] 是要看的那一维。
  final ({String label, List<Map<String, dynamic>> rows}) Function(
    String dim,
    String name,
    String breakKey,
  )
  breakdownFor;

  /// 拆分数据要现取时调它（宿主去打详情接口），拿到后 setState 会自然刷新。
  final Future<void> Function(String dim, String name)? requestBreakdown;

  /// 宿主直供的期内序列。人效和净TA 的行上没有 trend：
  /// 人效的加总就是公司总量（人是账本的一种分组），净TA 的序列在 metrics 里，
  /// 都不是「把行上的 trend 逐位相加」能拼出来的，所以留一个口子给宿主直给。
  /// 返回 null 时退回按行 trend 相加的老路。
  final ({List<double> values, List<String> labels})? Function(
    String dim,
    String metricKey,
  )?
  seriesFor;

  /// 顶栏换维时通知宿主去拉该维列表（供给进 BI 也能看到产品/渠道）。
  final ValueChanged<String>? onDimChanged;

  /// 灯塔是 keep-alive 叠层，不能 Navigator.push。关页由宿主收。
  final VoidCallback? onClose;

  /// 二级页顶栏（退出 · 灯塔 · 工具）。有则替代本页自带 masthead。
  final Widget? topChrome;

  /// 与一级/二级同款的日周月季年条。切粒度由宿主改 period 再灌数。
  final Widget? periodBar;

  /// 当前视角还在拉数。空列表时显示同步中，而不是「没有数据」。
  final bool loading;

  /// 日历「今天 / 本月」的行，用来画构成图例的本日新增、本月新增。
  /// [window] 为 `day` 或 `month`。返回 null = 还没拉到，显示「—」。
  final List<Map<String, dynamic>>? Function(String dim, String window)?
      windowRowsFor;

  @override
  State<LhBiViewPage> createState() => _LhBiViewPageState();
}

class _LhBiViewPageState extends State<LhBiViewPage>
    with SingleTickerProviderStateMixin {
  /// 五个视角：账本三维 + 人效（账本按负责人分组）+ 净TA（资金流五类）。
  /// 前四个同源同口径、可互相拆；净TA 单独挂在最后，只看自己。
  static const List<String> kAllDims = <String>[
    'product',
    'supply',
    'channel',
    'people',
    'netTa',
  ];

  List<String> get _dims {
    final given = widget.dims;
    if (given == null || given.isEmpty) return kAllDims;
    final out = [for (final d in kAllDims) if (given.contains(d)) d];
    return out.isEmpty ? kAllDims : out;
  }

  bool get _isNetTa => _dim == 'netTa';

  late String _dim = _dims.contains(widget.initialDim)
      ? widget.initialDim
      : 'product';
  late String _metricKey = widget.initialMetric;
  late String _breakKey = _firstCrossKey(_dim);

  static String _firstCrossKey(String dim) {
    final crosses = lhBiCrossDims(dim);
    return crosses.isEmpty ? '' : crosses.first.key;
  }

  /// 分类筛选，与主列表的 _groupFilter 同语义。
  String _group = '全部';

  /// 当前展开省份拆分的实体名；null = 没展开。
  String? _drillName;
  bool _drillBusy = false;

  bool _showTable = false;

  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
  }

  @override
  void didUpdateWidget(LhBiViewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rangeLabel != widget.rangeLabel ||
        oldWidget.periodLabel != widget.periodLabel) {
      _anim
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  // ── 数据 ─────────────────────────────────────────────────────────────────

  List<LhBiMetric> get _metrics {
    final list = widget.metricsFor(_dim);
    if (list.isEmpty) {
      return const <LhBiMetric>[
        LhBiMetric(key: 'sales', label: '销售额'),
        LhBiMetric(key: 'profit', label: '净利润'),
      ];
    }
    return list;
  }

  LhBiMetric get _metric {
    final list = _metrics;
    for (final m in list) {
      if (m.key == _metricKey) return m;
    }
    return list.first;
  }

  /// 构成图用的规模口径：选中指标本身可加总就用它，是比率就退回销售额。
  String get _scaleKey => _metric.isRate ? 'sales' : _metric.key;

  /// 分类条：全部 + 该维度真实存在的分类。只有一个分类时不值得占一行。
  List<String> get _categories {
    final raw = widget.categoriesFor(_dim);
    final out = <String>['全部'];
    for (final c in raw) {
      final t = c.trim();
      if (t.isEmpty || t == '全部' || out.contains(t)) continue;
      out.add(t);
    }
    return out.length <= 2 ? const <String>[] : out;
  }

  List<_BiItem> get _items {
    final rows = widget.rowsFor(_dim);
    final out = <_BiItem>[];
    for (final r in rows) {
      final name = r['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final group = r['group']?.toString().trim() ?? '';
      if (_group != '全部' && group != _group) continue;
      final value = widget.metricValue(r, _metric.key);
      final scale = widget.metricValue(r, _scaleKey);
      out.add(
        _BiItem(
          name: name,
          group: group,
          value: value,
          // 净TA 五类里三类天然为负；构成图只吃正值，直接用净额会把流出侧
          // 整片吞掉，只剩两片。取绝对值 → 环形读作「资金在这五类里怎么流动」。
          scale: _isNetTa ? scale.abs() : scale,
          // 净TA 没有 profit 字段，它的「盈亏」就是净额本身。
          profit: _isNetTa
              ? ((r['netTa'] as num?)?.toDouble() ?? value)
              : ((r['profit'] as num?)?.toDouble() ?? 0),
          delta: widget.metricDelta(r, _metric.key)?.pct,
          profitDelta: widget.metricDelta(r, _isNetTa ? 'netTa' : 'profit')?.pct,
        ),
      );
    }
    return out;
  }

  /// 点构成图的扇区 → 展开该项的交叉维拆分；再点一次收起。
  Future<void> _toggleDrill(String name) async {
    // 净TA 没有交叉维，点扇区不该进入一个永远空着的下钻面板。
    if (lhBiCrossDims(_dim).isEmpty) return;
    HapticFeedback.selectionClick();
    if (_drillName == name) {
      setState(() => _drillName = null);
      return;
    }
    setState(() {
      _drillName = name;
      _drillBusy = true;
    });
    final req = widget.requestBreakdown;
    if (req != null) {
      try {
        await req(_dim, name);
      } catch (_) {
        // 取不到就退回「暂无拆分」文案，不打断整页。
      }
    }
    if (!mounted) return;
    setState(() => _drillBusy = false);
  }

  void _pick(void Function() mutate) {
    HapticFeedback.selectionClick();
    final prevDim = _dim;
    setState(() {
      mutate();
      // 换了口径，上一个实体的交叉拆分就不再是同一件事了。
      _drillName = null;
      _drillBusy = false;
      if (_dim != prevDim) {
        _breakKey = _firstCrossKey(_dim);
        // 分类是「上一个视角的分类」——净TA 根本没有分类条，人效的板块也未必
        // 和供给的分类同名。带着旧值切过去会把整页筛成空，且没有控件能改回来。
        if (_group != '全部' && !_categories.contains(_group)) {
          _group = '全部';
        }
      }
    });
    if (_dim != prevDim) widget.onDimChanged?.call(_dim);
    _anim
      ..reset()
      ..forward();
  }

  void _pickBreak(String key) {
    if (key == _breakKey) return;
    HapticFeedback.selectionClick();
    setState(() => _breakKey = key);
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final items = _items;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _masthead(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              lhBiCardPad,
              10,
              lhBiCardPad,
              40,
            ),
            physics: const BouncingScrollPhysics(),
            children: [
                  _controlCard(),
                  const SizedBox(height: lighthouseHeroCardGap),
                  if (items.isEmpty)
                    widget.loading ? _loadingCard() : _emptyCard()
                  // 净TA 走自己那套仪表：它问的是「钱怎么流的」，
                  // 不是「谁占多少份额」，套账本那四张图只会越看越糊。
                  else if (_isNetTa) ...[
                    ..._netTaCards(items),
                  ] else ...[
                    _heroCard(items),
                    const SizedBox(height: lighthouseHeroCardGap),
                    _statRow(items),
                    const SizedBox(height: lighthouseHeroCardGap),
                    _compositionCard(items),
                    if (_showTable) ...[
                      const SizedBox(height: lighthouseHeroCardGap),
                      _tableCard(items),
                    ],
                  ],
                  const SizedBox(height: 14),
                  _footnote(),
            ],
          ),
        ),
      ],
    );
    // 挂在一级页里时外面已经有 SafeArea。独立打开才自己垫。
    return Scaffold(
      backgroundColor: LhColors.mist,
      body: widget.topChrome == null
          ? SafeArea(bottom: false, child: body)
          : body,
    );
  }

  // ── 顶栏：有宿主 chrome 时跟 L2 一样（退出 · 灯塔 · 日周月季年）────────

  Widget _masthead() {
    final chrome = widget.topChrome;
    if (chrome != null) {
      return ColoredBox(
        color: LhColors.paper,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            chrome,
            if (widget.periodBar != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  lhBiPeriodPad,
                  0,
                  lhBiPeriodPad,
                  10,
                ),
                child: widget.periodBar!,
              ),
            const ColoredBox(
              color: LhColors.line2,
              child: SizedBox(height: 0.5),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 11),
      decoration: const BoxDecoration(
        color: LhColors.paper,
        border: Border(
          bottom: BorderSide(color: LhColors.line2, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            'BI 视图',
            style: LhTypography.sans(
              size: 17,
              color: LhBiPlum.primary,
              weight: FontWeight.w800,
              letterSpacing: 0.4,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 7),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'ANALYTICS',
              style: _mono(size: 8.5, color: LhColors.mute2, spacing: 1.5),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: _rangePill(),
            ),
          ),
          const SizedBox(width: 8),
          _roundIcon(
            icon: _showTable
                ? Icons.bar_chart_rounded
                : Icons.table_rows_rounded,
            active: _showTable,
            onTap: () => setState(() => _showTable = !_showTable),
          ),
          const SizedBox(width: 6),
          _roundIcon(
            icon: Icons.close_rounded,
            active: false,
            onTap: () {
              if (widget.onClose != null) {
                widget.onClose!();
                return;
              }
              Navigator.of(context).maybePop();
            },
          ),
        ],
      ),
    );
  }

  Widget _rangePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: LhBiPlum.lavender,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: LhBiPlum.heroEdge, width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: LhBiPlum.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              widget.rangeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _mono(size: 9.5, color: LhBiPlum.deep, spacing: 0.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableToggle() => _roundIcon(
    icon: _showTable ? Icons.bar_chart_rounded : Icons.table_rows_rounded,
    active: _showTable,
    onTap: () => setState(() => _showTable = !_showTable),
  );

  Widget _roundIcon({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: active ? LhBiPlum.mist : LhColors.paper,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: active ? LhBiPlum.primary : LhColors.line2,
            width: active ? 1 : 0.7,
          ),
        ),
        child: Icon(
          icon,
          size: 15,
          color: active ? LhBiPlum.primary : LhColors.mute,
        ),
      ),
    );
  }

  // ── 唯一的一条筛选条：维度 + 指标（与「日 周 月 季 年」同款） ────────────

  Widget _controlCard() {
    return Container(
      decoration: BoxDecoration(
        color: LhColors.paper,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: LhColors.line2, width: 0.7),
      ),
      padding: EdgeInsets.fromLTRB(6, 6, 6, _isNetTa ? 6 : 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final d in _dims) Expanded(child: _dimCell(d)),
              if (_isNetTa) ...[
                const SizedBox(width: 4),
                _tableToggle(),
              ],
            ],
          ),
          // 净TA 之下没有分类条也没有指标条，那条分隔线就没有东西可分隔了。
          if (_categories.isNotEmpty || !_isNetTa) ...[
            const SizedBox(height: 7),
            Container(height: 0.5, color: LhColors.line2),
          ],
          if (_categories.isNotEmpty) ...[
            const SizedBox(height: 8),
            _chipRow('分类', [
              for (final c in _categories) ...[
                _pillChip(
                  label: c,
                  on: c == _group,
                  onTap: () => _pick(() => _group = c),
                ),
                const SizedBox(width: 6),
              ],
            ]),
            const SizedBox(height: 7),
            Container(height: 0.5, color: LhColors.line2),
          ],
          // 净TA 不出指标条：净额 / 流入 / 流出 在 hero 上一次给全，
          // 让人在三个读数之间来回点，本身就是分析效率的损耗。
          if (!_isNetTa) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _chipRow('指标', [
                    for (final m in _metrics) ...[
                      _pillChip(
                        label: m.label,
                        on: m.key == _metric.key,
                        onTap: () => _pick(() => _metricKey = m.key),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ]),
                ),
                _tableToggle(),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 一条横滚的 chip 行：左边一个 mono 小标，右边一串药丸。
  Widget _chipRow(String label, List<Widget> chips) {
    return SizedBox(
      height: 25,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8, left: 2),
              child: Text(label, style: _mono(size: 9, spacing: 0.6)),
            ),
          ),
          ...chips,
        ],
      ),
    );
  }

  Widget _dimCell(String dim) {
    final on = dim == _dim;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: on ? null : () => _pick(() => _dim = dim),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: on ? LhBiPlum.lavender : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (on) ...[
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: LhBiPlum.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              widget.dimLabel(dim),
              style: _sans(
                size: 12.5,
                color: on ? LhBiPlum.deep : LhColors.mute,
                weight: on ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 下钻维度切换 —— 一条等分分段控件。
  ///
  /// 原来是一排药丸挤在 Wrap 里：没有高度约束，行高塌到文字本身，
  /// 点击区只有十来个像素，手指够不着。分段控件把整条宽度等分给每一维，
  /// 每格 36 高、整格可点 —— 这是这一页上唯一需要反复点的控件，
  /// 它的命中区不该是全页最小的那个。
  Widget _breakSegment(
    List<({String key, String label})> crosses,
    String breakKey,
  ) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: LhColors.paper,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: LhColors.line2, width: 0.7),
      ),
      child: Row(
        children: [
          for (final c in crosses)
            Expanded(
              child: KeyedSubtree(
                key: ValueKey('bi-break-${c.key}'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: c.key == breakKey ? null : () => _pickBreak(c.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.key == breakKey
                          ? LhBiPlum.lavender
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: c.key == breakKey
                            ? LhBiPlum.primary
                            : Colors.transparent,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      c.label,
                      style: _sans(
                        size: 11.5,
                        color: c.key == breakKey
                            ? LhBiPlum.deep
                            : LhColors.mute,
                        weight: c.key == breakKey
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pillChip({
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: on ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? LhBiPlum.mist : LhColors.paper,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: on ? LhBiPlum.primary : LhColors.line2,
            width: on ? 1 : 0.7,
          ),
        ),
        child: Text(
          label,
          style: _sans(
            size: 11,
            color: on ? LhBiPlum.deep : LhColors.ink2,
            weight: on ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ── Hero 卡：全页唯一一块有色面 ──────────────────────────────────────────

  Widget _heroCard(List<_BiItem> items) {
    final total = items.fold<double>(0, (s, e) => s + e.value);
    final headline = _metric.isRate
        ? (items.isEmpty ? 0.0 : total / items.length)
        : total;
    final parts = lhBiParts(headline, isRate: _metric.isRate);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: LhBiPlum.heroFill,
        borderRadius: BorderRadius.circular(lighthouseHeroCardRadius),
        border: Border.all(color: LhBiPlum.heroEdge, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: lighthouseHeroMastheadLabelIconSize,
                height: lighthouseHeroMastheadLabelIconSize,
                decoration: BoxDecoration(
                  color: LhBiPlum.primary,
                  borderRadius: BorderRadius.circular(
                    lighthouseHeroMastheadLabelRadius,
                  ),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  size: 11,
                  color: LhColors.paper,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: LhScrollText(
                  '${widget.dimLabel(_dim)} · ${_metric.label}'
                  '${_metric.isRate ? ' 均值' : ' 合计'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(
                    size: lighthouseHeroMastheadLabelFontSize,
                    color: LhColors.ink,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                parts.text,
                style: LhTypography.number(size: 30, color: LhBiPlum.heroNum),
              ),
              if (parts.unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    parts.unit,
                    style: _sans(
                      size: 11,
                      color: LhColors.mute,
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 9),
          Text(
            // 「前三名占规模」原来挤在这一行，现在是下面的「集中度」磁贴，
            // 同一个数不在两处出现。
            '共 ${items.length} 项 · ${widget.periodLabel}',
            style: _mono(size: 9.5, color: LhColors.mute, spacing: 0.1),
          ),
        ],
      ),
    );
  }

  /// Hero 下面的三张磁贴。
  ///
  /// 上一版的毛病是三张贴子只讲了一件半事：
  ///   · 「头名」把答案（叫什么）排成小灰字，把 0.85万 排成大字 —— 问的是谁，
  ///     答的是多少，主语和宾语调了个个儿
  ///   · 「盈利面 8/10 项 · 80%」上下两行是同一个事实说两遍
  ///   · 「亏损面 2/10 项 · 2 项」也说两遍，而且大字给了「几项」——
  ///     亏损真正要看的是亏了多少钱，不是亏了几项
  ///   · 盈利面和亏损面互为补集（8 和 2），两张贴子占着一件事
  ///
  /// 这一版三张贴子问三件不同的事：谁最大 · 有多集中 · 亏了多少。
  /// 大字一律给答案，小字给旁证。头名和集中度都从构成图那套切片算，
  /// 和下面的环形图逐字对得上，不会出现「贴子说 0.85万、图上写 0.81万」。
  Widget _statRow(List<_BiItem> items) {
    final built = lhBiBuildCompositionSlices(
      items.map((e) => (name: e.name, scale: e.scale)),
    );
    final sliceTotal = built.fold<double>(0, (s, e) => s + e.value);
    final top = built.isEmpty ? null : built.first;
    final topPct = (top != null && sliceTotal > 0)
        ? top.value / sliceTotal * 100
        : null;
    final cr3 = built.take(3).fold<double>(0, (s, e) => s + e.value);
    final concentration = sliceTotal > 0 ? cr3 / sliceTotal * 100 : null;
    final headCount = math.min(3, built.length);

    final losers = items.where((e) => e.profit < 0).toList();
    final lossSum = losers.fold<double>(0, (s, e) => s + e.profit);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _sectionTile(
            sectionKey: 'scale',
            title: '头名',
            icon: Icons.leaderboard_rounded,
            // 问「谁最大」，大字就得是名字。数字退到上面一行当旁证。
            caption: top == null
                ? '—'
                : '${lhBiValue(top.value, isRate: false)}'
                      '${topPct == null ? '' : ' · 占 ${lhBiPct(topPct)}'}',
            nameHeadline: top?.name ?? '—',
          ),
        ),
        const SizedBox(width: lighthouseHeroCardGap),
        Expanded(
          child: _sectionTile(
            sectionKey: 'profit',
            title: '集中度',
            icon: Icons.donut_small_rounded,
            caption: _isNetTa ? '前 $headCount 类占资金' : '前 $headCount 名占规模',
            headline: concentration == null
                ? (text: '—', unit: '')
                : (text: concentration.toStringAsFixed(1), unit: '%'),
          ),
        ),
        const SizedBox(width: lighthouseHeroCardGap),
        Expanded(
          child: _sectionTile(
            sectionKey: 'cost',
            title: _isNetTa ? '流出面' : '亏损面',
            icon: Icons.trending_down_rounded,
            // 大字给金额、小字给项数 —— 「亏了多少」比「亏了几项」重要得多。
            caption: losers.isEmpty
                ? (_isNetTa ? '本期无流出项' : '本期无亏损项')
                : '${losers.length} / ${items.length} 项'
                      '${_isNetTa ? '为负' : '在亏'}',
            headline: losers.isEmpty
                ? (text: '0', unit: '')
                : lhBiParts(lossSum, isRate: false),
            headlineColor: losers.isEmpty ? null : LhColors.neg,
          ),
        ),
      ],
    );
  }

  Widget _sectionTile({
    required String sectionKey,
    required String title,
    required String caption,
    ({String text, String unit})? headline,
    // 大字是一个名字而不是一个数（头名贴用）。走 sans、不走等宽数字。
    String? nameHeadline,
    Color? headlineColor,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 9, 8, 10),
      decoration: BoxDecoration(
        color: LhBiSection.tint(sectionKey),
        borderRadius: BorderRadius.circular(lighthouseHeroCardRadius),
        border: Border.all(color: LhBiSection.edge(sectionKey), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _sectionHeader(sectionKey, title, icon: icon),
          const SizedBox(height: 9),
          LhScrollText(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _sans(
              size: lighthouseHeroMetricLabelFontSize,
              color: LhColors.mute,
              weight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          if (nameHeadline != null)
            LhScrollText(
              nameHeadline,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _sans(
                size: lighthouseHeroMetricValueFontSize - 1,
                color: headlineColor ?? LhColors.ink,
                weight: FontWeight.w700,
              ),
            )
          else if (headline != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: LhScrollText(
                    headline.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LhTypography.number(
                      size: lighthouseHeroMetricValueFontSize + 2,
                      color: headlineColor ?? LhColors.ink,
                    ),
                  ),
                ),
                if (headline.unit.isNotEmpty) ...[
                  const SizedBox(width: 1),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      headline.unit,
                      style: _sans(
                        size: 8,
                        color: LhColors.mute,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String sectionKey, String title, {IconData? icon}) {
    return Row(
      children: [
        Container(
          width: lighthouseHeroSectionIconSize,
          height: lighthouseHeroSectionIconSize,
          decoration: BoxDecoration(
            color: LhBiSection.accent(sectionKey),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(
            // 磁贴问的不是账本分区，是「谁最大 / 多集中 / 亏多少」，
            // 图标跟着问题走，不跟着底色走。
            icon ?? LhBiSection.icon(sectionKey),
            size: 10.5,
            color: LhColors.paper,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: LhScrollText(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: LhTypography.sans(
              size: lighthouseHeroGroupTitleFontSize,
              color: LhBiSection.title(sectionKey),
              weight: FontWeight.w700,
              letterSpacing: 0.2,
              height: 1.0,
            ),
          ),
        ),
      ],
    );
  }

  // ── 图卡外壳：白卡 + 分区图标 + 分区淡底结论条 ───────────────────────────

  Widget _chartCard({
    required String sectionKey,
    required String title,
    required String subtitle,
    required Widget child,
    String? insight,
  }) {
    final radius = BorderRadius.circular(lighthouseHeroCardRadius);
    return Container(
      decoration: BoxDecoration(
        color: LhColors.paper,
        borderRadius: radius,
        border: Border.all(color: LhColors.line2, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(
              children: [
                Container(
                  width: lighthouseHeroSectionIconSize,
                  height: lighthouseHeroSectionIconSize,
                  decoration: BoxDecoration(
                    color: LhBiSection.accent(sectionKey),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(
                    LhBiSection.icon(sectionKey),
                    size: 10.5,
                    color: LhColors.paper,
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _sans(
                      size: 12.5,
                      color: LhColors.ink,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LhScrollText(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: _mono(size: 9, spacing: 0.1),
                  ),
                ),
              ],
            ),
          ),
          child,
          if (insight != null) ...[
            // 分隔线单独一根，不挂在下面那块的 decoration 上。
            //
            //   Border(top: ...) 是「非 uniform border」，Flutter 的 Border.paint
            //   对它断言 borderRadius == null —— 两者写在同一个 BoxDecoration 里，
            //   build 能过，paint 一定抛。整张 BI 页四张图卡都吃这个结论，
            //   于是页面开得出来却什么都画不出来，看上去就是「打不开」。
            Container(height: 0.6, color: LhBiSection.edge(sectionKey)),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
              decoration: BoxDecoration(
                color: LhBiSection.tint(sectionKey),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(lighthouseHeroCardRadius),
                  bottomRight: Radius.circular(lighthouseHeroCardRadius),
                ),
              ),
              child: Text(
                insight,
                style: _mono(
                  size: 9.5,
                  color: LhBiSection.title(sectionKey),
                  weight: FontWeight.w500,
                  spacing: 0.1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 图 1 · 构成环形图 ────────────────────────────────────────────────────

  Widget _compositionCard(List<_BiItem> items) {
    final built = lhBiBuildCompositionSlices(
      items.map((e) => (name: e.name, scale: e.scale)),
    );
    if (built.isEmpty) {
      return _chartCard(
        sectionKey: 'scale',
        title: '维度构成',
        subtitle: '无正值数据',
        child: _noData('当前口径下没有可拆分的正值，构成图不显示。'),
      );
    }

    final slices = <_Slice>[
      for (var i = 0; i < built.length; i++)
        _Slice(
          name: built[i].name,
          value: built[i].value,
          color: built[i].name.startsWith('其他 ')
              ? LhBiPalette.other
              : LhBiPalette.slot(i),
        ),
    ];
    final ringTotal = slices.fold<double>(0, (s, e) => s + e.value);
    // 净TA / 比率：环就是规模。可加总指标：圆心跟 Hero 合计一样，带上亏损。
    final centerTotal = (_isNetTa || _metric.isRate)
        ? ringTotal
        : lhBiSignedTotal(items.map((e) => e.value));
    final lossItems = (_isNetTa || _metric.isRate)
        ? const <_BiItem>[]
        : items.where((e) => e.value < 0).toList();
    final lossSum = lhBiSignedTotal(lossItems.map((e) => e.value));

    final top = slices.first;
    final topPct = ringTotal > 0 ? top.value / ringTotal * 100 : 0.0;
    final scaleLabel = _metric.isRate ? '销售额' : _metric.label;

    return _chartCard(
      sectionKey: 'scale',
      title: '${widget.dimLabel(_dim)}构成',
      subtitle: _isNetTa
          ? '按净额绝对值 · ${items.length} 类'
          : (_metric.isRate
                ? '比率不可加总 · 按销售额拆'
                : '按$scaleLabel · ${items.length} 项'),
      insight:
          '头部「${top.name}」占 ${lhBiPct(topPct)}'
          '${slices.length > 1 ? '，前 ${math.min(3, slices.length)} 名合计 ${lhBiPct(_headPct(slices, ringTotal, 3))}' : ''}。',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              // 214 而不是 172 —— 环本身没变大多少，多出来的是上下两侧
              // 给引线标注让的行位，头部三片各占一行。
              height: 214,
              child: LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _hitDonut(
                    d.localPosition,
                    Size(box.maxWidth, box.maxHeight),
                    slices,
                    ringTotal,
                  ),
                  child: AnimatedBuilder(
                    animation: _anim,
                    builder: (_, _) => CustomPaint(
                      painter: _DonutPainter(
                        slices: slices,
                        total: ringTotal,
                        progress: Curves.easeOutCubic.transform(_anim.value),
                        centerLabel: scaleLabel,
                        centerParts: lhBiParts(centerTotal, isRate: false),
                        selected: _drillName,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
            if (lhBiCrossDims(_dim).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '点扇区或下面任一行，看它拆到'
                '${lhBiCrossDims(_dim).map((e) => e.label).join(' / ')}',
                textAlign: TextAlign.center,
                style: _mono(size: 8.5, color: LhColors.mute2, spacing: 0.2),
              ),
            ],
            const SizedBox(height: 10),
            if (_showsWindowIncrements || slices.isNotEmpty)
              _legendHeader(),
            for (var i = 0; i < slices.length; i++)
              _legendRow(slices[i], ringTotal, i),
            if (lossItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 2, right: 2),
                child: Text(
                  '另有 ${lossItems.length} 项亏损 ${lhBiMoney(lossSum)}，已计入圆心合计',
                  style: _mono(size: 9, color: LhColors.pos, spacing: 0.1),
                ),
              ),
            if (_showsWindowIncrements) ...[
              const SizedBox(height: 10),
              _windowTotalsRow(items),
            ],
            _drillPanel(),
          ],
        ),
      ),
    );
  }

  /// 扇区命中：把点击位置换成极角，再沿累计角度找出落在哪一片。
  /// 圆心那块（半径小于内圈）不算命中 —— 那里是总量读数，不是数据区。
  void _hitDonut(Offset p, Size size, List<_Slice> slices, double total) {
    if (total <= 0 || slices.isEmpty) return;
    final g = lhBiDonutGeom(size);
    final center = g.center;
    final outer = g.r + g.stroke / 2;
    if (g.r <= 8) return;
    final stroke = g.stroke;
    final v = p - center;
    final dist = v.distance;
    // 弹出的那片会超出外缘 6px，热区跟着放宽，不然选中之后反而点不掉。
    if (dist < outer - stroke - 6 || dist > outer + 8) return;
    // atan2 以三点钟为 0、逆时针为负；环从十二点开始顺时针画，换算成同一起点。
    var a = math.atan2(v.dy, v.dx) + math.pi / 2;
    if (a < 0) a += math.pi * 2;
    var acc = 0.0;
    for (final s in slices) {
      final sweep = (s.value / total) * math.pi * 2;
      if (a >= acc && a < acc + sweep) {
        if (s.color == LhBiPalette.other) return; // 「其他」是聚合，没有实体可钻
        _toggleDrill(s.name);
        return;
      }
      acc += sweep;
    }
  }

  /// 下钻面板：某个实体拆到另外三维（产品↔供给↔渠道↔人效）。
  Widget _drillPanel() {
    final name = _drillName;
    if (name == null) return const SizedBox.shrink();

    final crosses = lhBiCrossDims(_dim);
    if (crosses.isEmpty) return const SizedBox.shrink();
    final breakKey = crosses.any((e) => e.key == _breakKey)
        ? _breakKey
        : crosses.first.key;
    final b = widget.breakdownFor(_dim, name, breakKey);
    final rows = <_BiItem>[];
    for (final r in b.rows) {
      final n = r['name']?.toString().trim() ?? '';
      if (n.isEmpty) continue;
      rows.add(
        _BiItem(
          name: n,
          value: widget.metricValue(r, _metric.key),
          scale: widget.metricValue(r, _scaleKey),
          profit: (r['profit'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
    rows.sort((a, c) => c.value.abs().compareTo(a.value.abs()));
    final shown = rows.take(12).toList();
    final maxAbs = shown.fold<double>(
      0,
      (m, e) => math.max(m, e.value.abs()),
    );

    Widget body;
    if (_drillBusy && shown.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            '正在取${b.label}明细…',
            style: _mono(size: 9.5, color: LhColors.mute2),
          ),
        ),
      );
    } else if (shown.isEmpty || maxAbs <= 0) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '「$name」在当前区间没有${b.label}拆分数据。\n'
          '后端 detail 未下发该维度时这里就是空的，不做估算。',
          style: _mono(size: 9.5, color: LhColors.mute2, spacing: 0.1),
        ),
      );
    } else {
      body = SizedBox(
        height: shown.length * 26.0 + 20,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, _) => CustomPaint(
            painter: _RankBarPainter(
              items: shown,
              maxAbs: maxAbs,
              isRate: _metric.isRate,
              progress: Curves.easeOutCubic.transform(_anim.value),
              rowHeight: 26,
            ),
            size: Size.infinite,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: LhBiPlum.mist,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LhBiPlum.heroEdge, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(width: 2, height: 10, color: LhBiPlum.primary),
              const SizedBox(width: 6),
              Flexible(
                child: LhScrollText(
                  '$name · ${b.label}分布',
                  key: ValueKey('bi-drill-$name-$breakKey'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _sans(
                    size: 11,
                    color: LhBiPlum.deep,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _metric.label,
                style: _mono(size: 8.5, color: LhColors.mute2),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _drillName = null),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: LhColors.mute2,
                ),
              ),
            ],
          ),
          if (crosses.length > 1) ...[
            const SizedBox(height: 8),
            _breakSegment(crosses, breakKey),
          ],
          const SizedBox(height: 8),
          body,
          if (shown.length < rows.length)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '共 ${rows.length} 个${b.label}，按 ${_metric.label} 取前 ${shown.length} 个',
                style: _mono(size: 8.5, color: LhColors.mute2),
              ),
            ),
        ],
      ),
    );
  }

  double _headPct(List<_Slice> slices, double total, int n) {
    if (total <= 0) return 0;
    var acc = 0.0;
    for (var i = 0; i < slices.length && i < n; i++) {
      acc += slices[i].value;
    }
    return acc / total * 100;
  }

  bool get _showsWindowIncrements =>
      widget.windowRowsFor != null && !_metric.isRate;

  static const double _legendValueW = 48;
  static const double _legendPctW = 40;
  static const double _legendWinW = 52;
  static const double _legendChevronW = 16;
  static const double _legendSwatchW = 17;

  double? _windowMetric(String name, String window) {
    final rows = widget.windowRowsFor?.call(_dim, window);
    if (rows == null) return null;
    return lhBiLookupNamedMetric(
          rows,
          name,
          (row) => widget.metricValue(row, _metric.key),
        ) ??
        0;
  }

  double? _windowSum(Iterable<String> names, String window) {
    if (widget.windowRowsFor?.call(_dim, window) == null) return null;
    var sum = 0.0;
    for (final name in names) {
      sum += _windowMetric(name, window) ?? 0;
    }
    return sum;
  }

  String get _legendValueLabel {
    switch (_metric.key) {
      case 'profit':
      case 'netProfit':
        return '利润';
      default:
        return _metric.label;
    }
  }

  Widget _legendNumCell(double width, String text, {Color? color, double size = 10}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _mono(size: size, color: color ?? LhColors.ink, spacing: 0),
      ),
    );
  }

  Widget _legendNumericCols({
    required String value,
    required String pct,
    String? day,
    String? month,
    double size = 10,
  }) {
    final windows = _showsWindowIncrements;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _legendNumCell(_legendValueW, value, size: size),
        _legendNumCell(_legendPctW, pct, color: LhColors.mute, size: size),
        if (windows) ...[
          _legendNumCell(_legendWinW, day ?? '—', size: size),
          _legendNumCell(_legendWinW, month ?? '—', size: size),
        ],
      ],
    );
  }

  Widget _legendHeader() {
    final windows = _showsWindowIncrements;
    TextStyle headStyle() => _mono(size: 8, color: LhColors.mute2, spacing: 0);
    Widget head(double w, String t) => SizedBox(
      width: w,
      child: Text(
        t,
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: headStyle(),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
      child: Row(
        children: [
          const SizedBox(width: _legendSwatchW),
          const Expanded(child: SizedBox.shrink()),
          head(_legendValueW, _legendValueLabel),
          head(_legendPctW, '占比'),
          if (windows) ...[
            head(_legendWinW, '本日新增'),
            head(_legendWinW, '本月新增'),
          ],
          const SizedBox(width: _legendChevronW),
        ],
      ),
    );
  }

  Widget _windowTotalsRow(List<_BiItem> items) {
    final names = items.map((e) => e.name);
    final day = _windowSum(names, 'day');
    final month = _windowSum(names, 'month');
    final total = lhBiSignedTotal(items.map((e) => e.value));
    return Column(
      children: [
        Container(height: 0.7, color: LhColors.line2),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
          child: Row(
            children: [
              const SizedBox(width: _legendSwatchW),
              Expanded(
                child: Text(
                  '合计',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(size: 9.5, color: LhColors.mute, spacing: 0.1),
                ),
              ),
              _legendNumericCols(
                value: lhBiMoney(total),
                pct: '',
                day: day == null ? '—' : lhBiMoney(day),
                month: month == null ? '—' : lhBiMoney(month),
              ),
              const SizedBox(width: _legendChevronW),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendRow(_Slice s, double total, int index) {
    final pct = total > 0 ? s.value / total * 100 : 0.0;
    final drillable = s.color != LhBiPalette.other;
    final on = drillable && _drillName == s.name;
    final day = _showsWindowIncrements ? _windowMetric(s.name, 'day') : null;
    final month = _showsWindowIncrements ? _windowMetric(s.name, 'month') : null;
    return GestureDetector(
      key: ValueKey(lhBiLegendKey(s.name, index)),
      behavior: HitTestBehavior.opaque,
      onTap: drillable ? () => _toggleDrill(s.name) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
        decoration: BoxDecoration(
          color: on ? LhBiPlum.lavender : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: s.color,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LhScrollText(
                s.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _sans(
                  size: 11,
                  color: LhColors.ink2,
                  weight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            _legendNumericCols(
              value: lhBiMoney(s.value),
              pct: lhBiPct(pct),
              day: day == null ? null : lhBiMoney(day),
              month: month == null ? null : lhBiMoney(month),
            ),
            SizedBox(
              width: _legendChevronW,
              child: drillable
                  ? Icon(
                      on
                          ? Icons.expand_less_rounded
                          : Icons.chevron_right_rounded,
                      size: 14,
                      color: on ? LhBiPlum.primary : LhColors.mute2,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 净TA 视角 —— 另一套仪表，不是同一套图换标签
  //
  //   前四个视角问的是同一个问题：「这门生意里，谁贡献了多少」。构成图
  //   是围绕「份额」组织的，因为账本上的钱都是同向的。
  //
  //   净TA 问的是完全不同的问题：「这段时间钱怎么流的，最后剩下多少」。
  //   它的五个桶天生有正有负，份额没有意义 —— 把三个负桶塞进环形图，
  //   要么消失、要么取绝对值假装是份额，两种读法都是错的。
  //
  //   所以这一维换掉整套版式：
  //     · 深墨 hero + 对冲条：一眼看清流入 / 流出 / 净下来多少
  //     · 五类瀑布：从 0 出发逐类累加，最后收口到净额 —— 资金流唯一正确的图
  //     · 二级科目双向柱：具体哪一笔在动
  //     · 存量 / 流量双栏走势：上栏累计净额（钱攒下来没有），下栏每期净额
  //   配色也换：账本是紫，资金流是 青(流入) ↔ 珊瑚(流出)，不共用一套语义。
  // ═══════════════════════════════════════════════════════════════════════

  List<_FlowBucket> get _flowBuckets {
    final out = <_FlowBucket>[];
    for (final r in widget.rowsFor('netTa')) {
      final name = r['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final net = (r['netTa'] as num?)?.toDouble() ?? 0;
      final inflow =
          (r['inflow'] as num?)?.toDouble() ?? (net > 0 ? net : 0.0);
      // outflow 在数据层就是负数（见 lighthousePrepareNetTARows），别再取反。
      final outflow =
          (r['outflow'] as num?)?.toDouble() ?? (net < 0 ? net : 0.0);
      final subs = <_FlowSub>[];
      final raw = r['secondaries'];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final sn = m['name']?.toString().trim() ?? '';
          final sv = (m['netTa'] as num?)?.toDouble() ?? 0;
          if (sn.isEmpty || sv == 0) continue;
          subs.add(_FlowSub(name: sn, parent: name, net: sv));
        }
      }
      out.add(
        _FlowBucket(
          name: name,
          net: net,
          inflow: inflow,
          outflow: outflow,
          subs: subs,
        ),
      );
    }
    return out;
  }

  List<Widget> _netTaCards(List<_BiItem> items) {
    final buckets = _flowBuckets;
    if (buckets.isEmpty) return [_emptyCard()];
    return [
      _flowHero(buckets),
      const SizedBox(height: lighthouseHeroCardGap),
      _flowWaterfallCard(buckets),
      const SizedBox(height: lighthouseHeroCardGap),
      _flowSubRankCard(buckets),
      const SizedBox(height: lighthouseHeroCardGap),
      _flowTrendCard(),
      if (_showTable) ...[
        const SizedBox(height: lighthouseHeroCardGap),
        _tableCard(items),
      ],
    ];
  }

  // ── 深墨 hero：净额 + 对冲条 ─────────────────────────────────────────────

  Widget _flowHero(List<_FlowBucket> buckets) {
    var totalIn = 0.0;
    var totalOut = 0.0;
    var net = 0.0;
    for (final b in buckets) {
      totalIn += b.inflow;
      totalOut += b.outflow.abs();
      // 净额以 netTa 字段为准，不用 流入−流出 反推：后端两者都下发时
      // 未必分毫对齐，hero 上的大数必须和列表里那个数字一模一样。
      net += b.net;
    }
    final gross = totalIn + totalOut;
    final retention = gross > 0 ? net.abs() / gross * 100 : 0.0;
    // 符号单独画，数字取绝对值 —— 否则负数会出现「−-12.3」。
    final parts = lhBiParts(net.abs(), isRate: false);
    final netColor = net >= 0 ? LhBiFlow.inflowOn : LhBiFlow.outflowOn;
    final inFlex = gross > 0 ? (totalIn / gross * 1000).round() : 1;
    final outFlex = gross > 0 ? (totalOut / gross * 1000).round() : 1;

    Widget read(String label, String value, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: _mono(size: 8.5, color: LhBiFlow.mute, spacing: 0.8)),
        const SizedBox(height: 4),
        Text(
          value,
          style: LhTypography.number(size: 15, color: color),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 15),
      decoration: BoxDecoration(
        color: LhBiFlow.ink,
        borderRadius: BorderRadius.circular(lighthouseHeroCardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: lighthouseHeroMastheadLabelIconSize,
                height: lighthouseHeroMastheadLabelIconSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: LhBiFlow.inflow,
                  borderRadius: BorderRadius.circular(
                    lighthouseHeroMastheadLabelRadius,
                  ),
                ),
                child: const Icon(
                  Icons.swap_vert_rounded,
                  size: 12,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '净TA · 资金流',
                style: _sans(
                  size: lighthouseHeroMastheadLabelFontSize,
                  color: Colors.white,
                  weight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                widget.rangeLabel,
                style: _mono(size: 9, color: LhBiFlow.mute, spacing: 0.4),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${net >= 0 ? '' : '−'}${parts.text}',
                style: LhTypography.number(size: 32, color: netColor),
              ),
              if (parts.unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    parts.unit,
                    style: _sans(
                      size: 11,
                      color: LhBiFlow.mute,
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  net >= 0 ? '净流入' : '净流出',
                  style: _mono(size: 9.5, color: netColor, spacing: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          // 对冲条：整条宽度＝这段时间的资金总流动，左流出右流入，
          // 中间那道缝就是净额 —— 两边差多少，一眼看得出。
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                    flex: outFlex < 1 ? 1 : outFlex,
                    child: const ColoredBox(color: LhBiFlow.outflowOn),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: inFlex < 1 ? 1 : inFlex,
                    child: const ColoredBox(color: LhBiFlow.inflowOn),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: read('流出', lhBiMoney(totalOut), LhBiFlow.outflowOn),
              ),
              Expanded(
                child: read('流入', lhBiMoney(totalIn), LhBiFlow.inflowOn),
              ),
              Expanded(
                child: read(
                  '净留存率',
                  '${retention.toStringAsFixed(1)}%',
                  Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            '净留存率＝净额 ÷ 资金总流动（${lhBiMoney(gross)}）'
            '，衡量这段时间流过的钱最后留下多少。',
            style: _mono(size: 8.5, color: LhBiFlow.mute, spacing: 0.1),
          ),
        ],
      ),
    );
  }

  // ── 五类瀑布 ────────────────────────────────────────────────────────────

  Widget _flowWaterfallCard(List<_FlowBucket> buckets) {
    final steps = <_WaterfallStep>[];
    var cum = 0.0;
    var lo = 0.0;
    var hi = 0.0;
    for (final b in buckets) {
      final start = cum;
      cum += b.net;
      lo = math.min(lo, math.min(start, cum));
      hi = math.max(hi, math.max(start, cum));
      steps.add(
        _WaterfallStep(
          name: b.name,
          value: b.net,
          start: start,
          end: cum,
          isTotal: false,
        ),
      );
    }
    steps.add(
      _WaterfallStep(
        name: '净额',
        value: cum,
        start: 0,
        end: cum,
        isTotal: true,
      ),
    );
    if (hi - lo < 1e-9) {
      return _flowCard(
        title: '五类资金瀑布',
        subtitle: '无净额数据',
        child: _noData('当前区间五类净额全为 0。'),
      );
    }

    final biggest = buckets.isEmpty
        ? null
        : (List<_FlowBucket>.from(buckets)
                ..sort((a, b) => b.net.abs().compareTo(a.net.abs())))
              .first;

    return _flowCard(
      title: '五类资金瀑布',
      subtitle: '从 0 逐类累加 · 收口到净额',
      insight: biggest == null
          ? null
          : '影响最大的是「${biggest.name}」${lhBiMoney(biggest.net)}'
                '，${biggest.net >= 0 ? '把净额往上抬' : '把净额往下拉'}。',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
        child: SizedBox(
          height: steps.length * 30.0 + 16,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, _) => CustomPaint(
              painter: _WaterfallPainter(
                steps: steps,
                lo: lo,
                hi: hi,
                progress: Curves.easeOutCubic.transform(_anim.value),
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }

  // ── 二级科目双向柱 ──────────────────────────────────────────────────────

  Widget _flowSubRankCard(List<_FlowBucket> buckets) {
    final subs = <_FlowSub>[];
    for (final b in buckets) {
      subs.addAll(b.subs);
    }
    if (subs.isEmpty) {
      return _flowCard(
        title: '二级科目',
        subtitle: '无明细',
        child: _noData('后端未下发二级分类，这里不做拆分。'),
      );
    }
    subs.sort((a, b) => b.net.abs().compareTo(a.net.abs()));
    final shown = subs.take(14).toList();
    final items = [
      for (final e in shown)
        _BiItem(
          name: e.name,
          group: e.parent,
          value: e.net,
          scale: e.net.abs(),
          profit: e.net,
        ),
    ];
    final maxAbs = items.fold<double>(
      0,
      (m, e) => math.max(m, e.profit.abs()),
    );
    final top = shown.first;

    return _flowCard(
      title: '二级科目 Top ${shown.length}',
      subtitle: '按净额绝对值 · 共 ${subs.length} 项',
      insight:
          '动得最狠的是「${top.name}」${lhBiMoney(top.net)}'
          '（归${top.parent}）。',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        child: SizedBox(
          height: items.length * 28.0 + 24,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, _) => CustomPaint(
              painter: _DivergingPainter(
                items: items,
                maxAbs: maxAbs,
                progress: Curves.easeOutCubic.transform(_anim.value),
                gain: LhBiFlow.inflow,
                loss: LhBiFlow.outflow,
                gainLabel: '流入',
                lossLabel: '流出',
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }

  // ── 存量 / 流量双栏走势 ─────────────────────────────────────────────────

  Widget _flowTrendCard() {
    final host = widget.seriesFor?.call('netTa', 'netTa');
    final values = host?.values ?? const <double>[];
    if (values.length < 2) {
      return _flowCard(
        title: '资金流走势',
        subtitle: '后端未下发序列',
        child: _noData('当前区间没有净TA 时间序列。'),
      );
    }
    var cum = 0.0;
    final cumulative = <double>[];
    for (final v in values) {
      cum += v;
      cumulative.add(cum);
    }
    var turn = -1;
    for (var i = 1; i < cumulative.length; i++) {
      if ((cumulative[i - 1] < 0) != (cumulative[i] < 0)) turn = i;
    }

    return _flowCard(
      title: '资金流走势',
      subtitle: '上：累计净额（存量）· 下：每期净额（流量）',
      insight: turn > 0
          ? '累计净额在第 ${turn + 1} 期由'
                '${cumulative[turn] >= 0 ? '负转正' : '正转负'}。'
          : '累计净额全程${cum >= 0 ? '为正' : '为负'}，'
                '期末 ${lhBiMoney(cum)}。',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 2, 12, 14),
        child: SizedBox(
          height: 208,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (_, _) => CustomPaint(
              painter: _FlowTrendPainter(
                values: values,
                cumulative: cumulative,
                labels: host?.labels ?? const <String>[],
                progress: Curves.easeOutCubic.transform(_anim.value),
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }

  /// 净TA 的卡壳 —— 与账本四维的 [_chartCard] 同结构、不同身份：
  /// 图标块和标题走青色，一眼能看出「这不是刚才那套图」。
  Widget _flowCard({
    required String title,
    required String subtitle,
    String? insight,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: LhColors.paper,
        borderRadius: BorderRadius.circular(lighthouseHeroCardRadius),
        border: Border.all(color: LhBiFlow.edge, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: lighthouseHeroSectionIconSize,
                  height: lighthouseHeroSectionIconSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: LhBiFlow.tint,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: LhBiFlow.edge, width: 0.8),
                  ),
                  child: const Icon(
                    Icons.water_drop_outlined,
                    size: 11,
                    color: LhBiFlow.inflow,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: _sans(
                          size: 12.5,
                          color: LhColors.ink,
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: _mono(size: 8.5, color: LhColors.mute2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (insight != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Container(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                decoration: BoxDecoration(
                  color: LhBiFlow.tint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  insight,
                  style: _sans(
                    size: 10.5,
                    color: LhColors.ink2,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }

  // ── 数据表（每张图的无障碍孪生） ─────────────────────────────────────────

  Widget _tableCard(List<_BiItem> items) {
    final rows = List<_BiItem>.from(items)
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = rows.fold<double>(0, (s, e) => s + e.scale.abs());
    final radius = BorderRadius.circular(lighthouseHeroCardRadius);

    return Container(
      decoration: BoxDecoration(
        color: LhColors.paper,
        borderRadius: radius,
        border: Border.all(color: LhColors.line2, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: _sectionHeader('cash', '数据表 · ${_metric.label}'),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            decoration: BoxDecoration(
              color: LhColors.mist,
              border: const Border(
                top: BorderSide(color: LhColors.line2, width: 0.5),
                bottom: BorderSide(color: LhColors.line2, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                SizedBox(width: 22, child: Text('#', style: _mono(size: 9))),
                Expanded(child: Text('名称', style: _mono(size: 9))),
                SizedBox(
                  width: 64,
                  child: Text(
                    _metric.label,
                    textAlign: TextAlign.right,
                    style: _mono(size: 9),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '占比',
                    textAlign: TextAlign.right,
                    style: _mono(size: 9),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '净利',
                    textAlign: TextAlign.right,
                    style: _mono(size: 9),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: i == rows.length - 1
                        ? Colors.transparent
                        : LhColors.line2.withValues(alpha: 0.6),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      style: _mono(
                        size: 10,
                        color: i < 3 ? LhBiPlum.primary : LhColors.mute2,
                        weight: i < 3 ? FontWeight.w700 : FontWeight.w500,
                        spacing: 0,
                      ),
                    ),
                  ),
                  Expanded(
                    child: LhScrollText(
                      rows[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _sans(
                        size: 11,
                        color: LhColors.ink,
                        weight: FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 64,
                    child: Text(
                      lhBiValue(rows[i].value, isRate: _metric.isRate),
                      textAlign: TextAlign.right,
                      style: _mono(size: 10, color: LhColors.ink, spacing: 0),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      total > 0
                          ? lhBiPct(rows[i].scale.abs() / total * 100)
                          : '—',
                      textAlign: TextAlign.right,
                      style: _mono(size: 10, color: LhColors.mute, spacing: 0),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      lhBiMoney(rows[i].profit),
                      textAlign: TextAlign.right,
                      style: _mono(
                        size: 10,
                        color: rows[i].profit < 0
                            ? LhColors.neg
                            : LhColors.ink2,
                        spacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── 杂项 ─────────────────────────────────────────────────────────────────

  Widget _noData(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
    child: Text(text, style: _mono(size: 10, color: LhColors.mute2)),
  );

  Widget _emptyCard() => Container(
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
    decoration: BoxDecoration(
      color: LhColors.paper,
      borderRadius: BorderRadius.circular(lighthouseHeroCardRadius),
      border: Border.all(color: LhColors.line2, width: 0.7),
    ),
    child: Center(
      child: Text(
        '当前区间下没有可分析的数据。\n换个区间或维度再看。',
        textAlign: TextAlign.center,
        style: _mono(size: 11, color: LhColors.mute2, spacing: 0.2),
      ),
    ),
  );

  Widget _loadingCard() => Container(
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
    decoration: BoxDecoration(
      color: LhColors.paper,
      borderRadius: BorderRadius.circular(lighthouseHeroCardRadius),
      border: Border.all(color: LhColors.line2, width: 0.7),
    ),
    child: Center(
      child: Text(
        '数据同步中…',
        textAlign: TextAlign.center,
        style: _mono(size: 11, color: LhColors.mute2, spacing: 0.2),
      ),
    ),
  );

  Widget _footnote() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      _isNetTa
          ? '口径与净TA 列表一致：${widget.periodLabel} · ${widget.rangeLabel}。'
                '流入为正、流出为负，瀑布按五类映射顺序累加，不做估算。'
          : '口径与列表一致：${widget.periodLabel} · ${widget.rangeLabel}。'
                '构成环按正值拆分，圆心与合计同口径（含亏损）。比率指标不参与加总。',
      style: _mono(size: 8.5, color: LhColors.mute2, spacing: 0.1),
    ),
  );
}

@immutable
class _Slice {
  const _Slice({required this.name, required this.value, required this.color});
  final String name;
  final double value;
  final Color color;
}

// ═══════════════════════════════════════════════════════════════════════════
// 画笔
// ═══════════════════════════════════════════════════════════════════════════

/// 环形图的几何：画笔和命中测试必须用同一套，否则点得到的和看到的不是一片。
///
/// 环外先留 5px 给刻度环，再往外是引线标注的走线区，所以半径要收两次。
({Offset center, double r, double stroke}) lhBiDonutGeom(Size size) {
  final limit = math.min(size.height / 2 - 14, 96.0);
  final stroke = (limit * 0.34).clamp(20.0, 32.0);
  return (
    center: Offset(size.width / 2, size.height / 2 - 2),
    r: limit - 9 - stroke / 2,
    stroke: stroke,
  );
}

/// 同色系提亮 / 压暗 —— 3D 的三个面（受光顶面、背光侧壁、倒角）都从这里出。
Color _shade(Color c, double t) {
  final h = HSLColor.fromColor(c);
  return h
      .withLightness((h.lightness + t).clamp(0.0, 1.0))
      .withSaturation(
        (t < 0 ? h.saturation * 1.08 : h.saturation * 0.96).clamp(0.0, 1.0),
      )
      .toColor();
}

/// 环形图 —— 挤出式 3D 环 + 刻度环 + 头部引线标注。
///
/// 上一版是一条 28px 的平色带子躺在一张 470 宽的卡里，环左右各空 150px，
/// 整块读起来像「图还没加载完」。这一版补三样东西，两样填空间、一样给厚度：
///
///   · 厚度 —— 整环下移 7px 用深一档的同色再画一遍当侧壁（底部露外壁、
///     洞口上沿露内壁），顶面走左上→右下渐变，内外缘各一条倒角线。
///     光统一从左上来，整个环是同一个受光体，不是四条各自发光的带子。
///   · 刻度环 —— 外圈每 2.5% 一根细刻度、10% 一根粗的。角度从此可以直接
///     读成占比，环不再只是「大概谁大」。
///   · 引线标注 —— 头部三片拉到卡的左右边缘标名字和占比。空出来的地方
///     本来就该是标注区，图表书上管这叫 leader line，不是装饰。
class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.total,
    required this.progress,
    required this.centerLabel,
    required this.centerParts,
    this.selected,
  });

  final List<_Slice> slices;
  final double total;
  final double progress;
  final String centerLabel;
  final ({String text, String unit}) centerParts;

  /// 展开了拆分的那一片：它弹出来、保持满色，其余压淡。
  final String? selected;

  /// 侧壁厚度。再厚就开始像玩具，再薄就看不出是个立体的东西。
  static const double _depth = 7;

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || slices.isEmpty) return;
    final g = lhBiDonutGeom(size);
    final center = g.center;
    final r = g.r;
    final stroke = g.stroke;
    if (r <= 8) return;
    final rect = Rect.fromCircle(center: center, radius: r);
    final sel = selected;
    final gap = 2.0 / r;

    // 段几何。动画只缩 sweep；标注按终态角度放，免得引线跟着转一圈。
    final segs =
        <({
          double start,
          double sweep,
          double full,
          double mid,
          Color color,
          bool isSel,
        })>[];
    var cursor = -math.pi / 2;
    var fullCursor = -math.pi / 2;
    for (final s in slices) {
      final full = (s.value / total) * math.pi * 2;
      segs.add((
        start: cursor,
        sweep: full * progress,
        full: full,
        mid: fullCursor + full / 2,
        color: s.color,
        isSel: sel != null && s.name == sel,
      ));
      cursor += full * progress;
      fullCursor += full;
    }

    // ① 投影 —— 环浮在卡面上，不是印在上面。
    canvas.drawCircle(
      center.translate(0, _depth + 6),
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 2
        ..color = const Color(0xFF32275A).withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // ② 侧壁
    for (final s in segs) {
      final drawn = math.max(s.sweep - gap, 0.0);
      if (drawn <= 0) continue;
      final dim = sel != null && !s.isSel;
      final off =
          Offset(0, _depth) +
          (s.isSel ? Offset(math.cos(s.mid), math.sin(s.mid)) * 6 : Offset.zero);
      canvas.drawArc(
        rect.shift(off),
        s.start + gap / 2,
        drawn,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.isSel ? stroke + 6 : stroke
          ..color = _shade(s.color, -0.20).withValues(alpha: dim ? 0.16 : 1.0),
      );
    }

    // ③ 缝底 —— 片间那 2px 露出来的不是白，是一层雾紫，缝才读作缝。
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = LhBiPlum.mist,
    );

    // ④ 顶面 + 内外缘倒角
    for (final s in segs) {
      final drawn = math.max(s.sweep - gap, 0.0);
      if (drawn <= 0) continue;
      final dim = sel != null && !s.isSel;
      final a = dim ? 0.26 : 1.0;
      final w = s.isSel ? stroke + 6 : stroke;
      final off = s.isSel
          ? Offset(math.cos(s.mid), math.sin(s.mid)) * 6
          : Offset.zero;
      final c = center + off;
      final a0 = s.start + gap / 2;
      canvas.drawArc(
        rect.shift(off),
        a0,
        drawn,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..shader =
              LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _shade(s.color, 0.16).withValues(alpha: a),
                  s.color.withValues(alpha: a),
                  _shade(s.color, -0.11).withValues(alpha: a),
                ],
                stops: const [0, 0.52, 1],
              ).createShader(
                Rect.fromCircle(center: c, radius: r + w / 2),
              ),
      );
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r + w / 2 - 1),
        a0,
        drawn,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: dim ? 0.12 : 0.42),
      );
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - w / 2 + 1),
        a0,
        drawn,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.black.withValues(alpha: dim ? 0.04 : 0.10),
      );
    }

    // ⑤ 高光 —— 光从左上来，环的左上肩上糊一道白。
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r + stroke * 0.22),
      math.pi * 1.06,
      math.pi * 0.62,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.30
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // ⑥ 刻度环 —— 每格 2.5%，粗刻度 10%。
    final tickR = r + stroke / 2 + 5;
    for (var i = 0; i < 40; i++) {
      final a = -math.pi / 2 + i * math.pi * 2 / 40;
      final major = i % 4 == 0;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + d * tickR,
        center + d * (tickR + (major ? 5.5 : 2.5)),
        Paint()
          ..color = major
              ? LhBiPlum.line
              : LhBiPlum.line.withValues(alpha: 0.6)
          ..strokeWidth = major ? 1.1 : 0.7,
      );
    }

    // ⑦ 引线标注 —— 环转完了再淡入，转的时候满屏跑线太吵。
    final fade = ((progress - 0.72) / 0.28).clamp(0.0, 1.0);
    if (fade > 0.02) {
      _paintCallouts(canvas, size, center, tickR, segs, fade, sel);
    }

    // ⑧ 圆心读数：与 Hero 同款「大数 + 小单位」
    final label = _tp(centerLabel, _mono(size: 9, spacing: 0.6));
    final valueTp = _tp(
      centerParts.text,
      LhTypography.number(size: 21, color: LhBiPlum.heroNum),
    );
    final unitTp = _tp(
      centerParts.unit,
      _sans(size: 9, color: LhColors.mute, weight: FontWeight.w500),
    );
    final wide =
        valueTp.width + (centerParts.unit.isEmpty ? 0 : unitTp.width + 2);
    label.paint(canvas, Offset(center.dx - label.width / 2, center.dy - 19));
    valueTp.paint(canvas, Offset(center.dx - wide / 2, center.dy - 5));
    if (centerParts.unit.isNotEmpty) {
      unitTp.paint(
        canvas,
        Offset(center.dx - wide / 2 + valueTp.width + 2, center.dy + 5),
      );
    }
  }

  /// 头部三片的引线标注。左右各自按 y 排一遍，挤在一起的往下推。
  void _paintCallouts(
    Canvas canvas,
    Size size,
    Offset center,
    double tickR,
    List<
      ({
        double start,
        double sweep,
        double full,
        double mid,
        Color color,
        bool isSel,
      })
    >
    segs,
    double fade,
    String? sel,
  ) {
    final picked = <int>[];
    for (var i = 0; i < segs.length && picked.length < 3; i++) {
      if (slices[i].color == LhBiPalette.other) continue;
      // 小于 6% 的片，引线比片还长，标了反而乱。
      if (segs[i].full < math.pi * 2 * 0.06) continue;
      picked.add(i);
    }
    if (picked.isEmpty) return;

    final entries =
        <({int i, bool right, double y, Offset elbow})>[];
    for (final i in picked) {
      final d = Offset(math.cos(segs[i].mid), math.sin(segs[i].mid));
      final elbow = center + d * (tickR + 15);
      entries.add((i: i, right: d.dx >= 0, y: elbow.dy, elbow: elbow));
    }

    for (final right in const [true, false]) {
      final side = entries.where((e) => e.right == right).toList()
        ..sort((a, b) => a.y.compareTo(b.y));
      var prev = -1e9;
      for (final e in side) {
        var y = math.max(e.y, prev + 26);
        y = y.clamp(18.0, size.height - 18);
        prev = y;
        _paintOneCallout(canvas, size, center, e.i, e.elbow, y, right, fade, sel);
      }
    }
  }

  void _paintOneCallout(
    Canvas canvas,
    Size size,
    Offset center,
    int index,
    Offset elbow,
    double y,
    bool right,
    double fade,
    String? sel,
  ) {
    final s = slices[index];
    final dim = sel != null && s.name != sel;
    final alpha = fade * (dim ? 0.34 : 1.0);
    final xEnd = right
        ? math.min(size.width - 8, elbow.dx + 22)
        : math.max(8.0, elbow.dx - 22);

    final leg = Paint()
      ..color = s.color.withValues(alpha: alpha * 0.7)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    final anchor = center + (elbow - center) * 0.84;
    canvas.drawLine(anchor, Offset(elbow.dx, y), leg);
    canvas.drawLine(Offset(elbow.dx, y), Offset(xEnd, y), leg);
    canvas.drawCircle(
      Offset(xEnd, y),
      2.2,
      Paint()..color = s.color.withValues(alpha: alpha),
    );

    final room = right ? size.width - xEnd - 10 : xEnd - 10;
    if (room < 26) return;
    final pct = total > 0 ? s.value / total * 100 : 0.0;
    final nameTp = _tp(
      s.name,
      _sans(
        size: 9.5,
        color: LhColors.ink.withValues(alpha: alpha),
        weight: FontWeight.w700,
      ),
      maxWidth: room,
    );
    final pctTp = _tp(
      lhBiPct(pct),
      _mono(size: 9, color: LhColors.mute.withValues(alpha: alpha)),
    );
    final nx = right ? xEnd + 6 : xEnd - 6 - nameTp.width;
    final px = right ? xEnd + 6 : xEnd - 6 - pctTp.width;
    nameTp.paint(canvas, Offset(nx, y - 11));
    pctTp.paint(canvas, Offset(px, y + 1));
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress ||
      old.total != total ||
      old.slices.length != slices.length ||
      old.selected != selected ||
      old.centerParts.text != centerParts.text;
}

/// Top N 横向柱 —— 名义类目，一个色（灯塔紫）；负值走珊瑚。
/// 数值直标在右侧固定列，不压柱子，永远不会被裁。
class _RankBarPainter extends CustomPainter {
  _RankBarPainter({
    required this.items,
    required this.maxAbs,
    required this.isRate,
    required this.progress,
    this.rowHeight = 30,
    this.selected,
  });

  final List<_BiItem> items;
  final double maxAbs;
  final bool isRate;
  final double progress;

  /// 下钻面板里行更密，主排行榜用 30。
  final double rowHeight;

  /// 已展开省份拆分的那一行：底色点亮，其余不变。
  final String? selected;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty || maxAbs <= 0) return;

    const rankW = 18.0;
    const nameW = 76.0;
    const valueW = 62.0;
    final rowH = rowHeight;
    final barH = rowHeight >= 30 ? 11.0 : 9.0;

    final plotLeft = rankW + nameW + 8;
    final plotRight = size.width - valueW - 6;
    final plotW = plotRight - plotLeft;
    if (plotW <= 10) return;
    final bottom = items.length * rowH + 4;

    // 竖向发丝网格：用灯塔的紫 hairline，与全页线色一致
    final gridPaint = Paint()
      ..color = LhBiPlum.line
      ..strokeWidth = 0.5;
    for (var i = 1; i <= 4; i++) {
      final x = plotLeft + plotW * i / 4;
      canvas.drawLine(Offset(x, 2), Offset(x, bottom), gridPaint);
    }

    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final cy = i * rowH + rowH / 2;
      final isTop3 = i < 3;
      if (selected != null && it.name == selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, cy - rowH / 2 + 1, size.width, rowH - 2),
            const Radius.circular(6),
          ),
          Paint()..color = LhBiPlum.lavender,
        );
      }

      final rank = _tp(
        '${i + 1}',
        _mono(
          size: 10,
          color: isTop3 ? LhBiPlum.primary : LhColors.mute2,
          weight: isTop3 ? FontWeight.w700 : FontWeight.w500,
          spacing: 0,
        ),
      );
      rank.paint(canvas, Offset(0, cy - rank.height / 2));

      final showGroup = rowH >= 30 && it.group.isNotEmpty;
      final name = _tp(
        it.name,
        _sans(
          size: 10.5,
          color: LhColors.ink2,
          weight: isTop3 ? FontWeight.w600 : FontWeight.w500,
        ),
        maxWidth: nameW,
      );
      if (showGroup) {
        // 名称 + 分类两行 —— 排行榜上「谁」不只是名字，还包括它属于哪一档。
        name.paint(canvas, Offset(rankW, cy - name.height + 1));
        final grp = _tp(
          it.group,
          _mono(size: 8, color: LhColors.mute2, spacing: 0.1),
          maxWidth: nameW,
        );
        grp.paint(canvas, Offset(rankW, cy + 2));
      } else {
        name.paint(canvas, Offset(rankW, cy - name.height / 2));
      }

      final ratio = (it.value.abs() / maxAbs).clamp(0.0, 1.0);
      final w = plotW * ratio * progress;
      final neg = it.value < 0;
      final color = neg ? LhColors.neg : LhBiPlum.primary;
      if (w > 0.5) {
        final rr = Rect.fromLTWH(plotLeft, cy - barH / 2, w, barH);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rr,
            topRight: const Radius.circular(5),
            bottomRight: const Radius.circular(5),
          ),
          Paint()..color = color.withValues(alpha: isTop3 ? 1.0 : 0.62),
        );
      }

      final val = _tp(
        lhBiValue(it.value, isRate: isRate),
        _mono(
          size: 10,
          color: neg ? LhColors.neg : LhColors.ink,
          weight: isTop3 ? FontWeight.w700 : FontWeight.w600,
          spacing: 0,
        ),
        maxWidth: valueW,
      );
      val.paint(canvas, Offset(size.width - val.width, cy - val.height / 2));
    }

    // 基线
    canvas.drawLine(
      Offset(plotLeft, 2),
      Offset(plotLeft, bottom),
      Paint()
        ..color = LhBiPlum.heroEdge
        ..strokeWidth = 0.8,
    );

    // x 轴刻度（0 / 中 / 最大）
    for (var i = 0; i <= 2; i++) {
      final v = maxAbs * i / 2;
      final x = plotLeft + plotW * i / 2;
      final t = _tp(lhBiTick(v, isRate: isRate), _mono(size: 8.5, spacing: 0));
      t.paint(
        canvas,
        Offset(
          (x - t.width / 2).clamp(0.0, size.width - t.width),
          bottom + 5,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RankBarPainter old) =>
      old.progress != progress ||
      old.maxAbs != maxAbs ||
      old.selected != selected ||
      old.rowHeight != rowHeight ||
      old.items.length != items.length;
}

/// 净TA 二级科目：以零为中轴的发散柱。
/// 双极取「紫 ↔ 珊瑚」而不是绿红 —— 绿在这个 App 里是「跌 / 现金流」的语义色。
class _DivergingPainter extends CustomPainter {
  _DivergingPainter({
    required this.items,
    required this.maxAbs,
    required this.progress,
    this.gain = LhBiPalette.gain,
    this.loss = LhBiPalette.loss,
    this.gainLabel = '盈利',
    this.lossLabel = '亏损',
  });

  final List<_BiItem> items;
  final double maxAbs;
  final double progress;

  /// 双极配色与轴脚注可换：账本读「盈亏」，净TA 读「流入 / 流出」。
  final Color gain;
  final Color loss;
  final String gainLabel;
  final String lossLabel;

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty || maxAbs <= 0) return;

    const rowH = 28.0;
    const barH = 12.0;
    const nameW = 72.0;
    const valueW = 58.0;

    final plotLeft = nameW + 4;
    final plotRight = size.width - valueW - 6;
    final plotW = plotRight - plotLeft;
    if (plotW <= 20) return;
    final zeroX = plotLeft + plotW / 2;
    final half = plotW / 2;
    final bottom = items.length * rowH + 4;

    // 零轴（中性，不用任何一极的色）
    canvas.drawLine(
      Offset(zeroX, 0),
      Offset(zeroX, bottom),
      Paint()
        ..color = LhColors.line
        ..strokeWidth = 0.9,
    );

    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      final cy = i * rowH + rowH / 2;
      final pos = it.profit >= 0;
      final color = pos ? gain : loss;
      final w = half * (it.profit.abs() / maxAbs).clamp(0.0, 1.0) * progress;

      final name = _tp(
        it.name,
        _sans(size: 10.5, color: LhColors.ink2, weight: FontWeight.w500),
        maxWidth: nameW,
      );
      name.paint(canvas, Offset(0, cy - name.height / 2));

      if (w > 0.5) {
        final rr = pos
            ? Rect.fromLTWH(zeroX + 1, cy - barH / 2, w, barH)
            : Rect.fromLTWH(zeroX - 1 - w, cy - barH / 2, w, barH);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rr,
            topRight: Radius.circular(pos ? 5 : 0),
            bottomRight: Radius.circular(pos ? 5 : 0),
            topLeft: Radius.circular(pos ? 0 : 5),
            bottomLeft: Radius.circular(pos ? 0 : 5),
          ),
          Paint()..color = color,
        );
      }

      final val = _tp(
        lhBiMoney(it.profit),
        _mono(size: 10, color: color, weight: FontWeight.w700, spacing: 0),
        maxWidth: valueW,
      );
      val.paint(canvas, Offset(size.width - val.width, cy - val.height / 2));
    }

    // 轴脚注：负极 ← 0 → 正极
    final left = _tp(
      lossLabel,
      _mono(size: 8.5, color: loss, spacing: 0.3),
    );
    final mid = _tp('0', _mono(size: 8.5, spacing: 0));
    final right = _tp(
      gainLabel,
      _mono(size: 8.5, color: gain, spacing: 0.3),
    );
    final baseY = bottom + 5;
    left.paint(canvas, Offset(plotLeft, baseY));
    mid.paint(canvas, Offset(zeroX - mid.width / 2, baseY));
    right.paint(canvas, Offset(plotRight - right.width, baseY));
  }

  @override
  bool shouldRepaint(covariant _DivergingPainter old) =>
      old.progress != progress ||
      old.maxAbs != maxAbs ||
      old.items.length != items.length;
}

// ═══════════════════════════════════════════════════════════════════════════
// 净TA 专属：配色 · 模型 · 画笔
//
//   账本四维用紫（份额语义），净TA 用 青 ↔ 珊瑚（方向语义）。两套色不共用，
//   因为它们回答的不是同一类问题：紫色系里「深浅」表示大小，这里「左右」
//   表示进出，混用会让人把流出读成亏损。
// ═══════════════════════════════════════════════════════════════════════════

abstract final class LhBiFlow {
  /// 深墨 hero —— 与账本的雾紫 hero 拉开距离，进这一维就知道换了仪表。
  static const Color ink = Color(0xFF16202B);
  static const Color inflow = Color(0xFF0F9E8E);
  static const Color outflow = Color(0xFFD1553C);

  /// 深底上的同色（提亮，保证 4.5:1 以上）。
  static const Color inflowOn = Color(0xFF3FD1BC);
  static const Color outflowOn = Color(0xFFFF8B6D);
  static const Color mute = Color(0xFF8A98A8);
  static const Color tint = Color(0xFFF1F8F7);
  static const Color edge = Color(0xFFD6E7E4);
}

@immutable
class _FlowSub {
  const _FlowSub({
    required this.name,
    required this.parent,
    required this.net,
  });
  final String name;
  final String parent;
  final double net;
}

@immutable
class _FlowBucket {
  const _FlowBucket({
    required this.name,
    required this.net,
    required this.inflow,
    required this.outflow,
    required this.subs,
  });
  final String name;
  final double net;

  /// inflow ≥ 0，outflow ≤ 0（数据层就是这么存的）。
  final double inflow;
  final double outflow;
  final List<_FlowSub> subs;
}

@immutable
class _WaterfallStep {
  const _WaterfallStep({
    required this.name,
    required this.value,
    required this.start,
    required this.end,
    required this.isTotal,
  });
  final String name;
  final double value;
  final double start;
  final double end;
  final bool isTotal;
}

/// 横向瀑布：每行一类，柱子从上一档累计值画到本档累计值，最后一行收口到净额。
///
/// 用横向而不是纵向：手机宽度放不下六个竖柱＋四字类名，横过来名字有位置，
/// 柱长也更容易比。虚线接力棒把「上一档结束＝下一档开始」显式画出来 ——
/// 瀑布图看不懂，多半就是缺了这根线。
class _WaterfallPainter extends CustomPainter {
  _WaterfallPainter({
    required this.steps,
    required this.lo,
    required this.hi,
    required this.progress,
  });

  final List<_WaterfallStep> steps;
  final double lo;
  final double hi;
  final double progress;

  static const double rowH = 30;
  static const double nameW = 60;
  static const double valueW = 60;

  @override
  void paint(Canvas canvas, Size size) {
    if (steps.isEmpty) return;
    final plotLeft = nameW + 6;
    final plotRight = size.width - valueW - 2;
    final plotW = plotRight - plotLeft;
    if (plotW <= 24) return;

    final span = (hi - lo).abs() < 1e-9 ? 1.0 : hi - lo;
    double x(double v) => plotLeft + (v - lo) / span * plotW;
    final zeroX = x(0);
    final bottom = steps.length * rowH;

    canvas.drawLine(
      Offset(zeroX, 0),
      Offset(zeroX, bottom),
      Paint()
        ..color = LhColors.line
        ..strokeWidth = 0.9,
    );

    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final cy = i * rowH + rowH / 2;
      final positive = s.isTotal ? s.end >= 0 : s.value >= 0;
      final color = positive ? LhBiFlow.inflow : LhBiFlow.outflow;

      final name = _tp(
        s.name,
        _sans(
          size: 10.5,
          color: s.isTotal ? LhColors.ink : LhColors.ink2,
          weight: s.isTotal ? FontWeight.w700 : FontWeight.w500,
        ),
        maxWidth: nameW,
      );
      name.paint(canvas, Offset(0, cy - name.height / 2));

      final a = x(s.start);
      final b = a + (x(s.end) - a) * progress;
      final left = math.min(a, b);
      final right = math.max(a, b);
      final barH = s.isTotal ? 16.0 : 13.0;
      final rect = Rect.fromLTRB(
        left,
        cy - barH / 2,
        math.max(right, left + 1.5),
        cy + barH / 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = s.isTotal ? color : color.withAlpha(205),
      );
      if (s.isTotal) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = LhBiFlow.ink.withAlpha(120),
        );
      }

      // 接力虚线：这一档的终点＝下一档的起点。
      if (i < steps.length - 1 && !steps[i + 1].isTotal) {
        final linkX = x(s.end);
        final dash = Paint()
          ..color = LhColors.mute2.withAlpha(120)
          ..strokeWidth = 0.8;
        var y = cy + barH / 2 + 1;
        final endY = cy + rowH - barH / 2 - 1;
        while (y < endY) {
          canvas.drawLine(
            Offset(linkX, y),
            Offset(linkX, math.min(y + 2.5, endY)),
            dash,
          );
          y += 5;
        }
      }

      final val = _tp(
        '${s.value >= 0 ? '+' : '−'}${lhBiMoney(s.value.abs())}',
        _mono(
          size: 10,
          color: s.isTotal ? LhColors.ink : color,
          weight: FontWeight.w700,
          spacing: 0,
        ),
        maxWidth: valueW,
      );
      val.paint(canvas, Offset(size.width - val.width, cy - val.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _WaterfallPainter old) =>
      old.progress != progress ||
      old.lo != lo ||
      old.hi != hi ||
      old.steps.length != steps.length;
}

/// 存量 / 流量双栏：上栏累计净额（钱有没有攒下来），下栏每期净额（这期进出）。
///
/// 两栏各用各的刻度，因为它们不是一个量纲 —— 硬塞进一个坐标系，
/// 累计线会把每期柱压成一条贴底的线，等于白画。
class _FlowTrendPainter extends CustomPainter {
  _FlowTrendPainter({
    required this.values,
    required this.cumulative,
    required this.labels,
    required this.progress,
  });

  final List<double> values;
  final List<double> cumulative;
  final List<String> labels;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    const leftPad = 4.0;
    const rightPad = 6.0;
    final plotW = size.width - leftPad - rightPad;
    if (plotW <= 20) return;

    final topH = size.height * 0.54;
    final gap = 16.0;
    final botTop = topH + gap;
    final botH = size.height - botTop - 14;
    if (botH <= 10) return;

    final n = values.length;
    final step = plotW / (n - 1);

    // ── 上栏：累计净额面积线 ───────────────────────────────────────────
    var cLo = 0.0;
    var cHi = 0.0;
    for (final v in cumulative) {
      cLo = math.min(cLo, v);
      cHi = math.max(cHi, v);
    }
    if ((cHi - cLo).abs() < 1e-9) cHi = cLo + 1;
    double cy(double v) => topH - (v - cLo) / (cHi - cLo) * (topH - 6) - 3;

    final zeroY = cy(0);
    canvas.drawLine(
      Offset(leftPad, zeroY),
      Offset(size.width - rightPad, zeroY),
      Paint()
        ..color = LhColors.line
        ..strokeWidth = 0.8,
    );

    final shown = (n * progress).clamp(2, n).toInt();
    final path = Path();
    final area = Path();
    for (var i = 0; i < shown; i++) {
      final px = leftPad + i * step;
      final py = cy(cumulative[i]);
      if (i == 0) {
        path.moveTo(px, py);
        area.moveTo(px, zeroY);
        area.lineTo(px, py);
      } else {
        path.lineTo(px, py);
        area.lineTo(px, py);
      }
    }
    area.lineTo(leftPad + (shown - 1) * step, zeroY);
    area.close();
    final endPositive = cumulative[shown - 1] >= 0;
    final lineColor = endPositive ? LhBiFlow.inflow : LhBiFlow.outflow;
    canvas.drawPath(area, Paint()..color = lineColor.withAlpha(28));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = lineColor,
    );
    final lastX = leftPad + (shown - 1) * step;
    final lastY = cy(cumulative[shown - 1]);
    canvas.drawCircle(Offset(lastX, lastY), 3.2, Paint()..color = lineColor);
    canvas.drawCircle(
      Offset(lastX, lastY),
      3.2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = LhColors.paper,
    );

    final cumTag = _tp(
      '累计 ${lhBiMoney(cumulative[shown - 1])}',
      _mono(size: 9, color: lineColor, weight: FontWeight.w700, spacing: 0.2),
    );
    cumTag.paint(
      canvas,
      Offset(
        math.max(0.0, math.min(lastX + 6, size.width - cumTag.width)),
        math.max(0.0, lastY - cumTag.height - 4),
      ),
    );
    final cumKicker = _tp(
      '累计净额',
      _mono(size: 8.5, color: LhColors.mute2, spacing: 0.6),
    );
    cumKicker.paint(canvas, Offset(leftPad, 0));

    // ── 下栏：每期净额正负柱 ───────────────────────────────────────────
    var mx = 0.0;
    for (final v in values) {
      mx = math.max(mx, v.abs());
    }
    if (mx <= 0) mx = 1;
    final midY = botTop + botH / 2;
    canvas.drawLine(
      Offset(leftPad, midY),
      Offset(size.width - rightPad, midY),
      Paint()
        ..color = LhColors.line
        ..strokeWidth = 0.8,
    );

    final barW = math.max(2.0, math.min(11.0, step * 0.55));
    for (var i = 0; i < shown; i++) {
      final v = values[i];
      if (v == 0) continue;
      final px = leftPad + i * step;
      final h = (v.abs() / mx) * (botH / 2 - 4) * progress;
      final rect = v >= 0
          ? Rect.fromLTRB(px - barW / 2, midY - h, px + barW / 2, midY)
          : Rect.fromLTRB(px - barW / 2, midY, px + barW / 2, midY + h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()
          ..color = (v >= 0 ? LhBiFlow.inflow : LhBiFlow.outflow)
              .withAlpha(215),
      );
    }
    final barKicker = _tp(
      '每期净额',
      _mono(size: 8.5, color: LhColors.mute2, spacing: 0.6),
    );
    barKicker.paint(canvas, Offset(leftPad, botTop - 11));

    // ── 横轴：首 / 中 / 末三个刻度，够定位就行 ─────────────────────────
    String labelAt(int i) {
      if (i < 0 || i >= labels.length) return '${i + 1}';
      return labels[i];
    }

    final axisY = size.height - 11;
    final ticks = <int>{0, (n - 1) ~/ 2, n - 1};
    for (final i in ticks) {
      final t = _tp(labelAt(i), _mono(size: 8.5, spacing: 0.1));
      var tx = leftPad + i * step - t.width / 2;
      // 窄屏下标签可能比画布还宽，clamp 的上界必须先兜到 0，否则会断言失败。
      tx = tx.clamp(0.0, math.max(0.0, size.width - t.width));
      t.paint(canvas, Offset(tx, axisY));
    }
  }

  @override
  bool shouldRepaint(covariant _FlowTrendPainter old) =>
      old.progress != progress ||
      old.values.length != values.length ||
      old.cumulative.length != cumulative.length;
}
