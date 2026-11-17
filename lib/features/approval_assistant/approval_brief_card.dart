import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';

class ApprovalBriefCard extends StatefulWidget {
  const ApprovalBriefCard({
    super.key,
    required this.payload,
    required this.fallback,
    required this.onOpenAll,
  });

  final Map<String, dynamic> payload;
  final String fallback;
  final VoidCallback onOpenAll;

  @override
  State<ApprovalBriefCard> createState() => _ApprovalBriefCardState();
}

class _ApprovalBriefCardState extends State<ApprovalBriefCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final payload = widget.payload;
    final pending = (payload['pendingCount'] as num?)?.toInt() ?? 0;
    final overdue24 = (payload['overdue24hCount'] as num?)?.toInt() ?? 0;
    final overdueWeek = (payload['overdue1wCount'] as num?)?.toInt() ?? 0;
    final initiated = (payload['initiatedCount'] as num?)?.toInt() ?? 0;
    final pendingTypes = _typeCountRows(payload['pendingTypeCounts']);
    final initiatedTypes = _typeCountRows(payload['initiatedTypeCounts']);
    final hasItems = pending > 0 || initiated > 0;
    final purple = DunesColors.resolve(context, DunesColors.brandPurpleDeep);
    final muted = DunesColors.resolve(context, DunesColors.text2);

    return Container(
      width: 320,
      constraints: const BoxConstraints(maxWidth: 320),
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
            DunesColors.borderSoft,
            role: DunesColorRole.border,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C3A2A6A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: DunesColors.resolve(
                      context,
                      DunesColors.brandPurpleSoft,
                      role: DunesColorRole.surface,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.fact_check_outlined,
                    color: purple,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '今日审批简报',
                    style: DunesTypography.sans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.resolve(context, DunesColors.text),
                      context: context,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!hasItems)
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 3, 15, 14),
              child: Text(
                widget.fallback.isEmpty ? '暂无待审' : widget.fallback,
                style: DunesTypography.sans(
                  fontSize: 12,
                  height: 1.45,
                  color: muted,
                  context: context,
                ),
              ),
            )
          else ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 15),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: DunesColors.resolve(
                  context,
                  DunesColors.brandPurpleSoft,
                  role: DunesColorRole.surface,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pending > 0 || initiated <= 0)
                    Expanded(
                      child: _BriefMetric(label: '待我审批', value: pending),
                    ),
                  if (pending > 0 && initiated > 0) ...[
                    Container(
                      width: 1,
                      height: 39,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      color: DunesColors.resolve(
                        context,
                        DunesColors.brandPurpleLine,
                        role: DunesColorRole.border,
                      ).withValues(alpha: .55),
                    ),
                    Expanded(
                      child: _BriefMetric(label: '我发起进行中', value: initiated),
                    ),
                  ] else if (initiated > 0)
                    Expanded(
                      child: _BriefMetric(label: '我发起进行中', value: initiated),
                    ),
                ],
              ),
            ),
            if (overdue24 > 0 || overdueWeek > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(17, 10, 17, 0),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (overdue24 > 0)
                      _OverdueCount(label: '超24小时', count: overdue24),
                    if (overdueWeek > 0)
                      _OverdueCount(label: '超1周', count: overdueWeek),
                  ],
                ),
              ),
            if (_expanded && pendingTypes.isNotEmpty)
              _BriefTypeBlock(title: '待我审批', rows: pendingTypes),
            if (_expanded && initiatedTypes.isNotEmpty)
              _BriefTypeBlock(title: '我发起进行中', rows: initiatedTypes),
            if (pendingTypes.isNotEmpty || initiatedTypes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 4, 7, 0),
                child: TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                  label: Text(_expanded ? '收起明细' : '展开明细'),
                  style: TextButton.styleFrom(
                    foregroundColor: purple,
                    minimumSize: const Size(0, 44),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              )
            else
              const SizedBox(height: 12),
          ],
          Divider(
            height: 1,
            color: DunesColors.resolve(
              context,
              DunesColors.borderSoft,
              role: DunesColorRole.border,
            ),
          ),
          TextButton(
            onPressed: widget.onOpenAll,
            style: TextButton.styleFrom(
              foregroundColor: purple,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              minimumSize: const Size(0, 44),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '查看列表',
                  style: DunesTypography.sans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: purple,
                    context: context,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: purple),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<(String, int)> _typeCountRows(dynamic raw) {
    if (raw is! List) return const [];
    final out = <(String, int)>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final type = (item['type'] ?? item['name'] ?? '').toString().trim();
      final count = (item['count'] as num?)?.toInt() ?? 0;
      if (type.isEmpty || count <= 0) continue;
      out.add((type, count));
    }
    return out;
  }
}

class _BriefMetric extends StatelessWidget {
  const _BriefMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: DunesTypography.sans(
            fontSize: 11,
            color: DunesColors.resolve(context, DunesColors.text2),
            context: context,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$value',
          style: DunesTypography.sans(
            fontSize: 23,
            height: 1.1,
            fontWeight: FontWeight.w700,
            color: DunesColors.resolve(context, DunesColors.brandPurpleDeep),
            context: context,
          ),
        ),
      ],
    );
  }
}

class _OverdueCount extends StatelessWidget {
  const _OverdueCount({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label $count',
      style: DunesTypography.sans(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: DunesColors.resolve(context, DunesColors.amber),
        context: context,
      ),
    );
  }
}

class _BriefTypeBlock extends StatelessWidget {
  const _BriefTypeBlock({required this.title, required this.rows});

  final String title;
  final List<(String, int)> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: DunesTypography.sans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(context, DunesColors.text3),
              context: context,
            ),
          ),
          const SizedBox(height: 5),
          for (final (name, count) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: DunesTypography.sans(
                        fontSize: 12,
                        height: 1.35,
                        color: DunesColors.resolve(context, DunesColors.text),
                        context: context,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$count',
                    style: DunesTypography.sans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.resolve(
                        context,
                        DunesColors.brandPurpleDeep,
                      ),
                      context: context,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
