// ═════════════════════════════════════════════════════════════════════════════
// 月末预测 v2 · 数学模型（试行，2026-09）
//
//   v1（lighthouse_forecast.dart）是线性日均外推：已发生 ÷ 已过天数 × 当月天数，
//   等于假设每天做的量一样多。v2 用每天的数据建两个模型，按历史回测误差加权：
//
//   M1 · 月内节奏曲线
//        过去 6 个整月里「到第 d 天通常已完成全月的几成」，越近的月权重越大；
//        预测 = 已发生 ÷ 第 d 天的典型完成比例。月末冲量、周末偏低自动吃进去。
//
//   M2 · 剩余天数逐日加总
//        每天水平 = 近 28 天去掉星期效应后的指数加权均值（半衰期 7 天），
//        剩下每一天 = 水平 × 星期几系数 × 月末三天系数；预测 = 已发生 + Σ剩余。
//        月中业务突然变好 / 变差，它比 M1 反应快。
//
//   回测：把过去每个整月都「退回到同一天」，只用那一天之前的数据让 M0/M1/M2
//        各预测一次，再和那个月的真实全月比。误差小的模型权重大；组合模型
//        回测反而不如线性时，诚实地退回线性。
//   区间：组合模型回测里「真实 ÷ 预测」的 10% / 90% 分位 × 本次预测 = 80% 区间。
//   概率：同一组比值里，有几成会让本月超过上月全月。
//
//   截止日：日数据按 T+1 口径只用到昨天，今天不算（22 号看 = 截至 21 号）。
//   全部是纯函数，便于单测，日后可原样搬到 lighthouse-go。
// ═════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

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
  });

  /// 模型预测的月末值。
  final double forecast;

  /// 80% 区间。
  final double lo;
  final double hi;

  /// 截至 [cutoffDay] 的日数据累计（模型自己用的已发生）。
  final double actual;
  final int cutoffDay;
  final int totalDays;

  /// 同一截止日的线性外推（对照用）。
  final double linear;

  /// 回测平均绝对误差率（0.021 = 2.1%）。
  final double modelMape;
  final double linearMape;
  final int backtestMonths;

  /// false = 组合模型回测不如线性，已退回线性。
  final bool usedModel;

  /// 本月超过上月全月的概率 0~1；没有上月数据时为 null。
  final double? beatPrevProb;
  final double? prevMonthTotal;
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
    final dk = _daysIn(ms.year, ms.month);
    final tk = _sumRange(d, ms.year, ms.month, 1, dk);
    if (tk.abs() < 1e-6) continue;
    // 同号才有「完成几成」可言（毛利一会儿赚一会儿亏时这条不成立）。
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
  if (hist.length >= 28) {
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

double _quantile(List<double> xs, double q) {
  final s = [...xs]..sort();
  if (s.isEmpty) return 1;
  final pos = (s.length - 1) * q;
  final lo = pos.floor();
  final hi = pos.ceil();
  return s[lo] + (s[hi] - s[lo]) * (pos - lo);
}

/// 用日数据给出本月月末预测。数据不够（历史不足 2 个整月、本月不足 2 天）返回 null。
///
/// [daily]：日期 → 当天金额，至少覆盖本月 1 号之前约 6 个月；缺的天按 0。
/// [today]：北京时间今天。截止日 = 昨天。
LighthouseModelForecast? lighthouseModelForecast({
  required Map<DateTime, double> daily,
  required DateTime today,
}) {
  if (daily.isEmpty) return null;
  final d = <DateTime, double>{
    for (final e in daily.entries)
      if (e.value.isFinite) _day(e.key): e.value,
  };
  final earliest = d.keys.reduce((a, b) => a.isBefore(b) ? a : b);
  final t = _day(today);
  final y = t.year;
  final m = t.month;
  final total = _daysIn(y, m);
  final c = t.day - 1; // T+1：只用到昨天
  if (c < 2 || c >= total) return null;

  final now = _predictAt(d, earliest, y, m, c);

  // ── 回测：过去每个整月退回到同一天 ─────────────────────────────────
  final errLin = <double>[];
  final errPace = <double>[];
  final errDaily = <double>[];
  final bt = <({double truth, double? pace, double? daily, double linear})>[];
  for (var k = 1; k <= 6; k++) {
    final ms = DateTime(y, m - k, 1);
    if (ms.isBefore(earliest)) break;
    final dk = _daysIn(ms.year, ms.month);
    final truth = _sumRange(d, ms.year, ms.month, 1, dk);
    if (truth.abs() < 1e-6) continue;
    final ck = (c * dk / total).round().clamp(2, dk - 1);
    final p = _predictAt(d, earliest, ms.year, ms.month, ck);
    double err(double f) => ((f - truth) / truth).abs();
    errLin.add(err(p.linear));
    if (p.pace != null) errPace.add(err(p.pace!));
    if (p.daily != null) errDaily.add(err(p.daily!));
    bt.add((truth: truth, pace: p.pace, daily: p.daily, linear: p.linear));
  }
  double mean(List<double> xs) =>
      xs.isEmpty ? double.nan : xs.reduce((a, b) => a + b) / xs.length;
  final mLin = mean(errLin);
  final mPace = mean(errPace);
  final mDaily = mean(errDaily);

  // ── 组合：误差倒数加权；只用「现在算得出、回测至少 2 个月」的模型 ─────
  double combine(double? pace, double? dly) {
    var w = 0.0;
    var v = 0.0;
    if (pace != null && errPace.length >= 2) {
      final wi = 1 / (mPace + 0.01);
      w += wi;
      v += pace * wi;
    }
    if (dly != null && errDaily.length >= 2) {
      final wi = 1 / (mDaily + 0.01);
      w += wi;
      v += dly * wi;
    }
    return w > 0 ? v / w : double.nan;
  }

  final ratios = <double>[];
  final errEns = <double>[];
  for (final b in bt) {
    final f = combine(b.pace, b.daily);
    if (!f.isFinite || f.abs() < 1e-9) continue;
    ratios.add(b.truth / f);
    errEns.add(((f - b.truth) / b.truth).abs());
  }
  final mEns = mean(errEns);
  var forecast = combine(now.pace, now.daily);
  var usedModel = forecast.isFinite && errEns.length >= 2;
  if (usedModel && errLin.isNotEmpty && mEns > mLin) usedModel = false;
  if (!usedModel) {
    forecast = now.linear;
    ratios
      ..clear()
      ..addAll([
        for (final b in bt)
          if (b.linear.abs() > 1e-9) b.truth / b.linear,
      ]);
  }
  if (!forecast.isFinite) return null;

  // ── 80% 区间 + 超上月概率 ──────────────────────────────────────────
  final spread = usedModel ? mEns : mLin;
  double lo;
  double hi;
  if (ratios.length >= 3) {
    final a = forecast * _quantile(ratios, 0.1);
    final b = forecast * _quantile(ratios, 0.9);
    lo = math.min(a, b);
    hi = math.max(a, b);
  } else {
    final w = forecast.abs() * (spread.isFinite ? spread : 0.1);
    lo = forecast - w;
    hi = forecast + w;
  }
  // 区间至少要包住预测值本身，且不窄于回测平均误差的一半。
  final minHalf = forecast.abs() * (spread.isFinite ? spread / 2 : 0.03);
  lo = math.min(lo, forecast - minHalf);
  hi = math.max(hi, forecast + minHalf);

  final pm = DateTime(y, m - 1, 1);
  double? prev;
  double? beat;
  if (!pm.isBefore(earliest)) {
    prev = _sumRange(d, pm.year, pm.month, 1, _daysIn(pm.year, pm.month));
    if (ratios.isNotEmpty) {
      final hit = ratios.where((r) => forecast * r > prev!).length;
      beat = (hit + 0.5) / (ratios.length + 1);
    }
  }

  return LighthouseModelForecast(
    forecast: forecast,
    lo: lo,
    hi: hi,
    actual: now.actual,
    cutoffDay: c,
    totalDays: total,
    linear: now.linear,
    modelMape: usedModel ? mEns : mLin,
    linearMape: mLin,
    backtestMonths: bt.length,
    usedModel: usedModel,
    beatPrevProb: beat,
    prevMonthTotal: prev,
  );
}

/// 把模型结果套进图上用的 [LighthousePaceForecast]。
/// [shownActual] 是图上实线末端的值（月度序列的本月），与模型的日累计同源但可能
/// 多含今天的部分数据；预测值不低于它。
LighthousePaceForecast lighthousePaceFromModel(
  LighthouseModelForecast mf, {
  required double shownActual,
}) {
  final up = mf.forecast >= 0;
  final fc = up
      ? math.max(mf.forecast, shownActual)
      : math.min(mf.forecast, shownActual);
  return LighthousePaceForecast(
    actual: shownActual,
    forecast: fc,
    elapsedDays: mf.cutoffDay,
    totalDays: mf.totalDays,
    lo: math.min(mf.lo, fc),
    hi: math.max(mf.hi, fc),
    beatPrevProb: mf.beatPrevProb,
    modelMape: mf.modelMape,
    linearMape: mf.linearMape,
    byModel: mf.usedModel,
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// 量化报告：把上面的预测摊开 —— 各模型本月怎么说、回测每个月准不准、
// 月里不同时点的准度、模型学到的参数，以及累计走势图要用的曲线。
// ═════════════════════════════════════════════════════════════════════════════

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
  });

  /// 被回测的那个整月（1 号）。
  final DateTime month;

  /// 退回到的那一天（与本月截止日按天数比例对齐）。
  final int asOfDay;
  final double truth;
  final double linear;
  final double? pace;
  final double? daily;
  final double? ensemble;

  static double? err(double? f, double truth) =>
      f == null || truth.abs() < 1e-9 ? null : (f - truth) / truth;
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
  });

  final int day;
  final int months;

  /// 平均绝对误差率（0.021 = 2.1%）。
  final double? linear;
  final double? pace;
  final double? daily;
  final double? ensemble;
}

