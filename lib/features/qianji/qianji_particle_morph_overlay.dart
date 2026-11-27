import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';

/// 饕模块新旧版切换：简洁克制的空间景深柔光过渡（无花哨粒子，单色品牌紫微光涟漪）。
class QianjiParticleMorphOverlay extends StatelessWidget {
  const QianjiParticleMorphOverlay({
    super.key,
    required this.progress,
    required this.toNewLayout,
    required this.isDark,
  });

  final double progress;
  final bool toNewLayout;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (progress <= 0.0 || progress >= 1.0) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _QianjiCleanMorphPainter(
            t: progress,
            toNewLayout: toNewLayout,
            isDark: isDark,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _QianjiCleanMorphPainter extends CustomPainter {
  _QianjiCleanMorphPainter({
    required this.t,
    required this.toNewLayout,
    required this.isDark,
  });

  final double t;
  final bool toNewLayout;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // 柔光涟漪从右上角切换按钮附近优雅扩散
    final origin = Offset(size.width * (toNewLayout ? 0.86 : 0.18), 52);
    final maxR = math.sqrt(size.width * size.width + size.height * size.height);
    final ease = Curves.easeOutCubic.transform(t);
    final fade = math.sin(t * math.pi).clamp(0.0, 1.0);

    final accent = isDark
        ? const Color(0xFFA78BFA)
        : DunesColors.brandPurple;

    // 1. 极轻微的单色柔雾扩散光晕
    final glowRadius = maxR * (0.18 + 0.92 * ease);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: fade * (isDark ? 0.16 : 0.12)),
          accent.withValues(alpha: fade * (isDark ? 0.06 : 0.04)),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: origin, radius: glowRadius));
    canvas.drawCircle(origin, glowRadius, glowPaint);

    // 2. 一道克制的细光环随页面舒展消散
    final ringR = maxR * (0.08 + 0.85 * ease);
    final ringAlpha = (1.0 - t) * (isDark ? 0.24 : 0.18);
    if (ringAlpha > 0.005) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = accent.withValues(alpha: ringAlpha);
      canvas.drawCircle(origin, ringR, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _QianjiCleanMorphPainter oldDelegate) {
    return oldDelegate.t != t ||
        oldDelegate.toNewLayout != toNewLayout ||
        oldDelegate.isDark != isDark;
  }
}

/// 驱动简洁切页动效的控制器（420ms，干脆利落）。
class QianjiParticleMorphController {
  QianjiParticleMorphController({required TickerProvider vsync})
    : animation = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 420),
      );

  final AnimationController animation;
  bool toNewLayout = true;

  bool get isAnimating => animation.isAnimating;

  void trigger({
    required bool toNew,
    required bool reduceMotion,
    required VoidCallback onSwap,
  }) {
    onSwap();
    if (reduceMotion) return;
    toNewLayout = toNew;
    HapticFeedback.selectionClick();
    animation.forward(from: 0.0);
  }

  void dispose() {
    animation.dispose();
  }
}
