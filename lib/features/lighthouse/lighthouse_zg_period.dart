import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:dunes_app/core/theme/dunes_island.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

import 'lighthouse_feedback.dart';
import 'lighthouse_theme.dart';

// ═════════════════════════════════════════════════════════════════════════════
// 资管 · 周期浮岛（2026-11-05）
//
//   照灯塔顶栏的周期岛做：渐变紫小胶囊写当前期（今日 / 本月 / 上月…）+ mono 日期 + ⌄，
//   点开从岛的位置弹出「看哪个周期」面板：上面选粒度，下面「往前翻」横条（最新在最右）。
//   只放接口真能切的粒度：资金计划 / 资金流水 = 日、月；资金调动 = 月。周、季、年、区间
//   资管接口没有，就不出现在面板里。
// ═════════════════════════════════════════════════════════════════════════════

/// 当前看的那一期：粒度（day / month）+ 偏移（0 = 今天 / 本月，-1 = 昨天 / 上月，+1 = 下月）。
@immutable
class LhZgPeriod {
  const LhZgPeriod(this.grain, this.offset);
  const LhZgPeriod.month([this.offset = 0]) : grain = 'month';
  const LhZgPeriod.day([this.offset = 0]) : grain = 'day';

  final String grain;
  final int offset;

  bool get isDay => grain == 'day';

  /// 这一天（日粒度）。
  DateTime get day {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + offset);
  }

  /// 这个月的 1 号（月粒度）；日粒度时给那天所在的月。
  DateTime get month {
    if (isDay) return DateTime(day.year, day.month);
    final n = DateTime.now();
    return DateTime(n.year, n.month + offset);
  }

  /// 接口参数：yyyy-MM-dd 或 yyyy-MM。
  String get param {
    String p2(int v) => v.toString().padLeft(2, '0');
    return isDay ? '${day.year}-${p2(day.month)}-${p2(day.day)}' : '${month.year}-${p2(month.month)}';
  }

  @override
  bool operator ==(Object other) => other is LhZgPeriod && other.grain == grain && other.offset == offset;

  @override
  int get hashCode => Object.hash(grain, offset);
}

const _kWeek = ['一', '二', '三', '四', '五', '六', '日'];
String _p2(int v) => v.toString().padLeft(2, '0');

/// 胶囊上的名字：今日 / 昨日 / 前日 / 11.02；本月 / 上月 / 下月 / 9月 / 25年12月。
String lhZgPeriodName(LhZgPeriod p) {
  if (p.isDay) {
    if (p.offset == 0) return '今日';
    if (p.offset == -1) return '昨日';
    if (p.offset == -2) return '前日';
    return '${p.day.month}.${_p2(p.day.day)}';
  }
  if (p.offset == 0) return '本月';
  if (p.offset == -1) return '上月';
  if (p.offset == 1) return '下月';
  final m = p.month;
  return m.year == DateTime.now().year ? '${m.month}月' : '${m.year % 100}年${m.month}月';
}

/// 胶囊旁的日期：11.05；11.01–11.05（本月截至今天）/ 10.01–10.31。
String lhZgPeriodRange(LhZgPeriod p) {
  if (p.isDay) return '${_p2(p.day.month)}.${_p2(p.day.day)}';
  final m = p.month;
  final now = DateTime.now();
  final last = DateTime(m.year, m.month + 1, 0).day;
  final end = p.offset == 0 ? now.day : last;
  return '${_p2(m.month)}.01–${_p2(m.month)}.${_p2(end)}';
}

String _instDetail(LhZgPeriod p) {
  if (p.isDay) return '${_p2(p.day.month)}.${_p2(p.day.day)} 周${_kWeek[p.day.weekday - 1]}';
  return '${p.month.year}.${_p2(p.month.month)}';
}

const _kInk = Color(0xFF4A3A7A);
const _kInkStrong = Color(0xFF2B2147);
const _kMute = Color(0xFF6E6890);
const _kIcon = Color(0xFF5A458F);
const double _kH = 40;
const double _kInstW = 78;

class LhZgPeriodIsland extends StatefulWidget {
  const LhZgPeriodIsland({
    super.key,
    required this.value,
    required this.grains,
    required this.onChanged,
    this.dayBack = 60,
    this.monthBack = 12,
    this.monthForward = 0,
  });

  final LhZgPeriod value;

  /// 面板里放哪些粒度：'day' / 'month'。
  final List<String> grains;
  final ValueChanged<LhZgPeriod> onChanged;
  final int dayBack;
  final int monthBack;

  /// 月粒度往后能看几个月（资金计划可以先看下个月的计划）。
  final int monthForward;

  @override
  State<LhZgPeriodIsland> createState() => _LhZgPeriodIslandState();
}

class _LhZgPeriodIslandState extends State<LhZgPeriodIsland> {
  bool _open = false;

