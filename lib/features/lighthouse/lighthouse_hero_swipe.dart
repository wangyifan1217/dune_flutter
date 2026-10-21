import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

// ═════════════════════════════════════════════════════════════════════════════
// 主 Hero 的两个滑动手势（2026-10-21）
//
//   ① 走势卡左滑拉宽：大数卡收成一根竖条，走势卡吃掉腾出来的宽度，
//      一屏多看一倍历史；拉到头还往左拽 → 松手直接进全屏大图。
//      往右拽 / 点竖条 → 还原。
//   ② 大数卡左滑翻页：本日利润 ⇄ 资金与资产，同一张卡里翻，不再往下展开。
//
// 两件事用同一根弹簧，手感一致：轻微过冲、不晃第二下。
// 只管手势和几何，不管内容 —— 内容全由 native_lighthouse_page 传进来，
// 所以这里不依赖灯塔的私有类，也不认识任何指标。
// ═════════════════════════════════════════════════════════════════════════════

/// 收起后大数卡剩下的竖条宽度。40 刚好放下「4.40」+ 一颗回位钮；
/// 再窄数字要缩到 10px 以下，等于没写。
const double lighthouseHeroWideRailWidth = 40;

/// 拉宽到头后还能再往左拽多少（占可拉行程的比例）才算「要看大图」。
const double lighthouseHeroWideOverpull = 0.16;

/// 两个手势共用的弹簧：临界阻尼约 41，这里给 30 —— 落位时过冲一点点，
/// 像被吸到位，而不是硬停。
const SpringDescription lighthouseHeroSwipeSpring = SpringDescription(
  mass: 1,
  stiffness: 420,
  damping: 30,
);

/// 甩得够快就按方向走，不看停在哪（px/s）。
const double _kFlingVelocity = 320;

/// 出界后的阻尼：越往外拽越沉，最多拽出这么多。
double _rubber(double over, double delta) => delta / (1 + over * 10);

// ─────────────────────────────────────────────────────────────────────────────
// ① 大数卡 | 走势卡 —— 左右拉伸
// ─────────────────────────────────────────────────────────────────────────────

class LighthouseHeroWideRow extends StatefulWidget {
  const LighthouseHeroWideRow({
    super.key,
    required this.kpi,
    required this.rail,
    required this.trend,
    required this.wide,
    required this.onWideChanged,
    this.onOverpull,
    this.overpullHint,
    this.kpiFlex = 3,
    this.trendFlex = 7,
    this.gap = 10,
    this.railWidth = lighthouseHeroWideRailWidth,
    this.radius = 12,
    this.accent = const Color(0xFF7B5CD8),
  });

  /// 平常的大数卡（按 kpiFlex 的宽度排版，拉伸过程中宽度不变、只被裁）。
  final Widget kpi;

  /// 收起后的竖条。
  final Widget rail;

  /// 走势卡。图里的横拖（翻历史 / 扫点）照旧归图自己 ——
  /// 这里的横拖只在图例、表头这些空白处和两卡之间的中缝生效。
  final Widget trend;

  final bool wide;
  final ValueChanged<bool> onWideChanged;

  /// 拉宽到头还往左拽、松手 → 调它（打开全屏大图）。null = 没有这一档。
  final VoidCallback? onOverpull;

  /// 过拉时浮在走势卡左缘的提示（「松手看大图」）。
  final Widget? overpullHint;

  final int kpiFlex;
  final int trendFlex;
  final double gap;
  final double railWidth;
  final double radius;
  final Color accent;

  @override
  State<LighthouseHeroWideRow> createState() => _LighthouseHeroWideRowState();
}

