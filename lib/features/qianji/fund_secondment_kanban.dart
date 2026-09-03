import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'fund_secondment_models.dart';

const _themePurple = Color(0xFF7B5CD8);
const _cardBorder = Color(0xFFE8EAED);

/// 资金借调列表上方的老板看板：先看还剩多少钱，再看谁欠谁。
class FundSecondmentKanban extends StatelessWidget {
  const FundSecondmentKanban({
    super.key,
    required this.summary,
    this.filterAll = false,
    this.filterSettled = false,
    this.filterOpen = false,
    this.onFilterAll,
    this.onFilterSettled,
    this.onFilterOpen,
  });

  final FundSecondmentSummary summary;
  final bool filterAll;
  final bool filterSettled;
  final bool filterOpen;
  final VoidCallback? onFilterAll;
  final VoidCallback? onFilterSettled;
  final VoidCallback? onFilterOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Container(
        key: const Key('fund-secondment-kanban'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _cardBorder),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 560;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHero(),
                const SizedBox(height: 10),
                _RepayProgressBar(ratio: summary.repaidRatio),
                const SizedBox(height: 10),
                _buildStatChips(),
                if (summary.overdueCount > 0) ...[
                  const SizedBox(height: 8),
                  _AlertStrip(
                    color: DunesColors.coral,
                    bg: DunesColors.coralSoft,
                    text:
                        '有 ${summary.overdueCount} 笔已过预计还款日，还剩 ${formatFundSecondmentWan(summary.overdueRemainingWan)}',
                  ),
                ] else if (summary.dueSoonCount > 0) ...[
                  const SizedBox(height: 8),
                  _AlertStrip(
                    color: DunesColors.amber,
                    bg: DunesColors.amberSoft,
                    text:
                        '7 天内到期 ${summary.dueSoonCount} 笔，共 ${formatFundSecondmentWan(summary.dueSoonRemainingWan)}',
                  ),
                ],
                if (summary.remainingTotalWan > 0 &&
                    (summary.routes.isNotEmpty || summary.lenders.isNotEmpty)) ...[
                  const SizedBox(height: 12),
                  _buildBreakdown(wide),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHero() {
    final remaining = summary.remainingTotalWan;
    final allClear = summary.count > 0 && remaining <= 0;
    final title = allClear ? '目前没有未收回的钱' : '待收回';
    final subtitle = allClear
        ? '一共借出 ${formatFundSecondmentWan(summary.borrowTotalWan)}，已经全部收回'
        : summary.count == 0
            ? '还没有审批通过的借调'
            : '借出去还没还回来 · 一共 ${formatFundSecondmentWan(summary.borrowTotalWan)}，已收回 ${formatFundSecondmentWan(summary.repaidTotalWan)}';
    final amountColor = allClear
        ? DunesColors.green
        : remaining > 0
            ? DunesColors.coral
            : DunesColors.text3;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: DunesColors.text3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          formatFundSecondmentWan(remaining),
          style: TextStyle(
            fontSize: 28,
            height: 1.05,
            fontWeight: FontWeight.w800,
            color: amountColor,
          ),
        ),
      ],
    );
  }

  Widget _buildStatChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _KanbanChip(
          label: '未还清 ${summary.unsettledCount} 笔',
          selected: filterOpen,
          color: DunesColors.coral,
          onTap: onFilterOpen,
        ),
        _KanbanChip(
          label: '已还清 ${summary.settledCount} 笔',
          selected: filterSettled,
          color: DunesColors.green,
          onTap: onFilterSettled,
        ),
        _KanbanChip(
          label: '共 ${summary.count} 笔',
          selected: filterAll,
          color: _themePurple,
          onTap: onFilterAll,
        ),
      ],
    );
  }

  Widget _buildBreakdown(bool wide) {
    final routes = _BreakdownColumn(
      title: '谁欠谁',
      hint: '借款主体还欠付款主体',
      children: summary.routes
          .map(
            (route) => _BreakdownRow(
              from: route.borrowSubject,
              relation: '欠',
              to: route.paySubject,
              value: formatFundSecondmentWan(route.remainingWan),
            ),
          )
          .toList(growable: false),
    );
    if (summary.lenders.isEmpty) return routes;
    final lenders = _BreakdownColumn(
      title: '谁还在垫钱',
      hint: '付款主体未收回余额',
      children: summary.lenders
          .map(
            (item) => _BreakdownRow(
              label: item.subject,
              value: formatFundSecondmentWan(item.remainingWan),
            ),
          )
          .toList(growable: false),
    );
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          routes,
          const SizedBox(height: 12),
          lenders,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: routes),
        const SizedBox(width: 16),
        Expanded(flex: 2, child: lenders),
      ],
    );
  }
}

class _RepayProgressBar extends StatelessWidget {
  const _RepayProgressBar({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final repaidFlex = (ratio * 1000).round().clamp(0, 1000);
    final remainFlex = 1000 - repaidFlex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (repaidFlex > 0)
                  Flexible(
                    flex: repaidFlex,
                    child: const ColoredBox(color: DunesColors.green),
                  ),
                if (remainFlex > 0)
                  Flexible(
                    flex: remainFlex,
                    child: const ColoredBox(color: Color(0xFFF3D6CE)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '已收回 ${(ratio * 100).round()}%',
          style: const TextStyle(fontSize: 11, color: DunesColors.text3),
        ),
      ],
    );
  }
}

class _AlertStrip extends StatelessWidget {
  const _AlertStrip({
    required this.color,
    required this.bg,
    required this.text,
  });

  final Color color;
  final Color bg;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _KanbanChip extends StatelessWidget {
  const _KanbanChip({
    required this.label,
    required this.selected,
    required this.color,
    this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? color : DunesColors.text2;
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : const Color(0xFFF7F7F8),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _BreakdownColumn extends StatelessWidget {
  const _BreakdownColumn({
    required this.title,
    required this.hint,
    required this.children,
  });

  final String title;
  final String hint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: DunesColors.text,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hint,
          style: const TextStyle(fontSize: 11, color: DunesColors.text3),
        ),
        const SizedBox(height: 6),
        ...children,
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    this.label,
    this.from,
    this.relation,
    this.to,
    required this.value,
  });

  final String? label;
  final String? from;
  final String? relation;
  final String? to;
  final String value;

  static const _nameStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: DunesColors.text,
  );

  @override
  Widget build(BuildContext context) {
    final left = (from != null && to != null)
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(text: from),
                TextSpan(
                  text: '  ${relation ?? '欠'}  ',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.coral,
                  ),
                ),
                TextSpan(text: to),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _nameStyle,
          )
        : Text(
            label ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _nameStyle,
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: DunesColors.coral,
            ),
          ),
        ],
      ),
    );
  }
}
