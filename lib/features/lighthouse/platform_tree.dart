import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 沙丘平台生态树 · 可交互 (Flutter 版)
///
/// 从 SVG 原型移植:
///   - 沙丘为根基与主干,主干上分左右两条主枝
///   - 灯塔(左)/千机(右)灯笼:轻晃 + 呼吸光晕,可点击
///   - 资管(左)/NOVA(右)果实:随风轻摆,可点击
///
/// 用法:
/// ```dart
/// PlatformTree(
///   onLighthouseTap: () => 打开灯塔详情,
///   onQianjiTap:     () => 打开千机详情,
///   onAssetTap:      () => 打开资管数据源,
///   onNovaTap:       () => 打开 NOVA 数据源,
/// )
/// ```
///
/// 缩放:内部按 SVG 原生 680×540 坐标系绘制,外层 FittedBox 等比缩放,
/// 塞进任何宽度都保持长宽比。
class PlatformTree extends StatefulWidget {
  final VoidCallback? onLighthouseTap;
  final VoidCallback? onQianjiTap;
  final VoidCallback? onAssetTap;
  final VoidCallback? onNovaTap;

  /// 底部提示语,传空串即隐藏。
  final String hintText;

  const PlatformTree({
    super.key,
    this.onLighthouseTap,
    this.onQianjiTap,
    this.onAssetTap,
    this.onNovaTap,
    this.hintText = '点击灯笼或果实展开细节',
  });

  @override
  State<PlatformTree> createState() => _PlatformTreeState();
}

enum _TreeNode { none, lighthouse }

