// 月末预测 v4：分离月初结算 + 动态日模型 + 严格时间回测。
// 详见 docs/lighthouse-monthly-forecast.md；纯函数，不改变实际经营指标。
// 正金额：零值门控 + Gamma / log 链接；有符号金额：Gaussian。
// 联合估计动态水平、星期、月末效应；经验贝叶斯 + Laplace 近似。
// 主金额、10/90 分位、超上月概率由同一预测分布产生。

import 'dart:math' as math;
import 'package:flutter/foundation.dart' show immutable;
import 'lighthouse_dynamic_forecast.dart';
import 'lighthouse_forecast.dart';

@immutable
class LighthouseModelForecast {
  const LighthouseModelForecast({
    required this.forecast,
    required this.lo,
    required this.hi,
    required this.actual,
    required this.cutoffDay,
    required this.totalDays,
    required this.linear,
    required this.modelMape,
    required this.linearMape,
    required this.backtestMonths,
    required this.usedModel,
    this.beatPrevProb,
    this.prevMonthTotal,
    required this.month,
    required this.dynamic,
    required this.dynamicMape,
    required this.signed,
    required this.cumulativeMean,
    required this.cumulativeLo,
    required this.cumulativeHi,
    required this.paths,
  });
  final double forecast, lo, hi, actual, linear, modelMape, linearMape;
  final int cutoffDay, totalDays, backtestMonths;
  final bool usedModel, signed;
  final double? beatPrevProb, prevMonthTotal;
  final DateTime month;
  final LighthouseDynamicForecast dynamic;
  final double? dynamicMape;
  final List<double> cumulativeMean, cumulativeLo, cumulativeHi;
  final List<List<double>> paths;
  // 尚无独立覆盖率审计，不能只因为达到 6 折就自动宣布“正式模型”。
  bool get trial => true;
  String get modelLabel => usedModel ? '动态日模型' : '原算法';
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);
int _daysIn(int y, int m) => DateTime(y, m + 1, 0).day;

double _sumRange(Map<DateTime, double> d, int y, int m, int from, int to) {
  var s = 0.0;
  for (var i = from; i <= to; i++) {
    s += d[DateTime(y, m, i)] ?? 0.0;
  }
  return s;
}

/// 在「y 年 m 月第 c 天收盘」这个时点，只看此前数据给出三个模型的预测。
typedef _Pred = ({
  double actual,
  double linear,
  double? pace,
  double? daily,
  double? share,
  List<double> weekday,
  double monthEnd,
  double level,
});

