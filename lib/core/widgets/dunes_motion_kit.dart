import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/desktop_features.dart';
import '../theme/dunes_theme.dart';

/// 轻量紫灰微光骨架块：自动适配日间 / 夜间主题与系统「减弱动态效果」。
class DunesShimmerBox extends StatefulWidget {
  const DunesShimmerBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 10,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  State<DunesShimmerBox> createState() => _DunesShimmerBoxState();
}

class _DunesShimmerBoxState extends State<DunesShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final baseColor = isDark
        ? const Color(0xFF282638)
        : const Color(0xFFECE9F5);
    final highlightColor = isDark
        ? const Color(0xFF393652)
        : const Color(0xFFF8F6FD);

    if (reduceMotion) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final slide = -1.2 + t * 2.4;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(slide - 0.8, -0.2),
              end: Alignment(slide + 0.8, 0.2),
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.15, 0.5, 0.85],
            ),
          ),
        );
      },
    );
  }
}

/// 列表卡片微光骨架屏（审批、任务等列表首屏加载使用）。
class DunesListSkeleton extends StatelessWidget {
  const DunesListSkeleton({
    super.key,
    this.itemCount = 5,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 24),
  });

  final int itemCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1F1E2C) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFECE9F3);

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: itemCount,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 0.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const DunesShimmerBox(width: 28, height: 28, borderRadius: 9),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DunesShimmerBox(
                      width: double.infinity,
                      height: 14,
                      borderRadius: 6,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const DunesShimmerBox(width: 48, height: 18, borderRadius: 9),
                ],
              ),
              const SizedBox(height: 12),
              DunesShimmerBox(
                width: index.isEven ? 210 : 170,
                height: 11,
                borderRadius: 5,
              ),
              const SizedBox(height: 8),
              const DunesShimmerBox(width: 128, height: 10, borderRadius: 5),
            ],
          ),
        );
      },
    );
  }
}

