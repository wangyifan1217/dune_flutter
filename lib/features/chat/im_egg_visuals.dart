import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';
import 'im_egg_artwork.dart';

/// One isolated canvas for the effect. Glyphs are cached before animation ticks.
class ImEggParticleField extends StatefulWidget {
  const ImEggParticleField({
    super.key,
    this.motifs = const <String>[],
    this.glyphs = const <String>[],
    required this.duration,
    required this.count,
    required this.onFinished,
    this.washColor = const Color(0x00000000),
    this.useCustomWash = false,
    this.seed = 0,
    this.motion = 'fall',
    this.birthday = false,
    this.blueWash = false,
  });

  final List<String> motifs;

  /// Emoji glyphs used by the HTML preview's particle combinations.
  final List<String> glyphs;
  final Duration duration;
  final int count;
  final int seed;
  final String motion;
  final bool birthday;
  final bool blueWash;
  final Color washColor;
  final bool useCustomWash;
  final VoidCallback onFinished;

  @override
  State<ImEggParticleField> createState() => _ImEggParticleFieldState();
}

class _ImEggParticleFieldState extends State<ImEggParticleField>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation;
  late final List<_Particle> _particles;
  final Map<String, TextPainter> _glyphPainters = <String, TextPainter>{};
  final Map<String, ui.Image> _sprites = {};
  bool _artworkReady = false;
  Timer? _staticTimer;
  bool _reducedMotion = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _animation =
        AnimationController(
          vsync: this,
          duration: widget.duration + const Duration(milliseconds: 180),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _finish();
        });
    final random = math.Random(
      widget.seed == 0 ? DateTime.now().microsecondsSinceEpoch : widget.seed,
    );
    final glyphs = widget.glyphs.isNotEmpty
        ? widget.glyphs
        : widget.motifs.map(_emojiForMotif).toList(growable: false);
    final usableGlyphs = glyphs.isEmpty
        ? const ['🎉', '✨', '🎊', '💫']
        : glyphs;
    _particles = List.generate(
      widget.count.clamp(1, 56),
      (index) => _Particle(
        x: .02 + random.nextDouble() * .96,
        phase: random.nextDouble() * math.pi * 2,
        drift: (random.nextDouble() - .5) * 55,
        size:
            (widget.birthday ? 18 : 16) +
            random.nextDouble() * (widget.birthday ? 18 : 14),
        delay: random.nextDouble() * .85,
        duration: 2.4 + random.nextDouble() * 1.4,
        glyph: usableGlyphs[random.nextInt(usableGlyphs.length)],
      ),
    );
    for (final particle in _particles) {
      final fontSize = particle.size.roundToDouble();
      final key = _glyphPainterKey(particle.glyph, fontSize);
      _glyphPainters.putIfAbsent(
        key,
        () => TextPainter(
          text: TextSpan(
            text: particle.glyph,
            style: TextStyle(
              fontSize: fontSize,
              height: 1,
              decoration: TextDecoration.none,
              fontFamily: 'Apple Color Emoji',
              fontFamilyFallback: const [
                'Apple Color Emoji',
                'Noto Color Emoji',
                'Segoe UI Emoji',
              ],
              shadows: const [
                Shadow(
                  color: Color(0x3575413C),
                  blurRadius: 5,
                  offset: Offset(0, 4),
                ),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(),
      );
    }
    for (final glyph in usableGlyphs.toSet()) {
      final image = ImEggArtwork.cached(glyph);
      if (image != null) _sprites[glyph] = image;
    }
    _artworkReady = usableGlyphs.every(
      (glyph) =>
          !imEggArtworkSpecs.containsKey(glyph) || _sprites.containsKey(glyph),
    );
    if (!_artworkReady) unawaited(_loadArtwork(usableGlyphs));
  }

  Future<void> _loadArtwork(List<String> glyphs) async {
    final entries = await Future.wait(
      glyphs.toSet().map(
        (glyph) async => (glyph, await ImEggArtwork.load(glyph)),
      ),
    );
    if (!mounted) return;
    for (final (glyph, image) in entries) {
      if (image != null) _sprites[glyph] = image;
    }
    setState(() => _artworkReady = true);
    _startAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.disableAnimationsOf(context);
    _reducedMotion = reduced;
    _startAnimation();
  }

  void _startAnimation() {
    if (!_artworkReady || _finished) return;
    if (_reducedMotion) {
      _animation.stop();
      _staticTimer ??= Timer(const Duration(milliseconds: 1800), _finish);
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
    for (final painter in _glyphPainters.values) {
      painter.dispose();
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
            glyphPainters: _glyphPainters,
            sprites: Map.unmodifiable(_sprites),
            washColor: widget.washColor,
            useCustomWash: widget.useCustomWash,
            duration: widget.duration,
            motion: widget.motion,
            reducedMotion: _reducedMotion,
            birthday: widget.birthday,
            blueWash: widget.blueWash,
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
    required this.glyphPainters,
    required this.sprites,
    required this.washColor,
    required this.useCustomWash,
    required this.duration,
    required this.motion,
    required this.reducedMotion,
    required this.birthday,
    required this.blueWash,
  }) : super(repaint: animation);
  final Animation<double> animation;
  final List<_Particle> particles;
  final Map<String, TextPainter> glyphPainters;
  final Map<String, ui.Image> sprites;
  final Color washColor;
  final bool useCustomWash;
  final Duration duration;
  final String motion;
  final bool reducedMotion;
  final bool birthday;
  final bool blueWash;

  @override
  void paint(Canvas canvas, Size size) {
    final elapsed = animation.value * (duration.inMilliseconds + 180) / 1000;
    final effectSeconds = duration.inMilliseconds / 1000;
    const fadeCurve = Cubic(.25, .1, .25, 1);
    var overlayOpacity = reducedMotion
        ? 1.0
        : fadeCurve.transform((elapsed / .18).clamp(0.0, 1.0));
    if (!reducedMotion && elapsed > effectSeconds) {
      overlayOpacity =
          1 -
          fadeCurve.transform(
            ((elapsed - effectSeconds) / .18).clamp(0.0, 1.0),
          );
    }
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: overlayOpacity),
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    _drawWash(canvas, size, elapsed);
    final visible = reducedMotion ? particles.take(8) : particles;
    for (final particle in visible) {
      final rawProgress = reducedMotion
          ? particle.x
          : ((elapsed - particle.delay) / particle.duration).clamp(0.0, 1.0);
      if (!reducedMotion && (elapsed < particle.delay || rawProgress >= 1)) {
        continue;
      }
      final progress = reducedMotion
          ? rawProgress
          : const Cubic(.35, .05, .65, .95).transform(rawProgress);
      // CSS easing applies to each property's keyframe interval separately.
      const curve = Cubic(.35, .05, .65, .95);
      final first = curve.transform((rawProgress / .52).clamp(0.0, 1.0));
      final second = curve.transform(
        ((rawProgress - .52) / .48).clamp(0.0, 1.0),
      );
      final (x, y, rotation, scale, opacity) = reducedMotion
          ? (
              size.width * particle.x,
              size.height * (.1 + particle.phase / (math.pi * 2) * .8),
              0.0,
              1.0,
              .9,
            )
          : motion == 'fall'
          ? (
              size.width * particle.x + particle.drift * first,
              rawProgress < .52
                  ? _lerp(-78, -54 + size.height * .48, first)
                  : _lerp(
                      -54 + size.height * .48,
                      -54 + size.height * 1.08,
                      second,
                    ),
              rawProgress < .52
                  ? _lerp(-22, 165, first) * math.pi / 180
                  : _lerp(165, 350, second) * math.pi / 180,
              rawProgress < .52 ? _lerp(.78, 1, first) : _lerp(1, .9, second),
              rawProgress < .09
                  ? curve.transform((rawProgress / .09).clamp(0.0, 1.0))
                  : 1 -
                        curve.transform(
                          ((rawProgress - .09) / .91).clamp(0.0, 1.0),
                        ),
            )
          : switch (motion) {
              'float' => (
                size.width * particle.x +
                    math.sin(progress * math.pi + particle.phase) *
                        particle.drift,
                size.height + 45 - (size.height + 90) * progress,
                progress * math.pi * 2 - .35 + particle.phase * .08,
                .94 + math.sin(progress * math.pi * 2 + particle.phase) * .06,
                progress < .09
                    ? progress / .09
                    : ((1 - progress) / .91).clamp(0.0, 1.0),
              ),
              'burst' => (
                size.width / 2 +
                    math.cos(particle.phase) * size.width * .62 * progress,
                size.height / 2 +
                    math.sin(particle.phase) * size.height * .62 * progress,
                progress * math.pi * 2 - .35 + particle.phase * .08,
                .94 + math.sin(progress * math.pi * 2 + particle.phase) * .06,
                progress < .09
                    ? progress / .09
                    : ((1 - progress) / .91).clamp(0.0, 1.0),
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
                progress * math.pi * 2 - .35 + particle.phase * .08,
                .94 + math.sin(progress * math.pi * 2 + particle.phase) * .06,
                progress < .09
                    ? progress / .09
                    : ((1 - progress) / .91).clamp(0.0, 1.0),
              ),
              _ => (
                size.width * particle.x +
                    math.sin(progress * math.pi * 2 + particle.phase) *
                        particle.drift,
                -45 + (size.height + 110) * progress,
                progress * math.pi * 2 - .35 + particle.phase * .08,
                .94 + math.sin(progress * math.pi * 2 + particle.phase) * .06,
                progress < .09
                    ? progress / .09
                    : ((1 - progress) / .91).clamp(0.0, 1.0),
              ),
            };
      canvas.save();
      final sprite = sprites[particle.glyph];
      final spec = imEggArtworkSpecs[particle.glyph];
      final layoutWidth = spec == null
          ? particle.size
          : spec.$2 / 128 * particle.size;
      canvas.translate(x + layoutWidth / 2, y + particle.size / 2);
      if (!reducedMotion) {
        canvas.rotate(rotation);
        canvas.scale(scale, scale);
      }
      canvas.saveLayer(
        Rect.fromCircle(center: Offset.zero, radius: particle.size * 1.5),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
      if (sprite != null && spec != null) {
        final pixelScale = particle.size / 128;
        final target = Rect.fromLTWH(
          -(spec.$2 / 2 + 32) * pixelScale,
          -96 * pixelScale,
          sprite.width * pixelScale,
          sprite.height * pixelScale,
        );
        final source = Rect.fromLTWH(
          0,
          0,
          sprite.width.toDouble(),
          sprite.height.toDouble(),
        );
        canvas.drawImageRect(
          sprite,
          source,
          target.shift(const Offset(0, 4)),
          Paint()
            ..colorFilter = const ColorFilter.mode(
              Color(0x3575413C),
              BlendMode.srcIn,
            )
            ..imageFilter = ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        );
        canvas.drawImageRect(
          sprite,
          source,
          target,
          Paint()..filterQuality = FilterQuality.high,
        );
      } else if (_isChinaFlag(particle.glyph)) {
        paintChinaFlag(
          canvas,
          Rect.fromCenter(
            center: Offset.zero,
            width: particle.size * 1.35,
            height: particle.size * .9,
          ),
        );
      } else if (spec == null) {
        final glyphPainter =
            glyphPainters[_glyphPainterKey(
              particle.glyph,
              particle.size.roundToDouble(),
            )];
        if (glyphPainter != null) {
          glyphPainter.paint(
            canvas,
            Offset(-glyphPainter.width / 2, -glyphPainter.height / 2),
          );
        }
      }
      canvas.restore();
      canvas.restore();
    }
    canvas.restore();
    canvas.restore();
  }

  void _drawWash(Canvas canvas, Size size, double elapsed) {
    final rect = Offset.zero & size;
    final washProgress = reducedMotion
        ? 1.0
        : const Cubic(0, 0, .58, 1).transform((elapsed / .45).clamp(0.0, 1.0));
    canvas.saveLayer(
      rect,
      Paint()..color = Colors.white.withValues(alpha: washProgress),
    );
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(.9 + washProgress * .1);
    canvas.translate(-size.width / 2, -size.height / 2);
    if (useCustomWash) {
      canvas.drawRect(rect, Paint()..color = washColor);
    } else if (birthday) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x0AFFF8EE), Color(0x0AF8E3F2)],
          ).createShader(rect),
      );
    } else {
      final center = Offset(
        size.width * .5,
        size.height * (blueWash ? .48 : .47),
      );
      final radius = math.sqrt(
        size.width * size.width * .25 + math.pow(size.height - center.dy, 2),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            radius,
            blueWash
                ? const [
                    Color(0xEDEEF9FF),
                    Color(0xCCDCEEFF),
                    Color(0xBCD9D7FF),
                  ]
                : const [
                    Color(0xEBFFF8DD),
                    Color(0xA3FFF1D5),
                    Color(0xADF0DDFF),
                    Color(0xB8EBE5FF),
                  ],
            blueWash ? const [0, .35, 1] : const [0, .27, .69, 1],
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) =>
      old.reducedMotion != reducedMotion ||
      old.washColor != washColor ||
      old.useCustomWash != useCustomWash ||
      old.glyphPainters != glyphPainters ||
      old.sprites != sprites ||
      old.duration != duration ||
      old.birthday != birthday ||
      old.blueWash != blueWash ||
      old.particles != particles ||
      old.motion != motion;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

String _glyphPainterKey(String glyph, double fontSize) =>
    '$glyph|${fontSize.round()}';

String _emojiForMotif(String motif) => switch (motif) {
  'cake' => '🎂',
  'cakeSlice' || 'pastry' => '🍰',
  'cupcake' => '🧁',
  'redPacket' => '🧧',
  'coin' => '💰',
  'firework' => '🎆',
  'confetti' => '🎉',
  'goldStar' || 'star' => '⭐',
  'sparkle' => '✨',
  'moon' => '🌕',
  'rabbit' => '🐇',
  'snowflake' => '❄️',
  'pine' => '🎄',
  'heart' => '💜',
  'greenHeart' => '💚',
  'cap' => '🎓',
  'sprout' => '🌱',
  'flower' => '🌼',
  'rainbow' => '🌈',
  'flag' => '🇨🇳',
  'gift' => '🎁',
  'ribbon' => '💫',
  'sun' => '☀️',
  _ => '🎊',
};
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
      : imEggArtworkSpecs.containsKey(icon)
      ? SizedBox(
          width: imEggArtworkSpecs[icon]!.$2 / 128 * size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -size / 4,
                top: -size / 4,
                child: Image.asset(
                  imEggArtworkSpecs[icon]!.$1,
                  width: (imEggArtworkSpecs[icon]!.$2 + 64) / 128 * size,
                  height: size * 1.5,
                  excludeFromSemantics: true,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ],
          ),
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