class _LighthouseHeroWideRowState extends State<LighthouseHeroWideRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController.unbounded(
    vsync: this,
    value: widget.wide ? 1 : 0,
  );
  late double _target = widget.wide ? 1 : 0;
  double _span = 1;
  bool _dragging = false;
  bool _lastSide = false;
  bool _armed = false;

  @override
  void didUpdateWidget(LighthouseHeroWideRow old) {
    super.didUpdateWidget(old);
    final want = widget.wide ? 1.0 : 0.0;
    if (!_dragging && want != _target) _settle(want, 0);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _settle(double target, double velocity) {
    _target = target;
    _t.animateWith(
      SpringSimulation(lighthouseHeroSwipeSpring, _t.value, target, velocity),
    );
  }

  void _onStart(DragStartDetails d) {
    _t.stop();
    _dragging = true;
    _lastSide = _t.value >= 0.5;
    setState(() {});
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    final cur = _t.value;
    final step = -d.delta.dx / _span;
    final over = cur < 0 ? -cur : (cur > 1 ? cur - 1 : 0.0);
    final goingOut = (cur <= 0 && step < 0) || (cur >= 1 && step > 0);
    final next = (cur + (goingOut ? _rubber(over, step) : step))
        .clamp(-0.2, 1.0 + lighthouseHeroWideOverpull * 1.6)
        .toDouble();
    final side = next >= 0.5;
    if (side != _lastSide) {
      _lastSide = side;
      HapticFeedback.selectionClick();
    }
    final armed =
        widget.onOverpull != null && next >= 1 + lighthouseHeroWideOverpull;
    if (armed != _armed) {
      _armed = armed;
      if (armed) HapticFeedback.mediumImpact();
    }
    _t.value = next;
  }

  void _onEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final vx = d.velocity.pixelsPerSecond.dx;
    final wide = vx.abs() > _kFlingVelocity ? vx < 0 : _t.value >= 0.5;
    final overpulled = _armed && wide;
    _armed = false;
    _settle(wide ? 1 : 0, (-vx / _span).clamp(-10.0, 10.0).toDouble());
    setState(() {});
    if (wide != widget.wide) widget.onWideChanged(wide);
    if (overpulled) widget.onOverpull?.call();
  }

  void _onCancel() {
    if (!_dragging) return;
    _dragging = false;
    _armed = false;
    _settle(widget.wide ? 1 : 0, 0);
    setState(() {});
  }

  GestureDetector _dragZone({required Widget child, HitTestBehavior? behavior}) {
    return GestureDetector(
      behavior: behavior,
      onHorizontalDragStart: _onStart,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: _onCancel,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final normalKpi =
            (w - widget.gap) * widget.kpiFlex / (widget.kpiFlex + widget.trendFlex);
        _span = math.max(1.0, normalKpi - widget.railWidth);
        return AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final t = _t.value;
            final kpiW = lerpDouble(normalKpi, widget.railWidth, t)!
                .clamp(widget.railWidth * 0.7, normalKpi * 1.12)
                .toDouble();
            // 大数先走、竖条后到，中间有一小段两者叠着淡入淡出。
            final kpiFade = (1 - t / 0.55).clamp(0.0, 1.0).toDouble();
            final railFade = ((t - 0.4) / 0.45).clamp(0.0, 1.0).toDouble();
            final overpull = widget.onOverpull == null
                ? 0.0
                : ((t - 1.02) / (lighthouseHeroWideOverpull - 0.02))
                      .clamp(0.0, 1.0)
                      .toDouble();
            final resting = !_dragging && t.abs() < 0.001;
            final grip = _dragging || overpull > 0;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: kpiW,
                      child: ClipRRect(
                        // 静止在原位时不裁：大数卡里环比行允许略溢出。
                        clipBehavior: resting ? Clip.none : Clip.antiAlias,
                        borderRadius: BorderRadius.circular(widget.radius),
                        child: Stack(
                          fit: StackFit.expand,
                          clipBehavior: Clip.none,
                          children: [
                            if (kpiFade > 0)
                              OverflowBox(
                                alignment: Alignment.centerLeft,
                                minWidth: normalKpi,
                                maxWidth: normalKpi,
                                child: IgnorePointer(
                                  ignoring: t > 0.3,
                                  child: Opacity(
                                    opacity: kpiFade,
                                    child: Transform.translate(
                                      offset: Offset(
                                        -16 * t.clamp(0.0, 1.0).toDouble(),
                                        0,
                                      ),
                                      child: widget.kpi,
                                    ),
                                  ),
                                ),
                              ),
                            if (railFade > 0)
                              IgnorePointer(
                                ignoring: t < 0.6,
                                child: Opacity(
                                  opacity: railFade,
                                  child: _dragZone(child: widget.rail),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: widget.gap),
                    Expanded(child: _dragZone(child: widget.trend)),
                  ],
                ),
                // 中缝：一颗小把手，拖它最直接。热区左右各探出 6px。
                Positioned(
                  left: kpiW - 6,
                  width: widget.gap + 12,
                  top: 0,
                  bottom: 0,
                  child: Semantics(
                    button: true,
                    label: widget.wide ? '收起走势，回到大数' : '拉宽走势',
                    onTap: () => widget.onWideChanged(!widget.wide),
                    child: _dragZone(
                      behavior: HitTestBehavior.translucent,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: grip ? 4 : 3,
                          height: grip ? 34 : 24,
                          decoration: BoxDecoration(
                            color: widget.accent.withAlpha(grip ? 150 : 52),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (overpull > 0 && widget.overpullHint != null)
                  Positioned(
                    left: kpiW + widget.gap + 8,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Opacity(
                          opacity: overpull,
                          child: Transform.scale(
                            scale: 0.86 + 0.14 * overpull,
                            alignment: Alignment.centerLeft,
                            child: widget.overpullHint,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ② 大数卡内翻页
// ─────────────────────────────────────────────────────────────────────────────

class LighthouseHeroCardPager extends StatefulWidget {
  const LighthouseHeroCardPager({
    super.key,
    required this.pages,
    required this.page,
    required this.onPageChanged,
    this.accent = const Color(0xFF7B5CD8),
    this.indicatorBottom = 3,
    this.tabs,
    this.tabStyle,
    this.tabActiveStyle,
    this.position,
  });

  final List<Widget> pages;

  /// 非空时底部画一排文字页签（「利润 · 资金」）+ 一根跟手滑的短条，
  /// 代替小圆点；页签可点。页面自己要在底部留 ~24 的空。
  final List<String>? tabs;
  final TextStyle? tabStyle;
  final TextStyle? tabActiveStyle;

  /// 跟手的页位置（0…n-1，带小数）。外面可以拿它让别的东西跟着翻
  /// （主 Hero 右边的走势卡随左边换模式）。只在手势 / 动画里写，不在 build 里写。
  final ValueNotifier<double>? position;
  final int page;
  final ValueChanged<int> onPageChanged;
  final Color accent;

  /// 页码条离底边多远（底下紧贴着 BI 栏，留 3 就够）。
  final double indicatorBottom;

  @override
  State<LighthouseHeroCardPager> createState() =>
      _LighthouseHeroCardPagerState();
}

class _LighthouseHeroCardPagerState extends State<LighthouseHeroCardPager>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pos = AnimationController.unbounded(
    vsync: this,
    value: widget.page.toDouble(),
  );
  late int _target = widget.page;
  double _w = 1;
  bool _dragging = false;

  int get _last => math.max(0, widget.pages.length - 1);

  @override
  void initState() {
    super.initState();
    _pos.addListener(_publish);
  }

  void _publish() {
    final p = widget.position;
    if (p != null && p.value != _pos.value) p.value = _pos.value;
  }

  void _goTo(int page) {
    final target = page.clamp(0, _last).toInt();
    if (target == widget.page) return;
    _settle(target, 0);
    HapticFeedback.selectionClick();
    widget.onPageChanged(target);
  }

  @override
  void didUpdateWidget(LighthouseHeroCardPager old) {
    super.didUpdateWidget(old);
    final want = widget.page.clamp(0, _last).toInt();
    if (!_dragging && want != _target) _settle(want, 0);
  }

  @override
  void dispose() {
    _pos.removeListener(_publish);
    _pos.dispose();
    super.dispose();
  }

  void _settle(int target, double velocity) {
    _target = target;
    _pos.animateWith(
      SpringSimulation(
        lighthouseHeroSwipeSpring,
        _pos.value,
        target.toDouble(),
        velocity,
      ),
    );
  }

  void _onStart(DragStartDetails d) {
    _pos.stop();
    _dragging = true;
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    final cur = _pos.value;
    final step = -d.delta.dx / _w;
    final over = cur < 0 ? -cur : (cur > _last ? cur - _last : 0.0);
    final goingOut = (cur <= 0 && step < 0) || (cur >= _last && step > 0);
    _pos.value = (cur + (goingOut ? _rubber(over, step) : step))
        .clamp(-0.3, _last + 0.3)
        .toDouble();
  }

  void _onEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final vx = d.velocity.pixelsPerSecond.dx;
    final cur = _pos.value;
    var target = cur.round();
    if (vx.abs() > _kFlingVelocity) {
      target = vx < 0 ? cur.floor() + 1 : cur.ceil() - 1;
    }
    target = target.clamp(0, _last).toInt();
    _settle(target, (-vx / _w).clamp(-10.0, 10.0).toDouble());
    if (target != widget.page) {
      HapticFeedback.selectionClick();
      widget.onPageChanged(target);
    }
  }

  void _onCancel() {
    if (!_dragging) return;
    _dragging = false;
    _settle(widget.page.clamp(0, _last).toInt(), 0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.length < 2) {
      return widget.pages.isEmpty ? const SizedBox.shrink() : widget.pages.first;
    }
    return LayoutBuilder(
      builder: (context, box) {
        _w = math.max(1.0, box.maxWidth);
        return GestureDetector(
          onHorizontalDragStart: _onStart,
          onHorizontalDragUpdate: _onUpdate,
          onHorizontalDragEnd: _onEnd,
          onHorizontalDragCancel: _onCancel,
          child: AnimatedBuilder(
            animation: _pos,
            builder: (context, _) {
              final pos = _pos.value;
              // 翻动时裁到卡内（下一页不能画到走势卡上）；
              // 停稳后不裁，大数卡里环比行允许略溢出。
              final moving = _dragging || (pos - pos.round()).abs() > 0.001;
              return ClipRect(
                clipBehavior: moving ? Clip.hardEdge : Clip.none,
                child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < widget.pages.length; i++)
                    _page(i, pos),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: widget.indicatorBottom,
                    child: widget.tabs == null
                        ? IgnorePointer(child: _indicator(pos))
                        : _tabBar(pos),
                  ),
                ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _page(int i, double pos) {
    final d = i - pos;
    final far = d.abs();
    // 离开的那页走得慢一点（0.82 倍）、略缩、变淡 —— 像被下一页压过去。
    final dx = (d < 0 ? d * 0.82 : d) * _w;
    final visible = far < 0.999;
    return Positioned.fill(
      child: Visibility(
        visible: visible,
        maintainState: true,
        maintainAnimation: true,
        child: IgnorePointer(
          ignoring: far > 0.5,
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: Transform.scale(
              scale: 1 - 0.05 * far.clamp(0.0, 1.0),
              child: Opacity(
                opacity: (1 - 0.6 * far).clamp(0.0, 1.0).toDouble(),
                child: widget.pages[i],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 文字页签：「利润 · 资金」，当前页加粗变紫，下面一根 18×2 的短条跟手滑。
  Widget _tabBar(double pos) {
    final tabs = widget.tabs!;
    final n = tabs.length;
    final active = pos.round().clamp(0, n - 1);
    return SizedBox(
      height: 20,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: LayoutBuilder(
          builder: (context, box) {
            final slot = box.maxWidth / n;
            final x = pos.clamp(-0.15, n - 1 + 0.15) * slot;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: i == active,
                          label: tabs[i],
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _goTo(i),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 160),
                                style: (i == active
                                        ? widget.tabActiveStyle
                                        : widget.tabStyle) ??
                                    const TextStyle(fontSize: 10.5),
                                child: Text(tabs[i], maxLines: 1),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Positioned(
                  left: x + (slot - 18) / 2,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 18,
                      height: 2,
                      decoration: BoxDecoration(
                        color: widget.accent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 页码：一根短条在槽里滑，跟手走，不是两颗跳格的圆点。
  Widget _indicator(double pos) {
    const dot = 4.0, active = 12.0, gap = 3.0;
    final n = widget.pages.length;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          Builder(
            builder: (_) {
              final near = (1 - (pos - i).abs()).clamp(0.0, 1.0).toDouble();
              return Container(
                width: dot + (active - dot) * near,
                height: 3,
                decoration: BoxDecoration(
                  color: widget.accent.withAlpha((60 + 150 * near).round()),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
