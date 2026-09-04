import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ═════════════════════════════════════════════════════════════════════════════
// 灯塔 · 周期分段条（日 / 周 / 月 / 季 / 年）
//
//   静态的分段条只是"能点"，这条要"活着"。四层动效叠在一起，
//   每层都很轻，合起来才有质感：
//
//   1) 弹性滑块 —— 选中胶囊不是各格子各自变色，而是一整块滑过去；
//      滑行途中横向拉伸（squash & stretch），落位时收回，像有惯性。
//   2) 流光扫过 —— 胶囊表面每隔几秒有一道斜向高光掠过；切换粒度时
//      立刻重扫一次，让"我点中了"这件事有回响。
//   3) 辉光呼吸 —— 胶囊外圈紫色柔光缓慢明暗，选中态字也带一点光晕。
//   4) 边缘巡游光点 —— 一颗带拖尾的小光点沿胶囊圆角边框绕行，
//      这是"有东西在上面动"的那个东西。
//   5) 点击涟漪 —— 从手指落点扩散一圈紫环，320ms 内消失。
//
//   全部走一个 CustomPainter + 一个 RepaintBoundary，只重绘这一条，
//   不牵动页面其余部分。系统开启"减弱动效"时自动退化为静态样式。
// ═════════════════════════════════════════════════════════════════════════════

class LhPeriodBar extends StatefulWidget {
  const LhPeriodBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onTap,
    required this.baseTextStyle,
    this.pickerOpen = false,
    this.height = 44,
    this.trackRadius = 12,
    this.pillRadius = 8,
    this.dotSize = 4,
    this.floating = true,
    this.primary = const Color(0xFF7B5CD8),
    this.deep = const Color(0xFF5A458F),
    this.trackColor = const Color(0xFFFFFFFF),
    this.trackBorder = const Color(0xFFE5E1D3),
    this.idleTextColor = const Color(0xFF5A5C56),
  });

  /// 短标签，如 ['日','周','月','季','年']
  final List<String> labels;

  /// 当前选中下标；-1 表示无选中（例如自定义区间生效时）
  final int selectedIndex;

  /// 选中项是否展开了实例选择条（决定 ▾ 的朝向）
  final bool pickerOpen;

  final ValueChanged<int> onTap;

  /// 标签基础字体样式，组件只覆写 color / fontWeight / shadows
  final TextStyle baseTextStyle;

  final double height;
  final double trackRadius;
  final double pillRadius;
  final double dotSize;

  /// 是否绘制外层悬浮轨道（白底 + 描边 + 投影）
  final bool floating;

  final Color primary;
  final Color deep;
  final Color trackColor;
  final Color trackBorder;
  final Color idleTextColor;

  @override
  State<LhPeriodBar> createState() => _LhPeriodBarState();
}

