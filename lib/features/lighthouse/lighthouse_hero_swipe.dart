import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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
//
// 2026-10-26 · 手机适配：
//   · 所有横拖都走 [LighthouseDirectionalHDrag]：横向位移要明显大于竖向
//     （默认 1.4 倍）才接，斜着滚页面不会误触；阈值按设备取（iOS / 安卓 / 鼠标）。
//   · 图里的横拖先翻历史，翻到最新还往左拖 → 剩下的位移经
//     [LighthouseHeroWideScope] 交给拉宽（内层滚到头带动外层），不再两个手势抢。
//   · 拉宽过程里 [LighthouseHeroWideHandoff.progress] 是连续的，图据此连续加点，
//     松手不再从 7 点跳到 14 点。
//   · ③ [LighthouseFoldSection]：规模 / 成本 / 利润上滑收起，高度跟手。
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
// 方向锁横拖
// ─────────────────────────────────────────────────────────────────────────────

/// 横拖识别器，带方向锁：横向位移过了触摸阈值、并且 |dx| > ratio·|dy| 才接。
/// 斜着划（多半是在滚页面）就不接，竖向滚动自然赢。
class LighthouseDirectionalHDrag extends HorizontalDragGestureRecognizer {
  LighthouseDirectionalHDrag({super.debugOwner, this.ratio = 1.4});

  final double ratio;
  double _sx = 0, _sy = 0;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _sx = 0;
    _sy = 0;
    super.addAllowedPointer(event);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    _sx = 0;
    _sy = 0;
    super.addAllowedPointerPanZoom(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      _sx += event.delta.dx;
      _sy += event.delta.dy;
    } else if (event is PointerPanZoomUpdateEvent) {
      _sx += event.panDelta.dx;
      _sy += event.panDelta.dy;
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      ) &&
      _sx.abs() > ratio * _sy.abs();
}

/// [GestureDetector] 横拖那四个回调的方向锁版本。回调全空时原样返回 child。
class LighthouseHDrag extends StatelessWidget {
  const LighthouseHDrag({
    super.key,
    required this.child,
    this.onStart,
    this.onUpdate,
    this.onEnd,
    this.onCancel,
    this.behavior,
    this.ratio = 1.4,
  });

