import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'task_models.dart';

/// PC 主任务表。手机端继续用卡片。
class TaskGoalTable extends StatelessWidget {
  const TaskGoalTable({
    super.key,
    required this.tasks,
    required this.onOpen,
    required this.canComplete,
    required this.onComplete,
    required this.completeHint,
  });

  final List<TaskItem> tasks;
  final ValueChanged<TaskItem> onOpen;
  final bool Function(TaskItem task) canComplete;
  final ValueChanged<TaskItem> onComplete;
  final String? Function(TaskItem task) completeHint;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: const WidgetStatePropertyAll(Color(0xFFF7F5FB)),
        dataRowMinHeight: 52,
        dataRowMaxHeight: 64,
        columnSpacing: 28,
        columns: const [
          DataColumn(label: Text('主任务名称')),
          DataColumn(label: Text('子任务')),
          DataColumn(label: Text('当前状态')),
          DataColumn(label: Text('创建人')),
          DataColumn(label: Text('开始时间')),
          DataColumn(label: Text('结束时间')),
          DataColumn(label: Text('操作')),
        ],
        rows: [
          for (final task in tasks)
            DataRow(
              onSelectChanged: (_) => onOpen(task),
              cells: [
                DataCell(
                  SizedBox(
                    width: 220,
                    child: Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                DataCell(Text(taskSubtaskProgressLabel(task))),
                DataCell(Text(taskDisplayStatusLabel(task))),
                DataCell(Text(task.creatorName.isEmpty ? '—' : task.creatorName)),
                DataCell(Text(formatTaskYmd(task.startAt?.toLocal()))),
                DataCell(Text(formatTaskYmd(task.dueAt?.toLocal()))),
                DataCell(_completeCell(task)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _completeCell(TaskItem task) {
    if (task.status == 'completed') {
      return const Text('已完成', style: TextStyle(color: DunesColors.text3));
    }
    final hint = completeHint(task);
    if (!canComplete(task)) {
      return Text(
        hint ?? '—',
        style: const TextStyle(fontSize: 12, color: DunesColors.text3),
      );
    }
    return TextButton(
      onPressed: () => onComplete(task),
      child: const Text('标记完成'),
    );
  }
}
