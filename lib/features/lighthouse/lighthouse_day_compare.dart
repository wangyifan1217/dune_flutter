// 灯塔 · 日线的环比对照：上月同日（2026-11）。
//
// 2026-08 运营会定的口径：「今天是 25 号，就环比上个月的 25 号」。后端日期间
//（period.go 的 sameDayPrevMonth）早就这么比了，但前端点选走势某一天时还在拿
// 前一天比、文案写「vs 上日」。这里放纯函数，走势卡 / 大数 / 指标格共用。

import 'dart:math' as math;

/// 日线的对照：一律「上月同日」（2026-11 起，灯塔所有日角度都不再跟上日比）。
const String lighthouseDayCompareLabel = 'vs 上月同日';

/// 日线「上月同日」：今天 25 号就比上个月 25 号。上月没有这一天（3.31 → 2 月）
/// 取上月最后一天，和后端 period.go 的 sameDayPrevMonth 一致。
DateTime lighthouseSameDayPrevMonth(DateTime d) {
  final first = DateTime(d.year, d.month - 1, 1);
  final last = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, math.min(d.day, last));
}

final RegExp _lhDayKeyRe = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$');
final RegExp _lhDayLabelRe = RegExp(r'(\d{1,2})\D(\d{1,2})\D*$');

/// 横轴每一格的日期。「2026-11-02」这种键直接读；「11.02」只有月日，从最后一格
///（[latestYear]，默认今年）往回推，月份突然变大（1 月 → 12 月）就是跨了年。
/// 解析不了的格子是 null。
List<DateTime?> lighthouseDayAxisDates(List<String> axis, {int? latestYear}) {
  final out = List<DateTime?>.filled(axis.length, null);
  var year = latestYear ?? DateTime.now().year;
  int? laterMonth;
  for (var i = axis.length - 1; i >= 0; i--) {
    final raw = axis[i].trim();
    final full = _lhDayKeyRe.firstMatch(raw);
    if (full != null) {
      final y = int.parse(full.group(1)!);
      final m = int.parse(full.group(2)!);
      final d = int.parse(full.group(3)!);
      if (m < 1 || m > 12 || d < 1 || d > 31) continue;
      out[i] = DateTime(y, m, d);
      year = y;
      laterMonth = m;
      continue;
    }
    final md = _lhDayLabelRe.firstMatch(raw);
    if (md == null) continue;
    final m = int.parse(md.group(1)!);
    final d = int.parse(md.group(2)!);
    if (m < 1 || m > 12 || d < 1 || d > 31) continue;
    if (laterMonth != null && m > laterMonth) year--;
    out[i] = DateTime(year, m, d);
    laterMonth = m;
  }
  return out;
}

/// 点第 [index] 格时拿哪一格比：轴上「上月同日」那一格。
/// 轴上没有那一天（历史还没拉到那么早）→ null：宁可写「暂无对比」，
/// 也不拿前一天顶上。
int? lighthouseSameDayPrevMonthIndex(List<DateTime?> dates, int index) {
  if (index < 0 || index >= dates.length) return null;
  final d = dates[index];
  if (d == null) return null;
  final want = lighthouseSameDayPrevMonth(d);
  for (var j = index - 1; j >= 0; j--) {
    final p = dates[j];
    if (p == null) continue;
    if (p.year == want.year && p.month == want.month && p.day == want.day) {
      return j;
    }
    if (p.isBefore(want)) break;
  }
  return null;
}