_Pred _predictAt(
  Map<DateTime, double> d,
  DateTime earliest,
  int y,
  int m,
  int c,
) {
  final total = _daysIn(y, m);
  final actual = _sumRange(d, y, m, 1, c);
  final linear = actual / c * total;

  // ── M1 · 月内节奏曲线 ─────────────────────────────────────────────
  double? pace;
  var wSum = 0.0;
  var sSum = 0.0;
  var used = 0;
  for (var k = 1; k <= 6; k++) {
    final ms = DateTime(y, m - k, 1);
    if (ms.isBefore(earliest)) break;
    if (!_complete(d, ms.year, ms.month, _daysIn(ms.year, ms.month))) continue;
    final dk = _daysIn(ms.year, ms.month);
    final tk = _sumRange(d, ms.year, ms.month, 1, dk);
    if (tk.abs() < 1e-6) continue;
    // 同号才有「完成几成」可言（利润一会儿赚一会儿亏时这条不成立）。
    if (actual.abs() > 1e-6 && (tk > 0) != (actual > 0)) continue;
    final ck = (c * dk / total).round().clamp(1, dk);
    final share = _sumRange(d, ms.year, ms.month, 1, ck) / tk;
    if (!share.isFinite) continue;
    final w = math.pow(0.75, k - 1).toDouble();
    sSum += share * w;
    wSum += w;
    used++;
  }
  if (used >= 2 && wSum > 0) {
    final share = sSum / wSum;
    if (share > 0.05 && share <= 1.2) pace = actual / math.min(share, 1.0);
  }

  // ── M2 · 剩余天数逐日加总 ─────────────────────────────────────────
  double? daily;
  var wfOut = List<double>.filled(7, 1.0);
  var meOut = 1.0;
  var levelOut = 0.0;
  final hist = <DateTime>[
    for (var i = 55; i >= 0; i--) DateTime(y, m, c - i),
  ].where((t) => !t.isBefore(earliest)).toList();
  if (hist.length >= 28 && hist.every(d.containsKey)) {
    final absAll = <double>[for (final t in hist) (d[t] ?? 0).abs()];
    final meanAbs = absAll.reduce((a, b) => a + b) / absAll.length;
    final wf = List<double>.filled(8, 1.0);
    if (meanAbs > 1e-9) {
      for (var w = 1; w <= 7; w++) {
        final vs = [
          for (final t in hist)
            if (t.weekday == w) (d[t] ?? 0).abs(),
        ];
        if (vs.isEmpty) continue;
        final mw = vs.reduce((a, b) => a + b) / vs.length;
        wf[w] = (mw / meanAbs).clamp(0.3, 3.0).toDouble();
      }
    }
    // 水平：近 28 天去星期效应后的指数加权均值。
    var lw = 0.0;
    var lv = 0.0;
    final recent = hist.sublist(hist.length - 28);
    for (var i = 0; i < recent.length; i++) {
      final t = recent[i];
      final age = recent.length - 1 - i;
      final w = math.pow(0.5, age / 7).toDouble();
      lv += (d[t] ?? 0) / wf[t.weekday] * w;
      lw += w;
    }
    final level = lw > 0 ? lv / lw : 0.0;
    // 月末三天系数：前几个整月里末三天日均 ÷ 全月日均。
    var meSum = 0.0;
    var meN = 0;
    for (var k = 1; k <= 6; k++) {
      final ms = DateTime(y, m - k, 1);
      if (ms.isBefore(earliest)) break;
      if (!_complete(d, ms.year, ms.month, _daysIn(ms.year, ms.month))) {
        continue;
      }
      final dk = _daysIn(ms.year, ms.month);
      final all = _sumRange(d, ms.year, ms.month, 1, dk) / dk;
      if (all.abs() < 1e-9) continue;
      final tail = _sumRange(d, ms.year, ms.month, dk - 2, dk) / 3;
      final r = tail / all;
      if (!r.isFinite || r <= 0) continue;
      meSum += r;
      meN++;
    }
    final me = meN == 0 ? 1.0 : (meSum / meN).clamp(0.5, 3.0).toDouble();
    var rest = 0.0;
    for (var i = c + 1; i <= total; i++) {
      final t = DateTime(y, m, i);
      rest += level * wf[t.weekday] * (i > total - 3 ? me : 1.0);
    }
    daily = actual + rest;
    wfOut = wf.sublist(1);
    meOut = me;
    levelOut = level;
  }
  return (
    actual: actual,
    linear: linear,
    pace: pace,
    daily: daily,
    share: pace == null || pace.abs() < 1e-12 ? null : actual / pace,
    weekday: wfOut,
    monthEnd: meOut,
    level: levelOut,
  );
}

bool _complete(Map<DateTime, double> d, int y, int m, int to) =>
    [for (var i = 1; i <= to; i++) DateTime(y, m, i)].every(d.containsKey);

Map<DateTime, double> _observed(Map<DateTime, double> daily, DateTime today) {
  final latest = _day(today).subtract(const Duration(days: 1));
  return {
    for (final e in daily.entries)
      if (e.value.isFinite && !_day(e.key).isAfter(latest))
        _day(e.key): e.value,
  };
}

@immutable
class LighthouseBacktestRow {
  const LighthouseBacktestRow({
    required this.month,
    required this.asOfDay,
    required this.truth,
    required this.linear,
    this.pace,
    this.daily,
    this.ensemble,
    this.dynamic,
    this.weightPace = 0,
    this.weightDaily = 0,
  });
  final DateTime month;
  final int asOfDay;
  final double truth, linear;
  final double? pace, daily, ensemble, dynamic;

