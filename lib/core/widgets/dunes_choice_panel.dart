import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/desktop_features.dart';
import 'package:dunes_app/core/theme/dunes_theme.dart';

class DunesChoiceItem {
  const DunesChoiceItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.color = const Color(0xFF7B5CD8),
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

/// PC 居中紧凑卡片 / APP 底部卡片，避免空荡的系统弹框。
Future<void> showDunesChoicePanel({
  required BuildContext context,
  required String title,
  required List<DunesChoiceItem> items,
}) async {
  if (items.isEmpty) return;
  if (items.length == 1) {
    items.first.onTap();
    return;
  }
  final enabled = items;

  Widget panel(BuildContext ctx, {required bool sheet}) {
    final radius = sheet
        ? const BorderRadius.vertical(top: Radius.circular(24))
        : BorderRadius.circular(24);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Material(
          color: DunesColors.resolve(
            ctx,
            Colors.white,
            role: DunesColorRole.surface,
          ).withValues(alpha: 0.92),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: DunesColors.resolve(
                ctx,
                const Color(0xFFE5E5EA),
                role: DunesColorRole.border,
              ),
              width: 0.8,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              sheet ? 10 : 18,
              16,
              sheet ? 22 : 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sheet) ...[
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: DunesColors.resolve(
                          ctx,
                          const Color(0xFFD1D1D6),
                          role: DunesColorRole.surface,
                        ),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: DunesColors.resolve(
                            ctx,
                            const Color(0xFF1D1D1F),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(ctx).pop();
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: DunesColors.resolve(
                          ctx,
                          const Color(0xFF8E8E93),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < enabled.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _ChoiceCard(
                    item: enabled[i],
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(ctx).pop();
                      enabled[i].onTap();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  HapticFeedback.selectionClick();
  if (isDesktopCommOnly) {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (ctx, animation, secondary, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, animation, secondary) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: panel(ctx, sheet: false),
            ),
          ),
        );
      },
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(top: false, child: panel(ctx, sheet: true)),
  );
}

class _ChoiceCard extends StatefulWidget {
  const _ChoiceCard({required this.item, required this.onTap});

  final DunesChoiceItem item;
  final VoidCallback onTap;

  @override
  State<_ChoiceCard> createState() => _ChoiceCardState();
}

class _ChoiceCardState extends State<_ChoiceCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOutCubic,
      child: Material(
        color: DunesColors.resolve(
          context,
          const Color(0xFFF5F5F7),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(item.color, Colors.white, 0.22)!,
                        item.color,
                        Color.lerp(item.color, Colors.black, 0.14)!,
                      ],
                      stops: const [0.0, 0.58, 1.0],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: item.color.withValues(alpha: 0.24),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(item.icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.resolve(
                            context,
                            const Color(0xFF1D1D1F),
                          ),
                        ),
                      ),
                      if (item.subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: DunesColors.resolve(
                              context,
                              const Color(0xFF6E6E73),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: DunesColors.resolve(context, const Color(0xFFC7C7CC)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
