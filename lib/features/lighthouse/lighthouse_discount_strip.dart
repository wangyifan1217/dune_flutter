import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_discount_metric.dart';
import 'lighthouse_theme.dart';

// ════════════════════════════════════════════════════════════════════════
// 供给方卡片底边的折扣细条（2026-11-10）
//
//   一张供给方卡片 = 一个省，同时挂着中石油 / 中石化；折扣规则是按「湖南中石油」
//   「湖南中石化」分开签的，所以底边最多两段，左中石油、右中石化，各一根 2px 细线 + 一行小字。
//   只用紫的明度区分状态：档内浅紫、快过档稍深、封顶更淡，不加色块不加徽标。
//   数据只读 /lighthouse/discounts（按规则周期，不随日周月筛选），金额不重算。
//
//   旧的冻结列折扣条（lighthouseLedgerShowsDiscountUi）每行一套手势 + 展开卡，
//   在 Flutter Web 非虚拟化账本上会卡死；这里每段只有 Text + CustomPaint，一个点击。
// ════════════════════════════════════════════════════════════════════════

/// 供给方卡片阶梯价格（折叠条 + 展开卡）总开关。
const bool lighthouseSupplyDiscountStripEnabled = true;

/// 第一次进供给方时默认选中的分类。
const String lighthouseSupplyDefaultGroup = '中石油';

const Color _kTrack = Color(0xFFEFEBF6);
const Color _kFill = Color(0xFFB5AAD5);
const Color _kFillNear = Color(0xFF9C8CD0);
const Color _kFillCapped = Color(0xFFDCD5EC);
const Color _kText = Color(0xFF6E6C66);

enum LhDiscountLineTone { normal, near, capped, fixed }

/// 底边一段：一家供应商（省份 × 中石油 / 中石化）的主规则本期进度。
class LhSupplyDiscountLine {
  const LhSupplyDiscountLine({
    required this.group,
    required this.progress,
    required this.ticks,
    required this.text,
    required this.tone,
    required this.ruleId,
    required this.supplierKey,
  });

  final String group;
  final double progress;
  final List<double> ticks;
  final String text;
  final LhDiscountLineTone tone;
  final String ruleId;
  final String supplierKey;
}

