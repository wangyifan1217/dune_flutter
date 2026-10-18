import 'dart:math' as math;

import 'package:dunes_app/features/lighthouse/lighthouse_forecast.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_forecast_model.dart';
import 'package:dunes_app/features/lighthouse/lighthouse_forecast_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 跟 lighthouse_forecast_model_test 同一种合成数据：周末低、月末三天冲量、缓慢增长。
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

double _sumMonth(Map<DateTime, double> d, int y, int m) {
  var s = 0.0;
  for (var i = 1; i <= DateTime(y, m + 1, 0).day; i++) {
    s += d[DateTime(y, m, i)] ?? 0;
  }
  return s;
}

void main() {
  // 10 月 16 日看：日数据从 1 月 1 日起，截至 10 月 15 日。
  final daily = _synthetic(from: DateTime(2026, 1, 1), days: 288);
  final today = DateTime(2026, 10, 16);

  test('加了年末延伸，月末预测（点值 / 区间 / 概率）逐位不变', () {
    final plain = lighthouseModelForecast(daily: daily, today: today)!;
    final ext = lighthouseModelForecast(
      daily: daily,
      today: today,
      toYearEnd: true,
    )!;
    expect(ext.forecast, plain.forecast);
    expect(ext.lo, plain.lo);
    expect(ext.hi, plain.hi);
    expect(ext.beatPrevProb, plain.beatPrevProb);
    expect(plain.dynamic.futureMonths, isEmpty);
    expect(ext.dynamic.futureMonths, [DateTime(2026, 11, 1), DateTime(2026, 12, 1)]);
    expect(ext.dynamic.futureTotals.length, ext.paths.length);
    expect(ext.dynamic.futureTotals.first.length, 2);
  });

  test('全年 = 年初至上月实际 + 本月 + 之后各月；越往后区间越宽', () {
    final mf = lighthouseModelForecast(
      daily: daily,
      today: today,
      toYearEnd: true,
    )!;
    final ye = lighthouseYearEndForecast(month: mf, daily: daily, today: today)!;
    expect(ye.year, 2026);
    expect(ye.months.length, 3);
    expect(ye.months.first.current, isTrue);
    expect(ye.remainingMonths, 2);
    var ytd = 0.0;
    for (var m = 1; m <= 9; m++) {
      ytd += _sumMonth(daily, 2026, m);
    }
    expect(ye.ytdBefore, closeTo(ytd, 1e-6));
    final sum = ye.months.fold(0.0, (a, m) => a + m.forecast);
    expect(ye.total, closeTo(ytd + sum, 1e-6));
    expect(ye.lo, lessThan(ye.total));
    expect(ye.hi, greaterThan(ye.total));
    for (final m in ye.months) {
      expect(m.lo, lessThanOrEqualTo(m.forecast));
      expect(m.hi, greaterThanOrEqualTo(m.forecast));
    }
    double width(LighthouseYearEndMonth m) => (m.hi - m.lo) / m.forecast;
    expect(width(ye.months[2]), greaterThan(width(ye.months[1])));
    // 合成数据在缓慢增长、没有季节性：11、12 月应该落在 10 月附近。
    expect(ye.months[1].forecast / ye.months[0].forecast, inInclusiveRange(0.7, 1.4));
  });

  test('年初缺月、日数据也补不上：不出年末（不拿缺口当 0）', () {
    final late = _synthetic(from: DateTime(2026, 2, 10), days: 248);
    final mf = lighthouseModelForecast(
      daily: late,
      today: today,
      toYearEnd: true,
    )!;
    expect(
      lighthouseYearEndForecast(month: mf, daily: late, today: today),
      isNull,
    );
    // 月度接口把 1、2 月补上就有了。
    final ye = lighthouseYearEndForecast(
      month: mf,
      daily: late,
      today: today,
      monthly: {DateTime(2026, 1, 1): 3000, DateTime(2026, 2, 1): 2800},
    );
    expect(ye, isNotNull);
  });

  test('12 月：没有之后的月，全年 = 年初至 11 月 + 本月预测', () {
    final dec = _synthetic(from: DateTime(2026, 1, 1), days: 349);
    final t = DateTime(2026, 12, 16);
    final mf = lighthouseModelForecast(daily: dec, today: t, toYearEnd: true)!;
    final ye = lighthouseYearEndForecast(month: mf, daily: dec, today: t)!;
    expect(ye.months.length, 1);
    expect(ye.remainingMonths, 0);
    final p = lighthousePaceFromModel(mf, shownActual: mf.actual, yearEnd: ye);
    expect(p.future, isEmpty);
  });

  test('主图用的预测对象带上之后各月和全年', () {
    final mf = lighthouseModelForecast(
      daily: daily,
      today: today,
      toYearEnd: true,
    )!;
    final ye = lighthouseYearEndForecast(month: mf, daily: daily, today: today);
    final p = lighthousePaceFromModel(mf, shownActual: mf.actual, yearEnd: ye);
    expect(p.future.map((m) => m.month.month), [11, 12]);
    expect(p.yearTotal, ye!.total);
    expect(p.future.length, lessThanOrEqualTo(lighthouseYearEndChartMaxMonths));
  });

  test('报告：带年末一节和「提前 1 / 2 个月」回测', () {
    final r = lighthouseForecastReport(daily: daily, today: today)!;
    expect(r.yearEnd, isNotNull);
    expect(r.yearEnd!.horizons.map((h) => h.horizon), [1, 2]);
    expect(r.yearEnd!.horizons.first.months, greaterThanOrEqualTo(2));
    expect(r.yearEnd!.horizons.first.dynamic, isNotNull);
    // 去年没有数：不给超去年概率。
    expect(r.yearEnd!.lastYearTotal, isNull);
    expect(r.yearEnd!.beatLastYearProb, isNull);
  });

  testWidgets('预测条写出年末', (tester) async {
    tester.view.physicalSize = const Size(560, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final mf = lighthouseModelForecast(
      daily: daily,
      today: today,
      toYearEnd: true,
    )!;
    final ye = lighthouseYearEndForecast(month: mf, daily: daily, today: today);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LighthouseForecastStrip(
            forecast: lighthousePaceFromModel(
              mf,
              shownActual: mf.actual,
              yearEnd: ye,
            ),
            money: (v) => '${(v / 1e4).toStringAsFixed(2)}万',
            accent: const Color(0xFF51418E),
            onOpenReport: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('年末'), findsOneWidget);
  });
}
