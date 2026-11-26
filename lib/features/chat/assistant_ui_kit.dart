import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_theme.dart';

/// IM 助手内容区居中画布：PC 端限制最大阅读宽度（默认 820），移动端紧凑全宽，
/// 避免大屏下卡片被横向拉成细长条。
class AssistantFeedFrame extends StatelessWidget {
  const AssistantFeedFrame({
    super.key,
    required this.child,
    this.maxWidth = 820,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF5F5F7),
        role: DunesColorRole.surface,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

/// IM 助手统一 Bento 空状态 / 错态卡片。
class AssistantEmptyCard extends StatelessWidget {
  const AssistantEmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent = DunesColors.brandPurple,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F1D2C) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.055),
              width: hairline,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? const Color(0x22000000)
                    : const Color(0x0A3D2C7A),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: isDark ? 0.24 : 0.15),
                      accent.withValues(alpha: isDark ? 0.10 : 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  icon,
                  size: 27,
                  color: DunesColors.resolve(context, accent),
                ),
              ),
              const SizedBox(height: 15),
              Text(
                title,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: DunesColors.resolve(context, DunesColors.text),
                  context: context,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: DunesTypography.sans(
                  fontSize: 12.5,
                  height: 1.5,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  context: context,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                _AssistantDockButton(
                  action: AssistantDockAction(
                    label: actionLabel!,
                    icon: Icons.refresh_rounded,
                    primary: true,
                    onTap: onAction!,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// IM 助手统一触感 Bento 通知卡片外壳（18px 圆角 + 0.5px 细描边 + 悬停微提亮 + 按压轻弹）。
class AssistantCardShell extends StatefulWidget {
  const AssistantCardShell({
    super.key,
    required this.child,
    this.onTap,
    this.accent = DunesColors.brandPurple,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.only(bottom: 10),
    this.radius = 18,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color accent;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;

  @override
  State<AssistantCardShell> createState() => _AssistantCardShellState();
}

class _AssistantCardShellState extends State<AssistantCardShell> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final interactive = widget.onTap != null;
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );

    final card = AnimatedSlide(
      offset: interactive && _hovered && !_pressed && !disableAnim
          ? const Offset(0, -0.015)
          : Offset.zero,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: AnimatedScale(
        scale: interactive && _pressed && !disableAnim ? 0.988 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: widget.margin,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F1D2C) : Colors.white,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: interactive && _hovered
                  ? widget.accent.withValues(alpha: isDark ? 0.42 : 0.32)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.055)),
              width: interactive && _hovered ? 0.9 : hairline,
            ),
            boxShadow: [
              BoxShadow(
                color: interactive && _hovered
                    ? widget.accent.withValues(alpha: isDark ? 0.16 : 0.10)
                    : (isDark
                          ? const Color(0x1C000000)
                          : const Color(0x083D2C7A)),
                blurRadius: interactive && _hovered ? 16 : 10,
                offset: Offset(0, interactive && _hovered ? 5 : 2.5),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );

    if (!interactive) return card;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (mounted) setState(() => _pressed = true);
        },
        onTapUp: (_) {
          if (mounted) setState(() => _pressed = false);
        },
        onTapCancel: () {
          if (mounted) setState(() => _pressed = false);
        },
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap?.call();
        },
        child: card,
      ),
    );
  }
}

/// 底部 Dock 单个操作配置。
class AssistantDockAction {
  const AssistantDockAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
    this.accent,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  final Color? accent;
}

/// IM 助手底部悬浮单行胶囊 Dock：
/// - PC 端居中悬浮圆角白底 Dock，单行排布、主次分明，彻底告别两行大色块；
/// - 移动端自动收紧为单行可横向轻滑胶囊条，释放更多消息阅读区。
class AssistantDockBar extends StatelessWidget {
  const AssistantDockBar({
    super.key,
    required this.actions,
    this.maxWidth = 820,
  });

