// 灯塔 · 主 Hero 走势「往前拉加载历史」（股票式）
//
// summary 只下发最近 N 个桶（日 7 / 周 7 / 月 7 / 季 4 / 年 7），并带上每个桶的
// 机器键 heroSeriesKeys。走势图往前拖到左沿时，拿「当前最早的键」请求
// /lighthouse/hero-history?before=…，返回的一页序列键名与 summary.metrics
// 完全相同（salesSeries / profitSeries / costBillTypeSeries …）。
//
// 这里只放纯数据逻辑（可单测）：历史页的累积、与 summary.metrics 的拼接、
// 视窗换算。页面状态与请求在 native_lighthouse_page.dart。

import 'dart:math' as math;

/// 已加载的历史（最早的桶在前）。不可变：每拼一页生成一个新对象。
class LighthouseHeroHistory {
  const LighthouseHeroHistory({
    required this.requestKey,
    this.keys = const <String>[],
    this.labels = const <String>[],
    this.series = const <String, List<double>>{},
    this.costBillSeries = const <String, List<double>>{},
    this.hasMore = true,
    this.loading = false,
    this.error,
    this.version = 0,
  });

  /// 这份历史属于哪一次 summary（周期 / 偏移 / tab / 分类 / 当前窗口首键）。
  /// 任何一项变了，历史作废。
  final String requestKey;
  final List<String> keys;
  final List<String> labels;

  /// summary.metrics 里的 `xxxSeries` 键 → 历史值。
  final Map<String, List<double>> series;

  /// costBillTypeSeries 的 code → 历史值。
  final Map<String, List<double>> costBillSeries;
  final bool hasMore;
  final bool loading;
  final String? error;

  /// 每拼一页 +1，页面用它判断拼接结果是否要重算。
  final int version;

  int get length => keys.length;

  LighthouseHeroHistory copyWith({bool? loading, bool? hasMore, String? error}) {
    return LighthouseHeroHistory(
      requestKey: requestKey,
      keys: keys,
      labels: labels,
      series: series,
      costBillSeries: costBillSeries,
      hasMore: hasMore ?? this.hasMore,
      loading: loading ?? this.loading,
      error: error,
      version: version,
    );
  }

  /// 把后端返回的一页（更早）拼到最前面。
  /// 页里与已有键重叠的桶会被丢掉；页和已有序列的键集合不同时，缺的补 0。
  LighthouseHeroHistory prependPage(Map<String, dynamic> page) {
    final rawKeys = _stringList(page['keys']);
    final rawLabels = _stringList(page['labels']);
    final more = page['hasMore'] == true;
    if (rawKeys.isEmpty || rawKeys.length != rawLabels.length) {
      return LighthouseHeroHistory(
        requestKey: requestKey,
        keys: keys,
        labels: labels,
        series: series,
        costBillSeries: costBillSeries,
        hasMore: false,
        version: version,
      );
    }
    final existing = keys.toSet();
    final take = <int>[
      for (var i = 0; i < rawKeys.length; i++)
        if (!existing.contains(rawKeys[i])) i,
    ];
    final pageLen = take.length;
    final seriesRaw = page['series'] is Map
        ? Map<String, dynamic>.from(page['series'] as Map)
        : const <String, dynamic>{};

    List<double> pick(List<double> full) => [
      for (final i in take) i < full.length ? full[i] : 0.0,
    ];

    final nextSeries = <String, List<double>>{};
    final seriesKeys = <String>{
      ...series.keys,
      for (final e in seriesRaw.entries)
        if (e.value is List && e.key.endsWith('Series')) e.key,
    };
    for (final k in seriesKeys) {
      final pageVals = seriesRaw[k] is List
          ? pick(_doubleList(seriesRaw[k]))
          : List<double>.filled(pageLen, 0.0);
      final old = series[k] ?? List<double>.filled(length, 0.0);
      nextSeries[k] = [...pageVals, ...old];
    }

    final billRaw = seriesRaw['costBillTypeSeries'] is Map
        ? Map<String, dynamic>.from(seriesRaw['costBillTypeSeries'] as Map)
        : const <String, dynamic>{};
    final nextBills = <String, List<double>>{};
    for (final code in <String>{...costBillSeries.keys, ...billRaw.keys}) {
      final pageVals = billRaw[code] is List
          ? pick(_doubleList(billRaw[code]))
          : List<double>.filled(pageLen, 0.0);
      final old = costBillSeries[code] ?? List<double>.filled(length, 0.0);
      nextBills[code] = [...pageVals, ...old];
    }

    return LighthouseHeroHistory(
      requestKey: requestKey,
      keys: [for (final i in take) rawKeys[i], ...keys],
      labels: [for (final i in take) rawLabels[i], ...labels],
      series: nextSeries,
      costBillSeries: nextBills,
      hasMore: more && pageLen > 0,
      version: version + 1,
    );
  }
}

