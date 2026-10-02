import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

/// One isolated canvas for the entire effect. Glyph paragraphs and trajectories
/// are prepared once; animation ticks only repaint this layer.
class ImEggParticleField extends StatefulWidget {
  const ImEggParticleField({
    super.key,
    required this.glyphs,
    required this.duration,
    required this.count,
    required this.onFinished,
    this.seed = 0,
    this.motion = 'fall',
    this.birthday = false,
  });

  final List<String> glyphs;
  final Duration duration;
  final int count;
  final int seed;
  final String motion;
  final bool birthday;
  final VoidCallback onFinished;

  @override
  State<ImEggParticleField> createState() => _ImEggParticleFieldState();
}

class _ImEggParticleFieldState extends State<ImEggParticleField>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation;
  late final List<_Particle> _particles;
  final Map<String, TextPainter> _glyphs = {};
  Timer? _staticTimer;
  bool _reducedMotion = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animation = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _finish();
      });
    final random = math.Random(
      widget.seed == 0 ? DateTime.now().microsecondsSinceEpoch : widget.seed,
    );
    final glyphs = widget.glyphs.isEmpty ? const ['✨'] : widget.glyphs;
    for (final glyph in glyphs.toSet()) {
      if (_isChinaFlag(glyph)) continue;
      _glyphs[glyph] = TextPainter(
        text: TextSpan(
          text: glyph,
          style: const TextStyle(
            fontSize: 40,
            height: 1,
            color: Color(0xFF7657DC),
            decoration: TextDecoration.none,
            fontFamily: 'Apple Color Emoji',
            fontFamilyFallback: [
              'Apple Color Emoji',
              'Noto Color Emoji',
              'Segoe UI Emoji',
            ],
            shadows: [
              Shadow(
                color: Color(0x3275413C),
                blurRadius: 4,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    _particles = List.generate(
      widget.count.clamp(1, 56),
      (index) => _Particle(
        x: .025 + random.nextDouble() * .95,
        phase: random.nextDouble() * math.pi * 2,
        drift: 10 + random.nextDouble() * 36,
        size: (widget.birthday ? 20 : 18) + random.nextDouble() * 17,
        delay: random.nextDouble() * .2,
        duration: .6 + random.nextDouble() * .25,
        glyph: glyphs[random.nextInt(glyphs.length)],
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    _reducedMotion = reduced;
    if (reduced) {
      _animation.stop();
      _staticTimer ??= Timer(const Duration(milliseconds: 1500), _finish);
    } else if (!_animation.isAnimating && !_finished) {
      _staticTimer?.cancel();
      _staticTimer = null;
      _animation.forward();
    }
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _animation.stop();
      _finish();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _staticTimer?.cancel();
    _animation.dispose();
    for (final glyph in _glyphs.values) {
      glyph.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _ParticlePainter(
            animation: _animation,
            particles: _particles,
            glyphs: _glyphs,
            motion: widget.motion,
            reducedMotion: _reducedMotion,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

class _Particle {
  const _Particle({
    required this.x,
    required this.phase,
    required this.drift,
    required this.size,
    required this.delay,
    required this.duration,
    required this.glyph,
  });
  final double x, phase, drift, size, delay, duration;
  final String glyph;
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({
    required this.animation,
    required this.particles,
    required this.glyphs,
    required this.motion,
    required this.reducedMotion,
  }) : super(repaint: animation);
  final Animation<double> animation;
  final List<_Particle> particles;
  final Map<String, TextPainter> glyphs;
  final String motion;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final visible = reducedMotion ? particles.take(8) : particles;
    for (final particle in visible) {
      final progress = reducedMotion
          ? particle.x
          : ((animation.value - particle.delay) / particle.duration).clamp(
              0.0,
              1.0,
            );
      if (!reducedMotion &&
          (animation.value < particle.delay || progress >= 1)) {
        continue;
      }
      final (x, y) = reducedMotion
          ? (
              size.width * particle.x,
              size.height * (.1 + particle.phase / (math.pi * 2) * .8),
            )
          : switch (motion) {
              'float' => (
                size.width * particle.x +
                    math.sin(progress * math.pi + particle.phase) *
                        particle.drift,
                size.height + 45 - (size.height + 90) * progress,
              ),
              'burst' => (
                size.width / 2 +
                    math.cos(particle.phase) * size.width * .62 * progress,
                size.height / 2 +
                    math.sin(particle.phase) * size.height * .62 * progress,
              ),
              'orbit' => (
                size.width / 2 +
                    math.cos(particle.phase + progress * math.pi * 4) *
                        size.width *
                        (.08 + progress * .35),
                size.height / 2 +
                    math.sin(particle.phase + progress * math.pi * 4) *
                        size.height *
                        (.08 + progress * .35),
              ),
              _ => (
                size.width * particle.x +
                    math.sin(progress * math.pi * 2 + particle.phase) *
                        particle.drift,
                -45 + (size.height + 110) * progress,
              ),
            };
      canvas.save();
      canvas.translate(x, y);
      if (!reducedMotion) {
        canvas.rotate(progress * math.pi * 2 - .35 + particle.phase * .08);
        canvas.scale(
          .94 + math.sin(progress * math.pi * 2 + particle.phase) * .06,
          1,
        );
      }
      if (_isChinaFlag(particle.glyph)) {
        paintChinaFlag(
          canvas,
          Rect.fromCenter(
            center: Offset.zero,
            width: particle.size * 1.35,
            height: particle.size * .9,
          ),
        );
      } else {
        final painter = glyphs[particle.glyph]!;
        final scale = particle.size / 40;
        canvas.scale(scale);
        painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) =>
      old.reducedMotion != reducedMotion ||
      old.particles != particles ||
      old.motion != motion;
}

bool _isChinaFlag(String glyph) =>
    glyph == '🇨🇳' || glyph.trim().toUpperCase() == 'CN';

/// Draw the flag directly: platforms that render the Emoji as "CN" show the
/// same five-star flag as iOS, with no font or network dependency.
void paintChinaFlag(Canvas canvas, Rect rect) {
  canvas.save();
  canvas.translate(rect.left, rect.top);
  canvas.scale(rect.width / 30, rect.height / 20);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 30, 20),
    Paint()..color = const Color(0xFFDE2910),
  );
  void star(double x, double y, double radius, double angle) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? radius : radius * .382;
      final a = angle + i * math.pi / 5;
      final dx = x + math.cos(a) * r, dy = y + math.sin(a) * r;
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFDE00));
  }

  star(5, 5, 3, -math.pi / 2);
  for (final (x, y) in const [
    (10.0, 2.0),
    (12.0, 4.0),
    (12.0, 7.0),
    (10.0, 9.0),
  ]) {
    star(x, y, 1, math.atan2(5 - y, 5 - x));
  }
  canvas.restore();
}

class HolidayGlyph extends StatelessWidget {
  const HolidayGlyph({super.key, required this.icon, this.size = 56});
  final String icon;
  final double size;

  @override
  Widget build(BuildContext context) => _isChinaFlag(icon)
      ? CustomPaint(
          size: Size(size * 1.4, size * .94),
          painter: const _FlagPainter(),
        )
      : Text(
          icon,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: size,
            height: 1.1,
            color: DunesColors.resolve(context, const Color(0xFF7657DC)),
            decoration: TextDecoration.none,
            fontFamily: 'Apple Color Emoji',
          ),
        );
}

class _FlagPainter extends CustomPainter {
  const _FlagPainter();
  @override
  void paint(Canvas canvas, Size size) =>
      paintChinaFlag(canvas, Offset.zero & size);
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A dedicated welcome scene matching app_easter_eggs_preview.html.
class AppHolidayWelcome extends StatelessWidget {
  const AppHolidayWelcome({
    super.key,
    required this.greeting,
    required this.message,
    required this.icon,
    required this.onDismiss,
  });
  final String greeting, message, icon;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final night = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: night
            ? const Color(0xFF6C4A54)
            : const Color(0xFFD99467),
        systemNavigationBarIconBrightness: night
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Material(
        color: Colors.transparent,
        child: DefaultTextStyle(
          style: TextStyle(
            color: night
                ? DunesColors.resolve(context, const Color(0xFFF1EFF8))
                : DunesColors.resolve(context, const Color(0xFF302843)),
            decoration: TextDecoration.none,
            fontFamily: 'Geist',
            fontFamilyFallback: const ['PingFang SC', 'Noto Sans SC'],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: night
                    ? const [
                        Color(0xFF211A39),
                        Color(0xFF443260),
                        Color(0xFF6C4A54),
                      ]
                    : const [
                        Color(0xFF3B2D61),
                        Color(0xFF6C4E9D),
                        Color(0xFFD99467),
                      ],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -.4),
                        radius: .72,
                        colors: [
                          DunesColors.resolve(
                            context,
                            const Color(0xFFFFF7DD),
                          ).withValues(alpha: night ? .14 : .4),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 380,
                    height: 380,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: DunesColors.resolve(
                          context,
                          const Color(0x22FFFFFF),
                          role: DunesColorRole.border,
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 290,
                    height: 290,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: DunesColors.resolve(
                          context,
                          const Color(0x33FFFFFF),
                          role: DunesColorRole.border,
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 70,
                      ),
                      child: Container(
                        width: 320,
                        padding: const EdgeInsets.fromLTRB(26, 28, 26, 24),
                        decoration: BoxDecoration(
                          color: night
                              ? DunesColors.resolve(
                                  context,
                                  const Color(0xFF282735),
                                  role: DunesColorRole.surface,
                                )
                              : DunesColors.resolve(
                                  context,
                                  const Color(0xFFFDFBFF),
                                  role: DunesColorRole.surface,
                                ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: night
                                ? DunesColors.resolve(
                                    context,
                                    const Color(0xFF3A3848),
                                    role: DunesColorRole.border,
                                  )
                                : DunesColors.resolve(
                                    context,
                                    const Color(0x88FFFFFF),
                                    role: DunesColorRole.border,
                                  ),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x50281D43),
                              blurRadius: 55,
                              offset: Offset(0, 20),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HolidayGlyph(icon: icon),
                            const SizedBox(height: 18),
                            const Text(
                              '沙丘 · 节日祝福',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 2,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFB98B54),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              greeting,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              message,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.65,
                                color: night
                                    ? DunesColors.resolve(
                                        context,
                                        const Color(0xFFAAA6B7),
                                      )
                                    : DunesColors.resolve(
                                        context,
                                        const Color(0xFF85808F),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            Divider(
                              height: 1,
                              color: night
                                  ? DunesColors.resolve(
                                      context,
                                      const Color(0xFF3A3848),
                                      role: DunesColorRole.border,
                                    )
                                  : DunesColors.resolve(
                                      context,
                                      const Color(0xFFEEE9F3),
                                      role: DunesColorRole.border,
                                    ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '小饕和沙丘，陪你收下今天的小美好',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: night
                                    ? DunesColors.resolve(
                                        context,
                                        const Color(0xFFB9A9F5),
                                      )
                                    : DunesColors.resolve(
                                        context,
                                        const Color(0xFF7556D0),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: onDismiss,
                                    style: TextButton.styleFrom(
                                      backgroundColor: night
                                          ? DunesColors.resolve(
                                              context,
                                              const Color(0xFF393547),
                                              role: DunesColorRole.surface,
                                            )
                                          : DunesColors.resolve(
                                              context,
                                              const Color(0xFFF2EFF7),
                                              role: DunesColorRole.surface,
                                            ),
                                      foregroundColor: night
                                          ? DunesColors.resolve(
                                              context,
                                              const Color(0xFFCCC6D8),
                                            )
                                          : DunesColors.resolve(
                                              context,
                                              const Color(0xFF797486),
                                            ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                    ),
                                    child: const Text(
                                      '稍后看看',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: onDismiss,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: DunesColors.resolve(
                                        context,
                                        const Color(0xFF7657DC),
                                        role: DunesColorRole.surface,
                                      ),
                                      foregroundColor: DunesColors.resolve(
                                        context,
                                        Colors.white,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 13,
                                      ),
                                    ),
                                    child: const Text(
                                      '收下祝福',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: TextButton.icon(
                        onPressed: onDismiss,
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text('跳过'),
                        style: TextButton.styleFrom(
                          foregroundColor: DunesColors.resolve(
                            context,
                            Colors.white,
                          ),
                          backgroundColor: DunesColors.resolve(
                            context,
                            const Color(0x20FFFFFF),
                            role: DunesColorRole.surface,
                          ),
                          side: const BorderSide(color: Color(0x66FFFFFF)),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
