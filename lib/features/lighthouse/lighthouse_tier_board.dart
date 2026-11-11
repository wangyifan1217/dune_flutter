import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'lighthouse_discount_metric.dart';
import 'lighthouse_discount_strip.dart' show lighthouseDiscountPeriodLabel;
import 'lighthouse_theme.dart';

// ════════════════════════════════════════════════════════════════════════
// 供给方「阶梯」（2026-11-11 · V4）
//
//   平时只有一条折叠条，跟省份卡片底部的「细分」条同一个样子：
//     阶梯 14 · 11月 · 守住 4 · 放弃 10 · 还剩 17 天 ……… 展开
//   点开后在同一张卡里铺两列小卡，每条规则一张，只留五行：
//     省份 + 品牌章 + 守住/发力/放弃/封顶 · 规则名 · 本期累计 · 4px 进度条 + 差 X 到 Y ·
//     预计几号到 / 本期难达 + 多赚。
//   排序：发力 → 守住 → 放弃 → 封顶，同组按多赚从多到少；放弃 / 封顶变淡，先只露两张。
//   省份卡片底下不再各挂一条阶梯，阶梯只在这里看；点小卡进业务里的阶梯详情。
//
//   节奏 / 判断全部来自 lighthouseTierPaceOf（后端 discount_pace.go），这里不外推。
//   字号上限 = 账本卡片：名字 12 / 数值 11.5 / 标签 10 / 单位 9，再乘账本缩放。
// ════════════════════════════════════════════════════════════════════════

/// 供给方阶梯折叠区总开关。开着时省份卡片底下的「阶梯 N · 展开」条不再出现。
const bool lighthouseSupplyTierBoardEnabled = true;

/// 放弃 / 封顶的先露几张，其余点「显示」。
const int _kDimPreviewCount = 2;

const Color _kPurple = Color(0xFF7B5CD8);
const Color _kDeep = Color(0xFF5A458F);
const Color _kHeroNum = Color(0xFF4A3A7A);
const Color _kHeroInk = Color(0xFF2B2147);
const Color _kFill = Color(0xFF7B5CD8);
const Color _kFillFrom = Color(0xFFB8A6EE);
const Color _kSegDrop = Color(0xFFD3D1C7);
const Color _kSegCapped = Color(0xFFE6E3EC);
const Color _kFillSoft = Color(0xFFB5AAD5);
const Color _kProj = Color(0xFFCFC3EE);
const Color _kTrack = Color(0xFFEFEBF6);
const Color _kEdge = Color(0xFFE4DCF4);
const Color _kEdgeOpen = Color(0xFFC2AEE7);
const Color _kCardEdge = Color(0xFFE2D8F0);
const Color _kHairline = Color(0xFFF1EEF6);
const Color _kBarFill = Color(0xFFFAF9FD);
const Color _kBarFillOpen = Color(0xFFF7F3FC);
const Color _kChipSoft = Color(0xFFF0ECF6);
const Color _kNeutralChip = Color(0xFFF1EFF4);
const Color _kInk = Color(0xFF1F2421);
const Color _kInk2 = Color(0xFF5A5C56);
const Color _kMute = Color(0xFF6E6C66);
const Color _kMute2 = Color(0xFF94938A);

/// 一条规则：供给方卡片上的一家（省 × 中石油 / 中石化）的一条阶梯规则。
class LhTierBoardEntry {
  const LhTierBoardEntry({
    required this.province,
    required this.group,
    required this.supplierKey,
    required this.data,
    required this.pace,
    this.marginPct,
  });

  /// 卡片上的省名（「湖南省」）。
  final String province;

  /// 中石油 / 中石化。
  final String group;
  final String supplierKey;
  final Map<String, dynamic> data;
  final LighthouseTierPace pace;

  /// 这一行（省份）的毛利率 %，没有就是 null。
  final double? marginPct;

  String get ruleId => data['ruleId']?.toString() ?? '';

  String get shortProvince => province.replaceAll(RegExp(r'(省|市|壮族自治区|回族自治区|维吾尔自治区|自治区)$'), '');

