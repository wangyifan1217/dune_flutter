import 'package:flutter/material.dart';

import 'im_ui_kit.dart';

class DesktopMessageMenuItem {
  const DesktopMessageMenuItem({
    required this.id,
    required this.label,
    required this.icon,
  });
  final String id;
  final String label;
  final IconData icon;
}

Future<String?> showDesktopMessageMenu(
  BuildContext context,
  List<DesktopMessageMenuItem> actions, {
  Offset? anchor,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final point = anchor == null
      ? overlay.size.center(Offset.zero)
      : overlay.globalToLocal(anchor);
  final dark = ImVisualTokens.isDark(context);
  final accent = ImVisualTokens.accent(context);
  final surfaceColor = dark ? const Color(0xFF272536) : Colors.white;
  final borderColor = dark
      ? Colors.white.withValues(alpha: 0.12)
      : const Color(0x247B5CD8);

  return showMenu<String>(
    context: context,
    color: surfaceColor,
    elevation: 14,
    shadowColor: const Color(0xFF2D1E5F).withValues(alpha: dark ? 0.45 : 0.16),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: borderColor, width: 0.8),
    ),
    position: RelativeRect.fromRect(
      Rect.fromLTWH(point.dx, point.dy, 1, 1),
      Offset.zero & overlay.size,
    ),
    constraints: const BoxConstraints(minWidth: 206, maxWidth: 268),
    items: [
      for (final item in actions) ...[
        if (item.id == 'recall') const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: item.id,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: item.id == 'recall'
                      ? Theme.of(context).colorScheme.error.withValues(alpha: 0.10)
                      : accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(
                  item.icon,
                  size: 15,
                  color: item.id == 'recall'
                      ? Theme.of(context).colorScheme.error
                      : accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: item.id == 'recall'
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ],
  );
}
