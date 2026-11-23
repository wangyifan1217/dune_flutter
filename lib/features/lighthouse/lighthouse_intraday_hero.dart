import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_press.dart';
import 'lighthouse_theme.dart';

// ════════════════════════════════════════════════════════════════════════
// 灯塔 · 今日盈利大数卡（分时 / 近7天）（2026-11-23，原型 docs/lighthouse_7day_trend_prototype.html）
//
//   「日 · 近 7 天内 · 一级产品 / 供给 / 渠道 · 全部（没筛分类）」时替换原来的「左大数 + 右日走势」：
//     · 上面：今日盈利 +「截至 15:12 · 进行中」、大数、比昨天同一时刻；
//     · 分时 | 近7天 切换：
//         分时  = 当天累计（实线 + 渐隐面积）对前一天累计（虚线），「现在」红点 + 标签，没到的时段浅底；
//         近7天 = 每天的数连成平滑折线，今天单独一列「进行中」（空心红点，不和完整日连成往下掉的线），
//                 前 6 日日均虚线、最高点标签、点任意一天出浮层；
//     · 底下「选择日期查看分时」：单击 = 只换这张卡（大数 + 分时换成那天），
//       双击 = 整页切到那天（和走势图双击同一套，见 native_lighthouse_page 的 _commitIntradayDay）。
//   底下七格点哪个指标（核销额 / 销售额 / 收入 / GMV / 成本合计…），这张卡就换成哪个指标的分时和近 7 天。
//
//   数据：后端 /lighthouse/intraday?date=（lighthouse-go internal/lighthouse/intraday.go），
//   每次资管同步记一行全公司合计（利润、净利、销售、核销、GMV、收入、成本合计）。快照从上线那天起才有：
//     · 那天没有快照 → 按典型日内节奏推一条曲线，终点落在真实的当天合计上，图例写明「推算」；
//     · 前一天没有快照 → 「比昨天同一时刻」退成「已达昨日全天 x%」；
//     · 再没有 → 退成原来的环比。
//   快照是账本口径（不含资管损益），大数是主 Hero 口径（可能含损益），所以比较只拿快照比快照。
// ════════════════════════════════════════════════════════════════════════

/// 快照里有的指标（和后端 IntradayMetrics 的 json 名一致）。
const kLhIntradayMetricKeys = <String>[
  'profit',
  'netProfit',
  'sales',
  'verifiedSales',
  'gmv',
  'revenue',
  'totalCost',
];

/// 页面指标键 → 快照里的键。
String lhIntradaySnapshotKey(String metric) => switch (metric) {
  'costTotal' => 'totalCost',
  _ => metric,
};

/// 这个指标有没有分时快照（没有就只能按节奏推算）。
bool lhIntradayHasSnapshot(String metric) =>
    kLhIntradayMetricKeys.contains(lhIntradaySnapshotKey(metric));

class LhIntradayPoint {
  LhIntradayPoint.fromJson(Map<String, dynamic> j)
    : at = '${j['at'] ?? ''}',
      minute = (j['minute'] as num?)?.toInt() ?? 0,
      values = {
        for (final k in kLhIntradayMetricKeys)
          if (j[k] is num) k: (j[k] as num).toDouble(),
      };

  const LhIntradayPoint(this.at, this.minute, this.values);

  final String at;
  final int minute;
  final Map<String, double> values;

  double get profit => values['profit'] ?? 0;

  double? valueOf(String metric) => values[lhIntradaySnapshotKey(metric)];
}

class LhIntradayData {
  LhIntradayData.fromJson(Map<String, dynamic> j)
    : available = j['available'] == true,
      restricted = j['restricted'] == true,
      failed = j['failed'] == true,
      date = '${j['date'] ?? ''}',
      since = '${j['since'] ?? ''}',
      today = _points(j['today']),
      prev = _points(j['prev']);

  final bool available;
  final bool restricted;

  /// 前端取数失败（不是后端说没有）。
  final bool failed;

  /// 这份分时是哪一天的（YYYY-MM-DD）；[today] 是这一天，[prev] 是它前一天。
  final String date;
  final String since;
  final List<LhIntradayPoint> today;
  final List<LhIntradayPoint> prev;

  static List<LhIntradayPoint> _points(Object? v) => [
    if (v is List)
      for (final e in v)
        if (e is Map) LhIntradayPoint.fromJson(Map<String, dynamic>.from(e)),
  ];

  LhIntradayPoint? get last => today.isEmpty ? null : today.last;

  /// 前一天在 [minute] 时（含）最近的一次快照。
  LhIntradayPoint? prevAt(int minute) {
    LhIntradayPoint? hit;
    for (final p in prev) {
      if (p.minute > minute) break;
      hit = p;
    }
    return hit;
  }
}

/// 日期条 / 近7天里的一天。[value] 是那天的合计（元，比率指标是百分数）；没有就 null。
class LhIntradayDay {
  const LhIntradayDay({
    required this.date,
    required this.offset,
    this.value,
  });

  final DateTime date;

  /// 0 = 今天，-1 = 昨天…
  final int offset;
  final double? value;

  bool get isToday => offset == 0;
}

/// 画图用的一个点：当天第几分钟 + 数。
class _Pt {
  const _Pt(this.minute, this.v, [this.at = '']);

  final int minute;
  final double v;
  final String at;
}

/// 典型日内节奏：每小时占全天的权重（夜里少，上午起量，晚上最高）。只在没有快照时用来推曲线形状。
const _kTypicalHourWeights = <double>[
  1.0, 0.6, 0.4, 0.3, 0.3, 0.4, 0.8, 1.5, 2.5, 3.5, 4.2, 4.5,
  4.3, 4.4, 4.6, 4.8, 5.0, 5.2, 5.6, 6.0, 5.8, 5.0, 3.6, 2.2,
];

/// 典型节奏下，到当天第 [minute] 分钟累计占全天的比例（0–1）。
double _typicalShare(int minute) {
  final total = _kTypicalHourWeights.fold<double>(0, (a, b) => a + b);
  final h = (minute ~/ 60).clamp(0, 24);
  var acc = 0.0;
  for (var i = 0; i < h && i < 24; i++) {
    acc += _kTypicalHourWeights[i];
  }
  if (h < 24) acc += _kTypicalHourWeights[h] * (minute - h * 60) / 60;
  return acc / total;
}

