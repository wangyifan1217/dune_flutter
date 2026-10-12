import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import 'task_models.dart';
import 'task_widgets.dart';

/// Loads the existing detail endpoint on demand, preserving its access scope.
class TaskSubtasksDialog extends StatefulWidget {
  const TaskSubtasksDialog({
    super.key,
    required this.task,
    required this.loadDetail,
    required this.onOpenTask,
  });

  final TaskItem task;
  final Future<TaskDetail> Function() loadDetail;
  final ValueChanged<int> onOpenTask;

  @override
  State<TaskSubtasksDialog> createState() => _TaskSubtasksDialogState();
}

class _TaskSubtasksDialogState extends State<TaskSubtasksDialog> {
  late Future<TaskDetail> _detail;

  @override
  void initState() {
    super.initState();
    _detail = Future.sync(widget.loadDetail);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 680,
        height: (size.height * .78).clamp(0.0, 620.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '子任务概览',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<TaskDetail>(
                future: _detail,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              friendlyErrorText(snapshot.error!),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () => setState(() {
                                _detail = Future.sync(widget.loadDetail);
                              }),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final tasks = snapshot.data!.subtasks;
                  if (tasks.isEmpty) {
                    return const Center(child: Text('暂无可查看的子任务'));
                  }
                  final completed = tasks
                      .where((t) => t.status == 'completed')
                      .length;
                  final overdue = tasks
                      .where((t) => t.overdue && t.status != 'completed')
                      .length;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Text(
                          '共 ${tasks.length} 项 · 已完成 $completed 项 · 逾期 $overdue 项',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: tasks.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) =>
                              _taskRow(context, tasks[index]),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskRow(BuildContext context, TaskItem task) {
    final color = taskProgressTone(
      task.progressPct,
      overdue: task.overdue,
      completed: task.status == 'completed',
    );
    return Material(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF7F6FC),
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.pop(context);
          widget.onOpenTask(task.id);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TaskMetaChip(
                    text: task.overdue && task.status != 'completed'
                        ? '已逾期'
                        : taskStatusLabel(task.status),
                    color: color,
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text(
                    '负责人：${task.ownerName.trim().isEmpty ? '未指定' : task.ownerName}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (task.dueAt != null)
                    Text(
                      '截止：${formatTaskYmd(task.dueAt!.toLocal())}',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TaskProgressBar(
                      progressPct: task.progressPct,
                      overdue: task.overdue,
                      completed: task.status == 'completed',
                      height: 5,
                      showLabel: false,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${task.progressPct}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
