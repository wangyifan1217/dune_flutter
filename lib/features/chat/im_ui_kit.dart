import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';

/// IM 模块统一的苹果风品牌紫（#7B5CD8）+ 轻量浮岛磨砂视觉令牌与交互组件。
///
/// 所有页面与子页面共用此套语义令牌，自动适配日间 / 夜间 / 桌面端主题，
/// 且仅承担视觉与微交互增强，不改变任何业务状态与功能逻辑。
abstract final class ImVisualTokens {
  static const Color purple = DunesColors.brandPurple; // #7B5CD8
  static const Color purpleDeep = Color(0xFF5D3FB8);
  static const Color purpleLight = Color(0xFF9A7FF0);
  static const Color purpleSoft = Color(0xFFF3EEFC);
  static const Color purpleSoftDark = Color(0xFF2B2340);
  static const Color purpleLine = Color(0x2E7B5CD8);
  static const Color purpleGlow = Color(0x247B5CD8);

  /// iOS 分组页面浅底（与系统分组卡片形成温润层次）。
  static const Color iosGroupedBgLight = Color(0xFFF5F4F8);
  static const Color iosGroupedBgDark = Color(0xFF15151E);

  /// 会话画布浅底（略带空气感的极浅冷白/紫灰）。
  static const Color chatCanvasLight = Color(0xFFF8F7FB);
  static const Color chatCanvasDark = Color(0xFF14141D);

  static const Duration fastAnim = Duration(milliseconds: 160);
  static const Duration smoothAnim = Duration(milliseconds: 240);
  static const Curve iosCurve = Curves.easeOutCubic;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color accent(BuildContext context) =>
      isDark(context) ? const Color(0xFFB69BFF) : purple;

  static Color accentText(BuildContext context) =>
      isDark(context) ? const Color(0xFFCBB6FF) : const Color(0xFF6345C2);

  static Color accentSoftSurface(BuildContext context) =>
      isDark(context) ? purpleSoftDark : purpleSoft;

  static Color groupedBackground(BuildContext context) {
    if (isDark(context)) return iosGroupedBgDark;
    return isDesktopCommOnly ? const Color(0xFFF5F5F8) : iosGroupedBgLight;
  }

  static Color cardSurface(BuildContext context) =>
      isDark(context) ? const Color(0xFF21202E) : Colors.white;

  static Color cardElevated(BuildContext context) =>
      isDark(context) ? const Color(0xFF292738) : const Color(0xFFFBFBFE);

  static Color hairlineBorder(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : const Color(0xFFECE9F3);

  static List<BoxShadow> softCardShadow(BuildContext context) {
    if (isDark(context)) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 16,
          spreadRadius: -4,
          offset: const Offset(0, 6),
        ),
      ];
    }
    return [
      BoxShadow(
        color: const Color(0xFF4A3A7A).withValues(alpha: 0.06),
        blurRadius: 18,
        spreadRadius: -4,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.03),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  static List<BoxShadow> floatingIslandShadow(BuildContext context) {
    if (isDark(context)) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.45),
          blurRadius: 24,
          spreadRadius: -4,
          offset: const Offset(0, 10),
        ),
      ];
    }
    return [
      BoxShadow(
        color: const Color(0xFF4A3A7A).withValues(alpha: 0.14),
        blurRadius: 22,
        spreadRadius: -6,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: const Color(0xFF4A3A7A).withValues(alpha: 0.06),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  static LinearGradient primaryGradient(BuildContext context) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: isDark(context)
        ? const [Color(0xFF8B6CE6), Color(0xFF6A4FC9)]
        : const [Color(0xFF896AE4), Color(0xFF7050CE)],
  );
}

