// 灯塔 · PK 对比（只在一级）
//
// 这里放跟页面骨架无关的部分：对阵方的数据模型、一项指标怎么判输赢、
// 学术图风格的柱状图卡（本期对比 / 日周月季年）、参赛小签、挑选行。
// 页面骨架（深紫顶带 + 外面那条期间条 + 维度 / 分类）在
// native_lighthouse_page.dart 里，直接复用一级的部件。
//
// 图：淡蓝灰底卡 + 白色绘图区细框，左上图号（A、B、C…）+「单位：万」；
// 细柱、0 基线、发丝网格、柱顶带单位；赢的一方实心，其他方同色 45° 斜线。
// 柱下的名字一定写全：放不下先缩字（最小 8），再不行斜 38° 排。

import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_shared_card_data.dart';
import 'lighthouse_theme.dart';

// ── 颜色：8 色（已过色觉检查），第 9 个起中性灰，靠柱下名字认 ─────────────
const List<Color> lhPkPalette = <Color>[
  Color(0xFF7B5CD8),
  Color(0xFFD9891A),
  Color(0xFF1A9BA8),
  Color(0xFF3B4FA8),
  Color(0xFFC2507A),
  Color(0xFF6E8B2E),
  Color(0xFF2F8FD8),
  Color(0xFFB0742A),
];
const List<Color> lhPkPaletteTint = <Color>[
  Color(0xFFF3EEFC),
  Color(0xFFFDF4E4),
  Color(0xFFE6F5F6),
  Color(0xFFECEEF8),
  Color(0xFFFAEBF1),
  Color(0xFFEFF3E6),
  Color(0xFFE8F2FC),
  Color(0xFFF8EFE3),
];
const Color lhPkGrey = Color(0xFFA39DB0);
const Color lhPkGreyTint = Color(0xFFF1EFF4);

Color lhPkColorAt(int? i) =>
    i != null && i >= 0 && i < lhPkPalette.length ? lhPkPalette[i] : lhPkGrey;
Color lhPkTintAt(int? i) => i != null && i >= 0 && i < lhPkPaletteTint.length
    ? lhPkPaletteTint[i]
    : lhPkGreyTint;

/// 颜色跟着对象走，不跟名次：已有的留着，新来的占最小的空号。
Map<String, int> lhPkAssignColors(
  List<String> keys,
  Map<String, int> previous,
) {
  final out = <String, int>{
    for (final k in keys)
      if (previous[k] != null) k: previous[k]!,
  };
  for (final k in keys) {
    if (out.containsKey(k)) continue;
    var c = 0;
    while (out.values.contains(c)) {
      c++;
    }
    out[k] = c;
  }
  return out;
}

// ── 指标 ────────────────────────────────────────────────────────────────
enum LhPkKind { money, pct, permille }

class LhPkMetricDef {
  const LhPkMetricDef(
    this.key,
    this.label, {
    this.dir = 1,
    this.kind = LhPkKind.money,
    this.point = false,
  });
  final String key;
  final String label;

  /// 1 = 高者胜；-1 = 低者胜；0 = 只看不比。
  final int dir;
  final LhPkKind kind;

  /// 时点数（资产、折扣进度）：不分日周月季年。
  final bool point;

  String get rule => dir > 0 ? '高者胜' : (dir < 0 ? '低者胜' : '');
}

const Map<String, LhPkMetricDef> lhPkMetricDefs = <String, LhPkMetricDef>{
  'sales': LhPkMetricDef('sales', '销售额'),
  'verifiedSales': LhPkMetricDef('verifiedSales', '核销额'),
  'gmv': LhPkMetricDef('gmv', 'GMV'),
  'totalCost': LhPkMetricDef('totalCost', '成本合计', dir: -1),
  'projectCost': LhPkMetricDef('projectCost', '项目成本', dir: -1),
  'cost': LhPkMetricDef('cost', '业务成本', dir: -1),
  'costRate': LhPkMetricDef('costRate', '成本率', dir: -1, kind: LhPkKind.pct),
  'profit': LhPkMetricDef('profit', '利润'),
  'netProfit': LhPkMetricDef('netProfit', '净利润'),
  'revenue': LhPkMetricDef('revenue', '收入'),
  'spread': LhPkMetricDef('spread', '利差'),
  'grossMargin': LhPkMetricDef('grossMargin', '毛利率', kind: LhPkKind.pct),
  'roi': LhPkMetricDef('roi', 'ROI', kind: LhPkKind.pct),
  'prepaid': LhPkMetricDef('prepaid', '经营性净现金流'),
  'verifyRate': LhPkMetricDef('verifyRate', '核销率', kind: LhPkKind.pct),
  'spreadRate': LhPkMetricDef('spreadRate', '利差率', kind: LhPkKind.pct),
  'share': LhPkMetricDef('share', '占本维销售额', kind: LhPkKind.pct),
  'totalAssets': LhPkMetricDef('totalAssets', '账面资产', point: true),
  'regulatoryAccountBalance': LhPkMetricDef(
    'regulatoryAccountBalance',
    '已入账',
    point: true,
  ),
  'inTransitFunds': LhPkMetricDef(
    'inTransitFunds',
    '待入账',
    dir: 0,
    point: true,
  ),
  'endingPrepaymentBalance': LhPkMetricDef(
    'endingPrepaymentBalance',
    '期末预付',
    dir: 0,
    point: true,
  ),
  'fundPoolBalance': LhPkMetricDef(
    'fundPoolBalance',
    '可动用额度',
    point: true,
  ),
  'tierNow': LhPkMetricDef(
    'tierNow',
    '当前档位',
    kind: LhPkKind.permille,
    point: true,
  ),
  'gapNext': LhPkMetricDef('gapNext', '距下一档', dir: -1, point: true),
  'discountProgress': LhPkMetricDef(
    'discountProgress',
    '档内进度',
    kind: LhPkKind.pct,
    point: true,
  ),
};