/// AI 思考/处理态扫光文字：仅在挂载（生成中）期间运行动画，销毁即停，无空转帧。
class DunesShimmerText extends StatefulWidget {
  const DunesShimmerText(
    this.text, {
    super.key,
    required this.style,
    this.highlightColor,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;
  final TextStyle style;
  final Color? highlightColor;
  final int maxLines;
  final TextOverflow overflow;

  @override
  State<DunesShimmerText> createState() => _DunesShimmerTextState();
}

class _DunesShimmerTextState extends State<DunesShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseText = Text(
      widget.text,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      style: widget.style,
    );
    if (MediaQuery.disableAnimationsOf(context)) return baseText;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        widget.style.color ??
        (isDark ? const Color(0xFFB5B2C8) : const Color(0xFF6B657D));
    final sheen =
        widget.highlightColor ??
        (isDark ? const Color(0xFFE6DCFF) : DunesColors.brandPurple);

    return AnimatedBuilder(
      animation: _controller,
      child: baseText,
      builder: (context, child) {
        final slide = -1.1 + _controller.value * 2.2;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(slide - 0.55, 0),
              end: Alignment(slide + 0.55, 0),
              colors: [baseColor, sheen, baseColor],
              stops: const [0.1, 0.5, 0.9],
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}

/// 整数平滑滚动计数器（待办数、统计卡片数字变化时柔和过渡）。
class DunesAnimatedCounter extends StatelessWidget {
  const DunesAnimatedCounter({
    super.key,
    required this.value,
    required this.style,
    this.duration = const Duration(milliseconds: 360),
    this.formatter,
  });

  final int value;
  final TextStyle style;
  final Duration duration;
  final String Function(int value)? formatter;

  @override
  Widget build(BuildContext context) {
    final format = formatter ?? (int v) => '$v';
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text(format(value), style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, _) {
        return Text(format(animatedValue.round()), style: style);
      },
    );
  }
}

/// 审批通过/驳回/操作完成后的轻量浮层反馈（非阻塞、自动消失、兼容 PC/移动端）。
void showDunesResultOverlay(
  BuildContext context, {
  required String message,
  bool isSuccess = true,
  Duration duration = const Duration(milliseconds: 1250),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  if (isSuccess) {
    HapticFeedback.mediumImpact();
  } else {
    HapticFeedback.lightImpact();
  }
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _DunesResultOverlayCard(
      message: message,
      isSuccess: isSuccess,
      duration: duration,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _DunesResultOverlayCard extends StatefulWidget {
  const _DunesResultOverlayCard({
    required this.message,
    required this.isSuccess,
    required this.duration,
    required this.onDone,
  });

  final String message;
  final bool isSuccess;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_DunesResultOverlayCard> createState() =>
      _DunesResultOverlayCardState();
}

class _DunesResultOverlayCardState extends State<_DunesResultOverlayCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _ctrl.forward();
    _dismissTimer = Timer(widget.duration, () async {
      if (!mounted) return;
      await _ctrl.reverse();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.isSuccess
        ? const Color(0xFF34C759)
        : const Color(0xFFFF5B61);
    final curve = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    // APP 端统一走顶部「灵动岛」展开形态；PC 端保留居中磨砂卡片。
    if (!isDesktopCommOnly) {
      final topInset = MediaQuery.paddingOf(context).top;
      final islandTop = topInset > 14 ? topInset - 2.0 : 10.0;
      return Positioned(
        top: islandTop,
        left: 16,
        right: 16,
        child: IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, child) {
                final t = curve.value;
                final sx = (0.50 + t * 0.50).clamp(0.45, 1.06);
                final sy = (0.76 + t * 0.24).clamp(0.72, 1.04);
                final dy = (1.0 - t.clamp(0.0, 1.0)) * -18.0;
                return Opacity(
                  opacity: _ctrl.value.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Transform(
                      alignment: Alignment.topCenter,
                      transform: Matrix4.diagonal3Values(sx, sy, 1.0),
                      child: child,
                    ),
                  ),
                );
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.44),
                      blurRadius: 24,
                      spreadRadius: -4,
                      offset: const Offset(0, 10),
                    ),
                    BoxShadow(
                      color: accent.withValues(alpha: 0.28),
                      blurRadius: 18,
                      spreadRadius: -6,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(10, 9, 18, 9),
                      decoration: BoxDecoration(
                        color: widget.isSuccess
                            ? const Color(0xF50B0B10)
                            : const Color(0xF5210D0E),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.34),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              widget.isSuccess
                                  ? Icons.check_rounded
                                  : Icons.close_rounded,
                              size: 17,
                              color: accent,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              widget.message,
                              softWrap: true,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: widget.isSuccess
                                    ? const Color(0xFFC8F7D6)
                                    : const Color(0xFFFFB8BC),
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return IgnorePointer(
      child: Center(
        child: FadeTransition(
          opacity: _ctrl,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.86, end: 1.0).animate(curve),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 148,
                    maxWidth: 260,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: (isDark ? const Color(0xFF232234) : Colors.white)
                        .withValues(alpha: isDark ? 0.88 : 0.92),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.28),
                      width: 0.9,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.36 : 0.12,
                        ),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.isSuccess
                              ? Icons.check_rounded
                              : Icons.close_rounded,
                          size: 26,
                          color: accent,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: DunesTypography.sans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.resolve(context, DunesColors.text),
                          context: context,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 旋转紫调流光描边环（仅在活跃生成态挂载，非生成态不消耗任何帧）。
class DunesGlowRingPainter extends CustomPainter {
  const DunesGlowRingPainter({
    required this.angle,
    required this.isDark,
    this.strokeWidth = 2.0,
  });

  final double angle;
  final bool isDark;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: math.pi * 2,
      transform: GradientRotation(angle),
      colors: isDark
          ? const [
              Color(0x00B69BFF),
              Color(0xFF9E82FF),
              Color(0xFFE6DCFF),
              Color(0x00B69BFF),
            ]
          : const [
              Color(0x007B5CD8),
              Color(0xFF7B5CD8),
              Color(0xFFCBB6FF),
              Color(0x007B5CD8),
            ],
      stops: const [0.0, 0.35, 0.55, 1.0],
    ).createShader(rect);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = shader;
    canvas.drawOval(rect, paint);
  }

  @override
  bool shouldRepaint(covariant DunesGlowRingPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.isDark != isDark;
}