/// 轻量浮岛磨砂外壳（iOS 毛玻璃 + 极细紫调描边 + 轻投影）。
class ImFrostedIsland extends StatelessWidget {
  const ImFrostedIsland({
    super.key,
    required this.child,
    this.borderRadius = 999,
    this.padding = EdgeInsets.zero,
    this.blurSigma = 18,
    this.surfaceAlpha,
    this.tintColor,
    this.borderColor,
    this.shadows,
  });

  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double blurSigma;
  final double? surfaceAlpha;
  final Color? tintColor;
  final Color? borderColor;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final dark = ImVisualTokens.isDark(context);
    final baseColor =
        tintColor ??
        (dark ? const Color(0xFF262436) : const Color(0xFFFFFFFF));
    final alpha = surfaceAlpha ?? (dark ? 0.84 : 0.88);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows ?? ImVisualTokens.floatingIslandShadow(context),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: alpha),
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color:
                    borderColor ??
                    (dark
                        ? Colors.white.withValues(alpha: 0.12)
                        : const Color(0x267B5CD8)),
                width: 0.6,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// iOS 风格微按压缩放 + 桌面悬停高亮交互包裹。
class ImTapScale extends StatefulWidget {
  const ImTapScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.pressedScale = 0.972,
    this.enableHoverTint = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final double pressedScale;
  final bool enableHoverTint;

  @override
  State<ImTapScale> createState() => _ImTapScaleState();
}

