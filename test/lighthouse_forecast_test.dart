import 'package:dunes_app/features/lighthouse/lighthouse_forecast.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2026-08 运营会要求的唯一新增算法：
///   预测月末规模 = 本月已发生规模 ÷ 已过天数 × 当月天数
void main() {
  group('lighthouseMonthPaceForecast', () {
    test('会上口述算例：月中 1,000 万 → 约 2,000 万', () {
      // 30 天的月份走到第 15 天。
      final f = lighthouseMonthPaceForecast(
        actual: 10000000,
        now: DateTime(2026, 6, 15),
      );
      expect(f, isNotNull);
      expect(f!.totalDays, 30);
      expect(f.elapsedDays, 15);
      expect(f.forecast, closeTo(20000000, 1));
      expect(f.remaining, closeTo(10000000, 1));
    });

    test('会上口述算例：中石化 8/25 做到 8,700 万 → 约 1.08 亿', () {
      final f = lighthouseMonthPaceForecast(
        actual: 87000000,
        now: DateTime(2026, 8, 25),
      );
      expect(f, isNotNull);
      expect(f!.totalDays, 31);
      expect(f.elapsedDays, 25);
      expect(f.forecast, closeTo(107880000, 1000));
      expect(f.progress, closeTo(25 / 31, 1e-9));
    });

    test('月末最后一天不再预测 —— 实线就是结果', () {
      expect(
        lighthouseMonthPaceForecast(
          actual: 87000000,
          now: DateTime(2026, 8, 31),
        ),
        isNull,
      );
    });

    test('无发生额 / 负数不预测', () {
      expect(
        lighthouseMonthPaceForecast(actual: 0, now: DateTime(2026, 8, 10)),
        isNull,
      );
      expect(
        lighthouseMonthPaceForecast(actual: -5, now: DateTime(2026, 8, 10)),
        isNull,
      );
    });

    test('闰年二月天数正确', () {
      expect(lighthouseDaysInMonth(2028, 2), 29);
      expect(lighthouseDaysInMonth(2026, 2), 28);
      final f = lighthouseMonthPaceForecast(
        actual: 1400,
        now: DateTime(2028, 2, 14),
      );
      expect(f!.forecast, closeTo(2900, 1e-6));
    });
  });

  group('lighthouseMetricSupportsPace', () {
    test('比率类不月化', () {
      expect(lighthouseMetricSupportsPace('grossMargin'), isFalse);
      expect(lighthouseMetricSupportsPace('rate'), isFalse);
      expect(lighthouseMetricSupportsPace('spreadRate'), isFalse);
    });

    test('规模 / 金额类月化', () {
      expect(lighthouseMetricSupportsPace('sales'), isTrue);
      expect(lighthouseMetricSupportsPace('verifiedSales'), isTrue);
      expect(lighthouseMetricSupportsPace('profit'), isTrue);
      expect(lighthouseMetricSupportsPace('totalCost'), isTrue);
    });
  });
}