double? _num(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

int? _int(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// 规则周期名：规则名带「年阶梯」→ 年阶梯；带「月阶梯」或周期不到 40 天 → 「11月阶梯」。
String lighthouseDiscountPeriodLabel(Map<String, dynamic> d) {
  final name = d['ruleName']?.toString() ?? '';
  final start = DateTime.tryParse(d['periodStartTime']?.toString() ?? '');
  final end = DateTime.tryParse(d['periodEndTime']?.toString() ?? '');
  if (name.contains('年阶梯')) return '年阶梯';
  final monthly =
      name.contains('月阶梯') ||
      (start != null && end != null && end.difference(start).inDays < 40);
  // 周期常是「10.31–11.30」这种跨月写法，按中点取月份，不能直接用开始月。
  if (monthly && start != null && end != null) {
    final mid = start.add(Duration(milliseconds: end.difference(start).inMilliseconds ~/ 2));
    return '${mid.toLocal().month}月阶梯';
  }
  if (monthly && start != null) return '${start.toLocal().month}月阶梯';
  if (monthly) return '月阶梯';
  if (start != null && end != null) return '年阶梯';
  return '阶梯';
}

/// 由 /discounts 的一条（DiscountInfo）拼出底边的一段。null = 没有可画的进度。
LhSupplyDiscountLine? lighthouseSupplyDiscountLineOf(
  String group,
  String supplierKey,
  Map<String, dynamic> d,
) {
  final status = d['status']?.toString() ?? '';
  final level = _int(d['tierLevel']) ?? 0;
  final rate = _num(d['discountRate']);
  final nextPermille = _num(d['nextRate']) ?? _num(d['nextTier']);
  final next = _num(d['next_threshold']) ?? _num(d['target']);
  final gap = _num(d['salesToNextTier']) ?? _num(d['gap_to_next']);
  final ruleCount = _int(d['ruleCount']) ?? 1;
  final ruleId = d['ruleId']?.toString() ?? '';
  final period = lighthouseDiscountPeriodLabel(d);
  final rateLabel = rate == null ? '' : ' ${lighthouseDiscountRateLabel(rate)}';
  final more = ruleCount > 1 ? ' · +${ruleCount - 1} 条' : '';

  if (status == 'capped') {
    return LhSupplyDiscountLine(
      group: group,
      progress: 1,
      ticks: const [],
      text: '$period 已封顶$rateLabel$more',
      tone: LhDiscountLineTone.capped,
      ruleId: ruleId,
      supplierKey: supplierKey,
    );
  }
  if (status == 'fixed') {
    return LhSupplyDiscountLine(
      group: group,
      progress: 0,
      ticks: const [],
      text: '固定$rateLabel$more',
      tone: LhDiscountLineTone.fixed,
      ruleId: ruleId,
      supplierKey: supplierKey,
    );
  }
  final cum = _num(d['currentCumSales']) ?? _num(d['statAmount']) ?? 0;
  if (next == null || next <= 0) {
    if (cum <= 0 && level <= 0) return null;
    return LhSupplyDiscountLine(
      group: group,
      progress: 0,
      ticks: const [],
      text: '$period${level > 0 ? ' 第$level档' : ''}$rateLabel$more',
      tone: LhDiscountLineTone.normal,
      ruleId: ruleId,
      supplierKey: supplierKey,
    );
  }
  final progress = (_num(d['currentProgress']) ?? (cum / next)).clamp(0.0, 1.0).toDouble();
  // 白色刻度 = 已经过掉的档位门槛（第 2 档起），位置按「门槛 ÷ 下一档门槛」。
  final ticks = <double>[];
  final tiers = d['tiers'];
  if (tiers is List) {
    for (final t in tiers) {
      if (t is! Map) continue;
      final lv = _int(t['level']) ?? 0;
      final min = _num(t['minValue']) ?? 0;
      if (lv <= 1 || lv > level || min <= 0 || min >= next) continue;
      ticks.add(min / next);
    }
  }
  final nextLabel = nextPermille == null
      ? ''
      : '到 ${lighthouseDiscountRateLabel(nextPermille / 1000)}';
  final gapLabel = gap == null ? '' : ' · 差 ${lighthouseDiscountCompactWan(gap)}$nextLabel';
  return LhSupplyDiscountLine(
    group: group,
    progress: progress,
    ticks: ticks,
    text: '$period${level > 0 ? ' 第$level档' : ''}$rateLabel$gapLabel$more',
    tone: progress >= 0.9 ? LhDiscountLineTone.near : LhDiscountLineTone.normal,
    ruleId: ruleId,
    supplierKey: supplierKey,
  );
}

/// 一张供给方卡片要画的段：卡片带分类（标签二选了中石油）就只看这一家，
/// 省份合并卡按 supplyGroups 逐家找，缺省按中石油、中石化两家找。
List<LhSupplyDiscountLine> lighthouseSupplyDiscountLines({
  required Map<String, dynamic> discountsByName,
  required String rowName,
  String rowGroup = '',
  Object? supplyGroups,
}) {
  if (discountsByName.isEmpty) return const [];
  final groups = <String>[];
  final g = rowGroup.trim();
  if (g.isNotEmpty) {
    groups.add(g);
  } else if (supplyGroups is List && supplyGroups.isNotEmpty) {
    for (final x in supplyGroups) {
      final s = x?.toString().trim() ?? '';
      if (s.isNotEmpty && !groups.contains(s)) groups.add(s);
    }
  } else {
    groups.addAll(const ['中石油', '中石化']);
  }
  final out = <LhSupplyDiscountLine>[];
  for (final group in groups) {
    final key = lighthouseDiscountSupplyMatchKey(rowName, group);
    if (key.isEmpty) continue;
    final raw = discountsByName[key];
    if (raw is! Map) continue;
    final line = lighthouseSupplyDiscountLineOf(
      group,
      key,
      Map<String, dynamic>.from(raw),
    );
    if (line != null) out.add(line);
    if (out.length == 2) break;
  }
  return out;
}

/// 卡片底边那条窄带。[onTapLine] 点某一段（带规则 ID）。
class LhSupplyDiscountStrip extends StatelessWidget {
  const LhSupplyDiscountStrip({
    super.key,
    required this.lines,
    this.onTapLine,
    this.scale = 1,
  });

  final List<LhSupplyDiscountLine> lines;
  final ValueChanged<LhSupplyDiscountLine>? onTapLine;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final divider = DunesColors.resolve(
      context,
      const Color(0xFFF1EEF6),
      role: DunesColorRole.border,
    );
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: divider, width: 1))),
      padding: EdgeInsets.fromLTRB(14 * scale, 6 * scale, 14 * scale, 8 * scale),
      child: Row(
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) SizedBox(width: 20 * scale),
            Expanded(
              child: i < lines.length
                  ? _segment(context, lines[i])
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, LhSupplyDiscountLine line) {
    final ink = DunesColors.resolve(context, _kText);
    final style = LhTypography.mono(
      context: context,
      size: 10.5 * scale,
      color: ink,
      weight: FontWeight.w400,
    );
    final fill = switch (line.tone) {
      LhDiscountLineTone.near => _kFillNear,
      LhDiscountLineTone.capped => _kFillCapped,
      LhDiscountLineTone.fixed => _kTrack,
      LhDiscountLineTone.normal => _kFill,
    };
    final body = Semantics(
      button: onTapLine != null && line.ruleId.isNotEmpty,
      label: '${line.group}折扣进度：${line.text}',
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 22 * scale),
        child: Row(
          children: [
            Text(line.group, style: style),
            SizedBox(width: 8 * scale),
            SizedBox(
              width: 120 * scale,
              height: 2,
              child: CustomPaint(
                painter: _ThinBarPainter(
                  progress: line.progress,
                  ticks: line.ticks,
                  track: DunesColors.resolve(context, _kTrack, role: DunesColorRole.border),
                  fill: DunesColors.resolve(context, fill),
                  tick: DunesColors.resolve(context, Colors.white, role: DunesColorRole.surface),
                ),
              ),
            ),
            SizedBox(width: 8 * scale),
            Expanded(
              child: Text(
                line.text,
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
    if (onTapLine == null || line.ruleId.isEmpty) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTapLine!(line),
        child: body,
      ),
    );
  }
}

/// 2px 细线：底色 + 已走部分 + 白色档位刻度。业务页的阶梯细线也用它。
class LhThinProgressBar extends StatelessWidget {
  const LhThinProgressBar({
    super.key,
    required this.progress,
    this.ticks = const [],
    this.color = _kFill,
    this.height = 2,
  });

  final double progress;
  final List<double> ticks;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _ThinBarPainter(
          progress: progress,
          ticks: ticks,
          track: DunesColors.resolve(context, _kTrack, role: DunesColorRole.border),
          fill: DunesColors.resolve(context, color),
          tick: DunesColors.resolve(context, Colors.white, role: DunesColorRole.surface),
        ),
      ),
    );
  }
}