  final List<AssistantDockAction> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final restingBottom = bottomInset > 14 ? bottomInset - 12.0 : bottomInset;
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );
    final isWide = MediaQuery.sizeOf(context).width >= 720;

    return ColoredBox(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF5F5F7),
        role: DunesColorRole.surface,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isWide ? 16 : 12,
              6,
              isWide ? 16 : 12,
              restingBottom > 0 ? restingBottom + 8 : 12,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1F1D2C) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.055),
                  width: hairline,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? const Color(0x28000000)
                        : const Color(0x0E3D2C7A),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      _AssistantDockButton(action: actions[i]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantDockButton extends StatefulWidget {
  const _AssistantDockButton({required this.action});

  final AssistantDockAction action;

  @override
  State<_AssistantDockButton> createState() => _AssistantDockButtonState();
}

class _AssistantDockButtonState extends State<_AssistantDockButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.action;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );
    final tone = a.accent ?? DunesColors.brandPurple;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (mounted) setState(() => _pressed = true);
        },
        onTapUp: (_) {
          if (mounted) setState(() => _pressed = false);
        },
        onTapCancel: () {
          if (mounted) setState(() => _pressed = false);
        },
        onTap: () {
          HapticFeedback.selectionClick();
          a.onTap();
        },
        child: AnimatedScale(
          scale: _pressed && !disableAnim ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: a.primary ? 14 : 12),
            decoration: BoxDecoration(
              gradient: a.primary
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _hovered
                          ? [
                              Color.lerp(tone, Colors.white, 0.14)!,
                              Color.lerp(tone, Colors.black, 0.08)!,
                            ]
                          : [
                              Color.lerp(tone, Colors.white, 0.08)!,
                              tone,
                            ],
                    )
                  : null,
              color: a.primary
                  ? null
                  : (_hovered
                        ? tone.withValues(alpha: isDark ? 0.22 : 0.13)
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : const Color(0xFFF4F2FA))),
              borderRadius: BorderRadius.circular(11),
              border: a.primary
                  ? null
                  : Border.all(
                      color: _hovered
                          ? tone.withValues(alpha: 0.34)
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.045)),
                      width: hairline,
                    ),
              boxShadow: a.primary
                  ? [
                      BoxShadow(
                        color: tone.withValues(alpha: _hovered ? 0.32 : 0.20),
                        blurRadius: _hovered ? 12 : 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  a.icon,
                  size: 15.5,
                  color: a.primary
                      ? Colors.white
                      : DunesColors.resolve(context, tone),
                ),
                const SizedBox(width: 6),
                Text(
                  a.label,
                  style: DunesTypography.sans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: a.primary
                        ? Colors.white
                        : DunesColors.resolve(context, DunesColors.text),
                    context: context,
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

/// 浏览历史消息时右下角悬浮的「回到最新」胶囊按钮。
class AssistantJumpLatestPill extends StatefulWidget {
  const AssistantJumpLatestPill({
    super.key,
    required this.onTap,
    this.label = '回到最新',
    this.accent = DunesColors.brandPurple,
  });

  final VoidCallback onTap;
  final String label;
  final Color accent;

  @override
  State<AssistantJumpLatestPill> createState() =>
      _AssistantJumpLatestPillState();
}

class _AssistantJumpLatestPillState extends State<AssistantJumpLatestPill> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (mounted) setState(() => _pressed = true);
        },
        onTapUp: (_) {
          if (mounted) setState(() => _pressed = false);
        },
        onTapCancel: () {
          if (mounted) setState(() => _pressed = false);
        },
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed && !disableAnim ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF28253A) : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _hovered
                    ? widget.accent.withValues(alpha: 0.45)
                    : widget.accent.withValues(alpha: isDark ? 0.28 : 0.20),
                width: hairline,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? const Color(0x40000000)
                      : const Color(0x183D2C7A),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_downward_rounded,
                  size: 14.5,
                  color: DunesColors.resolve(context, widget.accent),
                ),
                const SizedBox(width: 5),
                Text(
                  widget.label,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, widget.accent),
                    context: context,
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
