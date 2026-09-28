import 'dart:math' as math;

import 'package:dunes_app/features/lighthouse/lighthouse_forecast_model.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_dynamic_forecast.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一份「周末低、月末三天冲量、缓慢增长」的日数据。
Map<DateTime, double> _synthetic({required DateTime from, required int days}) {
  final rnd = math.Random(1);
  final out = <DateTime, double>{};
  for (var i = 0; i < days; i++) {
    final t = DateTime(from.year, from.month, from.day + i);
    final dim = DateTime(t.year, t.month + 1, 0).day;
    final weekend = t.weekday >= 6 ? 0.6 : 1.1;
    final monthEnd = t.day > dim - 3 ? 2.2 : 1.0;
    out[t] =
        100 *
        (1 + 0.003 * i) *
        weekend *
        monthEnd *
        (0.85 + rnd.nextDouble() * 0.3);
  }
  return out;
}

void main() {
  test('有月末冲量时，模型回测误差明显小于线性外推', () {
    final daily = _synthetic(from: DateTime(2026, 1, 1), days: 265);
    final f = lighthouseModelForecast(
      daily: daily,
      today: DateTime(2026, 9, 16),
    );
    expect(f, isNotNull);
    expect(f!.cutoffDay, 15); // T+1：16 号看，截至 15 号
    expect(f.usedModel, isTrue);
    expect(f.modelMape, lessThan(f.linearMape));
    expect(f.lo, lessThanOrEqualTo(f.forecast));
    expect(f.hi, greaterThanOrEqualTo(f.forecast));
    // 线性外推看不到月末冲量，会系统性偏低。
    expect(f.forecast, greaterThan(f.linear));
  });

  test('历史不足 / 月初第 1、2 天不出预测', () {
    final daily = _synthetic(from: DateTime(2026, 9, 1), days: 10);
    expect(
      lighthouseModelForecast(daily: daily, today: DateTime(2026, 9, 2)),
      isNull,
    );
  });

  test('量化报告：回测明细、检查点、参数都能算出来', () {
    final daily = _synthetic(from: DateTime(2026, 1, 1), days: 265);
    final r = lighthouseForecastReport(
      daily: daily,
      today: DateTime(2026, 9, 22),
    );
    expect(r, isNotNull);
    expect(r!.rows, isNotEmpty);
    expect(r.checkpoints.map((r) => r.day), [5, 10, 15, 20, 25, 27, 29]);
    expect(r.weekdayFactors.length, 7);
    // 合成数据周末低：周六、周日系数 < 1。
    expect(r.weekdayFactors[5], lessThan(1));
    expect(r.monthEndFactor, greaterThan(1.5));
    expect(r.cumActual.length, r.summary.cutoffDay);
    expect(r.weightPace + r.weightDaily, closeTo(1, 1e-9));
  });

  test('点值、区间、超上月概率和图中逐日路径同口径', () {
    final f = lighthouseModelForecast(
      daily: _synthetic(from: DateTime(2026, 1, 1), days: 265),
      today: DateTime(2026, 9, 22),
    )!;
    expect(f.paths.length, 1600);
    expect(f.cumulativeMean.last, f.forecast);
    expect(f.cumulativeLo.last, f.lo);
    expect(f.cumulativeHi.last, f.hi);
    expect(
      f.lo,
      lighthouseForecastQuantile(f.paths.map((p) => p.last).toList(), .1),
    );
    expect(
      f.beatPrevProb,
      f.paths.where((p) => p.last > f.prevMonthTotal!).length / f.paths.length,
    );
    final sampleMean =
        f.paths.map((p) => p.last).reduce((a, b) => a + b) / f.paths.length;
    expect(sampleMean, closeTo(f.forecast, f.forecast.abs() * .02));
    for (final path in f.paths) {
      expect(path[f.cutoffDay - 1], f.actual);
      for (var day = 1; day < path.length; day++) {
        expect(path[day], greaterThanOrEqualTo(path[day - 1]));
      }
    }
  });

  test('本月未来数据再夸张也不能改变今天的预测', () {
    final all = _synthetic(from: DateTime(2026, 1, 1), days: 280);
    final today = DateTime(2026, 9, 16);
    final prefix = Map<DateTime, double>.fromEntries(
      all.entries.where((e) => e.key.isBefore(today)),
    );
    final polluted = {
      ...prefix,
      DateTime(2026, 9, 16): -1e12,
      DateTime(2026, 10, 1): 1e20,
    };
    final a = lighthouseModelForecast(daily: prefix, today: today)!;
    final b = lighthouseModelForecast(daily: polluted, today: today)!;
    expect(b.forecast, a.forecast);
    expect(b.lo, a.lo);
    expect(b.hi, a.hi);
    expect(b.signed, isFalse);
  });

  test('日模型拟合严格只读截止日前的数据', () {
    final all = _synthetic(from: DateTime(2026, 1, 1), days: 265);
    final cutoff = DateTime(2026, 8, 15);
    final prefix = Map<DateTime, double>.fromEntries(
      all.entries.where((e) => !e.key.isAfter(cutoff)),
    );
    final a = lighthouseDynamicForecast(
      daily: prefix,
      cutoff: cutoff,
      simulations: 0,
    )!;
    final b = lighthouseDynamicForecast(
      daily: {...prefix, DateTime(2026, 8, 16): -1e18},
      cutoff: cutoff,
      simulations: 0,
    )!;
    expect(a.forecast, b.forecast);
    expect(a.weekdayFactors, b.weekdayFactors);
  });

  test('当前月缺失暂停模型，不把空日补为零；截止日跟实际可用日期', () {
    final d = _synthetic(from: DateTime(2026, 1, 1), days: 265);
    d.remove(DateTime(2026, 9, 5));
    expect(
      lighthouseModelForecast(daily: d, today: DateTime(2026, 9, 22)),
      isNull,
    );
    final stale = _synthetic(from: DateTime(2026, 1, 1), days: 253);
    final f = lighthouseModelForecast(
      daily: stale,
      today: DateTime(2026, 9, 22),
    )!;
    expect(f.cutoffDay, 10);
  });

  test('历史不完整月不参与真实全月回测', () {
    final d = _synthetic(from: DateTime(2026, 1, 1), days: 265);
    d.remove(DateTime(2026, 7, 12));
    final r = lighthouseForecastReport(daily: d, today: DateTime(2026, 9, 22))!;
    expect(r.rows.any((r) => r.month.month == 7), isFalse);
    expect(r.checkpoints.every((r) => r.months < 6), isTrue);
  });

  test('组合对照权重不偷看被评分月份的未来真实金额', () {
    final d = _synthetic(from: DateTime(2026, 1, 1), days: 265);
    final a = lighthouseForecastReport(daily: d, today: DateTime(2026, 9, 22))!;
    final row = a.rows.firstWhere((r) => r.month.month == 7);
    for (var day = row.asOfDay + 1; day <= 31; day++) {
      d[DateTime(2026, 7, day)] = 1e6;
    }
    final b = lighthouseForecastReport(
      daily: d,
      today: DateTime(2026, 9, 22),
    )!.rows.firstWhere((r) => r.month.month == 7);
    expect(b.dynamic, row.dynamic);
    expect(b.ensemble, row.ensemble);
    expect(b.weightPace, row.weightPace);
    expect(b.weightDaily, row.weightDaily);
    expect(b.truth, isNot(row.truth));
  });

  test('原算法保底的分布同样与点值一致', () {
    final d = {
      for (var day = 0; day < 265; day++) DateTime(2026, 1, 1 + day): 100.0,
    };
    final f = lighthouseModelForecast(daily: d, today: DateTime(2026, 9, 22))!;
    expect(f.usedModel, isFalse);
    expect(f.forecast, 3000);
    final mean =
        f.paths.map((p) => p.last).reduce((a, b) => a + b) / f.paths.length;
    expect(mean, closeTo(f.forecast, f.forecast * .02));
    expect(
      f.beatPrevProb,
      f.paths.where((p) => p.last > f.prevMonthTotal!).length / 1600,
    );
  });

  test('利润允许未来负贡献，不把预测强行夹到已发生以上', () {
    final d = {
      for (var day = 0; day < 265; day++)
        DateTime(2026, 1, 1 + day): -100.0 - .3 * day,
    };
    final f = lighthouseModelForecast(
      daily: d,
      today: DateTime(2026, 9, 22),
      signed: true,
    )!;
    expect(f.signed, isTrue);
    expect(f.forecast, lessThan(f.actual));
    final strip = lighthousePaceFromModel(f, shownActual: 999999);
    expect(strip.forecast, f.forecast);
    expect(strip.beatPrevProb, f.beatPrevProb);
    expect(f.lo, lessThan(f.hi));
  });

  test('月初集中结算不会误学成月底负贡献；月底回测按剩余天数对齐', () {
    final daily = <DateTime, double>{};
    for (var i = 0; i < 280; i++) {
      final day = DateTime(2026, 1, 1 + i);
      final days = DateTime(day.year, day.month + 1, 0).day;
      daily[day] =
          50000 +
          (day.day == 1 ? 1500000 : 0) +
          (day.day == 2 ? 200000 : 0) +
          (day.day == 3 ? 100000 : 0) +
          (day.day > days - 3 ? 20000 : 0);
    }
    final report = lighthouseForecastReport(
      daily: daily,
      today: DateTime(2026, 9, 28),
      signed: true,
    )!;
    final f = report.summary;
    expect(f.usedModel, isTrue);
    expect(f.dynamic.monthEndFactor, greaterThan(10000));
    expect(f.dynamic.weekdayFactors.every((v) => v.abs() < 2500), isTrue);
    expect(f.forecast - f.actual, closeTo(210000, 15000));
    expect(f.forecast, closeTo(3360000, 15000));
    expect(f.dynamicMape, lessThan(.02));
    for (final row in report.rows) {
      final days = DateTime(row.month.year, row.month.month + 1, 0).day;
      expect(days - row.asOfDay, 3);
    }
  });

  test('九月最后一天尚未发生时，不因月初结算遗留效应压低普通日贡献', () {
    final daily = <DateTime, double>{};
    for (var i = 0; i < 280; i++) {
      final day = DateTime(2026, 1, 1 + i);
      daily[day] = 80000 + (day.day == 1 ? 1600000 : 0);
    }
    final f = lighthouseModelForecast(
      daily: daily,
      today: DateTime(2026, 9, 30),
      signed: true,
    )!;
    expect(f.cutoffDay, 29);
    expect(f.forecast - f.actual, closeTo(80000, 8000));
    expect(f.forecast, closeTo(4000000, 8000));
  });

  test('零值门控、闰年与大金额单位可计算且有限', () {
    final d = {
      for (var day = 0; day < 420; day++)
        DateTime(2023, 1, 1 + day): day % 5 == 0 ? 0.0 : 1e9 + day * 1e6,
    };
    final f = lighthouseModelForecast(daily: d, today: DateTime(2024, 2, 20))!;
    expect(f.totalDays, 29);
    expect([f.forecast, f.lo, f.hi].every((v) => v.isFinite), isTrue);
    expect(f.forecast, greaterThan(f.actual));
    expect(f.lo, greaterThanOrEqualTo(f.actual));
  });
}