class _ThinBarPainter extends CustomPainter {
  _ThinBarPainter({
    required this.progress,
    required this.ticks,
    required this.track,
    required this.fill,
    required this.tick,
  });

  final double progress;
  final List<double> ticks;
  final Color track;
  final Color fill;
  final Color tick;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, r),
      Paint()..color = track,
    );
    final w = size.width * progress.clamp(0.0, 1.0);
    if (w > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r),
        Paint()..color = fill,
      );
    }
    final p = Paint()..color = tick;
    for (final t in ticks) {
      if (t <= 0 || t >= 1) continue;
      canvas.drawRect(Rect.fromLTWH(size.width * t, 0, 1, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_ThinBarPainter old) =>
      old.progress != progress ||
      old.fill != fill ||
      old.track != track ||
      old.ticks.length != ticks.length;
}

// ════════════════════════════════════════════════════════════════════════
// 供给方卡片「阶梯」折叠条 + 展开卡（2026-11-10 · 第二版）
//
//   和产品的「细分 N · … 展开」同一个样子：卡片底部一条折叠条，摘要写主规则进度；
//   展开后每条规则一张卡挂在父卡片下方（左侧一根引导线），卡上「详情 ›」才去业务阶梯详情。
//   一家供应商多条规则时：主规则在前，otherRules 依次跟上，每条各算各的，不相加。
// ════════════════════════════════════════════════════════════════════════

/// 展开区的一张卡：一条规则。
class LhSupplyTierRule {
  const LhSupplyTierRule({
    required this.group,
    required this.supplierKey,
    required this.data,
    required this.line,
  });

  final String group;
  final String supplierKey;
  final Map<String, dynamic> data;
  final LhSupplyDiscountLine line;

  String get ruleId => data['ruleId']?.toString() ?? '';
}

/// 一张供给方卡片能展开的全部规则：按 supplyGroups 逐家找，每家主规则 + otherRules。
List<LhSupplyTierRule> lighthouseSupplyTierRules({
  required Map<String, dynamic> discountsByName,
  required String rowName,
  String rowGroup = '',
  Object? supplyGroups,
}) {
  if (discountsByName.isEmpty) return const [];
  final groups = <String>[];
  final g = rowGroup.trim();
  if (g.isNotEmpty) {
    groups.add(g);
  } else if (supplyGroups is List && supplyGroups.isNotEmpty) {
    for (final x in supplyGroups) {
      final s = x?.toString().trim() ?? '';
      if (s.isNotEmpty && !groups.contains(s)) groups.add(s);
    }
  } else {
    groups.addAll(const ['中石油', '中石化']);
  }
  final out = <LhSupplyTierRule>[];
  for (final group in groups) {
    final key = lighthouseDiscountSupplyMatchKey(rowName, group);
    if (key.isEmpty) continue;
    final raw = discountsByName[key];
    if (raw is! Map) continue;
    final primary = Map<String, dynamic>.from(raw);
    final all = <Map<String, dynamic>>[primary];
    final others = primary['otherRules'];
    if (others is List) {
      for (final o in others) {
        if (o is Map) all.add(Map<String, dynamic>.from(o));
      }
    }
    for (final d in all) {
      final line = lighthouseSupplyDiscountLineOf(group, key, d);
      if (line == null) continue;
      out.add(LhSupplyTierRule(group: group, supplierKey: key, data: d, line: line));
    }
  }
  return out;
}

/// 折叠条摘要：一家时直接写主规则那句；两家时「中石油 第2档… · 中石化 已封顶」。
String lighthouseSupplyTierPreview(List<LhSupplyTierRule> rules) {
  if (rules.isEmpty) return '';
  final firstByGroup = <String, LhSupplyTierRule>{};
  for (final r in rules) {
    firstByGroup.putIfAbsent(r.group, () => r);
  }
  if (firstByGroup.length == 1) {
    final r = firstByGroup.values.first;
    return r.line.text.replaceFirst(RegExp(r' · \+\d+ 条$'), '');
  }
  return firstByGroup.values
      .map((r) => '${r.group} ${r.line.text.replaceFirst(RegExp(r' · \+\d+ 条$'), '')}')
      .join('；');
}

String _lhMd(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

String _lhHm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 本期已过天数、总天数、到期末的预测累计、到下一档的日期（周期内到不了为 null）。
/// 2026-11-11 起不再自己按毫秒外推，统一读 [lighthouseTierPaceOf]（后端 discount_pace.go
/// 下发的近 7 日节奏；老后端时本地同口径退化），和冻结列、筛选、阶梯看板是同一个数。
({int day, int days, double projected, DateTime? eta}) _lhTierPace(Map<String, dynamic> d, double cum, double? next) {
  final p = lighthouseTierPaceOf(d);
  if (p == null) return (day: 0, days: 0, projected: cum, eta: null);
  return (
    day: p.elapsedDays,
    days: p.totalDays,
    projected: p.projectedCum,
    eta: next == null ? null : p.eta,
  );
}

/// 展开区的一张规则卡（方案 A · 刻度尺）：进度条按金额等比例，实色 = 已发生，虚线 = 按日均到月底。
/// 字号一律不大于外面账本卡片（数值 11.5 / 标签 10 / 单位 9，再乘账本缩放）。
class LhSupplyTierCard extends StatelessWidget {
  const LhSupplyTierCard({
    super.key,
    required this.rule,
    this.onDetail,
    this.scale = 1,
  });

  final LhSupplyTierRule rule;
  final VoidCallback? onDetail;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final d = rule.data;
    final ink = DunesColors.resolve(context, const Color(0xFF1F2421));
    final ink2 = DunesColors.resolve(context, const Color(0xFF5A5C56));
    final mute = DunesColors.resolve(context, _kText);
    final deep = DunesColors.resolve(context, const Color(0xFF5A458F));
    final hero = DunesColors.resolve(context, const Color(0xFF2B2147));
    final start = DateTime.tryParse(d['periodStartTime']?.toString() ?? '')?.toLocal();
    final end = DateTime.tryParse(d['periodEndTime']?.toString() ?? '')?.toLocal();
    final calc = DateTime.tryParse(d['calcTime']?.toString() ?? '')?.toLocal();
    final name = (d['ruleName']?.toString() ?? '').trim();
    final period = lighthouseDiscountPeriodLabel(d);
    final title = name.isEmpty ? '${rule.group} · $period' : name;
    final meta = [
      period,
      if (start != null && end != null) '${_lhMd(start)}–${_lhMd(end)}',
      if (calc != null) '计算于 ${_lhMd(calc)} ${_lhHm(calc)}',
    ].join(' · ');
    final cum = _num(d['currentCumSales']) ?? _num(d['statAmount']) ?? 0;
    final next = _num(d['next_threshold']) ?? _num(d['target']);
    final nextPermille = _num(d['nextRate']) ?? _num(d['nextTier']);
    final rate = _num(d['discountRate']);
    final rebate = _num(d['rebate']) ?? _num(d['rebateAmount']);
    final gain = _num(d['profitGainAtNextTier']);
    final base = (d['base']?.toString() ?? '').trim();
    final mode = (d['mode']?.toString() ?? '').trim();
    final level = _int(d['tierLevel']) ?? 0;
    final capped = d['status']?.toString() == 'capped';
    final pace = _lhTierPace(d, cum, capped ? null : next);

    final tiers = <(int, double, double?)>[];
    final raw = d['tiers'];
    if (raw is List) {
      for (final t in raw) {
        if (t is! Map) continue;
        tiers.add((_int(t['level']) ?? tiers.length + 1, _num(t['minValue']) ?? 0, _num(t['permille'])));
      }
    }
    tiers.sort((a, b) => a.$1.compareTo(b.$1));

    String head;
    if (capped) {
      head = '已封顶${rate == null ? '' : ' ${lighthouseDiscountRateLabel(rate)}'}';
    } else if (next != null) {
      final gap = math.max(0.0, next - cum);
      final to = nextPermille == null ? '' : ' 到 ${lighthouseDiscountRateLabel(nextPermille / 1000)}';
      final when = pace.eta != null
          ? '  预计 ${pace.eta!.month}/${pace.eta!.day}达到'
          : (pace.days > 0 ? '  本期难达' : '');
      head = '差 ${lighthouseDiscountCompactWan(gap)}$to$when';
    } else {
      head = level > 0 ? '第$level档' : '';
    }
    final headReachable = !capped && pace.eta != null;

    TextStyle mono(double size, Color color, {FontWeight weight = FontWeight.w500}) =>
        LhTypography.mono(context: context, size: size * scale, color: color, weight: weight);
    TextStyle sans(double size, Color color, {FontWeight weight = FontWeight.w400}) =>
        LhTypography.sans(context: context, size: size * scale, color: color, weight: weight, height: 1.3);

    final foot = <(String, String)>[
      ('当前', rate == null ? '—' : lighthouseDiscountRateLabel(rate)),
      ('本期返点', rebate == null ? '—' : lighthouseDiscountCompactWan(rebate)),
      if (capped && tiers.isNotEmpty && cum > tiers.last.$2)
        ('超过最高档', lighthouseDiscountCompactWan(cum - tiers.last.$2))
      else if (!capped && gain != null && gain > 0)
        ('过档多赚', lighthouseDiscountCompactWan(gain))
      else if (!capped && pace.days > 0)
        ('按日均到期末约', lighthouseDiscountCompactWan(pace.projected)),
    ];

    final detail = onDetail == null || rule.ruleId.isEmpty
        ? null
        : Semantics(
            button: true,
            label: '在业务中查看这条阶梯规则详情',
            excludeSemantics: true,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDetail,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: 32 * scale, minWidth: 44 * scale),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('详情', style: sans(10.5, deep, weight: FontWeight.w600)),
                      Icon(Icons.chevron_right_rounded, size: 14 * scale, color: deep),
                    ],
                  ),
                ),
              ),
            ),
          );

    return Container(
      margin: EdgeInsets.fromLTRB(6 * scale, 0, 8 * scale, 6 * scale),
      padding: EdgeInsets.fromLTRB(14 * scale, 12 * scale, 14 * scale, 10 * scale),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, Colors.white, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: DunesColors.resolve(context, const Color(0xFFDCD3F0), role: DunesColorRole.border),
          width: 0.9,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 1 * scale),
                          decoration: BoxDecoration(
                            color: DunesColors.resolve(context, const Color(0xFFFBEDEA), role: DunesColorRole.surface),
                            borderRadius: BorderRadius.circular(4 * scale),
                          ),
                          child: Text(
                            rule.group,
                            style: sans(9.5, DunesColors.resolve(context, const Color(0xFFB23A26)), weight: FontWeight.w600),
                          ),
                        ),
                        SizedBox(width: 6 * scale),
                        Flexible(
                          child: Text(
                            [mode, base].where((e) => e.isNotEmpty).join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(10, mute),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4 * scale),
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: sans(11.5, ink, weight: FontWeight.w600)),
                    SizedBox(height: 2 * scale),
                    Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: mono(9.5, mute, weight: FontWeight.w400)),
                  ],
                ),
              ),
              if (detail != null) ...[SizedBox(width: 8 * scale), detail],
            ],
          ),
          SizedBox(height: 10 * scale),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(lighthouseDiscountCompactWan(cum), style: mono(11.5, hero, weight: FontWeight.w600)),
              SizedBox(width: 5 * scale),
              Text('本期累计', style: sans(10, mute)),
              SizedBox(width: 10 * scale),
              Expanded(
                child: Text(
                  head,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: sans(10.5, headReachable ? deep : ink2, weight: FontWeight.w500),
                ),
              ),
            ],
          ),
          SizedBox(height: 8 * scale),
          _TierRuler(
            tiers: tiers,
            level: level,
            cum: cum,
            projected: capped ? cum : pace.projected,
            capped: capped,
            scale: scale,
          ),
          SizedBox(height: 6 * scale),
          Row(
            children: [
              _legend(context, '已发生', dashed: false),
              SizedBox(width: 12 * scale),
              if (!capped) _legend(context, '按日均到期末', dashed: true),
              const Spacer(),
              if (pace.days > 0) Text('第 ${pace.day} / ${pace.days} 天', style: mono(9, mute, weight: FontWeight.w400)),
            ],
          ),
          SizedBox(height: 8 * scale),
          Container(
            padding: EdgeInsets.only(top: 8 * scale),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: DunesColors.resolve(context, const Color(0xFFF1EEF6), role: DunesColorRole.border),
                ),
              ),
            ),
            child: Wrap(
              spacing: 16 * scale,
              runSpacing: 4 * scale,
              children: [
                for (final (k, v) in foot)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '$k ', style: sans(10, ink2)),
                        TextSpan(text: v, style: mono(10, ink)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, String label, {required bool dashed}) {
    final mute = DunesColors.resolve(context, _kText);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14 * scale,
          height: 5 * scale,
          child: CustomPaint(
            painter: _LegendSwatchPainter(
              color: DunesColors.resolve(context, dashed ? _kFillCapped : _kFillNear),
              dashed: dashed,
            ),
          ),
        ),
        SizedBox(width: 5 * scale),
        Text(
          label,
          style: LhTypography.sans(context: context, size: 9 * scale, color: mute, height: 1.2),
        ),
      ],
    );
  }
}