class _PlatformTreeState extends State<PlatformTree>
    with TickerProviderStateMixin {
  // 每个 controller 的 duration = SVG CSS 中一半(repeat.reverse 一来一回等于全周期)
  late final AnimationController _lanternWSwing;
  late final AnimationController _lanternCSwing;
  late final AnimationController _fruitWSwing;
  late final AnimationController _fruitCSwing;
  late final AnimationController _glowW;
  late final AnimationController _glowC;
  _TreeNode _selected = _TreeNode.none;

  @override
  void initState() {
    super.initState();
    _lanternWSwing = _makeCtrl(2250);
    _lanternCSwing = _makeCtrl(2500);
    _fruitWSwing = _makeCtrl(2000);
    _fruitCSwing = _makeCtrl(2150);
    _glowW = _makeCtrl(1750);
    _glowC = _makeCtrl(2000);

    // 错开相位,免得所有元件同一节奏抖
    _lanternCSwing.value = 0.35;
    _fruitWSwing.value = 0.55;
    _fruitCSwing.value = 0.15;
    _glowC.value = 0.4;
  }

  AnimationController _makeCtrl(int ms) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: ms),
      )..repeat(reverse: true);

  @override
  void dispose() {
    _lanternWSwing.dispose();
    _lanternCSwing.dispose();
    _fruitWSwing.dispose();
    _fruitCSwing.dispose();
    _glowW.dispose();
    _glowC.dispose();
    super.dispose();
  }

  void _select(_TreeNode node) {
    setState(() {
      _selected = _selected == node ? _TreeNode.none : node;
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = _Palette.forBrightness(dark: dark);

    return AspectRatio(
      aspectRatio: 680 / 540,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: 680,
          height: 540,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 静态树:背景 / 土 / 根 / 干 / 枝 / 叶 / 文字提示
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _selected = _TreeNode.none),
                  child: CustomPaint(
                    painter: _TreePainter(
                      palette: palette,
                      hint: widget.hintText,
                    ),
                  ),
                ),
              ),

                // 果实 · 资管
                _AnimatedFruit(
                  bounds: const Rect.fromLTWH(220, 195, 66, 90),
                  localCenter: const Offset(33, 27),
                  localPivot: const Offset(33, 80),
                  label: '资管',
                  palette: _FruitPalette.warm(dark: dark, stem: palette.stem),
                  controller: _fruitWSwing,
                  onTap: widget.onAssetTap,
                ),

                // 果实 · NOVA
                _AnimatedFruit(
                  bounds: const Rect.fromLTWH(384, 195, 66, 90),
                  localCenter: const Offset(33, 27),
                  localPivot: const Offset(33, 80),
                  label: 'NOVA',
                  palette: _FruitPalette.cool(dark: dark, stem: palette.stem),
                  controller: _fruitCSwing,
                  onTap: widget.onNovaTap,
                ),

                // 灯笼 · 灯塔
                _AnimatedLantern(
                  bounds: const Rect.fromLTWH(60, 115, 176, 155),
                  localCenter: const Offset(88, 73),
                  localPivot: const Offset(88, 7),
                  title: '灯塔',
                  subtitle: '市场部 · 统计平台',
                  palette: _LanternPalette.warm(
                    dark: dark,
                    string: palette.string,
                  ),
                  swingCtrl: _lanternWSwing,
                  glowCtrl: _glowW,
                  glow1Range: const _Range(0.30, 0.44),
                  glow2Range: const _Range(0.22, 0.34),
                  onTap: () => _select(_TreeNode.lighthouse),
                ),

                // 灯笼 · 千机
                _AnimatedLantern(
                  bounds: const Rect.fromLTWH(434, 115, 176, 155),
                  localCenter: const Offset(88, 73),
                  localPivot: const Offset(88, 7),
                  title: '千机',
                  subtitle: '研发部 · 统计平台',
                  palette: _LanternPalette.cool(
                    dark: dark,
                    string: palette.string,
                  ),
                  swingCtrl: _lanternCSwing,
                  glowCtrl: _glowC,
                  glow1Range: const _Range(0.32, 0.46),
                  glow2Range: const _Range(0.22, 0.32),
                  onTap: widget.onQianjiTap,
                ),

                // 灯塔总结卡 · 悬在灯笼上方
                if (_selected == _TreeNode.lighthouse)
                  Positioned(
                    left: 28,
                    top: 4,
                    width: 248,
                    child: _NodeSummaryCard(
                      title: '灯塔',
                      kicker: '市场部 · 统计平台',
                      accent: const Color(0xFFC47A3A),
                      lines: const [
                        ('哨兵', '折扣改写 / 毛利跳变 / 口径偏差'),
                        ('规模', '双口径毛利 · 本期偏差追踪'),
                        ('结构', 'Top3 增幅 / 塌陷 / 反常'),
                      ],
                      actionLabel: '进入灯塔',
                      onAction: widget.onLighthouseTap,
                      onClose: () =>
                          setState(() => _selected = _TreeNode.none),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
  }
}

// ============================================================================
//  Summary card · 点灯笼后浮在上方
// ============================================================================

class _NodeSummaryCard extends StatelessWidget {
  const _NodeSummaryCard({
    required this.title,
    required this.kicker,
    required this.accent,
    required this.lines,
    required this.actionLabel,
    this.onAction,
    this.onClose,
  });

  final String title;
  final String kicker;
  final Color accent;
  final List<(String, String)> lines;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFBF8F1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withAlpha(90), width: 1),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5A458F).withAlpha(28),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2A241C),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onClose,
                  child: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Color(0xFF9A8F7E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              kicker,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: accent.withAlpha(220),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            for (final line in lines) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        line.$1,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5A458F),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        line.$2,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: Color(0xFF5A5348),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                child: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
//  Palettes
// ============================================================================

class _Palette {
  final bool dark;
  final Color barkFill;
  final Color barkStroke;
  final Color barkLine;
  final Color barkHi;
  final Color barkTex;
  final Color knot;
  final Color soilLine;
  final Color soilLabel;
  final Color trunkLabel;
  final Color hint;
  final Color leafA;
  final Color leafB;
  final Color stem;
  final Color string;
  final Color skyTop;
  final Color skyMid;
  final Color skyBottom;
  final Color duneFar;
  final Color duneNear;
  final Color sunGlow;

  const _Palette({
    required this.dark,
    required this.barkFill,
    required this.barkStroke,
    required this.barkLine,
    required this.barkHi,
    required this.barkTex,
    required this.knot,
    required this.soilLine,
    required this.soilLabel,
    required this.trunkLabel,
    required this.hint,
    required this.leafA,
    required this.leafB,
    required this.stem,
    required this.string,
    required this.skyTop,
    required this.skyMid,
    required this.skyBottom,
    required this.duneFar,
    required this.duneNear,
    required this.sunGlow,
  });