class _ImTapScaleState extends State<ImTapScale> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final scale = (!enabled || !_pressed || disableAnim)
        ? 1.0
        : widget.pressedScale;
    final overlayColor = !enabled
        ? Colors.transparent
        : _pressed
        ? ImVisualTokens.accent(context).withValues(alpha: 0.08)
        : (_hovered && widget.enableHoverTint
              ? ImVisualTokens.accent(context).withValues(alpha: 0.04)
              : Colors.transparent);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) {
        if (enabled && !_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: scale,
          duration: disableAnim
              ? Duration.zero
              : const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: Stack(
            children: [
              widget.child,
              if (overlayColor != Colors.transparent)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: disableAnim
                          ? Duration.zero
                          : const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        color: overlayColor,
                        borderRadius: widget.borderRadius,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS 设置/详情页风格的圆角分组卡片容器（自动在子项间插入内缩发丝分割线）。
class ImGroupedCard extends StatelessWidget {
  const ImGroupedCard({
    super.key,
    required this.children,
    this.margin = EdgeInsets.zero,
    this.radius = 16,
    this.dividerIndent = 52,
    this.showBorder = true,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final double radius;
  final double dividerIndent;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final dividerColor = ImVisualTokens.hairlineBorder(context);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: ImVisualTokens.cardSurface(context),
        borderRadius: BorderRadius.circular(radius),
        border: showBorder
            ? Border.all(color: dividerColor, width: 0.7)
            : null,
        boxShadow: ImVisualTokens.softCardShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.6,
                thickness: 0.6,
                indent: dividerIndent,
                endIndent: 14,
                color: dividerColor,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// iOS 风格分段胶囊切换条（带平滑滑动高亮块）。
class ImSegmentedPillBar<T> extends StatelessWidget {
  const ImSegmentedPillBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.height = 38,
    this.padding = const EdgeInsets.all(3),
  });

  final List<({T value, String label, int badgeCount})> items;
  final T selected;
  final ValueChanged<T> onSelected;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final dark = ImVisualTokens.isDark(context);
    final trackColor = dark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFEEEBF5);
    final selectedIndex = items.indexWhere((e) => e.value == selected);
    final activeIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final alignX = items.length <= 1
        ? 0.0
        : -1.0 + (2.0 * activeIndex / (items.length - 1));

    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final thumbWidth = items.isEmpty
              ? constraints.maxWidth
              : constraints.maxWidth / items.length;
          return Stack(
            children: [
              AnimatedAlign(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment(alignX, 0),
                child: Container(
                  width: thumbWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: dark ? const Color(0xFF36324B) : Colors.white,
                    borderRadius: BorderRadius.circular(9.5),
                    boxShadow: [
                      BoxShadow(
                        color: dark
                            ? Colors.black.withValues(alpha: 0.25)
                            : const Color(0xFF4A3A7A).withValues(alpha: 0.10),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final item in items)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelected(item.value),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DunesTypography.sans(
                                    fontSize: 13,
                                    fontWeight: item.value == selected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: item.value == selected
                                        ? ImVisualTokens.accentText(context)
                                        : DunesColors.resolve(
                                            context,
                                            DunesColors.text2,
                                          ),
                                    context: context,
                                  ),
                                ),
                              ),
                              if (item.badgeCount > 0) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: item.value == selected
                                        ? ImVisualTokens.accentSoftSurface(
                                            context,
                                          )
                                        : (dark
                                              ? Colors.white.withValues(
                                                  alpha: 0.10,
                                                )
                                              : const Color(0xFFE3DFEE)),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    item.badgeCount > 99
                                        ? '99+'
                                        : '${item.badgeCount}',
                                    style: DunesTypography.sans(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: item.value == selected
                                          ? ImVisualTokens.accentText(context)
                                          : DunesColors.resolve(
                                              context,
                                              DunesColors.text3,
                                            ),
                                      context: context,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 品牌紫圆角选择勾选圈（替代生硬的静态 Icons.check_circle）。
class ImSelectCircle extends StatelessWidget {
  const ImSelectCircle({
    super.key,
    required this.selected,
    this.size = 22,
  });

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = ImVisualTokens.isDark(context);
    final accent = ImVisualTokens.accent(context);
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? accent : Colors.transparent,
        border: Border.all(
          color: selected
              ? accent
              : (dark
                    ? Colors.white.withValues(alpha: 0.28)
                    : const Color(0xFFC9C4D6)),
          width: selected ? 0 : 1.6,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.28),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : const [],
      ),
      child: AnimatedScale(
        scale: selected ? 1.0 : 0.4,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: size * 0.64,
                color: dark ? const Color(0xFF1D182D) : Colors.white,
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// 关键词紫调高亮文本（纯渲染增强，不改动匹配逻辑）。
class ImHighlightedText extends StatelessWidget {
  const ImHighlightedText({
    super.key,
    required this.text,
    required this.query,
    required this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;
  final String query;
  final TextStyle style;
  final int maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    if (q.isEmpty || text.isEmpty) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: overflow,
        style: style,
      );
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = q.toLowerCase();
    final spans = <InlineSpan>[];
    final highlightStyle = style.copyWith(
      color: ImVisualTokens.accentText(context),
      fontWeight: FontWeight.w700,
      backgroundColor: ImVisualTokens.accent(context).withValues(alpha: 0.10),
    );
    var start = 0;
    while (start < text.length) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx < 0) {
        spans.add(TextSpan(text: text.substring(start), style: style));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: style));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + q.length),
          style: highlightStyle,
        ),
      );
      start = idx + q.length;
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// 统一空状态卡片（带柔光紫调图标胶囊）。
class ImEmptyState extends StatelessWidget {
  const ImEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final accent = ImVisualTokens.accent(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ImVisualTokens.accentSoftSurface(context),
                border: Border.all(
                  color: accent.withValues(alpha: 0.16),
                ),
              ),
              child: Icon(icon, size: 26, color: accent),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: DunesColors.resolve(context, DunesColors.text),
                context: context,
              ),
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 12.5,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  height: 1.45,
                  context: context,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 轻脉冲骨架占位条（用于搜索加载、媒体缩略图加载等）。
class ImShimmerRow extends StatefulWidget {
  const ImShimmerRow({super.key, this.count = 3});

  final int count;

  @override
  State<ImShimmerRow> createState() => _ImShimmerRowState();
}

class _ImShimmerRowState extends State<ImShimmerRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = ImVisualTokens.isDark(context);
    final baseColor = dark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFECE8F4);
    final hiColor = dark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFF6F3FC);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final fill = Color.lerp(baseColor, hiColor, _controller.value)!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.count, (index) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: fill,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: index.isEven ? 120 : 96,
                          height: 12,
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Container(
                          width: index.isEven ? 180 : 150,
                          height: 10,
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }
}
