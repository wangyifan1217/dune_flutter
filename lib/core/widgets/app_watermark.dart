import 'package:flutter/material.dart';

import '../../features/auth/auth_session_coordinator.dart';

/// 全局视觉水印：登录后平铺当前用户 [displayName]，不拦截触摸。
class AppWatermark extends StatelessWidget {
  const AppWatermark({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AuthSessionCoordinator.instance,
      builder: (context, _) {
        final name =
            (AuthSessionCoordinator.instance.session?.displayName ?? '')
                .trim();
        if (name.isEmpty) return child;

        return Stack(
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _AppWatermarkPainter(text: '$name.dune'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AppWatermarkPainter extends CustomPainter {
  _AppWatermarkPainter({required this.text});

  final String text;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.5);
    canvas.translate(-size.width, -size.height);

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xFF444444).withValues(alpha: 0.06),
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const dx = 200.0;
    const dy = 120.0;
    for (var y = 0.0; y < size.height * 2; y += dy) {
      for (var x = 0.0; x < size.width * 2; x += dx) {
        tp.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AppWatermarkPainter oldDelegate) =>
      oldDelegate.text != text;
}