  final Widget child;
  final GestureDragStartCallback? onStart;
  final GestureDragUpdateCallback? onUpdate;
  final GestureDragEndCallback? onEnd;
  final GestureDragCancelCallback? onCancel;
  final HitTestBehavior? behavior;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    if (onStart == null && onUpdate == null && onEnd == null) return child;
    final settings = MediaQuery.maybeGestureSettingsOf(context);
    return RawGestureDetector(
      behavior: behavior,
      gestures: <Type, GestureRecognizerFactory>{
        LighthouseDirectionalHDrag:
            GestureRecognizerFactoryWithHandlers<LighthouseDirectionalHDrag>(
              () => LighthouseDirectionalHDrag(debugOwner: this, ratio: ratio),
              (r) {
                r
                  ..gestureSettings = settings
                  ..onStart = onStart
                  ..onUpdate = onUpdate
                  ..onEnd = onEnd
                  ..onCancel = onCancel;
              },
            ),
      },
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 拉宽接力：图翻到最新还往左拖，把剩下的位移交给外层
// ─────────────────────────────────────────────────────────────────────────────

abstract class LighthouseHeroWideHandoff {
  /// 0 = 平常 · 1 = 拉宽（拖动 / 回弹中带小数，橡皮筋时会略出界）。
  ValueListenable<double> get progress;
  void begin();

  /// 手指横向位移（px，往左为负）。
  void update(double dx);

  /// 松手时的横向速度（px/s）。
  void end(double vx);
  void cancel();
}

class LighthouseHeroWideScope extends InheritedWidget {
  const LighthouseHeroWideScope({
    super.key,
    required this.handoff,
    required super.child,
  });

  final LighthouseHeroWideHandoff handoff;

  static LighthouseHeroWideHandoff? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<LighthouseHeroWideScope>()
      ?.handoff;

  @override
  bool updateShouldNotify(LighthouseHeroWideScope oldWidget) =>
      oldWidget.handoff != handoff;
}

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
    with SingleTickerProviderStateMixin
    implements LighthouseHeroWideHandoff {
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

  // ── 接力（图里翻到最新还往左拖）───────────────────────────────────────
  @override
  ValueListenable<double> get progress => _t;

  @override
  void begin() => _startDrag();

  @override
  void update(double dx) => _updateDrag(dx);

  @override
  void end(double vx) => _endDrag(vx);

  @override
  void cancel() => _onCancel();

  void _onStart(DragStartDetails d) => _startDrag();
  void _onUpdate(DragUpdateDetails d) => _updateDrag(d.delta.dx);
  void _onEnd(DragEndDetails d) => _endDrag(d.velocity.pixelsPerSecond.dx);

  void _startDrag() {
    _t.stop();
    _dragging = true;
    _lastSide = _t.value >= 0.5;
    setState(() {});
  }

  void _updateDrag(double dx) {
    if (!_dragging) return;
    final cur = _t.value;
    final step = -dx / _span;
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

  void _endDrag(double vx) {
    if (!_dragging) return;
    _dragging = false;
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

  Widget _dragZone({required Widget child, HitTestBehavior? behavior}) {
    return LighthouseHDrag(
      behavior: behavior,
      onStart: _onStart,
      onUpdate: _onUpdate,
      onEnd: _onEnd,
      onCancel: _onCancel,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LighthouseHeroWideScope(handoff: this, child: _buildRow());
  }

  Widget _buildRow() {
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
    this.tabThumbColor = Colors.white,
    this.tabsAtTop = false,
    this.tabHeight = 28,
    this.position,
  });

  final List<Widget> pages;

  /// 非空时底部画一条通栏分段切换（「利润 | 资金」），白色滑块跟手走，
  /// 代替小圆点；每半边整块可点。页面自己要在底部留 ~36 的空。
  final List<String>? tabs;
  final TextStyle? tabStyle;
  final TextStyle? tabActiveStyle;

  /// 分段条滑块的底色（深色模式由外面传解析过的表面色）。
  final Color tabThumbColor;

  /// 分段条钉在顶上（[indicatorBottom] 这时当作离顶边的距离）。
  /// 页面自己要在顶部留出 tabHeight + 间距。
  final bool tabsAtTop;
  final double tabHeight;

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
        return LighthouseHDrag(
          onStart: _onStart,
          onUpdate: _onUpdate,
          onEnd: _onEnd,
          onCancel: _onCancel,
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
                    top: widget.tabs != null && widget.tabsAtTop
                        ? widget.indicatorBottom
                        : null,
                    bottom: widget.tabs != null && widget.tabsAtTop
                        ? null
                        : widget.indicatorBottom,
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

  /// 「利润 | 资金」分段切换条（2026-10-26）：原来是 10.5 号小字 + 18×2 短条，
  /// 点不准。改成通栏 28 高的分段钮 —— 淡紫底槽里一块白色滑块跟手走，
  /// 每半边都是整块热区；整条也可以横拖翻页（手势归外层 pager）。
  Widget _tabBar(double pos) {
    final tabs = widget.tabs!;
    final n = tabs.length;
    final active = pos.round().clamp(0, n - 1);
    final h = widget.tabHeight;
    const pad = 2.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        height: h,
        padding: const EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: widget.accent.withAlpha(20),
          borderRadius: BorderRadius.circular(h / 2.6),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final slot = box.maxWidth / n;
            final x = pos.clamp(0.0, (n - 1).toDouble()) * slot;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: x,
                  top: 0,
                  bottom: 0,
                  width: slot,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.tabThumbColor,
                        borderRadius: BorderRadius.circular(h / 2.6 - 2),
                        boxShadow: [
                          BoxShadow(
                            color: widget.accent.withAlpha(38),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
                                    const TextStyle(fontSize: 12),
                                child: Text(tabs[i], maxLines: 1),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
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

// ─────────────────────────────────────────────────────────────────────────────
// ③ 规模 / 成本 / 利润 —— 上滑收起（2026-10-26）
// ─────────────────────────────────────────────────────────────────────────────
//
//   只收这一块；大数卡和走势卡不动。把手在这块下面：往上推，这块的高度跟着
//   手指一格一格变矮（下面的列表跟着上来，不跳）；松手按位置 / 速度吸到收起或
//   展开，带一点弹簧。往下拉、或点把手，展开。
//   外层如果包着 AnimatedSize，拖动 / 回弹期间要让它让开（[onMovingChanged]），
//   否则它会把每一帧的高度变化再补间一遍，手感就成了「拖着橡皮走」。

class LighthouseFoldSection extends StatefulWidget {
  const LighthouseFoldSection({
    super.key,
    required this.child,
    required this.folded,
    required this.onFoldedChanged,
    required this.handleBuilder,
    this.onMovingChanged,
  });

  final Widget child;
  final bool folded;
  final ValueChanged<bool> onFoldedChanged;

  /// 把手。[progress]：0 展开 · 1 收起（拖动中带小数）。
  final Widget Function(BuildContext context, double progress) handleBuilder;

  /// 拖动或回弹开始 / 结束。
  final ValueChanged<bool>? onMovingChanged;

  @override
  State<LighthouseFoldSection> createState() => _LighthouseFoldSectionState();
}

class _LighthouseFoldSectionState extends State<LighthouseFoldSection>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController.unbounded(
    vsync: this,
    value: widget.folded ? 1 : 0,
  );
  final GlobalKey _childKey = GlobalKey();
  late double _target = widget.folded ? 1 : 0;
  bool _dragging = false;
  bool _moving = false;
  bool _lastSide = false;

  /// 这块展开时的高度（拖动时把像素换成进度用）。
  double get _h =>
      math.max(40.0, _childKey.currentContext?.size?.height ?? 120.0);

  @override
  void didUpdateWidget(LighthouseFoldSection old) {
    super.didUpdateWidget(old);
    // 自己松手已经朝这个方向弹了（带着甩的速度）就别重开一根零速弹簧。
    final want = widget.folded ? 1.0 : 0.0;
    if (!_dragging && want != _target) _settle(want, 0);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  void _setMoving(bool m) {
    if (_moving == m) return;
    _moving = m;
    widget.onMovingChanged?.call(m);
  }

  void _settle(double target, double velocity) {
    _target = target;
    _setMoving(true);
    _t
        .animateWith(
          SpringSimulation(lighthouseHeroSwipeSpring, _t.value, target, velocity),
        )
        .whenCompleteOrCancel(() {
          if (mounted && !_dragging) _setMoving(false);
        });
  }

  void _commit(bool folded, double velocity) {
    _settle(folded ? 1 : 0, velocity);
    if (folded != widget.folded) widget.onFoldedChanged(folded);
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    _commit(!widget.folded, 0);
  }

  void _onStart(DragStartDetails d) {
    _t.stop();
    _dragging = true;
    _lastSide = _t.value >= 0.5;
    _setMoving(true);
  }

  void _onUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    final cur = _t.value;
    final step = -d.delta.dy / _h;
    final over = cur < 0 ? -cur : (cur > 1 ? cur - 1 : 0.0);
    final goingOut = (cur <= 0 && step < 0) || (cur >= 1 && step > 0);
    final next = (cur + (goingOut ? _rubber(over, step) : step))
        .clamp(-0.12, 1.12)
        .toDouble();
    final side = next >= 0.5;
    if (side != _lastSide) {
      _lastSide = side;
      HapticFeedback.selectionClick();
    }
    _t.value = next;
  }

  void _onEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final vy = d.velocity.pixelsPerSecond.dy;
    final folded = vy.abs() > _kFlingVelocity ? vy < 0 : _t.value >= 0.5;
    _commit(folded, (-vy / _h).clamp(-10.0, 10.0).toDouble());
  }

  void _onCancel() {
    if (!_dragging) return;
    _dragging = false;
    _settle(widget.folded ? 1 : 0, 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) {
        final t = _t.value;
        final p = t.clamp(0.0, 1.0).toDouble();
        // 往下拽出界时 heightFactor > 1：多出来的一点空白就是橡皮筋。
        final factor = (1 - t).clamp(0.0, 1.06).toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: factor,
                child: IgnorePointer(
                  ignoring: p > 0.5,
                  child: Opacity(
                    // 比高度先走一步淡掉：收到一半时内容已经看不见，不会半截压着。
                    opacity: (1 - p * 1.5).clamp(0.0, 1.0).toDouble(),
                    child: KeyedSubtree(key: _childKey, child: widget.child),
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              onVerticalDragStart: _onStart,
              onVerticalDragUpdate: _onUpdate,
              onVerticalDragEnd: _onEnd,
              onVerticalDragCancel: _onCancel,
              child: widget.handleBuilder(context, p),
            ),
          ],
        );
      },
    );
  }
}