String _hhmm(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// 推一条曲线：每半小时一个点，到 [endMinute] 时正好是 [endValue]。
List<_Pt> _estimateCurve(double endValue, int endMinute) {
  final endShare = _typicalShare(endMinute);
  if (endShare <= 0) return const [];
  final out = <_Pt>[];
  for (var m = 30; m < endMinute; m += 30) {
    out.add(_Pt(m, endValue * _typicalShare(m) / endShare));
  }
  out.add(_Pt(endMinute, endValue, _hhmm(endMinute)));
  return out;
}

List<_Pt> _snapPoints(List<LhIntradayPoint> ps, String metric) => [
  for (final p in ps)
    if (p.valueOf(metric) != null) _Pt(p.minute, p.valueOf(metric)!, p.at),
];

/// 卡里的红（大数、曲线、现在标签、今天那一列）。
const _kIntradayRed = Color(0xFFD1493F);

/// 近7天折线 / 分时昨天虚线的紫。
const _kLinePurple = Color(0xFF7B5CD8);
const _kLinePurpleDeep = Color(0xFF6B4BD4);
const _kLinePurpleLight = Color(0xFFA48CF0);
const _kPrevDash = Color(0xFF8E72E0);


String _lhWan(double yuan, {int digits = 2}) {
  final fixed = (yuan.abs() / 10000).toStringAsFixed(digits);
  final parts = fixed.split('.');
  final head = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  final s = parts.length > 1 ? '$head.${parts[1]}' : head;
  final zero = s.replaceAll(RegExp(r'[0.,]'), '').isEmpty;
  return yuan < 0 && !zero ? '−$s' : s;
}

String _md(DateTime d) => '${d.month}/${d.day}';

const _kWeekdays = ['一', '二', '三', '四', '五', '六', '日'];
String _weekday(DateTime d) => _kWeekdays[(d.weekday - 1).clamp(0, 6)];

/// 「较 x」里的 ±。
String _signed(String s, double v) => v >= 0 ? '+$s' : '−$s';

double _nice(double x) {
  if (x <= 0 || x.isNaN || x.isInfinite) return 1;
  final p = math.pow(10, (math.log(x) / math.ln10).floor()).toDouble();
  final m = x / p;
  final k = m <= 1 ? 1.0 : (m <= 2 ? 2.0 : (m <= 2.5 ? 2.5 : (m <= 5 ? 5.0 : 10.0)));
  return k * p;
}

/// 平滑曲线（Catmull-Rom → 贝塞尔），控制点的 y 夹在相邻两点之间，不冲过头。
Path _smooth(List<Offset> pts) {
  final path = Path();
  if (pts.isEmpty) return path;
  path.moveTo(pts.first.dx, pts.first.dy);
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = i > 0 ? pts[i - 1] : pts[i];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
    final lo = math.min(p1.dy, p2.dy);
    final hi = math.max(p1.dy, p2.dy);
    final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, (p1.dy + (p2.dy - p0.dy) / 6).clamp(lo, hi).toDouble());
    final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, (p2.dy - (p3.dy - p1.dy) / 6).clamp(lo, hi).toDouble());
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return path;
}

/// 只画路径的前 [t]（0–1），画「从左往右描出来」的入场动画。
Path _partial(Path path, double t) {
  if (t >= 1) return path;
  final out = Path();
  final metrics = path.computeMetrics().toList();
  final total = metrics.fold<double>(0, (a, m) => a + m.length);
  var left = total * t.clamp(0.0, 1.0);
  for (final m in metrics) {
    if (left <= 0) break;
    out.addPath(m.extractPath(0, math.min(left, m.length)), Offset.zero);
    left -= m.length;
  }
  return out;
}

void _dashed(Canvas canvas, Path path, Paint paint, double on, double off) {
  for (final m in path.computeMetrics()) {
    for (var d = 0.0; d < m.length; d += on + off) {
      canvas.drawPath(m.extractPath(d, math.min(d + on, m.length)), paint);
    }
  }
}

void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint, double on, double off) {
  _dashed(canvas, Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy), paint, on, off);
}

class LighthouseIntradayHero extends StatefulWidget {
  const LighthouseIntradayHero({
    super.key,
    required this.metricKey,
    required this.metricLabel,
    required this.days,
    required this.selectedOffset,
    required this.committedOffset,
    required this.value,
    required this.data,
    required this.view,
    required this.onViewChanged,
    required this.onDayTap,
    required this.onDayCommit,
    this.todayData,
    this.isRate = false,
    this.fallbackDelta,
    this.fallbackVs = 'vs 上月同日',
    this.toggle,
    this.footer,
    this.asOfMinute,
  });

  /// 当前指标（利润 / 核销额 / 成本合计…，跟着底下七格走）。
  final String metricKey;

  /// 指标中文名（「利润」显示成「盈利」由卡自己处理）。
  final String metricLabel;

  /// 比率类指标（ROI、毛利率）：大数写 %，没有分时累计。
  final bool isRate;

  /// 近 7 天，旧 → 新，最后一个是今天。
  final List<LhIntradayDay> days;

  /// 卡上正在看的那一天（单击日期条预览出来的，或者就是整页那天）。
  final int selectedOffset;

  /// 整页现在是哪一天（右上角那天，双击切过去的）。
  final int committedOffset;

  /// 正在看的那天的大数（元 / 百分数）。
  final double value;

  /// 正在看的那天的分时（today = 那天，prev = 前一天）。null = 还在加载。
  final LhIntradayData? data;

  /// 今天的分时（近7天里今天那一列画「昨日同时」用）。
  final LhIntradayData? todayData;

  /// 'min' = 分时，'week' = 近7天。
  final String view;
  final ValueChanged<String> onViewChanged;

  /// 单击日期（预览：只换这张卡）。
  final ValueChanged<int> onDayTap;

  /// 双击日期（整页切到那天）。
  final ValueChanged<int> onDayCommit;

  /// 原来的环比，最后的兜底（只在看的就是整页那天时有意义）。
  final ({double pct, bool isUp})? fallbackDelta;
  final String fallbackVs;

  /// 顶上「利润 | 资金」切换条；没有就不放。
  final Widget? toggle;

  /// 底下「数据分析」入口。
  final Widget? footer;

  /// 今天的大数对应的时刻（当天第几分钟，上海时间）；今天没有快照时用它推曲线、写「截至」。
  final int? asOfMinute;

  @override
  State<LighthouseIntradayHero> createState() => _LighthouseIntradayHeroState();
}

class _LighthouseIntradayHeroState extends State<LighthouseIntradayHero> {
  /// 近7天里点开浮层的那一天（days 下标）。
  int? _tipIndex;

  /// 双击判定：两次抬手间隔不超过 320ms、点的是同一天。
  /// 不用 GestureDetector.onDoubleTap —— 那会让单击都多等 300ms 才响应。
  int? _lastTapOffset;
  DateTime? _lastTapAt;

  @override
  void didUpdateWidget(covariant LighthouseIntradayHero old) {
    super.didUpdateWidget(old);
    if (old.metricKey != widget.metricKey || old.view != widget.view) {
      _tipIndex = null;
    }
  }

  /// 单击马上响应；第二下落在同一天、间隔够短 = 双击。
  void _tapDay(int offset) {
    final now = DateTime.now();
    final last = _lastTapAt;
    final isDouble =
        _lastTapOffset == offset && last != null && now.difference(last).inMilliseconds <= 320;
    if (isDouble) {
      _lastTapOffset = null;
      _lastTapAt = null;
      setState(() => _tipIndex = null);
      widget.onDayCommit(offset);
      return;
    }
    _lastTapOffset = offset;
    _lastTapAt = now;
    widget.onDayTap(offset);
  }

  Color _c(Color x, {DunesColorRole role = DunesColorRole.foreground}) =>
      DunesColors.resolve(context, x, role: role);

  // ── 数的写法 ──
  String get _unit => widget.isRate ? '%' : '万';
  String _num(double v) => widget.isRate ? v.toStringAsFixed(1) : _lhWan(v);
  String _num1(double v) => widget.isRate ? v.toStringAsFixed(1) : _lhWan(v, digits: 1);
  String _withUnit(double v) => '${_num(v)}$_unit';

  /// 差值：金额写「1.20万」，比率写「1.2pt」。
  String _diff(double d) => widget.isRate ? '${d.abs().toStringAsFixed(1)}pt' : '${_lhWan(d.abs())}万';

  /// 「盈利」/「核销额」…
  String get _word => widget.metricKey == 'profit' ? '盈利' : widget.metricLabel;

  String _dayName(LhIntradayDay d) => switch (d.offset) {
    0 => '今日',
    -1 => '昨日',
    _ => '${_md(d.date)} ',
  };

  int get _selIndex {
    final i = widget.days.indexWhere((d) => d.offset == widget.selectedOffset);
    return i < 0 ? widget.days.length - 1 : i;
  }

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final sel = _selIndex;
    final day = days[sel];
    final isToday = day.isToday;
    final prevDay = sel > 0 ? days[sel - 1] : null;
    final prevTotal = prevDay?.value;
    final previewing = widget.selectedOffset != widget.committedOffset;

