import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_theme.dart';

// ════════════════════════════════════════════════════════════════════════
// 未结账款（2026-10-27 接入 · 2026-10-28 对齐资管文档 1.0 并嵌进资金页）
//
//   资管 /out/lighthouse/bill-outstanding 经 lighthouse-go 代理：
//   应收未回款 / 应付未付款，按「对方 + 账单类型」分组（1.0 不再带我方主体）。
//
//   资金页里的位置（原型「④ 按现有资金页嵌入」）：
//     · 规模 / 成本 / 利润下面多一块同样式的「账款」面板：应收 · 应付 · 净额；
//     · 点应收 / 应付：左边大数卡换成这一侧 + 迷你天平，右边图表卡换成
//       「按对方」构成（金额条 + 账单结束日刻度带）；再点一次或「回总资产」复原。
//
//   口径（界面上要写出来的）：
//     · 只含「未回款」「未付款」整张账单，部分回款 / 部分付款不在内；
//     · 「结束日超 N 天」= 账单结束日 + graceDays（现为 7）仍未结，临时规则，
//       不叫「逾期」「超期」（灯塔超期是提案 D+N / M+N，另一回事），不用红色；
//     · earliest / latestBillEnd 是「账单结束日范围」，不是账单覆盖期间、不是账龄；
//     · 省份是灯塔按主体表补的「匹配省份」，不是资管给的归属。
//   受限账号后端回 restricted，前端整块不出现；专题、分享卡不拉。
// ════════════════════════════════════════════════════════════════════════

/// 未结账款开关。2026-10-28：对齐 1.0、嵌进资金页后打开。
/// 财务没确认口径前要上线，改回 false：资金页不出面板、也不去拉接口。
const bool lighthouseBillOutstandingEnabled = true;

// ── 模型 ──────────────────────────────────────────────────────────────────

class LhBillTotal {
  const LhBillTotal({
    required this.unpaidAmount,
    required this.unpaidCount,
    required this.overdueAmount,
    required this.overdueCount,
  });

  final double unpaidAmount;
  final int unpaidCount;
  final double overdueAmount;
  final int overdueCount;

  double get overdueShare => unpaidAmount.abs() < 1e-9
      ? 0
      : (overdueAmount / unpaidAmount).clamp(0.0, 1.0).toDouble();

  double get overdueCountShare => unpaidCount == 0
      ? 0
      : (overdueCount / unpaidCount).clamp(0.0, 1.0).toDouble();

  static LhBillTotal? fromJson(Object? raw) {
    if (raw is! Map) return null;
    double d(String k) => (raw[k] as num?)?.toDouble() ?? 0;
    int i(String k) => (raw[k] as num?)?.toInt() ?? 0;
    return LhBillTotal(
      unpaidAmount: d('unpaidAmount'),
      unpaidCount: i('unpaidCount'),
      overdueAmount: d('overdueAmount'),
      overdueCount: i('overdueCount'),
    );
  }
}

class LhBillGroup {
  const LhBillGroup({
    required this.side,
    required this.counterparty,
    required this.billType,
    required this.billCount,
    required this.unpaidAmount,
    required this.overdueAmount,
    required this.earliestEnd,
    required this.latestEnd,
    required this.provinceName,
    required this.category,
  });

  /// AR 应收 / AP 应付。
  final String side;
  final String counterparty;
  final String billType;
  final int billCount;
  final double unpaidAmount;
  final double overdueAmount;

  /// 组内最早 / 最晚账单结束日，可空。是结束日的范围，不是覆盖期间。
  final DateTime? earliestEnd;
  final DateTime? latestEnd;

  /// 灯塔按主体表补的「匹配省份」，对不上为空。
  final String provinceName;

  /// 石油 / 石化归属；同省有多种归属时后端留空。
  final String category;

  static DateTime? _date(Object? v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static LhBillGroup fromJson(Map raw) => LhBillGroup(
    side: (raw['side'] ?? '').toString().trim().toUpperCase(),
    counterparty: (raw['counterpartyName'] ?? '').toString().trim(),
    billType: (raw['billTypeName'] ?? '').toString().trim(),
    billCount: (raw['billCount'] as num?)?.toInt() ?? 0,
    unpaidAmount: (raw['unpaidAmount'] as num?)?.toDouble() ?? 0,
    overdueAmount: (raw['overdueAmount'] as num?)?.toDouble() ?? 0,
    earliestEnd: _date(raw['earliestBillEnd']),
    latestEnd: _date(raw['latestBillEnd']),
    provinceName: (raw['provinceName'] ?? '').toString().trim(),
    category: (raw['category'] ?? '').toString().trim(),
  );
}

/// 同一对方的几种账单类型合在一起（构成图、明细卡用）。保持接口顺序：
/// 接口已按超 N 天金额、再按未结金额降序，第一次出现的位置就是这个对方的名次。
class LhBillCounterparty {
  LhBillCounterparty(this.name);

  final String name;
  final List<LhBillGroup> groups = <LhBillGroup>[];

  double get unpaidAmount => groups.fold(0, (s, g) => s + g.unpaidAmount);
  double get overdueAmount => groups.fold(0, (s, g) => s + g.overdueAmount);
  int get billCount => groups.fold(0, (s, g) => s + g.billCount);

  double get overdueShare => unpaidAmount.abs() < 1e-9
      ? 0
      : (overdueAmount / unpaidAmount).clamp(0.0, 1.0).toDouble();

