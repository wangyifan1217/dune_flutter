import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

class LighthouseSectionCard extends StatelessWidget {
  const LighthouseSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DunesColors.borderSoft),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class LighthousePill extends StatelessWidget {
  const LighthousePill({
    super.key,
    required this.text,
    this.active = false,
    this.onTap,
  });

  final String text;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? DunesColors.text : DunesColors.text2;
    final bg = active ? DunesColors.bgCard : DunesColors.bgApp;
    final border = active ? DunesColors.text2 : DunesColors.borderSoft;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Text(
          text,
          style: DunesTypography.sans(
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class LighthouseSparkline extends StatelessWidget {
  const LighthouseSparkline({
    super.key,
    required this.seed,
    required this.negative,
  });

  final String seed;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: CustomPaint(
        painter: _SparklinePainter(seed: seed, negative: negative),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.seed, required this.negative});

  final String seed;
  final bool negative;

  @override
  void paint(Canvas canvas, Size size) {
    final random = _SeedRandom(seed.hashCode);
    final pts = <Offset>[];
    const n = 24;
    for (var i = 0; i < n; i++) {
      final x = size.width * i / (n - 1);
      final base = 0.5 + math.sin(i / 4) * 0.13;
      final yv = (base + random.next() * 0.18).clamp(0.12, 0.88);
      final y = size.height * yv;
      pts.add(Offset(x, y));
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = negative ? DunesColors.coral : DunesColors.accent
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.seed != seed || oldDelegate.negative != negative;
  }
}

class _SeedRandom {
  _SeedRandom(int seed) : _state = seed == 0 ? 1 : seed;
  int _state;
  double next() {
    _state ^= (_state << 13);
    _state ^= (_state >> 17);
    _state ^= (_state << 5);
    return ((_state & 0x7fffffff) / 0x7fffffff).toDouble();
  }
}