    final red = _c(_kIntradayRed);
    final green = _c(LhColors.pos);
    final ink = _c(LhColors.ink);
    final mute = _c(LhColors.mute2);
    final purple = _c(LhColors.purple);
    final valueColor = widget.value < 0 && !widget.isRate ? green : red;

    // ── 分时：真快照 / 推算 ──
    final metric = widget.metricKey;
    final snapOk = !widget.isRate && lhIntradayHasSnapshot(metric);
    final d = widget.data;
    final realDay = snapOk && d != null ? _snapPoints(d.today, metric) : const <_Pt>[];
    final realPrev = snapOk && d != null ? _snapPoints(d.prev, metric) : const <_Pt>[];
    final asOf = widget.asOfMinute;
    final estDay = realDay.isEmpty && !widget.isRate;
    final dayPts = !estDay
        ? realDay
        : (isToday
              ? (asOf != null && asOf > 0 ? _estimateCurve(widget.value, asOf) : const <_Pt>[])
              : _estimateCurve(widget.value, 1440));
    final estPrev = realPrev.isEmpty && !widget.isRate;
    final prevPts = !estPrev
        ? realPrev
        : (prevTotal != null ? _estimateCurve(prevTotal, 1440) : const <_Pt>[]);
    final estimated = (estDay && dayPts.isNotEmpty) || (estPrev && prevPts.isNotEmpty);

    // 今天的「现在」和昨天同一时刻（都得是真快照）。
    final nowPt = isToday && realDay.isNotEmpty ? realDay.last : null;
    _Pt? prevSame;
    if (nowPt != null) {
      for (final p in realPrev) {
        if (p.minute > nowPt.minute) break;
        prevSame = p;
      }
    }

    // ── 大数右边的比较 ──
    final yLabel = isToday ? '昨日' : '前一日';
    String? cmpMain;
    Color cmpColor = red;
    final cmpSubs = <String>[];
    double? leadPct; // 信息条「领先 / 落后昨日同期」
    if (nowPt != null && prevSame != null && prevSame.v.abs() >= 1) {
      final diff = nowPt.v - prevSame.v;
      final pct = diff / prevSame.v.abs() * 100;
      leadPct = pct;
      cmpColor = diff >= 0 ? red : green;
      cmpMain = '较昨日同时 ${_signed(_diff(diff), diff)}  ${_signed('${pct.abs().toStringAsFixed(1)}%', pct)}';
      if (prevTotal != null) cmpSubs.add('昨日全天 ${_withUnit(prevTotal)}');
      cmpSubs.add('昨日同时 ${_withUnit(prevSame.v)}');
    } else if (isToday && prevTotal != null && prevTotal > 0 && !widget.isRate) {
      cmpMain = '已达昨日全天 ${(widget.value / prevTotal * 100).toStringAsFixed(0)}%';
      cmpColor = valueColor;
      cmpSubs.add('昨日全天 ${_withUnit(prevTotal)}');
    } else if (prevTotal != null) {
      final diff = widget.value - prevTotal;
      cmpColor = diff >= 0 ? red : green;
      final pct = !widget.isRate && prevTotal.abs() >= 1 ? diff / prevTotal.abs() * 100 : null;
      cmpMain = '较$yLabel ${_signed(_diff(diff), diff)}'
          '${pct == null ? '' : '  ${_signed('${pct.abs().toStringAsFixed(1)}%', pct)}'}';
      cmpSubs.add('$yLabel${isToday ? '' : ' ${_md(prevDay!.date)}'}全天 ${_withUnit(prevTotal)}');
    } else if (!previewing && widget.fallbackDelta != null) {
      final fd = widget.fallbackDelta!;
      cmpColor = fd.isUp ? red : green;
      cmpMain = '${fd.isUp ? '▲' : '▼'} ${fd.pct.abs().toStringAsFixed(1)}%';
      cmpSubs.add(widget.fallbackVs);
    }

    final stamp = isToday
        ? (nowPt != null
              ? '截至 ${nowPt.at} · 进行中'
              : (asOf != null ? '截至 ${_hhmm(asOf)} · 进行中' : '进行中'))
        : '${_md(day.date)} 周${_weekday(day.date)} · 全天';

    // ── 近7天的统计（今天不计入日均）──
    final done = [
      for (var i = 0; i < days.length; i++)
        if (!days[i].isToday && days[i].value != null) i,
    ];
    final avg = done.isEmpty ? null : done.fold<double>(0, (a, i) => a + days[i].value!) / done.length;
    int? maxI, minI;
    for (final i in done) {
      if (maxI == null || days[i].value! > days[maxI].value!) maxI = i;
      if (minI == null || days[i].value! < days[minI].value!) minI = i;
    }

