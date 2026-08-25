// ═════════════════════════════════════════════════════════════════════════════
// 月化规模预测 —— 2026-08 运营会要求新增的唯一一个算法
//
//   会议原话："增加一个算法，按照前面的发生额预测它的月化规模。我只要这一个算法。"
//
//   公式：  预测月末规模 = 本月已发生规模 ÷ 已过天数 × 当月天数
//
//   口径约束（会上明确）：
//     · 只在「点月」时出现 —— 点日 / 点周 / 点季 / 点年一律不预测。
//     · 只对规模 / 金额类指标出 —— 毛利率、ROI、利差率这类比率没有月化意义。
//     · 已发生部分画实线，月末预测部分画虚线（当月同一列向上延伸）。
//     · 用途：省一级在月中就能看出「这个月能不能达标」——达标就监测，
//       差几十万就提前加电加量，而不是等月底复盘。
//
//   口述算例：
//     · 月中（15/30 天）做到 1,000 万 → 预测约 2,000 万。
//     · 中石化 8 月 25 日做到 8,700 万 → 8700 ÷ 25 × 31 ≈ 10,788 万（约 1.08 亿）。
// ═════════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart' show immutable;

/// 当月自然日天数（DateTime(y, m + 1, 0) 会回退到上个月最后一天）。
int lighthouseDaysInMonth(int year, int month) =>
    DateTime(year, month + 1, 0).day;

@immutable
class LighthousePaceForecast {
  const LighthousePaceForecast({
    required this.actual,
    required this.forecast,
    required this.elapsedDays,
    required this.totalDays,
  });

  /// 本月已发生规模（实线末端的值）。
  final double actual;

  /// 线性外推到月末的预测规模（虚线端点的值）。
  final double forecast;

  /// 已过天数 —— 含当天。25 号看，就是 25 天。
  final int elapsedDays;

  /// 当月自然日天数。
  final int totalDays;

  /// 月度进度 0~1，给「已走完 81%」这类文案用。
  double get progress => totalDays <= 0 ? 0 : elapsedDays / totalDays;

  /// 还要补多少才能走到预测值（虚线那一段的长度）。
  double get remaining => forecast - actual;
}

/// 月化规模预测。不满足口径时返回 null —— 调用方据此决定「不画虚线」。
///
/// 返回 null 的情形：
///   · [actual] 非有限值、为 0 或为负 —— 没有可外推的发生额；
///   · 已过天数 <= 0 或已经走满当月 —— 月末当天没有预测的意义，实线即结果。
LighthousePaceForecast? lighthouseMonthPaceForecast({
  required double actual,
  required DateTime now,
}) {
  if (!actual.isFinite || actual <= 0) return null;
  final totalDays = lighthouseDaysInMonth(now.year, now.month);
  final elapsedDays = now.day;
  if (elapsedDays <= 0 || elapsedDays >= totalDays) return null;
  return LighthousePaceForecast(
    actual: actual,
    forecast: actual / elapsedDays * totalDays,
    elapsedDays: elapsedDays,
    totalDays: totalDays,
  );
}

/// 该指标是否适用月化预测：比率类不适用，规模 / 金额类适用。
///
/// 与 `_seriesForMetric` 的 key 保持一致，新增比率指标时同步补进来。
bool lighthouseMetricSupportsPace(String metricKey) {
  switch (metricKey) {
    case 'grossMargin':
    case 'rate':
    case 'spreadRate':
    case 'margin':
    case 'roi':
      return false;
    default:
      return true;
  }
}