class LhPkSectionDef {
  const LhPkSectionDef(this.key, this.title, this.keys);
  final String key;
  final String title;
  final List<String> keys;
}

/// 维度 → 分组 tab。利润放第一个；供给多「资产」「折扣进度」，其他维度多「结构」。
List<LhPkSectionDef> lhPkSectionsFor(String dim) => [
  const LhPkSectionDef('profit', '利润', [
    'profit',
    'netProfit',
    'revenue',
    'spread',
    'grossMargin',
    'roi',
  ]),
  const LhPkSectionDef('scale', '规模', ['sales', 'verifiedSales', 'gmv']),
  const LhPkSectionDef('cost', '成本', [
    'totalCost',
    'projectCost',
    'cost',
    'costRate',
  ]),
  const LhPkSectionDef('cash', '现金流', ['prepaid']),
  if (dim == 'supply') ...[
    const LhPkSectionDef('assets', '资产', [
      'totalAssets',
      'regulatoryAccountBalance',
      'inTransitFunds',
      'endingPrepaymentBalance',
      'fundPoolBalance',
    ]),
    const LhPkSectionDef('discount', '折扣进度', [
      'tierNow',
      'gapNext',
      'discountProgress',
    ]),
  ] else
    const LhPkSectionDef('mix', '结构', ['verifyRate', 'spreadRate', 'share']),
];

// ── 对阵方 ──────────────────────────────────────────────────────────────
class LhPkEntity {
  const LhPkEntity({
    required this.key,
    required this.name,
    this.group = '',
    this.sub = '',
    this.values = const <String, double?>{},
  });

  final String key;
  final String name;
  final String group;

  /// 挑选行第二行（「能源 · 第 2 名」/「3 个产品」）。
  final String sub;

  /// 金额是元，率是 %，档位是 ‰。
  final Map<String, double?> values;

  double? v(String k) {
    final x = values[k];
    return x != null && x.isFinite ? x : null;
  }
}

// ── 格式 ────────────────────────────────────────────────────────────────
String lhPkThousands(String s) {
  final neg = s.startsWith('-');
  final body = neg ? s.substring(1) : s;
  final dot = body.indexOf('.');
  final intPart = dot < 0 ? body : body.substring(0, dot);
  final rest = dot < 0 ? '' : body.substring(dot);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  return '${neg ? '−' : ''}$buf$rest';
}

String _trimZeros(String s) =>
    s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;

/// 元 → (数, 单位)：≥1 亿用亿，≥1 万用万；去掉末尾的 0。
({String n, String u}) lhPkMoneyParts(double? v) {
  if (v == null || !v.isFinite) return (n: '—', u: '');
  final a = v.abs();
  final s = v < 0 ? '−' : '';
  if (a >= 1e8) return (n: '$s${_trimZeros((a / 1e8).toStringAsFixed(2))}', u: '亿');
  if (a >= 1e4) {
    final w = a / 1e4;
    final d = w >= 1000 ? 0 : (w >= 100 ? 1 : 2);
    return (n: '$s${lhPkThousands(_trimZeros(w.toStringAsFixed(d)))}', u: '万');
  }
  return (n: '$s${a.toStringAsFixed(0)}', u: '元');
}

({String n, String u}) lhPkFormat(LhPkMetricDef def, double? v) {
  if (v == null || !v.isFinite) return (n: '—', u: '');
  if (def.key == 'gapNext' && v.abs() < 1e-9) return (n: '已到顶档', u: '');
  switch (def.kind) {
    case LhPkKind.money:
      return lhPkMoneyParts(v);
    case LhPkKind.pct:
      return (n: '${v < 0 ? '−' : ''}${v.abs().toStringAsFixed(1)}', u: '%');
    case LhPkKind.permille:
      return (n: v.toStringAsFixed(1), u: '‰');
  }
}

// ── 一项指标的胜负 ──────────────────────────────────────────────────────
class LhPkMetricResult {
  LhPkMetricResult._(this.def, this.values, this.winner);

  final LhPkMetricDef def;
  final List<double?> values;

  /// 唯一的赢家下标；打平 / 缺数 / 不比 = null。
  final int? winner;

  factory LhPkMetricResult.of(LhPkMetricDef def, List<LhPkEntity?> sides) =>
      LhPkMetricResult.fromValues(def, <double?>[
        for (final s in sides) s?.v(def.key),
      ]);

  factory LhPkMetricResult.fromValues(LhPkMetricDef def, List<double?> vals) {
    final present = <int>[
      for (var i = 0; i < vals.length; i++)
        if (vals[i] != null) i,
    ];
    if (def.dir == 0 || present.length < 2) {
      return LhPkMetricResult._(def, vals, null);
    }
    final xs = present.map((i) => vals[i]!);
    final best = def.dir > 0 ? xs.reduce(math.max) : xs.reduce(math.min);
    final hits = present.where((i) => (vals[i]! - best).abs() < 1e-9).toList();
    return LhPkMetricResult._(def, vals, hits.length == 1 ? hits.first : null);
  }

  bool get hasData => values.any((v) => v != null);

  /// 图上的刻度单位：金额按量级选万 / 亿。
  ({double div, String unit}) get scale => lhPkScaleFor(def, values);
}