@immutable
class LighthouseForecastReport {
  const LighthouseForecastReport({
    required this.summary,
    required this.pace,
    required this.daily,
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

  /// 本月两个子模型各自的预测。
  final double? pace;
  final double? daily;

  /// 组合权重（0~1，合计 1；某个模型不可用时为 0）。
  final double weightPace;
  final double weightDaily;

  final double? mapeLinear;
  final double? mapePace;
  final double? mapeDaily;
  final double? mapeEnsemble;

  /// 回测明细（按本月截止日对齐），新月份在前。
  final List<LighthouseBacktestRow> rows;

  /// 月里第 5 / 10 / 15 / 20 / 25 天分别预测时的准度。
  final List<LighthouseCheckpointRow> checkpoints;

  /// 星期一 … 星期日 的日量系数（1 = 平均）。
  final List<double> weekdayFactors;
  final double monthEndFactor;

  /// 去掉星期效应后的近期日均水平。
  final double dailyLevel;

  /// 到截止日「通常已完成全月的几成」。
  final double? paceShare;

  /// 本月 1 号 … 截止日 的累计。
  final List<double> cumActual;

  /// 1 号 … 月末 的典型累计完成比例（历史加权，0~1）。
  final List<double>? typicalShare;

  /// 上月 1 号 … 月末 的累计（按本月天数对齐）。
  final List<double>? prevCum;
}

({
  List<LighthouseBacktestRow> rows,
  double? lin,
  double? pace,
  double? daily,
  double? ens,
  double wPace,
  double wDaily,
})
_backtestAt(
  Map<DateTime, double> d,
  DateTime earliest,
  int y,
  int m,
  int c,
) {
  final total = _daysIn(y, m);
  final raw = <({DateTime month, int ck, double truth, _Pred p})>[];
  for (var k = 1; k <= 6; k++) {
    final ms = DateTime(y, m - k, 1);
    if (ms.isBefore(earliest)) break;
    final dk = _daysIn(ms.year, ms.month);
    final truth = _sumRange(d, ms.year, ms.month, 1, dk);
    if (truth.abs() < 1e-6) continue;
    final ck = (c * dk / total).round().clamp(2, dk - 1);
    raw.add((
      month: ms,
      ck: ck,
      truth: truth,
      p: _predictAt(d, earliest, ms.year, ms.month, ck),
    ));
  }
  double? mape(Iterable<double?> errs) {
    final xs = [
      for (final e in errs)
        if (e != null) e.abs(),
    ];
    return xs.length < 2 ? null : xs.reduce((a, b) => a + b) / xs.length;
  }

  final mLin = mape(
    raw.map((r) => LighthouseBacktestRow.err(r.p.linear, r.truth)),
  );
  final mPace = mape(
    raw.map((r) => LighthouseBacktestRow.err(r.p.pace, r.truth)),
  );
  final mDaily = mape(
    raw.map((r) => LighthouseBacktestRow.err(r.p.daily, r.truth)),
  );
  final wp = mPace == null ? 0.0 : 1 / (mPace + 0.01);
  final wd = mDaily == null ? 0.0 : 1 / (mDaily + 0.01);
  double? ensOf(double? p, double? dl) {
    var w = 0.0;
    var v = 0.0;
    if (p != null && wp > 0) {
      w += wp;
      v += p * wp;
    }
    if (dl != null && wd > 0) {
      w += wd;
      v += dl * wd;
    }
    return w > 0 ? v / w : null;
  }

  final rows = [
    for (final r in raw)
      LighthouseBacktestRow(
        month: r.month,
        asOfDay: r.ck,
        truth: r.truth,
        linear: r.p.linear,
        pace: r.p.pace,
        daily: r.p.daily,
        ensemble: ensOf(r.p.pace, r.p.daily),
      ),
  ];
  final mEns = mape(
    rows.map((r) => LighthouseBacktestRow.err(r.ensemble, r.truth)),
  );
  final wSum = wp + wd;
  return (
    rows: rows,
    lin: mLin,
    pace: mPace,
    daily: mDaily,
    ens: mEns,
    wPace: wSum > 0 ? wp / wSum : 0.0,
    wDaily: wSum > 0 ? wd / wSum : 0.0,
  );
}

/// 生成量化报告；数据不够建模时返回 null（与 [lighthouseModelForecast] 同条件）。
LighthouseForecastReport? lighthouseForecastReport({
  required Map<DateTime, double> daily,
  required DateTime today,
}) {
  final summary = lighthouseModelForecast(daily: daily, today: today);
  if (summary == null) return null;
  final d = <DateTime, double>{
    for (final e in daily.entries)
      if (e.value.isFinite) _day(e.key): e.value,
  };
  final earliest = d.keys.reduce((a, b) => a.isBefore(b) ? a : b);
  final t = _day(today);
  final y = t.year;
  final m = t.month;
  final total = _daysIn(y, m);
  final c = summary.cutoffDay;
  final now = _predictAt(d, earliest, y, m, c);
  final bt = _backtestAt(d, earliest, y, m, c);
  // 本月某个子模型算不出来时，权重全给另一个。
  final wp0 = now.pace == null ? 0.0 : bt.wPace;
  final wd0 = now.daily == null ? 0.0 : bt.wDaily;
  final wNow = wp0 + wd0;
  final wPaceNow = wNow > 0 ? wp0 / wNow : 0.0;
  final wDailyNow = wNow > 0 ? wd0 / wNow : 0.0;

  final checkpoints = <LighthouseCheckpointRow>[
    for (final cc in const [5, 10, 15, 20, 25])
      if (cc < total)
        () {
          final b = _backtestAt(d, earliest, y, m, cc);
          return LighthouseCheckpointRow(
            day: cc,
            months: b.rows.length,
            linear: b.lin,
            pace: b.pace,
            daily: b.daily,
            ensemble: b.ens,
          );
        }(),
  ];

  final cum = <double>[];
  var acc = 0.0;
  for (var i = 1; i <= c; i++) {
    acc += d[DateTime(y, m, i)] ?? 0;
    cum.add(acc);
  }

  // 典型完成比例曲线：前 6 个整月加权（同号月份才算）。
  List<double>? typical;
  {
    final months = <({int yy, int mm, int dk, double tk, double w})>[];
    for (var k = 1; k <= 6; k++) {
      final ms = DateTime(y, m - k, 1);
      if (ms.isBefore(earliest)) break;
      final dk = _daysIn(ms.year, ms.month);
      final tk = _sumRange(d, ms.year, ms.month, 1, dk);
      if (tk.abs() < 1e-6) continue;
      if (summary.forecast.abs() > 1e-6 && (tk > 0) != (summary.forecast > 0)) {
        continue;
      }
      months.add((
        yy: ms.year,
        mm: ms.month,
        dk: dk,
        tk: tk,
        w: math.pow(0.75, k - 1).toDouble(),
      ));
    }
    if (months.length >= 2) {
      typical = [
        for (var j = 1; j <= total; j++)
          () {
            var ws = 0.0;
            var ss = 0.0;
            for (final mo in months) {
              final jk = (j * mo.dk / total).round().clamp(1, mo.dk);
              ss += _sumRange(d, mo.yy, mo.mm, 1, jk) / mo.tk * mo.w;
              ws += mo.w;
            }
            return ws > 0 ? ss / ws : 0.0;
          }(),
      ];
    }
  }

  List<double>? prevCum;
  final pm = DateTime(y, m - 1, 1);
  if (!pm.isBefore(earliest)) {
    final dk = _daysIn(pm.year, pm.month);
    prevCum = [
      for (var j = 1; j <= total; j++)
        _sumRange(d, pm.year, pm.month, 1, (j * dk / total).round().clamp(1, dk)),
    ];
  }

  return LighthouseForecastReport(
    summary: summary,
    pace: now.pace,
    daily: now.daily,
    weightPace: wPaceNow,
    weightDaily: wDailyNow,
    mapeLinear: bt.lin,
    mapePace: bt.pace,
    mapeDaily: bt.daily,
    mapeEnsemble: bt.ens,
    rows: bt.rows,
    checkpoints: checkpoints,
    weekdayFactors: now.weekday,
    monthEndFactor: now.monthEnd,
    dailyLevel: now.level,
    paceShare: now.share,
    cumActual: cum,
    typicalShare: typical,
    prevCum: prevCum,
  );
}
