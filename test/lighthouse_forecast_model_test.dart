import 'dart:math' as math;

import 'package:dunes_app/features/lighthouse/lighthouse_forecast_model.dart';
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
    final r = lighthouseForecastReport(daily: daily, today: DateTime(2026, 9, 22));
    expect(r, isNotNull);
    expect(r!.rows, isNotEmpty);
    expect(r.checkpoints.length, 5);
    expect(r.weekdayFactors.length, 7);
    // 合成数据周末低：周六、周日系数 < 1。
    expect(r.weekdayFactors[5], lessThan(1));
    expect(r.monthEndFactor, greaterThan(1.5));
    expect(r.cumActual.length, r.summary.cutoffDay);
    expect(r.weightPace + r.weightDaily, closeTo(1, 1e-9));
  });
}