  double? get gain {
    final v = data['profitGainAtNextTier'];
    return v is num && v > 0 ? v.toDouble() : null;
  }

  double? get currentPermille {
    final r = data['discountRate'];
    if (r is num) return r.toDouble() * 1000;
    final c = data['currentTier'] ?? data['contractRatePermille'];
    return c is num ? c.toDouble() : null;
  }

  double? get nextPermille {
    final n = data['nextRate'] ?? data['nextTier'];
    return n is num ? n.toDouble() : null;
  }

  double? get nextThreshold {
    for (final k in const ['next_threshold', 'nextThreshold', 'target']) {
      final v = data[k];
      if (v is num && v > 0) return v.toDouble();
    }
    return null;
  }

  /// 「11月阶梯 · 全额累进 · 门槛值」。
  String get ruleLabel {
    final parts = <String>[
      lighthouseDiscountPeriodLabel(data),
      data['mode']?.toString().trim() ?? '',
      data['base']?.toString().trim() ?? '',
    ];
    return parts.where((s) => s.isNotEmpty).join(' · ');
  }

  bool get dim => pace.isDrop || pace.isCapped;

  /// 规则名（「湖南中石油-月阶梯-全额累进-门槛」），没有就用 [ruleLabel]。
  String get ruleName {
    final n = data['ruleName']?.toString().trim() ?? '';
    return n.isEmpty ? ruleLabel : n;
  }

  /// 「全额累进 · 门槛值」。
  String get modeBase =>
      [data['mode']?.toString().trim() ?? '', data['base']?.toString().trim() ?? ''].where((s) => s.isNotEmpty).join(' · ');

  DateTime? _time(String k) => DateTime.tryParse(data[k]?.toString() ?? '')?.toLocal();
  DateTime? get periodStart => _time('periodStartTime');
  DateTime? get periodEnd => _time('periodEndTime');
  DateTime? get calcTime => _time('calcTime');

  /// 本期返点（元）。
  double? get rebate {
    for (final k in const ['rebate', 'rebateAmount']) {
      final v = data[k];
      if (v is num) return v.toDouble();
    }
    return null;
  }

  /// 最高档门槛（封顶时算「超过最高档」）。
  double? get topThreshold {
    final raw = data['tiers'];
    if (raw is! List) return null;
    double? top;
    for (final t in raw) {
      if (t is! Map) continue;
      final v = t['minValue'];
      if (v is num && (top == null || v > top)) top = v.toDouble();
    }
    return top;
  }
}

String _md(DateTime d) => '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

int _verdictRank(String v) => switch (v) {
  lighthouseTierPush => 0,
  lighthouseTierHold => 1,
  lighthouseTierDrop => 2,
  lighthouseTierCapped => 3,
  _ => 4,
};

/// 发力 → 守住 → 放弃 → 封顶；同组按多赚从多到少。
List<LhTierBoardEntry> lighthouseTierBoardSorted(List<LhTierBoardEntry> entries) {
  final out = [...entries];
  out.sort((a, b) {
    final r = _verdictRank(a.pace.verdict).compareTo(_verdictRank(b.pace.verdict));
    if (r != 0) return r;
    return (b.gain ?? 0.0).compareTo(a.gain ?? 0.0);
  });
  return out;
}

class LhSupplyTierBoard extends StatefulWidget {
  const LhSupplyTierBoard({super.key, required this.entries, this.onOpenRule, this.scale = 1, this.filter = 'all', this.onFilter});

  final List<LhTierBoardEntry> entries;
  final ValueChanged<LhTierBoardEntry>? onOpenRule;
  final double scale;

  /// 列表的阶梯筛选：all / reach（守住）/ push（发力）/ hard（放弃）。
  final String filter;

  /// 点折叠条上的「守住 / 发力 / 放弃」格切换筛选；再点同一格回到 all。为空时那几格只是文字。
  final ValueChanged<String>? onFilter;

  @override
  State<LhSupplyTierBoard> createState() => _LhSupplyTierBoardState();
}

class _LhSupplyTierBoardState extends State<LhSupplyTierBoard> {
  bool _open = false;
  bool _showAllDim = false;