  factory _Palette.forBrightness({required bool dark}) => dark
      ? const _Palette(
          dark: true,
          barkFill: Color(0xFFA57C4B),
          barkStroke: Color(0xFF7A5A2E),
          barkLine: Color(0xFFA57C4B),
          barkHi: Color(0x8CC9A776),
          barkTex: Color(0x597A5A2E),
          knot: Color(0x597A5A2E),
          soilLine: Color(0xFFA89078),
          soilLabel: Color(0xFFA57C4B),
          trunkLabel: Color(0xFFFBF6ED),
          hint: Color(0xA6A57C4B),
          leafA: Color(0xB8B8884A),
          leafB: Color(0x8C97C459),
          stem: Color(0xFFA57C4B),
          string: Color(0xFFA57C4B),
          skyTop: Color(0xFF1A2230),
          skyMid: Color(0xFF2A3344),
          skyBottom: Color(0xFF3D3228),
          duneFar: Color(0xFF4A3A2C),
          duneNear: Color(0xFF5C4634),
          sunGlow: Color(0x66E8A85A),
        )
      : const _Palette(
          dark: false,
          barkFill: Color(0xFF8B6A3F),
          barkStroke: Color(0xFF6B4E28),
          barkLine: Color(0xFF8B6A3F),
          barkHi: Color(0x8CB39567),
          barkTex: Color(0x596B4E28),
          knot: Color(0x596B4E28),
          soilLine: Color(0xFFA89078),
          soilLabel: Color(0xFF8B6A3F),
          trunkLabel: Color(0xFFFBF6ED),
          hint: Color(0xA68B6A3F),
          leafA: Color(0xB8B8884A),
          leafB: Color(0x8C97C459),
          stem: Color(0xFF6B4E28),
          string: Color(0xFF6B4E28),
          skyTop: Color(0xFFE8F0F4),
          skyMid: Color(0xFFF3E8D4),
          skyBottom: Color(0xFFE8D5B8),
          duneFar: Color(0xFFD4B896),
          duneNear: Color(0xFFC9A87A),
          sunGlow: Color(0x55F0C070),
        );
}

class _LanternPalette {
  final Color bodyFill;
  final Color bodyStroke;
  final Color cap;
  final Color glow1;
  final Color glow2;
  final Color titleColor;
  final Color subtitleColor;
  final Color string;

  const _LanternPalette({
    required this.bodyFill,
    required this.bodyStroke,
    required this.cap,
    required this.glow1,
    required this.glow2,
    required this.titleColor,
    required this.subtitleColor,
    required this.string,
  });

  factory _LanternPalette.warm({required bool dark, required Color string}) =>
      _LanternPalette(
        bodyFill: dark ? const Color(0xFF2C1810) : const Color(0xFFFBF6ED),
        bodyStroke:
            dark ? const Color(0xFFF0997B) : const Color(0xFFB8884A),
        cap: const Color(0xFFB8884A),
        glow1: const Color(0xFFF0997B),
        glow2: const Color(0xFFEF9F27),
        titleColor:
            dark ? const Color(0xFFF5C4B3) : const Color(0xFF4A1B0C),
        subtitleColor:
            dark ? const Color(0xFFB8A88C) : const Color(0xFF6B5A42),
        string: string,
      );

  factory _LanternPalette.cool({required bool dark, required Color string}) =>
      _LanternPalette(
        bodyFill: dark ? const Color(0xFF0A2620) : const Color(0xFFF0F7F4),
        bodyStroke:
            dark ? const Color(0xFF5DCAA5) : const Color(0xFF1D9E75),
        cap: const Color(0xFF1D9E75),
        glow1: const Color(0xFF5DCAA5),
        glow2: const Color(0xFF85B7EB),
        titleColor:
            dark ? const Color(0xFF9FE1CB) : const Color(0xFF04342C),
        subtitleColor:
            dark ? const Color(0xFFB8A88C) : const Color(0xFF6B5A42),
        string: string,
      );
}

class _FruitPalette {
  final Color fill;
  final Color stroke;
  final Color highlight;
  final Color label;
  final Color stem;

  const _FruitPalette({
    required this.fill,
    required this.stroke,
    required this.highlight,
    required this.label,
    required this.stem,
  });

  factory _FruitPalette.warm({required bool dark, required Color stem}) =>
      _FruitPalette(
        fill: const Color(0xFFEF9F27),
        stroke: const Color(0xFF854F0B),
        highlight: const Color(0xB3FAC775),
        label: Colors.white,
        stem: stem,
      );

  factory _FruitPalette.cool({required bool dark, required Color stem}) =>
      _FruitPalette(
        fill: const Color(0xFF378ADD),
        stroke: const Color(0xFF0C447C),
        highlight: const Color(0xB3B5D4F4),
        label: Colors.white,
        stem: stem,
      );
}