  DateTime? get earliestEnd {
    DateTime? out;
    for (final g in groups) {
      final d = g.earliestEnd;
      if (d != null && (out == null || d.isBefore(out))) out = d;
    }
    return out;
  }

  DateTime? get latestEnd {
    DateTime? out;
    for (final g in groups) {
      final d = g.latestEnd ?? g.earliestEnd;
      if (d != null && (out == null || d.isAfter(out))) out = d;
    }
    return out;
  }

  /// 匹配标签：省份（+ 归属）。几组挂的省不一样就不写。
  String get matchLabel {
    final provinces = {
      for (final g in groups)
        if (g.provinceName.isNotEmpty) g.provinceName,
    };
    if (provinces.length != 1) return '';
    final cats = {
      for (final g in groups)
        if (g.category.isNotEmpty) g.category,
    };
    final p = provinces.first;
    return cats.length == 1 ? '$p · ${lhBillCategoryLabel(cats.first)}' : p;
  }
}

String lhBillCategoryLabel(String c) => switch (c.toLowerCase()) {
  'oil' || 'cnpc' || '石油' || '中石油' => '石油',
  'sinopec' || 'petro' || '石化' || '中石化' => '石化',
  _ => c,
};

class LhBillOutstanding {
  const LhBillOutstanding({
    required this.restricted,
    required this.asOf,
    required this.graceDays,
    required this.receivable,
    required this.payable,
    required this.groups,
    this.fixture = false,
  });

  /// 受限账号 / 后端没配资管：整块不出现。
  final bool restricted;

  /// 实际统计日 yyyy-MM-dd。
  final String asOf;

  /// 「结束日超 N 天」的 N（资管现为 7），文案都从这里读，不写死。
  final int graceDays;

  /// null = 这一侧没查（不是没有未结）。
  final LhBillTotal? receivable;
  final LhBillTotal? payable;
  final List<LhBillGroup> groups;

  /// 资管接口没通时，本机用文档样例撑起来。
  final bool fixture;

  bool get visible => !restricted && (receivable != null || payable != null);

  DateTime? get asOfDate => DateTime.tryParse(asOf);

  /// 统计日减 graceDays：结束日早于这天的算「超 N 天」。
  DateTime? get graceLine => asOfDate?.subtract(Duration(days: graceDays));

  String get asOfShort => asOf.length == 10 ? asOf.substring(5) : asOf;

  LhBillTotal? totalOf(String side) => side == 'AR' ? receivable : payable;

  /// 净额 = 应收 − 应付；任何一侧没查就没有净额。
  double? get net {
    final r = receivable;
    final p = payable;
    if (r == null || p == null) return null;
    return r.unpaidAmount - p.unpaidAmount;
  }

  List<LhBillCounterparty> counterparties(
    String side, {
    bool overdueOnly = false,
  }) {
    final out = <LhBillCounterparty>[];
    final byName = <String, LhBillCounterparty>{};
    for (final g in groups) {
      if (g.side != side) continue;
      if (overdueOnly && g.overdueAmount <= 0) continue;
      final name = g.counterparty.isEmpty ? '（未填对方）' : g.counterparty;
      final cp = byName.putIfAbsent(name, () {
        final c = LhBillCounterparty(name);
        out.add(c);
        return c;
      });
      cp.groups.add(g);
    }
    return out;
  }

  static LhBillOutstanding fromJson(Map<String, dynamic> data) {
    final hidden = data['restricted'] == true || data['unavailable'] == true;
    final grace = (data['graceDays'] as num?)?.toInt();
    return LhBillOutstanding(
      restricted: hidden,
      asOf: (data['asOf'] ?? '').toString(),
      graceDays: grace == null || grace <= 0 ? 7 : grace,
      receivable: LhBillTotal.fromJson(data['receivable']),
      payable: LhBillTotal.fromJson(data['payable']),
      groups: [
        for (final g in (data['groups'] as List? ?? const []))
          if (g is Map) LhBillGroup.fromJson(g),
      ],
      fixture: data['fixture'] == true,
    );
  }
}

/// 元 → 「2.29亿」「7083.9万」「860」。
String lhBillAmount(double yuan) {
  final v = yuan.abs();
  final sign = yuan < 0 ? '−' : '';
  if (v >= 1e8) return '$sign${(v / 1e8).toStringAsFixed(2)}亿';
  if (v >= 1e4) return '$sign${(v / 1e4).toStringAsFixed(1)}万';
  return '$sign${v.toStringAsFixed(0)}';
}

String _md(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _count(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

// ── 颜色 / 小件 ───────────────────────────────────────────────────────────

const _kDeep = Color(0xFF3B2D66);
const _kPlum = Color(0xFF7B5CD8);
const _kPlumSoft = Color(0xFF9C86E6);
const _kLine = Color(0xFFECE8F3);
const _kTrack = Color(0xFFF4F2F9);
const _kHatchBg = Color(0xFFE9E2FB);
const _kHatchInk = Color(0xFF9C86E6);
const _kGraceLine = Color(0xFFB9A5F0);
const _kSample = Color(0xFF8A6A12);

Color _r(
  BuildContext context,
  Color v, [
  DunesColorRole role = DunesColorRole.foreground,
]) => DunesColors.resolve(context, v, role: role);

/// 斜线纹：「结束日超 N 天」那一段。不用红色 —— 这是临时规则，不是警报。
class _HatchPainter extends CustomPainter {
  const _HatchPainter({required this.bg, required this.ink});

  final Color bg;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final p = Paint()
      ..color = ink
      ..strokeWidth = 1.3;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = -size.height; x < size.width + size.height; x += 4) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HatchPainter old) =>
      old.bg != bg || old.ink != ink;
}

Widget _hatch(BuildContext context) => CustomPaint(
  painter: _HatchPainter(
    bg: _r(context, _kHatchBg, DunesColorRole.surface),
    ink: _r(context, _kHatchInk),
  ),
);

/// 进度条：左段斜线 = 超 N 天占比，右段实心 = N 天内。
class LhBillShareBar extends StatelessWidget {
  const LhBillShareBar({
    super.key,
    required this.share,
    this.height = 5,
    this.solid = _kPlum,
  });