    final week = widget.view == 'week';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _c(Colors.white, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _c(const Color(0xFFE7E3EF), role: DunesColorRole.border), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.toggle != null) ...[widget.toggle!, const SizedBox(height: 10)],
          // ── 今日盈利 +「截至 15:12 · 进行中」──
          Row(
            children: [
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  layoutBuilder: (cur, prev) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...prev, if (cur != null) cur],
                  ),
                  child: Text(
                    '${_dayName(day)}$_word'.replaceAll('  ', ' '),
                    key: ValueKey('title|${day.offset}|${widget.metricKey}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LhTypography.sans(context: context, size: 13, weight: FontWeight.w700, color: ink),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: _c(LhColors.purpleSoft, role: DunesColorRole.surface),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      stamp,
                      key: ValueKey('stamp|$stamp'),
                      style: LhTypography.sans(context: context, size: 10.5, weight: FontWeight.w600, color: purple),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ── 大数 │ 比较 ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                flex: 5,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  // 换天 / 换指标：数字从旧值滚到新值（同一指标内才滚，换指标直接换）。
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey('big|${widget.metricKey}'),
                    tween: Tween<double>(end: widget.value),
                    duration: const Duration(milliseconds: 480),
                    curve: Curves.easeOutCubic,
                    builder: (context, shown, _) => Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _num(shown),
                          // 2026-11-23 · 46 / w800 太抢，压到 34 / w700，和页面其它大数同一档。
                          style: LhTypography.number(context: context, size: 34, color: valueColor)
                              .copyWith(letterSpacing: -0.6, height: 1.0),
                        ),
                        TextSpan(
                          text: _unit,
                          style: LhTypography.sans(context: context, size: 14, weight: FontWeight.w600, color: valueColor),
                        ),
                      ],
                    ),
                  ),
                  ),
                ),
              ),
              if (cmpMain != null) ...[
                const SizedBox(width: 12),
                Container(width: 1, height: 34, color: _c(const Color(0xFFECE8F4), role: DunesColorRole.border)),
                const SizedBox(width: 12),
                Expanded(
                  flex: 7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          cmpMain,
                          style: LhTypography.sans(context: context, size: 12.5, weight: FontWeight.w600, color: cmpColor),
                        ),
                      ),
                      if (cmpSubs.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            cmpSubs.join('  ｜  '),
                            style: LhTypography.sans(context: context, size: 11, color: mute),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _viewTabs(week),
          const SizedBox(height: 12),
          // ── 小标题 ──
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, size: 16, color: purple),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  week
                      ? '近7天 · 每日$_word'
                      : '${isToday ? '今日' : '${_md(day.date)} '}${widget.isRate ? widget.metricLabel : '累计$_word'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LhTypography.sans(context: context, size: 13, weight: FontWeight.w700, color: ink),
                ),
              ),
              const Spacer(),
              Text('单位：$_unit', style: LhTypography.sans(context: context, size: 11, color: mute)),
            ],
          ),
          if (week) ...[
            const SizedBox(height: 2),
            Text(
              '每个点是当天$_word${widget.isRate ? '' : '（非累计）'} · 今天仍在累计',
              style: LhTypography.sans(context: context, size: 11, color: mute),
            ),
          ],
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: week
                ? KeyedSubtree(
                    key: const ValueKey('week'),
                    child: _weekSection(days, sel, avg, maxI, minI, done.length),
                  )
                : KeyedSubtree(
                    key: const ValueKey('min'),
                    child: _minuteSection(
                      day: day,
                      isToday: isToday,
                      dayPts: dayPts,
                      prevPts: prevPts,
                      nowPt: nowPt,
                      prevSame: prevSame,
                      prevTotal: prevTotal,
                      estimated: estimated,
                      leadPct: leadPct,
                      avg: avg,
                      previewing: previewing,
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          Text('选择日期查看分时', style: LhTypography.sans(context: context, size: 13, weight: FontWeight.w700, color: ink)),
          const SizedBox(height: 8),
          _dateStrip(days, week),
          if (widget.footer != null) ...[const SizedBox(height: 12), widget.footer!],
        ],
      ),
    );
  }

  // ── 分时 | 近7天 ──
  Widget _viewTabs(bool week) {
    final ink2 = _c(LhColors.ink2);
    Widget tab(String text, String view) {
      final on = (view == 'week') == week;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (!on) widget.onViewChanged(view);
          },
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: LhTypography.sans(
                context: context,
                size: 13,
                weight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? _c(_kLinePurpleDeep) : ink2,
              ),
              child: Text(text),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _c(const Color(0xFFEFECF5), role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
            duration: const Duration(milliseconds: 300),
            curve: const Cubic(0.3, 0.7, 0.2, 1),
            alignment: week ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              // 2026-11-23 · 实心紫渐变太饱和（比大数还抢眼），改成白底块 + 紫字，
              //   和顶上「利润 | 资金」同一种切换条。
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _c(Colors.white, role: DunesColorRole.surface),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14281A5A), blurRadius: 6, offset: Offset(0, 1)),
                  ],
                ),
              ),
            ),
          ),
          ),
          Positioned.fill(child: Row(children: [tab('分时', 'min'), tab('近7天', 'week')])),
        ],
      ),
    );
  }

  // ── 分时 ──
  Widget _minuteSection({
    required LhIntradayDay day,
    required bool isToday,
    required List<_Pt> dayPts,
    required List<_Pt> prevPts,
    required _Pt? nowPt,
    required _Pt? prevSame,
    required double? prevTotal,
    required bool estimated,
    required double? leadPct,
    required double? avg,
    required bool previewing,
  }) {
    final red = _c(_kIntradayRed);
    final green = _c(LhColors.pos);
    final ink2 = _c(LhColors.ink2);
    final mute = _c(LhColors.mute2);
    final d = widget.data;
    final empty = dayPts.isEmpty && prevPts.isEmpty;
    final dayWord = isToday ? '今日' : '当日';
    final prevWord = isToday ? '昨日' : '前一日';

    Widget chart;
    if (widget.isRate) {
      chart = _placeholder('${widget.metricLabel}是比率，没有分时累计 · 看「近7天」');
    } else if (empty) {
      chart = _placeholder(
        d == null
            ? '分时数据加载中…'
            : d.failed
            ? '分时数据暂时取不到，稍后下拉刷新'
            : '这天还没有同步数据，下次同步后出现曲线',
      );
    } else {
      chart = SizedBox(
        height: 190,
        child: TweenAnimationBuilder<double>(
          key: ValueKey('min|${widget.metricKey}|${day.offset}'),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => CustomPaint(
            size: Size.infinite,
            painter: _MinutePainter(
              day: dayPts,
              prev: prevPts,
              isToday: isToday,
              nowMinute: isToday ? (nowPt?.minute ?? (dayPts.isEmpty ? null : dayPts.last.minute)) : null,
              prevSame: prevSame?.v,
              prevEndLabel: prevPts.isEmpty || prevPts.last.minute < 22 * 60
                  ? null
                  : '$prevWord全天 ${_withUnit(prevPts.last.v)}',
              progress: t,
              fmtAxis: (v) => '${_lhWan(v, digits: (v / 10000 - (v / 10000).roundToDouble()).abs() < 1e-6 ? 0 : 1)}万',
              fmtValue: _withUnit,
              red: red,
              prevColor: _c(_kPrevDash),
              mute: _c(const Color(0xFF9A95AA)),
              grid: _c(const Color(0xFFF0EDF6), role: DunesColorRole.border),
              future: _c(const Color(0xFFFAF9FD), role: DunesColorRole.surface),
              futureText: _c(const Color(0xFFB8B3C6)),
              halo: _c(Colors.white, role: DunesColorRole.surface),
              textScale: MediaQuery.textScalerOf(context),
            ),
          ),
        ),
      );
    }

    // 信息条
    final spans = <InlineSpan>[];
    TextStyle ts(Color c, {FontWeight w = FontWeight.w500}) =>
        LhTypography.sans(context: context, size: 12, weight: w, color: c);
    if (leadPct != null) {
      final up = leadPct >= 0;
      spans
        ..add(TextSpan(text: '今日暂${up ? '领先' : '落后'}昨日同期 ', style: ts(ink2)))
        ..add(TextSpan(text: '${leadPct.abs().toStringAsFixed(1)}%', style: ts(up ? red : green, w: FontWeight.w700)));
    } else if (isToday && prevTotal != null && prevTotal > 0 && !widget.isRate) {
      spans
        ..add(TextSpan(text: '今日已达昨日全天 ', style: ts(ink2)))
        ..add(TextSpan(text: '${(widget.value / prevTotal * 100).toStringAsFixed(0)}%', style: ts(red, w: FontWeight.w700)));
    } else if (!isToday && avg != null) {
      final diff = widget.value - avg;
      spans
        ..add(TextSpan(text: '${_md(day.date)} 全天 ', style: ts(ink2)))
        ..add(TextSpan(text: _withUnit(widget.value), style: ts(red, w: FontWeight.w700)))
        ..add(TextSpan(text: '，较日均 ', style: ts(ink2)))
        ..add(TextSpan(text: _signed(_diff(diff), diff), style: ts(diff >= 0 ? red : green, w: FontWeight.w700)));
    }
    final hint = previewing
        ? '双击日期看这天明细'
        : (widget.committedOffset != 0 ? '双击「今天」回到今天' : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        chart,
        if (!widget.isRate && !empty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _legend(Container(width: 16, height: 2.5, color: red), '$dayWord累计'),
              if (prevPts.isNotEmpty)
                _legend(SizedBox(width: 16, height: 4, child: CustomPaint(painter: _DashPainter(_c(_kPrevDash)))), '$prevWord累计'),
              if (estimated)
                Text('曲线按日内节奏推算', style: LhTypography.sans(context: context, size: 11, color: mute)),
            ],
          ),
        ],
        if (spans.isNotEmpty || hint != null) ...[
          const SizedBox(height: 10),
          _infoBar(spans, hint),
        ],
      ],
    );
  }

  Widget _placeholder(String text) => SizedBox(
    height: 150,
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: LhTypography.sans(context: context, size: 12, color: _c(LhColors.mute2)),
      ),
    ),
  );

  Widget _infoBar(List<InlineSpan> spans, String? right) {
    final ink2 = _c(LhColors.ink2);
    final mute = _c(LhColors.mute2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _c(const Color(0xFFF7F5FC), role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: ink2),
          const SizedBox(width: 6),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(TextSpan(children: spans), maxLines: 1),
            ),
          ),
          if (right != null) ...[
            const SizedBox(width: 8),
            Text(right, style: LhTypography.sans(context: context, size: 11, color: mute)),
          ],
        ],
      ),
    );
  }

  Widget _legend(Widget mark, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      mark,
      const SizedBox(width: 5),
      Text(text, style: LhTypography.sans(context: context, size: 11, color: _c(LhColors.mute2))),
    ],
  );

  // ── 近7天 ──
  Widget _weekSection(List<LhIntradayDay> days, int sel, double? avg, int? maxI, int? minI, int doneCount) {
    final red = _c(_kIntradayRed);
    final ink2 = _c(LhColors.ink2);
    final mute = _c(LhColors.mute2);
    final todayI = days.lastIndexWhere((d) => d.isToday);
    final today = todayI < 0 ? null : days[todayI];

    // 今天那一列的「昨日同时」：今天、昨天都有真快照才画。
    double? prevSame;
    final td = widget.todayData;
    if (!widget.isRate && lhIntradayHasSnapshot(widget.metricKey) && td != null) {
      final tPts = _snapPoints(td.today, widget.metricKey);
      if (tPts.isNotEmpty) {
        for (final p in _snapPoints(td.prev, widget.metricKey)) {
          if (p.minute > tPts.last.minute) break;
          prevSame = p.v;
        }
      }
    }
    // 今天的数：卡正在看今天就用大数（和上面对得上），否则用日走势里的。
    final todayValue = today == null ? null : (sel == todayI ? widget.value : today.value);
    final values = [
      for (var i = 0; i < days.length; i++) i == todayI ? todayValue : days[i].value,
    ];

    final chart = SizedBox(
      height: 206,
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, 206);
          final g = _WeekGeom(size, values, avg: avg, prevSame: prevSame);
          final tip = _tipIndex;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (e) {
              final i = g.indexAt(e.localPosition.dx);
              if (i == null || values[i] == null) {
                setState(() => _tipIndex = null);
                return;
              }
              final now = DateTime.now();
              final last = _lastTapAt;
              if (_lastTapOffset == days[i].offset &&
                  last != null &&
                  now.difference(last).inMilliseconds <= 320) {
                _lastTapOffset = null;
                _lastTapAt = null;
                setState(() => _tipIndex = null);
                widget.onDayCommit(days[i].offset);
                return;
              }
              _lastTapOffset = days[i].offset;
              _lastTapAt = now;
              setState(() => _tipIndex = _tipIndex == i ? null : i);
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey('week|${widget.metricKey}'),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) => CustomPaint(
                      painter: _WeekPainter(
                        geom: g,
                        days: days,
                        todayIndex: todayI,
                        selectedIndex: sel,
                        maxIndex: maxI,
                        minIndex: minI,
                        tipIndex: tip,
                        progress: t,
                        isRate: widget.isRate,
                        red: red,
                        redSoft: _c(const Color(0xFFFDF1EF), role: DunesColorRole.surface),
                        purple: _c(_kLinePurple),
                        purpleDeep: _c(_kLinePurpleDeep),
                        purpleLight: _c(_kLinePurpleLight),
                        selFill: _c(const Color(0xFFF5F2FC), role: DunesColorRole.surface),
                        ink2: ink2,
                        mute: _c(const Color(0xFF9A95AA)),
                        connector: _c(const Color(0xFFC9C4D6)),
                        tick: _c(const Color(0xFFA9A3BA)),
                        grid: _c(const Color(0xFFF0EDF6), role: DunesColorRole.border),
                        halo: _c(Colors.white, role: DunesColorRole.surface),
                        textScale: MediaQuery.textScalerOf(context),
                      ),
                    ),
                  ),
                ),
                if (tip != null && tip < days.length && values[tip] != null)
                  _weekTip(g, days, tip, values[tip]!, avg, prevSame),
              ],
            ),
          );
        },
      ),
    );

    // 统计三格
    Widget stat(String label, String? value) => Expanded(
      child: Column(
        children: [
          Text(label, style: LhTypography.sans(context: context, size: 11, color: mute)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value ?? '—',
                    style: LhTypography.number(context: context, size: 16, color: red).copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (value != null)
                    TextSpan(
                      text: _unit,
                      style: LhTypography.sans(context: context, size: 10.5, weight: FontWeight.w600, color: red),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    Widget vline() => Container(width: 1, height: 30, color: _c(const Color(0xFFECE8F4), role: DunesColorRole.border));
    final sum = [
      for (var i = 0; i < days.length; i++)
        if (i != todayI && days[i].value != null) days[i].value!,
    ].fold<double>(0, (a, b) => a + b);
    final stats = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: widget.isRate
          ? [
              stat('日均', avg == null ? null : _num(avg)),
              vline(),
              stat(maxI == null ? '最高' : '最高 · ${_md(days[maxI].date)}', maxI == null ? null : _num(days[maxI].value!)),
              vline(),
              stat(minI == null ? '最低' : '最低 · ${_md(days[minI].date)}', minI == null ? null : _num(days[minI].value!)),
            ]
          : [
              stat('$doneCount日累计', doneCount == 0 ? null : _num(sum)),
              vline(),
              stat('日均$_word', avg == null ? null : _num(avg)),
              vline(),
              stat(maxI == null ? '最高' : '最高 · ${_md(days[maxI].date)}', maxI == null ? null : _num(days[maxI].value!)),
            ],
    );

    // 信息条
    final spans = <InlineSpan>[];
    TextStyle ts(Color c, {FontWeight w = FontWeight.w500}) =>
        LhTypography.sans(context: context, size: 12, weight: w, color: c);
    if (maxI != null) {
      spans.add(TextSpan(text: '${_md(days[maxI].date)} 最高', style: ts(ink2)));
    }
    if (todayValue != null && avg != null && avg.abs() >= 1e-9 && !widget.isRate) {
      spans
        ..add(TextSpan(text: '${spans.isEmpty ? '' : ' · '}今天已达日均 ', style: ts(ink2)))
        ..add(TextSpan(text: '${(todayValue / avg * 100).toStringAsFixed(0)}%', style: ts(red, w: FontWeight.w700)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        chart,
        const SizedBox(height: 4),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _legend(Container(width: 16, height: 2.5, color: _c(_kLinePurple)), '完整日'),
            _legend(
              SizedBox(width: 16, height: 4, child: CustomPaint(painter: _DashPainter(_c(_kLinePurple).withAlpha(150)))),
              '前${doneCount}日日均',
            ),
            _legend(Container(width: 16, height: 2.5, color: red), '今天（进行中）'),
            if (prevSame != null)
              _legend(SizedBox(width: 16, height: 4, child: CustomPaint(painter: _DashPainter(_c(const Color(0xFFA9A3BA))))), '昨日同时'),
          ],
        ),
        const SizedBox(height: 8),
        stats,
        if (spans.isNotEmpty) ...[
          const SizedBox(height: 10),
          _infoBar(spans, '今天不计入日均'),
        ],
      ],
    );
  }

  Widget _weekTip(_WeekGeom g, List<LhIntradayDay> days, int i, double v, double? avg, double? prevSame) {
    final day = days[i];
    final red = _c(_kIntradayRed);
    final green = _c(LhColors.pos);
    final ink = _c(LhColors.ink);
    final ink2 = _c(LhColors.ink2);
    final purple = _c(LhColors.purple);
    final lines = <Widget>[];
    TextStyle s(double size, Color c, {FontWeight w = FontWeight.w500}) =>
        LhTypography.sans(context: context, size: size, weight: w, color: c);
    if (day.isToday) {
      lines.add(Text('今天 · 周${_weekday(day.date)}${widget.asOfMinute == null ? '' : ' 截至${_hhmm(widget.asOfMinute!)}'}', style: s(11, ink2)));
    } else {
      lines.add(Text('${_md(day.date)} 周${_weekday(day.date)}', style: s(11, ink2)));
    }
    final extra = <InlineSpan>[];
    if (day.isToday && prevSame != null) {
      final diff = v - prevSame;
      extra.add(TextSpan(text: '  比昨日同时 ${_signed(_diff(diff), diff)}', style: s(11, diff >= 0 ? red : green, w: FontWeight.w600)));
    } else if (!day.isToday && avg != null) {
      final diff = v - avg;
      extra.add(TextSpan(text: '  较日均 ${_signed(_diff(diff), diff)}', style: s(11, diff >= 0 ? red : green, w: FontWeight.w600)));
    }
    lines.add(
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: _withUnit(v),
              style: LhTypography.number(context: context, size: 14, color: ink).copyWith(fontWeight: FontWeight.w700),
            ),
            ...extra,
          ],
        ),
      ),
    );
    if (day.isToday && avg != null && avg.abs() >= 1e-9 && !widget.isRate) {
      lines.add(Text('已达日均 ${(v / avg * 100).toStringAsFixed(0)}%', style: s(11, ink2)));
    }
    if (!widget.isRate) {
      lines.add(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() => _tipIndex = null);
            widget.onDayTap(day.offset);
            widget.onViewChanged('min');
          },
          child: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(day.isToday ? '看今天分时 →' : '看当天分时 →', style: s(11, purple, w: FontWeight.w700)),
          ),
        ),
      );
    }
    final anchorX = math.min(math.max(g.x(i), 78.0), math.max(78.0, g.size.width - 70));
    // 浮层放点上面；上面放不下（会伸出图外，点不到「看当天分时」）就放点下面。
    const tipH = 82.0;
    final pointTop = math.min(g.y(v), prevSame != null && day.isToday ? g.y(prevSame) : g.y(v));
    final above = pointTop - 14 - tipH >= 0;
    return Positioned(
      left: anchorX,
      top: above ? pointTop - 14 : math.max(g.y(v), prevSame != null && day.isToday ? g.y(prevSame) : g.y(v)) + 16,
      child: FractionalTranslation(
        translation: Offset(-0.5, above ? -1 : 0),
        child: TweenAnimationBuilder<double>(
          key: ValueKey('tip|$i'),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(
              scale: 0.94 + 0.06 * t,
              alignment: above ? Alignment.bottomCenter : Alignment.topCenter,
              child: child,
            ),
          ),
          child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _c(Colors.white, role: DunesColorRole.surface),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color(0x2E28185A), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines,
          ),
        ),
        ),
      ),
    );
  }

  // ── 选择日期查看分时 ──
  Widget _dateStrip(List<LhIntradayDay> days, bool week) {
    final ink = _c(LhColors.ink);
    final mute = _c(LhColors.mute2);
    final purple = _c(LhColors.purple);
    final line = _c(const Color(0xFFECE8F4), role: DunesColorRole.border);
    return Row(
      children: [
        for (var i = 0; i < days.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Builder(
              builder: (context) {
                final day = days[i];
                final selected = day.offset == widget.selectedOffset;
                final filled = selected && !week;
                final committed = day.offset == widget.committedOffset && widget.committedOffset != widget.selectedOffset;
                final top = day.isToday ? '今天' : _weekday(day.date);
                final v = day.value;
                final sub = day.isToday ? '进行中' : (v == null ? '—' : _num1(v));
                final deep = _c(_kLinePurpleDeep);
                final fg = filled ? deep : ink;
                final fgSoft = filled ? purple : mute;
                return LhPressScale(
                  scale: 0.93,
                  child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _tapDay(day.offset),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      // 2026-11-23 · 选中格不再用实心紫渐变：浅紫底 + 紫边 + 紫字。
                      color: filled
                          ? _c(LhColors.purpleSoft, role: DunesColorRole.surface)
                          : _c(Colors.white, role: DunesColorRole.surface),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? purple : line,
                        width: selected ? 1.2 : 1,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(top, textAlign: TextAlign.center, style: LhTypography.sans(context: context, size: 11, color: fgSoft)),
                            const SizedBox(height: 1),
                            Text(
                              '${day.date.day}',
                              textAlign: TextAlign.center,
                              style: LhTypography.number(context: context, size: 14, color: fg).copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 1),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                sub,
                                style: LhTypography.sans(context: context, size: 10, color: purple),
                              ),
                            ),
                          ],
                        ),
                        // 整页现在停在这天（单击预览了别的天时提示一下）。
                        if (committed)
                          Positioned(
                            top: -2,
                            right: 5,
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(color: purple, shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DashPainter old) => old.color != color;
}

TextPainter _tp(TextScaler scale, String text, double size, Color color, {FontWeight weight = FontWeight.w500}) =>
    TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: color, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      textScaler: scale,
      maxLines: 1,
    )..layout();

/// 分时图。横轴 0–24 点；纵轴自动取整（万），刻度在左边。当天、前一天都从 0 点 0 元起画。
class _MinutePainter extends CustomPainter {
  _MinutePainter({
    required this.day,
    required this.prev,
    required this.isToday,
    required this.nowMinute,
    required this.prevSame,
    required this.prevEndLabel,
    required this.progress,
    required this.fmtAxis,
    required this.fmtValue,
    required this.red,
    required this.prevColor,
    required this.mute,
    required this.grid,
    required this.future,
    required this.futureText,
    required this.halo,
    required this.textScale,
  });

  final List<_Pt> day;
  final List<_Pt> prev;
  final bool isToday;
  final int? nowMinute;
  final double? prevSame;
  final String? prevEndLabel;
  final double progress;
  final String Function(double) fmtAxis;
  final String Function(double) fmtValue;
  final Color red;
  final Color prevColor;
  final Color mute;
  final Color grid;
  final Color future;
  final Color futureText;
  final Color halo;
  final TextScaler textScale;

  static const double _l = 36;
  static const double _r = 8;
  static const double _t = 18;
  static const double _b = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final base = size.height - _b;
    double x(int minute) => _l + (w - _l - _r) * minute / 1440;

    var lo = 0.0, hi = 0.0;
    for (final p in [...day, ...prev]) {
      lo = math.min(lo, p.v);
      hi = math.max(hi, p.v);
    }
    final step = _nice((hi - lo) / 3);
    final top = math.max(step, (hi / step).ceil() * step);
    final bottom = (lo / step).floor() * step;
    final range = (top - bottom) <= 0 ? step : top - bottom;
    double y(double v) => _t + (top - v) / range * (base - _t);
    final zeroY = y(0);

    // 还没到的时段：浅底 +「尚未发生」
    final nm = nowMinute;
    if (isToday && nm != null && nm < 1440) {
      final nx = x(nm);
      canvas.drawRect(Rect.fromLTRB(nx, _t - 4, w - _r, base), Paint()..color = future);
      final ft = _tp(textScale, '尚未发生', 11, futureText);
      final cx = (nx + w - _r) / 2 + 10;
      if (w - _r - nx > ft.width + 16) {
        ft.paint(canvas, Offset(cx - ft.width / 2, _t + (base - _t) * 0.42));
      }
    }

    // 网格 + 左侧刻度
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var t = bottom; t <= top + step / 2; t += step) {
      final ty = y(t);
      canvas.drawLine(Offset(_l, ty), Offset(w - _r, ty), gp);
      final label = t.abs() < 1e-9 ? '0' : fmtAxis(t);
      final tp = _tp(textScale, label, 10, mute);
      tp.paint(canvas, Offset(_l - 6 - tp.width, ty - tp.height / 2));
    }

    // 横轴刻度
    for (final (h, label) in const [(0, '00:00'), (6, '06:00'), (12, '12:00'), (18, '18:00'), (24, '24:00')]) {
      final tp = _tp(textScale, label, 10, mute);
      final cx = x(h * 60);
      final lx = math.min(w - tp.width, math.max(0.0, cx - tp.width / 2));
      tp.paint(canvas, Offset(lx, size.height - tp.height));
    }

    List<Offset> pts(List<_Pt> ps) => [
      Offset(x(0), zeroY),
      for (final p in ps) Offset(x(p.minute), y(p.v)),
    ];

    // 前一天：虚线
    if (prev.isNotEmpty) {
      final path = _smooth(pts(prev));
      _dashed(
        canvas,
        path,
        Paint()
          ..color = prevColor.withAlpha(220)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
        4,
        4,
      );
      final label = prevEndLabel;
      if (label != null) {
        final end = Offset(x(prev.last.minute), y(prev.last.v));
        canvas.drawCircle(end, 2.8, Paint()..color = prevColor);
        final tp = _tp(textScale, label, 10, prevColor);
        tp.paint(canvas, Offset(math.max(_l, w - _r - tp.width), math.max(0.0, end.dy - tp.height - 5)));
      }
    }

    if (day.isEmpty) return;

    // 当天：渐隐面积 + 实线（从左往右描出来）
    final dp = pts(day);
    final line = _smooth(dp);
    final area = Path.from(line)
      ..lineTo(dp.last.dx, zeroY)
      ..lineTo(dp.first.dx, zeroY)
      ..close();
    final fade = ((progress - 0.15) / 0.85).clamp(0.0, 1.0);
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [red.withAlpha((56 * fade).round()), red.withAlpha(0)],
        ).createShader(Rect.fromLTRB(0, _t, w, zeroY)),
    );
    canvas.drawPath(
      _partial(line, progress),
      Paint()
        ..color = red
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (progress < 0.98) return;

    final last = day.last;
    final ex = x(last.minute);
    final ey = y(last.v);

    if (isToday) {
      // 现在：竖虚线到底
      _dashedLine(canvas, Offset(ex, ey), Offset(ex, zeroY), Paint()
        ..color = red.withAlpha(150)
        ..strokeWidth = 1, 3, 3);
      // 昨天同一时刻：紫点 + 数
      final ps = prevSame;
      if (ps != null) {
        final py = y(ps);
        canvas.drawCircle(Offset(ex, py), 3.5, Paint()..color = prevColor);
        final tp = _tp(textScale, fmtValue(ps), 10, prevColor);
        final lx = ex + 7 + tp.width > w - _r ? ex - 7 - tp.width : ex + 7;
        tp.paint(canvas, Offset(lx, py + 2));
      }
      // 现在：光晕 + 空心红点 + 红标签
      canvas.drawCircle(Offset(ex, ey), 9, Paint()..color = red.withAlpha(46));
      canvas.drawCircle(Offset(ex, ey), 4.5, Paint()..color = halo);
      canvas.drawCircle(
        Offset(ex, ey),
        4.5,
        Paint()
          ..color = red
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      final at = last.at.isEmpty ? _hhmm(last.minute) : last.at;
      final pill = _tp(textScale, '$at · ${fmtValue(last.v)}', 11, Colors.white, weight: FontWeight.w600);
      final pw = pill.width + 16;
      final ph = pill.height + 6;
      final px = math.min(w - _r - pw, math.max(_l, ex - pw / 2));
      var py0 = ey - ph - 10;
      if (py0 < 0) py0 = ey + 10;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(px, py0, pw, ph), Radius.circular(ph / 2)),
        Paint()..color = red,
      );
      pill.paint(canvas, Offset(px + 8, py0 + 3));
    } else {
      // 往前某一天：末端实心点 + 全天数
      canvas.drawCircle(Offset(ex, ey), 4, Paint()..color = red);
      final tp = _tp(textScale, fmtValue(last.v), 11, red, weight: FontWeight.w600);
      tp.paint(canvas, Offset(math.max(_l, ex - 6 - tp.width), math.max(0.0, ey - tp.height - 6)));
    }
  }

  @override
  bool shouldRepaint(covariant _MinutePainter old) =>
      old.progress != progress ||
      old.day != day ||
      old.prev != prev ||
      old.red != red ||
      old.prevSame != prevSame;
}

