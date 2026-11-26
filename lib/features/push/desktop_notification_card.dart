import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared by desktop message and actionable notifications on Windows/macOS.
class DesktopNotificationCard extends StatelessWidget {
  const DesktopNotificationCard({
    super.key,
    required this.title,
    required this.body,
    required this.leading,
    required this.onTap,
    required this.onClose,
    this.actionLabel = '查看消息',
    this.isError = false,
    this.onEnter,
    this.onExit,
  });

  final String title;
  final String body;
  final Widget leading;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final String actionLabel;
  final bool isError;
  final VoidCallback? onEnter;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? const Color(0xFFF2F3F5) : const Color(0xFF1D1B29);
    final secondary = dark ? const Color(0xFFA8A4BC) : const Color(0xFF6B6680);
    final accent = isError
        ? (dark ? const Color(0xFFFF7A80) : const Color(0xFFD64545))
        : (dark ? const Color(0xFFB69BFF) : const Color(0xFF7B5CD8));
    final radius = BorderRadius.circular(20);
    return MouseRegion(
      onEnter: (_) => onEnter?.call(),
      onExit: (_) => onExit?.call(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .36 : .12),
              blurRadius: 28,
              spreadRadius: -4,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: accent.withValues(alpha: dark ? .18 : .10),
              blurRadius: 18,
              spreadRadius: -6,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Material(
              color: (dark ? const Color(0xFF232132) : Colors.white).withValues(
                alpha: dark ? 0.88 : 0.92,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(
                  color: accent.withValues(alpha: dark ? 0.28 : 0.22),
                  width: 0.9,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                mouseCursor: SystemMouseCursors.click,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 2.5,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accent.withValues(alpha: 0.25),
                            accent,
                            accent.withValues(alpha: 0.25),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  isError ? '沙丘 · 需要关注' : '沙丘 · 新通知',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: secondary,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: '关闭通知',
                                onPressed: onClose,
                                constraints: const BoxConstraints.tightFor(
                                  width: 28,
                                  height: 28,
                                ),
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: secondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExcludeSemantics(child: leading),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.35,
                                        fontWeight: FontWeight.w600,
                                        color: foreground,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      body,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.5,
                                        color: secondary,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      actionLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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

/// Leave room for the desktop title bar, including macOS window controls.
class DesktopNotificationPosition extends StatelessWidget {
  const DesktopNotificationPosition({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
    top: MediaQuery.paddingOf(context).top + 64,
    left: 16,
    right: 20,
    bottom: 16 + MediaQuery.paddingOf(context).bottom,
    child: Align(
      alignment: Alignment.topRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(child: child),
      ),
    ),
  );
}