  final double share;
  final double height;
  final Color solid;

  @override
  Widget build(BuildContext context) {
    final s = share.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            if (s > 0)
              Expanded(
                flex: (s * 1000).round().clamp(1, 1000),
                child: _hatch(context),
              ),
            if (s < 1)
              Expanded(
                flex: ((1 - s) * 1000).round().clamp(1, 1000),
                child: ColoredBox(
                  color: _r(context, solid, DunesColorRole.surface),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 账单结束日刻度带：所有行共用 [from]–[to] 一把尺。
///   斜线段 = 早于「统计日 − N 天」的结束日，实心段 = 之后的；
///   虚线 = N 天线，深色竖线 = 统计日。
class LhBillEndTrack extends StatelessWidget {
  const LhBillEndTrack({
    super.key,
    required this.from,
    required this.to,
    required this.graceLine,
    required this.asOf,
    required this.start,
    required this.end,
    this.height = 10,
  });

  final DateTime from;
  final DateTime to;
  final DateTime graceLine;
  final DateTime asOf;
  final DateTime? start;
  final DateTime? end;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height + 6,
      child: CustomPaint(
        painter: _EndTrackPainter(
          from: from,
          to: to,
          graceLine: graceLine,
          asOf: asOf,
          start: start,
          end: end,
          barH: height,
          track: _r(context, _kTrack, DunesColorRole.surface),
          solid: _r(context, _kPlum),
          hatchBg: _r(context, _kHatchBg, DunesColorRole.surface),
          hatchInk: _r(context, _kHatchInk),
          grace: _r(context, _kGraceLine),
          asOfInk: _r(context, _kDeep),
        ),
      ),
    );
  }
}

class _EndTrackPainter extends CustomPainter {
  _EndTrackPainter({
    required this.from,
    required this.to,
    required this.graceLine,
    required this.asOf,
    required this.start,
    required this.end,
    required this.barH,
    required this.track,
    required this.solid,
    required this.hatchBg,
    required this.hatchInk,
    required this.grace,
    required this.asOfInk,
  });

  final DateTime from, to, graceLine, asOf;
  final DateTime? start, end;
  final double barH;
  final Color track, solid, hatchBg, hatchInk, grace, asOfInk;

  double _x(DateTime d, double w) {
    final span = to.difference(from).inHours.toDouble();
    if (span <= 0) return 0;
    final f = d.difference(from).inHours / span;
    return (f.clamp(0.0, 1.0) * w).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final top = (size.height - barH) / 2;
    final rr = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, top, w, barH),
      Radius.circular(barH / 2),
    );
    canvas.drawRRect(rr, Paint()..color = track);

    final s = start;
    if (s != null) {
      final e = end ?? s;
      var x0 = _x(s, w);
      var x1 = _x(e, w);
      if (x1 - x0 < 4) x1 = math.min(w, x0 + 4);
      if (x1 - x0 < 4) x0 = math.max(0, x1 - 4);
      final xg = _x(graceLine, w);
      final segTop = top + 2;
      final segH = barH - 4;
      // 斜线段
      final hEnd = math.min(x1, xg);
      if (hEnd > x0) {
        final r = Rect.fromLTRB(x0, segTop, hEnd, segTop + segH);
        canvas.save();
        canvas.clipRRect(RRect.fromRectAndRadius(r, const Radius.circular(2)));
        canvas.drawRect(r, Paint()..color = hatchBg);
        final p = Paint()
          ..color = hatchInk
          ..strokeWidth = 1.2;
        for (var x = r.left - segH; x < r.right + segH; x += 4) {
          canvas.drawLine(Offset(x, r.bottom), Offset(x + segH, r.top), p);
        }
        canvas.restore();
      }
      // 实心段
      final sStart = math.max(x0, xg);
      if (x1 > sStart) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(sStart, segTop, x1, segTop + segH),
            const Radius.circular(2),
          ),
          Paint()..color = solid,
        );
      }
    }

    // N 天线（虚线）
    final xg = _x(graceLine, w);
    final dash = Paint()
      ..color = grace
      ..strokeWidth = 1.2;
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(
        Offset(xg, y),
        Offset(xg, math.min(size.height, y + 1.6)),
        dash,
      );
    }
    // 统计日
    final xa = _x(asOf, w);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(xa - 1, 0, 2, size.height),
        const Radius.circular(1),
      ),
      Paint()..color = asOfInk,
    );
  }

  @override
  bool shouldRepaint(covariant _EndTrackPainter old) =>
      old.start != start ||
      old.end != end ||
      old.from != from ||
      old.to != to ||
      old.solid != solid;
}

