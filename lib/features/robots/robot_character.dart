import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'robot_models.dart';

/// 更接近角色库参考的扁平卡通头像：柔和五官 + 丝滑待机动画。
class RobotFaceAvatar extends StatefulWidget {
  const RobotFaceAvatar({
    super.key,
    required this.role,
    this.size = 48,
    this.animate = true,
    /// 执行中：浮动/轻倾/呼吸；空闲：只眨眼。
    this.busy = false,
  });

  final RobotRole role;
  final double size;
  final bool animate;
  final bool busy;

  @override
  State<RobotFaceAvatar> createState() => _RobotFaceAvatarState();
}

class _RobotFaceAvatarState extends State<RobotFaceAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // 单向循环，避免 reverse 造成的来回顿挫。
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (widget.animate) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant RobotFaceAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.animate && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 0=睁眼 … 1=闭眼，短促三角波形，更丝滑。
  double _eyeClose(double t) {
    // 每圈眨一次，窗口略宽更易察觉
    double blinkAt(double center) {
      const half = 0.045;
      final d = (t - center).abs();
      if (d >= half) return 0;
      return 1 - (d / half);
    }

    return blinkAt(0.62).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return CustomPaint(
        size: Size.square(widget.size),
        painter: _FacePainter(
          role: widget.role,
          eyeClose: 0,
          breath: 0.5,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        final wave = t * math.pi * 2;
        final eyeClose = _eyeClose(t);
        final busy = widget.busy;

        // 空闲：只眨眼；执行中：浮动 + 轻倾 + 轻微缩放
        final bob = busy
            ? math.sin(wave) * math.max(1.6, widget.size * 0.055)
            : 0.0;
        final tilt = busy ? math.sin(wave * 0.85 + 0.4) * 0.07 : 0.0;
        final scale = busy ? 1.0 + math.sin(wave) * 0.035 : 1.0;
        final breath = busy ? 0.5 + 0.5 * math.sin(wave) : 0.5;

        Widget face = CustomPaint(
          size: Size.square(widget.size),
          painter: _FacePainter(
            role: widget.role,
            eyeClose: eyeClose,
            breath: breath,
          ),
        );

        if (busy) {
          face = Transform.translate(
            offset: Offset(0, bob),
            child: Transform.rotate(
              angle: tilt,
              child: Transform.scale(scale: scale, child: face),
            ),
          );
        }

        return face;
      },
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter({
    required this.role,
    required this.eyeClose,
    required this.breath,
  });

  final RobotRole role;
  final double eyeClose;
  final double breath;

  int get _hairStyle {
    switch (role.id) {
      case 'r_lighthouse':
        return 0;
      case 'r_ops':
        return 0;
      case 'r_doc':
        return 1;
      case 'r_qa':
        return 2;
      case 'r_msg':
        return 3;
      default:
        return role.id.hashCode.abs() % 4;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final r = s / 2;

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));

    // 脸底：柔和径向高光
    final faceShader = ui.Gradient.radial(
      c.translate(-r * 0.18, -r * 0.22),
      r * 1.15,
      [
        Color.lerp(role.skin, Colors.white, 0.22)!,
        role.skin,
        Color.lerp(role.skin, const Color(0xFFB88A6A), 0.12)!,
      ],
      const [0.0, 0.55, 1.0],
    );
    canvas.drawCircle(c, r, Paint()..shader = faceShader);

    _paintHair(canvas, c, r);
    _paintEars(canvas, c, r);
    _paintFace(canvas, c, r);
    _paintCollar(canvas, c, r);

    canvas.restore();

    // 外圈描边（不裁切）
    canvas.drawCircle(
      c,
      r - 0.6,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, s * 0.035),
    );
    canvas.drawCircle(
      c,
      r - 0.6,
      Paint()
        ..color = role.accent.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, s * 0.02),
    );
  }

  void _paintEars(Canvas canvas, Offset c, double r) {
    final ear = Paint()..color = Color.lerp(role.skin, const Color(0xFFE09A7A), 0.15)!;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx - r * 0.78, c.dy + r * 0.02),
        width: r * 0.28,
        height: r * 0.36,
      ),
      ear,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx + r * 0.78, c.dy + r * 0.02),
        width: r * 0.28,
        height: r * 0.36,
      ),
      ear,
    );
  }

  void _paintHair(Canvas canvas, Offset c, double r) {
    final hair = Paint()..color = role.hair;
    final style = _hairStyle;

    // 头顶大块
    final top = Path()
      ..moveTo(c.dx - r * 0.92, c.dy + r * 0.05)
      ..quadraticBezierTo(
        c.dx - r * 0.75,
        c.dy - r * 0.95,
        c.dx,
        c.dy - r * 0.98,
      )
      ..quadraticBezierTo(
        c.dx + r * 0.75,
        c.dy - r * 0.95,
        c.dx + r * 0.92,
        c.dy + r * 0.05,
      )
      ..quadraticBezierTo(c.dx, c.dy - r * 0.2, c.dx - r * 0.92, c.dy + r * 0.05);
    canvas.drawPath(top, hair);

    switch (style) {
      case 0:
        // 干净齐刘海
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - r * 0.72, c.dy - r * 0.05)
            ..quadraticBezierTo(c.dx - r * 0.25, c.dy + r * 0.12, c.dx, c.dy - r * 0.02)
            ..quadraticBezierTo(c.dx + r * 0.25, c.dy + r * 0.12, c.dx + r * 0.72, c.dy - r * 0.05)
            ..quadraticBezierTo(c.dx, c.dy - r * 0.28, c.dx - r * 0.72, c.dy - r * 0.05),
          hair,
        );
        break;
      case 1:
        // 中分
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - r * 0.7, c.dy - r * 0.08)
            ..quadraticBezierTo(c.dx - r * 0.35, c.dy + r * 0.18, c.dx - r * 0.04, c.dy - r * 0.05)
            ..lineTo(c.dx - r * 0.04, c.dy - r * 0.55)
            ..close(),
          hair,
        );
        canvas.drawPath(
          Path()
            ..moveTo(c.dx + r * 0.7, c.dy - r * 0.08)
            ..quadraticBezierTo(c.dx + r * 0.35, c.dy + r * 0.18, c.dx + r * 0.04, c.dy - r * 0.05)
            ..lineTo(c.dx + r * 0.04, c.dy - r * 0.55)
            ..close(),
          hair,
        );
        break;
      case 2:
        // 侧扫
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - r * 0.55, c.dy - r * 0.35)
            ..quadraticBezierTo(c.dx + r * 0.1, c.dy + r * 0.05, c.dx + r * 0.78, c.dy + r * 0.08)
            ..quadraticBezierTo(c.dx + r * 0.2, c.dy - r * 0.15, c.dx - r * 0.2, c.dy - r * 0.5)
            ..close(),
          hair,
        );
        break;
      default:
        // 蓬松卷
        canvas.drawCircle(Offset(c.dx - r * 0.42, c.dy - r * 0.55), r * 0.28, hair);
        canvas.drawCircle(Offset(c.dx + r * 0.4, c.dy - r * 0.52), r * 0.3, hair);
        canvas.drawCircle(Offset(c.dx, c.dy - r * 0.7), r * 0.26, hair);
        break;
    }

    // 发丝高光
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx - r * 0.22, c.dy - r * 0.55),
        width: r * 0.22,
        height: r * 0.1,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.14),
    );
  }

  void _paintFace(Canvas canvas, Offset c, double r) {
    final eyeY = c.dy + r * 0.02;
    final eyeDx = r * 0.22;
    final open = 1.0 - eyeClose;

    // 腮红（呼吸）
    final blushA = 0.16 + breath * 0.1;
    final blush = Paint()..color = const Color(0xFFFF8FA3).withValues(alpha: blushA);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx - r * 0.42, c.dy + r * 0.22),
        width: r * 0.28,
        height: r * 0.14,
      ),
      blush,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx + r * 0.42, c.dy + r * 0.22),
        width: r * 0.28,
        height: r * 0.14,
      ),
      blush,
    );

    void paintEye(Offset center) {
      final whiteH = r * 0.2 * open.clamp(0.08, 1.0);
      final whiteW = r * 0.22;
      final whiteRect = Rect.fromCenter(center: center, width: whiteW * 2, height: whiteH * 2);
      canvas.drawOval(whiteRect, Paint()..color = Colors.white);

      if (open < 0.18) {
        // 近似闭眼弧线
        final lid = Paint()
          ..color = const Color(0xFF2C2F36)
          ..strokeWidth = r * 0.045
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          Offset(center.dx - whiteW, center.dy),
          Offset(center.dx + whiteW, center.dy),
          lid,
        );
        return;
      }

      final irisR = r * 0.11 * open.clamp(0.35, 1.0);
      final irisColor = Color.lerp(const Color(0xFF3A4450), role.accent, 0.35)!;
      canvas.drawCircle(center, irisR, Paint()..color = irisColor);
      canvas.drawCircle(center, irisR * 0.55, Paint()..color = const Color(0xFF1B1E24));
      canvas.drawCircle(
        center.translate(-irisR * 0.28, -irisR * 0.32),
        irisR * 0.28,
        Paint()..color = Colors.white.withValues(alpha: 0.95),
      );
      canvas.drawCircle(
        center.translate(irisR * 0.35, irisR * 0.2),
        irisR * 0.12,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
    }

    paintEye(Offset(c.dx - eyeDx, eyeY));
    paintEye(Offset(c.dx + eyeDx, eyeY));

    if (role.glasses) {
      final g = Paint()
        ..color = const Color(0xFF4A4F57)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.045;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(c.dx - eyeDx, eyeY), width: r * 0.42, height: r * 0.34 * open.clamp(0.55, 1)),
          Radius.circular(r * 0.12),
        ),
        g,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(c.dx + eyeDx, eyeY), width: r * 0.42, height: r * 0.34 * open.clamp(0.55, 1)),
          Radius.circular(r * 0.12),
        ),
        g,
      );
      canvas.drawLine(
        Offset(c.dx - eyeDx + r * 0.21, eyeY),
        Offset(c.dx + eyeDx - r * 0.21, eyeY),
        g,
      );
    }

    // 鼻子小点
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx, c.dy + r * 0.14),
        width: r * 0.08,
        height: r * 0.05,
      ),
      Paint()..color = const Color(0xFFD9A08A).withValues(alpha: 0.55),
    );

    // 微笑
    final smile = Path()
      ..moveTo(c.dx - r * 0.16, c.dy + r * 0.3)
      ..quadraticBezierTo(
        c.dx,
        c.dy + r * (0.4 + breath * 0.02),
        c.dx + r * 0.16,
        c.dy + r * 0.3,
      );
    canvas.drawPath(
      smile,
      Paint()
        ..color = const Color(0xFFC56B7A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.045
        ..strokeCap = StrokeCap.round,
    );
  }

  void _paintCollar(Canvas canvas, Offset c, double r) {
    final collar = Path()
      ..moveTo(c.dx - r * 0.95, c.dy + r * 0.55)
      ..quadraticBezierTo(c.dx, c.dy + r * 0.35, c.dx + r * 0.95, c.dy + r * 0.55)
      ..lineTo(c.dx + r, c.dy + r)
      ..lineTo(c.dx - r, c.dy + r)
      ..close();
    canvas.drawPath(
      collar,
      Paint()..color = Color.lerp(role.accent, Colors.white, 0.15)!,
    );
    // 领口折线
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - r * 0.22, c.dy + r * 0.55)
        ..lineTo(c.dx, c.dy + r * 0.78)
        ..lineTo(c.dx + r * 0.22, c.dy + r * 0.55),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.035
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _FacePainter oldDelegate) {
    return oldDelegate.role != role ||
        oldDelegate.eyeClose != eyeClose ||
        oldDelegate.breath != breath;
  }
}

class RobotAvatarStack extends StatelessWidget {
  const RobotAvatarStack({
    super.key,
    required this.roleIds,
    this.size = 28,
  });

  final List<String> roleIds;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ids = roleIds.take(5).toList();
    final width = size + (ids.length - 1) * (size * 0.62);
    return SizedBox(
      width: width < 0 ? size : width,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < ids.length; i++)
            Positioned(
              left: i * size * 0.62,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: RobotFaceAvatar(
                  role: RobotCatalog.roleById(ids[i]),
                  size: size,
                  animate: false,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
