// ignore_for_file: lines_longer_than_80_chars
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../auth/auth_session.dart';
import '../conversation/comm_unread_notifier.dart';
import '../shell/dunes_main_tab_bar.dart';
import '../workbench/workbench_badge_notifier.dart';
import 'lighthouse_data.dart';
import 'lighthouse_service.dart';
import 'lighthouse_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Static period data (mirrors PERIOD_DATA in lighthouse_v13.html)
// ─────────────────────────────────────────────────────────────────────────────
class _PeriodInfo {
  const _PeriodInfo({
    required this.label,
    required this.short,
    required this.salesV,
    required this.salesU,
    required this.deltaDir,
    required this.deltaVal,
    required this.deltaVs,
    required this.hasDelta,
    required this.profitV,
    required this.profitU,
    required this.gmvV,
    required this.gmvU,
    required this.rate,
    required this.compose,
  });

  final String label;
  final String short;
  final double salesV;
  final String salesU;
  final String deltaDir;
  final double deltaVal;
  final String deltaVs;
  final bool hasDelta;
  final double profitV;
  final String profitU;
  final double gmvV;
  final String gmvU;
  final double rate;
  final List<_ComposeItem> compose;
}

class _ComposeItem {
  const _ComposeItem({required this.name, required this.pct, required this.color});
  final String name;
  final double pct;
  final Color color;
}

const _kPeriodKeys = ['day', 'week', 'month', 'quarter', 'year'];

// period bar 短标签（纯 UI 文案，非业务数据）
const _kPeriodShort = {
  'day': '日',
  'week': '周',
  'month': '月',
  'quarter': '季',
  'year': '年',
};

const _kPeriodVs = {
  'day': 'vs 昨日',
  'week': 'vs 上周',
  'month': 'vs 上月',
  'quarter': 'vs 上季',
  'year': 'vs 去年同期',
};

// Hero metric cell definitions per tab
class _HeroMetric {
  const _HeroMetric({required this.key, required this.label, required this.isRate, required this.cellColor});
  final String key;
  final String label;
  final bool isRate;
  final Color cellColor;
}

// HUN 行内分类 — primary 算法；颜色/标签读 metrics.ui.hunOptions
class _HunInfo {
  const _HunInfo({required this.u, required this.n, required this.h});
  final double u, n, h;

  bool get hasU => u.abs() > 1e-9;
  bool get hasN => n.abs() > 1e-9;
  bool get hasH => h.abs() > 1e-9;
  bool get hasAny => hasU || hasN || hasH;
  double get total => u + n + h;

  /// 主标签：U / N / H / mixed / none
  /// 规则：H 有数据时优先；否则看 U:N，若两者都 ≥30% 总额则为 mixed，否则取较大那个。
  String get primary {
    if (!hasAny) return 'none';
    if (hasH && h >= u && h >= n) return 'H';
    final t = u + n;
    if (t <= 0) return hasH ? 'H' : 'none';
    final uShare = u / t;
    if (hasU && hasN && uShare > 0.30 && uShare < 0.70) return 'mixed';
    return u >= n ? 'U' : 'N';
  }
}

Color _lhColorFromKey(String? key) {
  switch (key) {
    case 'pos':
      return LhColors.pos;
    case 'neg':
      return LhColors.neg;
    case 'product':
      return LhColors.product;
    case 'copper':
      return LhColors.copper;
    case 'cnpc':
      return LhColors.cnpc;
    case 'pingan':
      return LhColors.pingan;
    case 'ink2':
      return LhColors.ink2;
    case 'ink':
      return LhColors.ink;
    default:
      return LhColors.mute;
  }
}

/// 后端尚未返回 metrics.ui 时的本地兜底（与 ui_schema.go 保持一致）。
Map<String, dynamic> _fallbackUiRoot() {
  Map<String, dynamic> metric(String key, String label, String short, String colorKey, {bool listDefault = true, bool sortable = true, bool hero = false, bool isRate = false}) =>
      {'key': key, 'label': label, 'short': short, 'colorKey': colorKey, 'listDefault': listDefault, 'sortable': sortable, 'hero': hero, 'isRate': isRate};

  final hunOptions = [
    {'value': '全部', 'label': '全部', 'colorKey': 'ink', 'match': '', 'cubeValue': '全部'},
    {'value': 'U', 'label': 'U', 'colorKey': 'product', 'match': 'U', 'cubeValue': 'U', 'badge': 'U'},
    {'value': 'N', 'label': 'N', 'colorKey': 'copper', 'match': 'N', 'cubeValue': 'N', 'badge': 'N'},
    {'value': '混合', 'label': '混合', 'colorKey': 'ink2', 'match': 'mixed', 'cubeValue': 'mixed', 'badge': 'U·N'},
    {'value': 'H', 'label': 'H', 'colorKey': 'mute2', 'match': 'H', 'cubeValue': 'H', 'badge': 'H'},
  ];

  Map<String, dynamic> tab(String name, List<Map<String, dynamic>> metrics, List<String> defaultMetrics, List<String> heroMetrics, {List<String>? categories, List<Map<String, dynamic>>? filters}) => {
        'metrics': metrics,
        'defaultMetrics': defaultMetrics,
        if (categories != null) 'categories': categories,
        if (filters != null) 'filters': filters,
        'heroMetrics': heroMetrics,
      };

  return {
    'tabs': {
      'product': tab(
        'product',
        [
          metric('sales', '销售额', '销售', 'pingan'),
          metric('gmv', '引流GMV', '引流', 'product'),
          metric('gmv2', 'GMV', 'GMV', 'product'),
          metric('its', 'ITS', 'ITS', 'mute'),
          metric('itsAfter', '折后ITS', '折ITS', 'mute'),
          metric('spread', '利差', '利差', 'copper'),
          metric('woa', 'WOA', 'WOA', 'mute'),
          metric('revenue', '收入', '收入', 'cnpc'),
          metric('totalCost', '成本', '成本', 'neg'),
          metric('cost', '业务成本', '业务', 'neg'),
          metric('tax', '税务成本', '税务', 'mute'),
          metric('profit', '毛利润', '毛利', 'pos', listDefault: false, hero: true),
          metric('rate', '毛利率', '毛利率', 'copper', listDefault: false, hero: true, isRate: true),
        ],
        ['sales', 'gmv', 'gmv2', 'its', 'itsAfter', 'spread', 'woa', 'revenue', 'totalCost', 'cost', 'tax'],
        ['profit', 'gmv', 'rate', 'revenue', 'cost', 'tax'],
        categories: ['全部', '能源', '出行', '运营商', 'Fintech'],
      ),
      'supply': tab(
        'supply',
        [
          metric('sales', '销售额', '销售', 'pingan'),
          metric('gmv', '引流GMV', '引流', 'product'),
          metric('cost', '业务成本', '业务', 'neg'),
          metric('tax', '税务成本', '税务', 'mute'),
          metric('spread', '利差', '利差', 'copper'),
          metric('saasFee', 'SAAS服务费', 'SAAS', 'mute'),
          metric('woa', 'WOA', 'WOA', 'mute'),
          metric('projectCost', '项目成本', '项目', 'mute'),
          metric('deferred', '抵扣延期分润', '延期', 'mute'),
          metric('discount', '折扣返点', '折扣', 'copper', sortable: false),
          metric('profit', '毛利润', '毛利', 'pos', listDefault: false, hero: true),
          metric('rate', '毛利率', '毛利率', 'copper', listDefault: false, hero: true, isRate: true),
        ],
        ['sales', 'gmv', 'cost', 'tax', 'spread', 'saasFee', 'woa', 'projectCost', 'deferred', 'discount'],
        ['sales', 'revenue', 'cost', 'profit', 'rate'],
        filters: [
          {'key': 'fuel', 'label': '筛选', 'options': [{'value': '全部', 'label': '全部'}, {'value': '汽油', 'label': '汽油'}]},
          {'key': 'hun', 'label': 'U/N', 'options': hunOptions},
        ],
      ),
      'channel': tab(
        'channel',
        [
          metric('sales', '销售额', '销售', 'pingan'),
          metric('gmv', '引流GMV', '引流', 'product'),
          metric('cost', '业务成本', '业务', 'neg'),
          metric('tax', '税务成本', '税务', 'mute'),
          metric('spread', '利差', '利差', 'copper'),
          metric('saasFee', 'SAAS服务费', 'SAAS', 'mute'),
          metric('woa', 'WOA', 'WOA', 'mute'),
          metric('projectCost', '项目成本', '项目', 'mute'),
          metric('deferred', '抵扣延期分润', '延期', 'mute'),
          metric('profit', '毛利润', '毛利', 'pos', listDefault: false, hero: true),
          metric('rate', '毛利率', '毛利率', 'copper', listDefault: false, hero: true, isRate: true),
        ],
        ['sales', 'gmv', 'cost', 'tax', 'spread', 'saasFee', 'woa', 'projectCost', 'deferred'],
        ['profit', 'revenue', 'cost', 'rate'],
        filters: [
          {'key': 'hun', 'label': 'U/N', 'options': hunOptions},
        ],
      ),
    },
    'defaultSort': {'field': 'profit', 'desc': true},
    'resetMetrics': ['sales', 'cost', 'gmv'],
    'resetSort': {'field': 'sales', 'desc': true},
    'hunOptions': hunOptions,
    'cubeFilters': [
      {'key': 'product', 'label': '产品'},
      {'key': 'supply', 'label': '供给'},
      {'key': 'supplyHun', 'label': '供U/N', 'hun': true},
      {'key': 'channel', 'label': '渠道'},
      {'key': 'channelHun', 'label': '渠U/N', 'hun': true},
    ],
  };
}

// Category groups: loaded from backend metrics.ui (see _categoryOptions).
List<String> _getGroups(String tab, List<Map<String, dynamic>> rows, {List<String>? override}) {
  if (override != null && override.isNotEmpty) return override;
  final groups = <String>{'全部'};
  for (final r in rows) {
    final g = r['group']?.toString();
    if (g != null && g.isNotEmpty) groups.add(g);
  }
  final list = groups.toList();
  list.sort((a, b) {
    if (a == '全部') return -1;
    if (b == '全部') return 1;
    return a.compareTo(b);
  });
  return list;
}

// Formatting
String _fmt(double n) {
  final abs = n.abs();
  if (abs >= 1e8) return (n / 1e8).toStringAsFixed(2);
  if (abs >= 1e4) return (n / 1e4).toStringAsFixed(2);
  return n.toStringAsFixed(abs < 0.01 ? 2 : (abs < 1 ? 2 : 1));
}

String _unit(double n) {
  final abs = n.abs();
  if (abs >= 1e8) return '亿';
  if (abs >= 1e4) return '万';
  return '';
}

/// 实收返点率（‰）: 2.0 → '2‰'，2.5 → '2.5‰'，null → '—'
String _fmtPermille(double? r) {
  if (r == null) return '—';
  if (r == r.truncate()) return '${r.toInt()}‰';
  return '${r.toStringAsFixed(1)}‰';
}

// Group tag background + foreground colors (centralised — used by main list & detail list)
({Color bg, Color fg}) _groupTagColors(String group) {
  switch (lhGroupTagClass(group)) {
    case 'cnpc':    return (bg: const Color(0x14A33A2A), fg: LhColors.cnpc);
    case 'sinopec': return (bg: const Color(0x191F6B4A), fg: LhColors.sinopec);
    case 'private': return (bg: const Color(0x194A8A7B), fg: LhColors.private);
    case 'carrier': return (bg: const Color(0x145B47E8), fg: LhColors.carrier);
    case 'pingan':  return (bg: const Color(0x145B47E8), fg: LhColors.pingan);
    case 'dict':    return (bg: const Color(0x1AC9842A), fg: LhColors.dict);
    case 'multi':   return (bg: const Color(0x1A7A6CC4), fg: LhColors.multi);
    default:        return (bg: const Color(0x1E9A968F), fg: LhColors.unk);
  }
}

// period bar / 趋势卡标题（纯 UI 文案，非业务数据）
const _kPeriodTitle = {
  'day': '近 24 小时趋势',
  'week': '本周趋势',
  'month': '近 30 日趋势',
  'quarter': '本季趋势',
  'year': '近 12 个月趋势',
};

// ─────────────────────────────────────────────────────────────────────────────
// Trend chart — 3-series (收入/成本/毛利), period-aware, tap+drag to locate
// Performance: data + bounds cached in State; lines painter is RepaintBoundary'd
// so drag only repaints the cheap overlay (dashed guideline + 3 markers).
// ─────────────────────────────────────────────────────────────────────────────
class _TrendSeries {
  const _TrendSeries({required this.revenue, required this.cost, required this.profit});
  final List<double> revenue;
  final List<double> cost;
  final List<double> profit;
}


// ============================================================================
// 折扣与返点 — supply 行级 discount：底表金额 + 规则表类型/档位
// ============================================================================

class _DiscountRow {
  const _DiscountRow({
    required this.province,
    required this.cur,
    required this.rebate,
    this.effectivePermille,
    this.ruleType,
    this.base,
    this.mode,
    this.contractRate,
    this.tierLabel,
    this.tierCount,
    this.nextRate,
    this.progress,
    this.gapToNext,
    this.status,
  });

  final String province;
  final double cur;
  final double rebate;
  final double? effectivePermille;
  final String? ruleType;
  final String? base;
  final String? mode;
  final double? contractRate;
  final String? tierLabel;
  final int? tierCount;
  final double? nextRate;
  final double? progress;
  final double? gapToNext;
  final String? status;

  bool get isFixed => ruleType == '固定' || status == 'fixed';
  bool get isLadder => ruleType == '月阶梯' || ruleType == '年阶梯';
  bool get hasNext => nextRate != null && gapToNext != null && gapToNext! > 0;

  static _DiscountRow? fromApi(Map<String, dynamic> d, String supplyName) {
    final cur = (d['currentCumSales'] as num?)?.toDouble() ??
        (d['cur'] as num?)?.toDouble();
    if (cur == null || cur <= 0) return null;

    final rebate = (d['rebate'] as num?)?.toDouble() ??
        (d['estimated_rebate'] as num?)?.toDouble() ??
        0.0;
    final effectivePermille = (d['effectivePermille'] as num?)?.toDouble();
    final contractRate = (d['contractRatePermille'] as num?)?.toDouble() ??
        (d['currentTier'] as num?)?.toDouble() ??
        (d['curRate'] as num?)?.toDouble();
    final nextRate = (d['nextTier'] as num?)?.toDouble() ??
        (d['nextRate'] as num?)?.toDouble();
    final gapToNext = (d['salesToNextTier'] as num?)?.toDouble() ??
        (d['gap_to_next'] as num?)?.toDouble();
    final progress = (d['currentProgress'] as num?)?.toDouble();

    final province = d['province']?.toString().trim().isNotEmpty == true
        ? d['province'].toString()
        : supplyName.replaceAll(RegExp(r'省$|市$'), '');

    return _DiscountRow(
      province: province,
      cur: cur,
      rebate: rebate,
      effectivePermille: effectivePermille ??
          (rebate > 0 ? rebate / cur * 1000 : null),
      ruleType: d['ruleType']?.toString() ?? d['rule_type']?.toString(),
      base: d['base']?.toString(),
      mode: d['mode']?.toString(),
      contractRate: contractRate,
      tierLabel: d['tierLabel']?.toString(),
      tierCount: (d['tierCount'] as num?)?.toInt(),
      nextRate: nextRate,
      progress: progress,
      gapToNext: gapToNext,
      status: d['status']?.toString(),
    );
  }
}

Color _discountTypeColor(_DiscountRow r) {
  switch (r.ruleType) {
    case '固定':
      return LhColors.copper;
    case '月阶梯':
      return LhColors.cnpc;
    case '年阶梯':
      return LhColors.sinopec;
    default:
      return LhColors.mute;
  }
}

String _discountRateLine(_DiscountRow r) {
  final parts = <String>[];
  if (r.contractRate != null && r.contractRate! > 0) {
    parts.add('合约 ${_fmtPermille(r.contractRate)}');
  }
  if (r.effectivePermille != null) {
    parts.add('实收 ${_fmtPermille(r.effectivePermille)}');
  }
  return parts.isEmpty ? '—' : parts.join(' · ');
}

class _SeriesRange {
  const _SeriesRange(this.min, this.max);
  final double min;
  final double max;
  double get span {
    final s = max - min;
    return s.abs() < 1e-9 ? 1.0 : s;
  }
}

class _TrendBounds {
  const _TrendBounds(this.revenue, this.cost, this.profit);
  final _SeriesRange revenue;
  final _SeriesRange cost;
  final _SeriesRange profit;
}

_TrendBounds _computeBounds(_TrendSeries s) {
  _SeriesRange computeOne(List<double> v) {
    if (v.isEmpty) return const _SeriesRange(0, 1);
    double mn = v.reduce(math.min);
    double mx = v.reduce(math.max);
    final span = mx - mn;
    if (span.abs() < 1e-9) {
      // 所有点相等，扩展上下各 10% (或至少 1) 让线居中
      final pad = math.max(mx.abs() * 0.1, 1.0);
      return _SeriesRange(mn - pad, mx + pad);
    }
    // 上下各 8% padding 防贴边
    final pad = span * 0.08;
    return _SeriesRange(mn - pad, mx + pad);
  }
  return _TrendBounds(
    computeOne(s.revenue),
    computeOne(s.cost),
    computeOne(s.profit),
  );
}

// ── Lines painter (heavy, but RepaintBoundary'd; only repaints on data change) ─
class _TrendLinesPainter extends CustomPainter {
  const _TrendLinesPainter({
    required this.series,
    required this.bounds,
    required this.colors,
    required this.padH,
  });
  final _TrendSeries series;
  final _TrendBounds bounds;
  final List<Color> colors;
  final double padH;

  @override
  void paint(Canvas canvas, Size size) {
    const padTop = 8.0;
    const padBottom = 6.0;
    final usableH = size.height - padTop - padBottom;
    final usableW = size.width - padH * 2;
    final n = series.revenue.length;
    final step = n <= 1 ? 0.0 : usableW / (n - 1);

    double xOf(int i) => padH + i * step;
    double yOf(double v, _SeriesRange r) =>
        padTop + (r.max - v) / r.span * usableH;

    // 水平网格 4 条 (chart 高度等分,独立于数据)
    final gridPaint = Paint()
      ..color = LhColors.line2
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    for (int i = 0; i <= 3; i++) {
      final y = padTop + usableH * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    void drawLine(List<double> pts, Color color, _SeriesRange range) {
      if (pts.length < 2) return;
      final path = Path()..moveTo(xOf(0), yOf(pts[0], range));
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(xOf(i), yOf(pts[i], range));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    drawLine(series.revenue, colors[0], bounds.revenue);
    drawLine(series.cost, colors[1], bounds.cost);
    drawLine(series.profit, colors[2], bounds.profit);
  }

  @override
  bool shouldRepaint(_TrendLinesPainter old) =>
      !identical(old.series, series) ||
      !identical(old.bounds, bounds) ||
      old.padH != padH ||
      !identical(old.colors, colors);
}

// ── Overlay painter (light; runs every drag frame) ───────────────────────────
class _TrendOverlayPainter extends CustomPainter {
  const _TrendOverlayPainter({
    required this.series,
    required this.bounds,
    required this.colors,
    required this.padH,
    required this.selectedIndex,
  });
  final _TrendSeries series;
  final _TrendBounds bounds;
  final List<Color> colors;
  final double padH;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final si = selectedIndex;
    if (si == null) return;
    final n = series.revenue.length;
    if (si < 0 || si >= n) return;

    const padTop = 8.0;
    const padBottom = 6.0;
    final usableH = size.height - padTop - padBottom;
    final usableW = size.width - padH * 2;
    final step = n <= 1 ? 0.0 : usableW / (n - 1);

    final x = padH + si * step;
    double yOf(double v, _SeriesRange r) =>
        padTop + (r.max - v) / r.span * usableH;

    final dashPaint = Paint()
      ..color = LhColors.ink2.withAlpha(140)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke;
    const dashH = 3.0;
    const dashGap = 2.0;
    final yEnd = padTop + usableH;
    double y = padTop;
    while (y < yEnd) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + dashH, yEnd)),
        dashPaint,
      );
      y += dashH + dashGap;
    }

    void marker(double v, Color color, _SeriesRange range) {
      final cy = yOf(v, range);
      canvas.drawCircle(Offset(x, cy), 4.0, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(x, cy),
        4.0,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      canvas.drawCircle(Offset(x, cy), 1.8, Paint()..color = color);
    }

    marker(series.revenue[si], colors[0], bounds.revenue);
    marker(series.cost[si], colors[1], bounds.cost);
    marker(series.profit[si], colors[2], bounds.profit);
  }

  @override
  bool shouldRepaint(_TrendOverlayPainter old) =>
      old.selectedIndex != selectedIndex ||
      !identical(old.series, series) ||
      !identical(old.bounds, bounds) ||
      old.padH != padH;
}

// ── The widget ────────────────────────────────────────────────────────────────
class _TrendChart extends StatefulWidget {
  const _TrendChart({
    required this.labels,
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.rangeLabel,
    required this.title,
    this.showHeader = true,
  });

  final List<String> labels; // 每个点的完整标签（X 轴 / tooltip）
  final List<double> revenue;
  final List<double> cost;
  final List<double> profit;
  final String rangeLabel;
  final String title;
  final bool showHeader;