({double div, String unit}) lhPkScaleFor(
  LhPkMetricDef def,
  Iterable<double?> values,
) {
  switch (def.kind) {
    case LhPkKind.pct:
      return (div: 1, unit: '%');
    case LhPkKind.permille:
      return (div: 1, unit: '‰');
    case LhPkKind.money:
      var maxAbs = 0.0;
      for (final v in values) {
        if (v != null && v.abs() > maxAbs) maxAbs = v.abs();
      }
      return maxAbs >= 1e8 ? (div: 1e8, unit: '亿') : (div: 1e4, unit: '万');
  }
}

double _lhPkNice(double x) {
  if (x <= 0) return 1;
  final e = math.pow(10, (math.log(x) / math.ln10).floor()).toDouble();
  final f = x / e;
  const steps = <double>[1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];
  for (final s in steps) {
    if (f <= s + 1e-9) return s * e;
  }
  return 10 * e;
}

String _lhPkAxisText(double v) {
  if (v.abs() < 1e-9) return '0';
  final a = v.abs();
  final txt = a >= 100 ? a.toStringAsFixed(0) : _trimZeros(a.toStringAsFixed(1));
  return lhPkThousands('${v < 0 ? '-' : ''}$txt');
}

// ── 学术图的颜色 ────────────────────────────────────────────────────────
abstract final class LhPkFig {
  static const card = Color(0xFFEEF3F8);
  static const cardEdge = Color(0xFFDCE5EF);
  static const plot = Color(0xFFFFFFFF);
  static const frame = Color(0xFFD5DEE8);
  static const grid = Color(0xFFE7EDF4);
  static const zero = Color(0xFF9FB0C4);
  static const ink = Color(0xFF16202B);
  static const ink2 = Color(0xFF2B3644);
  static const mute = Color(0xFF7C8796);
  static const mute2 = Color(0xFF9AA5B3);
}

BoxDecoration lhPkFigureDeco(BuildContext context) => BoxDecoration(
  color: DunesColors.resolve(context, LhPkFig.card, role: DunesColorRole.surface),
  borderRadius: BorderRadius.circular(10),
  border: Border.all(
    color: DunesColors.resolve(
      context,
      LhPkFig.cardEdge,
      role: DunesColorRole.border,
    ),
    width: 0.8,
  ),
);

Widget _lhPkFigCaption(
  BuildContext context, {
  required String panel,
  required String label,
  required String unit,
  String rule = '',
}) {
  Color c(Color x) => DunesColors.resolve(context, x);
  return Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Text(
        panel,
        style: LhTypography.sans(
          context: context,
          size: 12.5,
          color: c(LhPkFig.ink),
          weight: FontWeight.w800,
        ),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LhTypography.sans(
            context: context,
            size: 11.5,
            color: c(LhPkFig.ink2),
            weight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 6),
      Text(
        '单位：$unit',
        style: LhTypography.sans(
          context: context,
          size: 9,
          color: c(LhPkFig.mute),
        ),
      ),
      const Spacer(),
      if (rule.isNotEmpty)
        Text(
          rule,
          style: LhTypography.sans(
            context: context,
            size: 9,
            color: c(LhPkFig.mute2),
          ),
        ),
    ],
  );
}

// ── 本期对比：一张图 ────────────────────────────────────────────────────
class LhPkChartCard extends StatelessWidget {
  const LhPkChartCard({
    super.key,
    required this.panel,
    required this.result,
    required this.names,
    required this.colors,
  });

  /// 图号 A、B、C…
  final String panel;
  final LhPkMetricResult result;
  final List<String> names;
  final List<Color> colors;

  static const double plotHeight = 112;
  static const double axisWidth = 34;

