import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final purple = DunesColors.resolve(context, DunesColors.brandPurple);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE5E5EA),
            role: DunesColorRole.border,
          ),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(purple, Colors.white, 0.22)!,
                  purple,
                  Color.lerp(purple, Colors.black, 0.14)!,
                ],
                stops: const [0.0, 0.58, 1.0],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.fact_check_rounded,
              size: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              parts.first.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: DunesColors.resolve(context, const Color(0xFF1D1D1F)),
              ),
            ),
          ),
          if (parts.length > 1) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
              decoration: BoxDecoration(
                color: DunesColors.resolve(
                  context,
                  DunesColors.brandPurpleSoft,
                  role: DunesColorRole.surface,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '共 ${parts.last.trim()}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: purple,
                ),
              ),
            ),
          ],
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
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width >= 680;
    return Material(
      color: DunesColors.resolve(
        context,
        active ? DunesColors.brandPurpleSoft : Colors.white,
        role: DunesColorRole.surface,
      ),
      shape: StadiumBorder(
        side: BorderSide(
          color: DunesColors.resolve(
            context,
            active ? DunesColors.brandPurpleLine : const Color(0xFFE5E5EA),
            role: DunesColorRole.border,
          ),
          width: 0.8,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        hoverColor: Colors.transparent,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: compact ? 32 : 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: DunesColors.resolve(
                    context,
                    active
                        ? DunesColors.brandPurple
                        : const Color(0xFF6E6E73),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ApprovalListEmpty extends StatelessWidget {
  const ApprovalListEmpty({super.key, required this.filtered});
  final bool filtered;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: DunesColors.resolve(
              context,
              DunesColors.brandPurpleSoft,
              role: DunesColorRole.surface,
            ),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            filtered ? Icons.search_off_rounded : Icons.task_alt_rounded,
            size: 28,
            color: DunesColors.resolve(context, DunesColors.brandPurple),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          filtered ? '没有符合条件的审批' : '暂无审批记录',
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: DunesColors.resolve(context, const Color(0xFF1D1D1F)),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          filtered ? '试试其他状态、模板或关键词' : '新的审批记录将在这里展示',
          style: TextStyle(
            fontSize: 12,
            color: DunesColors.resolve(context, const Color(0xFF8E8E93)),
          ),
        ),
      ],
    ),
  );
}