  @override
  State<_TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<_TrendChart> {
  static const double _kChartPadH = 6.0;
  static const Color _cRev = LhColors.product;
  static const Color _cCost = LhColors.neg;
  static const Color _cProf = LhColors.pos;
  static const List<Color> _kColors = [_cRev, _cCost, _cProf];

  int? _selectedIndex;
  late _TrendSeries _series;
  late _TrendBounds _bounds;
  late List<String> _pointLabels;
  late List<String> _xLabels;
  late List<int> _xAnchors;
  double _totRev = 0, _totCost = 0, _totProf = 0;

  int get _n => _series.profit.length;

  @override
  void initState() {
    super.initState();
    _recompute();
  }

  @override
  void didUpdateWidget(_TrendChart old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.profit, widget.profit) ||
        !listEquals(old.revenue, widget.revenue) ||
        !listEquals(old.cost, widget.cost) ||
        !listEquals(old.labels, widget.labels)) {
      _recompute();
      _selectedIndex = null;
    }
  }

  void _recompute() {
    final n = [widget.revenue.length, widget.cost.length, widget.profit.length]
        .fold<int>(0, math.max);
    List<double> pad(List<double> l) =>
        l.length == n ? l : [...l, ...List<double>.filled(n - l.length, 0.0)];
    _series = _TrendSeries(
      revenue: pad(widget.revenue),
      cost: pad(widget.cost),
      profit: pad(widget.profit),
    );
    _bounds = _computeBounds(_series);
    _pointLabels = widget.labels;
    _totRev = _series.revenue.fold(0.0, (a, b) => a + b);
    _totCost = _series.cost.fold(0.0, (a, b) => a + b);
    _totProf = _series.profit.fold(0.0, (a, b) => a + b);
    final (xs, anchors) = _computeSparse(widget.labels, n);
    _xLabels = xs;
    _xAnchors = anchors;
  }

  /// 后端给的是逐点全标签，这里挑最多 5 个均匀锚点作稀疏 X 轴。
  static (List<String>, List<int>) _computeSparse(List<String> labels, int n) {
    final count = labels.length;
    if (count == 0 || n == 0) return (const <String>[], const <int>[]);
    if (count <= 5) {
      return (labels, List<int>.generate(count, (i) => i));
    }
    const want = 5;
    final anchors = <int>[];
    for (int i = 0; i < want; i++) {
      anchors.add((i * (count - 1) / (want - 1)).round());
    }
    return (anchors.map((i) => labels[i]).toList(), anchors);
  }

  void _setSelectionFromX(double localX, double widthPx) {
    final n = _n;
    final usable = widthPx - _kChartPadH * 2;
    if (usable <= 0 || n <= 0) return;
    final relX = (localX - _kChartPadH).clamp(0.0, usable);
    final i = n <= 1 ? 0 : ((relX / usable) * (n - 1)).round().clamp(0, n - 1);
    if (_selectedIndex != i) {
      setState(() => _selectedIndex = i);
    }
  }

  void _clearSelection() {
    if (_selectedIndex != null) setState(() => _selectedIndex = null);
  }

  Widget _legendChip(String label, double value, Color color) {
    final isNeg = value < 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: LhTypography.sans(size: 9, color: LhColors.mute2, weight: FontWeight.w500, letterSpacing: 0.3),
        ),
        const SizedBox(width: 3),
        RichText(
          text: TextSpan(children: [
            if (isNeg)
              TextSpan(text: '-', style: LhTypography.sans(size: 10, weight: FontWeight.w600, color: LhColors.neg, letterSpacing: -0.1)),
            TextSpan(
              text: _fmt(value.abs()),
              style: LhTypography.sans(
                size: 10,
                weight: FontWeight.w600,
                color: isNeg ? LhColors.neg : LhColors.ink2,
                letterSpacing: -0.1,
              ),
            ),
            TextSpan(text: _unit(value.abs()), style: LhTypography.mono(size: 8, color: LhColors.mute, weight: FontWeight.w500)),
          ]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final si = _selectedIndex;
    final isSelected = si != null && si >= 0 && si < _n;

    double at(List<double> l, int i) => (i >= 0 && i < l.length) ? l[i] : 0;
    final rVal = isSelected ? at(_series.revenue, si) : _totRev;
    final cVal = isSelected ? at(_series.cost, si) : _totCost;
    final pVal = isSelected ? at(_series.profit, si) : _totProf;
    final statusText = (isSelected && si < _pointLabels.length)
        ? _pointLabels[si]
        : '本期合计';

    // 顶部 header（稳定 Row 结构：状态 chip + 3 legend + 占位关闭按钮）
    final headerRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? LhColors.ink.withAlpha(13) : Colors.transparent,
            border: Border.all(
              color: isSelected ? LhColors.line : LhColors.line2,
              width: 0.5,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            statusText,
            style: LhTypography.mono(
              size: 9,
              color: isSelected ? LhColors.ink : LhColors.mute,
              weight: FontWeight.w600,
              letterSpacing: isSelected ? 0.4 : 0.8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            spacing: 7,
            runSpacing: 3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _legendChip('收入', rVal, _cRev),
              _legendChip('成本', cVal, _cCost),
              _legendChip('毛利', pVal, _cProf),
            ],
          ),
        ),
        SizedBox(
          width: 15,
          height: 15,
          child: isSelected
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _clearSelection,
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close_rounded, size: 11, color: LhColors.mute2),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(widget.title,
                  style: LhTypography.mono(size: 9.5, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 1.2)),
              Text(widget.rangeLabel,
                  style: LhTypography.mono(size: 9, color: LhColors.mute2, weight: FontWeight.w500, letterSpacing: 0.3)),
            ],
          ),
          const SizedBox(height: 8),
        ],
        headerRow,
        const SizedBox(height: 8),
        // 双 Painter Stack：折线层用 RepaintBoundary 隔离
        LayoutBuilder(builder: (ctx, c) {
          final w = c.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _setSelectionFromX(d.localPosition.dx, w),
            onHorizontalDragStart: (d) => _setSelectionFromX(d.localPosition.dx, w),
            onHorizontalDragUpdate: (d) => _setSelectionFromX(d.localPosition.dx, w),
            child: SizedBox(
              height: 76,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _TrendLinesPainter(
                          series: _series,
                          bounds: _bounds,
                          colors: _kColors,
                          padH: _kChartPadH,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _TrendOverlayPainter(
                        series: _series,
                        bounds: _bounds,
                        colors: _kColors,
                        padH: _kChartPadH,
                        selectedIndex: _selectedIndex,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 4),
        SizedBox(
          height: 14,
          child: LayoutBuilder(builder: (ctx, c) {
            final w = c.maxWidth;
            final usableW = w - _kChartPadH * 2;
            final n = _n;
            return Stack(
              children: [
                for (int i = 0; i < _xAnchors.length; i++)
                  Positioned(
                    left: ((n <= 1 ? _kChartPadH : _kChartPadH + _xAnchors[i] / (n - 1) * usableW) - 14)
                        .clamp(0.0, (w - 28).clamp(0.0, double.infinity)),
                    width: 28,
                    child: Center(
                      child: Text(
                        _xLabels[i],
                        style: LhTypography.mono(size: 8.5, color: LhColors.mute2, weight: FontWeight.w500, letterSpacing: 0.2),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ),
        const SizedBox(height: 4),
        // 固定高度的提示位，避免出现/消失带来跳动
        SizedBox(
          height: 12,
          child: isSelected
              ? const SizedBox.shrink()
              : Text(
                  '拖动查看每点',
                  style: LhTypography.sans(size: 9, color: LhColors.mute2, weight: FontWeight.w500, letterSpacing: 0.4),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main page widget
// ─────────────────────────────────────────────────────────────────────────────
class NativeLighthousePage extends StatefulWidget {
  const NativeLighthousePage({
    super.key,
    required this.session,
    required this.navigation,
    required this.commUnread,
    required this.workbenchBadge,
  });

  final AuthSession session;
  final DunesNavigationController navigation;
  final CommUnreadNotifier commUnread;
  final WorkbenchBadgeNotifier workbenchBadge;

  @override
  State<NativeLighthousePage> createState() => _NativeLighthousePageState();
}

enum _DdMode { none, category, metric, filter, hun }

class _NativeLighthousePageState extends State<NativeLighthousePage> {
  LighthouseDataBundle? _bundle;
  bool _loading = true;
  String? _loadError;

  String _tab = 'product';
  String _period = 'month';
  String _groupFilter = '全部';
  String _supplyFuelFilter = '全部';
  String _hunFilter = '全部'; // '全部' | 'U' | 'N' | 'H' | '混合' — 仅 supply/channel
  final Set<String> _expanded = {};
  bool _discountExpanded = false;
  static const int _discountPreviewCount = 3;

  // 分页 — 每页 15 行，上一页 / 下一页（主列表 + 详情 SKU）
  static const int _pageSize = 15;
  int _listPage = 1;
  int _detailPage = 1;

  // Analysis cube — 懒加载自 /lighthouse/analysis/cube
  _CubeData? _cubeData;
  bool _cubeLoading = false;
  bool _cubeError = false;
  String _cubeCacheKey = '';

  // Cube filters (analysis tab) — 与主应用筛选独立
  String _cubeProductGroup = '全部';
  String _cubeSupplyGroup = '全部';
  String _cubeSupplyHun = '全部';
  String _cubeChannelGroup = '全部';
  String _cubeChannelHun = '全部';
  String? _cubeSelectedKey; // 选中的亮点 'xi-yi-zi'
  String? _cubeSelectedOwner; // 选中的负责人（第四维度）
  /// 当前点开的 cube filter chip（null = 都收起）
  /// 值: 'product' | 'supply' | 'supplyHun' | 'channel' | 'channelHun'
  String? _cubeFilterOpen;

  // ── 3D 视角状态（可旋转/拖动/缩放）─────────────────────────────────────
  //   默认值复刻原 isometric 30° 视角，让初次进入与旧版本一致
  static const double _kCubeDefaultYaw   = math.pi / 6;   // 绕竖直轴
  static const double _kCubeDefaultPitch = math.pi / 6;   // 绕水平轴
  double _cubeYaw   = _kCubeDefaultYaw;
  double _cubePitch = _kCubeDefaultPitch;
  double _cubeScale = 1.0;
  Offset _cubePan = Offset.zero;
  // 手势暂存（onScaleStart → onScaleEnd 期间）
  double _cubeGestureBaseScale = 1.0;
  Offset? _cubeGestureStartFocal;
  Offset? _cubeGestureLastFocal;
  DateTime? _cubeGestureStartTime;
  double _cubeGestureMaxMove = 0;

  // ── 立方体文字显示开关（细粒度，用户自己挑）─────────────────────────
  bool _cubeShowAxisNames = true;       // 产品轴名
  bool _cubeShowProductTicks = true;    // X 轴每个 tick 的产品名
  bool _cubeShowSupplyLabels = false;   // 供给方轴名 + Y 轴刻度名（默认关）
  bool _cubeShowChannelLabels = false;  // 渠道轴名 + Z 轴刻度名（默认关）
  bool _cubeShowOwnerInitials = true;   // owner 质心圆里的首字
  bool _cubeTextPanelOpen = false;      // 文字下拉是否展开
  DateTime? _lastSyncedAt;
  bool _refreshing = false; // 手动点击「数据同步」刷新中
  // ── 周期实例筛选（哪一天 / 哪个周 / 月 / 季 / 年）──
  // 0 = 当前实例（今日/本周/本月/本季/今年），-1 = 上一个，以此类推。
  int _periodOffset = 0;
  bool _periodPickerOpen = false;
  // 点击 hero 小格 → 进入指标分析页（per-metric drill-down）
  String? _metricPageKey;
  String? _detailKey; // non-null when detail view is open
  String? _detailType;
  String _detailSubTab = '';
  String _detailSkuQuery = '';
  final TextEditingController _detailSkuSearchCtrl = TextEditingController();

  // Sort state
  String _sortField = 'profit';
  bool _sortDesc = true;

  // Per-tab selected metrics (labels/keys from backend metrics.ui)
  final Map<String, List<String>> _metrics = {
    'product': <String>[],
    'supply': <String>[],
    'channel': <String>[],
  };

  // Dropdown — per-button GlobalKey so panel anchors to the specific tapped button,
  // not the entire actions row (this was what made it look "乱飞").
  _DdMode _ddMode = _DdMode.none;
  OverlayEntry? _ddEntry;
  final GlobalKey _btnKeyCategory = GlobalKey();
  final GlobalKey _btnKeyMetric = GlobalKey();
  final GlobalKey _btnKeyFilter = GlobalKey();
  final GlobalKey _btnKeyHun = GlobalKey();

  /// Metrics/sort context tab — detail page uses detail type (same as outer tab).
  String get _metricsTab => _detailType ?? _tab;

  bool get _isPageBusy => _loading || _cubeLoading;

  Map<String, dynamic>? get _uiRoot {
    final raw = _bundle?.metrics['ui'];
    if (raw is Map && raw.isNotEmpty) {
      return raw.cast<String, dynamic>();
    }
    if (_bundle != null) return _fallbackUiRoot();
    return null;
  }

  Map<String, dynamic>? _uiTab(String tab) =>
      (_uiRoot?['tabs'] as Map?)?[tab] as Map<String, dynamic>?;

  List<Map<String, dynamic>> _uiMetricDefs(String tab) {
    final raw = _uiTab(tab)?['metrics'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }

  Map<String, Map<String, dynamic>> _uiMetricDefMap(String tab) {
    return {for (final d in _uiMetricDefs(tab)) d['key'] as String: d};
  }

  String _metricLabel(String key, {String tab = ''}) {
    final t = tab.isEmpty ? _metricsTab : tab;
    return _uiMetricDefMap(t)[key]?['label'] as String? ?? key;
  }

  String _metricShort(String key, {String tab = ''}) {
    final t = tab.isEmpty ? _metricsTab : tab;
    return _uiMetricDefMap(t)[key]?['short'] as String? ?? key;
  }

  List<String> _uiDefaultMetrics(String tab) {
    final raw = _uiTab(tab)?['defaultMetrics'];
    if (raw is List) return raw.cast<String>();
    return _uiMetricDefs(tab)
        .where((d) => d['listDefault'] == true)
        .map((d) => d['key'] as String)
        .toList();
  }

  List<String> _uiResetMetrics() {
    final raw = _uiRoot?['resetMetrics'];
    if (raw is List && raw.isNotEmpty) return raw.cast<String>();
    return const ['sales', 'cost', 'gmv'];
  }

  String _uiResetSortField() {
    final reset = _uiRoot?['resetSort'];
    if (reset is Map && reset['field'] is String) return reset['field'] as String;
    return 'sales';
  }

  List<_HeroMetric> _heroMetricsFor(String tab) {
    final order = (_uiTab(tab)?['heroMetrics'] as List?)?.cast<String>() ??
        const ['profit', 'rate'];
    final defs = _uiMetricDefMap(tab);
    final out = <_HeroMetric>[];
    for (final key in order) {
      final d = defs[key];
      if (d == null) continue;
      out.add(_HeroMetric(
        key: key,
        label: d['label'] as String? ?? key,
        isRate: d['isRate'] == true,
        cellColor: _lhColorFromKey(d['colorKey'] as String?),
      ));
    }
    return out;
  }

  List<Map<String, dynamic>> _uiFilters(String tab) {
    final raw = _uiTab(tab)?['filters'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }

  Map<String, dynamic>? _uiFilterDef(String tab, String key) {
    for (final f in _uiFilters(tab)) {
      if (f['key'] == key) return f;
    }
    return null;
  }

  bool _hasUiFilter(String tab, String key) => _uiFilterDef(tab, key) != null;

  List<Map<String, dynamic>> _uiFilterOptions(String tab, String key) {
    final raw = _uiFilterDef(tab, key)?['options'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }

  List<Map<String, dynamic>> get _hunOptions {
    final raw = _uiRoot?['hunOptions'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return _uiFilterOptions('supply', 'hun');
  }

  List<Map<String, dynamic>> get _cubeFilterDefs {
    final raw = _uiRoot?['cubeFilters'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    return const [];
  }

  Map<String, dynamic>? _hunOptionByToken(String token) {
    if (token.isEmpty || token == 'none') return null;
    for (final o in _hunOptions) {
      if (o['value'] == token || o['match'] == token || o['cubeValue'] == token) {
        return o;
      }
    }
    return null;
  }

  String _hunMatchFor(String filterValue) {
    final o = _hunOptionByToken(filterValue);
    return o?['match'] as String? ?? (filterValue == '全部' ? '' : filterValue);
  }

  Color _hunColorFor(String token) =>
      _lhColorFromKey(_hunOptionByToken(token)?['colorKey'] as String?);

  String _hunBadgeFor(String token) {
    final o = _hunOptionByToken(token);
    return o?['badge'] as String? ?? o?['label'] as String? ?? token;
  }

  String _hunLabelFor(String token) {
    final o = _hunOptionByToken(token);
    return o?['label'] as String? ?? token;
  }

  String _cubeFilterLabel(String key) {
    for (final d in _cubeFilterDefs) {
      if (d['key'] == key) return d['label'] as String? ?? key;
    }
    return key;
  }

  List<Map<String, String>> _cubeHunOptionPairs() {
    final out = <Map<String, String>>[];
    for (final o in _hunOptions) {
      final value = o['value'] as String? ?? '';
      if (value == '全部') {
        out.add({'value': '全部', 'label': '全部'});
        continue;
      }
      final cubeValue = o['cubeValue'] as String? ?? o['match'] as String? ?? value;
      out.add({
        'value': cubeValue,
        'label': o['label'] as String? ?? cubeValue,
      });
    }
    if (out.isEmpty) return const [{'value': '全部', 'label': '全部'}];
    return out;
  }

  String _hunBarTitle() =>
      (_uiFilterDef('supply', 'hun')?['label'] as String?) ?? 'U/N';

  List<String> _categoryOptions(String tab) {
    final raw = _uiTab(tab)?['categories'];
    if (raw is List && raw.isNotEmpty) return raw.cast<String>();
    if (_bundle == null) return const ['全部'];
    return _getGroups(tab, _bundle!.rowsOf(tab));
  }

  void _syncMetricsFromUI() {
    for (final tab in const ['product', 'supply', 'channel']) {
      final defaults = _uiDefaultMetrics(tab);
      if (defaults.isEmpty) continue;
      final valid = defaults.toSet();
      final current = _metrics[tab] ?? const [];
      final pruned = current.where(valid.contains).toList();
      _metrics[tab] = pruned.isEmpty ? List<String>.from(defaults) : List<String>.from(pruned);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.navigation.canBackInterceptor = _hasInternalBackStack;
    widget.navigation.backInterceptor = _handleInternalBack;
    if (widget.session.lighthouseAccess) {
      _load();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    widget.navigation.canBackInterceptor = null;
    widget.navigation.backInterceptor = null;
    _ddEntry?.remove();
    _detailSkuSearchCtrl.dispose();
    super.dispose();
  }

  bool _hasInternalBackStack() =>
      _detailKey != null || _metricPageKey != null;

  bool _handleInternalBack() {
    if (_detailKey != null) {
      _closeDropdown();
      setState(() {
        _detailKey = null;
        _detailType = null;
        _resetDetailSkuSearch();
      });
      return true;
    }
    if (_metricPageKey != null) {
      _closeDropdown();
      setState(() => _metricPageKey = null);
      return true;
    }
    return false;
  }

  void _resetDetailSkuSearch() {
    _detailSkuQuery = '';
    if (_detailSkuSearchCtrl.text.isNotEmpty) {
      _detailSkuSearchCtrl.clear();
    }
  }

  String _normalizeSearchText(String raw) =>
      raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');

  /// SKU 模糊匹配：名称/分组包含关键词，或关键词字符按序出现（子序列）。
  bool _skuRowMatchesQuery(Map<String, dynamic> row, String query) {
    final q = _normalizeSearchText(query);
    if (q.isEmpty) return true;
    final name = _normalizeSearchText(row['name']?.toString() ?? '');
    final group = _normalizeSearchText(row['group']?.toString() ?? '');
    if (name.contains(q) || group.contains(q)) return true;
    bool subseq(String text) {
      var ti = 0;
      for (var i = 0; i < q.length; i++) {
        final idx = text.indexOf(q[i], ti);
        if (idx < 0) return false;
        ti = idx + 1;
      }
      return true;
    }
    return subseq(name) || subseq(group);
  }

  Widget _buildDetailSkuSearchBar() {
    final active = _detailSkuQuery.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: LhColors.paper,
          border: Border.all(color: active ? LhColors.ink2 : LhColors.line, width: 1),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 15, color: active ? LhColors.ink : LhColors.mute),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _detailSkuSearchCtrl,
                style: LhTypography.sans(size: 12, color: LhColors.ink, weight: FontWeight.w500),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索 SKU 名称…',
                  hintStyle: LhTypography.sans(size: 12, color: LhColors.mute2, weight: FontWeight.w400),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() {
                  _detailSkuQuery = v;
                  _detailPage = 1;
                }),
              ),
            ),
            if (active)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() {
                  _resetDetailSkuSearch();
                  _detailPage = 1;
                }),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 14, color: LhColors.mute),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _load() async {
    final requestedPeriod = _period;
    final requestedFuel = _supplyFuelFilter;
    final requestedOffset = _periodOffset;
    try {
      final bundle = await LighthouseService(session: widget.session)
          .fetchOverview(
        period: requestedPeriod,
        fuel: requestedFuel,
        offset: requestedOffset,
      );
      if (mounted &&
          requestedPeriod == _period &&
          requestedFuel == _supplyFuelFilter &&
          requestedOffset == _periodOffset) {
        setState(() {
          _bundle = bundle;
          _loading = false;
          _loadError = null;
          _rowsCacheKey = '';
          _rowsCache = null;
          _cubeCacheKey = '';
          _cubeData = null;
          _cubeError = false;
          // 「数据已同步」展示前端拉取数据的当前时刻（强制中国时间 UTC+8，不依赖设备时区）。
          _lastSyncedAt = _nowCST();
          _syncMetricsFromUI();
        });
      }
    } catch (e) {
      if (mounted &&
          requestedPeriod == _period &&
          requestedFuel == _supplyFuelFilter &&
          requestedOffset == _periodOffset) {
        setState(() {
          _loading = false;
          _loadError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  /// 手动刷新 — 点击顶部「数据已同步」胶囊触发，重新拉取概览 + 立方体。
  /// 不清空当前页面（保留视图），只在胶囊上转小圈，完成后更新同步时间。
  Future<void> _refresh() async {
    if (_refreshing || _loading) return;
    setState(() {
      _refreshing = true;
      _rowsCacheKey = '';
      _rowsCache = null;
      _cubeCacheKey = '';
      _cubeData = null;
      _cubeError = false;
    });
    await _load();
    if (_tab == 'analysis') await _loadAnalysisCube();
    if (mounted) setState(() => _refreshing = false);
  }

  /// 切换油品筛选 → 带 `fuel` 重新请求（后端真过滤，而非前端乘系数）。
  void _applyFuelFilter(String fuel) {
    if (fuel == _supplyFuelFilter) return;
    setState(() {
      _supplyFuelFilter = fuel;
      _loading = true;
      _loadError = null;
      _detailKey = null;
      _detailType = null;
      _resetDetailSkuSearch();
      _rowsCacheKey = '';
      _rowsCache = null;
      _cubeCacheKey = '';
      _cubeData = null;
      _cubeError = false;
    });
    _load();
    if (_tab == 'analysis') _loadAnalysisCube();
  }

  Future<void> _loadAnalysisCube() async {
    final key = '$_period|$_periodOffset|$_supplyFuelFilter';
    if (_cubeLoading) return;
    if (_cubeCacheKey == key && _cubeData != null) return;

    setState(() => _cubeLoading = true);
    try {
      final data = await LighthouseService(session: widget.session).fetchAnalysisCube(
        period: _period,
        offset: _periodOffset,
        fuel: _supplyFuelFilter != '全部' ? _supplyFuelFilter : null,
      );
      if (!mounted) return;
      setState(() {
        _cubeData = _parseCubeData(data);
        _cubeCacheKey = key;
        _cubeLoading = false;
        _cubeError = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _cubeData = null;
          _cubeCacheKey = key;
          _cubeLoading = false;
          _cubeError = true;
        });
      }
    }
  }

  List<_DiscountRow> _discountRowsFromBundle() {
    final rows = _bundle?.rowsOf('supply') ?? const [];
    final result = <_DiscountRow>[];
    for (final r in rows) {
      final raw = r['discount'];
      if (raw is Map) {
        final parsed = _DiscountRow.fromApi(raw.cast<String, dynamic>(), r['name']?.toString() ?? '');
        if (parsed != null) result.add(parsed);
      }
    }
    return result;
  }

  _CubeData _parseCubeData(Map<String, dynamic> data) {
    List<({String name, String group, double profit})> parseDim(String key) {
      final raw = data[key] as List? ?? const [];
      return raw
          .whereType<Map>()
          .map((r) => (
                name: r['name']?.toString() ?? '',
                group: r['group']?.toString() ?? '',
                profit: (r['profit'] as num?)?.toDouble() ?? 0,
              ))
          .toList();
    }

    final products = parseDim('products');
    final supplies = parseDim('supplies');
    final channels = parseDim('channels');

    int dimIndex(List<({String name, String group, double profit})> dims, String name, int fallback) {
      for (var i = 0; i < dims.length; i++) {
        if (dims[i].name == name) return i;
      }
      return fallback.clamp(0, dims.isEmpty ? 0 : dims.length - 1);
    }

    final lit = <_CubePoint>[];
    for (final item in (data['lit'] as List? ?? const []).whereType<Map>()) {
      final productName = item['x']?.toString() ?? '';
      final supplyName = item['y']?.toString() ?? '';
      final channelName = item['z']?.toString() ?? '';
      final productGroup = item['x_group']?.toString() ?? '';
      // 优先用后端 owner（接通后） — 当前 mock：按产品组(业务线)派生负责人
      final ownerName = item['owner']?.toString().isNotEmpty == true
          ? item['owner'].toString()
          : _deriveCubeOwner(productGroup, supplyName);
      lit.add(_CubePoint(
        xi: dimIndex(products, productName, (item['xi'] as num?)?.toInt() ?? 0),
        yi: dimIndex(supplies, supplyName, (item['yi'] as num?)?.toInt() ?? 0),
        zi: dimIndex(channels, channelName, (item['zi'] as num?)?.toInt() ?? 0),
        x: productName,
        y: supplyName,
        z: channelName,
        value: (item['value'] as num?)?.toDouble() ?? 0,
        productGroup: item['x_group']?.toString() ?? '',
        supplyGroup: item['y_group']?.toString() ?? '',
        channelGroup: item['z_group']?.toString() ?? '',
        supplyHun: item['supply_hun']?.toString() ?? 'none',
        channelHun: item['channel_hun']?.toString() ?? 'none',
        owner: ownerName,
      ));
    }

    final stats = data['stats'] as Map? ?? const {};
    return _CubeData(
      products: products,
      supplies: supplies,
      channels: channels,
      lit: lit,
      litCount: (stats['lit_count'] as num?)?.toInt(),
      totalPossible: (stats['total_possible'] as num?)?.toInt(),
      coveragePct: (stats['coverage_pct'] as num?)?.toDouble(),
    );
  }

  /// 返回中国时间 (UTC+8)，不依赖设备本地时区。
  /// 返回的 DateTime 是 isUtc=true 的"伪 CST"对象，hour/minute/day/weekday 都是
  /// 北京时间的值，直接读用即可（不要再 .toLocal()）。
  DateTime _nowCST() => DateTime.now().toUtc().add(const Duration(hours: 8));

  // ── FE-1: Greeting / AppBar 动态文案 ───────────────────────────────────────
  String _formatDateLabel() {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final now = _nowCST();
    final w = weekdays[now.weekday - 1];
    final mm = now.month.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    return '星期$w · $mm.$dd';
  }

  String _greetingText() {
    final hour = _nowCST().hour;
    final greeting = hour < 6
        ? '夜深了'
        : hour < 11
            ? '早上好'
            : hour < 14
                ? '中午好'
                : hour < 18
                    ? '下午好'
                    : hour < 22
                        ? '晚上好'
                        : '夜深了';
    final name = _userName();
    return name.isEmpty ? greeting : '$greeting，$name';
  }

  String _userName() {
    final display = widget.session.displayName;
    if (display != null && display.isNotEmpty) return display;
    return widget.session.phone;
  }

  String _syncedAtLabel() {
    final t = _lastSyncedAt ?? _nowCST();
    final mo = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$mo-$dd $hh:$mm';
  }

  Set<String> _liveMetrics(String tab) {
    final keys = _uiMetricDefs(tab)
        .where((d) => d['listDefault'] == true)
        .map((d) => d['key'] as String);
    final set = keys.toSet();
    return set.isEmpty ? _uiDefaultMetrics(tab).toSet() : set;
  }

  // Cached sorted/filtered rows — re-computed only when the source state changes.
  String _rowsCacheKey = '';
  List<Map<String, dynamic>>? _rowsCache;

  List<Map<String, dynamic>> get _currentRows {
    if (_bundle == null) return const [];
    final key = '$_period|$_tab|$_groupFilter|$_hunFilter|$_sortField|$_sortDesc';
    final cached = _rowsCache;
    if (cached != null && key == _rowsCacheKey) return cached;
    _listPage = 1; // 筛选/排序/周期变化时重置分页
    _discountExpanded = false;

    var rows = _bundle!.rowsOf(_tab);
    if (_groupFilter != '全部') {
      rows = rows.where((r) => r['group']?.toString() == _groupFilter).toList();
    }
    // HUN 过滤（仅 supply / channel）
    if (_hunFilter != '全部' && (_tab == 'supply' || _tab == 'channel')) {
      final match = _hunMatchFor(_hunFilter);
      rows = rows.where((r) => _hunOf(r).primary == match).toList();
    }
    final result = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) {
        final pa = (a[_sortField] as num?)?.toDouble() ?? 0;
        final pb = (b[_sortField] as num?)?.toDouble() ?? 0;
        return _sortDesc ? pb.compareTo(pa) : pa.compareTo(pb);
      });
    _rowsCacheKey = key;
    _rowsCache = result;
    return result;
  }

  /// 当后端未返回 `label` 时，按当前日期动态生成，避免显示过期硬编码日期。
  String _periodLabelFor(String period) {
    final now = _nowCST();
    String two(int v) => v.toString().padLeft(2, '0');
    switch (period) {
      case 'day':
        return '今日 · ${now.year}.${two(now.month)}.${two(now.day)}';
      case 'week':
        final monday = now.subtract(Duration(days: now.weekday - 1));
        final sunday = monday.add(const Duration(days: 6));
        return '本周 · ${two(monday.month)}.${two(monday.day)} – ${two(sunday.month)}.${two(sunday.day)}';
      case 'month':
        return '本月 · ${now.year}.${two(now.month)}';
      case 'quarter':
        final q = ((now.month - 1) ~/ 3) + 1;
        return '本季 · ${now.year}.Q$q';
      case 'year':
        return '今年 · ${now.year}';
      default:
        return '';
    }
  }

  /// Hero 顶部聚合：完全读后端 `metrics`，缺字段用 0 / 动态日期占位（无写死业务兜底）。
  _PeriodInfo get _heroInfo {
    final m = _bundle?.metrics ?? const <String, dynamic>{};
    final dynamicLabel = _periodLabelFor(_period);

    final compose = <_ComposeItem>[];
    final rawCompose = m['compose'];
    if (rawCompose is List) {
      for (final c in rawCompose.whereType<Map>()) {
        final name = c['name']?.toString() ?? '';
        compose.add(_ComposeItem(
          name: name,
          pct: (c['pct'] as num?)?.toDouble() ?? 0,
          color: _composeColor(c['colorKey']?.toString() ?? '', name),
        ));
      }
    }

    final salesDir = m['salesDeltaDir']?.toString() ?? m['deltaDir']?.toString() ?? 'flat';
    final salesPct = (m['salesDeltaPct'] as num?)?.toDouble() ?? (m['deltaPct'] as num?)?.toDouble();

    return _PeriodInfo(
      label: m['label']?.toString() ?? dynamicLabel,
      short: m['short']?.toString() ?? (_kPeriodShort[_period] ?? ''),
      salesV: (m['salesV'] as num?)?.toDouble() ?? 0,
      salesU: m['salesU']?.toString() ?? '',
      deltaDir: salesDir == 'down' ? 'down' : 'up',
      deltaVal: salesPct?.abs() ?? 0,
      deltaVs: m['deltaVs']?.toString() ?? (_kPeriodVs[_period] ?? ''),
      hasDelta: salesDir != 'flat' && salesPct != null,
      profitV: (m['profitV'] as num?)?.toDouble() ?? 0,
      profitU: m['profitU']?.toString() ?? '',
      gmvV: (m['gmvV'] as num?)?.toDouble() ?? 0,
      gmvU: m['gmvU']?.toString() ?? '',
      rate: (m['rate'] as num?)?.toDouble() ?? 0,
      compose: compose,
    );
  }

  /// 后端 compose.colorKey → 颜色；未知时按 name 推断。
  Color _composeColor(String key, String name) {
    switch (key) {
      case 'cnpc':
        return LhColors.cnpc;
      case 'sinopec':
        return LhColors.sinopec;
      case 'private':
        return LhColors.private;
      case 'carrier':
        return LhColors.carrier;
      case 'pingan':
        return LhColors.pingan;
      case 'dict':
        return LhColors.dict;
      case 'multi':
        return LhColors.multi;
      case 'unk':
        return LhColors.unk;
    }
    return lhGroupColor(name);
  }

  bool get _mainFilterActive =>
      _groupFilter != '全部' || (_tab == 'supply' && _supplyFuelFilter != '全部');

  bool get _listFilterActive =>
      _mainFilterActive ||
      ((_tab == 'supply' || _tab == 'channel') && _hunFilter != '全部');

  /// 当前 hero 上方激活的所有筛选 → 返回 (label, value) 列表用于渲染 pills
  /// 顺序按重要性：tab group → fuel → HUN
  List<({String label, String value, VoidCallback onClear})> _activeHeroFilters() {
    final list = <({String label, String value, VoidCallback onClear})>[];
    const tabName = {'product': '产品', 'supply': '供给', 'channel': '渠道'};
    if (_groupFilter != '全部') {
      list.add((
        label: tabName[_tab] ?? '分类',
        value: _groupFilter,
        onClear: () => setState(() {
          _groupFilter = '全部';
          if (_tab == 'supply') _supplyFuelFilter = '全部';
        }),
      ));
    }
    if (_tab == 'supply' && _supplyFuelFilter != '全部') {
      list.add((
        label: '油品',
        value: _supplyFuelFilter,
        onClear: () => setState(() => _supplyFuelFilter = '全部'),
      ));
    }
    if ((_tab == 'supply' || _tab == 'channel') && _hunFilter != '全部') {
      list.add((
        label: _uiFilterDef(_tab, 'hun')?['label'] as String? ?? 'U/N',
        value: _hunLabelFor(_hunFilter),
        onClear: () => setState(() => _hunFilter = '全部'),
      ));
    }
    return list;
  }

  // ── Dropdown helpers ──────────────────────────────────────────────────────
  // 浮层使用 per-button GlobalKey 锚定到具体按钮，配合屏幕边界避让 + 入场动画
  void _closeDropdown() {
    _ddEntry?.remove();
    _ddEntry = null;
    if (mounted) setState(() => _ddMode = _DdMode.none);
  }

  void _toggleDropdown(_DdMode mode) {
    if (_ddMode == mode) {
      _closeDropdown();
      return;
    }
    _ddEntry?.remove();
    _ddEntry = null;
    setState(() => _ddMode = mode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _ddMode != mode) return;
      _showDropdownOverlay(mode);
    });
  }

  GlobalKey? _btnKeyFor(_DdMode mode) {
    switch (mode) {
      case _DdMode.category:
        return _btnKeyCategory;
      case _DdMode.metric:
        return _btnKeyMetric;
      case _DdMode.filter:
        return _btnKeyFilter;
      case _DdMode.hun:
        return _btnKeyHun;
      case _DdMode.none:
        return null;
    }
  }

  double _panelWidthFor(_DdMode mode) {
    switch (mode) {
      case _DdMode.metric:
        return 280;
      case _DdMode.category:
        return 220;
      case _DdMode.filter:
        return 180;
      case _DdMode.hun:
        return 240;
      case _DdMode.none:
        return 220;
    }
  }

  void _showDropdownOverlay(_DdMode mode) {
    final key = _btnKeyFor(mode);
    final ctx = key?.currentContext;
    if (ctx == null) return;
    final rb = ctx.findRenderObject() as RenderBox?;
    if (rb == null || !rb.attached) return;
    final btnTopLeft = rb.localToGlobal(Offset.zero);
    final btnSize = rb.size;
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    final panelW = math.min(_panelWidthFor(mode), screen.width - 16);

    const gap = 6.0;
    const absoluteMaxH = 360.0;
    final topInset = mq.padding.top + 8;
    final bottomInset = mq.padding.bottom + 12;
    final spaceBelow = screen.height - (btnTopLeft.dy + btnSize.height) - gap - bottomInset;
    final spaceAbove = btnTopLeft.dy - gap - topInset;
    // 优先在按钮下方展开，避免面板「往上飘」脱离触发按钮
    final placeBelow = spaceBelow >= 88 || spaceBelow >= spaceAbove;
    final panelMaxH = math.min(absoluteMaxH, math.max(120.0, placeBelow ? spaceBelow : spaceAbove));
    final top = placeBelow
        ? btnTopLeft.dy + btnSize.height + gap
        : math.max(topInset, btnTopLeft.dy - gap - panelMaxH);

    double left = btnTopLeft.dx + btnSize.width - panelW;
    if (left < 8) left = btnTopLeft.dx;
    if (left + panelW > screen.width - 8) left = screen.width - 8 - panelW;
    if (left < 8) left = 8;

    _ddEntry = OverlayEntry(
      builder: (overlayCtx) {
        return Stack(
          children: [
            // 全屏遮罩：点外部收起（Web 上用 Listener 比 GestureDetector 更可靠）
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (_) => _closeDropdown(),
                child: ColoredBox(color: Colors.black.withAlpha(18)),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: panelW,
              child: TapRegion(
                onTapOutside: (_) => _closeDropdown(),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0.0, end: 1.0),
                  builder: (_, t, child) {
                    return Opacity(
                      opacity: t,
                      child: Transform.translate(
                        offset: Offset(0, placeBelow ? (1 - t) * -4 : (1 - t) * 4),
                        child: child,
                      ),
                    );
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: _LhDropdownPanel(
                      width: panelW,
                      maxHeight: panelMaxH,
                      child: _buildDropdownContent(mode),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context, rootOverlay: true).insert(_ddEntry!);
  }

  void _refreshDropdown() {
    setState(() {});
    _ddEntry?.markNeedsBuild();
  }

  Widget _buildDropdownContent(_DdMode mode) {
    if (mode == _DdMode.category) return _buildCategoryDropdown();
    if (mode == _DdMode.metric) return _buildMetricDropdown();
    if (mode == _DdMode.filter) return _buildSupplyFilterDropdown();
    if (mode == _DdMode.hun) return _buildHunDropdown();
    return const SizedBox();
  }

  // ── Category dropdown ─────────────────────────────────────────────────────
  Widget _buildCategoryDropdown() {
    final groups = _groups;
    return StatefulBuilder(builder: (ctx, setLocal) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('选择分类', style: LhTypography.mono(size: 9, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 1.5)),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _groupFilter = '全部';
                    if (_tab == 'supply') _supplyFuelFilter = '全部';
                  });
                  _closeDropdown();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(3)),
                  child: Text('全部', style: LhTypography.sans(size: 10, color: LhColors.copper, weight: FontWeight.w500)),
                ),
              ),
            ],
          ),
          Container(height: 1, color: LhColors.line2, margin: const EdgeInsets.symmetric(vertical: 7)),
          // Options
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: groups.map((g) {
              final isOn = g == _groupFilter;
              Color optColor = LhColors.ink;
              Color optBg = Colors.transparent;
              Color optBorder = LhColors.line;
              if (isOn) {
                final gc = lhGroupColor(g);
                if (g == '全部') {
                  optBg = LhColors.ink.withAlpha(13);
                  optBorder = LhColors.ink;
                  optColor = LhColors.ink;
                } else {
                  optBg = gc.withAlpha(15);
                  optBorder = gc;
                  optColor = gc;
                }
              }
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _groupFilter = g;
                    if (_tab == 'supply') _supplyFuelFilter = '全部';
                  });
                  _closeDropdown();
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                  decoration: BoxDecoration(
                    color: optBg,
                    border: Border.all(color: optBorder, width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(g, style: LhTypography.sans(size: 10, color: isOn ? optColor : LhColors.ink2, weight: isOn ? FontWeight.w600 : FontWeight.w500, letterSpacing: 0)),
                ),
              );
            }).toList(),
          ),
        ],
      );
    });
  }

  Widget _buildSupplyFilterDropdown() {
    return _buildUiFilterDropdown('fuel', currentValue: _supplyFuelFilter, onPick: (v) {
      _closeDropdown();
      _applyFuelFilter(v);
    });
  }

  Widget _buildUiFilterDropdown(
    String filterKey, {
    required String currentValue,
    required ValueChanged<String> onPick,
  }) {
    final def = _uiFilterDef(_tab, filterKey);
    if (def == null) return const SizedBox.shrink();
    final title = def['label'] as String? ?? filterKey;
    final options = _uiFilterOptions(_tab, filterKey);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: LhTypography.mono(size: 9, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 1.5)),
            GestureDetector(
              onTap: () => onPick('全部'),
              child: Text('全部', style: LhTypography.sans(size: 10, color: LhColors.copper, weight: FontWeight.w500)),
            ),
          ],
        ),
        Container(height: 1, color: LhColors.line2, margin: const EdgeInsets.symmetric(vertical: 7)),
        if (filterKey == 'hun')
          Column(
            children: options.map((opt) {
              final value = opt['value'] as String? ?? '';
              final label = opt['label'] as String? ?? value;
              final color = _lhColorFromKey(opt['colorKey'] as String?);
              final isOn = currentValue == value;
              return GestureDetector(
                onTap: () => onPick(value),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                  decoration: BoxDecoration(
                    color: isOn ? color.withAlpha(14) : Colors.transparent,
                    border: Border.all(color: isOn ? color : LhColors.line, width: 1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isOn ? color : color.withAlpha(22),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          value == '全部'
                              ? '∗'
                              : (_hunOptionByToken(value)?['badge'] as String? ??
                                  _hunLabelFor(value)),
                          style: LhTypography.mono(
                            size: (() {
                              final badge = _hunOptionByToken(value)?['badge'] as String? ?? value;
                              return badge.length > 2 ? 8.5 : 11.0;
                            })(),
                            color: isOn ? Colors.white : _hunColorFor(value),
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          label,
                          style: LhTypography.sans(
                            size: 11,
                            color: isOn ? color : LhColors.ink2,
                            weight: isOn ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isOn) Icon(Icons.check_rounded, size: 14, color: color),
                    ],
                  ),
                ),
              );
            }).toList(),
          )
        else
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: options.map((opt) {
              final v = opt['value'] as String? ?? '';
              final label = opt['label'] as String? ?? v;
              final isOn = currentValue == v;
              return GestureDetector(
                onTap: () => onPick(v),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                  decoration: BoxDecoration(
                    color: isOn ? LhColors.ink.withAlpha(13) : Colors.transparent,
                    border: Border.all(color: isOn ? LhColors.ink : LhColors.line, width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    label,
                    style: LhTypography.sans(
                      size: 10,
                      color: isOn ? LhColors.ink : LhColors.ink2,
                      weight: isOn ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildHunDropdown() {
    return _buildUiFilterDropdown('hun', currentValue: _hunFilter, onPick: (v) {
      setState(() => _hunFilter = v);
      _closeDropdown();
    });
  }

  // ── HUN helper — 读行级 hunU / hunN / hunH（后端真字段） ─────────────────
  _HunInfo _hunOf(Map<String, dynamic> r) {
    return _HunInfo(
      u: (r['hunU'] as num?)?.toDouble() ?? 0,
      n: (r['hunN'] as num?)?.toDouble() ?? 0,
      h: (r['hunH'] as num?)?.toDouble() ?? 0,
    );
  }

  // ── Metric + sort dropdown ────────────────────────────────────────────────
  Widget _buildMetricDropdown() {
    final tab = _metricsTab;
    final defs = _uiMetricDefs(tab);
    final available = defs
        .where((d) => d['listDefault'] == true)
        .map((d) => d['key'] as String)
        .toList();
    var sortable = [
      for (final d in defs)
        if (d['sortable'] != false) d['key'] as String,
    ];
    if (sortable.isEmpty) {
      sortable = ['profit', ...available.where((k) => k != 'discount')];
    }

    return StatefulBuilder(builder: (ctx, setLocal) {
      final selected = _metrics[tab] ?? [];

      void refresh() {
        _refreshDropdown();
        setLocal(() {});
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('排序 & 显示', style: LhTypography.mono(size: 9, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 1.5)),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _metrics[tab] = List.from(_uiResetMetrics());
                    _sortField = _uiResetSortField();
                    _sortDesc = true;
                  });
                  refresh();
                },
                child: Text('默认', style: LhTypography.sans(size: 10, color: LhColors.copper, weight: FontWeight.w500)),
              ),
            ],
          ),
          Container(height: 1, color: LhColors.line2, margin: const EdgeInsets.symmetric(vertical: 7)),
          Text('按 ${_metricLabel(_sortField, tab: tab)} 排序',
            style: LhTypography.sans(size: 10.5, color: LhColors.mute)),
          const SizedBox(height: 7),
          Wrap(
            spacing: 4, runSpacing: 4,
            children: sortable.map((k) {
              final isOn = k == _sortField;
              return GestureDetector(
                onTap: () {
                  setState(() => _sortField = k);
                  refresh();
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                  decoration: BoxDecoration(
                    color: isOn ? LhColors.ink : Colors.transparent,
                    border: Border.all(color: isOn ? LhColors.ink : LhColors.line, width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(_metricLabel(k, tab: tab), style: LhTypography.sans(size: 10, color: isOn ? Colors.white : LhColors.mute, weight: isOn ? FontWeight.w600 : FontWeight.w500)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          // Sort direction
          Row(
            children: [
              Expanded(child: _ddDirBtn('↓ 从高到低', 'desc', refresh)),
              const SizedBox(width: 5),
              Expanded(child: _ddDirBtn('↑ 从低到高', 'asc', refresh)),
            ],
          ),

          Container(height: 1, color: LhColors.line, margin: const EdgeInsets.symmetric(vertical: 9)),

          // Display metrics
          Text('每行展示指标', style: LhTypography.sans(size: 9, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 0.5)),
          const SizedBox(height: 5),
          Wrap(
            spacing: 4, runSpacing: 4,
            children: available.map((k) {
              final isOn = selected.contains(k);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    final m = _metrics[tab]!;
                    if (isOn) {
                      if (m.length > 1) m.remove(k);
                    } else {
                      m.add(k);
                    }
                  });
                  refresh();
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                  decoration: BoxDecoration(
                    color: isOn ? LhColors.ink.withAlpha(13) : Colors.transparent,
                    border: Border.all(color: isOn ? LhColors.ink : LhColors.line, width: 1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(_metricLabel(k, tab: tab), style: LhTypography.sans(size: 10, color: isOn ? LhColors.ink : LhColors.ink2, weight: isOn ? FontWeight.w600 : FontWeight.w500)),
                ),
              );
            }).toList(),
          ),
        ],
      );
    });
  }

  Widget _ddDirBtn(String label, String dir, VoidCallback refresh) {
    final isOn = _sortDesc == (dir == 'desc');
    return GestureDetector(
      onTap: () {
        setState(() => _sortDesc = (dir == 'desc'));
        refresh();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: isOn ? LhColors.copperSoft : Colors.transparent,
          border: Border.all(color: isOn ? LhColors.copper : LhColors.line, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(label, style: LhTypography.sans(size: 10, color: isOn ? LhColors.copper : LhColors.mute, weight: isOn ? FontWeight.w600 : FontWeight.w400, letterSpacing: 0.2)),
        ),
      ),
    );
  }

  List<String> get _groups {
    if (_bundle == null) return const ['全部'];
    return _categoryOptions(_tab);
  }

  bool get _hasAccess => widget.session.lighthouseAccess;

  bool _isNoPermissionError(Object? error) {
    if (error == null) return false;
    final msg = error.toString();
    return msg.contains('暂无权限') ||
        msg.contains('无权限') ||
        msg.contains('403');
  }

  Widget _buildNoAccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: LhColors.line2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: LhColors.line),
              ),
              child: const Icon(Icons.lock_outline_rounded, size: 28, color: LhColors.mute),
            ),
            const SizedBox(height: 18),
            Text(
              '暂无权限',
              style: LhTypography.sans(size: 16, weight: FontWeight.w600, color: LhColors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              '当前账号未开通灯塔访问权限，如需使用请联系管理员。',
              textAlign: TextAlign.center,
              style: LhTypography.sans(size: 12, color: LhColors.mute, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasInternalBackStack(),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleInternalBack();
      },
      child: Scaffold(
      backgroundColor: LhColors.cream,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: !_hasAccess
                  ? _buildNoAccessView()
                  : Stack(
                      children: [
                        _detailKey != null
                            ? _buildDetailView()
                            : _buildMainView(),
                        if (_isPageBusy) _buildLoadingOverlay(),
                      ],
                    ),
            ),
            DunesMainTabBar(
              navigation: widget.navigation,
              activeScreen: 'LH',
              commUnread: widget.commUnread,
              workbenchBadge: widget.workbenchBadge,
              lighthouseAccess: widget.session.lighthouseAccess,
            ),
          ],
        ),
      ),
    ),
    );
  }

  // ───── AppBar ─────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 2),
      child: Row(
        children: [
          // Brand mark
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A1816), Color(0xFF3A342C)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: LhColors.copper.withAlpha(64), width: 1),
            ),
            child: Center(
              child: Container(
                width: 5.5,
                height: 5.5,
                decoration: BoxDecoration(
                  color: LhColors.copper,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: LhColors.copper.withAlpha(140), blurRadius: 7)],
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('灯塔', style: LhTypography.sans(size: 15, weight: FontWeight.w700, color: LhColors.ink, letterSpacing: 2)),
              Text('LIGHTHOUSE', style: LhTypography.mono(size: 8.5, color: LhColors.mute, letterSpacing: 1.5)),
            ],
          ),
          if (_isPageBusy) ...[
            const Spacer(),
            const _LhBrandLoader(size: 22),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    final label = _cubeLoading && !_loading ? '分析加载中' : '数据同步中';
    return Positioned.fill(
      child: ColoredBox(
        color: LhColors.cream.withAlpha(210),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _LhBrandLoader(size: 48),
              const SizedBox(height: 14),
              Text(
                label,
                style: LhTypography.mono(
                  size: 10,
                  color: LhColors.mute,
                  weight: FontWeight.w600,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───── Main View ──────────────────────────────────────────────────────────
  Widget _buildMainView() {
    if (_metricPageKey != null) return _buildMetricAnalysisPage(_metricPageKey!);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (_ddMode != _DdMode.none && n is ScrollStartNotification) {
          _closeDropdown();
        }
        return false;
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          _buildGreeting(),
          _buildPanel(),
          if (_tab == 'supply') _buildDiscountSection(),
          if (_tab == 'analysis') _buildAnalysisView() else _buildList(),
          _buildFooter(),
        ],
      ),
    );
  }

  // ───── Greeting ───────────────────────────────────────────────────────────
  Widget _buildGreeting() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(_formatDateLabel(), style: LhTypography.sans(size: 12, color: LhColors.mute, weight: FontWeight.w500, letterSpacing: 0.3)),
              const Spacer(),
              _buildPill(),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_greetingText(), style: LhTypography.sans(size: 23, color: LhColors.ink, weight: FontWeight.w700, letterSpacing: 0.4)),
              const SizedBox(width: 8),
              Text('本月累计', style: LhTypography.sans(size: 11, color: LhColors.mute2)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPill() {
    final busy = _refreshing || _loading;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : _refresh,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: LhColors.paper,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: LhColors.line, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 9,
                height: 9,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation<Color>(LhColors.copper),
                ),
              )
            else
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: LhColors.pos,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: LhColors.pos.withAlpha(46), blurRadius: 0, spreadRadius: 3)],
                ),
              ),
            const SizedBox(width: 6),
            Text(
              busy ? '数据同步中…' : '数据已同步 · ${_syncedAtLabel()}',
              style: LhTypography.sans(size: 11, color: LhColors.ink2, weight: FontWeight.w500),
            ),
            const SizedBox(width: 5),
            Icon(
              Icons.refresh_rounded,
              size: 12,
              color: busy ? LhColors.mute2 : LhColors.copper,
            ),
          ],
        ),
      ),
    );
  }

  // ───── Panel (Hero + Tabs + Sortbar) ──────────────────────────────────────
  Widget _buildPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          transform: GradientRotation(2.97), // ~170deg
          colors: [Colors.white, Color(0xFFFCFAF5), Color(0xFFF7F4EC), Color(0xFFF2EEE3)],
          stops: [0, 0.35, 0.75, 1],
        ),
        border: Border.all(color: LhColors.line2, width: 1),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: const Color(0x07140A00), blurRadius: 2, offset: const Offset(0, 1)),
          BoxShadow(color: const Color(0x10140A00), blurRadius: 20, spreadRadius: -10, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHero(),
          _buildTabSegment(),
          if (_tab != 'analysis') _buildSortbar(),
        ],
      ),
    );
  }

  // ───── Hero ───────────────────────────────────────────────────────────────
  Widget _buildHero() {
    final p = _heroInfo;
    final isUp = p.deltaDir == 'up';
    final deltaColor = isUp ? LhColors.pos : LhColors.neg;
    final deltaArrow = isUp ? '↑' : '↓';
    final metrics = _heroMetricsFor(_tab);

    // Compute totals from data
    final rows = _currentRows;
    double sumSales = 0, sumGmv = 0, sumCost = 0, sumProfit = 0, sumRevenue = 0, sumTax = 0;
    for (final r in rows) {
      sumSales += (r['sales'] as num?)?.toDouble() ?? 0;
      sumGmv += (r['gmv'] as num?)?.toDouble() ?? 0;
      sumCost += (r['cost'] as num?)?.toDouble() ?? 0;
      sumProfit += (r['profit'] as num?)?.toDouble() ?? 0;
      sumRevenue += (r['revenue'] as num?)?.toDouble() ?? 0;
      sumTax += (r['tax'] as num?)?.toDouble() ?? 0;
    }
    final sumRate = sumSales > 0 ? sumProfit / sumSales * 100 : 0.0;
    final totals = {
      'sales': sumSales, 'gmv': sumGmv, 'cost': sumCost,
      'profit': sumProfit, 'revenue': sumRevenue, 'tax': sumTax, 'rate': sumRate,
    };

    final filterActive = _listFilterActive;
    final bigV = filterActive ? _fmt(sumSales) : p.salesV.toString().replaceAll(RegExp(r'\.0$'), '');
    final bigU = filterActive ? ('${_unit(sumSales)}元') : ('${p.salesU}元');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period bar — 日/周/月/季/年（下划线 tab 风格，含实例选择）
          _buildPeriodBar(),
          const SizedBox(height: 10),
          // Label + delta inline (saves a row of vertical real-estate)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                filterActive ? '筛选销售额 · FILTERED' : '总销售额 · GROSS SALES',
                style: LhTypography.mono(size: 9.5, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 1.8),
              ),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 1, color: LhColors.line2)),
              const SizedBox(width: 8),
              Text(
                p.hasDelta ? '$deltaArrow ${p.deltaVal}%' : '—',
                style: LhTypography.mono(size: 10.5, color: p.hasDelta ? deltaColor : LhColors.mute2, weight: FontWeight.w600, letterSpacing: 0.2),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Big number + 右侧板报式筛选角标
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 数字组 (baseline 对齐)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        bigV,
                        style: LhTypography.number(size: 30, color: LhColors.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 1),
                    Text(bigU, style: LhTypography.sans(size: 14, color: LhColors.mute, weight: FontWeight.w500)),
                  ],
                ),
              ),
              // 板报角标 — 仅在有筛选时显示
              _buildFilterPosterCard(),
            ],
          ),
          const SizedBox(height: 4),
          // Context line (vs … · period)
          Text(
            '${p.deltaVs} · ${p.label}',
            style: LhTypography.sans(size: 10.5, color: LhColors.mute),
          ),
          const SizedBox(height: 12),
          // Compose bar
          _buildComposeBar(p),
          // HUN 占比（仅 supply / channel）
          if (_tab == 'supply' || _tab == 'channel') ...[
            const SizedBox(height: 10),
            _buildHunComposeBar(rows),
          ],
          const SizedBox(height: 14),
          // Hero grid
          _buildHeroGrid(metrics, totals, filterActive),
        ],
      ),
    );
  }

  /// 板报式筛选角标 — 贴在销售额右侧
  /// 视觉：copper 实色上沿 + cream 内填 + copper 厚边框 + 倾斜 -2° 像贴纸
  /// 单击整个板报清掉所有筛选
  Widget _buildFilterPosterCard() {
    final filters = _activeHeroFilters();
    if (filters.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 10, top: 2),
      child: Transform.rotate(
        angle: -0.025, // 约 -1.4° 贴纸感
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // 点角标 → 一键清掉所有筛选
            setState(() {
              _groupFilter = '全部';
              _supplyFuelFilter = '全部';
              _hunFilter = '全部';
            });
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 78, maxWidth: 130),
            decoration: BoxDecoration(
              color: LhColors.copperSoft,
              border: Border.all(color: LhColors.copper, width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 顶部 copper 实色 stripe
                Container(
                  color: LhColors.copper,
                  padding: const EdgeInsets.fromLTRB(7, 3, 7, 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '筛选',
                        style: LhTypography.sans(
                          size: 9,
                          color: Colors.white,
                          weight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const Spacer(),
                      if (filters.length > 1)
                        Text(
                          '×${filters.length}',
                          style: LhTypography.mono(
                            size: 9,
                            color: Colors.white.withAlpha(220),
                            weight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                    ],
                  ),
                ),
                // 内容区 — 每个筛选 value 一行大字
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < filters.length; i++) ...[
                        if (i > 0) const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            // 小前缀 (产品/供给/HUN/油品)
                            Text(
                              filters[i].label,
                              style: LhTypography.sans(
                                size: 8,
                                color: LhColors.copper.withAlpha(180),
                                weight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(width: 4),
                            // value — 大号 bold
                            Flexible(
                              child: Text(
                                filters[i].value,
                                style: LhTypography.sans(
                                  size: 14,
                                  color: LhColors.ink,
                                  weight: FontWeight.w700,
                                  letterSpacing: 0.1,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      // 底部提示行 — 点击清除
                      Row(
                        children: [
                          Icon(Icons.close_rounded, size: 9, color: LhColors.copper.withAlpha(160)),
                          const SizedBox(width: 2),
                          Text(
                            '点击清除',
                            style: LhTypography.mono(
                              size: 8,
                              color: LhColors.copper.withAlpha(160),
                              weight: FontWeight.w500,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 页面级周期筛选：粒度（日/周/月/季/年）+ 实例（哪一天/周/月/季/年）
  // offset 0 = 当前实例，-1 = 上一个，依此类推。所有数据仍走后端真实库，
  // offset 透传给 fetchOverview / fetchAnalysisCube。
  // ═══════════════════════════════════════════════════════════════════════

  String _two(int v) => v.toString().padLeft(2, '0');

  /// 给定粒度 + offset 的锚点日期（实例起点）。
  DateTime _periodAnchor(String period, int offset) {
    final now = _nowCST();
    switch (period) {
      case 'day':
        return DateTime(now.year, now.month, now.day)
            .add(Duration(days: offset));
      case 'week':
        final mon = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return mon.add(Duration(days: offset * 7));
      case 'month':
        return DateTime(now.year, now.month + offset, 1);
      case 'quarter':
        final q0 = (now.month - 1) ~/ 3; // 0..3
        final idx = now.year * 4 + q0 + offset;
        return DateTime(idx ~/ 4, (idx % 4) * 3 + 1, 1);
      case 'year':
        return DateTime(now.year + offset, 1, 1);
      default:
        return now;
    }
  }

  /// 实例主标签（按钮 + 列表）。
  String _periodInstanceLabel(String period, int offset) {
    final a = _periodAnchor(period, offset);
    switch (period) {
      case 'day':
        if (offset == 0) return '今日';
        if (offset == -1) return '昨日';
        if (offset == -2) return '前日';
        return '${_two(a.month)}.${_two(a.day)}';
      case 'week':
        if (offset == 0) return '本周';
        if (offset == -1) return '上周';
        return '${-offset}周前';
      case 'month':
        if (offset == 0) return '本月';
        if (offset == -1) return '上月';
        return '${a.year}.${_two(a.month)}';
      case 'quarter':
        final q = (a.month - 1) ~/ 3 + 1;
        if (offset == 0) return '本季';
        if (offset == -1) return '上季';
        return '${a.year} Q$q';
      case 'year':
        if (offset == 0) return '今年';
        if (offset == -1) return '去年';
        return '${a.year}';
      default:
        return '';
    }
  }

  /// 实例副标签（小字日期范围 / 精确值）。
  String _periodInstanceDetail(String period, int offset) {
    final a = _periodAnchor(period, offset);
    switch (period) {
      case 'day':
        const wk = ['一', '二', '三', '四', '五', '六', '日'];
        return '${a.year}.${_two(a.month)}.${_two(a.day)} 周${wk[a.weekday - 1]}';
      case 'week':
        final end = a.add(const Duration(days: 6));
        return '${_two(a.month)}.${_two(a.day)}–${_two(end.month)}.${_two(end.day)}';
      case 'month':
        return '${a.year}.${_two(a.month)}';
      case 'quarter':
        final q = (a.month - 1) ~/ 3 + 1;
        return '${a.year} 第$q季度';
      case 'year':
        return '${a.year} 年度';
      default:
        return '';
    }
  }

  /// 每种粒度展示的实例数量（offset 0..-(n-1)）。
  int _periodInstanceCount(String period) {
    switch (period) {
      case 'day':
        return 14;
      case 'week':
        return 12;
      case 'month':
        return 12;
      case 'quarter':
        return 8;
      case 'year':
        return 5;
      default:
        return 6;
    }
  }

  /// 统一切换粒度 / 实例 → 清缓存 + 重新拉取（真实库数据）。
  void _applyPeriod({String? period, int? offset}) {
    final newPeriod = period ?? _period;
    final newOffset = offset ?? _periodOffset;
    if (newPeriod == _period && newOffset == _periodOffset) {
      setState(() => _periodPickerOpen = false);
      return;
    }
    setState(() {
      _period = newPeriod;
      _periodOffset = newOffset;
      _periodPickerOpen = false;
      _loading = true;
      _loadError = null;
      _detailKey = null;
      _detailType = null;
      _resetDetailSkuSearch();
      _rowsCacheKey = '';
      _rowsCache = null;
      _cubeCacheKey = '';
      _cubeData = null;
      _cubeError = false;
    });
    _load();
    if (_tab == 'analysis') _loadAnalysisCube();
  }

  /// 还原版下划线 tab 风格：日/周/月/季/年。
  /// 选中那一项右边多一个小 ▾ — 点它（或再点选中项）展开实例选择条。
  /// 非选中项：点 → 切粒度并把 offset 重置为 0。
  Widget _buildPeriodBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: _kPeriodKeys.map((k) {
            final isOn = k == _period;
            final shortLabel = _kPeriodShort[k] ?? '';
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (k == _period) {
                    // 再点选中项 → 展开/收起实例选择
                    setState(() => _periodPickerOpen = !_periodPickerOpen);
                  } else {
                    // 切粒度 → offset 回到 0
                    setState(() => _periodPickerOpen = false);
                    _applyPeriod(period: k, offset: 0);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: isOn ? LhColors.copper : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        shortLabel,
                        textAlign: TextAlign.center,
                        style: LhTypography.sans(
                          size: 13.5,
                          color: isOn ? LhColors.ink : LhColors.mute,
                          weight: isOn ? FontWeight.w700 : FontWeight.w500,
                          letterSpacing: isOn ? 1.5 : 1,
                        ),
                      ),
                      if (isOn) ...[
                        const SizedBox(width: 2),
                        Icon(
                          _periodPickerOpen
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 14,
                          color: LhColors.copper,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        // 非默认实例时，下面贴一行淡色提示：当前看的是哪一期
        if (_periodOffset != 0 && !_periodPickerOpen)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 10, color: LhColors.copper),
                const SizedBox(width: 4),
                Text(
                  '${_periodInstanceLabel(_period, _periodOffset)} · ${_periodInstanceDetail(_period, _periodOffset)}',
                  style: LhTypography.mono(
                    size: 9.5,
                    color: LhColors.copper,
                    weight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _applyPeriod(offset: 0),
                  child: Text(
                    '回到当前',
                    style: LhTypography.mono(
                      size: 9,
                      color: LhColors.mute,
                      weight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 实例选择条 — 横滑选具体哪一天/周/月/季/年
        if (_periodPickerOpen) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: _periodInstanceCount(_period),
              itemBuilder: (ctx, i) => _periodInstanceChip(-i),
            ),
          ),
        ],
      ],
    );
  }

  /// 实例选择条上的单个芯片 — 极简：纵向两行文案 + 选中态下划线。
  Widget _periodInstanceChip(int off) {
    final on = off == _periodOffset;
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _applyPeriod(offset: off),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: on ? LhColors.copper : Colors.transparent,
                width: 1.2,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _periodInstanceLabel(_period, off),
                style: LhTypography.sans(
                  size: 11,
                  color: on ? LhColors.ink : LhColors.mute,
                  weight: on ? FontWeight.w700 : FontWeight.w500,
                  height: 1.2,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                _periodInstanceDetail(_period, off),
                style: LhTypography.mono(
                  size: 8.5,
                  color: on ? LhColors.copper : LhColors.mute2,
                  weight: FontWeight.w500,
                  height: 1.2,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposeBar(_PeriodInfo p) {
    final compose = p.compose.where((c) => c.pct > 0).toList();
    if (compose.isEmpty) return const SizedBox.shrink();
    final leading = compose.take(2).map((c) => '${c.name} ${c.pct.round()}%').join(' · ');
    final label = compose.length > 2 ? '$leading · 其他' : leading;

    return Row(
      children: [
        Text('渠道构成', style: LhTypography.sans(size: 9.5, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 0.6)),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
                children: compose.map((c) => Expanded(
                  flex: c.pct.round().clamp(1, 100),
                  child: Container(
                    color: c.color,
                  ),
                )).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: LhTypography.mono(size: 8.5, color: LhColors.mute2, weight: FontWeight.w500, letterSpacing: 0.2),
        ),
      ],
    );
  }

  /// HUN 占比条（U / N / H 三色），与 _buildComposeBar 视觉对齐。
  /// 用当前 rows 的成本拆分汇总（带 hun 过滤后的实际可见 rows）。
  Widget _buildHunComposeBar(List<Map<String, dynamic>> rows) {
    double sumU = 0, sumN = 0, sumH = 0;
    int countU = 0, countN = 0, countMixed = 0;
    for (final r in rows) {
      final h = _hunOf(r);
      sumU += h.u;
      sumN += h.n;
      sumH += h.h;
      switch (h.primary) {
        case 'U': countU++; break;
        case 'N': countN++; break;
        case 'mixed': countMixed++; break;
      }
    }
    final total = sumU + sumN + sumH;
    if (total <= 0) return const SizedBox.shrink();

    final uPct = (sumU / total * 100);
    final nPct = (sumN / total * 100);
    final hPct = (sumH / total * 100);

    String segLabel(String token, double pct, int count) {
      if (pct < 0.5) return '';
      return '${_hunBadgeFor(token)} ${pct.round()}%';
    }

    final partsBuf = <String>[];
    final uTxt = segLabel('U', uPct, countU);
    final nTxt = segLabel('N', nPct, countN);
    final hTxt = segLabel('H', hPct, 0);
    if (uTxt.isNotEmpty) partsBuf.add(uTxt);
    if (nTxt.isNotEmpty) partsBuf.add(nTxt);
    if (hTxt.isNotEmpty) partsBuf.add(hTxt);
    if (countMixed > 0) partsBuf.add('${_hunLabelFor('mixed')} $countMixed');
    final label = partsBuf.join(' · ');

    return Row(
      children: [
        Text('${_hunBarTitle()} 占比', style: LhTypography.sans(size: 9.5, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 0.6)),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  if (uPct > 0.5)
                    Expanded(flex: uPct.round().clamp(1, 100), child: Container(color: _hunColorFor('U'))),
                  if (nPct > 0.5)
                    Expanded(flex: nPct.round().clamp(1, 100), child: Container(color: _hunColorFor('N'))),
                  if (hPct > 0.5)
                    Expanded(flex: hPct.round().clamp(1, 100), child: Container(color: _hunColorFor('H'))),
                  if (uPct < 0.5 && nPct < 0.5 && hPct < 0.5)
                    Expanded(child: Container(color: LhColors.line2)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label.isEmpty ? '—' : label,
          style: LhTypography.mono(size: 8.5, color: LhColors.mute2, weight: FontWeight.w500, letterSpacing: 0.2),
        ),
      ],
    );
  }

  Widget _buildHeroGrid(List<_HeroMetric> metrics, Map<String, double> totals, bool filterActive) {
    return LayoutBuilder(builder: (context, constraints) {
      final availW = constraints.maxWidth;
      const cols = 3;
      const colGap = 12.0;
      final cw = (availW - colGap * (cols - 1)) / cols;

      // 把 metrics 按 cols 一组分行
      final rows = <List<_HeroMetric>>[];
      for (int i = 0; i < metrics.length; i += cols) {
        rows.add(metrics.skip(i).take(cols).toList());
      }

      final widgets = <Widget>[];
      for (int r = 0; r < rows.length; r++) {
        final rowMetrics = rows[r];
        final rowCells = <Widget>[];
        for (int c = 0; c < cols; c++) {
          if (c < rowMetrics.length) {
            rowCells.add(_buildHeroCell(rowMetrics[c], totals, filterActive, cw));
          } else {
            rowCells.add(SizedBox(width: cw)); // 空位占位，保持列对齐
          }
          if (c < cols - 1) rowCells.add(const SizedBox(width: colGap));
        }
        widgets.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rowCells,
          ),
        ));
        // Hairline divider between rows (editorial 杂志感)
        if (r < rows.length - 1) {
          widgets.add(Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 11),
            color: LhColors.line2,
          ));
        }
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
    });
  }

  /// Hero 小格：未筛选时读 metrics.*V/*U（含 revenue/cost/tax）；筛选后读当前可见行汇总。
  Widget _buildHeroCell(_HeroMetric m, Map<String, double> totals, bool filterActive, double width) {
    final mtr = _bundle?.metrics ?? const <String, dynamic>{};
    final Widget valueRow;

    if (!filterActive && m.key == 'rate') {
      final rate = (mtr['rate'] as num?)?.toDouble();
      valueRow = rate == null
          ? Text('—', style: LhTypography.sans(size: 18, weight: FontWeight.w700, color: LhColors.mute2))
          : _heroRateText(rate);
    } else if (!filterActive && mtr.containsKey('${m.key}V')) {
      final raw = (mtr['${m.key}V'] as num?)?.toDouble() ?? 0;
      final unit = mtr['${m.key}U']?.toString() ?? '';
      valueRow = _heroMetricsAmountText(raw, unit);
    } else {
      final raw = totals[m.key] ?? 0;
      if (m.isRate) {
        valueRow = raw == 0
            ? Text('—', style: LhTypography.sans(size: 18, weight: FontWeight.w700, color: LhColors.mute2))
            : _heroRateText(raw);
      } else if (raw == 0 && filterActive) {
        valueRow = Text('—', style: LhTypography.sans(size: 18, weight: FontWeight.w700, color: LhColors.mute2));
      } else {
        valueRow = _heroRowAmountText(raw);
      }
    }

    // ── 环比 tag（有后端数据才展示） ─────────────────────────────────────────
    final d = _deltaForMetric(m.key);
    final deltaUnit = m.isRate ? 'pp' : '%';

    return SizedBox(
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _metricPageKey = m.key),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              m.label.toUpperCase(),
              style: LhTypography.mono(
                size: 8.5,
                color: LhColors.mute2,
                weight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: valueRow),
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(color: m.cellColor, shape: BoxShape.circle),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  d == null ? '—' : '${d.isUp ? '↑' : '↓'} ${d.pct.toStringAsFixed(1)}$deltaUnit',
                  style: LhTypography.mono(
                    size: 9.5,
                    color: d == null ? LhColors.mute2 : (d.isUp ? LhColors.pos : LhColors.neg),
                    weight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded,
                    size: 12, color: LhColors.mute2),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 指标分析页（per-metric drill-down）
  //   点 hero 小格 → 进入这个页面：单指标视角，三维度拆解 + 完整列表
  //   六个指标：profit / gmv / rate / revenue / cost (or totalCost) / tax
  // ═══════════════════════════════════════════════════════════════════════

  /// 指标 → 中文标签
  String _metricPageLabel(String key) {
    const labels = {
      'profit': '毛利润',
      'gmv': '引流GMV',
      'rate': '毛利率',
      'revenue': '收入',
      'cost': '业务成本',
      'totalCost': '成本',
      'tax': '税务成本',
    };
    return labels[key] ?? key;
  }

  /// 指标 → 该维度强调色
  Color _metricPageAccent(String key) {
    switch (key) {
      case 'profit':
        return LhColors.pos;
      case 'rate':
        return LhColors.copper;
      case 'gmv':
        return LhColors.product;
      case 'revenue':
        return LhColors.cnpc;
      case 'cost':
      case 'totalCost':
      case 'tax':
        return LhColors.neg;
      default:
        return LhColors.ink;
    }
  }

  /// 顶部胶囊（hero 数字）格式化 — 复用现有渲染器
  Widget _metricPageHeroNumber(String key) {
    final mtr = _bundle?.metrics ?? const <String, dynamic>{};
    if (key == 'rate') {
      final rate = (mtr['rate'] as num?)?.toDouble();
      if (rate == null) {
        return Text('—', style: LhTypography.sans(size: 34, weight: FontWeight.w700, color: LhColors.mute2));
      }
      return RichText(
        text: TextSpan(children: [
          TextSpan(text: rate.toStringAsFixed(2), style: LhTypography.sans(size: 34, weight: FontWeight.w700, color: LhColors.ink, letterSpacing: -0.6, height: 1.0)),
          TextSpan(text: ' %', style: LhTypography.mono(size: 14, color: LhColors.mute, weight: FontWeight.w500)),
        ]),
      );
    }
    if (mtr.containsKey('${key}V')) {
      final raw = (mtr['${key}V'] as num?)?.toDouble() ?? 0;
      final unit = mtr['${key}U']?.toString() ?? '';
      final isNeg = raw < 0;
      final v = raw.abs().toString().replaceAll(RegExp(r'\.0$'), '');
      return RichText(
        text: TextSpan(children: [
          if (isNeg) TextSpan(text: '-', style: LhTypography.sans(size: 34, weight: FontWeight.w700, color: LhColors.neg, letterSpacing: -0.6, height: 1.0)),
          TextSpan(text: v, style: LhTypography.sans(size: 34, weight: FontWeight.w700, color: isNeg ? LhColors.neg : LhColors.ink, letterSpacing: -0.6, height: 1.0)),
          if (unit.isNotEmpty) TextSpan(text: ' $unit', style: LhTypography.mono(size: 13, color: LhColors.mute, weight: FontWeight.w500)),
        ]),
      );
    }
    // 后端没给 metricV/U → 用前端各行汇总
    double sum = 0;
    for (final r in _bundle?.rowsOf(_tab) ?? const []) {
      sum += (r[key] as num?)?.toDouble() ?? 0;
    }
    final isNeg = sum < 0;
    return RichText(
      text: TextSpan(children: [
        if (isNeg) TextSpan(text: '-', style: LhTypography.sans(size: 34, weight: FontWeight.w700, color: LhColors.neg, letterSpacing: -0.6, height: 1.0)),
        TextSpan(text: _fmt(sum.abs()), style: LhTypography.sans(size: 34, weight: FontWeight.w700, color: isNeg ? LhColors.neg : LhColors.ink, letterSpacing: -0.6, height: 1.0)),
        TextSpan(text: ' ${_unit(sum.abs())}元', style: LhTypography.mono(size: 13, color: LhColors.mute, weight: FontWeight.w500)),
      ]),
    );
  }

  /// 某一行在该指标上的值 — 对于 rate 等需要派生的指标做兜底
  double _rowMetricValue(Map<String, dynamic> r, String key) {
    if (key == 'rate') {
      final sales = (r['sales'] as num?)?.toDouble() ?? 0;
      final profit = (r['profit'] as num?)?.toDouble() ?? 0;
      return sales > 0 ? profit / sales * 100 : 0;
    }
    return (r[key] as num?)?.toDouble() ?? 0;
  }

  /// 某行的"权重值" — rate 页用 profit 做排序权重（避免低销量小行被高 rate 排前）
  double _rowWeightForMetric(Map<String, dynamic> r, String key) {
    if (key == 'rate') return (r['profit'] as num?)?.toDouble() ?? 0;
    return _rowMetricValue(r, key).abs();
  }

  /// 指标分析页主体
  Widget _buildMetricAnalysisPage(String key) {
    final label = _metricPageLabel(key);
    final accent = _metricPageAccent(key);
    final delta = _deltaForMetric(key);
    final deltaUnit = key == 'rate' ? 'pp' : '%';

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          // ── Top bar ──
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 14, 10),
            decoration: BoxDecoration(
              color: LhColors.paper,
              border: Border(
                bottom: BorderSide(color: LhColors.line2, width: 1),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _metricPageKey = null),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.arrow_back_rounded, size: 20, color: LhColors.ink),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: LhTypography.sans(
                    size: 16,
                    color: LhColors.ink,
                    weight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _periodInstanceLabel(_period, _periodOffset),
                  style: LhTypography.mono(
                    size: 10,
                    color: LhColors.mute,
                    weight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                _buildPill(),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // ── Hero card ──
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                  decoration: BoxDecoration(
                    color: LhColors.paper,
                    border: Border.all(color: LhColors.line2, width: 1),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: accent.withAlpha(10), blurRadius: 16, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: LhTypography.mono(size: 9, color: LhColors.mute2, weight: FontWeight.w700, letterSpacing: 1.8),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(child: _metricPageHeroNumber(key)),
                          if (delta != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: (delta.isUp ? LhColors.pos : LhColors.neg).withAlpha(18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${delta.isUp ? '↑' : '↓'} ${delta.pct.toStringAsFixed(1)}$deltaUnit',
                                style: LhTypography.mono(
                                  size: 11,
                                  color: delta.isUp ? LhColors.pos : LhColors.neg,
                                  weight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_heroInfo.deltaVs} · ${_heroInfo.label}',
                        style: LhTypography.sans(size: 10.5, color: LhColors.mute),
                      ),
                      const SizedBox(height: 12),
                      _metricPageSecondaryRow(key),
                    ],
                  ),
                ),
                // ── 三维度 TOP 5 ──
                _metricPageSection('按维度', '产品 × 供给 × 渠道'),
                _metricDimensionBreakdown(key, 'product', '产品', accent),
                _metricDimensionBreakdown(key, 'supply', '供给方', accent),
                _metricDimensionBreakdown(key, 'channel', '渠道', accent),
                // ── 完整列表（按当前 tab） ──
                _metricPageSection(
                  '完整列表',
                  '当前${{'product': '产品', 'supply': '供给', 'channel': '渠道', 'analysis': '产品'}[_tab]} · 按$label降序',
                ),
                _metricFullList(key, accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// hero 卡里第二行：补充关联指标（毛利率 page 显示绝对毛利，反之亦然）
  Widget _metricPageSecondaryRow(String key) {
    final mtr = _bundle?.metrics ?? const <String, dynamic>{};
    final pairs = <(String, String)>[];
    switch (key) {
      case 'profit':
        final r = (mtr['rate'] as num?)?.toDouble();
        if (r != null) pairs.add(('毛利率', '${r.toStringAsFixed(2)}%'));
        break;
      case 'rate':
        final p = (mtr['profitV'] as num?)?.toDouble();
        final pu = mtr['profitU']?.toString() ?? '';
        if (p != null) pairs.add(('绝对毛利', '¥${p.toStringAsFixed(2)}$pu'));
        break;
      case 'gmv':
        final s = (mtr['salesV'] as num?)?.toDouble();
        final g = (mtr['gmvV'] as num?)?.toDouble();
        if (s != null && g != null && s > 0) {
          pairs.add(('销售/GMV', '${(s / g * 100).toStringAsFixed(1)}%'));
        }
        break;
      case 'revenue':
        final s = (mtr['salesV'] as num?)?.toDouble();
        final r = (mtr['revenueV'] as num?)?.toDouble();
        if (s != null && r != null && s > 0) {
          pairs.add(('收入率', '${(r / s * 100).toStringAsFixed(1)}%'));
        }
        break;
      case 'cost':
      case 'totalCost':
        final s = (mtr['salesV'] as num?)?.toDouble();
        final c = (mtr['${key}V'] as num?)?.toDouble();
        if (s != null && c != null && s > 0) {
          pairs.add(('成本率', '${(c / s * 100).toStringAsFixed(1)}%'));
        }
        break;
      case 'tax':
        final r = (mtr['revenueV'] as num?)?.toDouble();
        final t = (mtr['taxV'] as num?)?.toDouble();
        if (r != null && t != null && r > 0) {
          pairs.add(('税负率', '${(t / r * 100).toStringAsFixed(1)}%'));
        }
        break;
    }
    if (pairs.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: pairs.map((p) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(p.$1, style: LhTypography.mono(size: 9.5, color: LhColors.mute2, weight: FontWeight.w600, letterSpacing: 0.6)),
          const SizedBox(width: 5),
          Text(p.$2, style: LhTypography.sans(size: 13, color: LhColors.ink2, weight: FontWeight.w600)),
        ],
      )).toList(),
    );
  }

  /// 段落标题（"§ 维度" 之类）
  Widget _metricPageSection(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: LhTypography.sans(size: 14, color: LhColors.ink, weight: FontWeight.w700, letterSpacing: 0.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Container(height: 1, color: LhColors.line2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            sub,
            style: LhTypography.mono(size: 9.5, color: LhColors.mute2, weight: FontWeight.w600, letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }

  /// 单维度 TOP 5 区块
  Widget _metricDimensionBreakdown(String key, String dim, String dimLabel, Color accent) {
    final rows = _bundle?.rowsOf(dim) ?? const [];
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Text('$dimLabel：无数据', style: LhTypography.mono(size: 10, color: LhColors.mute2)),
      );
    }
    final sorted = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) => _rowWeightForMetric(b, key).compareTo(_rowWeightForMetric(a, key)));
    final top = sorted.take(5).toList();

    // 计算 bar 比例的分母（top 之和 or 全部之和）
    double maxAbs = 0;
    for (final r in top) {
      final v = _rowMetricValue(r, key).abs();
      if (v > maxAbs) maxAbs = v;
    }
    if (maxAbs == 0) maxAbs = 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: LhColors.line2, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                dimLabel,
                style: LhTypography.mono(size: 9.5, color: LhColors.mute, weight: FontWeight.w700, letterSpacing: 1.6),
              ),
              const SizedBox(width: 6),
              Text(
                'TOP ${top.length} / 共 ${rows.length}',
                style: LhTypography.mono(size: 9, color: LhColors.mute2, weight: FontWeight.w500, letterSpacing: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < top.length; i++)
            _metricBreakdownRow(top[i], key, i + 1, maxAbs, accent),
        ],
      ),
    );
  }

  /// 单行 bar：rank + name + group chip + 条形 + 数值
  Widget _metricBreakdownRow(Map<String, dynamic> r, String key, int rank, double maxAbs, Color accent) {
    final name = r['name']?.toString() ?? '—';
    final group = r['group']?.toString() ?? '';
    final v = _rowMetricValue(r, key);
    final isRate = key == 'rate';
    final isNeg = v < 0;
    final ratio = (v.abs() / maxAbs).clamp(0.0, 1.0);
    final groupColor = group.isEmpty ? LhColors.mute2 : lhGroupColor(group);

    final valueStr = isRate
        ? '${v.toStringAsFixed(2)}%'
        : '${isNeg ? '-' : ''}¥${_fmt(v.abs())}${_unit(v.abs())}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            child: Text(
              '$rank',
              style: LhTypography.mono(size: 10, color: LhColors.mute2, weight: FontWeight.w700, letterSpacing: 0.3),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: LhTypography.sans(size: 12, color: LhColors.ink, weight: FontWeight.w600, letterSpacing: 0.1),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (group.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: groupColor.withAlpha(20),
                          border: Border.all(color: groupColor.withAlpha(80), width: 0.6),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          group,
                          style: LhTypography.mono(size: 8.5, color: groupColor, weight: FontWeight.w700),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      valueStr,
                      style: LhTypography.sans(
                        size: 12,
                        color: isNeg ? LhColors.neg : LhColors.ink,
                        weight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: LhColors.line2.withAlpha(160),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: ratio,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isNeg ? LhColors.neg.withAlpha(180) : accent.withAlpha(190),
                        borderRadius: BorderRadius.circular(2),
                      ),
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

  /// 完整列表 — 当前 tab 全部行按此指标降序
  Widget _metricFullList(String key, Color accent) {
    final rows = _bundle?.rowsOf(_tab == 'analysis' ? 'product' : _tab) ?? const [];
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Text('无数据', style: LhTypography.mono(size: 11, color: LhColors.mute2)),
      );
    }
    final sorted = List<Map<String, dynamic>>.from(rows)
      ..sort((a, b) => _rowWeightForMetric(b, key).compareTo(_rowWeightForMetric(a, key)));

    double maxAbs = 0;
    for (final r in sorted) {
      final v = _rowMetricValue(r, key).abs();
      if (v > maxAbs) maxAbs = v;
    }
    if (maxAbs == 0) maxAbs = 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: LhColors.line2, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < sorted.length; i++) ...[
            if (i > 0)
              Container(height: 0.5, color: LhColors.line2.withAlpha(140)),
            _metricBreakdownRow(sorted[i], key, i + 1, maxAbs, accent),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 指标分析页 END
  // ═══════════════════════════════════════════════════════════════════════

  Widget _heroRateText(double rate) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: rate.toStringAsFixed(2), style: LhTypography.sans(size: 18, weight: FontWeight.w700, color: LhColors.ink, letterSpacing: -0.4)),
          TextSpan(text: '%', style: LhTypography.mono(size: 10, color: LhColors.mute, weight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// 后端 metrics.*V/*U（已按万/亿换算）。
  Widget _heroMetricsAmountText(double raw, String unit) {
    final isNeg = raw < 0;
    final v = raw.abs().toString().replaceAll(RegExp(r'\.0$'), '');
    return RichText(
      text: TextSpan(
        children: [
          if (isNeg) TextSpan(text: '-', style: LhTypography.sans(size: 18, weight: FontWeight.w700, color: LhColors.neg, letterSpacing: -0.4)),
          TextSpan(text: v, style: LhTypography.sans(size: 18, weight: FontWeight.w700, color: isNeg ? LhColors.neg : LhColors.ink, letterSpacing: -0.4)),
          if (unit.isNotEmpty) TextSpan(text: unit, style: LhTypography.mono(size: 10, color: LhColors.mute, weight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// 筛选态：对可见行原值（元）做前端格式化。
  Widget _heroRowAmountText(double raw) {
    final isNeg = raw < 0;
    final u = _unit(raw.abs());
    final v = _fmt(raw.abs());
    return RichText(
      text: TextSpan(
        children: [
          if (isNeg) TextSpan(text: '-', style: LhTypography.sans(size: 18, weight: FontWeight.w700, color: LhColors.neg, letterSpacing: -0.4)),
          TextSpan(text: v, style: LhTypography.sans(size: 18, weight: FontWeight.w700, color: isNeg ? LhColors.neg : LhColors.ink, letterSpacing: -0.4)),
          if (u.isNotEmpty) TextSpan(text: u, style: LhTypography.mono(size: 10, color: LhColors.mute, weight: FontWeight.w500)),
        ],
      ),
    );
  }

  /// 读取 hero 各指标环比；缺字段或 flat 返回 null（显示 —）。
  ({double pct, bool isUp})? _deltaForMetric(String key) {
    final m = _bundle?.metrics ?? const <String, dynamic>{};
    final pctKey = key == 'rate' ? 'rateDeltaPp' : '${key}DeltaPct';
    final dirKey = key == 'rate' ? 'rateDeltaDir' : '${key}DeltaDir';
    if (!m.containsKey(pctKey)) return null;
    final realDir = m[dirKey]?.toString();
    if (realDir == 'flat') return null;
    final realPct = (m[pctKey] as num?)?.toDouble() ?? 0;
    return (pct: realPct.abs(), isUp: realDir != 'down');
  }

  // ───── Tab Segment ────────────────────────────────────────────────────────
  Widget _buildTabSegment() {
    final tabs = [
      {'key': 'product', 'label': '产品', 'accent': LhColors.product},
      {'key': 'supply', 'label': '供给方', 'accent': LhColors.sinopec},
      {'key': 'channel', 'label': '渠道', 'accent': LhColors.carrier},
      {'key': 'analysis', 'label': '分析', 'accent': LhColors.copper},
    ];
    final counts = {
      'product': _bundle?.rowsOf('product').length ?? 0,
      'supply': _bundle?.rowsOf('supply').length ?? 0,
      'channel': _bundle?.rowsOf('channel').length ?? 0,
      'analysis': 0,
    };

    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: LhColors.line2, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: tabs.map((t) {
            final key = t['key']! as String;
            final label = t['label']! as String;
            final accent = t['accent']! as Color;
            final isOn = _tab == key;
            final count = counts[key] ?? 0;
            final isAnalysis = key == 'analysis';

            return Expanded(
              child: GestureDetector(
                onTap: () {
                  if (key == _tab) return;
                  _closeDropdown();
                  setState(() {
                    _tab = key;
                    _groupFilter = '全部';
                    if (key != 'supply') _supplyFuelFilter = '全部';
                    if (key != 'supply' && key != 'channel') _hunFilter = '全部';
                    _listPage = 1;
                  });
                  if (key == 'analysis') _loadAnalysisCube();
                },
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.bottomCenter,
                  children: [
                    if (isOn)
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [accent.withAlpha(20), accent.withAlpha(0)],
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            label,
                            style: LhTypography.sans(
                              size: 14.5,
                              color: isOn ? accent : LhColors.mute,
                              weight: isOn ? FontWeight.w700 : FontWeight.w500,
                              letterSpacing: 1,
                            ),
                          ),
                          if (!isAnalysis) ...[
                            const SizedBox(width: 5),
                            Text(
                              '$count',
                              style: LhTypography.mono(
                                size: 10,
                                color: isOn ? accent.withAlpha(191) : LhColors.mute2,
                                weight: isOn ? FontWeight.w600 : FontWeight.w500,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isOn)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(height: 2.5, color: accent),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ───── Sort Bar ───────────────────────────────────────────────────────────
  Widget _buildSortbar() {
    final rows = _currentRows;
    final String totalStr;
    if (_listFilterActive) {
      double total = 0;
      for (final r in rows) {
        total += (r['profit'] as num?)?.toDouble() ?? 0;
      }
      totalStr = '筛选 ${rows.length} 项 · 毛利 ¥${_fmt(total)}${_unit(total)}';
    } else {
      final p = _heroInfo;
      totalStr = '本期毛利 ¥${p.profitV}${p.profitU} · 列表 ${rows.length} 项';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = _buildDropdownActions(
            showCategory: true,
            showMetric: true,
            showFilter: _hasUiFilter(_tab, 'fuel'),
            showHun: _hasUiFilter(_tab, 'hun'),
          );
          final narrow = constraints.maxWidth < 340;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  totalStr,
                  style: LhTypography.mono(size: 9, color: LhColors.mute, letterSpacing: 0.2),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: actions,
                  ),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  totalStr,
                  style: LhTypography.mono(size: 9, color: LhColors.mute, letterSpacing: 0.2),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: actions,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// HTML `.sortbar .actions` — buttons + dropdown anchor (position:absolute; right:0)
  Widget _buildDropdownActions({
    required bool showCategory,
    required bool showMetric,
    bool showFilter = false,
    bool showHun = false,
  }) {
    final tab = _metricsTab;
    final catActive = _groupFilter != '全部';
    final filterActive = _tab == 'supply' && _supplyFuelFilter != '全部';
    final hunActive = (_tab == 'supply' || _tab == 'channel') && _hunFilter != '全部';
    final selectedMetrics = _metrics[tab] ?? [];
    final fullCount = _liveMetrics(tab).length;
    final metricActive = selectedMetrics.length != fullCount;
    final ddOn = _ddMode != _DdMode.none;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showCategory) ...[
          KeyedSubtree(
            key: _btnKeyCategory,
            child: _buildSortBtn(
              icon: Icons.grid_view_rounded,
              label: catActive ? _groupFilter : '分类',
              active: catActive || (_ddMode == _DdMode.category),
              onTap: () => _toggleDropdown(_DdMode.category),
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (showMetric) ...[
          KeyedSubtree(
            key: _btnKeyMetric,
            child: _buildSortBtn(
              icon: Icons.bar_chart_rounded,
              label: '指标',
              active: metricActive || ddOn && _ddMode == _DdMode.metric,
              badge: '${selectedMetrics.length}',
              onTap: () => _toggleDropdown(_DdMode.metric),
            ),
          ),
        ],
        if (showFilter) ...[
          const SizedBox(width: 6),
          KeyedSubtree(
            key: _btnKeyFilter,
            child: _buildSortBtn(
              icon: Icons.filter_list_rounded,
              label: filterActive
                  ? _supplyFuelFilter
                  : (_uiFilterDef(_tab, 'fuel')?['label'] as String? ?? '筛选'),
              active: filterActive || (_ddMode == _DdMode.filter),
              onTap: () => _toggleDropdown(_DdMode.filter),
            ),
          ),
        ],
        if (showHun) ...[
          const SizedBox(width: 6),
          KeyedSubtree(
            key: _btnKeyHun,
            child: _buildSortBtn(
              icon: Icons.scatter_plot_rounded,
              label: hunActive
                  ? _hunFilter
                  : (_uiFilterDef(_tab, 'hun')?['label'] as String? ?? 'U/N'),
              active: hunActive || (_ddMode == _DdMode.hun),
              onTap: () => _toggleDropdown(_DdMode.hun),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSortBtn({
    required IconData icon,
    required String label,
    required bool active,
    String? badge,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? LhColors.ink.withAlpha(8) : LhColors.paper,
          border: Border.all(color: active ? LhColors.ink2 : LhColors.line, width: 1),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 11, color: active ? LhColors.ink : LhColors.mute),
            const SizedBox(width: 4),
            Text(label, style: LhTypography.sans(size: 10, color: active ? LhColors.ink : LhColors.mute, weight: FontWeight.w500, letterSpacing: 0.2)),
            if (badge != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                constraints: const BoxConstraints(minWidth: 13, minHeight: 13),
                decoration: BoxDecoration(
                  color: LhColors.copper,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(badge, style: LhTypography.mono(size: 8.5, color: Colors.white, weight: FontWeight.w700), textAlign: TextAlign.center),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ───── Discount Section (supply only) ────────────────────────────────────
  Widget _buildDiscountSection() {
    final allRows = _discountRowsFromBundle();
    if (allRows.isEmpty) return const SizedBox.shrink();

    final sorted = allRows.toList()..sort((a, b) => b.rebate.compareTo(a.rebate));
    final fixedCount = allRows.where((r) => r.isFixed).length;
    final ladderCount = allRows.where((r) => r.isLadder).length;
    final otherCount = allRows.length - fixedCount - ladderCount;
    final remaining = sorted.length - _discountPreviewCount;
    final showAll = _discountExpanded || sorted.length <= _discountPreviewCount;
    final visible = showAll ? sorted : sorted.take(_discountPreviewCount).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(22, 12, 22, 4),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: LhColors.line2, width: 1),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x05140A00), blurRadius: 2, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0F140A00), blurRadius: 14, spreadRadius: -8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('折扣与返点',
                      style: LhTypography.mono(size: 9.5, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 1.2)),
                  const SizedBox(height: 2),
                  Text(
                    showAll ? '${sorted.length} 家 · 按返点排序' : 'TOP $_discountPreviewCount · 共 ${sorted.length} 家',
                    style: LhTypography.mono(size: 9, color: LhColors.mute2, weight: FontWeight.w500, letterSpacing: 0.3),
                  ),
                ],
              ),
              if (remaining > 0)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _discountExpanded = !_discountExpanded),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _discountExpanded ? '收起' : '展开全部',
                        style: LhTypography.sans(size: 10, color: LhColors.copper, weight: FontWeight.w500),
                      ),
                      AnimatedRotation(
                        turns: _discountExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: LhColors.copper),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('规则表 zk_type/zk_mod · 底表累计+返佣 · 合约‰ vs 实收‰',
              style: LhTypography.sans(size: 9, color: LhColors.mute2, letterSpacing: 0.2)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildDiscountLegendChip('固定', LhColors.copper, fixedCount),
              _buildDiscountLegendChip('月/年阶梯', LhColors.cnpc, ladderCount),
              if (otherCount > 0)
                _buildDiscountLegendChip('无规则', LhColors.mute, otherCount),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < visible.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: Border(
                  top: i == 0
                      ? BorderSide.none
                      : const BorderSide(color: LhColors.line2, width: 0.5),
                ),
              ),
              child: _buildDiscountRow(visible[i]),
            ),
          if (remaining > 0)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _discountExpanded = !_discountExpanded),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: LhColors.line2, width: 0.5)),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _discountExpanded ? '收起' : '展开剩余 $remaining 家',
                      style: LhTypography.sans(size: 10.5, color: LhColors.copper, weight: FontWeight.w500, letterSpacing: 0.3),
                    ),
                    if (_discountExpanded) ...[
                      const SizedBox(width: 2),
                      AnimatedRotation(
                        turns: 0.5,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: LhColors.copper),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiscountLegendChip(String label, Color color, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80), width: 0.5),
      ),
      child: Text('$label $count',
          style: LhTypography.mono(size: 8.5, color: color, weight: FontWeight.w600, letterSpacing: 0.2)),
    );
  }

  /// 折扣返点行：类型标签 + 档位 + 底表金额 + 合约/实收 ‰ + 阶梯进度
  Widget _buildDiscountRow(_DiscountRow r) {
    final typeColor = _discountTypeColor(r);
    final modeLabel = r.mode ?? r.ruleType ?? '无规则';
    final baseHint = r.base != null ? ' · 基数${r.base}' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Text(r.province,
                  style: LhTypography.sans(size: 11.5, color: LhColors.ink, weight: FontWeight.w600, letterSpacing: 0.1)),
            ),
            Expanded(
              child: Wrap(
                spacing: 5,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: typeColor.withAlpha(18),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: typeColor.withAlpha(100), width: 0.5),
                    ),
                    child: Text(modeLabel,
                        style: LhTypography.mono(size: 8.5, color: typeColor, weight: FontWeight.w600, letterSpacing: 0.2)),
                  ),
                  if (r.tierLabel != null)
                    Text(r.tierLabel!,
                        style: LhTypography.mono(size: 8.5, color: LhColors.mute2, weight: FontWeight.w500)),
                  if (r.tierCount != null && r.tierCount! > 1)
                    Text('共${r.tierCount}档',
                        style: LhTypography.mono(size: 8, color: LhColors.mute2)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('累计 ${(r.cur / 10000).toStringAsFixed(1)} 万$baseHint',
                    style: LhTypography.sans(size: 10, color: LhColors.mute, letterSpacing: 0.1)),
                RichText(
                  text: TextSpan(children: [
                    TextSpan(text: '返 ', style: LhTypography.sans(size: 9, color: LhColors.mute2)),
                    TextSpan(
                      text: (r.rebate / 10000).toStringAsFixed(r.rebate >= 1e5 ? 1 : 2),
                      style: LhTypography.sans(size: 11, color: LhColors.pos, weight: FontWeight.w700),
                    ),
                    TextSpan(text: ' 万', style: LhTypography.mono(size: 8.5, color: LhColors.mute)),
                  ]),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.only(left: 52),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_discountRateLine(r),
                  style: LhTypography.mono(size: 8.5, color: LhColors.mute2, weight: FontWeight.w600, letterSpacing: 0.2)),
              if (r.hasNext) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (r.progress ?? 0).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: const Color(0x0B140A00),
                    color: typeColor.withAlpha(180),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '→ ${_fmtPermille(r.nextRate)} · 差 ${(r.gapToNext! / 10000).toStringAsFixed(1)} 万 · ${((r.progress ?? 0) * 100).round()}%',
                  style: LhTypography.mono(size: 8, color: LhColors.mute2, letterSpacing: 0.2),
                ),
              ] else if (r.isFixed) ...[
                const SizedBox(height: 2),
                Text('封顶 · 无下一档',
                    style: LhTypography.mono(size: 8, color: LhColors.mute2)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ───── List ───────────────────────────────────────────────────────────────
  Widget _buildList() {
    if (_loading) {
      return const SizedBox(height: 240);
    }
    if (_loadError != null) {
      if (_isNoPermissionError(_loadError)) {
        return _buildNoAccessView();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 40),
        child: Column(
          children: [
            Text('数据加载失败', style: LhTypography.sans(size: 14, color: LhColors.ink, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_loadError!, textAlign: TextAlign.center, style: LhTypography.sans(size: 11, color: LhColors.mute)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () {
                setState(() {
                  _loading = true;
                  _loadError = null;
                });
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: LhColors.copperSoft,
                  border: Border.all(color: LhColors.copper),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('重试', style: LhTypography.sans(size: 12, color: LhColors.copper, weight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }
    final rows = _currentRows;
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text('暂无数据', style: LhTypography.sans(size: 12, color: LhColors.mute))),
      );
    }
    final totalPages = _totalPages(rows.length);
    final page = _listPage.clamp(1, totalPages);
    final start = (page - 1) * _pageSize;
    final end = (start + _pageSize).clamp(0, rows.length);
    final visible = rows.sublist(start, end);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
      child: Column(
        children: [
          for (int i = 0; i < visible.length; i++)
            _buildListItem(visible[i], start + i),
          if (totalPages > 1) ...[
            const SizedBox(height: 8),
            _buildPageBar(
              currentPage: page,
              totalPages: totalPages,
              onPageSelected: (p) => setState(() => _listPage = p),
            ),
          ],
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════════════════════════════════
  // ─── ANALYSIS VIEW ───────────────────────────────────────────────────────
  // 第 4 tab「分析」：3D 坐标 + 机会清单懒加载自 GET /lighthouse/analysis/cube
  // ═════════════════════════════════════════════════════════════════════════

  // ═════════════════════════════════════════════════════════════════════════
  // ─── ANALYSIS VIEW ───────────────────────────────────────────────────────
  // 「分析」tab 整页内容：
  //   - Header（数据分析标题 + 时段）
  //   - Stat strip（4 个关键数字）
  //   - § 01 3D 坐标（产品 × 供给方 × 渠道）── 主图
  //   - § 02 未点亮坐标（按潜在毛利排序的机会清单）
  // ═════════════════════════════════════════════════════════════════════════

  Widget _buildAnalysisView() {
    if (_cubeLoading && _cubeData == null) {
      return const SizedBox(height: 420);
    }
    if (_cubeError && _cubeData == null) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text('分析数据加载失败', style: LhTypography.sans(size: 12, color: LhColors.mute)),
        ),
      );
    }
    final cube = _cubeData ??
        const _CubeData(
          products: [],
          supplies: [],
          channels: [],
          lit: [],
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAnalysisHeader(),
          const SizedBox(height: 14),
          _AnalysisCard(
            index: '§ 01',
            title: '3D 坐标',
            sub: '产品 × 供给方 × 渠道',
            padContent: false,
            child: _buildCubeBody(cube),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '数据分析',
                style: LhTypography.sans(
                  size: 18,
                  color: LhColors.ink,
                  weight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_heroInfo.label}  ·  对比${_heroInfo.deltaVs.replaceFirst('vs ', '')}',
                style: LhTypography.mono(
                  size: 10.5,
                  color: LhColors.mute,
                  weight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: LhColors.pos.withAlpha(220),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '同步',
                  style: LhTypography.mono(
                    size: 9,
                    color: LhColors.mute2,
                    weight: FontWeight.w700,
                    letterSpacing: 1.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              _syncedAtLabel(),
              style: LhTypography.mono(
                size: 10.5,
                color: LhColors.ink2,
                weight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── § 01 3D 立方体 ────────────────────────────────────────────────────────
  /// 当前 filter 下此点是否匹配
  /// 5 维过滤（不含 owner）— 用于负责人 strip 聚合，让 strip 始终展示全部 owner 供对比。
  bool _cubeDimMatch(_CubePoint p) {
    if (_cubeProductGroup != '全部' && p.productGroup != _cubeProductGroup) return false;
    if (_cubeSupplyGroup != '全部' && p.supplyGroup != _cubeSupplyGroup) return false;
    if (_cubeSupplyHun != '全部' && p.supplyHun != _cubeSupplyHun) return false;
    if (_cubeChannelGroup != '全部' && p.channelGroup != _cubeChannelGroup) return false;
    if (_cubeChannelHun != '全部' && p.channelHun != _cubeChannelHun) return false;
    return true;
  }

  /// 完整过滤（5 维 + 选中 owner 硬过滤）— 驱动立方体亮点的显示与计数。
  bool _cubeMatch(_CubePoint p) {
    if (!_cubeDimMatch(p)) return false;
    if (_cubeSelectedOwner != null && p.owner != _cubeSelectedOwner) return false;
    return true;
  }

  bool get _cubeHasActiveFilter =>
      _cubeProductGroup != '全部' ||
      _cubeSupplyGroup != '全部' ||
      _cubeSupplyHun != '全部' ||
      _cubeChannelGroup != '全部' ||
      _cubeChannelHun != '全部';

  bool get _cubeHasOwnerFilter => _cubeSelectedOwner != null;

  void _cubeResetFilters() {
    setState(() {
      _cubeProductGroup = '全部';
      _cubeSupplyGroup = '全部';
      _cubeSupplyHun = '全部';
      _cubeChannelGroup = '全部';
      _cubeChannelHun = '全部';
      _cubeSelectedOwner = null;
      _cubeFilterOpen = null;
    });
  }

  String _cubePointKey(_CubePoint p) => '${p.xi}-${p.yi}-${p.zi}';

  Widget _buildCubeBody(_CubeData cube) {
    if (cube.products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          '数据不足，无法生成 3D 坐标',
          style: LhTypography.mono(size: 11, color: LhColors.mute),
        ),
      );
    }

    final dimMatched = cube.lit.where(_cubeDimMatch).toList();
    final matchedPoints = cube.lit.where(_cubeMatch).toList();
    final matchedSet = matchedPoints.map(_cubePointKey).toSet();
    final litShown = matchedPoints.length;

    // ── 第 4 维度: 负责人聚合 — 基于 5 维过滤后的 dimMatched（不含 owner 过滤），
    //    让 strip 始终展示全部 owner 供对比；立方体本身再按选中 owner 硬过滤。
    final ownerStats = <String, _OwnerStat>{};
    for (final c in dimMatched) {
      final s = ownerStats.putIfAbsent(c.owner, () => _OwnerStat());
      s.count++;
      s.totalValue += c.value.abs();
    }
    final sortedOwners = ownerStats.entries.toList()
      ..sort((a, b) => b.value.count.compareTo(a.value.count));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 负责人 strip（替代旧数字 strip，第 4 维度入口）──
        if (sortedOwners.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Row(
              children: [
                Text(
                  '负责人',
                  style: LhTypography.mono(
                    size: 9,
                    color: LhColors.mute2,
                    weight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${sortedOwners.length} 人 · ${matchedPoints.length} 坐标',
                  style: LhTypography.mono(
                    size: 9,
                    color: LhColors.mute,
                    weight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                if (_cubeSelectedOwner != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _cubeSelectedOwner = null),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close_rounded, size: 12, color: LhColors.copper),
                        const SizedBox(width: 2),
                        Text(
                          '清除',
                          style: LhTypography.mono(
                            size: 10,
                            color: LhColors.copper,
                            weight: FontWeight.w600,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            height: 36,
            child: Builder(
              builder: (ctx) {
                final ownerColors = _CubePainter.ownerColorMap(cube.lit);
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                  scrollDirection: Axis.horizontal,
                  itemCount: sortedOwners.length,
                  itemBuilder: (ctx, i) {
                    final e = sortedOwners[i];
                    final col = ownerColors[e.key] ?? LhColors.mute;
                    return _buildOwnerChip(e.key, e.value, matchedPoints.length, col);
                  },
                );
              },
            ),
          ),
        ],
        // Filter chip 行
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: _buildCubeFilterChips(cube),
        ),
        const SizedBox(height: 4),
        // 立方体 — 走全宽，高度随屏宽/屏高自适应（分析 tab 主视觉区尽量占满）
        LayoutBuilder(
          builder: (ctx, constraints) {
            final viewH = MediaQuery.sizeOf(ctx).height;
            final cubeH = (constraints.maxWidth * 1.08)
                .clamp(340.0, viewH * 0.52);
            final size = Size(constraints.maxWidth, cubeH);
            return SizedBox(
              height: cubeH,
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    _buildCubeInteractive(
                      cube,
                      size,
                      matched: matchedSet,
                      dimUnmatched: _cubeHasActiveFilter,
                    ),
                    // 视角控制 — 右上角：放大查看 + 重置视角
                    Positioned(
                      top: 6,
                      right: 8,
                      left: 8,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: _buildCubeViewControls(cube),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // 选中亮点详情卡（动画进出）
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _cubeSelectedKey == null
              ? const SizedBox(width: double.infinity)
              : _buildSelectedCubePointCard(cube),
        ),
        // 底部图例 — 极简版：覆盖率 mini progress bar + 紧凑文案
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
          child: _buildCubeLegend(cube, matchedShown: litShown),
        ),
      ],
    );
  }

  /// Owner chip — 横向 strip 里的一个负责人卡
  Widget _buildOwnerChip(String owner, _OwnerStat stat, int totalLit, Color accent) {
    final selected = _cubeSelectedOwner == owner;
    final initial = owner.isEmpty ? '?' : owner.substring(0, 1);
    final ratio = totalLit == 0 ? 0.0 : stat.count / totalLit;

    String fmtValue(double v) {
      if (v.abs() >= 10000) return '¥${(v / 10000).toStringAsFixed(1)}万';
      if (v.abs() >= 100) return '¥${v.toStringAsFixed(0)}';
      return '¥${v.toStringAsFixed(1)}';
    }

    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _cubeSelectedOwner = selected ? null : owner;
          _cubeSelectedKey = null; // 切 owner 时清掉选中坐标
        }),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 3, 7, 3),
          decoration: BoxDecoration(
            color: selected ? accent.withAlpha(18) : LhColors.paper,
            border: Border.all(
              color: selected ? accent : LhColors.line,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? accent : accent.withAlpha(22),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: LhTypography.sans(
                    size: 9,
                    color: selected ? Colors.white : accent,
                    weight: FontWeight.w700,
                    letterSpacing: -0.2,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                owner,
                style: LhTypography.sans(
                  size: 10,
                  color: selected ? accent : LhColors.ink,
                  weight: FontWeight.w600,
                  letterSpacing: -0.1,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                '${stat.count}',
                style: LhTypography.mono(
                  size: 8.5,
                  color: selected ? accent.withAlpha(220) : LhColors.mute,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                width: 18,
                height: 1.5,
                decoration: BoxDecoration(
                  color: LhColors.line2,
                  borderRadius: BorderRadius.circular(1),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: ratio.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected ? accent : accent.withAlpha(160),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                fmtValue(stat.totalValue),
                style: LhTypography.mono(
                  size: 8,
                  color: LhColors.mute2,
                  weight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 点击 cube 时：用 painter 的投影函数算出每个亮点的屏幕坐标，
  /// 找最近的，距离 ≤ 22px 视为命中；同一点再点 = 取消选中
  String? _cubeTapHitKey(Offset tap, _CubeData cube, Size size) {
    final positions = _CubePainter.projectLitPoints(
      cube, size,
      yaw: _cubeYaw,
      pitch: _cubePitch,
      scale: _cubeScale,
      pan: _cubePan,
    );
    String? hitKey;
    var bestDist = 22.0;
    positions.forEach((key, pos) {
      final d = (pos - tap).distance;
      if (d < bestDist) {
        bestDist = d;
        hitKey = key;
      }
    });
    return hitKey;
  }

  void _handleCubeTap(Offset tap, _CubeData cube, Size size) {
    final hitKey = _cubeTapHitKey(tap, cube, size);
    setState(() {
      if (hitKey == null) {
        _cubeSelectedKey = null;
      } else if (hitKey == _cubeSelectedKey) {
        _cubeSelectedKey = null;
      } else {
        _cubeSelectedKey = hitKey;
      }
    });
  }

  /// 共享的 cube 交互层 — 主页和全屏视图都用这个
  /// onExternalChange: 全屏 dialog 调用时传入 setDlg，让 dialog 也跟随重绘
  Widget _buildCubeInteractive(
    _CubeData cube,
    Size size, {
    required Set<String> matched,
    required bool dimUnmatched,
    VoidCallback? onExternalChange,
    VoidCallback? onRequestDismiss,
  }) {
    void mut(VoidCallback fn) {
      setState(fn);
      onExternalChange?.call();
    }

    return ClipRect(
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (d) {
        _cubeGestureStartFocal = d.localFocalPoint;
        _cubeGestureLastFocal = d.localFocalPoint;
        _cubeGestureStartTime = DateTime.now();
        _cubeGestureBaseScale = _cubeScale;
        _cubeGestureMaxMove = 0;
      },
      onScaleUpdate: (d) {
        if (_cubeGestureStartFocal != null) {
          final m = (d.localFocalPoint - _cubeGestureStartFocal!).distance;
          if (m > _cubeGestureMaxMove) _cubeGestureMaxMove = m;
        }
        final last = _cubeGestureLastFocal ?? d.localFocalPoint;
        final delta = d.localFocalPoint - last;
        _cubeGestureLastFocal = d.localFocalPoint;
        mut(() {
          if (d.pointerCount <= 1) {
            // 单指 → 旋转
            _cubeYaw += delta.dx * 0.012;
            _cubePitch = (_cubePitch - delta.dy * 0.012)
                .clamp(-math.pi / 2 + 0.05, math.pi / 2 - 0.05);
          } else {
            // 多指 → 缩放 + 平移
            _cubeScale =
                (_cubeGestureBaseScale * d.scale).clamp(0.5, 3.0);
            _cubePan += delta;
            // 限制平移，放大后不把图形拖出白色容器太多
            final maxPanX = size.width * 0.28 * _cubeScale;
            final maxPanY = size.height * 0.28 * _cubeScale;
            _cubePan = Offset(
              _cubePan.dx.clamp(-maxPanX, maxPanX),
              _cubePan.dy.clamp(-maxPanY, maxPanY),
            );
          }
        });
      },
      onScaleEnd: (d) {
        final start = _cubeGestureStartFocal;
        final startedAt = _cubeGestureStartTime;
        if (start != null && startedAt != null) {
          final dt = DateTime.now().difference(startedAt).inMilliseconds;
          if (onRequestDismiss != null && _cubeGestureMaxMove >= 24) {
            final end = _cubeGestureLastFocal ?? start;
            final dx = end.dx - start.dx;
            final dy = end.dy - start.dy;
            if (dx < -52 && dx.abs() > dy.abs() * 1.25) {
              onRequestDismiss();
              _cubeGestureStartFocal = null;
              _cubeGestureLastFocal = null;
              _cubeGestureStartTime = null;
              _cubeGestureMaxMove = 0;
              return;
            }
          }
          if (dt < 280 && _cubeGestureMaxMove < 8) {
            if (onRequestDismiss != null) {
              onRequestDismiss();
            } else {
              _handleCubeTap(start, cube, size);
              onExternalChange?.call();
            }
          }
        }
        _cubeGestureStartFocal = null;
        _cubeGestureLastFocal = null;
        _cubeGestureStartTime = null;
        _cubeGestureMaxMove = 0;
      },
      child: CustomPaint(
        size: size,
        painter: _CubePainter(
          data: cube,
          matched: matched,
          dimUnmatched: dimUnmatched,
          selectedKey: _cubeSelectedKey,
          selectedOwner: _cubeSelectedOwner,
          yaw: _cubeYaw,
          pitch: _cubePitch,
          scale: _cubeScale,
          pan: _cubePan,
          showAxisNames: _cubeShowAxisNames,
          showProductTicks: _cubeShowProductTicks,
          showSupplyLabels: _cubeShowSupplyLabels,
          showChannelLabels: _cubeShowChannelLabels,
          showOwnerInitials: _cubeShowOwnerInitials,
        ),
      ),
    ),
    );
  }

  /// 缩放 helper — +/− 按钮和键盘都用这个
  void _zoomCube(double factor, {VoidCallback? onExternalChange}) {
    setState(() {
      _cubeScale = (_cubeScale * factor).clamp(0.5, 3.0);
    });
    onExternalChange?.call();
  }

  void _resetCubeView({VoidCallback? onExternalChange}) {
    setState(() {
      _cubeYaw = _kCubeDefaultYaw;
      _cubePitch = _kCubeDefaultPitch;
      _cubeScale = 1.0;
      _cubePan = Offset.zero;
    });
    onExternalChange?.call();
  }

  bool get _cubeViewIsDefault =>
      (_cubeYaw - _kCubeDefaultYaw).abs() < 0.01 &&
      (_cubePitch - _kCubeDefaultPitch).abs() < 0.01 &&
      (_cubeScale - 1.0).abs() < 0.01 &&
      _cubePan == Offset.zero;

  /// 主页右上角的视角控制栏：[文字▾] [放大查看] [重置]
  /// + 文字按钮按下时下方展开 popup
  Widget _buildCubeViewControls(_CubeData cube) {
    final shownCount = (_cubeShowAxisNames ? 1 : 0) +
        (_cubeShowProductTicks ? 1 : 0) +
        (_cubeShowSupplyLabels ? 1 : 0) +
        (_cubeShowChannelLabels ? 1 : 0) +
        (_cubeShowOwnerInitials ? 1 : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
            // 文字开关
            _CubeChipButton(
              icon: _cubeTextPanelOpen
                  ? Icons.expand_less_rounded
                  : Icons.text_fields_rounded,
              label: '文字 $shownCount/5',
              color: shownCount == 5 ? LhColors.copper : LhColors.ink,
              onTap: () => setState(() {
                _cubeTextPanelOpen = !_cubeTextPanelOpen;
              }),
            ),
            const SizedBox(width: 6),
            // 放大查看按钮 — 一直可见，主功能
            _CubeChipButton(
              icon: Icons.zoom_out_map_rounded,
              label: '放大查看',
              color: LhColors.ink,
              onTap: () => _openCubeFullscreen(cube),
            ),
            const SizedBox(width: 6),
            // 重置 — 仅在视角偏离时高亮
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _cubeViewIsDefault ? 0.35 : 1.0,
              child: _CubeChipButton(
                icon: Icons.refresh_rounded,
                label: '重置',
                color: LhColors.ink,
                onTap: _cubeViewIsDefault ? null : () => _resetCubeView(),
              ),
            ),
          ],
        ),
        ),
        // 文字下拉面板（独立 Row 下方，紧贴对齐）
        if (_cubeTextPanelOpen) ...[
          const SizedBox(height: 6),
          _buildCubeTextPanel(),
        ],
      ],
    );
  }

  /// 文字显示下拉面板 — 5 个 toggle
  Widget _buildCubeTextPanel() {
    Widget toggleRow({
      required IconData icon,
      required String label,
      required String hint,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Icon(icon, size: 12,
                  color: value ? LhColors.copper : LhColors.mute2),
              const SizedBox(width: 7),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: LhTypography.sans(
                      size: 11,
                      color: value ? LhColors.ink : LhColors.mute,
                      weight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                  Text(
                    hint,
                    style: LhTypography.mono(
                      size: 8.5,
                      color: LhColors.mute2,
                      weight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // 自制小开关 — 比 Switch 更紧凑
              Container(
                width: 24,
                height: 14,
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: value
                      ? LhColors.copper.withAlpha(200)
                      : LhColors.line2,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  alignment:
                      value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 11, height: 11,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: LhColors.copper.withAlpha(110), width: 0.8),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
              child: Text(
                'LABELS · 文字显示',
                style: LhTypography.mono(
                  size: 8.5,
                  color: LhColors.copper,
                  weight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            Container(height: 0.6, color: LhColors.line2),
            toggleRow(
              icon: Icons.straighten_rounded,
              label: '产品轴',
              hint: 'X 轴「产品」轴名',
              value: _cubeShowAxisNames,
              onChanged: (v) => setState(() => _cubeShowAxisNames = v),
            ),
            Container(height: 0.6, color: LhColors.line2.withAlpha(120)),
            toggleRow(
              icon: Icons.label_outline_rounded,
              label: '产品名',
              hint: '每条 X 轴的产品标签',
              value: _cubeShowProductTicks,
              onChanged: (v) => setState(() => _cubeShowProductTicks = v),
            ),
            Container(height: 0.6, color: LhColors.line2.withAlpha(120)),
            toggleRow(
              icon: Icons.apartment_rounded,
              label: '供给',
              hint: 'Y 轴轴名 + 供给方标签',
              value: _cubeShowSupplyLabels,
              onChanged: (v) => setState(() => _cubeShowSupplyLabels = v),
            ),
            Container(height: 0.6, color: LhColors.line2.withAlpha(120)),
            toggleRow(
              icon: Icons.hub_outlined,
              label: '渠道',
              hint: 'Z 轴轴名 + 渠道标签',
              value: _cubeShowChannelLabels,
              onChanged: (v) => setState(() => _cubeShowChannelLabels = v),
            ),
            Container(height: 0.6, color: LhColors.line2.withAlpha(120)),
            toggleRow(
              icon: Icons.person_outline_rounded,
              label: '负责人',
              hint: '聚类圆里的首字',
              value: _cubeShowOwnerInitials,
              onChanged: (v) => setState(() => _cubeShowOwnerInitials = v),
            ),
          ],
        ),
      ),
    );
  }

  /// 全屏 dialog — 大尺寸 cube + +/- 按钮 + 详情卡
  void _openCubeFullscreen(_CubeData cube) {
    // 保存进入前的文字开关状态 — 关闭时还原
    final saved = <bool>[
      _cubeShowAxisNames,
      _cubeShowProductTicks,
      _cubeShowSupplyLabels,
      _cubeShowChannelLabels,
      _cubeShowOwnerInitials,
    ];
    // 默认放大后所有坐标标签全开
    setState(() {
      _cubeShowAxisNames = true;
      _cubeShowProductTicks = true;
      _cubeShowSupplyLabels = true;
      _cubeShowChannelLabels = true;
      _cubeShowOwnerInitials = true;
    });

    // 局部状态：右上角面板用 — 不污染主页
    bool filterOpen = false;
    bool textOpen = false;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(200),
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            void resync() => setDlg(() {});

            final matchedPoints = cube.lit.where(_cubeMatch).toList();
            final matchedSet = matchedPoints.map(_cubePointKey).toSet();

            return Dialog(
              insetPadding: EdgeInsets.zero,
              backgroundColor: LhColors.paper,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero,
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // ── Top bar：极简 — 关闭 + 坐标数 + 文字 + 筛选 + 重置 ──
                    Container(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: LhColors.line2.withAlpha(140),
                            width: 0.5,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(dialogCtx).pop(),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(Icons.close_rounded,
                                  size: 18, color: LhColors.ink),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${matchedPoints.length} 坐标',
                            style: LhTypography.mono(
                              size: 10,
                              color: LhColors.mute,
                              weight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const Spacer(),
                          // 文字开关
                          _CubeChipButton(
                            icon: textOpen
                                ? Icons.expand_less_rounded
                                : Icons.text_fields_rounded,
                            label: '文字',
                            color: textOpen ? LhColors.copper : LhColors.ink,
                            onTap: () => setDlg(() {
                              textOpen = !textOpen;
                              if (textOpen) filterOpen = false;
                            }),
                          ),
                          const SizedBox(width: 5),
                          // 筛选
                          _CubeChipButton(
                            icon: filterOpen
                                ? Icons.expand_less_rounded
                                : Icons.tune_rounded,
                            label: '筛选',
                            color: filterOpen
                                ? LhColors.copper
                                : (_cubeHasActiveFilter
                                    ? LhColors.copper
                                    : LhColors.ink),
                            onTap: () => setDlg(() {
                              filterOpen = !filterOpen;
                              if (filterOpen) textOpen = false;
                            }),
                          ),
                          const SizedBox(width: 5),
                          // 重置视角
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: _cubeViewIsDefault ? 0.35 : 1.0,
                            child: _CubeChipButton(
                              icon: Icons.refresh_rounded,
                              label: '重置',
                              color: LhColors.ink,
                              onTap: _cubeViewIsDefault
                                  ? null
                                  : () => _resetCubeView(onExternalChange: resync),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── 可折叠 — 筛选 / 文字面板 ──
                    if (filterOpen)
                      Listener(
                        onPointerUp: (_) =>
                            Future<void>.microtask(() => setDlg(() {})),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          decoration: BoxDecoration(
                            color: LhColors.paper,
                            border: Border(
                              bottom: BorderSide(
                                color: LhColors.line2.withAlpha(140),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: _buildCubeFilterChips(cube),
                        ),
                      ),
                    if (textOpen)
                      Listener(
                        onPointerUp: (_) =>
                            Future<void>.microtask(() => setDlg(() {})),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                          decoration: BoxDecoration(
                            color: LhColors.paper,
                            border: Border(
                              bottom: BorderSide(
                                color: LhColors.line2.withAlpha(140),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: _buildCubeTextPanel(),
                        ),
                      ),

                    // ── Cube 主体 ──
                    Expanded(
                      child: ClipRect(
                        child: LayoutBuilder(
                          builder: (ctx, c) {
                            final size = Size(c.maxWidth, c.maxHeight);
                            return Stack(
                              clipBehavior: Clip.hardEdge,
                              children: [
                                _buildCubeInteractive(
                                  cube,
                                  size,
                                  matched: matchedSet,
                                  dimUnmatched: _cubeHasActiveFilter,
                                  onExternalChange: resync,
                                  onRequestDismiss: () =>
                                      Navigator.of(dialogCtx).pop(),
                                ),
                                // 单个小缩放按钮 — 循环 1x → 1.5x → 2.25x → 1x
                                Positioned(
                                  right: 14,
                                  bottom: 14,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      final next = _cubeScale >= 2.0
                                          ? 1.0 / _cubeScale
                                          : 1.5;
                                      _zoomCube(next, onExternalChange: resync);
                                    },
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: LhColors.paper,
                                        border: Border.all(
                                          color: LhColors.line,
                                          width: 1,
                                        ),
                                        borderRadius: BorderRadius.circular(18),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x14000000),
                                            blurRadius: 6,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        _cubeScale >= 2.0
                                            ? Icons.zoom_out_rounded
                                            : Icons.zoom_in_rounded,
                                        size: 18,
                                        color: LhColors.ink,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),

                    // ── 选中亮点详情卡（如有） ──
                    if (_cubeSelectedKey != null)
                      Container(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: LhColors.line2.withAlpha(140),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: _buildSelectedCubePointCard(cube),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      // 关闭全屏 → 还原标签开关 + 收起 cube filter chip 下拉
      if (!mounted) return;
      setState(() {
        _cubeShowAxisNames = saved[0];
        _cubeShowProductTicks = saved[1];
        _cubeShowSupplyLabels = saved[2];
        _cubeShowChannelLabels = saved[3];
        _cubeShowOwnerInitials = saved[4];
        _cubeFilterOpen = null;
      });
    });
  }

  /// 选中亮点的详情卡 — 显示该坐标的 (产品, 供给方, 渠道) + 毛利
  Widget _buildSelectedCubePointCard(_CubeData cube) {
    _CubePoint? selected;
    for (final c in cube.lit) {
      if ('${c.xi}-${c.yi}-${c.zi}' == _cubeSelectedKey) {
        selected = c;
        break;
      }
    }
    if (selected == null) return const SizedBox(width: double.infinity);
    final p = selected;

    // ── 取 owner 色作为整张卡的 accent ──
    final ownerColors = _CubePainter.ownerColorMap(cube.lit);
    final accent = ownerColors[p.owner] ??
        (p.owner.isEmpty ? LhColors.mute : LhColors.copper);

    String fmtValue(double v) {
      final abs = v.abs();
      if (abs >= 10000) return (v / 10000).toStringAsFixed(2);
      if (abs >= 100) return v.toStringAsFixed(0);
      return v.toStringAsFixed(1);
    }
    String fmtUnit(double v) => v.abs() >= 10000 ? '万' : '';

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 5, 14, 0),
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: accent.withAlpha(70), width: 1),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: accent.withAlpha(16),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
                    // ── Header：坐标 + 负责人 + 关闭 ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 5, 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: accent.withAlpha(18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '坐标 ${p.xi}·${p.yi}·${p.zi}',
                              style: LhTypography.mono(
                                size: 8.5,
                                color: accent,
                                weight: FontWeight.w600,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          if (p.owner.isNotEmpty) ...[
                            Container(
                              width: 13,
                              height: 13,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                p.owner.substring(0, 1),
                                style: LhTypography.sans(
                                  size: 8,
                                  color: Colors.white,
                                  weight: FontWeight.w600,
                                  height: 1.0,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              p.owner,
                              style: LhTypography.sans(
                                size: 10,
                                color: LhColors.ink2,
                                weight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const Spacer(),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _cubeSelectedKey = null),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 13,
                                color: LhColors.mute2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── 毛利 ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '毛利',
                            style: LhTypography.mono(
                              size: 8.5,
                              color: LhColors.mute2,
                              weight: FontWeight.w500,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(width: 7),
                          RichText(
                            text: TextSpan(children: [
                              TextSpan(
                                text: '¥',
                                style: LhTypography.mono(
                                  size: 11,
                                  color: LhColors.mute,
                                  weight: FontWeight.w500,
                                ),
                              ),
                              const WidgetSpan(child: SizedBox(width: 2)),
                              TextSpan(
                                text: fmtValue(p.value),
                                style: LhTypography.number(
                                  size: 16,
                                  color: LhColors.ink,
                                ),
                              ),
                              if (fmtUnit(p.value).isNotEmpty)
                                TextSpan(
                                  text: ' ${fmtUnit(p.value)}',
                                  style: LhTypography.mono(
                                    size: 9,
                                    color: LhColors.mute,
                                    weight: FontWeight.w500,
                                  ),
                                ),
                            ]),
                          ),
                        ],
                      ),
                    ),

                    // ── 分隔线 ──
                    Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      color: LhColors.line2.withAlpha(160),
                    ),

                    // ── 三维度信息 ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _cubeDetailRow('产品', p.x, p.productGroup, null),
                          const SizedBox(height: 6),
                          _cubeDetailRow('供给', p.y, p.supplyGroup, p.supplyHun),
                          const SizedBox(height: 6),
                          _cubeDetailRow('渠道', p.z, p.channelGroup, p.channelHun),
                        ],
                      ),
                    ),
                  ],
                ),
      ),
    );
  }

  Widget _cubeDetailRow(String dim, String name, String group, String? hun) {
    final groupColor = group.isEmpty ? LhColors.mute2 : lhGroupColor(group);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(width: 2, height: 12, color: groupColor.withAlpha(120)),
        const SizedBox(width: 6),
        SizedBox(
          width: 24,
          child: Text(
            dim,
            style: LhTypography.mono(
              size: 9,
              color: LhColors.mute2,
              weight: FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name,
            style: LhTypography.sans(
              size: 11.5,
              color: LhColors.ink,
              weight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (group.isNotEmpty) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: groupColor.withAlpha(20),
              border: Border.all(color: groupColor.withAlpha(80), width: 0.8),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              group,
              style: LhTypography.mono(
                size: 9,
                color: groupColor,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
        // HUN chip
        if (hun != null && hun.isNotEmpty && hun != 'none') ...[
          const SizedBox(width: 4),
          Builder(builder: (_) {
            final hunColor = _hunColorFor(hun);
            final hunLabel = _hunBadgeFor(hun);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: hunColor,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                hunLabel,
                style: LhTypography.mono(
                  size: hunLabel.length > 2 ? 8.5 : 10,
                  color: Colors.white,
                  weight: FontWeight.w600,
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  /// 底部图例 — 极简版：左侧点状图例 + 中间迷你覆盖率 bar + 右侧 P·S·C 维度统计
  Widget _buildCubeLegend(_CubeData cube, {required int matchedShown}) {
    final litTotal = cube.litCount ?? cube.lit.length;
    final possible = cube.totalPossible ??
        (cube.products.length * cube.supplies.length * cube.channels.length);
    final unlit = possible - litTotal;
    final coverage = possible == 0 ? 0.0 : litTotal / possible;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 左：状态文案
        if (_cubeHasActiveFilter || _cubeHasOwnerFilter) ...[
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: LhColors.copper, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$matchedShown 匹配 · 其余淡化',
            style: LhTypography.mono(
              size: 9.5,
              color: LhColors.mute,
              weight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ] else ...[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: LhColors.copper,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: LhColors.copper.withAlpha(80), blurRadius: 5),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '正毛利',
            style: LhTypography.mono(
              size: 9.5,
              color: LhColors.ink2,
              weight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$litTotal',
            style: LhTypography.mono(
              size: 11,
              color: LhColors.copper,
              weight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 10, color: LhColors.line2),
          const SizedBox(width: 10),
          Text(
            '未点亮',
            style: LhTypography.mono(
              size: 9.5,
              color: LhColors.mute,
              weight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$unlit',
            style: LhTypography.mono(
              size: 11,
              color: LhColors.mute,
              weight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
        const Spacer(),
        // 中：迷你覆盖率 progress
        SizedBox(
          width: 56,
          child: Stack(
            children: [
              Container(
                height: 3,
                decoration: BoxDecoration(
                  color: LhColors.line2,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: coverage.clamp(0.0, 1.0),
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: LhColors.copper,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // 右：维度尺寸
        Text(
          '${cube.products.length}P·${cube.supplies.length}S·${cube.channels.length}C',
          style: LhTypography.mono(
            size: 9,
            color: LhColors.mute2,
            weight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }


  /// Cube filter chip 行 — 5 个维度 (产品 / 供给 / 供HUN / 渠道 / 渠HUN)
  /// 点击 chip → 下方 inline 展开选项 → 选完自动收起
  Widget _buildCubeFilterChips(_CubeData cube) {
    // 派生每维可用选项
    List<String> distinct(List<String> raw) {
      final set = <String>{};
      for (final g in raw) {
        if (g.isNotEmpty) set.add(g);
      }
      return ['全部', ...set.toList()..sort()];
    }
    final productGroups = distinct(cube.products.map((p) => p.group).toList());
    final supplyGroups = distinct(cube.supplies.map((s) => s.group).toList());
    final channelGroups = distinct(cube.channels.map((c) => c.group).toList());
    final hunPairs = _cubeHunOptionPairs();
    final hunValues = hunPairs.map((e) => e['value']!).toList();

    String displayCubeValue(String dim, String current) {
      if (!dim.contains('Hun') || current == '全部') return current;
      return _hunLabelFor(current);
    }

    Widget filterChip({
      required String dim,
      required String current,
      required String label,
    }) {
      final isOpen = _cubeFilterOpen == dim;
      final isActive = current != '全部';
      final accent = isActive ? LhColors.copper : LhColors.ink2;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _cubeFilterOpen = isOpen ? null : dim),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 4, 7, 4),
          decoration: BoxDecoration(
            color: isActive ? LhColors.copper.withAlpha(13) : (isOpen ? const Color(0x08140A00) : Colors.transparent),
            border: Border.all(
              color: isActive || isOpen ? LhColors.copper : LhColors.line,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: LhTypography.sans(size: 9, color: LhColors.mute2, weight: FontWeight.w500, letterSpacing: 0.3),
              ),
              const SizedBox(width: 5),
              Text(
                displayCubeValue(dim, current),
                style: LhTypography.sans(size: 10.5, color: accent, weight: FontWeight.w600, letterSpacing: 0.1),
              ),
              Icon(
                isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 13,
                color: isActive || isOpen ? LhColors.copper : LhColors.mute2,
              ),
            ],
          ),
        ),
      );
    }

    Widget? expandedOpts;
    if (_cubeFilterOpen != null) {
      final List<String> options;
      final String current;
      void Function(String) onPick;
      switch (_cubeFilterOpen!) {
        case 'product':
          options = productGroups;
          current = _cubeProductGroup;
          onPick = (v) => _cubeProductGroup = v;
          break;
        case 'supply':
          options = supplyGroups;
          current = _cubeSupplyGroup;
          onPick = (v) => _cubeSupplyGroup = v;
          break;
        case 'supplyHun':
          options = hunValues;
          current = _cubeSupplyHun;
          onPick = (v) => _cubeSupplyHun = v;
          break;
        case 'channel':
          options = channelGroups;
          current = _cubeChannelGroup;
          onPick = (v) => _cubeChannelGroup = v;
          break;
        case 'channelHun':
          options = hunValues;
          current = _cubeChannelHun;
          onPick = (v) => _cubeChannelHun = v;
          break;
        default:
          options = const [];
          current = '';
          onPick = (_) {};
      }
      expandedOpts = Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 2),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Builder(
                  builder: (ctx) {
                    final opt = options[i];
                    final on = opt == current;
                    return GestureDetector(
                      onTap: () => setState(() {
                        onPick(opt);
                        _cubeFilterOpen = null;
                        _cubeSelectedKey = null;
                        _cubeSelectedOwner = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                        decoration: BoxDecoration(
                          color: on ? LhColors.copper.withAlpha(13) : Colors.transparent,
                          border: Border.all(color: on ? LhColors.copper : LhColors.line, width: 1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          (_cubeFilterOpen?.contains('Hun') ?? false)
                              ? _hunLabelFor(opt)
                              : opt,
                          style: LhTypography.sans(
                            size: 10.5,
                            color: on ? LhColors.copper : LhColors.ink2,
                            weight: on ? FontWeight.w600 : FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              filterChip(dim: 'product', current: _cubeProductGroup, label: _cubeFilterLabel('product')),
              const SizedBox(width: 5),
              filterChip(dim: 'supply', current: _cubeSupplyGroup, label: _cubeFilterLabel('supply')),
              const SizedBox(width: 5),
              filterChip(dim: 'supplyHun', current: _cubeSupplyHun, label: _cubeFilterLabel('supplyHun')),
              const SizedBox(width: 5),
              filterChip(dim: 'channel', current: _cubeChannelGroup, label: _cubeFilterLabel('channel')),
              const SizedBox(width: 5),
              filterChip(dim: 'channelHun', current: _cubeChannelHun, label: _cubeFilterLabel('channelHun')),
              if (_cubeHasActiveFilter || _cubeHasOwnerFilter) ...[
                const SizedBox(width: 5),
                GestureDetector(
                  onTap: _cubeResetFilters,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Text(
                      '重置',
                      style: LhTypography.sans(size: 10.5, color: LhColors.copper, weight: FontWeight.w500, letterSpacing: 0.3),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (expandedOpts != null) expandedOpts,
      ],
    );
  }


  int _totalPages(int itemCount) {
    if (itemCount <= 0) return 1;
    return (itemCount + _pageSize - 1) ~/ _pageSize;
  }

  Widget _buildPageNavButton({
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    bool iconAfter = false,
  }) {
    final color = enabled ? LhColors.ink : LhColors.mute2;
    final iconWidget = Icon(icon, size: 16, color: color);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 72, minHeight: 36),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: enabled ? LhColors.paper : Colors.transparent,
            border: Border.all(color: enabled ? LhColors.line2 : LhColors.line, width: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: iconAfter
                ? [
                    Text(label, style: LhTypography.sans(size: 12, color: color, weight: FontWeight.w600)),
                    const SizedBox(width: 2),
                    iconWidget,
                  ]
                : [
                    iconWidget,
                    const SizedBox(width: 2),
                    Text(label, style: LhTypography.sans(size: 12, color: color, weight: FontWeight.w600)),
                  ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageBar({
    required int currentPage,
    required int totalPages,
    required ValueChanged<int> onPageSelected,
  }) {
    void goPage(int page) {
      if (page < 1 || page > totalPages || page == currentPage) return;
      onPageSelected(page);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: LhColors.line2, width: 0.5)),
      ),
      child: Row(
        children: [
          _buildPageNavButton(
            label: '上一页',
            icon: Icons.chevron_left_rounded,
            enabled: currentPage > 1,
            onTap: () => goPage(currentPage - 1),
          ),
          Expanded(
            child: Text(
              '第 $currentPage / $totalPages 页',
              textAlign: TextAlign.center,
              style: LhTypography.mono(size: 11, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 0.2),
            ),
          ),
          _buildPageNavButton(
            label: '下一页',
            icon: Icons.chevron_right_rounded,
            enabled: currentPage < totalPages,
            onTap: () => goPage(currentPage + 1),
            iconAfter: true,
          ),
        ],
      ),
    );
  }

  Widget _buildListItem(Map<String, dynamic> r, int idx) {
    final name = r['name']?.toString() ?? '';
    final group = r['group']?.toString() ?? '';
    final profit = (r['profit'] as num?)?.toDouble() ?? 0;
    final groupColor = lhGroupColor(group);
    final rank = (idx + 1).toString().padLeft(2, '0');
    final isTop3 = idx < 3;
    final isNeg = profit < 0;
    final trendKey = '$_tab::$name::$group';
    final isExpanded = _expanded.contains(trendKey);
    final vsLabel = _kPeriodVs[_period] ?? 'vs 上月';

    // 毛利率 = profit / sales × 100% (mult-invariant — mult on top & bottom cancels)
    final salesRaw = (r['sales'] as num?)?.toDouble() ?? 0;
    final hasRate = salesRaw != 0;
    final rateValue = hasRate ? ((r['profit'] as num?)?.toDouble() ?? 0) / salesRaw * 100 : 0.0;

    // 环比：跟随当前排序列读 r['deltas'][sortField]，否则回退 deltaPct（毛利环比）
    final deltas = (r['deltas'] as Map?)?.cast<String, dynamic>();
    final deltaRaw = (deltas?[_sortField] as num?)?.toDouble() ??
        (r['deltaPct'] as num?)?.toDouble();
    final showDelta = deltaRaw != null;
    final delta = deltaRaw ?? 0;
    final dArrow = delta >= 0 ? '↑' : '↓';
    final dColor = delta >= 0 ? LhColors.pos : LhColors.neg;
    final hasTrend = r['trend'] is Map;
    final canExpand = hasTrend;

    // Tag color (centralised helper)
    final tagColors = _groupTagColors(group);
    final tagBg = tagColors.bg;
    final tagFg = tagColors.fg;

    // Can navigate to detail?
    bool canDetail = false;
    if (_bundle != null) {
      if (_tab == 'product') {
        canDetail = _bundle!.productDetail.containsKey(name);
      } else if (_tab == 'supply') {
        canDetail = _bundle!.supplyDetail.containsKey(name);
      } else if (_tab == 'channel') {
        canDetail = _bundle!.channelDetail.containsKey('$name::$group');
      }
    }

    // Meta row — driven by per-tab selected metrics (excluding 'discount' and 'profit')
    final selectedMetricKeys = (_metrics[_tab] ?? []).where((k) => k != 'discount' && k != 'profit');
    final metaItems = <_MetaItem>[];
    for (final k in selectedMetricKeys) {
      final v = (r[k] as num?)?.toDouble() ?? 0;
      final label = _metricShort(k);
      metaItems.add(_MetaItem(label, '${_fmt(v.abs())}${_unit(v.abs())}'));
    }

    void openDetail() {
      final detKey = _tab == 'channel' ? '$name::$group' : name;
      setState(() {
        _detailKey = detKey;
        _detailType = _tab;
        _detailPage = 1;
        _resetDetailSkuSearch();
      });
    }

    return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: LhColors.paper,
          border: Border.all(
            color: isExpanded ? LhColors.ink2.withAlpha(40) : LhColors.line2,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rank — top3 use a chip badge, others use plain number with consistent footprint
                SizedBox(
                  width: 22,
                  height: 22,
                  child: isTop3
                      ? Container(
                          decoration: BoxDecoration(
                            color: LhColors.copperSoft,
                            border: Border.all(color: LhColors.copper.withAlpha(140), width: 1),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            rank,
                            style: LhTypography.mono(
                              size: 9.5,
                              color: LhColors.copper,
                              weight: FontWeight.w700,
                              letterSpacing: 0,
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            rank,
                            style: LhTypography.mono(
                              size: 10.5,
                              color: groupColor,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                // Main content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name row
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: LhTypography.sans(size: 12.5, weight: FontWeight.w600, color: LhColors.ink),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // HUN tag（仅 supply / channel）
                          if ((_tab == 'supply' || _tab == 'channel')) ...[
                            const SizedBox(width: 5),
                            Builder(builder: (_) {
                              final h = _hunOf(r);
                              if (!h.hasAny) return const SizedBox.shrink();
                              final col = _hunColorFor(h.primary);
                              final lbl = _hunBadgeFor(h.primary);
                              return Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: lbl.length > 2 ? 4 : 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: col.withAlpha(20),
                                  border: Border.all(color: col.withAlpha(80), width: 0.8),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  lbl,
                                  style: LhTypography.mono(
                                    size: lbl.length > 2 ? 8 : 9,
                                    color: col,
                                    weight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              );
                            }),
                          ],
                          const SizedBox(width: 6),
                          // Group tag
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: tagBg, borderRadius: BorderRadius.circular(3)),
                            child: Text(group, style: LhTypography.sans(size: 8.5, color: tagFg, weight: FontWeight.w600, letterSpacing: 0.3)),
                          ),
                          if (canDetail) ...[
                            const SizedBox(width: 2),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: openDetail,
                              child: const Padding(
                                padding: EdgeInsets.all(4),
                                child: Icon(Icons.chevron_right, size: 18, color: LhColors.mute2),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // Meta row
                      if (metaItems.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 10,
                          runSpacing: 3,
                          children: metaItems.map((m) => RichText(
                            text: TextSpan(children: [
                              TextSpan(text: '${m.label} ', style: LhTypography.mono(size: 9.5, color: LhColors.mute2)),
                              TextSpan(text: m.value, style: LhTypography.mono(size: 9.5, color: LhColors.mute, weight: FontWeight.w500)),
                            ]),
                          )).toList(),
                        ),
                      ],
                      // Trend row（环比 + 展开趋势；都没有则整行不渲染）
                      if (showDelta || canExpand) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.only(top: 5),
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: LhColors.line2, width: 1, style: BorderStyle.solid)),
                          ),
                          child: Row(
                            children: [
                              if (showDelta) ...[
                                Text(
                                  '$dArrow ${delta.abs().toStringAsFixed(1)}%',
                                  style: LhTypography.mono(size: 10.5, color: dColor, weight: FontWeight.w600, letterSpacing: 0.2),
                                ),
                                const SizedBox(width: 6),
                                Text(vsLabel, style: LhTypography.mono(size: 9.5, color: LhColors.mute2, letterSpacing: 0.2)),
                              ],
                              const Spacer(),
                              if (canExpand)
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() {
                                    if (_expanded.contains(trendKey)) {
                                      _expanded.remove(trendKey);
                                    } else {
                                      _expanded.add(trendKey);
                                    }
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: AnimatedRotation(
                                      turns: isExpanded ? 0.5 : 0,
                                      duration: const Duration(milliseconds: 250),
                                      child: const Icon(Icons.keyboard_arrow_down_rounded, size: 15, color: LhColors.mute),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      // Expanded body (trend / discount) — 嵌在 main column 内，
                      // 宽度自动 = name/meta 行宽度（不再越过 rank/right column 边界）
                      if (isExpanded)
                        GestureDetector(
                          onTap: () {}, // absorb taps so chart area doesn't trigger row navigation
                          child: _buildInlineExpanded(trendKey, name, r, groupColor),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Value (right column)
                SizedBox(
                  width: 72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      RichText(
                        text: TextSpan(children: [
                          if (isNeg) TextSpan(text: '-', style: LhTypography.sans(size: 13, weight: FontWeight.w600, color: LhColors.neg, letterSpacing: -0.2)),
                          TextSpan(text: _fmt(profit.abs()), style: LhTypography.sans(size: 13, weight: FontWeight.w600, color: isNeg ? LhColors.neg : LhColors.ink, letterSpacing: -0.2)),
                          TextSpan(text: _unit(profit.abs()), style: LhTypography.mono(size: 9.5, color: LhColors.mute, weight: FontWeight.w500)),
                        ]),
                      ),
                      const SizedBox(height: 1),
                      Text('毛利', style: LhTypography.mono(size: 9, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 0.8)),
                      const SizedBox(height: 4),
                      hasRate
                          ? RichText(
                              text: TextSpan(children: [
                                TextSpan(
                                  text: rateValue.toStringAsFixed(rateValue.abs() >= 100 ? 1 : 2),
                                  style: LhTypography.mono(size: 10.5, color: rateValue < 0 ? LhColors.neg : LhColors.ink2, weight: FontWeight.w600),
                                ),
                                TextSpan(
                                  text: '%',
                                  style: LhTypography.mono(size: 8, color: LhColors.mute, weight: FontWeight.w500),
                                ),
                              ]),
                            )
                          : Text('—', style: LhTypography.mono(size: 10.5, color: LhColors.mute2, weight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
  }

  // ───── Inline Expanded (Trend / Discount toggle) ──────────────────────────
  /// 从行数据 `r['trend']` 构建真实趋势图；无 trend 返回 null。
  _TrendChart? _trendChartFor(Map<String, dynamic> r, {bool showHeader = true}) {
    final t = (r['trend'] as Map?)?.cast<String, dynamic>();
    if (t == null) return null;
    List<double> nums(dynamic v) => (v is List)
        ? v.map((e) => (e is num) ? e.toDouble() : 0.0).toList()
        : <double>[];
    var profit = nums(t['profit']);
    if (profit.isEmpty) profit = nums(t['points']);
    if (profit.isEmpty) return null;
    final labels = ((t['labels'] ?? t['xLabels']) as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    return _TrendChart(
      labels: labels,
      revenue: nums(t['revenue']),
      cost: nums(t['cost']),
      profit: profit,
      rangeLabel: t['rangeLabel']?.toString() ?? '',
      title: _kPeriodTitle[_period] ?? '趋势',
      showHeader: showHeader,
    );
  }

  Widget _buildInlineExpanded(String trendKey, String name, Map<String, dynamic> r, Color groupColor) {
    final trendChart = _trendChartFor(r, showHeader: false);
    final headerTitle = _kPeriodTitle[_period] ?? '趋势';
    final headerRange = (r['trend'] as Map?)?['rangeLabel']?.toString() ?? '';

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 2),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: LhColors.line2, width: 1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (title / range)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(headerTitle,
                    style: LhTypography.mono(size: 9.5, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 1.2)),
                Text(headerRange,
                    style: LhTypography.mono(size: 9, color: LhColors.mute2, weight: FontWeight.w500, letterSpacing: 0.3)),
              ],
            ),
            const SizedBox(height: 11),
            // Body
            if (trendChart != null)
              trendChart
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text('暂无趋势数据',
                      style: LhTypography.sans(size: 11, color: LhColors.mute)),
                ),
              ),
          ],
        ),
      ),
    );
  }


  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 22),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(width: 28, height: 0.5, color: LhColors.copper.withAlpha(140)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('· FIN ·', style: LhTypography.mono(size: 9, color: LhColors.mute2, weight: FontWeight.w500, letterSpacing: 2)),
          ),
          Container(width: 28, height: 0.5, color: LhColors.copper.withAlpha(140)),
        ],
      ),
    );
  }

  // ───── Detail View ────────────────────────────────────────────────────────

  // Sub-tab config per detail type (mirrors DETAIL_CONFIG in HTML)
  static const _kDetailSubTabs = {
    'product': [
      _SubTabInfo(key: 'supply',      label: '供给', color: LhColors.sinopec),
      _SubTabInfo(key: 'channel',     label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'project',     label: '项目', color: LhColors.copper),
      _SubTabInfo(key: 'productName', label: 'SKU',  color: LhColors.product),
    ],
    'supply': [
      _SubTabInfo(key: 'product',     label: '产品', color: LhColors.product),
      _SubTabInfo(key: 'channel',     label: '渠道', color: LhColors.carrier),
      _SubTabInfo(key: 'project',     label: '项目', color: LhColors.copper),
      _SubTabInfo(key: 'productName', label: 'SKU',  color: LhColors.product),
    ],
    'channel': [
      _SubTabInfo(key: 'product',     label: '产品', color: LhColors.product),
      _SubTabInfo(key: 'supply',      label: '供给', color: LhColors.sinopec),
      _SubTabInfo(key: 'project',     label: '项目', color: LhColors.copper),
      _SubTabInfo(key: 'productName', label: 'SKU',  color: LhColors.product),
    ],
  };

  Widget _buildDetailView() {
    final key = _detailKey ?? '';
    final type = _detailType ?? 'product';

    // Retrieve the detail dict for this entity
    Map<String, dynamic>? detailDict;
    if (_bundle != null) {
      if (type == 'product') {
        detailDict = _bundle!.productDetail[key] as Map<String, dynamic>?;
      } else if (type == 'supply') {
        detailDict = _bundle!.supplyDetail[key] as Map<String, dynamic>?;
      } else if (type == 'channel') {
        detailDict = _bundle!.channelDetail[key] as Map<String, dynamic>?;
      }
    }
    if (detailDict == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() { _detailKey = null; _detailType = null; _resetDetailSkuSearch(); });
      });
      return const SizedBox();
    }

    // Find entity row in main DATA
    Map<String, dynamic> entity = {};
    if (_bundle != null) {
      final rows = _bundle!.rowsOf(type);
      if (type == 'channel') {
        final parts = key.split('::');
        final n = parts.isNotEmpty ? parts[0] : '';
        final g = parts.length > 1 ? parts[1] : '';
        entity = rows.firstWhere((r) => r['name'] == n && r['group'] == g, orElse: () => {});
      } else {
        entity = rows.firstWhere((r) => r['name'] == key, orElse: () => {});
      }
    }

    final displayName = type == 'channel' ? key.split('::').first : key;
    final groupLabel = type == 'channel' && key.contains('::') ? key.split('::').last : '';

    final subTabList = _kDetailSubTabs[type] ?? _kDetailSubTabs['product']!;
    // Ensure _detailSubTab is valid for this type
    if (!subTabList.any((t) => t.key == _detailSubTab)) {
      _detailSubTab = subTabList.first.key;
    }

    // Same metrics source as main list (HTML: state.metrics[type])

    // Sub-tab rows (aggregated by name+group, sorted by profit desc)
    final rawSubRows = detailDict[_detailSubTab];
    final subRows = <Map<String, dynamic>>[];
    if (rawSubRows is List) {
      // Aggregate by name::group
      final agg = <String, Map<String, dynamic>>{};
      for (final r in rawSubRows.cast<Map<String, dynamic>>()) {
        final k = '${r['name']}::${r['group']}';
        if (!agg.containsKey(k)) {
          agg[k] = {'name': r['name'], 'group': r['group']};
        }
        final a = agg[k]!;
        for (final field in r.keys) {
          if (field == 'name' || field == 'group') continue;
          final v = (r[field] as num?)?.toDouble();
          if (v != null) {
            a[field] = ((a[field] as num?)?.toDouble() ?? 0) + v;
          } else if (!a.containsKey(field)) {
            a[field] = r[field];
          }
        }
      }
      subRows.addAll(agg.values);
      subRows.sort((a, b) {
        final pa = (a['profit'] as num?)?.toDouble() ?? 0;
        final pb = (b['profit'] as num?)?.toDouble() ?? 0;
        return pb.compareTo(pa);
      });
    }

    final isSkuTab = _detailSubTab == 'productName';
    final filteredSubRows = isSkuTab && _detailSkuQuery.trim().isNotEmpty
        ? subRows.where((r) => _skuRowMatchesQuery(r, _detailSkuQuery)).toList()
        : subRows;

    // Totals for sub rows
    double sumSales = 0, sumGmv = 0, sumCost = 0;
    for (final r in filteredSubRows) {
      sumSales += (r['sales'] as num?)?.toDouble() ?? 0;
      sumGmv += (r['gmv'] as num?)?.toDouble() ?? 0;
      sumCost += (r['cost'] as num?)?.toDouble() ?? 0;
    }

    // Entity profit
    final entityProfit = (entity['profit'] as num?)?.toDouble() ?? 0;
    final entityProfitIsNeg = entityProfit < 0;
    final entitySales = (entity['sales'] as num?)?.toDouble() ?? 0;
    final entityRate = entitySales > 0 ? entityProfit / entitySales * 100 : 0.0;

    // Mini metrics
    final miniMetrics = _heroMetricsFor(type).where((m) => m.key != 'profit').toList();
    final miniTotals = <String, double>{};
    for (final m in miniMetrics) {
      if (m.isRate) {
        miniTotals['rate'] = entityRate;
      } else {
        miniTotals[m.key] = (entity[m.key] == null
            ? (m.key == 'revenue' ? entitySales : 0.0)
            : (entity[m.key] as num).toDouble());
      }
    }

    // Eyebrow text
    final eyebrow = type == 'product' ? '产品详情 · PRODUCT'
        : type == 'supply' ? '供给方详情 · SUPPLY'
        : '渠道详情 · CHANNEL';

    return Column(
      children: [
        // ── Sticky header ──────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            color: LhColors.cream,
            border: Border(bottom: BorderSide(color: LhColors.line2, width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 22, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _closeDropdown();
                  setState(() { _detailKey = null; _detailType = null; _resetDetailSkuSearch(); });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.chevron_left_rounded, size: 18, color: LhColors.mute),
                      const SizedBox(width: 2),
                      Text('返回', style: LhTypography.sans(size: 12.5, color: LhColors.mute, weight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
              Text(eyebrow, style: LhTypography.mono(size: 9, color: LhColors.mute2, weight: FontWeight.w600, letterSpacing: 1.5)),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              const SizedBox(height: 14),
              // ── dt-summary card ─────────────────────────────────────────
              Container(
                margin: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(2.97),
                    colors: [Colors.white, Color(0xFFFCFAF5), Color(0xFFF7F4EC), Color(0xFFF2EEE3)],
                    stops: [0, 0.35, 0.75, 1],
                  ),
                  border: Border.all(color: LhColors.line2, width: 1),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: const Color(0x07140A00), blurRadius: 2, offset: const Offset(0, 1)),
                    BoxShadow(color: const Color(0x10140A00), blurRadius: 20, spreadRadius: -10, offset: const Offset(0, 6)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + group tag (colored)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(displayName, style: LhTypography.sans(size: 22, weight: FontWeight.w700, color: LhColors.ink, letterSpacing: -0.2)),
                        if (groupLabel.isNotEmpty)
                          Builder(builder: (_) {
                            final tc = _groupTagColors(groupLabel);
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: tc.bg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(groupLabel.toUpperCase(), style: LhTypography.mono(size: 9, color: tc.fg, weight: FontWeight.w700, letterSpacing: 0.5)),
                            );
                          }),
                      ],
                    ),
                    // Profit number (LhTypography.number → consistent with hero)
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          RichText(
                            text: TextSpan(children: [
                              if (entityProfitIsNeg) TextSpan(text: '-', style: LhTypography.number(size: 26, color: LhColors.neg)),
                              TextSpan(
                                text: _fmt(entityProfit.abs()),
                                style: LhTypography.number(size: 26, color: entityProfitIsNeg ? LhColors.neg : LhColors.ink),
                              ),
                              TextSpan(text: _unit(entityProfit.abs()), style: LhTypography.sans(size: 13, color: LhColors.mute, weight: FontWeight.w500)),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          Text('本月毛利润', style: LhTypography.mono(size: 9, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 0.8)),
                        ],
                      ),
                    ),
                    // Divider
                    Container(height: 1, color: LhColors.line2, margin: const EdgeInsets.only(bottom: 12)),
                    // Mini metric grid
                    _buildDetailMiniGrid(miniMetrics, miniTotals),
                  ],
                ),
              ),

              // ── 趋势卡：3 lines (收入/成本/毛利)，读后端真实 trend，无数据则隐藏 ──
              if (_trendChartFor(entity) case final chart?) ...[
                const SizedBox(height: 10),
                Container(
                  margin: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  decoration: BoxDecoration(
                    color: LhColors.paper,
                    border: Border.all(color: LhColors.line2, width: 1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: chart,
                ),
              ],

              const SizedBox(height: 10),

              // ── Sub-tab segment (matches main TabSegment visual language) ──
              Container(
                decoration: const BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: LhColors.line2, width: 1),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: subTabList.map((t) {
                      final isOn = t.key == _detailSubTab;
                      final count = (detailDict![t.key] is List) ? (detailDict[t.key] as List).length : 0;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _detailSubTab = t.key;
                            _detailPage = 1;
                            if (t.key != 'productName') _resetDetailSkuSearch();
                          }),
                          behavior: HitTestBehavior.opaque,
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              if (isOn)
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [t.color.withAlpha(20), t.color.withAlpha(0)],
                                      ),
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      t.label,
                                      style: LhTypography.sans(
                                        size: 14,
                                        color: isOn ? t.color : LhColors.mute,
                                        weight: isOn ? FontWeight.w700 : FontWeight.w500,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$count',
                                      style: LhTypography.mono(
                                        size: 10,
                                        color: isOn ? t.color.withAlpha(191) : LhColors.mute2,
                                        weight: isOn ? FontWeight.w600 : FontWeight.w500,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isOn)
                                Positioned(
                                  bottom: -1,
                                  left: 0,
                                  right: 0,
                                  child: Container(height: 3, color: t.color),
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 0),

              if (isSkuTab) _buildDetailSkuSearchBar(),

              // ── dt-totals row ─────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(22, isSkuTab ? 8 : 8, 22, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isSkuTab && _detailSkuQuery.trim().isNotEmpty
                            ? '${filteredSubRows.length}/${subRows.length} 项 · 销售 ¥${_fmt(sumSales)}${_unit(sumSales)} · 引流 ¥${_fmt(sumGmv)}${_unit(sumGmv)} · 业务 ¥${_fmt(sumCost)}${_unit(sumCost)}'
                            : '${filteredSubRows.length} 项 · 销售 ¥${_fmt(sumSales)}${_unit(sumSales)} · 引流 ¥${_fmt(sumGmv)}${_unit(sumGmv)} · 业务 ¥${_fmt(sumCost)}${_unit(sumCost)}',
                        style: LhTypography.mono(size: 9, color: LhColors.mute, letterSpacing: 0.2),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildDropdownActions(showCategory: false, showMetric: true),
                  ],
                ),
              ),

              // ── Sub list ───────────────────────────────────────────────
              if (filteredSubRows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      isSkuTab && _detailSkuQuery.trim().isNotEmpty ? '无匹配 SKU' : '暂无数据',
                      style: LhTypography.sans(size: 12, color: LhColors.mute),
                    ),
                  ),
                )
              else
                Builder(
                  builder: (context) {
                    final totalPages = _totalPages(filteredSubRows.length);
                    final page = _detailPage.clamp(1, totalPages);
                    final start = (page - 1) * _pageSize;
                    final end = (start + _pageSize).clamp(0, filteredSubRows.length);
                    final visible = filteredSubRows.sublist(start, end);
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                      child: Column(
                        children: [
                          for (int i = 0; i < visible.length; i++)
                            _buildDetailListItem(visible[i], start + i, type),
                          if (totalPages > 1) ...[
                            const SizedBox(height: 8),
                            _buildPageBar(
                              currentPage: page,
                              totalPages: totalPages,
                              onPageSelected: (p) => setState(() => _detailPage = p),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),

              // ── § 经营分析 ──────────────────────────────────────────────
              if (entity.isNotEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      transform: GradientRotation(2.97),
                      colors: [Colors.white, Color(0xFFFCFAF5), Color(0xFFF7F4EC), Color(0xFFF2EEE3)],
                      stops: [0, 0.35, 0.75, 1],
                    ),
                    border: Border.all(color: LhColors.line2, width: 1),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: const Color(0x07140A00), blurRadius: 2, offset: const Offset(0, 1)),
                      BoxShadow(color: const Color(0x10140A00), blurRadius: 20, spreadRadius: -10, offset: const Offset(0, 6)),
                    ],
                  ),
                  child: _buildBusinessAnalysis(entity, type),
                ),

              _buildFooter(),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // § 经营分析 (Business Analysis)
  // ═══════════════════════════════════════════════════════════════════════
  //
  // 在每个产品 / 供给 / 渠道详情底部展示 4 个子模块，全部基于现有 row 字段
  // 计算，无 mock 数据：
  //
  //   A. ROI 仪表       — 投资回报率 + 毛利率 + 同组对比 + 行业基准
  //   B. 成本结构条      — 销售额拆 5 段 (业务/税/SaaS/项目/毛利)
  //   C. 健康度评分      — 5 维 bars (盈利/增长/成本/效率/规模) + 综合 0-100
  //   D. 同组排名直方图  — 在同 group peers 中的 ROI 排序位置
  //
  // 行业基准 (ROI 8%) 暂定，业务确认后改成从 _bundle.metrics['benchmark'] 读取。

  // ── A. ROI 算法 ────────────────────────────────────────────────────────
  /// 总投入：优先 totalCost；否则各成本项绝对值之和；仍无则回退销售额。
  double _calcInvestBase(Map<String, dynamic> r) {
    final sales = (r['sales'] as num?)?.toDouble() ?? 0;
    final totalCost = (r['totalCost'] as num?)?.toDouble() ?? 0;
    if (totalCost > 0 && (sales <= 0 || totalCost >= sales * 0.01)) {
      return totalCost;
    }
    final cost = (r['cost'] as num?)?.toDouble() ?? 0;
    final tax = (r['tax'] as num?)?.toDouble() ?? 0;
    final saas = (r['saasFee'] as num?)?.toDouble() ?? 0;
    final proj = (r['projectCost'] as num?)?.toDouble() ?? 0;
    final sum = cost.abs() + tax.abs() + saas.abs() + proj.abs();
    if (sum > 0) return sum;
    return sales > 0 ? sales : 0;
  }

  /// ROI = 毛利 / 总投入 × 100%
  double _calcROI(Map<String, dynamic> r) {
    final profit = (r['profit'] as num?)?.toDouble() ?? 0;
    final base = _calcInvestBase(r);
    if (base <= 0) return 0;
    return profit / base * 100;
  }

  double _calcMarginRate(Map<String, dynamic> r) {
    final profit = (r['profit'] as num?)?.toDouble() ?? 0;
    final sales = (r['sales'] as num?)?.toDouble() ?? 0;
    if (sales <= 0) return 0;
    return profit / sales * 100;
  }

  double _calcGroupAvgROI(String type, String group) {
    final rows = _bundle?.rowsOf(type) ?? const <Map<String, dynamic>>[];
    final peers = rows.where((r) => r['group']?.toString() == group).toList();
    if (peers.isEmpty) return 0;
    double sum = 0;
    for (final p in peers) {
      sum += _calcROI(p);
    }
    return sum / peers.length;
  }

  // ── B. 健康度评分 ──────────────────────────────────────────────────────
  ({int score, int profit, int growth, int cost, int efficiency, int scale})
      _calcHealthScores(Map<String, dynamic> r, String type) {
    final sales = (r['sales'] as num?)?.toDouble() ?? 0;
    final profit = (r['profit'] as num?)?.toDouble() ?? 0;
    final cost = (r['cost'] as num?)?.toDouble() ?? 0;
    final gmv = (r['gmv'] as num?)?.toDouble() ?? 0;
    final deltaPct = (r['deltaPct'] as num?)?.toDouble() ?? 0;

    int scale01(double v, double lo, double hi) {
      if (hi == lo) return 0;
      final t = ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
      return (t * 100).round();
    }

    final marginRate = sales > 0 ? (profit / sales * 100) : 0.0;
    final costRatio = sales > 0 ? (1 - cost / sales) : 0.0;
    final gmvConv = gmv > 0 ? (sales / gmv) : 0.0;

    final pScore = scale01(marginRate, 0, 30);
    final gScore = scale01(deltaPct, -20, 50);
    final cScore = scale01(costRatio, 0.5, 0.95);
    final eScore = scale01(gmvConv, 0.5, 1.0);

    // 规模实力 — 在同 tab 内按 sales 取百分位
    final rows = _bundle?.rowsOf(type) ?? const <Map<String, dynamic>>[];
    int sScore = 0;
    if (rows.isNotEmpty) {
      int below = 0;
      for (final x in rows) {
        final xs = (x['sales'] as num?)?.toDouble() ?? 0;
        if (xs < sales) below++;
      }
      sScore = (below / rows.length * 100).round();
    }

    // 加权综合 — 25/15/20/20/20
    final composite = (pScore * 25 + gScore * 15 + cScore * 20 + eScore * 20 + sScore * 20) ~/ 100;

    return (
      score: composite,
      profit: pScore,
      growth: gScore,
      cost: cScore,
      efficiency: eScore,
      scale: sScore,
    );
  }

  // ── C. 同组排名 ────────────────────────────────────────────────────────
  ({int rank, int total, double percentile, List<({String name, double roi, bool isMe})> peers})
      _calcGroupRanking(Map<String, dynamic> r, String type) {
    final myName = r['name']?.toString() ?? '';
    final myGroup = r['group']?.toString() ?? '';
    final rows = _bundle?.rowsOf(type) ?? const <Map<String, dynamic>>[];
    final peers = rows.where((x) => x['group']?.toString() == myGroup).toList();
    if (peers.isEmpty) {
      return (rank: 0, total: 0, percentile: 0.0, peers: const []);
    }
    peers.sort((a, b) => _calcROI(b).compareTo(_calcROI(a)));
    final myIdx = peers.indexWhere((x) => x['name']?.toString() == myName);
    final rank = myIdx < 0 ? peers.length : myIdx + 1;
    final total = peers.length;
    final pct = total <= 1 ? 100.0 : ((1 - myIdx / (total - 1)) * 100).clamp(0.0, 100.0).toDouble();
    final list = peers.take(12).map((p) {
      return (
        name: p['name']?.toString() ?? '',
        roi: _calcROI(p),
        isMe: p['name']?.toString() == myName,
      );
    }).toList();
    return (rank: rank, total: total, percentile: pct, peers: list);
  }

  // ── 主入口 ────────────────────────────────────────────────────────────
  Widget _buildBusinessAnalysis(Map<String, dynamic> r, String type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          // section header
          Row(
            children: [
              Text('§', style: LhTypography.mono(size: 12, color: LhColors.copper, weight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('经营分析', style: LhTypography.sans(size: 13, color: LhColors.ink, weight: FontWeight.w700, letterSpacing: 0.2)),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 1, color: LhColors.line2)),
              const SizedBox(width: 8),
              Text(
                'BUSINESS',
                style: LhTypography.mono(size: 8, color: LhColors.mute2, weight: FontWeight.w700, letterSpacing: 1.8),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildAnalysisROI(r, type),
          _analysisDivider(),
          _buildAnalysisCostStack(r, type),
          _analysisDivider(),
          _buildAnalysisHealthBars(r, type),
          _analysisDivider(),
          _buildAnalysisRanking(r, type),
      ],
    );
  }

  Widget _analysisDivider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Container(height: 1, color: LhColors.line2),
      );

  // ── A. ROI 仪表 ────────────────────────────────────────────────────────
  Widget _buildAnalysisROI(Map<String, dynamic> r, String type) {
    final roi = _calcROI(r);
    final margin = _calcMarginRate(r);
    final groupName = r['group']?.toString() ?? '';
    final groupAvg = _calcGroupAvgROI(type, groupName);
    final diff = roi - groupAvg;
    const benchmark = 8.0; // TODO: 改 _bundle.metrics['benchmark']

    Color verdictColor;
    String verdictText;
    if (roi >= benchmark * 1.3) {
      verdictColor = LhColors.pos;
      verdictText = '优秀';
    } else if (roi >= benchmark * 0.7) {
      verdictColor = LhColors.copper;
      verdictText = '良好';
    } else {
      verdictColor = LhColors.neg;
      verdictText = '待提升';
    }

    Widget bigNum(String label, double val, Color color) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: LhTypography.sans(
              size: 9,
              color: LhColors.mute2,
              weight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                val.toStringAsFixed(1),
                style: LhTypography.sans(
                  size: 26,
                  color: color,
                  weight: FontWeight.w700,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '%',
                  style: LhTypography.mono(
                    size: 11,
                    color: color.withAlpha(180),
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: bigNum('ROI 投资回报', roi, verdictColor)),
            Container(
              width: 1,
              height: 36,
              color: LhColors.line2,
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),
            Expanded(child: bigNum('毛利率', margin, LhColors.ink)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
              decoration: BoxDecoration(
                color: verdictColor.withAlpha(33),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                verdictText,
                style: LhTypography.sans(
                  size: 10,
                  color: verdictColor,
                  weight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: diff >= 0 ? LhColors.pos : LhColors.neg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '同组均值 ${groupAvg.toStringAsFixed(1)}%',
              style: LhTypography.sans(
                size: 10,
                color: LhColors.mute,
                weight: FontWeight.w500,
              ),
            ),
            Text(
              ' · ${diff >= 0 ? "+" : ""}${diff.toStringAsFixed(1)}pp',
              style: LhTypography.mono(
                size: 10,
                color: diff >= 0 ? LhColors.pos : LhColors.neg,
                weight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            Text(
              '基准 ${benchmark.toStringAsFixed(0)}%',
              style: LhTypography.mono(
                size: 9,
                color: LhColors.mute2,
                weight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── B. 成本结构条 ──────────────────────────────────────────────────────
  Widget _buildAnalysisCostStack(Map<String, dynamic> r, String type) {
    final sales = (r['sales'] as num?)?.toDouble() ?? 0;
    if (sales <= 0) return const SizedBox.shrink();

    final cost = ((r['cost'] as num?)?.toDouble() ?? 0).clamp(0.0, double.infinity);
    final tax = ((r['tax'] as num?)?.toDouble() ?? 0).clamp(0.0, double.infinity);
    final saas = ((r['saasFee'] as num?)?.toDouble() ?? 0).clamp(0.0, double.infinity);
    final proj = ((r['projectCost'] as num?)?.toDouble() ?? 0).clamp(0.0, double.infinity);
    final profit = ((r['profit'] as num?)?.toDouble() ?? 0).clamp(0.0, double.infinity);

    // 5 段：业务 / 税 / SaaS / 项目 / 毛利；占比统一以销售额为分母
    final segments = <({String label, double value, Color color})>[
      (label: '业务', value: cost, color: const Color(0xFFD05568)),
      (label: '税务', value: tax, color: const Color(0xFF8A6FE0)),
      if (saas > 0) (label: 'SaaS', value: saas, color: const Color(0xFFC9842A)),
      if (proj > 0) (label: '项目', value: proj, color: const Color(0xFF7C5CD6)),
      (label: '毛利', value: profit, color: LhColors.pos),
    ];
    final barTotal = segments.fold<double>(0, (s, x) => s + x.value);
    if (barTotal <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '成本结构',
              style: LhTypography.sans(
                size: 11,
                color: LhColors.ink2,
                weight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            Text(
              '销售 ¥${_fmt(sales)}${_unit(sales)}',
              style: LhTypography.mono(
                size: 9.5,
                color: LhColors.mute,
                weight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (final s in segments)
                  Expanded(
                    flex: ((s.value / barTotal) * 10000).round().clamp(1, 10000),
                    child: Container(color: s.color),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 11,
          runSpacing: 5,
          children: [
            for (final s in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: s.color,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    s.label,
                    style: LhTypography.sans(
                      size: 9.5,
                      color: LhColors.ink2,
                      weight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${(s.value / sales * 100).toStringAsFixed(0)}%',
                    style: LhTypography.mono(
                      size: 9,
                      color: s.label == '毛利' ? LhColors.pos : LhColors.mute,
                      weight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  // ── C. 健康度 5 维 bars ────────────────────────────────────────────────
  Widget _buildAnalysisHealthBars(Map<String, dynamic> r, String type) {
    final h = _calcHealthScores(r, type);

    Color scoreColor(int s) {
      if (s >= 70) return LhColors.pos;
      if (s >= 40) return LhColors.copper;
      return LhColors.neg;
    }

    Widget bar(String label, int score) {
      final c = scoreColor(score);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Text(
                label,
                style: LhTypography.sans(
                  size: 10,
                  color: LhColors.ink2,
                  weight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: LhColors.line2,
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: (score / 100).clamp(0.0, 1.0),
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 22,
              child: Text(
                '$score',
                textAlign: TextAlign.right,
                style: LhTypography.mono(
                  size: 10,
                  color: c,
                  weight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '健康度',
              style: LhTypography.sans(
                size: 11,
                color: LhColors.ink2,
                weight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            Text(
              '${h.score}',
              style: LhTypography.sans(
                size: 14,
                color: scoreColor(h.score),
                weight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 1),
            Text(
              '/100',
              style: LhTypography.mono(
                size: 9,
                color: LhColors.mute,
                weight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        bar('盈利能力', h.profit),
        bar('增长性', h.growth),
        bar('成本控制', h.cost),
        bar('运营效率', h.efficiency),
        bar('规模实力', h.scale),
      ],
    );
  }

  // ── D. 同组排名直方图 ──────────────────────────────────────────────────
  Widget _buildAnalysisRanking(Map<String, dynamic> r, String type) {
    final ranking = _calcGroupRanking(r, type);
    if (ranking.total == 0) return const SizedBox.shrink();

    final groupName = r['group']?.toString() ?? '';
    final rois = ranking.peers.map((p) => p.roi).toList();
    final maxRoi = rois.fold<double>(0, (m, v) => v > m ? v : m);
    final minRoi = rois.fold<double>(double.infinity, (m, v) => v < m ? v : m);
    final span = (maxRoi - minRoi).abs() < 0.001 ? 1.0 : (maxRoi - minRoi);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '同组对比',
              style: LhTypography.sans(
                size: 11,
                color: LhColors.ink2,
                weight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '· $groupName ${ranking.total} 家',
              style: LhTypography.mono(
                size: 9,
                color: LhColors.mute,
                weight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            Text(
              '第 ${ranking.rank}/${ranking.total} · 前 ${ranking.percentile.toStringAsFixed(0)}%',
              style: LhTypography.mono(
                size: 10,
                color: LhColors.copper,
                weight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final p in ranking.peers)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          height: ((p.roi - minRoi) / span * 32 + 4).clamp(4.0, 36.0),
                          decoration: BoxDecoration(
                            color: p.isMe ? LhColors.copper : LhColors.mute2.withAlpha(70),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(1.5)),
                          ),
                        ),
                        const SizedBox(height: 3),
                        if (p.isMe)
                          Container(
                            width: 7,
                            height: 2,
                            decoration: BoxDecoration(
                              color: LhColors.copper,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          )
                        else
                          const SizedBox(height: 2),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailMiniGrid(List<_HeroMetric> metrics, Map<String, double> totals) {
    final n = metrics.length;
    // n=4 用 2 列 (2x2 更对称); n=3/6/其他 用 3 列
    final cols = (n == 4) ? 2 : 3;
    return LayoutBuilder(builder: (context, constraints) {
      final availW = constraints.maxWidth;
      const colGap = 12.0;
      final cw = (availW - colGap * (cols - 1)) / cols;

      final rows = <List<_HeroMetric>>[];
      for (int i = 0; i < n; i += cols) {
        rows.add(metrics.skip(i).take(cols).toList());
      }

      final widgets = <Widget>[];
      for (int r = 0; r < rows.length; r++) {
        final rowMetrics = rows[r];
        final rowCells = <Widget>[];
        for (int c = 0; c < cols; c++) {
          if (c < rowMetrics.length) {
            rowCells.add(_buildHeroCell(rowMetrics[c], totals, true, cw));
          } else {
            rowCells.add(SizedBox(width: cw));
          }
          if (c < cols - 1) rowCells.add(const SizedBox(width: colGap));
        }
        widgets.add(IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rowCells,
          ),
        ));
        if (r < rows.length - 1) {
          widgets.add(Container(
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 11),
            color: LhColors.line2,
          ));
        }
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
    });
  }

  Widget _buildDetailListItem(Map<String, dynamic> r, int idx, String type) {
    final name = r['name']?.toString() ?? '';
    final group = r['group']?.toString() ?? '';
    final profit = (r['profit'] as num?)?.toDouble() ?? 0;
    final isNeg = profit < 0;
    final rank = (idx + 1).toString().padLeft(2, '0');
    final isTop3 = idx < 3;
    final groupColor = lhGroupColor(group);

    // 毛利率 = profit / sales × 100%
    final salesRaw = (r['sales'] as num?)?.toDouble() ?? 0;
    final hasRate = salesRaw != 0;
    final rateValue = hasRate ? profit / salesRaw * 100 : 0.0;

    // Meta row — same as main list, no period scaling (HTML detail: r[k] || 0)
    final metaItems = <_MetaItem>[];
    for (final k in (_metrics[type] ?? []).where((key) => key != 'discount')) {
      final v = (r[k] as num?)?.toDouble() ?? 0;
      metaItems.add(_MetaItem(_metricShort(k, tab: type), '${_fmt(v.abs())}${_unit(v.abs())}'));
    }

    final tagColors = _groupTagColors(group);
    final tagBg = tagColors.bg;
    final tagFg = tagColors.fg;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: LhColors.line2, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rank — match main list visual language
          SizedBox(
            width: 22,
            height: 22,
            child: isTop3
                ? Container(
                    decoration: BoxDecoration(
                      color: LhColors.copperSoft,
                      border: Border.all(color: LhColors.copper.withAlpha(140), width: 1),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      rank,
                      style: LhTypography.mono(
                        size: 9.5,
                        color: LhColors.copper,
                        weight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      rank,
                      style: LhTypography.mono(
                        size: 10.5,
                        color: groupColor,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          // Main
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name, style: LhTypography.sans(size: 12.5, weight: FontWeight.w600, color: LhColors.ink), overflow: TextOverflow.ellipsis),
                    ),
                    if (group.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: tagBg, borderRadius: BorderRadius.circular(3)),
                        child: Text(group, style: LhTypography.sans(size: 8.5, color: tagFg, weight: FontWeight.w600, letterSpacing: 0.3)),
                      ),
                    ],
                  ],
                ),
                // Meta
                if (metaItems.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 10,
                    runSpacing: 3,
                    children: metaItems.map((m) => RichText(
                      text: TextSpan(children: [
                        TextSpan(text: '${m.label} ', style: LhTypography.mono(size: 9.5, color: LhColors.mute2)),
                        TextSpan(text: m.value, style: LhTypography.mono(size: 9.5, color: LhColors.mute, weight: FontWeight.w500)),
                      ]),
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Value
          SizedBox(
            width: 72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                RichText(
                  text: TextSpan(children: [
                    if (isNeg) TextSpan(text: '-', style: LhTypography.sans(size: 13, weight: FontWeight.w600, color: LhColors.neg, letterSpacing: -0.2)),
                    TextSpan(text: _fmt(profit.abs()), style: LhTypography.sans(size: 13, weight: FontWeight.w600, color: isNeg ? LhColors.neg : LhColors.ink, letterSpacing: -0.2)),
                    TextSpan(text: _unit(profit.abs()), style: LhTypography.mono(size: 9.5, color: LhColors.mute, weight: FontWeight.w500)),
                  ]),
                ),
                const SizedBox(height: 1),
                Text('毛利', style: LhTypography.mono(size: 9, color: LhColors.mute, weight: FontWeight.w600, letterSpacing: 0.8)),
                const SizedBox(height: 4),
                hasRate
                    ? RichText(
                        text: TextSpan(children: [
                          TextSpan(
                            text: rateValue.toStringAsFixed(rateValue.abs() >= 100 ? 1 : 2),
                            style: LhTypography.mono(size: 10.5, color: rateValue < 0 ? LhColors.neg : LhColors.ink2, weight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: '%',
                            style: LhTypography.mono(size: 8, color: LhColors.mute, weight: FontWeight.w500),
                          ),
                        ]),
                      )
                    : Text('—', style: LhTypography.mono(size: 10.5, color: LhColors.mute2, weight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaItem {
  const _MetaItem(this.label, this.value);
  final String label;
  final String value;
}

class _SubTabInfo {
  const _SubTabInfo({required this.key, required this.label, required this.color});
  final String key;
  final String label;
  final Color color;
}

// ── Brand refresh loader（灯塔 logo + 铜色旋转环）────────────────────────────
class _LhBrandLoader extends StatefulWidget {
  const _LhBrandLoader({this.size = 40});

  final double size;

  @override
  State<_LhBrandLoader> createState() => _LhBrandLoaderState();
}

class _LhBrandLoaderState extends State<_LhBrandLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final mark = s * 0.52;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(
            turns: _spin,
            child: SizedBox(
              width: s,
              height: s,
              child: CustomPaint(
                painter: _LhLoaderRingPainter(stroke: math.max(1.5, s * 0.05)),
              ),
            ),
          ),
          Container(
            width: mark,
            height: mark,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A1816), Color(0xFF3A342C)],
              ),
              borderRadius: BorderRadius.circular(mark * 0.28),
              border: Border.all(color: LhColors.copper.withAlpha(72), width: 1),
            ),
            child: Center(
              child: Container(
                width: mark * 0.22,
                height: mark * 0.22,
                decoration: BoxDecoration(
                  color: LhColors.copper,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: LhColors.copper.withAlpha(150), blurRadius: mark * 0.18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LhLoaderRingPainter extends CustomPainter {
  const _LhLoaderRingPainter({required this.stroke});

  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = LhColors.copper;
    canvas.drawArc(rect.deflate(stroke), -math.pi / 2, math.pi * 1.35, false, paint);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = LhColors.line2.withAlpha(160);
    canvas.drawArc(rect.deflate(stroke), math.pi * 0.55, math.pi * 1.55, false, track);
  }

  @override
  bool shouldRepaint(covariant _LhLoaderRingPainter oldDelegate) =>
      oldDelegate.stroke != stroke;
}

// ── Dropdown panel (HTML `.dropdown`) ───────────────────────────────────────
class _LhDropdownPanel extends StatelessWidget {
  const _LhDropdownPanel({
    this.width = 220,
    this.maxHeight = 360,
    required this.child,
  });

  final double width;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: LhColors.paper,
          border: Border.all(color: LhColors.line, width: 1),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Color(0x23140A00), blurRadius: 28, offset: Offset(0, 12)),
            BoxShadow(color: Color(0x0D140A00), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ANALYSIS support widgets / data classes
// ═════════════════════════════════════════════════════════════════════════════


// ═════════════════════════════════════════════════════════════════════════════
// ANALYSIS — 数据类 + Cube painter + 卡片外壳
// ═════════════════════════════════════════════════════════════════════════════

class _CubePoint {
  const _CubePoint({
    required this.xi,
    required this.yi,
    required this.zi,
    required this.x,
    required this.y,
    required this.z,
    required this.value,
    required this.productGroup,
    required this.supplyGroup,
    required this.channelGroup,
    required this.supplyHun,
    required this.channelHun,
    required this.owner,
  });
  final int xi, yi, zi;
  final String x, y, z;
  final double value;
  final String productGroup;
  final String supplyGroup;
  final String channelGroup;
  final String supplyHun;   // 'U' | 'N' | 'H' | 'mixed' | 'none'
  final String channelHun;
  final String owner;       // 第 4 维度：该坐标的负责人（mock 派生）
}

/// Owner 聚合统计（用于 owner strip 显示）
class _OwnerStat {
  int count = 0;
  double totalValue = 0;
}

/// 按「产品组（业务线）」把坐标派生到负责人（mock）：
///   能源   → 王一凡
///   运营商 → 石淼 / 徐峥（按供给方名稳定二分，同一供给方永远同一负责人）
///   其他   → ""（未分配，不 mock 假名字）
/// 同一 (productGroup, supplyName) 永远归同一负责人。
String _deriveCubeOwner(String productGroup, String supplyName) {
  switch (productGroup) {
    case '能源':
      return '王一凡';
    case '运营商':
      return supplyName.isEmpty || supplyName.hashCode.isEven ? '石淼' : '徐峥';
    default:
      return '';
  }
}

class _CubeData {
  const _CubeData({
    required this.products,
    required this.supplies,
    required this.channels,
    required this.lit,
    this.litCount,
    this.totalPossible,
    this.coveragePct,
  });
  final List<({String name, String group, double profit})> products;
  final List<({String name, String group, double profit})> supplies;
  final List<({String name, String group, double profit})> channels;
  final List<_CubePoint> lit;
  final int? litCount;
  final int? totalPossible;
  final double? coveragePct;
}

/// 分析卡：editorial 风格、统一外壳，无 accent 色条。
class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({
    required this.index,
    required this.title,
    required this.sub,
    required this.child,
    this.padContent = true,
  });

  final String index; // "§ 01"
  final String title; // "3D 坐标"
  final String sub;   // "产品 × 供给方 × 渠道"
  final Widget child;
  final bool padContent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: LhColors.paper,
        border: Border.all(color: LhColors.line2, width: 1),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x08140A00), blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题条
            Container(
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: LhColors.line2, width: 1)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    index,
                    style: LhTypography.mono(
                      size: 9.5,
                      color: LhColors.mute2,
                      weight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    title,
                    style: LhTypography.sans(
                      size: 13,
                      color: LhColors.ink,
                      weight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sub,
                      style: LhTypography.mono(
                        size: 10,
                        color: LhColors.mute,
                        weight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: padContent
                  ? const EdgeInsets.fromLTRB(14, 14, 14, 14)
                  : EdgeInsets.zero,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// 3D 立方体 painter：(X 产品, Y 供给, Z 渠道) → 2D 投影。
/// 投影法同 lighthouse_my_v4.html — Y 轴朝右上方 30° 退缩。
class _CubePainter extends CustomPainter {
  const _CubePainter({
    required this.data,
    this.matched,
    this.dimUnmatched = false,
    this.selectedKey,
    this.selectedOwner,
    this.yaw = math.pi / 6,
    this.pitch = math.pi / 6,
    this.scale = 1.0,
    this.pan = Offset.zero,
    this.showAxisNames = true,
    this.showProductTicks = true,
    this.showSupplyLabels = false,
    this.showChannelLabels = false,
    this.showOwnerInitials = true,
  });
  final _CubeData data;
  final Set<String>? matched;  // 'xi-yi-zi' 集合；null = 全部匹配
  final bool dimUnmatched;     // 有活动 filter 时，淡化非匹配点
  final String? selectedKey;   // 'xi-yi-zi' 形式，被点击高亮的那个亮点
  final String? selectedOwner; // 选中的负责人（第 4 维度），cluster spider 高亮
  final double yaw;            // 绕竖直轴（左右拖动）
  final double pitch;          // 绕水平轴（上下拖动）
  final double scale;          // 缩放因子（双指捏合）
  final Offset pan;            // 平移（双指拖动）
  final bool showAxisNames;        // 产品轴名
  final bool showProductTicks;     // X 轴每个 tick 的产品名
  final bool showSupplyLabels;     // 供给方轴名 + Y 轴刻度名
  final bool showChannelLabels;    // 渠道轴名 + Z 轴刻度名
  final bool showOwnerInitials;    // owner 质心圆里的首字

  /// Owner 调色板 — 8 色，柔和但足够分散，与 editorial paper 底色协调
  /// 排序前的颜色顺序经过手工调整，相邻不撞色
  static const List<Color> _kOwnerPalette = [
    Color(0xFFB8884A), // copper       铜
    Color(0xFF1F6B4A), // sinopec      墨绿
    Color(0xFF5B47E8), // carrier      靛紫
    Color(0xFFC9842A), // dict         琥珀
    Color(0xFF1F3A5F), // product      深海军蓝
    Color(0xFFA33A2A), // cnpc         砖红
    Color(0xFF4A8A7B), // private      青松
    Color(0xFF7A6CC4), // multi        薰衣
  ];

  /// 把 lit 中的所有 owner 排序后稳定分配颜色。
  /// 空 owner（未分配负责人）映射到中性灰，不占用 palette 槽位。
  static Map<String, Color> ownerColorMap(List<_CubePoint> lit) {
    final owners = <String>{};
    for (final c in lit) {
      if (c.owner.isNotEmpty) owners.add(c.owner);
    }
    final sorted = owners.toList()..sort();
    final map = <String, Color>{};
    for (int i = 0; i < sorted.length; i++) {
      map[sorted[i]] = _kOwnerPalette[i % _kOwnerPalette.length];
    }
    return map;
  }

  /// 单点取色 — owner 有色则取 owner 色，否则降级中性灰
  static Color _colorForOwner(String owner, Map<String, Color> ownerColors) {
    if (owner.isEmpty) return LhColors.mute;
    return ownerColors[owner] ?? LhColors.mute;
  }

  /// 通用 3D → 2D 投影构造器，被 paint 与 projectLitPoints 共用。
  /// 先把 (x,y,z) 平移到立方体中心，再依次绕 Z(yaw)、绕 X(pitch) 旋转，
  /// 最后做正交投影（Y 屏幕轴朝下）。
  static Offset Function(num, num, num) _makeProjector({
    required _CubeData data,
    required Size size,
    required double yaw,
    required double pitch,
    required double scale,
    required Offset pan,
  }) {
    final nX = data.products.length;
    final nY = data.supplies.length;
    final nZ = data.channels.length;

    const padLeft = 14.0, padRight = 46.0, padTop = 24.0, padBottom = 46.0;
    final usableW = size.width - padLeft - padRight;
    final usableH = size.height - padTop - padBottom;

    // 用最长对角线决定基础单位，确保旋转到任意角度都能装下
    final maxExtent = math.sqrt(
      ((nX - 1) * (nX - 1) + (nY - 1) * (nY - 1) + (nZ - 1) * (nZ - 1)).toDouble(),
    );
    final baseUnit = maxExtent < 1
        ? 12.0
        : (math.min(usableW, usableH) / maxExtent).clamp(7.0, 38.0);
    final unit = baseUnit * scale;

    final cx = (nX - 1) / 2.0;
    final cy = (nY - 1) / 2.0;
    final cz = (nZ - 1) / 2.0;
    final ox = padLeft + usableW / 2.0 + pan.dx;
    final oy = padTop + usableH / 2.0 + pan.dy;

    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    final cosP = math.cos(pitch), sinP = math.sin(pitch);

    return (num x, num y, num z) {
      final dx = (x.toDouble() - cx) * unit;
      final dy = (y.toDouble() - cy) * unit;
      final dz = (z.toDouble() - cz) * unit;
      // 绕 Z（yaw）
      final x1 = dx * cosY - dy * sinY;
      final y1 = dx * sinY + dy * cosY;
      // 绕 X（pitch）
      final z2 = y1 * sinP + dz * cosP;
      // 正交投影，屏幕 Y 朝下
      return Offset(ox + x1, oy - z2);
    };
  }

  /// 投影后的 depth（数值越大越靠后），用来排序绘制顺序
  static double _depthOf(double x, double y, double z, _CubeData data, double yaw, double pitch) {
    final nX = data.products.length;
    final nY = data.supplies.length;
    final nZ = data.channels.length;
    final cx = (nX - 1) / 2.0;
    final cy = (nY - 1) / 2.0;
    final cz = (nZ - 1) / 2.0;
    final dx = (x - cx);
    final dy = (y - cy);
    final dz = (z - cz);
    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    final cosP = math.cos(pitch), sinP = math.sin(pitch);
    final y1 = dx * sinY + dy * cosY;
    final z1 = dz;
    // 视线沿屏幕外的 +y 方向，所以 rotated-y 越大越靠后
    return y1 * cosP + z1 * sinP;
  }

  /// 与 paint 内部完全相同的投影几何，提取出来给 hit-test 用。
  /// 输入：data + canvas size + 当前视角；输出：每个亮点的屏幕坐标
  static Map<String, Offset> projectLitPoints(
    _CubeData data,
    Size size, {
    double yaw = math.pi / 6,
    double pitch = math.pi / 6,
    double scale = 1.0,
    Offset pan = Offset.zero,
  }) {
    if (data.products.isEmpty) return const {};
    final nX = data.products.length;
    final nY = data.supplies.length;
    final nZ = data.channels.length;
    if (nX < 2 || nY < 2 || nZ < 2) return const {};

    const padLeft = 14.0, padRight = 46.0, padTop = 24.0, padBottom = 46.0;
    final usableW = size.width - padLeft - padRight;
    final usableH = size.height - padTop - padBottom;
    if (usableW < 50 || usableH < 50) return const {};

    final proj = _makeProjector(
      data: data, size: size,
      yaw: yaw, pitch: pitch, scale: scale, pan: pan,
    );

    final positions = <String, Offset>{};
    for (final c in data.lit) {
      positions['${c.xi}-${c.yi}-${c.zi}'] =
          proj(c.xi.toDouble(), c.yi.toDouble(), c.zi.toDouble());
    }
    return positions;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.products.isEmpty) return;

    final nX = data.products.length;
    final nY = data.supplies.length;
    final nZ = data.channels.length;
    if (nX < 2 || nY < 2 || nZ < 2) return;

    final usableW = size.width - 14.0 - 46.0;
    final usableH = size.height - 24.0 - 46.0;
    if (usableW < 50 || usableH < 50) return;

    // ── 投影器：可自由旋转 / 缩放 / 平移 ──
    final proj = _makeProjector(
      data: data, size: size,
      yaw: yaw, pitch: pitch, scale: scale, pan: pan,
    );

    final X = (nX - 1).toDouble();
    final Y = (nY - 1).toDouble();
    final Z = (nZ - 1).toDouble();

    final c000 = proj(0, 0, 0);
    final c100 = proj(X, 0, 0);
    final c010 = proj(0, Y, 0);
    final c001 = proj(0, 0, Z);
    final c110 = proj(X, Y, 0);
    final c101 = proj(X, 0, Z);
    final c011 = proj(0, Y, Z);
    final c111 = proj(X, Y, Z);

    // ═══════════════════════════════════════════════════════════════════
    // Layer 1: 三面墙（地板 + 后墙 + 左墙）— 用冷灰，去 cream 复古感
    // ═══════════════════════════════════════════════════════════════════
    const wallColor = Color(0xFFEFEBF9);  // 冷感的暖灰，alpha 控制层次

    // 地板 (z=0)
    final floorPath = Path()
      ..moveTo(c000.dx, c000.dy)
      ..lineTo(c100.dx, c100.dy)
      ..lineTo(c110.dx, c110.dy)
      ..lineTo(c010.dx, c010.dy)
      ..close();
    canvas.drawPath(
      floorPath,
      Paint()
        ..color = wallColor.withAlpha(120)
        ..style = PaintingStyle.fill,
    );

    // 后墙 (x=0)
    final backPath = Path()
      ..moveTo(c000.dx, c000.dy)
      ..lineTo(c001.dx, c001.dy)
      ..lineTo(c011.dx, c011.dy)
      ..lineTo(c010.dx, c010.dy)
      ..close();
    canvas.drawPath(
      backPath,
      Paint()
        ..color = wallColor.withAlpha(60)
        ..style = PaintingStyle.fill,
    );

    // 左墙 (y=Y)
    final leftPath = Path()
      ..moveTo(c010.dx, c010.dy)
      ..lineTo(c110.dx, c110.dy)
      ..lineTo(c111.dx, c111.dy)
      ..lineTo(c011.dx, c011.dy)
      ..close();
    canvas.drawPath(
      leftPath,
      Paint()
        ..color = wallColor.withAlpha(40)
        ..style = PaintingStyle.fill,
    );

    // ═══════════════════════════════════════════════════════════════════
    // Layer 2: 网格 hairlines — 含边界线，保证同名维度落在同一网格线上
    // ═══════════════════════════════════════════════════════════════════
    final gridPaint = Paint()
      ..color = LhColors.mute2.withAlpha(50)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    final gridEdgePaint = Paint()
      ..color = LhColors.mute2.withAlpha(72)
      ..strokeWidth = 0.65
      ..style = PaintingStyle.stroke;

    // 地板网格：每个 product 一条纵线 + 每个 supply 一条横线（含 0 与 max）
    for (int x = 0; x < nX; x++) {
      canvas.drawLine(
        proj(x.toDouble(), 0, 0),
        proj(x.toDouble(), Y, 0),
        x == 0 || x == nX - 1 ? gridEdgePaint : gridPaint,
      );
    }
    for (int y = 0; y < nY; y++) {
      canvas.drawLine(
        proj(0, y.toDouble(), 0),
        proj(X, y.toDouble(), 0),
        y == 0 || y == nY - 1 ? gridEdgePaint : gridPaint,
      );
    }

    // 后墙网格：Y 方向 + Z 方向
    for (int y = 0; y < nY; y++) {
      canvas.drawLine(
        proj(0, y.toDouble(), 0),
        proj(0, y.toDouble(), Z),
        y == 0 || y == nY - 1 ? gridEdgePaint : gridPaint,
      );
    }
    for (int z = 0; z < nZ; z++) {
      canvas.drawLine(
        proj(0, 0, z.toDouble()),
        proj(0, Y, z.toDouble()),
        z == 0 || z == nZ - 1 ? gridEdgePaint : gridPaint,
      );
    }

    // 左墙网格：X 方向 + Z 方向
    for (int x = 0; x < nX; x++) {
      canvas.drawLine(
        proj(x.toDouble(), Y, 0),
        proj(x.toDouble(), Y, Z),
        x == 0 || x == nX - 1 ? gridEdgePaint : gridPaint,
      );
    }
    for (int z = 0; z < nZ; z++) {
      canvas.drawLine(
        proj(0, Y, z.toDouble()),
        proj(X, Y, z.toDouble()),
        z == 0 || z == nZ - 1 ? gridEdgePaint : gridPaint,
      );
    }

    // 未点亮交点 — 全 P×S×C 格，与 lit 共用整数网格坐标
    final litKeys = data.lit.map((p) => '${p.xi}-${p.yi}-${p.zi}').toSet();
    final unlitFront = Paint()..color = LhColors.mute2.withAlpha(55);
    final unlitBack = Paint()..color = LhColors.line2.withAlpha(70);
    for (int z = 0; z < nZ; z++) {
      for (int y = 0; y < nY; y++) {
        for (int x = 0; x < nX; x++) {
          if (litKeys.contains('$x-$y-$z')) continue;
          final p = proj(x.toDouble(), y.toDouble(), z.toDouble());
          canvas.drawCircle(p, y > nY / 2 ? 1.5 : 2.0, y > nY / 2 ? unlitBack : unlitFront);
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Layer 3: 边线 (前 8 实线 + 后 4 虚线) — 统一深灰 hairline
    // ═══════════════════════════════════════════════════════════════════
    // 后边 4 条：虚线
    final dashPaint = Paint()
      ..color = LhColors.mute2.withAlpha(70)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;
    _dashed(canvas, dashPaint, c010, c110);
    _dashed(canvas, dashPaint, c010, c011);
    _dashed(canvas, dashPaint, c110, c111);
    _dashed(canvas, dashPaint, c011, c111);

    // 前 9 条实线（含 c000 → c100 / c010 / c001 这三条轴边）
    final edgePaint = Paint()
      ..color = LhColors.ink2.withAlpha(120)
      ..strokeWidth = 0.9
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c000, c100, edgePaint);
    canvas.drawLine(c000, c010, edgePaint);
    canvas.drawLine(c000, c001, edgePaint);
    canvas.drawLine(c100, c110, edgePaint);
    canvas.drawLine(c100, c101, edgePaint);
    canvas.drawLine(c001, c101, edgePaint);
    canvas.drawLine(c001, c011, edgePaint);
    canvas.drawLine(c101, c111, edgePaint);

    // ═══════════════════════════════════════════════════════════════════
    // Layer 4: 三轴箭头（在 cube 外延伸，统一深灰，标签同色）
    // ═══════════════════════════════════════════════════════════════════
    final axisColor = LhColors.ink2;
    final xExt = proj(X + 0.4, 0, 0);
    final yExt = proj(0, Y + 0.4, 0);
    final zExt = proj(0, 0, Z + 0.4);

    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c100, xExt, axisPaint);
    canvas.drawLine(c010, yExt, axisPaint);
    canvas.drawLine(c001, zExt, axisPaint);
    _arrow(canvas, axisColor, c100, xExt);
    _arrow(canvas, axisColor, c010, yExt);
    _arrow(canvas, axisColor, c001, zExt);

    // 轴标签 — 产品 / 供给 / 渠道各自独立开关
    if (showAxisNames) {
      final xLab = proj(X + 1.0, 0, 0);
      _label(canvas, '产品', xLab + const Offset(0, 13), 11, axisColor, FontWeight.w600,
          anchor: _TA.center);
    }
    if (showSupplyLabels) {
      final yLab = proj(0, Y + 1.0, 0);
      _label(canvas, '供给方', yLab + const Offset(7, 0), 11, axisColor, FontWeight.w600,
          anchor: _TA.left);
    }
    if (showChannelLabels) {
      final zLab = proj(0, 0, Z + 0.8);
      _label(canvas, '渠道', zLab + const Offset(0, -8), 11, axisColor, FontWeight.w600,
          anchor: _TA.center);
    }

    Offset axisPerp(num ax, num ay, num az, num bx, num by, num bz) {
      final dir = proj(bx, by, bz) - proj(ax, ay, az);
      if (dir.distance < 0.001) return const Offset(0, 1);
      final perp = Offset(-dir.dy, dir.dx);
      return perp / perp.distance;
    }

    void drawDimTick({
      required Offset tick,
      required Offset perp,
      required Color groupCol,
      required String? label,
      required _TA anchor,
    }) {
      canvas.drawLine(
        tick,
        tick + perp * 4,
        Paint()
          ..color = groupCol.withAlpha(190)
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round,
      );
      final dotPos = tick + perp * 10;
      canvas.drawCircle(dotPos, 2.0, Paint()..color = groupCol);
      canvas.drawCircle(
        dotPos + const Offset(-0.5, -0.5),
        0.6,
        Paint()..color = Colors.white.withAlpha(180),
      );
      if (label != null) {
        final short = label.length > 8 ? '${label.substring(0, 7)}…' : label;
        _label(
          canvas,
          short,
          tick + perp * 19,
          8.5,
          LhColors.ink2,
          FontWeight.w700,
          anchor: anchor,
          letterSpacing: 0.2,
        );
      }
    }

    // 产品刻度 — 每个 tick 加业务线色 accent；标签前画 editorial dot
    final xPerp = axisPerp(0, 0, 0, 1, 0, 0);
    for (int i = 0; i < nX; i++) {
      final tick = proj(i.toDouble(), 0, 0);
      final group = data.products[i].group;
      final groupCol = group.isEmpty ? LhColors.mute2 : lhGroupColor(group);
      drawDimTick(
        tick: tick,
        perp: xPerp,
        groupCol: groupCol,
        label: showProductTicks ? data.products[i].name : null,
        anchor: _TA.center,
      );
    }

    // 供给刻度 — Y 轴，默认隐藏
    if (showSupplyLabels) {
      final yPerp = axisPerp(0, 0, 0, 0, 1, 0);
      for (int i = 0; i < nY; i++) {
        final tick = proj(0, i.toDouble(), 0);
        final group = data.supplies[i].group;
        final groupCol = group.isEmpty ? LhColors.mute2 : lhGroupColor(group);
        drawDimTick(
          tick: tick,
          perp: yPerp,
          groupCol: groupCol,
          label: data.supplies[i].name,
          anchor: _TA.left,
        );
      }
    }

    // 渠道刻度 — Z 轴，默认隐藏
    if (showChannelLabels) {
      final zPerp = axisPerp(0, 0, 0, 0, 0, 1);
      for (int i = 0; i < nZ; i++) {
        final tick = proj(0, 0, i.toDouble());
        final group = data.channels[i].group;
        final groupCol = group.isEmpty ? LhColors.mute2 : lhGroupColor(group);
        drawDimTick(
          tick: tick,
          perp: zPerp,
          groupCol: groupCol,
          label: data.channels[i].name,
          anchor: _TA.left,
        );
      }
    }

    // ═══════════════════════════════════════════════════════════════════
    // Layer 5: 亮点 + 第 4 维度（owner cluster spider）
    //
    // 数学逻辑：
    //   对每个 owner w，持有点集 {(xi,yi,zi)}，算 3D 质心后投影到 2D
    //   从质心向每个成员画细线（spider）
    //   质心位置画一个带首字标识的圆
    //
    //   selectedOwner == null  → 所有 spider 用 alpha 32 平淡画
    //   selectedOwner == w     → 该 owner 的 spider alpha 160 突出
    //                            该 owner 的点保持完整渲染
    //                            其他 owner 的点缩小淡化
    // ═══════════════════════════════════════════════════════════════════
    bool isMatch(_CubePoint c) {
      if (matched == null) return true;
      return matched!.contains('${c.xi}-${c.yi}-${c.zi}');
    }
    bool isInSelectedOwner(_CubePoint c) =>
        selectedOwner == null || c.owner == selectedOwner;

    // ── 计算 owner 颜色映射（painter 内一次性算好，多个 Pass 共用）──
    final ownerColors = ownerColorMap(data.lit);

    // 按当前视角的深度（rotated y）从远到近排序，确保前后遮挡正确
    final sortedLit = [...data.lit]..sort((a, b) {
      final da = _depthOf(a.xi.toDouble(), a.yi.toDouble(), a.zi.toDouble(), data, yaw, pitch);
      final db = _depthOf(b.xi.toDouble(), b.yi.toDouble(), b.zi.toDouble(), data, yaw, pitch);
      return db.compareTo(da);
    });

    // Pass 1: filter 不匹配点（dimUnmatched 时画为淡灰小圈）
    if (dimUnmatched) {
      for (final c in sortedLit) {
        if (isMatch(c)) continue;
        final p = proj(c.xi.toDouble(), c.yi.toDouble(), c.zi.toDouble());
        canvas.drawCircle(p, 3.0, Paint()..color = LhColors.mute2.withAlpha(48));
        canvas.drawCircle(p, 1.5, Paint()..color = LhColors.mute2.withAlpha(140));
      }
    }

    // ── Owner 聚类：按 owner 分组 + 投影 + 算质心 ──
    final ownerGroups = <String, List<Offset>>{};
    for (final c in sortedLit) {
      if (!isMatch(c)) continue;
      final p = proj(c.xi.toDouble(), c.yi.toDouble(), c.zi.toDouble());
      ownerGroups.putIfAbsent(c.owner, () => []).add(p);
    }
    final ownerCentroids = <String, Offset>{};
    ownerGroups.forEach((owner, points) {
      double sx = 0, sy = 0;
      for (final pt in points) {
        sx += pt.dx;
        sy += pt.dy;
      }
      ownerCentroids[owner] = Offset(sx / points.length, sy / points.length);
    });

    // Pass 2: Spider 连线（质心 → 每个亮点；每个 owner 用各自颜色）
    // 顺序：先画其他 owner，再画 selected owner，让选中态盖在上层
    final otherOwners = ownerGroups.keys.where((o) => o != selectedOwner).toList();
    final selectedFirst = selectedOwner != null && ownerGroups.containsKey(selectedOwner)
        ? [selectedOwner!]
        : <String>[];
    final drawOrder = [...otherOwners, ...selectedFirst];

    for (final owner in drawOrder) {
      final pts = ownerGroups[owner]!;
      final centroid = ownerCentroids[owner]!;
      if (pts.length < 2) continue; // 1 个点无 spider

      final isThisOwner = selectedOwner == owner;
      final ownerCol = _colorForOwner(owner, ownerColors);
      final spiderAlpha = selectedOwner == null
          ? 38
          : (isThisOwner ? 180 : 10);
      final spiderWidth = isThisOwner ? 1.3 : 0.6;
      final spiderPaint = Paint()
        ..color = ownerCol.withAlpha(spiderAlpha)
        ..strokeWidth = spiderWidth
        ..strokeCap = StrokeCap.round;
      for (final pt in pts) {
        canvas.drawLine(centroid, pt, spiderPaint);
      }
    }

    // Pass 3: 匹配点的地板投影
    for (final c in sortedLit) {
      if (!isMatch(c)) continue;
      if (!isInSelectedOwner(c)) continue;
      final shadow = proj(c.xi.toDouble(), c.yi.toDouble(), 0);
      canvas.drawCircle(shadow, 3.5, Paint()..color = const Color(0x14140A00));
    }

    // Pass 4: 灯柱（细线连到地板，跟随 owner 色淡化）
    for (final c in sortedLit) {
      if (!isMatch(c)) continue;
      if (!isInSelectedOwner(c)) continue;
      final p = proj(c.xi.toDouble(), c.yi.toDouble(), c.zi.toDouble());
      final shadow = proj(c.xi.toDouble(), c.yi.toDouble(), 0);
      if ((p - shadow).distance > 4) {
        canvas.drawLine(
          shadow, p,
          Paint()
            ..color = _colorForOwner(c.owner, ownerColors).withAlpha(46)
            ..strokeWidth = 0.6
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Pass 5: 主体（按 owner 着色 — 多彩；owner 选中时淡化其他 owner 的点）
    for (final c in sortedLit) {
      if (!isMatch(c)) continue;
      final p = proj(c.xi.toDouble(), c.yi.toDouble(), c.zi.toDouble());
      final isSelected = selectedKey == '${c.xi}-${c.yi}-${c.zi}';
      final inOwner = isInSelectedOwner(c);

      // 0 值暗点（运营商/出行等 0 利润业务线占位）— 小灰圆，不画光晕，
      // 视觉上与正毛利亮点区分，但仍计入 owner cluster。
      if (c.value == 0) {
        if (!inOwner) {
          canvas.drawCircle(p, 2.0, Paint()..color = LhColors.mute2.withAlpha(36));
        } else {
          canvas.drawCircle(p, 3.2, Paint()..color = LhColors.mute2.withAlpha(110));
          canvas.drawCircle(p, 1.4, Paint()..color = LhColors.mute2.withAlpha(200));
        }
        if (isSelected) {
          canvas.drawCircle(
            p, 6,
            Paint()
              ..color = LhColors.mute2
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.2,
          );
        }
        continue;
      }

      // ── 按 owner 取色 ──
      final pc = _colorForOwner(c.owner, ownerColors);

      if (!inOwner) {
        // 其他 owner 的点 — 缩小淡化，保留自身 owner 色（半透明）
        canvas.drawCircle(p, 3.5, Paint()..color = pc.withAlpha(70));
        continue;
      }

      if (isSelected) {
        // 选中态：外层光晕 + 内核 owner 色 + 白边 + 同色描边
        canvas.drawCircle(p, 22, Paint()..color = pc.withAlpha(30));
        canvas.drawCircle(p, 14, Paint()..color = pc.withAlpha(70));
        canvas.drawCircle(p, 7, Paint()..color = pc);
        canvas.drawCircle(
          p, 7,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
        canvas.drawCircle(
          p, 9.5,
          Paint()
            ..color = pc
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0,
        );
      } else {
        canvas.drawCircle(p, 11, Paint()..color = pc.withAlpha(36));
        canvas.drawCircle(p, 5.5, Paint()..color = pc);
      }
    }

    // Pass 6: Owner 质心标识 (在亮点之上，方便看到归属)
    ownerCentroids.forEach((owner, centroid) {
      final pts = ownerGroups[owner]!;
      if (pts.length < 2) return; // 只一个点没必要画质心
      final isThisOwner = selectedOwner == owner;
      final ownerCol = _colorForOwner(owner, ownerColors);
      final radius = isThisOwner ? 11.0 : 8.5;
      final ringAlpha = selectedOwner == null
          ? 150
          : (isThisOwner ? 255 : 30);
      // 白底（盖住下面的线）
      canvas.drawCircle(centroid, radius, Paint()..color = LhColors.paper);
      // 边框圈 — owner 色
      canvas.drawCircle(
        centroid, radius,
        Paint()
          ..color = ownerCol.withAlpha(ringAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isThisOwner ? 1.8 : 0.9,
      );
      // 首字标识 — 可被开关隐藏（圆圈本身仍画）
      if (showOwnerInitials) {
        final initial = owner.isEmpty ? '?' : owner.substring(0, 1);
        _label(
          canvas, initial, centroid,
          isThisOwner ? 11 : 9.5,
          ownerCol.withAlpha(selectedOwner == null ? 230 : (isThisOwner ? 255 : 60)),
          FontWeight.w700,
          anchor: _TA.center,
        );
      }
    });
  }

  void _dashed(Canvas canvas, Paint paint, Offset a, Offset b) {
    const dashLen = 2.5;
    const gapLen = 2.0;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    final ux = dx / len, uy = dy / len;
    double t = 0;
    while (t < len) {
      final tEnd = t + dashLen < len ? t + dashLen : len;
      canvas.drawLine(
        Offset(a.dx + ux * t, a.dy + uy * t),
        Offset(a.dx + ux * tEnd, a.dy + uy * tEnd),
        paint,
      );
      t += dashLen + gapLen;
    }
  }

  void _arrow(Canvas canvas, Color color, Offset start, Offset end) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    final ux = dx / len, uy = dy / len;
    final px = -uy, py = ux;
    final a = Offset(end.dx - ux * 4 + px * 2.3, end.dy - uy * 4 + py * 2.3);
    final b = Offset(end.dx - ux * 4 - px * 2.3, end.dy - uy * 4 - py * 2.3);
    final path = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _label(
    Canvas canvas,
    String text,
    Offset pos,
    double size,
    Color color,
    FontWeight weight, {
    _TA anchor = _TA.left,
    bool mono = false,
    double letterSpacing = 0,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          fontFamily: mono ? 'Geist Mono' : 'PingFang SC',
          fontFamilyFallback: mono
              ? const ['JetBrains Mono', 'SF Mono', 'Menlo', 'monospace']
              : const ['HarmonyOS Sans SC', 'Noto Sans SC', 'sans-serif'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    double x = pos.dx;
    switch (anchor) {
      case _TA.center:
        x -= tp.width / 2;
        break;
      case _TA.right:
        x -= tp.width;
        break;
      case _TA.left:
        break;
    }
    tp.paint(canvas, Offset(x, pos.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_CubePainter old) =>
      !identical(old.data, data) ||
      old.dimUnmatched != dimUnmatched ||
      !identical(old.matched, matched) ||
      old.selectedKey != selectedKey ||
      old.selectedOwner != selectedOwner ||
      old.yaw != yaw ||
      old.pitch != pitch ||
      old.scale != scale ||
      old.pan != pan ||
      old.showAxisNames != showAxisNames ||
      old.showProductTicks != showProductTicks ||
      old.showSupplyLabels != showSupplyLabels ||
      old.showChannelLabels != showChannelLabels ||
      old.showOwnerInitials != showOwnerInitials;
}

enum _TA { left, center, right }

/// Cube 视角控制栏的胶囊按钮（图标 + 文字 + 铜色描边）
/// onTap 为 null 时按钮整体置灰且不响应。
class _CubeChipButton extends StatelessWidget {
  const _CubeChipButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 与「产品 / 供给」排序栏（_buildSortBtn）一致的灰色框框：
    //   resting = paper 底 + line 灰边；active(传入 copper)= 微灰底 + ink2 边。
    final active = color == LhColors.copper;
    final fg = active ? LhColors.ink : LhColors.mute;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? LhColors.ink.withAlpha(8) : LhColors.paper,
          border: Border.all(
            color: active ? LhColors.ink2 : LhColors.line,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: LhTypography.sans(
                size: 10,
                color: fg,
                weight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