/// 一组数据共用的刻度范围：最早结束日所在月 1 号 → 统计日后 3 天。
({DateTime from, DateTime to})? lhBillTrackRange(
  LhBillOutstanding data,
  List<LhBillCounterparty> rows,
) {
  final asOf = data.asOfDate;
  if (asOf == null) return null;
  DateTime? first;
  for (final r in rows) {
    final d = r.earliestEnd;
    if (d != null && (first == null || d.isBefore(first))) first = d;
  }
  first ??= asOf.subtract(const Duration(days: 90));
  final grace = data.graceLine ?? asOf;
  if (!first.isBefore(grace)) first = grace.subtract(const Duration(days: 30));
  return (
    from: DateTime(first.year, first.month, 1),
    to: asOf.add(const Duration(days: 3)),
  );
}

String _endCaption(DateTime? s, DateTime? e) {
  if (s == null) return '账单结束日为空';
  final ee = e ?? s;
  if (ee == s) return '账单结束日：${_md(s)}';
  return '最早账单结束日：${_md(s)} · 最晚账单结束日：${_md(ee)}';
}

// ── ① 资金页「账款」面板（规模 / 成本 / 利润下面）──────────────────────────

class LhBillPanel extends StatelessWidget {
  const LhBillPanel({
    super.key,
    required this.data,
    required this.focus,
    required this.onPick,
    required this.panelColor,
    required this.edgeColor,
    this.radius = 12,
  });

  final LhBillOutstanding data;