/// 近7天图的几何：画图和浮层共用，保证点和浮层对得上。
class _WeekGeom {
  _WeekGeom(this.size, this.values, {required this.avg, required this.prevSame}) {
    var lo = 0.0, hi = 0.0;
    final a = avg, ps = prevSame;
    for (final v in [...values.whereType<double>(), if (a != null) a, if (ps != null) ps]) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    step = _nice((hi - lo) / 4);
    top = math.max(step, (hi / step).ceil() * step);
    // 最高点上面要放「最高」标签：离顶太近就再抬一格。
    if (hi > 0 && (top - hi) / (top - math.min(0.0, lo)) < 0.08) top += step;
    bottom = (lo / step).floor() * step;
  }

  final Size size;
  final List<double?> values;
  final double? avg;
  final double? prevSame;
  late final double step;
  late double top;
  late final double bottom;

  static const double l = 36;
  static const double r = 10;
  static const double t = 30;
  static const double b = 24;

  int get n => values.length;
  double get stepX => (size.width - l - r) / n;
  double get base => size.height - b;
  double x(int i) => l + stepX * (i + 0.5);
  double y(double v) => t + (top - v) / ((top - bottom) <= 0 ? 1 : top - bottom) * (base - t);

  int? indexAt(double dx) {
    if (n == 0 || dx < l - 4) return null;
    return math.min(n - 1, math.max(0, ((dx - l) / stepX).floor()));
  }
}

