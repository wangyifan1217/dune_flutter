import 'package:flutter/material.dart';
import '../../core/theme/dunes_theme.dart';

/// Quiet, compact summary shared by the four approval lists.
class ApprovalListSummary extends StatelessWidget {
  const ApprovalListSummary({
    super.key,
    required this.kicker,
    required this.badgeText,
    required this.footItems,
    this.badgeUrge = false,
  });
  final String kicker, badgeText;
  final bool badgeUrge;
  final List<(String, String, String?)> footItems;

  @override
  Widget build(BuildContext context) {
    final parts = kicker.split('·');
    final accent = DunesColors.resolve(context, DunesColors.brandPurple);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            DunesColors.borderSoft,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    DunesColors.brandPurpleSoft,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.fact_check_outlined, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      parts.first.trim(),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.resolve(context, DunesColors.text),
                      ),
                    ),
                    if (parts.length > 1)
                      Text(
                        '共 ${parts.last.trim()}',
                        style: TextStyle(
                          fontSize: 11,
                          color: DunesColors.resolve(
                            context,
                            DunesColors.text3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: DunesColors.resolve(
                    context,
                    badgeUrge
                        ? DunesColors.brandPurpleSoft
                        : DunesColors.bgSoft,
                    role: DunesColorRole.surface,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: badgeUrge
                        ? accent
                        : DunesColors.resolve(context, DunesColors.text2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < footItems.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 28,
                    color: DunesColors.resolve(
                      context,
                      DunesColors.borderSoft,
                      role: DunesColorRole.border,
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        footItems[i].$2,
                        style: TextStyle(
                          fontSize: 20,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          color: footItems[i].$3 == 'urge'
                              ? accent
                              : DunesColors.resolve(context, DunesColors.text),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        footItems[i].$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: DunesColors.resolve(
                            context,
                            DunesColors.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class ApprovalListFilterChip extends StatelessWidget {
  const ApprovalListFilterChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.showDot = false,
  });
  final String label;
  final bool active, showDot;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: DunesColors.resolve(
      context,
      active ? DunesColors.brandPurpleSoft : Colors.white,
      role: DunesColorRole.surface,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(
        color: DunesColors.resolve(
          context,
          active ? DunesColors.brandPurpleLine : DunesColors.borderSoft,
          role: DunesColorRole.border,
        ),
      ),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: DunesColors.resolve(
              context,
              active ? DunesColors.brandPurpleDeep : DunesColors.text2,
            ),
          ),
        ),
      ),
    ),
  );
}

class ApprovalListEmpty extends StatelessWidget {
  const ApprovalListEmpty({super.key, required this.filtered});
  final bool filtered;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      children: [
        Icon(
          filtered ? Icons.search_off_rounded : Icons.task_alt_rounded,
          size: 36,
          color: DunesColors.resolve(context, DunesColors.brandPurpleLine),
        ),
        const SizedBox(height: 10),
        Text(
          filtered ? '没有符合条件的审批' : '暂无审批记录',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DunesColors.resolve(context, DunesColors.text2),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          filtered ? '试试其他状态、模板或关键词' : '新的审批记录将在这里展示',
          style: TextStyle(
            fontSize: 11,
            color: DunesColors.resolve(context, DunesColors.text3),
          ),
        ),
      ],
    ),
  );
}