  /// 仅由此月之前的已完成回测折计算；没有历史依据时不构造组合。
  final double weightPace, weightDaily;
  static double? err(double? f, double truth) =>
      f == null || truth.abs() < 1e-9 ? null : (f - truth) / truth.abs();
}

@immutable
class LighthouseCheckpointRow {
  const LighthouseCheckpointRow({
    required this.day,
    required this.months,
    this.linear,
    this.pace,
    this.daily,
    this.ensemble,
    this.dynamic,
  });
  final int day, months;
  final double? linear, pace, daily, ensemble, dynamic;
}

/// WAPE = Σ|预测−真实| / Σ|真实|；适用于存在零月、负月的金额。
/// 只有所有被比较方法均可计算的月份才用于该项评分。
double? _wape(
  List<LighthouseBacktestRow> rows,
  double? Function(LighthouseBacktestRow) prediction,
) {
  if (rows.length < 2 || rows.any((r) => prediction(r) == null)) return null;
  var denominator = 0.0, numerator = 0.0;
  for (final r in rows) {
    denominator += r.truth.abs();
    numerator += (prediction(r)! - r.truth).abs();
  }
  return denominator > 1e-9 ? numerator / denominator : null;
}

({double pace, double daily}) _weights(List<LighthouseBacktestRow> rows) {
  final common = rows.where((r) => r.pace != null && r.daily != null).toList();
  final p = _wape(common, (r) => r.pace);
  final d = _wape(common, (r) => r.daily);
  if (p == null || d == null) return (pace: 0.0, daily: 0.0);
  final wp = 1 / (p + 0.01), wd = 1 / (d + 0.01);
  return (pace: wp / (wp + wd), daily: wd / (wp + wd));
}

List<LighthouseBacktestRow> _backtestAt(
  Map<DateTime, double> d,
  DateTime month,
  int c,
  bool signed,
) {
  final earliest = d.keys.reduce((a, b) => a.isBefore(b) ? a : b);
  final total = _daysIn(month.year, month.month);
  final rows = <LighthouseBacktestRow>[];
  // 从早到晚：组合的权重只读以前的折，绝不读当前被打分月份。
  for (var k = 6; k >= 1; k--) {
    final ms = DateTime(month.year, month.month - k, 1);
    final days = _daysIn(ms.year, ms.month);
    if (!_complete(d, ms.year, ms.month, days)) continue;
    // 最后一周按剩余天数对齐，保证比较的是同样的月底窗口，而非不同尾日。
    final ck =
        (total - c <= 7 ? days - (total - c) : (c * days / total).round())
            .clamp(2, days - 1);
    final dm = lighthouseDynamicForecast(
      daily: d,
      cutoff: DateTime(ms.year, ms.month, ck),
      signed: signed,
      simulations: 0,
    );
    if (dm == null) continue;
    final p = _predictAt(d, earliest, ms.year, ms.month, ck);
    final w = _weights(rows);
    final ens = p.pace != null && p.daily != null && w.pace + w.daily > 0
        ? p.pace! * w.pace + p.daily! * w.daily
        : null;
    rows.add(
      LighthouseBacktestRow(
        month: ms,
        asOfDay: ck,
        truth: _sumRange(d, ms.year, ms.month, 1, days),
        linear: p.linear,
        pace: p.pace,
        daily: p.daily,
        ensemble: ens,
        dynamic: dm.forecast,
        weightPace: w.pace,
        weightDaily: w.daily,
      ),
    );
  }
  return rows;
}