/// 近7天：完整日平滑折线 + 面积，今天单独一列「进行中」，日均虚线、最高 / 最低标签。
class _WeekPainter extends CustomPainter {
  _WeekPainter({
    required this.geom,
    required this.days,
    required this.todayIndex,
    required this.selectedIndex,
    required this.maxIndex,
    required this.minIndex,
    required this.tipIndex,
    required this.progress,
    required this.isRate,
    required this.red,
    required this.redSoft,
    required this.purple,
    required this.purpleDeep,
    required this.purpleLight,
    required this.selFill,
    required this.ink2,
    required this.mute,
    required this.connector,
    required this.tick,
    required this.grid,
    required this.halo,
    required this.textScale,
  });

  final _WeekGeom geom;
  final List<LhIntradayDay> days;
  final int todayIndex;
  final int selectedIndex;
  final int? maxIndex;
  final int? minIndex;
  final int? tipIndex;
  final double progress;
  final bool isRate;
  final Color red;
  final Color redSoft;
  final Color purple;
  final Color purpleDeep;
  final Color purpleLight;
  final Color selFill;
  final Color ink2;
  final Color mute;
  final Color connector;
  final Color tick;
  final Color grid;
  final Color halo;
  final TextScaler textScale;

  String _short(double v) => isRate ? v.toStringAsFixed(1) : (v / 10000).toStringAsFixed(1);