/// 主 Hero 序列键（与 lighthouse-go attachSeriesKeys 一一对应）。
/// 只拼这些 —— metrics 里还有净TA 等别的 `xxxSeries`，它们不是这根时间轴。
const lighthouseHeroHistorySeriesKeys = <String>[
  'salesSeries',
  'profitSeries',
  'netProfitSeries',
  'revenueSeries',
  'costSeries',
  'taxSeries',
  'operatingCostSeries',
  'totalCostSeries',
  'projectCostSeries',
  'spreadSeries',
  'spreadRateSeries',
  'rateSeries',
  'verifiedSeries',
  'verifiedSalesSeries',
  'prepaidSeries',
  'gmvSeries',
  'grossMarginSeries',
];

/// 把历史拼到 summary.metrics 前面，得到一份「更长的」metrics 视图。
///
/// 只动走势相关的键：heroSeriesLabels / heroSeriesKeys / 各 `xxxSeries` /
/// costBillTypeSeries。其余标量原样保留。`xxxSeriesPrev`（对比序列）不拼 ——
/// 它和主序列不是同一根时间轴。
Map<String, dynamic> lighthouseMergeHeroHistory(
  Map<String, dynamic> metrics,
  LighthouseHeroHistory history,
) {
  final n = history.length;
  if (n == 0) return metrics;
  final baseKeys = _stringList(metrics['heroSeriesKeys']);
  final baseLen = baseKeys.length;
  if (baseLen == 0) return metrics;
  final out = Map<String, dynamic>.from(metrics);
  out['heroSeriesKeys'] = [...history.keys, ...baseKeys];
  final baseLabels = _stringList(metrics['heroSeriesLabels']);
  out['heroSeriesLabels'] = [
    ...history.labels,
    ...(baseLabels.length == baseLen
        ? baseLabels
        : List<String>.filled(baseLen, '')),
  ];
  for (final k in lighthouseHeroHistorySeriesKeys) {
    final raw = metrics[k];
    if (raw is! List) continue;
    final base = _doubleList(raw);
    if (base.length != baseLen) continue;
    final hist = history.series[k] ?? List<double>.filled(n, 0.0);
    out[k] = <double>[...hist, ...base];
  }
  final bills = metrics['costBillTypeSeries'];
  if (bills is Map) {
    final merged = <String, List<double>>{};
    for (final e in bills.entries) {
      final base = _doubleList(e.value);
      if (base.length != baseLen) continue;
      final hist =
          history.costBillSeries[e.key.toString()] ??
          List<double>.filled(n, 0.0);
      merged[e.key.toString()] = <double>[...hist, ...base];
    }
    out['costBillTypeSeries'] = merged;
  }
  return out;
}

/// 视窗：最右那个点的下标 [viewEnd]（可带小数，拖动中间态），一屏 [visible] 个点。
/// 返回夹紧后的 viewEnd —— 不能拖过最新，也不能拖到最早之前。
double lighthouseTrendClampViewEnd({
  required double viewEnd,
  required int count,
  required int visible,
}) {
  if (count <= 0) return 0;
  final hi = (count - 1).toDouble();
  final lo = math.min(hi, (visible - 1).toDouble());
  return viewEnd.clamp(lo, hi).toDouble();
}

/// 屏幕 x → 最近的数据下标（视窗模式），夹在当前一屏可见的点里。
int lighthouseTrendIndexAtX({
  required double x,
  required double padH,
  required double step,
  required double viewStart,
  required int visible,
  required int count,
}) {
  if (count <= 0) return 0;
  if (step <= 0) return count - 1;
  final raw = (viewStart + (x - padH) / step).round();
  final lo = (viewStart - 1e-6).ceil().clamp(0, count - 1);
  final hi = (viewStart + visible - 1 + 1e-6).floor().clamp(lo, count - 1);
  return raw.clamp(lo, hi);
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const <String>[];
  return [for (final e in raw) e?.toString() ?? ''];
}

List<double> _doubleList(dynamic raw) {
  if (raw is! List) return const <double>[];
  return [for (final e in raw) e is num ? e.toDouble() : 0.0];
}