/// 最新可用日期不晚于昨天。当前月有缺口则暂停模型，不能把缺失当 0。
/// 没有后端完整性水位时，“可用”不等于数据已完成业务对账。
LighthouseModelForecast? lighthouseModelForecast({
  required Map<DateTime, double> daily,
  required DateTime today,
  bool signed = false,
}) {
  final d = _observed(daily, today);
  final current = d.keys.where(
    (t) => t.year == today.year && t.month == today.month,
  );
  if (current.isEmpty) return null;
  final cutoff = current.reduce((a, b) => a.isAfter(b) ? a : b);
  final c = cutoff.day, total = _daysIn(today.year, today.month);
  if (c < 2 || c >= total || !_complete(d, today.year, today.month, c)) {
    return null;
  }
  var completeMonths = 0;
  for (var k = 1; k <= 6; k++) {
    final ms = DateTime(today.year, today.month - k, 1);
    if (_complete(d, ms.year, ms.month, _daysIn(ms.year, ms.month))) {
      completeMonths++;
    }
  }
  if (completeMonths < 2) return null;
  // 分布口径只由当前可见数据决定，未来负金额不能反向影响历史拟合。
  final isSigned = signed || d.values.any((v) => v < 0);
  final dm = lighthouseDynamicForecast(
    daily: d,
    cutoff: cutoff,
    signed: isSigned,
  );
  if (dm == null) return null;
  final month = DateTime(today.year, today.month, 1);
  final rows = _backtestAt(d, month, c, signed);
  final ml = _wape(rows, (r) => r.linear);
  final md = _wape(rows, (r) => r.dynamic);
  final linear = dm.actual / c * total;
  final use = ml != null && md != null && md <= ml;
  final target = use ? dm.forecast : linear;
  // 主预测与分布保持一致：原算法保底时，正金额只缩放“剩余部分”；
  // 有符号金额按剩余进度平移。不会把未来利润强行夹到已发生利润以上。
  final remaining = dm.forecast - dm.actual;
  double align(double v, int day) {
    if (day <= c) return v;
    if (!isSigned && remaining > 1e-9) {
      return dm.actual + (v - dm.actual) * (target - dm.actual) / remaining;
    }
    return v + (target - dm.forecast) * (day - c) / (total - c);
  }

  final mean = [
    for (var i = 0; i < total; i++) align(dm.cumulativeMean[i], i + 1),
  ];
  final paths = [
    for (final path in dm.paths)
      [for (var i = 0; i < total; i++) align(path[i], i + 1)],
  ];
  final lo = [
    for (var i = 0; i < total; i++)
      lighthouseForecastQuantile([for (final path in paths) path[i]], 0.1),
  ];
  final hi = [
    for (var i = 0; i < total; i++)
      lighthouseForecastQuantile([for (final path in paths) path[i]], 0.9),
  ];
  final pm = DateTime(today.year, today.month - 1, 1);
  final previous = _complete(d, pm.year, pm.month, _daysIn(pm.year, pm.month))
      ? _sumRange(d, pm.year, pm.month, 1, _daysIn(pm.year, pm.month))
      : null;
  final beat = previous == null
      ? null
      : paths.where((p) => p.last > previous).length / paths.length;
  return LighthouseModelForecast(
    forecast: target,
    lo: lo.last,
    hi: hi.last,
    actual: dm.actual,
    cutoffDay: c,
    totalDays: total,
    linear: linear,
    modelMape: (use ? md : ml) ?? double.nan,
    linearMape: ml ?? double.nan,
    backtestMonths: rows.length,
    usedModel: use,
    beatPrevProb: beat,
    prevMonthTotal: previous,
    month: month,
    dynamic: dm,
    dynamicMape: md,
    signed: isSigned,
    cumulativeMean: mean,
    cumulativeLo: lo,
    cumulativeHi: hi,
    paths: paths,
  );
}

/// 实线可以是实时累计；预测与概率仍保持同一个 T+1 截止口径，不单独夹点值。
LighthousePaceForecast lighthousePaceFromModel(
  LighthouseModelForecast mf, {
  required double shownActual,
}) => LighthousePaceForecast(
  actual: shownActual,
  forecast: mf.forecast,
  elapsedDays: mf.cutoffDay,
  totalDays: mf.totalDays,
  lo: mf.lo,
  hi: mf.hi,
  beatPrevProb: mf.beatPrevProb,
  modelMape: mf.modelMape,
  linearMape: mf.linearMape,
  byModel: mf.usedModel,
  modelLabel: mf.modelLabel,
  backtestMonths: mf.backtestMonths,
  trial: mf.trial,
);