  String _axis(double v) {
    if (v.abs() < 1e-9) return '0';
    if (isRate) return '${v.toStringAsFixed(0)}%';
    final wan = v / 10000;
    final whole = (wan - wan.roundToDouble()).abs() < 1e-6;
    return '${_lhWan(v, digits: whole ? 0 : 1)}万';
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = geom;
    final w = size.width;
    final base = g.base;
    final values = g.values;
    final sw = g.stepX;

    // 选中的那天（不是今天时）：淡紫底
    if (selectedIndex >= 0 && selectedIndex < values.length && selectedIndex != todayIndex) {
      final cx = g.x(selectedIndex);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(cx - sw / 2 + 3, _WeekGeom.t - 16, cx + sw / 2 - 3, base), const Radius.circular(10)),
        Paint()..color = selFill,
      );
    }
    // 今天那一列：浅红底 +「进行中」
    if (todayIndex >= 0) {
      final cx = g.x(todayIndex);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(cx - sw / 2 + 3, _WeekGeom.t - 16, cx + sw / 2 - 3, base), const Radius.circular(10)),
        Paint()..color = redSoft,
      );
      final tp = _tp(textScale, '进行中', 10, red, weight: FontWeight.w600);
      tp.paint(canvas, Offset(cx - tp.width / 2, _WeekGeom.t - 13));
    }

    // 网格 + 左侧刻度（离日均签太近的刻度不写，免得叠在一起）
    final avg = g.avg;
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var v = g.bottom; v <= g.top + g.step / 2; v += g.step) {
      final ty = g.y(v);
      canvas.drawLine(Offset(_WeekGeom.l, ty), Offset(w - _WeekGeom.r, ty), gp);
      if (avg != null && (ty - g.y(avg)).abs() <= 11) continue;
      final tp = _tp(textScale, _axis(v), 10, mute);
      tp.paint(canvas, Offset(_WeekGeom.l - 6 - tp.width, ty - tp.height / 2));
    }

    // 横轴日期
    for (var i = 0; i < days.length; i++) {
      final today = i == todayIndex;
      final tp = _tp(
        textScale,
        today ? '今天' : _md(days[i].date),
        10.5,
        today ? red : mute,
        weight: today ? FontWeight.w600 : FontWeight.w400,
      );
      tp.paint(canvas, Offset(g.x(i) - tp.width / 2, size.height - tp.height - 2));
    }

    // 日均虚线 + 纵轴上的紫签
    if (avg != null) {
      final ay = g.y(avg);
      final endX = todayIndex >= 0 ? g.x(todayIndex) - sw / 2 : w - _WeekGeom.r;
      _dashedLine(canvas, Offset(_WeekGeom.l, ay), Offset(endX, ay), Paint()
        ..color = purple.withAlpha(140)
        ..strokeWidth = 1, 5, 4);
      final tp = _tp(textScale, '均${_short(avg)}', 9, Colors.white, weight: FontWeight.w600);
      final tw = math.max(_WeekGeom.l - 2, tp.width + 8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, ay - 8, tw, 16), const Radius.circular(8)),
        Paint()..color = purple,
      );
      tp.paint(canvas, Offset((tw - tp.width) / 2, ay - tp.height / 2));
    }

    // 选中浮层的竖线
    final tip = tipIndex;
    if (tip != null && tip < values.length) {
      canvas.drawLine(
        Offset(g.x(tip), _WeekGeom.t - 16),
        Offset(g.x(tip), base),
        Paint()
          ..color = purple.withAlpha(64)
          ..strokeWidth = 1,
      );
    }

    // 完整日：按连续段画平滑线 + 面积
    final runs = <List<int>>[];
    var cur = <int>[];
    for (var i = 0; i < values.length; i++) {
      if (i == todayIndex || values[i] == null) {
        if (cur.isNotEmpty) runs.add(cur);
        cur = <int>[];
        continue;
      }
      cur.add(i);
    }
    if (cur.isNotEmpty) runs.add(cur);
    final zeroY = g.y(math.max(0.0, g.bottom));
    final fade = ((progress - 0.1) / 0.9).clamp(0.0, 1.0);
    for (final run in runs) {
      final pts = [for (final i in run) Offset(g.x(i), g.y(values[i]!))];
      if (pts.length >= 2) {
        final line = _smooth(pts);
        final area = Path.from(line)
          ..lineTo(pts.last.dx, zeroY)
          ..lineTo(pts.first.dx, zeroY)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.7, 1],
              colors: [
                purple.withAlpha((72 * fade).round()),
                purple.withAlpha((13 * fade).round()),
                purple.withAlpha(0),
              ],
            ).createShader(Rect.fromLTRB(0, _WeekGeom.t, w, zeroY)),
        );
        canvas.drawPath(
          _partial(line, progress),
          Paint()
            ..shader = LinearGradient(colors: [purpleLight, purpleDeep])
                .createShader(Rect.fromLTRB(pts.first.dx, 0, pts.last.dx + 1, 1))
            ..strokeWidth = 2.6
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    final labelAlpha = ((progress - 0.35) / 0.65).clamp(0.0, 1.0);
    int a(int max) => (max * labelAlpha).round();

    // 接到今天：灰色细虚线（不和完整日连成一条往下掉的线）
    final tv = todayIndex >= 0 ? values[todayIndex] : null;
    if (tv != null && todayIndex > 0 && values[todayIndex - 1] != null) {
      _dashedLine(
        canvas,
        Offset(g.x(todayIndex - 1), g.y(values[todayIndex - 1]!)),
        Offset(g.x(todayIndex), g.y(tv)),
        Paint()
          ..color = connector.withAlpha(a(255))
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
        2,
        4,
      );
    }

    // 完整日的点 + 数
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null || i == todayIndex) continue;
      final c = Offset(g.x(i), g.y(v));
      final isMax = i == maxIndex;
      final isMin = i == minIndex && !isMax;
      if (isMax) {
        canvas.drawCircle(c, 5, Paint()..color = purpleDeep.withAlpha(a(255)));
        final tp = _tp(textScale, '最高 ${_short(v)}', 10.5, Colors.white.withAlpha(a(255)), weight: FontWeight.w600);
        final pw = tp.width + 14;
        final px = math.min(w - pw, math.max(0.0, c.dx - pw / 2));
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(px, c.dy - 27, pw, 18), const Radius.circular(9)),
          Paint()..color = purpleDeep.withAlpha(a(255)),
        );
        tp.paint(canvas, Offset(px + 7, c.dy - 27 + (18 - tp.height) / 2));
      } else {
        canvas.drawCircle(c, 3.6, Paint()..color = halo.withAlpha(a(255)));
        canvas.drawCircle(
          c,
          3.6,
          Paint()
            ..color = purple.withAlpha(a(255))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        final tp = _tp(textScale, _short(v), 10, (isMin ? mute : ink2).withAlpha(a(255)));
        tp.paint(canvas, Offset(c.dx - tp.width / 2, isMin ? c.dy + 6 : c.dy - 9 - tp.height));
      }
    }

    // 今天：昨日同时短刻度 + 空心红点 + 数
    if (tv != null) {
      final cx = g.x(todayIndex);
      final ps = g.prevSame;
      if (ps != null) {
        final py = g.y(ps);
        _dashedLine(canvas, Offset(cx - sw / 2 + 7, py), Offset(cx + sw / 2 - 7, py), Paint()
          ..color = tick.withAlpha(a(255))
          ..strokeWidth = 1.6, 3, 2);
        final tp = _tp(textScale, '昨 ${_short(ps)}', 9, mute.withAlpha(a(255)));
        tp.paint(canvas, Offset(cx - tp.width / 2, py + 4));
      }
      final c = Offset(cx, g.y(tv));
      canvas.drawCircle(c, 9, Paint()..color = red.withAlpha(a(46)));
      canvas.drawCircle(c, 4.5, Paint()..color = halo.withAlpha(a(255)));
      canvas.drawCircle(
        c,
        4.5,
        Paint()
          ..color = red.withAlpha(a(255))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      final tp = _tp(textScale, _short(tv), 11.5, red.withAlpha(a(255)), weight: FontWeight.w700);
      tp.paint(canvas, Offset(cx - tp.width / 2, c.dy - 10 - tp.height));
    }
  }

  @override
  bool shouldRepaint(covariant _WeekPainter old) =>
      old.progress != progress ||
      old.tipIndex != tipIndex ||
      old.selectedIndex != selectedIndex ||
      old.geom.values != geom.values ||
      old.geom.size != geom.size ||
      old.red != red;
}
