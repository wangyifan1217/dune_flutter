import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'robot_catalog_cache.dart';
import 'robot_models.dart';

/// 扁平矢量机器人头像：方形脑袋 + LED 眼 + 轻待机动画。
/// 外形与 IM 用户头像一致：圆角方形（[commBorderRadius]）。
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

  /// 与 [ImUserAvatar.commBorderRadius] 对齐。
  static double cornerRadius(double size) => size * 0.18;

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

  /// 0=睁眼 … 1=闭眼，短促三角波形。
  double _eyeClose(double t) {
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

  /// 天线/嘴部变体，区分不同机器人。
  int get _variant => role.id.hashCode.abs() % 3;

  Color get _metal {
    // 浅金属壳，略带角色强调色，避免肉色「人脸」感。
    return Color.lerp(const Color(0xFFE8ECF2), role.accent, 0.14)!;
  }

  Color get _metalDeep {
    return Color.lerp(const Color(0xFF9AA3B0), role.hair, 0.35)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    final r = s / 2;
    final corner = Radius.circular(RobotFaceAvatar.cornerRadius(s));
    final bounds = Rect.fromCenter(center: c, width: s, height: s);
    final outer = RRect.fromRectAndRadius(bounds, corner);

    canvas.save();
    canvas.clipRRect(outer);

    // 背景：淡强调色底
    canvas.drawRRect(
      outer,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(c.dx, c.dy - r),
          Offset(c.dx, c.dy + r),
          [
            Color.lerp(Colors.white, role.accent, 0.08)!,
            Color.lerp(role.accent, const Color(0xFFF2F4F8), 0.82)!,
          ],
        ),
    );

    _paintAntenna(canvas, c, r);
    _paintHead(canvas, c, r);
    _paintEars(canvas, c, r);
    _paintFacePlate(canvas, c, r);
    _paintNeck(canvas, c, r);

    canvas.restore();

    final strokeRect = outer.deflate(0.6);
    canvas.drawRRect(
      strokeRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, s * 0.035),
    );
    canvas.drawRRect(
      strokeRect,
      Paint()
        ..color = role.accent.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, s * 0.02),
    );
  }

  void _paintAntenna(Canvas canvas, Offset c, double r) {
    final stem = Paint()
      ..color = _metalDeep
      ..strokeWidth = math.max(1.4, r * 0.07)
      ..strokeCap = StrokeCap.round;
    final tip = Paint()..color = role.accent;
    final glow = Paint()..color = role.accent.withValues(alpha: 0.28);

    switch (_variant) {
      case 1:
        // 双天线
        for (final dx in [-0.22, 0.22]) {
          final base = Offset(c.dx + r * dx, c.dy - r * 0.62);
          final top = Offset(c.dx + r * dx * 1.15, c.dy - r * 0.92);
          canvas.drawLine(base, top, stem);
          canvas.drawCircle(top, r * 0.09, glow);
          canvas.drawCircle(top, r * 0.055, tip);
        }
      case 2:
        // 侧偏单天线
        final base = Offset(c.dx + r * 0.12, c.dy - r * 0.62);
        final top = Offset(c.dx + r * 0.28, c.dy - r * 0.94);
        canvas.drawLine(base, top, stem);
        canvas.drawCircle(top, r * 0.1, glow);
        canvas.drawCircle(top, r * 0.06, tip);
      default:
        // 居中天线
        final base = Offset(c.dx, c.dy - r * 0.62);
        final top = Offset(c.dx, c.dy - r * 0.94);
        canvas.drawLine(base, top, stem);
        canvas.drawCircle(top, r * 0.11, glow);
        canvas.drawCircle(top, r * 0.065, tip);
    }
  }

  void _paintHead(Canvas canvas, Offset c, double r) {
    // 方脑袋本体（圆角略小，更「方」）
    final headRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(c.dx, c.dy - r * 0.06),
        width: r * 1.42,
        height: r * 1.28,
      ),
      Radius.circular(r * 0.16),
    );
    final headPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(c.dx - r * 0.5, c.dy - r * 0.7),
        Offset(c.dx + r * 0.5, c.dy + r * 0.5),
        [
          Color.lerp(_metal, Colors.white, 0.35)!,
          _metal,
          Color.lerp(_metal, _metalDeep, 0.28)!,
        ],
        const [0.0, 0.45, 1.0],
      );
    canvas.drawRRect(headRect, headPaint);

    // 顶盖暗条
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(c.dx, c.dy - r * 0.58),
          width: r * 1.22,
          height: r * 0.16,
        ),
        Radius.circular(r * 0.06),
      ),
      Paint()..color = _metalDeep.withValues(alpha: 0.55),
    );

    // 壳边
    canvas.drawRRect(
      headRect,
      Paint()
        ..color = _metalDeep.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, r * 0.04),
    );
  }

  void _paintEars(Canvas canvas, Offset c, double r) {
    final earPaint = Paint()..color = Color.lerp(_metalDeep, role.accent, 0.25)!;
    final bolt = Paint()..color = Colors.white.withValues(alpha: 0.7);
    for (final side in [-1.0, 1.0]) {
      final ear = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(c.dx + side * r * 0.78, c.dy - r * 0.02),
          width: r * 0.2,
          height: r * 0.42,
        ),
        Radius.circular(r * 0.06),
      );
      canvas.drawRRect(ear, earPaint);
      canvas.drawCircle(
        Offset(c.dx + side * r * 0.78, c.dy - r * 0.02),
        r * 0.045,
        bolt,
      );
    }
  }

  void _paintFacePlate(Canvas canvas, Offset c, double r) {
    final open = 1.0 - eyeClose;
    final plate = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(c.dx, c.dy - r * 0.02),
        width: r * 1.08,
        height: r * 0.78,
      ),
      Radius.circular(r * 0.1),
    );
    // 深色显示屏
    canvas.drawRRect(
      plate,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(c.dx, c.dy - r * 0.4),
          Offset(c.dx, c.dy + r * 0.35),
          const [Color(0xFF2A303A), Color(0xFF1A1E26)],
        ),
    );
    canvas.drawRRect(
      plate,
      Paint()
        ..color = role.accent.withValues(alpha: 0.2 + breath * 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, r * 0.03),
    );

    final eyeY = c.dy - r * 0.08;
    final eyeDx = r * 0.24;
    final eyeH = r * 0.22 * open.clamp(0.12, 1.0);
    final eyeW = r * 0.2;

    void paintLed(Offset center) {
      if (open < 0.2) {
        canvas.drawLine(
          Offset(center.dx - eyeW, center.dy),
          Offset(center.dx + eyeW, center.dy),
          Paint()
            ..color = role.accent.withValues(alpha: 0.85)
            ..strokeWidth = math.max(1.2, r * 0.05)
            ..strokeCap = StrokeCap.round,
        );
        return;
      }
      final led = RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: eyeW * 2, height: eyeH * 2),
        Radius.circular(r * 0.045),
      );
      canvas.drawRRect(
        led,
        Paint()..color = role.accent.withValues(alpha: 0.95),
      );
      canvas.drawRRect(
        led.deflate(r * 0.03),
        Paint()..color = Color.lerp(role.accent, Colors.white, 0.45)!,
      );
      // 高光点
      canvas.drawCircle(
        center.translate(-eyeW * 0.25, -eyeH * 0.25),
        r * 0.035,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }

    paintLed(Offset(c.dx - eyeDx, eyeY));
    paintLed(Offset(c.dx + eyeDx, eyeY));

    if (role.glasses) {
      final g = Paint()
        ..color = const Color(0xFFD0D5DE).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.04;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(c.dx - eyeDx, eyeY),
            width: r * 0.48,
            height: r * 0.36 * open.clamp(0.55, 1),
          ),
          Radius.circular(r * 0.06),
        ),
        g,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(c.dx + eyeDx, eyeY),
            width: r * 0.48,
            height: r * 0.36 * open.clamp(0.55, 1),
          ),
          Radius.circular(r * 0.06),
        ),
        g,
      );
      canvas.drawLine(
        Offset(c.dx - eyeDx + r * 0.24, eyeY),
        Offset(c.dx + eyeDx - r * 0.24, eyeY),
        g,
      );
    }

    // 嘴：扬声器槽 / 微笑线
    final mouthY = c.dy + r * 0.22;
    if (_variant == 2) {
      for (final i in [-1, 0, 1]) {
        canvas.drawLine(
          Offset(c.dx - r * 0.18, mouthY + i * r * 0.05),
          Offset(c.dx + r * 0.18, mouthY + i * r * 0.05),
          Paint()
            ..color = role.accent.withValues(alpha: 0.55)
            ..strokeWidth = math.max(1.0, r * 0.035)
            ..strokeCap = StrokeCap.round,
        );
      }
    } else {
      final smile = Path()
        ..moveTo(c.dx - r * 0.16, mouthY)
        ..quadraticBezierTo(
          c.dx,
          mouthY + r * (0.1 + breath * 0.02),
          c.dx + r * 0.16,
          mouthY,
        );
      canvas.drawPath(
        smile,
        Paint()
          ..color = role.accent.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.2, r * 0.05)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintNeck(Canvas canvas, Offset c, double r) {
    final neck = RRect.fromRectAndRadius(
      Rect.fromLTRB(
        c.dx - r * 0.55,
        c.dy + r * 0.48,
        c.dx + r * 0.55,
        c.dy + r * 1.05,
      ),
      Radius.circular(r * 0.08),
    );
    canvas.drawRRect(
      neck,
      Paint()..color = Color.lerp(role.accent, Colors.white, 0.12)!,
    );
    // 颈关节
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(c.dx, c.dy + r * 0.52),
          width: r * 0.36,
          height: r * 0.12,
        ),
        Radius.circular(r * 0.04),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
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
    final radius = RobotFaceAvatar.cornerRadius(size);
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
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: RobotFaceAvatar(
                    role: RobotCatalogCache.instance.resolve(ids[i]),
                    size: size,
                    animate: false,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
