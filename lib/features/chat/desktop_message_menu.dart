import 'package:flutter/material.dart';

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
  return showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(point.dx, point.dy, 1, 1),
      Offset.zero & overlay.size,
    ),
    constraints: const BoxConstraints(minWidth: 210, maxWidth: 280),
    items: [
      for (final item in actions) ...[
        if (item.id == 'recall') const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: item.id,
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 18,
                color: item.id == 'recall'
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
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