  Duration _dur(int ms) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : Duration(milliseconds: ms);

  @override
  Widget build(BuildContext context) {
    final name = lhZgPeriodName(widget.value);
    final range = lhZgPeriodRange(widget.value);
    return Builder(
      builder: (anchor) => Semantics(
        button: true,
        expanded: _open,
        label: '切换周期，当前$name，$range',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_openSheet(anchor)),
          child: AnimatedScale(
            scale: _open ? 0.96 : 1,
            duration: _dur(180),
            curve: Curves.easeOutCubic,
            child: Container(
              height: _kH,
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              decoration: dunesIslandDecoration(context, radius: _kH / 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: _dur(280),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0, 0.45), end: Offset.zero).animate(a),
                        child: child,
                      ),
                    ),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.center,
                      children: [...previous, ?current],
                    ),
                    child: Container(
                      key: ValueKey('zg-island-$name'),
                      height: _kH - 8,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        gradient: kDunesIslandPillGradient,
                        borderRadius: BorderRadius.all(Radius.circular((_kH - 8) / 2)),
                        boxShadow: kDunesIslandPillShadow,
                      ),
                      child: Text(
                        name,
                        maxLines: 1,
                        style: LhTypography.sans(
                          size: 13,
                          weight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.4,
                          height: 1.0,
                          context: context,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  AnimatedSwitcher(
                    duration: _dur(220),
                    child: Text(
                      range,
                      key: ValueKey('zg-island-range-$range'),
                      maxLines: 1,
                      softWrap: false,
                      style: LhTypography.mono(
                        size: 11.5,
                        weight: FontWeight.w700,
                        color: _kInk,
                        letterSpacing: 0.2,
                        height: 1.0,
                        context: context,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: _dur(300),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _kIcon),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int _count(String grain) => grain == 'day' ? widget.dayBack + 1 : widget.monthBack + 1 + widget.monthForward;

  /// 横条第 i 格（从右往左数）对应的偏移。月粒度最右边先放「下月」。
  int _offsetAt(String grain, int i) => grain == 'day' ? -i : widget.monthForward - i;

  Future<void> _openSheet(BuildContext anchor) async {
    if (_open) return;
    LighthouseFeedback.instance.play(LighthouseFeedbackKind.select);
    setState(() => _open = true);
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      setState(() => _open = false);
      return;
    }
    final r = box.localToGlobal(Offset.zero) & box.size;
    final screen = MediaQuery.sizeOf(context);
    final phone = screen.width < 600;
    final width = phone ? screen.width - 24 : math.min(420.0, screen.width - 24);
    final left = (r.right - width).clamp(12.0, math.max(12.0, screen.width - 12 - width)).toDouble();
    final top = r.bottom + 8;
    final ox = ((r.center.dx - left) / width).clamp(0.0, 1.0) * 2 - 1;
    final reduce = MediaQuery.disableAnimationsOf(context);
    var cur = widget.value;
    final scroll = ScrollController(
      initialScrollOffset: math.max(0, (_offsetIndex(cur) - 1) * _kInstW),
    );
    try {
      await Navigator.of(context, rootNavigator: true).push<void>(
        PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: reduce ? Duration.zero : const Duration(milliseconds: 340),
          reverseTransitionDuration: reduce ? Duration.zero : const Duration(milliseconds: 150),
          pageBuilder: (ctx, a, _) => Stack(
            children: [
              Positioned.fill(
                child: Semantics(
                  button: true,
                  label: '收起周期',
                  onTap: () => _close(ctx),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => _close(ctx),
                    child: FadeTransition(
                      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut, reverseCurve: Curves.easeIn),
                      child: const ColoredBox(color: Color(0x242B2147)),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: left,
                top: top,
                width: width,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  child: FadeTransition(
                    opacity: CurvedAnimation(parent: a, curve: const Interval(0, 0.55, curve: Curves.easeOut), reverseCurve: Curves.easeIn),
                    child: ScaleTransition(
                      alignment: Alignment(ox, -1),
                      scale: Tween<double>(begin: 0.9, end: 1).animate(
                        CurvedAnimation(parent: a, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: StatefulBuilder(
                          builder: (c2, setLocal) => _sheet(c2, ctx, scroll, cur, (p) {
                            cur = p;
                            setLocal(() {});
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _open = false);
      Future<void>.delayed(const Duration(milliseconds: 300), scroll.dispose);
    }
  }

  int _offsetIndex(LhZgPeriod p) => p.isDay ? -p.offset : widget.monthForward - p.offset;

  void _close(BuildContext ctx) {
    if (!ctx.mounted) return;
    if (ModalRoute.of(ctx)?.isCurrent ?? false) Navigator.of(ctx).pop();
  }

  Widget _sheet(BuildContext context, BuildContext routeCtx, ScrollController scroll, LhZgPeriod cur, ValueChanged<LhZgPeriod> setCur) {
    const names = {'day': '日', 'month': '月'};
    void pickGrain(String g) {
      LighthouseFeedback.instance.play(LighthouseFeedbackKind.select);
      if (g == cur.grain) return;
      final p = LhZgPeriod(g, 0);
      setCur(p);
      widget.onChanged(p);
      if (scroll.hasClients) {
        unawaited(scroll.animateTo(0, duration: _dur(320), curve: Curves.easeOutCubic));
      }
    }

    void pickOffset(int off) {
      LighthouseFeedback.instance.play(LighthouseFeedbackKind.select);
      final p = LhZgPeriod(cur.grain, off);
      setCur(p);
      widget.onChanged(p);
      Future<void>.delayed(_dur(180), () => _close(routeCtx));
    }

    Widget grain(String g) {
      final on = g == cur.grain;
      final sub = on ? lhZgPeriodName(cur) : lhZgPeriodName(LhZgPeriod(g, 0));
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: '${names[g]}，$sub',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => pickGrain(g),
            child: AnimatedContainer(
              duration: _dur(240),
              curve: Curves.easeOutCubic,
              height: 54,
              decoration: BoxDecoration(
                gradient: on ? kDunesIslandPillGradient : null,
                color: on ? null : DunesColors.resolve(context, const Color(0xFFF4F1FC), role: DunesColorRole.surface),
                borderRadius: BorderRadius.circular(15),
                boxShadow: on ? kDunesIslandPillShadow : const [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    names[g] ?? g,
                    style: LhTypography.sans(
                      size: 15,
                      weight: on ? FontWeight.w700 : FontWeight.w600,
                      color: on ? Colors.white : const Color(0xFF3A2A66),
                      height: 1.0,
                      context: context,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    sub,
                    maxLines: 1,
                    style: LhTypography.mono(
                      size: 9.5,
                      weight: FontWeight.w600,
                      color: on ? const Color(0xD9FFFFFF) : const Color(0xFF8A80AE),
                      height: 1.0,
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget inst(int i) {
      final off = _offsetAt(cur.grain, i);
      final p = LhZgPeriod(cur.grain, off);
      final on = off == cur.offset;
      return Semantics(
        button: true,
        selected: on,
        label: lhZgPeriodName(p),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => pickOffset(off),
          child: AnimatedContainer(
            duration: _dur(220),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minWidth: _kInstW - 4),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? DunesColors.resolve(context, Colors.white, role: DunesColorRole.surface) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: on ? const Color(0x2E7B5CD8) : Colors.transparent, width: 0.6),
              boxShadow: on
                  ? const [BoxShadow(color: Color(0x2E4A3A7A), blurRadius: 8, spreadRadius: -2, offset: Offset(0, 2))]
                  : const [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  lhZgPeriodName(p),
                  maxLines: 1,
                  style: LhTypography.sans(
                    size: 12.5,
                    weight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on ? _kInkStrong : _kMute,
                    height: 1.0,
                    context: context,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _instDetail(p),
                  maxLines: 1,
                  style: LhTypography.mono(
                    size: 8.5,
                    weight: FontWeight.w600,
                    color: on ? const Color(0xFF6A4FC9) : const Color(0xFF9A92BA),
                    height: 1.0,
                    context: context,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget label(String text) => Text(
      text,
      style: LhTypography.sans(size: 12, weight: FontWeight.w600, color: _kMute, height: 1.0, context: context),
    );

    final home = LhZgPeriod(cur.grain, 0);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: DunesColors.resolve(context, Colors.white, role: DunesColorRole.surface),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kDunesIslandEdge, width: 0.5),
        boxShadow: kDunesIslandPanelShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              label('看哪个周期'),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  lhZgPeriodRange(cur),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: LhTypography.mono(size: 11, weight: FontWeight.w700, color: _kInk, height: 1.0, context: context),
                ),
              ),
            ],
          ),
          if (widget.grains.length > 1) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < widget.grains.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  grain(widget.grains[i]),
                ],
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              label('往前翻'),
              const SizedBox(width: 6),
              const Icon(Icons.west_rounded, size: 12, color: Color(0xFFB0A8CC)),
              const Spacer(),
              if (cur.offset != 0)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => pickOffset(0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(color: const Color(0x147B5CD8), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      '回到${lhZgPeriodName(home)}',
                      style: LhTypography.sans(size: 11, weight: FontWeight.w700, color: const Color(0xFF6A4FC9), height: 1.0, context: context),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 50,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: const Color(0x0F7B5CD8), borderRadius: BorderRadius.circular(16)),
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (b) => const LinearGradient(
                colors: [Color(0x00000000), Color(0xFF000000)],
                stops: [0.0, 0.1],
              ).createShader(b),
              child: ListView.builder(
                controller: scroll,
                reverse: true,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: _count(cur.grain),
                itemBuilder: (c, i) => inst(i),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