class _Range {
  final double min;
  final double max;
  const _Range(this.min, this.max);
  double lerp(double t) => min + (max - min) * t;
}

// ============================================================================
//  Interactive elements
// ============================================================================

class _AnimatedLantern extends StatelessWidget {
  final Rect bounds;
  final Offset localCenter; // 灯身+光晕中心(local 坐标)
  final Offset localPivot; // 摆动支点(local 坐标)= 挂绳与树枝相接处
  final String title;
  final String subtitle;
  final _LanternPalette palette;
  final AnimationController swingCtrl;
  final AnimationController glowCtrl;
  final _Range glow1Range;
  final _Range glow2Range;
  final VoidCallback? onTap;

  const _AnimatedLantern({
    required this.bounds,
    required this.localCenter,
    required this.localPivot,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.swingCtrl,
    required this.glowCtrl,
    required this.glow1Range,
    required this.glow2Range,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: bounds,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: Listenable.merge([swingCtrl, glowCtrl]),
            builder: (context, _) {
              // 摆动 -2° ~ +2°
              final angle = (swingCtrl.value * 4 - 2) * math.pi / 180;
              return Transform(
                transform: Matrix4.rotationZ(angle),
                origin: localPivot,
                child: CustomPaint(
                  size: bounds.size,
                  painter: _LanternPainter(
                    center: localCenter,
                    title: title,
                    subtitle: subtitle,
                    palette: palette,
                    glow1Opacity: glow1Range.lerp(glowCtrl.value),
                    glow2Opacity: glow2Range.lerp(glowCtrl.value),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AnimatedFruit extends StatelessWidget {
  final Rect bounds;
  final Offset localCenter;
  final Offset localPivot;
  final String label;
  final _FruitPalette palette;
  final AnimationController controller;
  final VoidCallback? onTap;

  const _AnimatedFruit({
    required this.bounds,
    required this.localCenter,
    required this.localPivot,
    required this.label,
    required this.palette,
    required this.controller,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: bounds,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              // 摆动 -3° ~ +3°
              final angle = (controller.value * 6 - 3) * math.pi / 180;
              return Transform(
                transform: Matrix4.rotationZ(angle),
                origin: localPivot,
                child: child,
              );
            },
            child: CustomPaint(
              size: bounds.size,
              painter: _FruitPainter(
                center: localCenter,
                label: label,
                palette: palette,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
//  Tree base painter · 土 + 根 + 干 + 枝 + 叶 + 提示
// ============================================================================

class _TreePainter extends CustomPainter {
  final _Palette palette;
  final String hint;

  _TreePainter({required this.palette, required this.hint});

  @override
  void paint(Canvas canvas, Size size) {
    _drawSky(canvas, size);
    _drawSun(canvas);
    _drawDunes(canvas, size);
    _drawSoil(canvas);
    _drawRoots(canvas);
    _drawTrunk(canvas);
    _drawTrunkTexture(canvas);
    _drawTrunkLabel(canvas);
    _drawBranches(canvas);
    _drawTwigs(canvas);
    _drawLeaves(canvas);
    _drawSoilLabel(canvas);
    if (hint.isNotEmpty) _drawHint(canvas);
  }

  void _drawSky(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [palette.skyTop, palette.skyMid, palette.skyBottom],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  void _drawSun(Canvas canvas) {
    final center = const Offset(520, 88);
    canvas.drawCircle(
      center,
      72,
      Paint()..color = palette.sunGlow,
    );
    canvas.drawCircle(
      center,
      36,
      Paint()..color = palette.sunGlow.withAlpha(140),
    );
  }

  void _drawDunes(Canvas canvas, Size size) {
    // 远沙丘
    final far = Path()
      ..moveTo(0, 390)
      ..quadraticBezierTo(120, 350, 240, 375)
      ..quadraticBezierTo(360, 400, 480, 360)
      ..quadraticBezierTo(580, 335, 680, 370)
      ..lineTo(680, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(far, Paint()..color = palette.duneFar.withAlpha(120));

    // 近沙丘
    final near = Path()
      ..moveTo(0, 430)
      ..quadraticBezierTo(140, 400, 280, 425)
      ..quadraticBezierTo(420, 455, 560, 415)
      ..quadraticBezierTo(640, 395, 680, 420)
      ..lineTo(680, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(near, Paint()..color = palette.duneNear.withAlpha(160));
  }

  void _drawSoil(Canvas canvas) {
    final paint = Paint()
      ..color = palette.soilLine
      ..strokeWidth = 0.5;
    _dashedLine(canvas, const Offset(60, 465), const Offset(620, 465), paint,
        dash: 3, gap: 6);
  }

  void _drawRoots(Canvas canvas) {
    final paint = Paint()
      ..color = palette.barkLine
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const roots = <_RootData>[
      _RootData(4, Offset(320, 462), Offset(285, 482), Offset(240, 498)),
      _RootData(4, Offset(335, 462), Offset(335, 490), Offset(330, 508)),
      _RootData(4, Offset(350, 462), Offset(385, 482), Offset(430, 498)),
      _RootData(3, Offset(302, 462), Offset(260, 475), Offset(215, 480)),
      _RootData(3, Offset(368, 462), Offset(410, 470), Offset(455, 478)),
      _RootData(2, Offset(240, 498), Offset(220, 508), Offset(200, 510)),
      _RootData(2, Offset(430, 498), Offset(450, 508), Offset(470, 510)),
      _RootData(2, Offset(215, 480), Offset(195, 485), Offset(180, 488)),
      _RootData(2, Offset(455, 478), Offset(475, 485), Offset(490, 488)),
    ];

    for (final r in roots) {
      paint.strokeWidth = r.width.toDouble();
      final path = Path()
        ..moveTo(r.start.dx, r.start.dy)
        ..quadraticBezierTo(r.ctrl.dx, r.ctrl.dy, r.end.dx, r.end.dy);
      canvas.drawPath(path, paint);
    }
  }

  void _drawTrunk(Canvas canvas) {
    final path = Path()
      ..moveTo(292, 465)
      ..quadraticBezierTo(302, 400, 315, 335)
      ..lineTo(355, 335)
      ..quadraticBezierTo(368, 400, 378, 465)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = palette.barkFill
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.barkStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75,
    );
  }

  void _drawTrunkTexture(Canvas canvas) {
    final tex = Paint()
      ..color = palette.barkTex
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(const Offset(320, 340), const Offset(325, 462), tex);
    canvas.drawLine(const Offset(340, 340), const Offset(340, 462), tex);
    canvas.drawLine(const Offset(353, 340), const Offset(358, 462), tex);

    // 树节
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(325, 405), width: 6, height: 12),
      Paint()..color = palette.knot,
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(352, 435), width: 6, height: 10),
      Paint()..color = palette.knot,
    );
  }

  void _drawTrunkLabel(Canvas canvas) {
    _paintText(
      canvas,
      '沙',
      const Offset(335, 380),
      TextStyle(
        color: palette.trunkLabel,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 1,
        height: 1.0,
      ),
    );
    _paintText(
      canvas,
      '丘',
      const Offset(335, 405),
      TextStyle(
        color: palette.trunkLabel,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 1,
        height: 1.0,
      ),
    );
  }

  void _drawBranches(Canvas canvas) {
    // 左主枝
    final left = Path()
      ..moveTo(318, 335)
      ..quadraticBezierTo(265, 285, 210, 220)
      ..quadraticBezierTo(172, 175, 148, 122);

    canvas.drawPath(
      left,
      Paint()
        ..color = palette.barkLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round,
    );

    // 左主枝高光
    final leftHi = Path()
      ..moveTo(320, 335)
      ..quadraticBezierTo(267, 285, 212, 220)
      ..quadraticBezierTo(174, 175, 150, 124);

    canvas.drawPath(
      leftHi,
      Paint()
        ..color = palette.barkHi
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );

    // 右主枝
    final right = Path()
      ..moveTo(352, 335)
      ..quadraticBezierTo(405, 285, 460, 220)
      ..quadraticBezierTo(498, 175, 522, 122);

    canvas.drawPath(
      right,
      Paint()
        ..color = palette.barkLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round,
    );

    final rightHi = Path()
      ..moveTo(350, 335)
      ..quadraticBezierTo(403, 285, 458, 220)
      ..quadraticBezierTo(496, 175, 520, 124);

    canvas.drawPath(
      rightHi,
      Paint()
        ..color = palette.barkHi
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawTwigs(Canvas canvas) {
    final paint = Paint()
      ..color = palette.barkLine
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const twigs = <_RootData>[
      _RootData(3, Offset(260, 295), Offset(240, 285), Offset(222, 285)),
      _RootData(3, Offset(205, 225), Offset(185, 215), Offset(170, 215)),
      _RootData(2, Offset(232, 253), Offset(218, 250), Offset(210, 253)),
      _RootData(3, Offset(410, 295), Offset(430, 285), Offset(448, 285)),
      _RootData(3, Offset(465, 225), Offset(485, 215), Offset(500, 215)),
      _RootData(2, Offset(438, 253), Offset(452, 250), Offset(460, 253)),
    ];

    for (final t in twigs) {
      paint.strokeWidth = t.width.toDouble();
      final path = Path()
        ..moveTo(t.start.dx, t.start.dy)
        ..quadraticBezierTo(t.ctrl.dx, t.ctrl.dy, t.end.dx, t.end.dy);
      canvas.drawPath(path, paint);
    }
  }

  void _drawLeaves(Canvas canvas) {
    const leaves = <_LeafData>[
      // 左半冠
      _LeafData(Offset(288, 278), 10, 5, false, -40),
      _LeafData(Offset(248, 248), 9, 4.5, true, -55),
      _LeafData(Offset(222, 228), 10, 5, false, -65),
      _LeafData(Offset(185, 185), 9, 4.5, true, -30),
      _LeafData(Offset(220, 195), 8, 4, false, -70),
      _LeafData(Offset(165, 150), 8, 4, true, -40),
      _LeafData(Offset(200, 270), 8, 4, false, -50),
      // 右半冠
      _LeafData(Offset(382, 278), 10, 5, false, 40),
      _LeafData(Offset(422, 248), 9, 4.5, true, 55),
      _LeafData(Offset(448, 228), 10, 5, false, 65),
      _LeafData(Offset(485, 185), 9, 4.5, true, 30),
      _LeafData(Offset(450, 195), 8, 4, false, 70),
      _LeafData(Offset(505, 150), 8, 4, true, 40),
      _LeafData(Offset(470, 270), 8, 4, false, 50),
    ];

    for (final leaf in leaves) {
      final color = leaf.copper ? palette.leafA : palette.leafB;
      canvas.save();
      canvas.translate(leaf.center.dx, leaf.center.dy);
      canvas.rotate(leaf.angleDeg * math.pi / 180);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: leaf.rx * 2, height: leaf.ry * 2),
        Paint()..color = color,
      );
      canvas.restore();
    }
  }

  void _drawSoilLabel(Canvas canvas) {
    _paintText(
      canvas,
      '底土',
      const Offset(620, 484),
      TextStyle(
        color: palette.soilLabel,
        fontSize: 11,
        letterSpacing: 4,
        height: 1.0,
      ),
      align: _TextAlign.end,
    );
  }

  void _drawHint(Canvas canvas) {
    _paintText(
      canvas,
      hint,
      const Offset(340, 530),
      TextStyle(
        color: palette.hint,
        fontSize: 11,
        letterSpacing: 2,
        height: 1.0,
      ),
    );
  }

  @override
  bool shouldRepaint(_TreePainter old) =>
      old.palette.dark != palette.dark || old.hint != hint;
}

// ============================================================================
//  Lantern painter · 挂绳 + 光晕 + 灯身 + 流苏 + 文字
// ============================================================================

class _LanternPainter extends CustomPainter {
  final Offset center;
  final String title;
  final String subtitle;
  final _LanternPalette palette;
  final double glow1Opacity;
  final double glow2Opacity;

  _LanternPainter({
    required this.center,
    required this.title,
    required this.subtitle,
    required this.palette,
    required this.glow1Opacity,
    required this.glow2Opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 挂绳(顶部到灯帽)
    final stringPaint = Paint()
      ..color = palette.string
      ..strokeWidth = 0.75
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center.dx, 7), Offset(center.dx, 27), stringPaint);

    // 外光晕
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 144, height: 120),
      Paint()..color = palette.glow1.withOpacity(glow1Opacity),
    );
    // 内光晕
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 100, height: 84),
      Paint()..color = palette.glow2.withOpacity(glow2Opacity),
    );

    // 灯帽
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(center.dx - 55, 27, 110, 9),
        const Radius.circular(2),
      ),
      Paint()..color = palette.cap,
    );

    // 灯身
    final bodyRect = Rect.fromLTWH(center.dx - 50, 36, 100, 70);
    final bodyRRect =
        RRect.fromRectAndRadius(bodyRect, const Radius.circular(18));
    canvas.drawRRect(
      bodyRRect,
      Paint()..color = palette.bodyFill,
    );
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..color = palette.bodyStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75,
    );

    // 底帽
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(center.dx - 55, 106, 110, 6),
        const Radius.circular(2),
      ),
      Paint()..color = palette.cap,
    );

    // 流苏绳
    canvas.drawLine(
      Offset(center.dx, 112),
      Offset(center.dx, 135),
      stringPaint,
    );

    // 流苏球
    canvas.drawCircle(
      Offset(center.dx, 139),
      3.5,
      Paint()..color = palette.cap,
    );

    // 标题
    _paintText(
      canvas,
      title,
      Offset(center.dx, 65),
      TextStyle(
        color: palette.titleColor,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 1.0,
      ),
    );

    // 副标题
    _paintText(
      canvas,
      subtitle,
      Offset(center.dx, 89),
      TextStyle(
        color: palette.subtitleColor,
        fontSize: 12,
        height: 1.0,
      ),
    );
  }

