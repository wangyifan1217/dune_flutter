import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// App 紫渐变（Gemini 星芒形态 + 通讯紫）。
const List<Color> kAiSummaryPurpleGradient = <Color>[
  Color(0xFFE9D5FF),
  Color(0xFFB794F4),
  Color(0xFF7B5CD8),
  Color(0xFF5B3FA0),
];

/// 智能总结入口：Gemini 式四角星芒。
/// 动画只改绘制透明度，不用 Transform/Opacity，避免带动整页（含搜索栏）抖动。
class AiSummarySparkleIcon extends StatefulWidget {
  const AiSummarySparkleIcon({
    super.key,
    required this.onTap,
    this.size = 22,
    this.animate = true,
  });

  final VoidCallback onTap;
  final double size;
  final bool animate;

  @override
  State<AiSummarySparkleIcon> createState() => _AiSummarySparkleIconState();
}

class _AiSummarySparkleIconState extends State<AiSummarySparkleIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.animate) {
      _controller.repeat(reverse: true);
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant AiSummarySparkleIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '智能总结',
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: RepaintBoundary(
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final t = Curves.easeInOut.transform(_controller.value);
                    return CustomPaint(
                      painter: GeminiSparklePainter(
                        colors: kAiSummaryPurpleGradient,
                        showCompanion: true,
                        pulse: 0.72 + 0.28 * t,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 会话列表头像：大星 + 小星，无方底。
class AiSummaryAvatarMark extends StatelessWidget {
  const AiSummaryAvatarMark({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(
        painter: GeminiSparklePainter(
          colors: kAiSummaryPurpleGradient,
          showCompanion: true,
          pulse: 1,
        ),
      ),
    );
  }
}

/// Gemini 风格四角星：尖角 + 内凹腰线，线性紫渐变。
class GeminiSparklePainter extends CustomPainter {
  const GeminiSparklePainter({
    required this.colors,
    this.showCompanion = false,
    this.pulse = 1,
  });

  final List<Color> colors;
  final bool showCompanion;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final mainCenter = showCompanion
        ? Offset(s * 0.42, s * 0.40)
        : Offset(size.width / 2, size.height / 2);
    final mainRadius = showCompanion ? s * 0.36 : s * 0.46;

    _drawSparkle(
      canvas,
      center: mainCenter,
      radius: mainRadius,
      colors: colors,
      alpha: pulse.clamp(0.0, 1.0),
    );

    if (showCompanion) {
      _drawSparkle(
        canvas,
        center: Offset(s * 0.72, s * 0.70),
        radius: s * 0.14,
        colors: <Color>[
          colors.first,
          colors[colors.length ~/ 2],
          colors.last,
        ],
        alpha: (pulse * 0.9).clamp(0.0, 1.0),
      );
    }
  }

  void _drawSparkle(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required List<Color> colors,
    required double alpha,
  }) {
    final path = _geminiSparklePath(center, radius);
    final bounds = path.getBounds().inflate(0.5);
    // dart:ui Gradient.linear：未传 colorStops 时 colors 必须恰好 2 个；
    // 多色需显式 stops（Windows 桌面端会因此直接 paint 失败）。
    final shaded = colors
        .map((c) => c.withValues(alpha: (c.a * alpha).clamp(0.0, 1.0)))
        .toList(growable: false);
    final stops = shaded.length <= 2
        ? null
        : List<double>.generate(
            shaded.length,
            (i) => i / (shaded.length - 1),
          );
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..shader = ui.Gradient.linear(
        bounds.topLeft,
        bounds.bottomRight,
        shaded.length >= 2
            ? shaded
            : <Color>[
                shaded.isEmpty ? const Color(0xFF7B5CD8) : shaded.first,
                shaded.isEmpty ? const Color(0xFF5B3FA0) : shaded.first,
              ],
        stops,
      );
    canvas.drawPath(path, paint);
  }

  Path _geminiSparklePath(Offset center, double radius) {
    final path = Path();
    final pinch = radius * 0.12;

    for (var i = 0; i < 4; i++) {
      final angle = -math.pi / 2 + i * math.pi / 2;
      final tip = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      final nextAngle = angle + math.pi / 2;
      final nextTip = Offset(
        center.dx + math.cos(nextAngle) * radius,
        center.dy + math.sin(nextAngle) * radius,
      );
      final mid = angle + math.pi / 4;
      final ctrl = Offset(
        center.dx + math.cos(mid) * pinch,
        center.dy + math.sin(mid) * pinch,
      );

      if (i == 0) {
        path.moveTo(tip.dx, tip.dy);
      }
      path.quadraticBezierTo(ctrl.dx, ctrl.dy, nextTip.dx, nextTip.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant GeminiSparklePainter oldDelegate) {
    return oldDelegate.colors != colors ||
        oldDelegate.showCompanion != showCompanion ||
        oldDelegate.pulse != pulse;
  }
}