@immutable
class LighthouseForecastReport {
  const LighthouseForecastReport({
    required this.summary,
    required this.pace,
    required this.daily,
    required this.ensemble,
    required this.weightPace,
    required this.weightDaily,
    required this.mapeLinear,
    required this.mapePace,
    required this.mapeDaily,
    required this.mapeEnsemble,
    required this.rows,
    required this.checkpoints,
    required this.weekdayFactors,
    required this.monthEndFactor,
    required this.dailyLevel,
    required this.paceShare,
    required this.cumActual,
    required this.typicalShare,
    required this.prevCum,
  });
  final LighthouseModelForecast summary;
  final double? pace,
      daily,
      ensemble,
      mapeLinear,
      mapePace,
      mapeDaily,
      mapeEnsemble;
  final double weightPace, weightDaily, monthEndFactor, dailyLevel;
  final double? paceShare;
  final List<LighthouseBacktestRow> rows;
  final List<LighthouseCheckpointRow> checkpoints;
  final List<double> weekdayFactors, cumActual;
  final List<double>? typicalShare, prevCum;
}

LighthouseForecastReport? lighthouseForecastReport({
  required Map<DateTime, double> daily,
  required DateTime today,
  bool signed = false,
}) {
  final summary = lighthouseModelForecast(
    daily: daily,
    today: today,
    signed: signed,
  );
  if (summary == null) return null;
  final d = _observed(daily, today);
  final earliest = d.keys.reduce((a, b) => a.isBefore(b) ? a : b);
  final m = summary.month, c = summary.cutoffDay, total = summary.totalDays;
  final now = _predictAt(d, earliest, m.year, m.month, c);
  final rows = _backtestAt(d, m, c, signed);
  final w = _weights(rows);
  final common = rows.where((r) => r.pace != null && r.daily != null).toList();
  final ensCommon = rows.where((r) => r.ensemble != null).toList();
  final checkpoints = [
    for (final day in {
      5,
      10,
      15,
      20,
      25,
      total - 3,
      total - 1,
    }.toList()..sort())
      () {
        final b = _backtestAt(d, m, day, signed);
        return LighthouseCheckpointRow(
          day: day,
          months: b.length,
          linear: _wape(b, (r) => r.linear),
          dynamic: _wape(b, (r) => r.dynamic),
        );
      }(),
  ];
  final pm = DateTime(m.year, m.month - 1, 1);
  List<double>? previous;
  if (summary.prevMonthTotal != null) {
    final days = _daysIn(pm.year, pm.month);
    previous = [
      for (var j = 1; j <= total; j++)
        _sumRange(
          d,
          pm.year,
          pm.month,
          1,
          (j * days / total).round().clamp(1, days),
        ),
    ];
  }
  return LighthouseForecastReport(
    summary: summary,
    pace: now.pace,
    daily: now.daily,
    ensemble: now.pace != null && now.daily != null && w.pace + w.daily > 0
        ? now.pace! * w.pace + now.daily! * w.daily
        : null,
    weightPace: w.pace,
    weightDaily: w.daily,
    mapeLinear: summary.linearMape.isFinite ? summary.linearMape : null,
    mapePace: _wape(common, (r) => r.pace),
    mapeDaily: _wape(common, (r) => r.daily),
    mapeEnsemble: _wape(ensCommon, (r) => r.ensemble),
    rows: rows.reversed.toList(),
    checkpoints: checkpoints,
    weekdayFactors: summary.dynamic.weekdayFactors,
    monthEndFactor: summary.dynamic.monthEndFactor,
    dailyLevel: summary.dynamic.dailyLevel,
    paceShare: now.share,
    cumActual: summary.cumulativeMean.take(c).toList(),
    typicalShare: null,
    prevCum: previous,
  );
}