  @override
  bool shouldRepaint(_LanternPainter old) =>
      old.glow1Opacity != glow1Opacity ||
      old.glow2Opacity != glow2Opacity ||
      old.palette.bodyFill != palette.bodyFill ||
      old.title != title ||
      old.subtitle != subtitle;
}

// ============================================================================
//  Fruit painter · 果柄 + 果身 + 高光 + 文字
// ============================================================================

class _FruitPainter extends CustomPainter {
  final Offset center;
  final String label;
  final _FruitPalette palette;

  _FruitPainter({
    required this.center,
    required this.label,
    required this.palette,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 果柄
    canvas.drawLine(
      Offset(center.dx, center.dy + 18),
      Offset(center.dx, center.dy + 53),
      Paint()
        ..color = palette.stem
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );

    // 果身
    canvas.drawCircle(
      center,
      19,
      Paint()..color = palette.fill,
    );
    canvas.drawCircle(
      center,
      19,
      Paint()
        ..color = palette.stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // 高光
    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(-6, -7),
        width: 12,
        height: 8,
      ),
      Paint()..color = palette.highlight,
    );

    // 标签
    _paintText(
      canvas,
      label,
      Offset(center.dx, center.dy + 2),
      TextStyle(
        color: palette.label,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.0,
      ),
    );
  }