  double get s => widget.scale;

  TextStyle _sans(double size, Color color, FontWeight weight, {double height = 1.3}) =>
      LhTypography.sans(context: context, size: size * s, color: DunesColors.resolve(context, color), weight: weight, height: height);

  TextStyle _mono(double size, Color color, FontWeight weight) =>
      LhTypography.mono(context: context, size: size * s, color: DunesColors.resolve(context, color), weight: weight);

  String _wan(double v) => lighthouseDiscountCompactWan(v);

  String _rate(double? permille) => permille == null ? '—' : lighthouseDiscountRateLabel(permille / 1000);

  @override
  Widget build(BuildContext context) {
    final judged = widget.entries.where((e) => e.pace.verdict.isNotEmpty).toList();
    if (judged.isEmpty) return const SizedBox.shrink();
    final sorted = lighthouseTierBoardSorted(judged);
    // 点了折叠条上的「守住 / 发力 / 放弃」：那一组置顶并全部露出，其余照常排在后面。
    final pinVerdict = _filterVerdict(widget.filter);
    final pinned = pinVerdict == null ? const <LhTierBoardEntry>[] : sorted.where((e) => e.pace.verdict == pinVerdict).toList();
    final rest = sorted.where((e) => e.pace.verdict != pinVerdict || pinVerdict == null).toList();
    final bright = rest.where((e) => !e.dim).toList();
    final dimmed = rest.where((e) => e.dim).toList();
    final shownDim = _showAllDim ? dimmed : dimmed.take(_kDimPreviewCount).toList();
    final hiddenDim = dimmed.length - shownDim.length;
    final cards = [...pinned, ...bright, ...shownDim];

    final edge = DunesColors.resolve(context, _open ? _kEdgeOpen : _kEdge, role: DunesColorRole.border);
    return Container(
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, Colors.white, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(_open ? 16 : 14),
        border: Border.all(color: edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _bar(sorted),
          if (_open) ...[
            _openHeader(sorted),
            Padding(padding: EdgeInsets.fromLTRB(10 * s, 0, 10 * s, 10 * s), child: _grid(cards)),
            if (hiddenDim > 0 || (_showAllDim && dimmed.length > _kDimPreviewCount)) _moreRow(hiddenDim),
          ],
        ],
      ),
    );
  }

  // ── 折叠条 ─────────────────────────────────────────────────────────────

  /// 每种判断在分段条 / 小圆点上的颜色。
  static Color _segColor(String verdict) => switch (verdict) {
    lighthouseTierHold => _kPurple,
    lighthouseTierPush => _kFillFrom,
    lighthouseTierDrop => _kSegDrop,
    _ => _kSegCapped,
  };

  /// 折叠条（原型 A）：
  ///   ① ↳ 11月阶梯   12 条 · 还剩 17 天 ……………… 展开 ⌄
  ///   ② [● 难达 8] [● 可达 4] ……………… [↗ 11月能多赚 12万]
  /// ② 的小格：点了筛底下的数据行 + 展开看板（那组置顶）；再点取消筛选。整条本身不开合，收起只靠右上角。
  Widget _bar(List<LhTierBoardEntry> sorted) {
    int count(String v) => sorted.where((e) => e.pace.verdict == v).length;
    final period = lighthouseDiscountPeriodLabel(sorted.first.data);
    // (筛选值, 判断, 标签)；封顶不参与筛选。
    // 顺序：难达 · 可达 · 发力 · 封顶（可达固定在第二格）；默认都不选 = 全部省份。
    const cells = [
      ('hard', lighthouseTierDrop, '难达'),
      ('reach', lighthouseTierHold, '可达'),
      ('push', lighthouseTierPush, '发力'),
      ('', lighthouseTierCapped, '封顶'),
    ];
    final remaining = sorted.first.pace.remainingDays;
    // 能多赚 = 可达 + 发力 这些「本期够得着」的规则过档多赚之和。
    final reachableGain = sorted
        .where((e) => e.pace.verdict == lighthouseTierHold || e.pace.verdict == lighthouseTierPush)
        .fold<double>(0, (sum, e) => sum + (e.gain ?? 0));
    // 整条不再可点：小格只管筛选底下的数据行，只有右上角「展开 / 收起」开合看板。
    return Container(
      padding: EdgeInsets.fromLTRB(12 * s, 10 * s, 6 * s, 10 * s),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, _open ? _kBarFillOpen : Colors.white, role: DunesColorRole.surface),
        border: _open
            ? Border(
                bottom: BorderSide(color: DunesColors.resolve(context, _kHairline, role: DunesColorRole.border)),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ① 标题行
          Row(
            children: [
              _branchMark(),
              SizedBox(width: 8 * s),
              Expanded(
                child: Wrap(
                  spacing: 8 * s,
                  runSpacing: 2 * s,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(period.isEmpty ? '阶梯' : period, style: _sans(13, _kHeroInk, FontWeight.w700, height: 1.25)),
                    Text(
                      '${sorted.length} 条 · ${remaining > 0 ? '还剩 $remaining 天' : '最后一天'}',
                      style: _mono(10.5, _kMute2, FontWeight.w400),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 4 * s),
              _toggle(sorted.length),
            ],
          ),
          SizedBox(height: 9 * s),
          // ② 计数小格 + 能多赚
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6 * s,
                  runSpacing: 6 * s,
                  children: [
                    for (final c in cells)
                      // 选中的那格即使 0 条也留着，好让人点掉筛选。
                      if (count(c.$2) > 0 || (c.$1.isNotEmpty && c.$1 == widget.filter)) _filterCell(c.$1, c.$2, c.$3, count(c.$2)),
                  ],
                ),
              ),
              if (reachableGain > 0) ...[SizedBox(width: 8 * s), _gainTotal(period, reachableGain)],
            ],
          ),
        ],
      ),
    );
  }

  /// 右上角「展开 ⌄ / 收起 ⌃」：看板开合的唯一入口，点区至少 44×32。
  Widget _toggle(int total) => Semantics(
    button: true,
    expanded: _open,
    label: _open ? '收起阶梯' : '展开 $total 条阶梯',
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _open = !_open),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 32 * s, minWidth: 44 * s),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(_open ? '收起' : '展开', style: _sans(11, _kPurple, FontWeight.w600, height: 1.2)),
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(Icons.keyboard_arrow_down_rounded, size: 17 * s, color: DunesColors.resolve(context, _kPurple)),
            ),
          ],
        ),
      ),
    ),
  );

  /// 「↑ 11月能多赚 12万」：可达 + 发力的过档多赚合计，紫色小框。
  Widget _gainTotal(String period, double value) {
    final m = RegExp(r'(\d+月)').firstMatch(period);
    final scope = m?.group(1) ?? '期内';
    return Container(
      padding: EdgeInsets.fromLTRB(6 * s, 3 * s, 8 * s, 3 * s),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, _kChipSoft, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(7 * s),
        border: Border.all(color: DunesColors.resolve(context, _kEdgeOpen, role: DunesColorRole.border), width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.trending_up_rounded, size: 13 * s, color: DunesColors.resolve(context, _kPurple)),
          SizedBox(width: 4 * s),
          Text('$scope能多赚', style: _sans(10.5, _kPurple, FontWeight.w500, height: 1.2)),
          SizedBox(width: 4 * s),
          Text(_wan(value), style: _mono(12, _kPurple, FontWeight.w700)),
        ],
      ),
    );
  }

  /// 展开后、小卡上方一行：本期起止 · 第几天 · 计算于，右边是进度条图例（各卡共用一份）。
  Widget _openHeader(List<LhTierBoardEntry> sorted) {
    final first = sorted.first;
    final p = first.pace;
    final st = first.periodStart, en = first.periodEnd, calc = first.calcTime;
    final meta = [
      if (st != null && en != null) '${_md(st)}–${_md(en)}',
      if (p.totalDays > 0) '第 ${p.elapsedDays}/${p.totalDays} 天',
      if (calc != null) '计算于 ${_md(calc)} ${_hm(calc)}',
    ].join(' · ');
    return Padding(
      padding: EdgeInsets.fromLTRB(12 * s, 8 * s, 12 * s, 8 * s),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10 * s,
        runSpacing: 4 * s,
        children: [
          Text(meta, style: _mono(9.5, _kMute2, FontWeight.w400)),
          Wrap(spacing: 8 * s, runSpacing: 4 * s, children: [_legend('已发生', dashed: false), _legend('按日均到期末', dashed: true)]),
        ],
      ),
    );
  }

  Widget _legend(String label, {required bool dashed}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 14 * s,
        height: 6,
        child: CustomPaint(
          painter: _MiniBarPainter(
            fill: dashed ? 0 : 1,
            projected: 1,
            track: Colors.transparent,
            fillFrom: DunesColors.resolve(context, _kFillFrom),
            fillTo: DunesColors.resolve(context, _kFill),
            projColor: DunesColors.resolve(context, _kProj),
            knob: false,
          ),
        ),
      ),
      SizedBox(width: 4 * s),
      Text(label, style: _sans(9, _kMute2, FontWeight.w400, height: 1.2)),
    ],
  );

  static String? _filterVerdict(String filter) => switch (filter) {
    'reach' => lighthouseTierHold,
    'push' => lighthouseTierPush,
    'hard' => lighthouseTierDrop,
    _ => null,
  };

  /// 折叠条上的一格「● 可达 4」：有 onFilter 时可点，点亮 = 列表按这组筛、展开看板并把这组置顶。
  Widget _filterCell(String value, String verdict, String label, int n) {
    final on = value.isNotEmpty && widget.filter == value;
    final soft = verdict == lighthouseTierHold || verdict == lighthouseTierPush;
    final bg = on ? _kPurple : (soft ? _kChipSoft : _kNeutralChip);
    final fg = on ? Colors.white : (soft ? _kDeep : _kInk2);
    final dot = on ? Colors.white : _segColor(verdict);
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, bg, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(7 * s),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6 * s,
            height: 6 * s,
            decoration: BoxDecoration(color: DunesColors.resolve(context, dot), shape: BoxShape.circle),
          ),
          SizedBox(width: 5 * s),
          Text(label, style: _sans(11, fg, FontWeight.w500, height: 1.2)),
          SizedBox(width: 4 * s),
          Text('$n', style: _mono(11.5, fg, FontWeight.w700)),
        ],
      ),
    );
    final onFilter = widget.onFilter;
    if (onFilter == null || value.isEmpty) return chip;
    return Semantics(
      button: true,
      selected: on,
      label: on ? '取消筛选 $label $n' : '只看 $label $n',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // 选中一组时顺手展开看板（那组置顶）；取消筛选不收起。
          if (!on && !_open) setState(() => _open = true);
          onFilter(on ? 'all' : value);
        },
        child: chip,
      ),
    );
  }

  /// 和「细分」条同一枚实心「↳」章，换成品牌紫。
  Widget _branchMark() {
    final size = 16 * s;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF9A84E0), _kPurple, Color(0xFF6A4FA0)],
          stops: [0, 0.52, 1],
        ),
      ),
      child: Icon(Icons.subdirectory_arrow_right_rounded, size: size * 0.7, color: Colors.white),
    );
  }

  // ── 两列小卡 ───────────────────────────────────────────────────────────

  Widget _grid(List<LhTierBoardEntry> cards) {
    final gap = 8 * s;
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      if (i > 0) rows.add(SizedBox(height: gap));
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _card(cards[i])),
              SizedBox(width: gap),
              Expanded(child: i + 1 < cards.length ? _card(cards[i + 1]) : const SizedBox.shrink()),
            ],
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Widget _card(LhTierBoardEntry e) {
    final p = e.pace;
    final groupColor = lhGroupColor(e.group);
    final (vLabel, vFg, vBg) = switch (p.verdict) {
      lighthouseTierPush => ('发力', Colors.white, _kPurple),
      lighthouseTierHold => ('可达', _kDeep, _kChipSoft),
      lighthouseTierDrop => ('难达', _kMute, _kNeutralChip),
      lighthouseTierCapped => ('封顶', _kMute, _kNeutralChip),
      _ => ('—', _kMute, _kNeutralChip),
    };

    final next = e.nextThreshold;
    final fill = p.isCapped ? 1.0 : (next == null ? 0.0 : (p.cum / next).clamp(0.0, 1.0).toDouble());
    final proj = p.isCapped ? 1.0 : (next == null ? 0.0 : (p.projectedCum / next).clamp(0.0, 1.0).toDouble());

    final String gapLine;
    if (p.isCapped) {
      gapLine = '已封顶 ${_rate(e.currentPermille)}';
    } else if (p.gap == null) {
      gapLine = '—';
    } else {
      gapLine = '差 ${_wan(p.gap!)}';
    }
    final toLine = p.isCapped || p.gap == null ? '' : ' 到 ${_rate(e.nextPermille)}';

    final eta = p.eta;
    final String status;
    Color statusColor = _kDeep;
    switch (p.verdict) {
      case lighthouseTierHold:
        status = eta == null ? '本期能到' : '预计 ${eta.month}/${eta.day} 到';
      case lighthouseTierPush:
        final m = p.paceMultiple;
        status = m == null ? '使把劲能到' : '日均要提 ${((m - 1) * 100).round()}%';
        statusColor = _kPurple;
      case lighthouseTierCapped:
        status = '已在最高档';
        statusColor = _kMute2;
      default:
        status = '本期难达';
        statusColor = _kMute2;
    }

    final cumRaw = _wan(p.cum);
    final unitMatch = RegExp(r'^(.*?)(万|亿)$').firstMatch(cumRaw);

    // 进度条两端：左 = 当前档，右 = 下一档（门槛）；封顶时右边写「最高档」。
    final leftRate = _rate(e.currentPermille);
    final String rightEnd;
    if (p.isCapped) {
      rightEnd = '最高档';
    } else if (next == null) {
      rightEnd = '';
    } else {
      rightEnd = '${_rate(e.nextPermille)} · ${_wan(next)}';
    }

    // 底部：当前 · 返点 是事实，右边小框是「为什么值得做」—— 多赚 / 超最高档 / 到期末约。
    final top = e.topThreshold;
    final facts = <(String, String)>[if (e.currentPermille != null) ('当前', leftRate), ('返点', e.rebate == null ? '—' : _wan(e.rebate!))];
    final (String, String)? badge = p.isCapped
        ? (top != null && p.cum > top ? ('超最高档', _wan(p.cum - top)) : null)
        : e.gain != null
        ? ('多赚', _wan(e.gain!))
        : ('到期末约', _wan(p.projectedCum));

    final hairline = BorderSide(color: DunesColors.resolve(context, _kHairline, role: DunesColorRole.border));

    final body = Container(
      padding: EdgeInsets.fromLTRB(10 * s, 9 * s, 10 * s, 8 * s),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, Colors.white, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DunesColors.resolve(context, p.isPush ? _kEdgeOpen : _kCardEdge, role: DunesColorRole.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ① 省份 + 品牌 + 判断
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 4 * s,
                  runSpacing: 2 * s,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(e.shortProvince, style: _sans(12, _kInk, FontWeight.w700)),
                    _chip(e.group, groupColor, groupColor.withAlpha(26), weight: FontWeight.w600, size: 9),
                  ],
                ),
              ),
              SizedBox(width: 4 * s),
              _chip(vLabel, vFg, vBg, weight: FontWeight.w700, size: 9.5),
            ],
          ),
          SizedBox(height: 4 * s),
          // ② 规则名 + 口径
          Text(e.ruleName, style: _sans(10, _kInk2, FontWeight.w600)),
          SizedBox(height: 1 * s),
          Text(
            [lighthouseDiscountPeriodLabel(e.data), e.modeBase].where((x) => x.isNotEmpty).join(' · '),
            style: _sans(9.5, _kMute2, FontWeight.w400),
          ),
          SizedBox(height: 6 * s),
          // ③ 本期累计
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: unitMatch?.group(1) ?? cumRaw, style: _mono(11.5, _kHeroInk, FontWeight.w700)),
                if (unitMatch != null) TextSpan(text: unitMatch.group(2), style: _sans(9, _kMute2, FontWeight.w500)),
                TextSpan(text: '  本期累计', style: _sans(9.5, _kMute2, FontWeight.w400)),
              ],
            ),
          ),
          SizedBox(height: 6 * s),
          // ④ 进度条 + 两端档位
          SizedBox(
            height: 12,
            width: double.infinity,
            child: CustomPaint(
              painter: _MiniBarPainter(
                fill: fill,
                projected: proj,
                track: DunesColors.resolve(context, _kTrack, role: DunesColorRole.border),
                fillFrom: DunesColors.resolve(context, e.dim ? _kTrack : _kFillFrom),
                fillTo: DunesColors.resolve(context, e.dim ? _kFillSoft : _kFill),
                projColor: DunesColors.resolve(context, _kProj),
                knobRing: DunesColors.resolve(context, e.dim ? _kFillSoft : _kPurple),
                knobFill: DunesColors.resolve(context, Colors.white, role: DunesColorRole.surface),
              ),
            ),
          ),
          SizedBox(height: 4 * s),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 6 * s,
              runSpacing: 2 * s,
              children: [
                Text(e.currentPermille == null ? '0' : leftRate, style: _mono(9.5, _kDeep, FontWeight.w600)),
                if (rightEnd.isNotEmpty)
                  Text.rich(
                    TextSpan(
                      children: [
                        if (!p.isCapped) TextSpan(text: _rate(e.nextPermille), style: _mono(9.5, _kDeep, FontWeight.w600)),
                        TextSpan(text: p.isCapped ? rightEnd : ' @ ${_wan(next!)}', style: _mono(9.5, _kMute2, FontWeight.w400)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 5 * s),
          // ⑤ 差多少到几 + 什么时候到
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: gapLine, style: _mono(10, _kInk, FontWeight.w600)),
                if (toLine.isNotEmpty) TextSpan(text: toLine, style: _mono(10, _kDeep, FontWeight.w600)),
              ],
            ),
          ),
          SizedBox(height: 2 * s),
          Text(status, style: _sans(9.5, statusColor, FontWeight.w600)),
          const Spacer(),
          // ⑥ 当前 · 返点 ……  [多赚 4万]（放不下自动换行）
          Container(
            width: double.infinity,
            margin: EdgeInsets.only(top: 8 * s),
            padding: EdgeInsets.only(top: 7 * s),
            decoration: BoxDecoration(border: Border(top: hairline)),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6 * s,
              runSpacing: 5 * s,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      for (var i = 0; i < facts.length; i++) ...[
                        if (i > 0) TextSpan(text: '  ', style: _sans(9, _kMute, FontWeight.w400)),
                        TextSpan(text: '${facts[i].$1} ', style: _sans(9, _kMute, FontWeight.w400)),
                        TextSpan(text: facts[i].$2, style: _mono(9.5, _kInk, FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
                if (badge != null) _gainBadge(badge.$1, badge.$2, strong: !e.dim),
              ],
            ),
          ),
        ],
      ),
    );

    final card = Opacity(opacity: e.dim ? 0.78 : 1, child: body);
    if (widget.onOpenRule == null || e.ruleId.isEmpty) return card;
    return Semantics(
      button: true,
      label: '${e.province}${e.group} 阶梯规则详情',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => widget.onOpenRule!(e), child: card),
      ),
    );
  }

  /// 「多赚 4万」小框：淡紫底 + 紫描边 + ↑；放弃 / 封顶的卡用灰框。
  Widget _gainBadge(String label, String value, {required bool strong}) {
    final ring = strong ? _kEdgeOpen : _kCardEdge;
    final bg = strong ? _kBarFillOpen : _kBarFill;
    final ink = strong ? _kHeroNum : _kMute;
    return Container(
      padding: EdgeInsets.fromLTRB(5 * s, 2 * s, 6 * s, 2 * s),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, bg, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(6 * s),
        border: Border.all(color: DunesColors.resolve(context, ring, role: DunesColorRole.border), width: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label == '多赚') ...[
            Icon(Icons.arrow_upward_rounded, size: 10 * s, color: DunesColors.resolve(context, strong ? _kPurple : _kMute2)),
            SizedBox(width: 2 * s),
          ],
          Text(label, style: _sans(9, strong ? _kDeep : _kMute, FontWeight.w500, height: 1.3)),
          SizedBox(width: 3 * s),
          Text(value, style: _mono(10, ink, FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _chip(String text, Color fg, Color bg, {required FontWeight weight, required double size}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 0.5 * s),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, bg, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(3 * s),
      ),
      child: Text(text, style: _sans(size, fg, weight, height: 1.5)),
    );
  }

  Widget _moreRow(int hidden) {
    final expanded = hidden <= 0;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: expanded ? '收起难达的规则' : '显示另外 $hidden 条',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showAllDim = !_showAllDim),
        child: Container(
          constraints: BoxConstraints(minHeight: 36 * s),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: DunesColors.resolve(context, _kHairline, role: DunesColorRole.border)),
            ),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: expanded ? '' : '还有 $hidden 条本期难达 · ', style: _sans(10.5, _kMute, FontWeight.w400)),
                TextSpan(text: expanded ? '收起难达的' : '显示', style: _sans(10.5, _kPurple, FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 小卡里的进度条：6px 圆角轨道 + 斜纹（按日均到期末）+ 渐变实色（已发生）+ 白芯紫圈的游标。
class _MiniBarPainter extends CustomPainter {
  _MiniBarPainter({
    required this.fill,
    required this.projected,
    required this.track,
    required this.fillFrom,
    required this.fillTo,
    required this.projColor,
    this.knob = true,
    this.knobRing = Colors.transparent,
    this.knobFill = Colors.white,
  });

  final double fill;
  final double projected;
  final Color track;
  final Color fillFrom;
  final Color fillTo;
  final Color projColor;
  final bool knob;
  final Color knobRing;
  final Color knobFill;

  @override
  void paint(Canvas canvas, Size size) {
    const barH = 6.0;
    final knobR = knob ? size.height / 2 : 0.0;
    // 两头留出半个游标，免得游标在 0% / 100% 时被切掉。
    final left = knobR;
    final w = size.width - knobR * 2;
    final top = (size.height - barH) / 2;
    final r = const Radius.circular(barH / 2);
    final whole = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, barH), r);

    canvas.save();
    canvas.clipRRect(whole);
    canvas.drawRRect(whole, Paint()..color = track);
    final fx = left + w * fill;
    final px = left + w * projected;
    if (px > fx) {
      final zone = Rect.fromLTRB(fx, top, px, top + barH);
      canvas.drawRect(zone, Paint()..color = projColor.withAlpha(90));
      final stripe = Paint()
        ..color = projColor
        ..strokeWidth = 1.6;
      canvas.save();
      canvas.clipRect(zone);
      for (var x = fx - barH; x < px + barH; x += 4.5) {
        canvas.drawLine(Offset(x, top + barH), Offset(x + barH, top), stripe);
      }
      canvas.restore();
    }
    if (fx > left) {
      final rect = Rect.fromLTRB(left, top, fx, top + barH);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, r), Paint()..shader = LinearGradient(colors: [fillFrom, fillTo]).createShader(rect));
    }
    canvas.restore();

    if (knob && fill > 0 && fill < 1) {
      final c = Offset(fx, size.height / 2);
      canvas.drawCircle(c, knobR, Paint()..color = knobRing.withAlpha(40));
      canvas.drawCircle(c, knobR - 1.5, Paint()..color = knobFill);
      canvas.drawCircle(
        c,
        knobR - 1.5,
        Paint()
          ..color = knobRing
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_MiniBarPainter old) =>
      old.fill != fill ||
      old.projected != projected ||
      old.fillFrom != fillFrom ||
      old.fillTo != fillTo ||
      old.track != track ||
      old.projColor != projColor ||
      old.knobRing != knobRing;
}
