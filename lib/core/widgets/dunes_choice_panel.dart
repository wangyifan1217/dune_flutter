import 'package:flutter/material.dart';

import '../platform/desktop_features.dart';

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
    return Material(
      color: Colors.white,
      borderRadius: sheet
          ? const BorderRadius.vertical(top: Radius.circular(20))
          : BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, sheet ? 12 : 16, 16, sheet ? 20 : 16),
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
                    color: const Color(0xFFE8E0F0),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2C1E3F),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Color(0xFF8A7A9E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < enabled.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _ChoiceCard(
                item: enabled[i],
                onTap: () {
                  Navigator.of(ctx).pop();
                  enabled[i].onTap();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  if (isDesktopCommOnly) {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: Colors.black.withValues(alpha: 0.28),
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
    builder: (ctx) => SafeArea(
      top: false,
      child: panel(ctx, sheet: true),
    ),
  );
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({required this.item, required this.onTap});

  final DunesChoiceItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF8F5FC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, color: item.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2C1E3F),
                      ),
                    ),
                    if (item.subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF817589),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFB5A9C4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