class _LegendSwatchPainter extends CustomPainter {
  _LegendSwatchPainter({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final r = Radius.circular(size.height / 2);
    if (!dashed) {
      canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), p);
      return;
    }
    for (var x = 0.0; x < size.width; x += 5) {
      canvas.drawRect(Rect.fromLTWH(x, 0, math.min(3, size.width - x), size.height), p);
    }
  }

  @override
  bool shouldRepaint(_LegendSwatchPainter old) => old.color != color || old.dashed != dashed;
}

/// 刻度尺：一整根条按金额等比例（右端 = 最高档门槛 × 1.15），白色刻度 = 各档门槛，
/// 上方费率、下方门槛金额；实色到本期累计，虚线到按日均外推的期末位置，白底圆点 = 现在。
class _TierRuler extends StatelessWidget {
  const _TierRuler({
    required this.tiers,
    required this.level,
    required this.cum,
    required this.projected,
    required this.capped,
    required this.scale,
  });

  final List<(int, double, double?)> tiers;
  final int level;
  final double cum;
  final double projected;
  final bool capped;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final top = tiers.isEmpty ? 0.0 : tiers.last.$2;
    final maxV = math.max(top * 1.15, math.max(cum, 1.0) * 1.05);
    final mute = DunesColors.resolve(context, _kText);
    final deep = DunesColors.resolve(context, const Color(0xFF5A458F));
    final hero = DunesColors.resolve(context, const Color(0xFF2B2147));
    final dim = DunesColors.resolve(context, const Color(0xFF9A98A3));
    final labelH = 13 * scale;
    final barH = 8 * scale;
    final gap = 4 * scale;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        double xOf(double v) => (v / maxV).clamp(0.0, 1.0) * w;
        Widget label(double v, String text, TextStyle style, double y) {
          const approx = 46.0;
          final x = xOf(v);
          final width = approx * scale;
          double left;
          TextAlign align;
          if (x <= 1) {
            left = 0;
            align = TextAlign.left;
          } else if (x + width / 2 >= w) {
            left = w - width;
            align = TextAlign.right;
          } else {
            left = x - width / 2;
            align = TextAlign.center;
          }
          return Positioned(
            left: left,
            top: y,
            width: width,
            child: Text(text, textAlign: align, maxLines: 1, softWrap: false, overflow: TextOverflow.visible, style: style),
          );
        }