  /// 当前选中的一侧：'AR' / 'AP' / null。
  final String? focus;
  final ValueChanged<String> onPick;
  final Color panelColor;
  final Color edgeColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ink2 = _r(context, LhColors.ink2);
    final mute2 = _r(context, LhColors.mute2);
    final net = data.net;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: edgeColor, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 14,
                color: _r(context, _kPlum),
              ),
              const SizedBox(width: 5),
              Text(
                '账款',
                style: LhTypography.sans(
                  size: 12,
                  weight: FontWeight.w700,
                  color: _r(context, LhColors.ink),
                  context: context,
                ),
              ),
              const SizedBox(width: 6),
              _tag(context, data.fixture ? '资管账单 · 样例' : '资管账单'),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '只算整张未结 · 统计日 ${data.asOfShort}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: LhTypography.sans(
                    size: 9.5,
                    color: mute2,
                    context: context,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          const SizedBox(height: 6),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _cell(context, 'AR', '应收未回款', _kPlumSoft)),
                const SizedBox(width: 4),
                Expanded(child: _cell(context, 'AP', '应付未付款', _kPlum)),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(9, 7, 6, 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '净额（应收 − 应付）',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LhTypography.sans(
                            size: 10,
                            color: ink2,
                            context: context,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _amount(context, net),
                        const SizedBox(height: 3),
                        Text(
                          net == null ? '有一侧没查' : (net < 0 ? '我方净应付' : '我方净应收'),
                          style: LhTypography.sans(
                            size: 9.5,
                            color: mute2,
                            context: context,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(BuildContext context, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
    decoration: BoxDecoration(
      color: _r(context, _kPlum, DunesColorRole.surface).withAlpha(20),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      text,
      style: LhTypography.sans(
        size: 9.5,
        weight: FontWeight.w600,
        color: _r(context, const Color(0xFF5A458F)),
        context: context,
      ),
    ),
  );

  Widget _amount(BuildContext context, double? v) {
    if (v == null) {
      return Text(
        '—',
        style: LhTypography.number(
          size: 14,
          color: _r(context, LhColors.mute2),
          context: context,
        ),
      );
    }
    final s = lhBillAmount(v);
    final unit = s.endsWith('亿') || s.endsWith('万')
        ? s.substring(s.length - 1)
        : '';
    final digits = unit.isEmpty ? s : s.substring(0, s.length - 1);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: digits,
            style: LhTypography.number(
              size: 14,
              color: _r(context, LhColors.ink),
              context: context,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          TextSpan(
            text: unit,
            style: LhTypography.sans(
              size: 9.5,
              color: _r(context, LhColors.ink2),
              weight: FontWeight.w500,
              context: context,
            ),
          ),
        ],
      ),
      maxLines: 1,
    );
  }

  Widget _cell(BuildContext context, String side, String label, Color solid) {
    final t = data.totalOf(side);
    final on = focus == side;
    final ink2 = _r(context, LhColors.ink2);
    return Semantics(
      button: true,
      selected: on,
      enabled: t != null,
      label: '$label，${on ? '再点一次回到总资产' : '在上面的大数卡和图表里看'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: t == null ? null : () => onPick(side),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(9, 7, 7, 7),
          decoration: BoxDecoration(
            color: on
                ? _r(context, Colors.white, DunesColorRole.surface)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: on
                  ? _r(context, _kPlum, DunesColorRole.border).withAlpha(46)
                  : Colors.transparent,
              width: 0.8,
            ),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: const Color(0xFF5A458F).withAlpha(28),
                      blurRadius: 6,
                      offset: const Offset(0, 1.5),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LhTypography.sans(
                        size: 10,
                        color: ink2,
                        weight: on ? FontWeight.w600 : FontWeight.w500,
                        context: context,
                      ),
                    ),
                  ),
                  if (t != null)
                    Text(
                      '${_count(t.unpaidCount)} 张',
                      style: LhTypography.mono(
                        size: 9,
                        color: ink2,
                        context: context,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              _amount(context, t?.unpaidAmount),
              if (t != null) ...[
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: LhBillShareBar(
                        share: t.overdueShare,
                        height: 5,
                        solid: solid,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '超 ${data.graceDays} 天 ${(t.overdueShare * 100).round()}%',
                      style: LhTypography.mono(
                        size: 9,
                        color: ink2,
                        context: context,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── ② 大数卡底部：迷你天平 ────────────────────────────────────────────────

/// 应收在左、应付在右；横梁向金额大的一侧倾斜（对数压缩，最多 12°），
/// 换数据时摆一下落定。点它打开明细。
class LhBillMiniBalance extends StatelessWidget {
  const LhBillMiniBalance({super.key, required this.data, this.onTap});

  final LhBillOutstanding data;
  final VoidCallback? onTap;

  double get _tilt {
    final r = data.receivable?.unpaidAmount ?? 0;
    final p = data.payable?.unpaidAmount ?? 0;
    if (r <= 0 && p <= 0) return 0;
    final ratio = (p + 1) / (r + 1);
    final deg = (math.log(ratio) / math.ln10 * 8).clamp(-12.0, 12.0);
    return deg * math.pi / 180;
  }

  @override
  Widget build(BuildContext context) {
    final deep = _r(context, _kDeep);
    final mute2 = _r(context, LhColors.mute2);
    final net = data.net;
    final disable = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    TextStyle small(Color c, {bool bold = false}) => LhTypography.mono(
      size: 9.5,
      color: c,
      weight: bold ? FontWeight.w700 : FontWeight.w500,
      context: context,
    );
    return Semantics(
      button: onTap != null,
      label: '应收应付天平，查看按对方明细',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 0.7,
              color: _r(context, _kLine, DunesColorRole.surface),
            ),
            const SizedBox(height: 5),
            SizedBox(
              height: 34,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('应收', style: small(mute2)),
                        Text(
                          data.receivable == null
                              ? '—'
                              : lhBillAmount(data.receivable!.unpaidAmount),
                          style: small(deep, bold: true),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('应付', style: small(mute2)),
                        Text(
                          data.payable == null
                              ? '—'
                              : lhBillAmount(data.payable!.unpaidAmount),
                          style: small(deep, bold: true),
                        ),
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: 92,
                      height: 34,
                      child: Stack(
                        alignment: Alignment.topCenter,
                        children: [
                          Positioned(
                            top: 10,
                            child: CustomPaint(
                              size: const Size(12, 24),
                              painter: _FulcrumPainter(
                                _r(
                                  context,
                                  const Color(0xFFE4DCF4),
                                  DunesColorRole.surface,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: _tilt),
                              duration: disable
                                  ? Duration.zero
                                  : const Duration(milliseconds: 1100),
                              curve: Curves.elasticOut,
                              builder: (context, a, child) =>
                                  Transform.rotate(angle: a, child: child),
                              child: Container(
                                width: 86,
                                height: 3,
                                decoration: BoxDecoration(
                                  color: deep,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: _r(
                                  context,
                                  Colors.white,
                                  DunesColorRole.surface,
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(color: deep, width: 1.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    net == null
                        ? '按对方查看'
                        : '${net < 0 ? '净应付' : '净应收'} ${lhBillAmount(net.abs())} · 按对方查看',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: LhTypography.sans(
                      size: 9,
                      color: deep,
                      weight: FontWeight.w600,
                      height: 1.0,
                      context: context,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 14,
                  color: _r(context, _kPlum),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FulcrumPainter extends CustomPainter {
  const _FulcrumPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _FulcrumPainter old) => old.color != color;
}

// ── ③ 右卡「构成」：按对方 ─────────────────────────────────────────────────

/// 走势 / 构成 切换的占位：资管只给当天快照，「走势」置灰。
class LhBillSnapshotSegment extends StatelessWidget {
  const LhBillSnapshotSegment({super.key});

  @override
  Widget build(BuildContext context) {
    Widget seg(String t, bool on) => Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on
            ? _r(context, Colors.white, DunesColorRole.surface)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        t,
        style: LhTypography.sans(
          size: 11,
          weight: on ? FontWeight.w700 : FontWeight.w500,
          color: on
              ? _r(context, LhColors.ink)
              : _r(context, LhColors.mute2).withAlpha(140),
          context: context,
        ),
      ),
    );
    return Semantics(
      label: '只有当天快照，暂无走势',
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: _r(context, const Color(0xFFEEE8FB), DunesColorRole.surface),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [seg('走势', false), seg('构成', true)],
        ),
      ),
    );
  }
}

Widget _fill(bool bounded, Widget child) => bounded
    ? Expanded(
        child: Align(alignment: Alignment.topCenter, child: child),
      )
    : child;

class LhBillMix extends StatelessWidget {
  const LhBillMix({
    super.key,
    required this.data,
    required this.side,
    required this.onSideChanged,
    required this.onOpenAll,
  });

  final LhBillOutstanding data;
  final String side;
  final ValueChanged<String> onSideChanged;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final rows = data.counterparties(side);
    final range = lhBillTrackRange(data, rows);
    final ink2 = _r(context, LhColors.ink2);
    final mute2 = _r(context, LhColors.mute2);
    final solid = side == 'AP' ? _kPlum : _kPlumSoft;
    return LayoutBuilder(
      builder: (context, box) {
        // 窄（手机）：名字 + 金额一行、金额条一行，刻度带进明细；宽：四列。
        final wide = box.maxWidth >= 380;
        final rowH = wide ? 30.0 : 38.0;
        final headH = 26.0 + (wide ? 18 : 0);
        final footH = 22.0;
        final bounded = box.maxHeight.isFinite;
        final int fit = bounded
            ? ((box.maxHeight - headH - footH) / rowH)
                  .floor()
                  .clamp(1, 8)
                  .toInt()
            : 6;
        final shown = rows.take(fit).toList();
        final rest = rows.length - shown.length;
        var max = 0.0;
        for (final r in rows) {
          max = math.max(max, r.unpaidAmount.abs());
        }
        if (max <= 0) max = 1;

        Widget chip(String key, String label, Color c) {
          final on = side == key;
          final t = data.totalOf(key);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: t == null ? null : () => onSideChanged(key),
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: _r(
                  context,
                  on ? const Color(0xFFE9E3F8) : const Color(0xFFF3F0F8),
                  DunesColorRole.surface,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 3,
                    decoration: BoxDecoration(
                      color: _r(context, c),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: LhTypography.sans(
                      size: 11,
                      weight: on ? FontWeight.w700 : FontWeight.w500,
                      color: on ? _r(context, _kDeep) : ink2,
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        Widget amountBar(LhBillCounterparty r) => Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (r.unpaidAmount.abs() / max)
                .clamp(0.04, 1.0)
                .toDouble(),
            child: LhBillShareBar(
              share: r.overdueShare,
              height: 9,
              solid: solid,
            ),
          ),
        );

        Widget amountText(LhBillCounterparty r) => Text(
          lhBillAmount(r.unpaidAmount),
          maxLines: 1,
          textAlign: TextAlign.right,
          style: LhTypography.mono(
            size: 11,
            weight: FontWeight.w700,
            color: _r(context, LhColors.ink),
            context: context,
          ),
        );

        Widget name(LhBillCounterparty r) => Text(
          r.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: LhTypography.sans(
            size: 11,
            weight: FontWeight.w600,
            color: _r(context, LhColors.ink),
            context: context,
          ),
        );

        final asOf = data.asOfDate;
        final grace = data.graceLine;
        final hasTrack = wide && range != null && asOf != null && grace != null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                chip('AP', '应付', _kPlum),
                const SizedBox(width: 6),
                chip('AR', '应收', _kPlumSoft),
                const Spacer(),
                SizedBox(width: 12, height: 7, child: _hatch(context)),
                const SizedBox(width: 4),
                Text(
                  '结束日超 ${data.graceDays} 天',
                  style: LhTypography.sans(
                    size: 9.5,
                    color: ink2,
                    context: context,
                  ),
                ),
              ],
            ),
            if (hasTrack)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const SizedBox(width: 84),
                    const Spacer(),
                    SizedBox(
                      width: 150,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _md(range!.from),
                            style: LhTypography.mono(
                              size: 8.5,
                              color: mute2,
                              context: context,
                            ),
                          ),
                          Text(
                            '统计日 ${_md(asOf!)}',
                            style: LhTypography.mono(
                              size: 8.5,
                              color: mute2,
                              context: context,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 2),
            if (rows.isEmpty)
              _fill(
                bounded,
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '这一侧没有未结账单',
                      style: LhTypography.sans(
                        size: 11,
                        color: mute2,
                        context: context,
                      ),
                    ),
                  ),
                ),
              )
            else
              _fill(
                bounded,
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final r in shown)
                      Container(
                        height: rowH,
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: _r(context, _kLine, DunesColorRole.border),
                              width: 0.6,
                            ),
                          ),
                        ),
                        child: wide
                            ? Row(
                                children: [
                                  SizedBox(width: 84, child: name(r)),
                                  const SizedBox(width: 8),
                                  Expanded(child: amountBar(r)),
                                  const SizedBox(width: 8),
                                  SizedBox(width: 64, child: amountText(r)),
                                  if (hasTrack) ...[
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      width: 150,
                                      child: LhBillEndTrack(
                                        from: range!.from,
                                        to: range!.to,
                                        graceLine: grace!,
                                        asOf: asOf!,
                                        start: r.earliestEnd,
                                        end: r.latestEnd,
                                        height: 8,
                                      ),
                                    ),
                                  ],
                                ],
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(child: name(r)),
                                      const SizedBox(width: 6),
                                      amountText(r),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  amountBar(r),
                                ],
                              ),
                      ),
                  ],
                ),
              ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenAll,
              child: SizedBox(
                height: footH,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        rest > 0
                            ? '还有 $rest 个对方 · 按对方查看全部'
                            : (hasTrack
                                  ? '右列：账单结束日范围（虚线 = 统计日前 ${data.graceDays} 天）'
                                  : '按对方查看明细'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LhTypography.sans(
                          size: 9.5,
                          color: mute2,
                          context: context,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: _r(context, _kPlum),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── ④ 整页明细：按对方 ───────────────────────────────────────────────────

Future<void> showLighthouseBillOutstandingSheet(
  BuildContext context,
  LhBillOutstanding data, {
  String? initialSide,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'lighthouse-bill-outstanding'),
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, animation, secondaryAnimation) =>
          _BillSheet(data: data, initialSide: initialSide),
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) =>
          SlideTransition(
            position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  ),
                ),
            child: child,
          ),
    ),
  );
}

class _BillSheet extends StatefulWidget {
  const _BillSheet({required this.data, this.initialSide});

  final LhBillOutstanding data;
  final String? initialSide;

  @override
  State<_BillSheet> createState() => _BillSheetState();
}

class _BillSheetState extends State<_BillSheet> {
  late String _side =
      widget.initialSide ?? (widget.data.payable != null ? 'AP' : 'AR');
  bool _overdueOnly = false;
  bool _caliberOpen = false;
  final Set<String> _expanded = <String>{};

  Color _c(Color v, [DunesColorRole r = DunesColorRole.foreground]) =>
      DunesColors.resolve(context, v, role: r);

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final total = data.totalOf(_side);
    final rows = data.counterparties(_side, overdueOnly: _overdueOnly);
    final n = data.graceDays;
    return Scaffold(
      backgroundColor: _c(LhColors.mist, DunesColorRole.surface),
      body: SafeArea(
        child: Column(
          children: [
            _topBar(data),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                children: [
                  _segment(),
                  const SizedBox(height: 10),
                  if (total != null) _summary(total, n, rows.length),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(
                        '往来对方',
                        style: LhTypography.sans(
                          size: 14,
                          weight: FontWeight.w700,
                          color: _c(LhColors.ink),
                          context: context,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${rows.length} 个 · 按未结金额排序',
                        style: LhTypography.sans(
                          size: 10.5,
                          color: _c(LhColors.mute2),
                          context: context,
                        ),
                      ),
                      const Spacer(),
                      _overdueToggle(n),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < rows.length; i++) _card(i, rows[i]),
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Text(
                          _overdueOnly ? '没有结束日超 $n 天的账款' : '这一侧没有未结账款',
                          style: LhTypography.sans(
                            size: 12,
                            color: _c(LhColors.mute2),
                            context: context,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  _caliber(n),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar(LhBillOutstanding data) => Container(
    padding: const EdgeInsets.fromLTRB(6, 8, 14, 10),
    decoration: BoxDecoration(
      color: _c(Colors.white, DunesColorRole.surface),
      border: Border(
        bottom: BorderSide(
          color: _c(LhColors.line2, DunesColorRole.border),
          width: 0.7,
        ),
      ),
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: '返回',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '未结账款',
                style: LhTypography.sans(
                  size: 17,
                  weight: FontWeight.w700,
                  color: _c(LhColors.ink),
                  context: context,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '资管账单 · 统计日 ${data.asOf.isEmpty ? '—' : data.asOf}',
                style: LhTypography.sans(
                  size: 10.5,
                  color: _c(LhColors.mute2),
                  context: context,
                ),
              ),
            ],
          ),
        ),
        if (data.fixture)
          Text(
            '样例数据',
            style: LhTypography.sans(
              size: 10.5,
              color: _c(_kSample),
              context: context,
            ),
          ),
      ],
    ),
  );

  Widget _segment() {
    Widget seg(String key, String label, LhBillTotal? t) {
      final on = _side == key;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: t == null
              ? null
              : () => setState(() {
                  _side = key;
                  _expanded.clear();
                }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on
                  ? _c(Colors.white, DunesColorRole.surface)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: on
                  ? const [
                      BoxShadow(
                        color: Color(0x124A3A7A),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              t == null
                  ? '$label · 未查询'
                  : '$label · ${_count(t.unpaidCount)} 张',
              style: LhTypography.sans(
                size: 12,
                weight: on ? FontWeight.w700 : FontWeight.w500,
                color: _c(on ? _kDeep : LhColors.ink2),
                context: context,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _c(LhColors.purpleSoft, DunesColorRole.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _c(const Color(0xFFE2D8F0), DunesColorRole.border),
          width: 0.7,
        ),
      ),
      child: Row(
        children: [
          seg('AP', '应付未付款', widget.data.payable),
          seg('AR', '应收未回款', widget.data.receivable),
        ],
      ),
    );
  }

  Widget _summary(LhBillTotal t, int n, int counterpartyCount) {
    TextStyle small(Color col) =>
        LhTypography.sans(size: 10.5, color: _c(col), context: context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: _c(Colors.white, DunesColorRole.surface),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _c(const Color(0xFFE9E3F5), DunesColorRole.border),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _side == 'AP' ? '应付未付款' : '应收未回款',
            style: LhTypography.sans(
              size: 11,
              weight: FontWeight.w600,
              color: _c(LhColors.ink2),
              context: context,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                lhBillAmount(t.unpaidAmount),
                style: LhTypography.number(
                  size: 28,
                  color: _c(_kDeep),
                  context: context,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_count(t.unpaidCount)} 张账单 · $counterpartyCount 个往来对方',
            style: small(LhColors.mute2),
          ),
          const SizedBox(height: 13),
          LhBillShareBar(share: t.overdueShare, height: 6),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('其中结束日超 $n 天', style: small(LhColors.ink2))),
              Text(
                '${lhBillAmount(t.overdueAmount)} · ${(t.overdueShare * 100).round()}%',
                style: LhTypography.number(
                  size: 13,
                  color: _c(_kDeep),
                  context: context,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_count(t.overdueCount)} 张 · 临时判断口径，不代表合同违约',
            style: small(LhColors.mute2),
          ),
        ],
      ),
    );
  }

  Widget _overdueToggle(int n) {
    final on = _overdueOnly;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _overdueOnly = !on),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _c(
              on ? const Color(0xFFF0ECF6) : Colors.white,
              DunesColorRole.surface,
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: _c(
                on ? const Color(0x737B5CD8) : const Color(0xFFE4DCF4),
                DunesColorRole.border,
              ),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 12, height: 7, child: _hatch(context)),
              const SizedBox(width: 5),
              Text(
                '只看结束日超 $n 天',
                style: LhTypography.sans(
                  size: 11.5,
                  weight: on ? FontWeight.w700 : FontWeight.w500,
                  color: _c(on ? _kDeep : LhColors.ink2),
                  context: context,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(int index, LhBillCounterparty r) {
    final n = widget.data.graceDays;
    final match = r.matchLabel;
    final open = _expanded.contains(r.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _c(Colors.white, DunesColorRole.surface),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: _c(const Color(0xFFE9E3F5), DunesColorRole.border),
            width: 0.8,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() {
                if (open) {
                  _expanded.remove(r.name);
                } else {
                  _expanded.add(r.name);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 10, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _c(
                              LhColors.purpleSoft,
                              DunesColorRole.surface,
                            ),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            (index + 1).toString().padLeft(2, '0'),
                            style: LhTypography.mono(
                              size: 10,
                              weight: FontWeight.w700,
                              color: _c(_kPlum),
                              context: context,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: LhTypography.sans(
                                  size: 13.5,
                                  weight: FontWeight.w700,
                                  color: _c(LhColors.ink),
                                  context: context,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${_count(r.billCount)} 张账单 · ${r.groups.length} 种类型',
                                style: LhTypography.sans(
                                  size: 10.5,
                                  color: _c(LhColors.mute2),
                                  context: context,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              lhBillAmount(r.unpaidAmount),
                              style: LhTypography.number(
                                size: 15,
                                color: _c(LhColors.ink),
                                context: context,
                              ),
                            ),
                            const SizedBox(height: 4),
                            AnimatedRotation(
                              turns: open ? 0.5 : 0,
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 19,
                                color: _c(_kPlum),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LhBillShareBar(share: r.overdueShare, height: 5),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.overdueAmount > 0
                                ? '其中超 $n 天 ${lhBillAmount(r.overdueAmount)}'
                                : '没有结束日超 $n 天的账款',
                            style: LhTypography.sans(
                              size: 10.5,
                              color: _c(LhColors.ink2),
                              context: context,
                            ),
                          ),
                        ),
                        if (r.overdueAmount > 0)
                          Text(
                            '${(r.overdueShare * 100).round()}%',
                            style: LhTypography.mono(
                              size: 10.5,
                              weight: FontWeight.w700,
                              color: _c(_kDeep),
                              context: context,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _endCaption(r.earliestEnd, r.latestEnd),
                      style: LhTypography.sans(
                        size: 10,
                        color: _c(LhColors.mute2),
                        context: context,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity),
              secondChild: _billDetails(r, match, n),
              crossFadeState: open
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
              sizeCurve: Curves.easeOutCubic,
            ),
          ],
        ),
      ),
    );
  }

  Widget _billDetails(LhBillCounterparty r, String match, int n) => Container(
    margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
    padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
    decoration: BoxDecoration(
      color: _c(const Color(0xFFF7F6FA), DunesColorRole.surface),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '账单类型明细',
              style: LhTypography.sans(
                size: 11,
                weight: FontWeight.w700,
                color: _c(LhColors.ink2),
                context: context,
              ),
            ),
            const Spacer(),
            Text(
              match.isEmpty ? '省份未识别' : '匹配省份 · $match',
              style: LhTypography.sans(
                size: 10,
                color: _c(match.isEmpty ? LhColors.mute2 : _kPlum),
                context: context,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        for (var i = 0; i < r.groups.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: _c(LhColors.line2, DunesColorRole.border),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.groups[i].billType.isEmpty
                            ? '未填写账单类型'
                            : r.groups[i].billType,
                        style: LhTypography.sans(
                          size: 11.5,
                          weight: FontWeight.w600,
                          color: _c(LhColors.ink),
                          context: context,
                        ),
                      ),
                    ),
                    Text(
                      lhBillAmount(r.groups[i].unpaidAmount),
                      style: LhTypography.number(
                        size: 12.5,
                        color: _c(LhColors.ink),
                        context: context,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_count(r.groups[i].billCount)} 张 · 其中超 $n 天 '
                  '${lhBillAmount(r.groups[i].overdueAmount)}',
                  style: LhTypography.sans(
                    size: 10.5,
                    color: _c(LhColors.ink2),
                    context: context,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _endCaption(r.groups[i].earliestEnd, r.groups[i].latestEnd),
                  style: LhTypography.sans(
                    size: 10,
                    color: _c(LhColors.mute2),
                    context: context,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _caliber(int n) {
    final data = widget.data;
    return Material(
      color: _c(Colors.white, DunesColorRole.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _c(const Color(0xFFE9E3F5), DunesColorRole.border),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _caliberOpen = !_caliberOpen),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: _c(_kPlum)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '数据口径与范围',
                      style: LhTypography.sans(
                        size: 11.5,
                        weight: FontWeight.w600,
                        color: _c(LhColors.ink2),
                        context: context,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _caliberOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: _c(LhColors.mute2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(
                    height: 1,
                    color: _c(LhColors.line2, DunesColorRole.border),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '只含状态为「未回款」「未付款」的整张账单，部分回款、部分付款不在内。\n'
                    '“结束日超 $n 天”按账单结束日 + $n 天的临时规则判断，不代表合同违约；结束日为空的不计入。\n'
                    '应收返利取自石油拆分对账窗，折后付款不产生应收账单。\n'
                    '电子券采购款的应付账单目前止于 2026-08-31，之后的业务还没出账单（以资管说明为准）。\n'
                    '匹配省份由灯塔按主体表补充，同一对方分属多个省时不挂。',
                    style: LhTypography.sans(
                      size: 10.5,
                      color: _c(LhColors.ink2),
                      height: 1.65,
                      context: context,
                    ),
                  ),
                  if (data.fixture) ...[
                    const SizedBox(height: 6),
                    Text(
                      '样例数据：应付分组只示意一部分，加起来不等于合计。',
                      style: LhTypography.sans(
                        size: 10.5,
                        color: _c(_kSample),
                        context: context,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            crossFadeState: _caliberOpen
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
            sizeCurve: Curves.easeOutCubic,
          ),
        ],
      ),
    );
  }
}
