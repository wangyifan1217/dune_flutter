import 'package:dunes_app/features/lighthouse/lighthouse_trend_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = <String, dynamic>{
    'heroSeriesKeys': ['2026-09-15', '2026-09-16'],
    'heroSeriesLabels': ['9.15', '9.16'],
    'salesSeries': [10, 20],
    'profitSeries': [1, 2],
    'profitSeriesPrev': [9, 9],
    'netTaSeries': [5, 5],
    'costBillTypeSeries': {
      'A': [3, 4],
    },
    'profit': 2,
  };

  Map<String, dynamic> page(List<String> keys, {bool more = true}) => {
    'keys': keys,
    'labels': [for (final k in keys) k.substring(5)],
    'hasMore': more,
    'series': {
      'salesSeries': [for (var i = 0; i < keys.length; i++) i + 1],
      'costBillTypeSeries': {
        'A': [for (var i = 0; i < keys.length; i++) 7],
      },
    },
  };

  test('历史页拼到最前，缺的序列补 0，重叠键去重', () {
    var h = const LighthouseHeroHistory(requestKey: 'k');
    h = h.prependPage(page(['2026-09-13', '2026-09-14']));
    h = h.prependPage(page(['2026-09-12', '2026-09-13'], more: false));
    expect(h.keys, ['2026-09-12', '2026-09-13', '2026-09-14']);
    expect(h.series['salesSeries'], [1, 1, 2]);
    expect(h.hasMore, isFalse);
    expect(h.version, 2);

    final merged = lighthouseMergeHeroHistory(base, h);
    expect(merged['heroSeriesKeys'], hasLength(5));
    expect(merged['heroSeriesLabels'].first, '09-12');
    expect(merged['salesSeries'], [1, 1, 2, 10, 20]);
    // 历史页没带 profitSeries：补 0，长度仍然对齐。
    expect(merged['profitSeries'], [0, 0, 0, 1, 2]);
    // 对比序列、非 Hero 时间轴的序列不拼。
    expect(merged['profitSeriesPrev'], [9, 9]);
    expect(merged['netTaSeries'], [5, 5]);
    expect((merged['costBillTypeSeries'] as Map)['A'], [7, 7, 7, 3, 4]);
    expect(merged['profit'], 2);
  });

  test('空页：hasMore=false，原数据不动', () {
    final h = const LighthouseHeroHistory(requestKey: 'k').prependPage({
      'keys': <String>[],
      'labels': <String>[],
      'hasMore': false,
    });
    expect(h.length, 0);
    expect(h.hasMore, isFalse);
    expect(identical(lighthouseMergeHeroHistory(base, h), base), isTrue);
  });

  test('视窗夹紧与点选换算', () {
    expect(
      lighthouseTrendClampViewEnd(viewEnd: 40, count: 30, visible: 7),
      29,
    );
    expect(lighthouseTrendClampViewEnd(viewEnd: 1, count: 30, visible: 7), 6);
    expect(lighthouseTrendClampViewEnd(viewEnd: 3, count: 4, visible: 7), 3);
    // step 10、视窗从 5 开始、一屏 7 个：x=6+20 → 下标 7。
    expect(
      lighthouseTrendIndexAtX(
        x: 26,
        padH: 6,
        step: 10,
        viewStart: 5,
        visible: 7,
        count: 30,
      ),
      7,
    );
    // 拖到画布外也夹回可见范围。
    expect(
      lighthouseTrendIndexAtX(
        x: 999,
        padH: 6,
        step: 10,
        viewStart: 5,
        visible: 7,
        count: 30,
      ),
      11,
    );
  });
}
