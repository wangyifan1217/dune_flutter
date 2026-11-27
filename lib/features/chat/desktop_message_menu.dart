import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
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
  final dangerColor = DunesColors.resolve(context, DunesColors.coral);
  final surfaceColor = dark ? const Color(0xFF272536) : Colors.white;
  final borderColor = dark
      ? Colors.white.withValues(alpha: 0.12)
      : const Color(0xFFE5E5EA);

  Color toneFor(String id) => switch (id) {
    'recall' || 'delete' => dangerColor,
    'forward' || 'transcribe' => DunesColors.resolve(context, DunesColors.blue),
    'favorite' || 'star' || 'pin' || 'unpin' => DunesColors.resolve(
      context,
      DunesColors.amber,
    ),
    'save' || 'download' || 'redownload' => DunesColors.resolve(
      context,
      DunesColors.green,
    ),
    'multi_msg' ||
    'multi' ||
    'select' ||
    'save_to_kb' ||
    'save_to_drive' => DunesColors.resolve(context, DunesColors.accent),
    _ => accent,
  };

  return showMenu<String>(
    context: context,
    color: surfaceColor,
    elevation: 16,
    shadowColor: Colors.black.withValues(alpha: dark ? 0.45 : 0.14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: borderColor, width: 0.6),
    ),
    position: RelativeRect.fromRect(
      Rect.fromLTWH(point.dx, point.dy, 1, 1),
      Offset.zero & overlay.size,
    ),
    constraints: const BoxConstraints(minWidth: 214, maxWidth: 276),
    items: [
      for (final item in actions) ...[
        if (item.id == 'recall') const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: item.id,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: toneFor(item.id).withValues(alpha: dark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.icon,
                  size: 15,
                  color: toneFor(item.id),
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
                        ? dangerColor
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