        final barTop = labelH + gap;
        return SizedBox(
          height: labelH * 2 + gap * 2 + barH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final t in tiers)
                label(
                  t.$2,
                  t.$3 == null ? '—' : lighthouseDiscountRateLabel(t.$3! / 1000),
                  LhTypography.mono(
                    context: context,
                    size: 9.5 * scale,
                    weight: t.$1 == level ? FontWeight.w700 : FontWeight.w500,
                    color: t.$1 == level ? hero : (t.$1 < level ? deep : dim),
                  ),
                  0,
                ),
              Positioned(
                left: 0,
                right: 0,
                top: barTop,
                height: barH,
                child: CustomPaint(
                  painter: _RulerPainter(
                    ticks: [for (final t in tiers) if (t.$2 > 0) xOf(t.$2) / w],
                    fill: math.max(xOf(cum) / w, cum > 0 ? 0.012 : 0),
                    projected: xOf(projected) / w,
                    track: DunesColors.resolve(context, _kTrack, role: DunesColorRole.border),
                    fillColor: DunesColors.resolve(context, capped ? _kFillCapped : _kFillNear),
                    projColor: DunesColors.resolve(context, _kFillCapped),
                    tick: DunesColors.resolve(context, Colors.white, role: DunesColorRole.surface),
                    dot: !capped,
                  ),
                ),
              ),
              for (final t in tiers)
                label(
                  t.$2,
                  t.$2 <= 0 ? '0' : lighthouseDiscountCompactWan(t.$2),
                  LhTypography.mono(context: context, size: 9 * scale, weight: FontWeight.w400, color: mute),
                  barTop + barH + gap,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.ticks,
    required this.fill,
    required this.projected,
    required this.track,
    required this.fillColor,
    required this.projColor,
    required this.tick,
    required this.dot,
  });

  final List<double> ticks;
  final double fill;
  final double projected;
  final Color track;
  final Color fillColor;
  final Color projColor;
  final Color tick;
  final bool dot;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final r = Radius.circular(h / 2);
    final whole = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.save();
    canvas.clipRRect(whole);
    canvas.drawRRect(whole, Paint()..color = track);
    final px = size.width * projected.clamp(0.0, 1.0);
    final fx = size.width * fill.clamp(0.0, 1.0);
    if (px > fx) {
      final p = Paint()..color = projColor;
      for (var x = fx; x < px; x += 5) {
        canvas.drawRect(Rect.fromLTWH(x, 0, math.min(3, px - x), h), p);
      }
    }
    if (fx > 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, fx, h), r), Paint()..color = fillColor);
    }
    final tp = Paint()..color = tick;
    for (final t in ticks) {
      if (t <= 0 || t >= 1) continue;
      canvas.drawRect(Rect.fromLTWH(size.width * t - 1, 0, 2, h), tp);
    }
    canvas.restore();
    if (dot) {
      final c = Offset(fx.clamp(h * 0.9, size.width - h * 0.9), h / 2);
      canvas.drawCircle(c, h * 0.85, Paint()..color = tick);
      canvas.drawCircle(
        c,
        h * 0.85,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = h * 0.35,
      );
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.fill != fill ||
      old.projected != projected ||
      old.fillColor != fillColor ||
      old.track != track ||
      old.ticks.length != ticks.length ||
      old.dot != dot;
}