  @override
  bool shouldRepaint(_FruitPainter old) =>
      old.label != label ||
      old.palette.fill != palette.fill ||
      old.center != center;
}

// ============================================================================
//  Data
// ============================================================================

class _RootData {
  final int width;
  final Offset start;
  final Offset ctrl;
  final Offset end;
  const _RootData(this.width, this.start, this.ctrl, this.end);
}

class _LeafData {
  final Offset center;
  final double rx;
  final double ry;
  final bool copper; // true = copper leaf (A), false = green leaf (B)
  final double angleDeg;
  const _LeafData(this.center, this.rx, this.ry, this.copper, this.angleDeg);
}

enum _TextAlign { start, center, end }

// ============================================================================
//  Drawing helpers
// ============================================================================

void _paintText(
  Canvas canvas,
  String text,
  Offset anchor,
  TextStyle style, {
  _TextAlign align = _TextAlign.center,
}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  double dx;
  switch (align) {
    case _TextAlign.start:
      dx = anchor.dx;
      break;
    case _TextAlign.center:
      dx = anchor.dx - tp.width / 2;
      break;
    case _TextAlign.end:
      dx = anchor.dx - tp.width;
      break;
  }
  final dy = anchor.dy - tp.height / 2;
  tp.paint(canvas, Offset(dx, dy));
}

void _dashedLine(
  Canvas canvas,
  Offset start,
  Offset end,
  Paint paint, {
  double dash = 3,
  double gap = 6,
}) {
  final delta = end - start;
  final total = delta.distance;
  if (total <= 0) return;
  final dir = Offset(delta.dx / total, delta.dy / total);

  double t = 0;
  while (t < total) {
    final segEnd = math.min(t + dash, total);
    canvas.drawLine(
      Offset(start.dx + dir.dx * t, start.dy + dir.dy * t),
      Offset(start.dx + dir.dx * segEnd, start.dy + dir.dy * segEnd),
      paint,
    );
    t += dash + gap;
  }
}
