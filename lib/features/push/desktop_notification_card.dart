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
    final foreground = dark ? const Color(0xFFF2F3F5) : const Color(0xFF20252C);
    final secondary = dark ? const Color(0xFFAAB1BD) : const Color(0xFF687280);
    final accent = isError
        ? (dark ? const Color(0xFFFF9393) : const Color(0xFFC43D3D))
        : (dark ? const Color(0xFF82B8FF) : const Color(0xFF176CE5));
    final radius = BorderRadius.circular(18);
    return MouseRegion(
      onEnter: (_) => onEnter?.call(),
      onExit: (_) => onExit?.call(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .28 : .10),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: dark ? const Color(0xFF252930) : const Color(0xFFFCFDFE),
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: dark ? const Color(0xFF414751) : const Color(0xFFE2E7EE),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            mouseCursor: SystemMouseCursors.click,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isError ? '沙丘 · 需要关注' : '沙丘 · 新通知',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: secondary),
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