  @override
  Widget build(BuildContext context) {
    Color c(Color x) => DunesColors.resolve(context, x);
    final def = result.def;
    final sc = result.scale;
    final n = names.length;
    final labelStyle = LhTypography.sans(
      context: context,
      size: 10,
      color: c(LhPkFig.ink2),
      height: 1.1,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 9, 9, 8),
      decoration: lhPkFigureDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _lhPkFigCaption(
            context,
            panel: panel,
            label: def.label,
            unit: sc.unit,
            rule: def.rule,
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, box) {
              final plotW = math.max(box.maxWidth - axisWidth, 1.0);
              final slot = plotW / math.max(n, 1);
              final labels = _LhPkLabelLayout.fit(
                names,
                labelStyle,
                slot,
                Directionality.of(context),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: plotHeight,
                    child: CustomPaint(
                      painter: _LhPkColumnsPainter(
                        values: [
                          for (final v in result.values)
                            v == null ? null : v / sc.div,
                        ],
                        caps: [
                          for (final v in result.values) () {
                            final f = lhPkFormat(def, v);
                            return '${f.n}${f.u}';
                          }(),
                        ],
                        winner: result.winner,
                        colors: colors,
                        axisWidth: axisWidth,
                        showAxis: true,
                        showCaps: true,
                        capSize: slot < 46 ? 8 : 9,
                        style: _LhPkFigStyle.of(context),
                        textDirection: Directionality.of(context),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  SizedBox(
                    height: labels.height,
                    child: CustomPaint(
                      painter: _LhPkLabelsPainter(
                        layout: labels,
                        axisWidth: axisWidth,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── 日周月季年：一行五个小图（各用各的刻度） ───────────────────────────
class LhPkCrossCard extends StatelessWidget {
  const LhPkCrossCard({
    super.key,
    required this.panel,
    required this.def,
    required this.periodLabels,
    required this.values,
    required this.colors,
    this.loading = const <bool>[],
    this.selected = -1,
  });

  final String panel;
  final LhPkMetricDef def;

  /// 今日 / 本周 / 本月 / 本季 / 本年
  final List<String> periodLabels;

  /// values[期间][参赛方]；某期还没拉到 = 整个 null。
  final List<List<double?>?> values;
  final List<Color> colors;
  final List<bool> loading;

  /// 跟顶上期间条选中的那一期，标题加粗。
  final int selected;

  @override
  Widget build(BuildContext context) {
    Color c(Color x) => DunesColors.resolve(context, x);
    final all = <double?>[
      for (final p in values) ...?p,
    ];
    final sc = lhPkScaleFor(def, all);
    final style = _LhPkFigStyle.of(context);
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: lhPkFigureDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _lhPkFigCaption(
            context,
            panel: panel,
            label: def.label,
            unit: sc.unit,
            rule: def.rule,
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var p = 0; p < periodLabels.length; p++) ...[
                if (p > 0) const SizedBox(width: 6),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final vals = p < values.length ? values[p] : null;
                      final busy = p < loading.length && loading[p];
                      final scaled = <double?>[
                        for (final v in vals ?? const <double?>[])
                          v == null ? null : v / sc.div,
                      ];
                      var top = 0.0;
                      for (final v in scaled) {
                        if (v != null && v > top) top = v;
                      }
                      final res = vals == null
                          ? null
                          : LhPkMetricResult.fromValues(def, vals);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                periodLabels[p],
                                style: LhTypography.sans(
                                  context: context,
                                  size: 10,
                                  color: c(
                                    p == selected ? LhPkFig.ink : LhPkFig.ink2,
                                  ),
                                  weight: p == selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              if (vals != null && top > 0)
                                Text(
                                  _lhPkAxisText(_lhPkNice(top)),
                                  style: LhTypography.mono(
                                    context: context,
                                    size: 7.5,
                                    color: c(LhPkFig.mute),
                                    weight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          SizedBox(
                            height: 92,
                            child: vals == null
                                ? Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: style.plot,
                                      border: Border.all(
                                        color: style.frame,
                                        width: 1,
                                      ),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: busy
                                        ? SizedBox.square(
                                            dimension: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.4,
                                              color: c(LhPkFig.mute2),
                                            ),
                                          )
                                        : Text(
                                            '—',
                                            style: LhTypography.sans(
                                              context: context,
                                              size: 10,
                                              color: c(LhPkFig.mute2),
                                            ),
                                          ),
                                  )
                                : CustomPaint(
                                    painter: _LhPkColumnsPainter(
                                      values: scaled,
                                      caps: const <String>[],
                                      winner: res?.winner,
                                      colors: colors,
                                      axisWidth: 0,
                                      showAxis: false,
                                      showCaps: false,
                                      capSize: 8,
                                      maxBar: 14,
                                      style: style,
                                      textDirection: Directionality.of(context),
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LhPkFigStyle {
  const _LhPkFigStyle({
    required this.plot,
    required this.frame,
    required this.grid,
    required this.zero,
    required this.hatchBg,
    required this.tick,
    required this.cap,
    required this.capStrong,
  });
  final Color plot;
  final Color frame;
  final Color grid;
  final Color zero;
  final Color hatchBg;
  final TextStyle tick;
  final TextStyle cap;
  final TextStyle capStrong;

  static _LhPkFigStyle of(BuildContext context) {
    Color c(Color x) => DunesColors.resolve(context, x);
    Color b(Color x) =>
        DunesColors.resolve(context, x, role: DunesColorRole.border);
    final plot = DunesColors.resolve(
      context,
      LhPkFig.plot,
      role: DunesColorRole.surface,
    );
    return _LhPkFigStyle(
      plot: plot,
      frame: b(LhPkFig.frame),
      grid: b(LhPkFig.grid),
      zero: b(LhPkFig.zero),
      hatchBg: plot,
      tick: LhTypography.mono(
        context: context,
        size: 8,
        color: c(LhPkFig.mute),
        weight: FontWeight.w500,
        height: 1.0,
      ),
      cap: LhTypography.mono(
        context: context,
        size: 9,
        color: c(LhPkFig.ink2),
        weight: FontWeight.w600,
        height: 1.0,
      ),
      capStrong: LhTypography.mono(
        context: context,
        size: 9,
        color: c(LhPkFig.ink),
        weight: FontWeight.w700,
        height: 1.0,
      ),
    );
  }
}

class _LhPkColumnsPainter extends CustomPainter {
  _LhPkColumnsPainter({
    required this.values,
    required this.caps,
    required this.winner,
    required this.colors,
    required this.axisWidth,
    required this.showAxis,
    required this.showCaps,
    required this.capSize,
    required this.style,
    required this.textDirection,
    this.maxBar = 22,
  });

  final List<double?> values;
  final List<String> caps;
  final int? winner;
  final List<Color> colors;
  final double axisWidth;
  final bool showAxis;
  final bool showCaps;
  final double capSize;
  final double maxBar;
  final _LhPkFigStyle style;
  final TextDirection textDirection;

  TextPainter _text(String s, TextStyle st) => TextPainter(
    text: TextSpan(text: s, style: st),
    textDirection: textDirection,
    maxLines: 1,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    final plotL = axisWidth;
    final plotRect = Rect.fromLTWH(plotL, 0, size.width - plotL, size.height);
    final frame = RRect.fromRectAndRadius(plotRect, const Radius.circular(3));
    canvas.drawRRect(frame, Paint()..color = style.plot);
    if (n == 0) return;
    var vMax = 0.0;
    var vMin = 0.0;
    for (final v in values) {
      if (v == null) continue;
      vMax = math.max(vMax, v);
      vMin = math.min(vMin, v);
    }
    final top = vMax > 0 ? _lhPkNice(vMax) : 0.0;
    final bot = vMin < 0 ? -_lhPkNice(-vMin) : 0.0;
    final span = (top - bot) == 0 ? 1.0 : top - bot;
    final padTop = showCaps ? 16.0 : 6.0;
    final padBottom = showCaps && vMin < 0 ? 14.0 : 0.0;
    final plotH = size.height - padTop - padBottom;
    double y(double v) => padTop + (top - v) / span * plotH;

    // 网格 + 刻度
    final ticks = bot < 0 ? <double>[top, 0, bot] : <double>[top, top / 2, 0];
    final seen = <double>{};
    for (final t in ticks) {
      if (!seen.add(t)) continue;
      final ty = y(t);
      final isZero = t.abs() < 1e-9;
      canvas.drawLine(
        Offset(plotRect.left + 1, ty),
        Offset(plotRect.right - 1, ty),
        Paint()
          ..color = isZero ? style.zero : style.grid
          ..strokeWidth = 1,
      );
      if (showAxis) {
        final tp = _text(_lhPkAxisText(t), style.tick);
        tp.paint(canvas, Offset(plotL - 4 - tp.width, ty - tp.height / 2));
      }
    }

    final zeroY = y(0);
    final slot = plotRect.width / n;
    final bw = math.min(maxBar, slot * 0.58);
    for (var i = 0; i < n; i++) {
      final cx = plotRect.left + slot * (i + 0.5);
      final v = values[i];
      final strong = winner == i;
      if (v == null) {
        if (showCaps) {
          final tp = _text('—', style.cap.copyWith(fontSize: capSize));
          tp.paint(canvas, Offset(cx - tp.width / 2, zeroY - 13));
        }
        continue;
      }
      final yv = y(v);
      final neg = v < 0;
      final t = math.min(yv, zeroY);
      final h = math.max((yv - zeroY).abs(), 1.5);
      final rect = Rect.fromLTWH(cx - bw / 2, t, bw, h);
      const r = Radius.circular(3);
      final rr = neg
          ? RRect.fromRectAndCorners(rect, bottomLeft: r, bottomRight: r)
          : RRect.fromRectAndCorners(rect, topLeft: r, topRight: r);
      final color = colors[i % colors.length];
      if (strong || winner == null) {
        canvas.drawRRect(rr, Paint()..color = color);
      } else {
        // 输的一方：同色 45° 斜线 + 同色细边
        canvas.save();
        canvas.clipRRect(rr);
        canvas.drawRect(rect, Paint()..color = style.hatchBg);
        final hatch = Paint()
          ..color = color
          ..strokeWidth = 1.4;
        for (var x = rect.left - rect.height; x < rect.right; x += 4.2) {
          canvas.drawLine(
            Offset(x, rect.bottom),
            Offset(x + rect.height, rect.top),
            hatch,
          );
        }
        canvas.restore();
        canvas.drawRRect(
          rr.deflate(0.5),
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      if (showCaps && i < caps.length) {
        final st = (strong ? style.capStrong : style.cap).copyWith(
          fontSize: capSize,
        );
        final tp = _text(caps[i], st);
        final capY = neg ? t + h + 3 : t - 3 - tp.height;
        tp.paint(canvas, Offset(cx - tp.width / 2, capY));
      }
    }
    // 细框最后画，压住柱子底边
    canvas.drawRRect(
      frame.deflate(0.5),
      Paint()
        ..color = style.frame
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_LhPkColumnsPainter old) =>
      old.winner != winner ||
      old.capSize != capSize ||
      old.style.plot != style.plot ||
      !_sameList(old.values, values) ||
      !_sameList(old.caps, caps) ||
      !_sameList(old.colors, colors);

  static bool _sameList<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 柱下名字怎么排：横排放得下就横排；放不下先缩字（最小 8）；还不行斜 38°。
class _LhPkLabelLayout {
  _LhPkLabelLayout(this.painters, this.rotate, this.height, this.slot);

  final List<TextPainter> painters;
  final bool rotate;
  final double height;
  final double slot;

  static const double angle = -38 * math.pi / 180;

  static _LhPkLabelLayout fit(
    List<String> names,
    TextStyle base,
    double slot,
    TextDirection dir,
  ) {
    List<TextPainter> lay(double size) => [
      for (final s in names)
        TextPainter(
          text: TextSpan(text: s, style: base.copyWith(fontSize: size)),
          textDirection: dir,
          maxLines: 1,
        )..layout(),
    ];
    double widest(List<TextPainter> ps) =>
        ps.fold<double>(0, (a, p) => math.max(a, p.width));
    final room = slot - 4;
    var ps = lay(10);
    if (widest(ps) <= room) return _LhPkLabelLayout(ps, false, 20, slot);
    final shrink = 10 * room / widest(ps);
    if (shrink >= 8) {
      ps = lay(shrink);
      if (widest(ps) <= room) return _LhPkLabelLayout(ps, false, 20, slot);
    }
    ps = lay(9);
    final w = widest(ps);
    final h = ps.isEmpty ? 0.0 : ps.first.height;
    final rotated = w * math.sin(-angle) + h * math.cos(-angle) + 8;
    return _LhPkLabelLayout(ps, true, rotated.ceilToDouble(), slot);
  }
}

class _LhPkLabelsPainter extends CustomPainter {
  _LhPkLabelsPainter({required this.layout, required this.axisWidth});
  final _LhPkLabelLayout layout;
  final double axisWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final n = layout.painters.length;
    if (n == 0) return;
    final slot = (size.width - axisWidth) / n;
    for (var i = 0; i < n; i++) {
      final tp = layout.painters[i];
      final cx = axisWidth + slot * (i + 0.5);
      if (!layout.rotate) {
        tp.paint(canvas, Offset(cx - tp.width / 2, 5));
        continue;
      }
      // 斜排：右上角钉在柱子正下方，往左下斜
      canvas.save();
      canvas.translate(cx + 2, 5);
      canvas.rotate(_LhPkLabelLayout.angle);
      tp.paint(canvas, Offset(-tp.width, 0));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_LhPkLabelsPainter old) =>
      old.layout != layout || old.axisWidth != axisWidth;
}

/// 分组里的图怎么排：一行一张（手机、宽屏都一样）。
class LhPkChartGrid extends StatelessWidget {
  const LhPkChartGrid({super.key, required this.cards, required this.sides});
  final List<Widget> cards;

  /// 参赛方个数：越多每张图越宽。
  final int sides;

  static int columnsFor(double width, int sides) => 1;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final cols = columnsFor(box.maxWidth, sides);
      const gap = 8.0;
      final rows = <Widget>[];
      for (var i = 0; i < cards.length; i += cols) {
        final chunk = cards.sublist(i, math.min(i + cols, cards.length));
        final fill = cols == 2 && chunk.length == 1;
        rows.add(
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < (fill ? 1 : cols); j++) ...[
                  if (j > 0) const SizedBox(width: gap),
                  Expanded(
                    child: j < chunk.length ? chunk[j] : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        );
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    },
  );
}

// ── 参赛小签 / 添加 / 挑选行 / 分类胶囊 ─────────────────────────────────
/// 一个参赛方：色块 + 名字（写全）+ ×。
class LhPkChip extends StatelessWidget {
  const LhPkChip({
    super.key,
    required this.name,
    required this.color,
    this.onRemove,
  });
  final String name;
  final Color color;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Container(
    height: 30,
    padding: EdgeInsets.only(left: 10, right: onRemove == null ? 10 : 2),
    decoration: BoxDecoration(
      color: DunesColors.resolve(
        context,
        const Color(0xFFFBFAFD),
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(
        color: DunesColors.resolve(
          context,
          const Color(0xFFE6E2EE),
          role: DunesColorRole.border,
        ),
        width: 0.8,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          name,
          style: LhTypography.sans(
            context: context,
            size: 12.5,
            color: DunesColors.resolve(context, LhColors.ink),
            weight: FontWeight.w600,
            height: 1.0,
          ),
        ),
        if (onRemove != null)
          Semantics(
            button: true,
            label: '移出 $name',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: SizedBox.square(
                dimension: 26,
                child: Icon(
                  Icons.close_rounded,
                  size: 12,
                  color: DunesColors.resolve(context, lhPkGrey),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// 虚线小签「+ 添加…」。
class LhPkAddChip extends StatelessWidget {
  const LhPkAddChip({
    super.key,
    required this.label,
    required this.onTap,
    this.active = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CustomPaint(
        painter: _LhPkDashedPillPainter(
          color: DunesColors.resolve(
            context,
            active ? const Color(0xFF7B5CD8) : const Color(0xFFCFC5E6),
            role: DunesColorRole.border,
          ),
          fill: DunesColors.resolve(
            context,
            active ? const Color(0xFFF3EEFC) : Colors.white,
            role: DunesColorRole.surface,
          ),
        ),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.keyboard_arrow_up_rounded : Icons.add_rounded,
                size: 14,
                color: DunesColors.resolve(context, const Color(0xFF7B5CD8)),
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: LhTypography.sans(
                  context: context,
                  size: 12,
                  color: DunesColors.resolve(context, const Color(0xFF5A458F)),
                  weight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LhPkDashedPillPainter extends CustomPainter {
  _LhPkDashedPillPainter({required this.color, required this.fill});
  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.drawRRect(rr, Paint()..color = fill);
    final path = Path()..addRRect(rr.deflate(0.5));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 3.5, m.length)), paint);
        d += 6;
      }
    }
  }

  @override
  bool shouldRepaint(_LhPkDashedPillPainter old) =>
      old.color != color || old.fill != fill;
}

/// 挑选面板里的一行（跟账本行同一套）：排名 / 名字 + 分类 / 销售额 / 利润 / 勾。
class LhPkPickRow extends StatelessWidget {
  const LhPkPickRow({
    super.key,
    required this.rank,
    required this.entity,
    required this.color,
    required this.onTap,
  });

  final int rank;
  final LhPkEntity entity;

  /// 已在对比里 = 它的颜色；不在 = null。
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Color c(Color x) => DunesColors.resolve(context, x);
    final on = color != null;
    final sales = lhPkMoneyParts(entity.v('sales'));
    final profit = lhPkMoneyParts(entity.v('profit'));
    Widget stat(String label, String value) => SizedBox(
      width: 74,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: LhTypography.sans(
              context: context,
              size: 9,
              color: c(LhColors.mute2),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: LhTypography.sans(
                context: context,
                size: 11.5,
                color: c(LhColors.ink),
                weight: FontWeight.w700,
                height: 1.1,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: on,
      label: entity.name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              on ? const Color(0xFFFBFAFD) : Colors.white,
              role: DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                const Color(0xFFECE8F3),
                role: DunesColorRole.border,
              ),
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  rank.toString().padLeft(2, '0'),
                  style: LhTypography.mono(
                    context: context,
                    size: 10,
                    color: c(const Color(0xFF7B5CD8)),
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entity.name,
                      style: LhTypography.sans(
                        context: context,
                        size: 12.5,
                        color: c(LhColors.ink),
                        weight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    if (entity.sub.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        entity.sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LhTypography.sans(
                          context: context,
                          size: 9.5,
                          color: c(LhColors.mute),
                          height: 1.1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              stat('销售额', '${sales.n}${sales.u}'),
              stat('利润', '${profit.n}${profit.u}'),
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on
                      ? color
                      : DunesColors.resolve(
                          context,
                          Colors.white,
                          role: DunesColorRole.surface,
                        ),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: on ? color! : c(const Color(0xFFC9C3D4)),
                    width: 1,
                  ),
                ),
                child: on
                    ? const Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「比分类」开着时的分类胶囊：选中的带色块。
class LhPkMarkedPill extends StatelessWidget {
  const LhPkMarkedPill({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;

  /// 选中 = 它的颜色；没选 = null。
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final on = color != null;
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: DunesColors.resolve(
                  context,
                  const Color(0xFFFBFAFD),
                  role: DunesColorRole.surface,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: on
                      ? color!
                      : DunesColors.resolve(
                          context,
                          const Color(0xFFE6E2EE),
                          role: DunesColorRole.border,
                        ),
                  width: on ? 1 : 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (on) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: LhTypography.sans(
                      context: context,
                      size: 12,
                      color: DunesColors.resolve(
                        context,
                        on ? LhColors.ink : LhColors.ink2,
                      ),
                      weight: on ? FontWeight.w700 : FontWeight.w500,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 综合：一张淡灰细线表，所有分组的指标一次看完 ──────────────────────
/// 表里的一行：分组标题行（[title] 非空）或指标行。
class LhPkTableRow {
  const LhPkTableRow.head(this.title)
    : label = '',
      sub = '',
      rule = '',
      cells = const <String>[],
      winner = null,
      lastInBlock = true,
      tips = const <String>[];

  const LhPkTableRow.metric({
    required this.label,
    this.sub = '',
    this.rule = '',
    required this.cells,
    this.winner,
    this.lastInBlock = true,
    this.tips = const <String>[],
  }) : title = '';

  final String title;
  final String label;

  /// 日周月季年时的「今日 / 本周…」，时点数写「时点」。
  final String sub;
  final String rule;
  final List<String> cells;
  final int? winner;

  /// 一个指标的最后一行（日周月季年时五行一组）：下面画深一点的线。
  final bool lastInBlock;
  final List<String> tips;

  bool get isHead => title.isNotEmpty;

  /// 转发到 IM 用：只带展示用的字符串，不带原始金额。
  Map<String, dynamic> toJson() => isHead
      ? <String, dynamic>{'h': title}
      : <String, dynamic>{
          'l': label,
          if (sub.isNotEmpty) 's': sub,
          if (rule.isNotEmpty) 'r': rule,
          'c': cells,
          if (winner != null) 'w': winner,
          if (!lastInBlock) 'e': false,
        };

  static LhPkTableRow? fromJson(Map<String, dynamic> raw) {
    final h = raw['h'];
    if (h is String && h.isNotEmpty) return LhPkTableRow.head(h);
    final cells = raw['c'];
    if (cells is! List) return null;
    final w = raw['w'];
    return LhPkTableRow.metric(
      label: raw['l']?.toString() ?? '',
      sub: raw['s']?.toString() ?? '',
      rule: raw['r']?.toString() ?? '',
      cells: [for (final c in cells) c.toString()],
      winner: w is num ? w.toInt() : null,
      lastInBlock: raw['e'] != false,
    );
  }
}

class LhPkSummaryTable extends StatelessWidget {
  const LhPkSummaryTable({
    super.key,
    required this.names,
    required this.colors,
    required this.tints,
    required this.rows,
  });

  final List<String> names;
  final List<Color> colors;
  final List<Color> tints;
  final List<LhPkTableRow> rows;

  static const double labelWidth = 112;
  static const double minCell = 84;
  static const double rowHeight = 30;

  @override
  Widget build(BuildContext context) {
    Color c(Color x) => DunesColors.resolve(context, x);
    Color b(Color x) =>
        DunesColors.resolve(context, x, role: DunesColorRole.border);
    Color s(Color x) =>
        DunesColors.resolve(context, x, role: DunesColorRole.surface);
    final n = names.length;
    final outer = b(const Color(0xFFE3E6EB));
    final vLine = b(const Color(0xFFEEF0F3));
    final rowLine = b(const Color(0xFFECEEF2));
    final subLine = b(const Color(0xFFF4F5F7));
    final mono = LhTypography.mono(
      context: context,
      size: 11,
      color: c(const Color(0xFF3D4653)),
      weight: FontWeight.w500,
      height: 1.0,
    );

    Widget table(double width) {
      final cellW = (width - labelWidth) / math.max(n, 1);
      final header = IntrinsicHeight(
        child: Container(
          decoration: BoxDecoration(
            color: s(const Color(0xFFFAFBFC)),
            border: Border(bottom: BorderSide(color: outer, width: 1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: labelWidth,
                padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
                alignment: Alignment.bottomLeft,
                child: Text(
                  '指标',
                  style: LhTypography.sans(
                    context: context,
                    size: 10,
                    color: c(LhPkFig.mute),
                    weight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              for (var i = 0; i < n; i++)
                Container(
                  width: cellW,
                  padding: const EdgeInsets.fromLTRB(6, 9, 8, 9),
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: vLine, width: 1)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors[i],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      // 名字写全：放不下就换行
                      Flexible(
                        child: Text(
                          names[i],
                          textAlign: TextAlign.right,
                          style: LhTypography.sans(
                            context: context,
                            size: 11,
                            color: c(LhPkFig.ink2),
                            weight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
      final body = <Widget>[];
      for (final r in rows) {
        if (r.isHead) {
          body.add(
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 5),
              decoration: BoxDecoration(
                color: s(const Color(0xFFF5F6F8)),
                border: Border(bottom: BorderSide(color: rowLine, width: 1)),
              ),
              child: Text(
                r.title,
                style: LhTypography.sans(
                  context: context,
                  size: 10,
                  color: c(LhPkFig.mute),
                  weight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ),
          );
          continue;
        }
        body.add(
          Container(
            height: rowHeight,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: r.lastInBlock ? rowLine : subLine,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: labelWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (r.label.isNotEmpty)
                            TextSpan(
                              text: r.label,
                              style: LhTypography.sans(
                                context: context,
                                size: 11.5,
                                color: c(LhPkFig.ink2),
                                weight: FontWeight.w600,
                              ),
                            ),
                          if (r.sub.isNotEmpty)
                            TextSpan(
                              text: r.label.isEmpty ? r.sub : ' ${r.sub}',
                              style: LhTypography.sans(
                                context: context,
                                size: 9.5,
                                color: c(LhPkFig.mute),
                              ),
                            ),
                          if (r.rule.isNotEmpty)
                            TextSpan(
                              text: ' ${r.rule}',
                              style: LhTypography.sans(
                                context: context,
                                size: 8.5,
                                color: c(const Color(0xFFA9B2BE)),
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
                for (var i = 0; i < n; i++)
                  _lhPkMaybeTip(
                    i < r.tips.length ? r.tips[i] : '',
                    Container(
                      width: cellW,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      alignment: Alignment.centerRight,
                      decoration: BoxDecoration(
                        color: r.winner == i
                            ? s(tints[i % tints.length])
                            : Colors.transparent,
                        border: Border(
                          left: BorderSide(color: vLine, width: 1),
                        ),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          i < r.cells.length ? r.cells[i] : '—',
                          maxLines: 1,
                          style: r.winner == i
                              ? mono.copyWith(
                                  color: c(LhPkFig.ink),
                                  fontWeight: FontWeight.w700,
                                )
                              : mono,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
      return SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, ...body],
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s(Colors.white),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: outer, width: 1),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final need = labelWidth + minCell * n;
          if (box.maxWidth >= need) return table(box.maxWidth);
          // 参赛方多了：左右滑
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table(need),
          );
        },
      ),
    );
  }
}

Widget _lhPkMaybeTip(String tip, Widget child) =>
    tip.isEmpty ? child : Tooltip(message: tip, child: child);

/// IM 里的 PK 卡片（转发确认框里的预览也用它）：标题 + 参赛小签 + 综合表；
/// 行多时先收起，点「展开全部」看完。
class LhPkSharedCardView extends StatefulWidget {
  const LhPkSharedCardView({
    super.key,
    required this.data,
    this.collapsedRows = 14,
  });

  final LighthouseSharedCardData data;
  final int collapsedRows;

  @override
  State<LhPkSharedCardView> createState() => _LhPkSharedCardViewState();
}

class _LhPkSharedCardViewState extends State<LhPkSharedCardView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    Color c(Color x) => DunesColors.resolve(context, x);
    final d = widget.data;
    final names = d.pkNames;
    final idx = d.pkColors;
    final colors = [
      for (var i = 0; i < names.length; i++)
        lhPkColorAt(i < idx.length ? idx[i] : null),
    ];
    final tints = [
      for (var i = 0; i < names.length; i++)
        lhPkTintAt(i < idx.length ? idx[i] : null),
    ];
    final rows = <LhPkTableRow>[
      for (final r in d.pkRows)
        if (LhPkTableRow.fromJson(r) case final row?) row,
    ];
    var cut = rows.length;
    if (!_expanded && rows.length > widget.collapsedRows) {
      cut = widget.collapsedRows;
      // 别停在一条分组标题上
      while (cut > 1 && rows[cut - 1].isHead) {
        cut--;
      }
    }
    final shown = rows.sublist(0, cut);
    final hidden = rows.length - cut;
    return Container(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  d.title,
                  style: LhTypography.sans(
                    context: context,
                    size: 14,
                    color: c(LhColors.ink),
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                d.pkMode == 'cross' ? '综合 · 日周月季年' : '综合 · 本期对比',
                style: LhTypography.sans(
                  context: context,
                  size: 10.5,
                  color: c(LhColors.mute2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < names.length; i++)
                LhPkChip(name: names[i], color: colors[i]),
            ],
          ),
          const SizedBox(height: 10),
          LhPkSummaryTable(
            names: names,
            colors: colors,
            tints: tints,
            rows: shown,
          ),
          if (hidden > 0 || _expanded && rows.length > widget.collapsedRows)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _expanded ? '收起' : '展开全部（还有 $hidden 行）',
                      style: LhTypography.sans(
                        context: context,
                        size: 11,
                        color: c(const Color(0xFF7B5CD8)),
                        weight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 15,
                      color: c(const Color(0xFF7B5CD8)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