class _LhPeriodBarState extends State<LhPeriodBar>
    with TickerProviderStateMixin {
  // 呼吸辉光
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  // 流光扫过（一个周期里只有前 22% 在扫，其余时间留白）
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4600),
  );

  // 边缘巡游光点
  late final AnimationController _comet = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6200),
  );

  // 滑块位移
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  // 滑块整体淡入淡出（无选中态时收起）
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  // 点击涟漪
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );

  late Listenable _merged;

  double _from = 0;
  double _to = 0;
  double _rippleX = 0;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _merged = Listenable.merge([
      _glow,
      _shimmer,
      _comet,
      _slide,
      _fade,
      _ripple,
    ]);
    final i = widget.selectedIndex;
    _from = _to = (i < 0 ? 0 : i).toDouble();
    _slide.value = 1.0;
    _fade.value = i < 0 ? 0.0 : 1.0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncAmbient();
  }

  void _syncAmbient() {
    if (_reduced) {
      _glow.stop();
      _shimmer.stop();
      _comet.stop();
      _glow.value = 0.45;
      return;
    }
    if (!_glow.isAnimating) _glow.repeat(reverse: true);
    if (!_shimmer.isAnimating) _shimmer.repeat();
    if (!_comet.isAnimating) _comet.repeat();
  }

  @override
  void didUpdateWidget(covariant LhPeriodBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = widget.selectedIndex;
    final was = oldWidget.selectedIndex;
    if (now != was) {
      if (now >= 0) {
        _from = was >= 0 ? _currentPos() : now.toDouble();
        _to = now.toDouble();
        if (_reduced) {
          _slide.value = 1.0;
        } else {
          _slide.forward(from: 0);
          // 切换瞬间立刻补一道流光，让点击有回响
          _shimmer.repeat();
        }
        _fade.forward();
      } else {
        _fade.reverse();
      }
    }
  }

  double _currentPos() {
    final p = Curves.easeOutQuart.transform(_slide.value.clamp(0.0, 1.0));
    return _from + (_to - _from) * p;
  }

  @override
  void dispose() {
    _glow.dispose();
    _shimmer.dispose();
    _comet.dispose();
    _slide.dispose();
    _fade.dispose();
    _ripple.dispose();
    super.dispose();
  }

  void _handleTap(int i) {
    // _rippleX 已在 onTapDown 里按手指落点算好
    if (!_reduced) _ripple.forward(from: 0);
    widget.onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.labels.length;
    return RepaintBoundary(
      child: Container(
        height: widget.height,
        padding: const EdgeInsets.all(4),
        decoration: widget.floating
            ? BoxDecoration(
                color: widget.trackColor,
                border: Border.all(color: widget.trackBorder, width: 0.7),
                borderRadius: BorderRadius.circular(widget.trackRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(8),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              )
            : null,
        child: LayoutBuilder(
          builder: (ctx, c) {
            final trackW = c.maxWidth;
            final cellW = n == 0 ? trackW : trackW / n;
            return AnimatedBuilder(
              animation: _merged,
              builder: (ctx, _) {
                final glow = Curves.easeInOut.transform(_glow.value);
                final fade = Curves.easeOut.transform(_fade.value);
                final pos = _currentPos();

                // 滑行途中横向拉伸：起步张开，落位收回
                final dist = math.min(1.6, (_to - _from).abs());
                final travel = _slide.isAnimating
                    ? math.sin(math.pi * _slide.value.clamp(0.0, 1.0))
                    : 0.0;
                final grow = cellW * 0.17 * travel * dist;
                // 圆点 / ▾ 只在落位后出现，滑行途中收起
                final settle = 1 - 0.95 * travel;

                var pillW = cellW + grow;
                var pillL = pos * cellW - grow / 2;
                pillL = pillL.clamp(-1.0, math.max(-1.0, trackW - pillW + 1));

                double? shimmerT;
                if (!_reduced && fade > 0.02) {
                  const window = 0.22;
                  if (_shimmer.value < window) {
                    shimmerT = Curves.easeInOutSine.transform(
                      _shimmer.value / window,
                    );
                  }
                }

                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _LhPeriodFxPainter(
                          pillLeft: pillL,
                          pillWidth: pillW,
                          pillOpacity: fade,
                          radius: widget.pillRadius,
                          trackRadius: widget.trackRadius - 4,
                          glow: glow,
                          shimmer: shimmerT,
                          comet: (_reduced || fade < 0.02) ? null : _comet.value,
                          ripple: _ripple.isAnimating ? _ripple.value : null,
                          rippleX: _rippleX,
                          primary: widget.primary,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < n; i++)
                          Expanded(
                            child: _cell(
                              i,
                              cellW,
                              ((1 - (i - pos).abs()).clamp(0.0, 1.0)) * fade,
                              glow,
                              settle,
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _cell(int i, double cellW, double t, double glow, double settle) {
    final aux = (t * settle).clamp(0.0, 1.0);
    final style = widget.baseTextStyle.copyWith(
      color: Color.lerp(widget.idleTextColor, widget.deep, t),
      fontWeight: FontWeight.lerp(FontWeight.w500, FontWeight.w600, t),
      shadows: t > 0.05
          ? [
              Shadow(
                color: widget.primary.withValues(
                  alpha: 0.22 * t * (0.45 + 0.55 * glow),
                ),
                blurRadius: 7,
              ),
            ]
          : null,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _rippleX = i * cellW + d.localPosition.dx,
      onTap: () => _handleTap(i),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Text(
              widget.labels[i],
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
          if (aux > 0.02)
            Align(
              alignment: const Alignment(-0.5, 0),
              child: Opacity(
                opacity: aux,
                child: Container(
                  width: widget.dotSize * (0.85 + 0.35 * glow) * (0.4 + 0.6 * aux),
                  height:
                      widget.dotSize * (0.85 + 0.35 * glow) * (0.4 + 0.6 * aux),
                  decoration: BoxDecoration(
                    color: widget.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.primary.withValues(
                          alpha: 0.35 + 0.35 * glow,
                        ),
                        blurRadius: 4 + 3 * glow,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (aux > 0.02)
            Align(
              alignment: const Alignment(0.62, 0),
              child: Opacity(
                opacity: aux,
                child: AnimatedRotation(
                  turns: widget.pickerOpen ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 13,
                    color: widget.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 画笔 —— 胶囊底 / 外辉光 / 流光 / 巡游光点 / 涟漪
// ═════════════════════════════════════════════════════════════════════════════
class _LhPeriodFxPainter extends CustomPainter {
  const _LhPeriodFxPainter({
    required this.pillLeft,
    required this.pillWidth,
    required this.pillOpacity,
    required this.radius,
    required this.trackRadius,
    required this.glow,
    required this.shimmer,
    required this.comet,
    required this.ripple,
    required this.rippleX,
    required this.primary,
  });

  final double pillLeft;
  final double pillWidth;
  final double pillOpacity;
  final double radius;
  final double trackRadius;
  final double glow;
  final double? shimmer;
  final double? comet;
  final double? ripple;
  final double rippleX;
  final Color primary;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final o = pillOpacity.clamp(0.0, 1.0);

    if (o > 0.01 && pillWidth > 1) {
      final rect = Rect.fromLTWH(pillLeft, 0, pillWidth, h);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius));

      // ① 外辉光 —— 呼吸
      canvas.drawRRect(
        rr.inflate(1.2),
        Paint()
          ..color = primary.withValues(alpha: (0.10 + 0.14 * glow) * o)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 + 4.5 * glow),
      );

      // ② 胶囊底 —— 上浅下深的雾紫，顶部再压一层高光
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(rect.left, rect.top),
            Offset(rect.right, rect.bottom),
            [
              const Color(0xFFF6F1FD).withValues(alpha: o),
              const Color(0xFFE3D9F7).withValues(alpha: o),
              const Color(0xFFEFE9FB).withValues(alpha: o),
            ],
            const [0.0, 0.55, 1.0],
          ),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(rect.left, rect.top),
            Offset(rect.left, rect.bottom),
            [
              Colors.white.withValues(alpha: 0.75 * o),
              Colors.white.withValues(alpha: 0.0),
            ],
            const [0.0, 0.62],
          ),
      );

      // ③ 描边
      canvas.drawRRect(
        rr.deflate(0.35),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = primary.withValues(alpha: (0.20 + 0.16 * glow) * o),
      );

      // ④ 流光扫过
      final s = shimmer;
      if (s != null) {
        canvas.save();
        canvas.clipRRect(rr);
        final band = pillWidth * 0.26;
        final skew = h * 0.40;
        final span = pillWidth + band * 2 + skew;
        final cx = rect.left - band - skew + span * s;
        final path = Path()
          ..moveTo(cx - band, h)
          ..lineTo(cx - band + skew, 0)
          ..lineTo(cx + band + skew, 0)
          ..lineTo(cx + band, h)
          ..close();
        // 三角包络：中段最亮，两端消隐
        final env = math.sin(math.pi * s);
        canvas.drawPath(
          path,
          Paint()
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2)
            ..shader = ui.Gradient.linear(
              Offset(cx - band, 0),
              Offset(cx + band + skew, 0),
              [
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.98 * env * o),
                Colors.white.withValues(alpha: 0.55 * env * o),
                primary.withValues(alpha: 0.10 * env * o),
                Colors.white.withValues(alpha: 0.0),
              ],
              const [0.0, 0.40, 0.52, 0.66, 1.0],
            ),
        );
        canvas.restore();
      }

      // ⑤ 边缘巡游光点 —— 带拖尾，沿圆角边框绕行
      final cm = comet;
      if (cm != null) {
        final path = Path()..addRRect(rr.deflate(0.4));
        final metrics = path.computeMetrics().toList();
        if (metrics.isNotEmpty) {
          final m = metrics.first;
          final len = m.length;
          const trail = 0.20;
          const samples = 20;
          for (var i = 0; i < samples; i++) {
            final f = i / (samples - 1); // 0 = 尾  1 = 头
            var d = (cm - trail * (1 - f)) % 1.0;
            if (d < 0) d += 1.0;
            final tan = m.getTangentForOffset(d * len);
            if (tan == null) continue;
            final a = math.pow(f, 2.4).toDouble();
            canvas.drawCircle(
              tan.position,
              0.5 + 1.4 * f,
              Paint()
                ..color = Color.lerp(primary, Colors.white, 0.42 * f)!
                    .withValues(alpha: 0.70 * a * o),
            );
          }
          final head = m.getTangentForOffset((cm % 1.0) * len);
          if (head != null) {
            canvas.drawCircle(
              head.position,
              3.0,
              Paint()
                ..color = primary.withValues(alpha: 0.55 * o)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
            );
            canvas.drawCircle(
              head.position,
              1.15,
              Paint()..color = Colors.white.withValues(alpha: 0.95 * o),
            );
          }
        }
      }
    }

    // ⑥ 点击涟漪 —— 裁在轨道内
    final rp = ripple;
    if (rp != null) {
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(math.max(2, trackRadius)),
        ),
      );
      final p = Curves.easeOutCubic.transform(rp.clamp(0.0, 1.0));
      final a = (1 - rp).clamp(0.0, 1.0);
      final r = 5 + math.max(pillWidth, 24) * 1.9 * p;
      canvas.drawCircle(
        Offset(rippleX, h / 2),
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.4 + 1.5 * a
          ..color = primary.withValues(alpha: 0.34 * a * a),
      );
      canvas.drawCircle(
        Offset(rippleX, h / 2),
        r * 0.7,
        Paint()..color = primary.withValues(alpha: 0.06 * a),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _LhPeriodFxPainter old) =>
      old.pillLeft != pillLeft ||
      old.pillWidth != pillWidth ||
      old.pillOpacity != pillOpacity ||
      old.glow != glow ||
      old.shimmer != shimmer ||
      old.comet != comet ||
      old.ripple != ripple ||
      old.rippleX != rippleX ||
      old.radius != radius ||
      old.primary != primary;
}
