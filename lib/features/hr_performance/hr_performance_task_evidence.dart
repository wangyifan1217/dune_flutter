import 'package:flutter/material.dart';
import '../../core/theme/dunes_theme.dart';

/// Only displays facts present in the assessment evidence snapshot.
class HrTaskEvidenceContent extends StatelessWidget {
  const HrTaskEvidenceContent({
    super.key,
    required this.task,
    this.ownerName = '',
    this.indicatorNames = const [],
    this.missing = false,
  });
  final Map<String, dynamic> task;
  final String ownerName;
  final List<String> indicatorNames;
  final bool missing;

  String text(dynamic value) => '${value ?? ''}'.trim();
  DateTime? date(dynamic value) => DateTime.tryParse(text(value));
  String time(dynamic value) {
    final parsed = date(value);
    if (parsed == null) return '未记录';
    final local = parsed.toUtc().add(const Duration(hours: 8));
    String pad(int n) => '$n'.padLeft(2, '0');
    return '${local.year}-${pad(local.month)}-${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final muted = DunesColors.resolve(context, DunesColors.text3);
    final purple = DunesColors.resolve(context, DunesColors.brandPurpleDeep);
    final status = text(task['status']);
    final completed = date(task['completedAt']);
    final due = date(task['dueAt']);
    final state = missing
        ? '原任务已不存在'
        : const {
                'completed': '已完成',
                'active': '进行中',
                'pending': '待处理',
                'cancelled': '已取消',
                'archived': '已归档',
              }[status] ??
              (status.isEmpty ? (completed == null ? '状态未记录' : '已完成') : status);
    final fields = <String>[
      '#${task['id'] ?? '—'}',
      if (text(task['ownerName']).isNotEmpty || ownerName.isNotEmpty)
        '负责人 ${text(task['ownerName']).isEmpty ? ownerName : task['ownerName']}',
      if (text(task['priority']).isNotEmpty)
        '优先级 ${const {'urgent': '紧急', 'high': '高', 'medium': '中', 'low': '低'}[text(task['priority'])] ?? task['priority']}',
      if (text(task['category']).isNotEmpty) '分类 ${task['category']}',
      '截止 ${time(task['dueAt'])}',
      '完成 ${time(task['completedAt'])}',
      if (due != null && completed != null)
        completed.isAfter(due) ? '逾期完成' : '按期完成',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                text(task['title']).isEmpty ? '未命名任务' : text(task['title']),
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              state,
              style: TextStyle(fontSize: 12, color: missing ? muted : purple),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final field in fields)
              Text(
                field,
                style: TextStyle(fontSize: 12, height: 1.4, color: muted),
              ),
          ],
        ),
        if (indicatorNames.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              '关联指标：${indicatorNames.join('、')}',
              style: TextStyle(fontSize: 12, height: 1.4, color: purple),
            ),
          ),
        if (text(task['description']).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              text(task['description']),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.4, color: muted),
            ),
          ),
      ],
    );
  }
}
