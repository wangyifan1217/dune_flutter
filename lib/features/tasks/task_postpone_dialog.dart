import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'task_models.dart';

class TaskPostponeDraft {
  const TaskPostponeDraft({required this.dueAt, this.reason = ''});

  final DateTime dueAt;
  final String reason;
}

Future<TaskPostponeDraft?> showTaskPostponeDialog(
  BuildContext context, {
  required TaskItem task,
}) {
  return showDialog<TaskPostponeDraft>(
    context: context,
    builder: (ctx) => _TaskPostponeDialog(task: task),
  );
}

class _TaskPostponeDialog extends StatefulWidget {
  const _TaskPostponeDialog({required this.task});

  final TaskItem task;

  @override
  State<_TaskPostponeDialog> createState() => _TaskPostponeDialogState();
}

class _TaskPostponeDialogState extends State<_TaskPostponeDialog> {
  final _reasonCtrl = TextEditingController();
  DateTime? _dueAt;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime? d) {
    if (d == null) return '请选择';
    final local = d.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$m-$day';
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final current = widget.task.dueAt?.toLocal();
    final initial = _dueAt ??
        (current == null
            ? now
            : DateTime(current.year, current.month, current.day).add(
                const Duration(days: 1),
              ));
    final first = current == null
        ? DateTime(now.year - 1)
        : DateTime(current.year, current.month, current.day).add(
            const Duration(days: 1),
          );
    var last = DateTime(now.year + 5);
    if (first.isAfter(last)) last = first;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: last,
      helpText: '选择新的截止日',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: DunesColors.brandPurple,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dueAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      _error = taskPostponeError(
        startAt: widget.task.startAt,
        currentDue: widget.task.dueAt,
        newDue: _dueAt,
      );
    });
  }

  void _submit() {
    final err = taskPostponeError(
      startAt: widget.task.startAt,
      currentDue: widget.task.dueAt,
      newDue: _dueAt,
    );
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(
      context,
      TaskPostponeDraft(dueAt: _dueAt!, reason: _reasonCtrl.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('延期任务'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.task.dueAt == null
                  ? '请选择新的截止日。'
                  : '当前截止 ${_fmt(widget.task.dueAt)}，新的截止日必须更晚。',
              style: const TextStyle(
                fontSize: 13,
                color: DunesColors.text2,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickDue,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '新的截止日',
                            style: TextStyle(
                              fontSize: 11,
                              color: DunesColors.text3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _fmt(_dueAt),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _dueAt == null
                                  ? DunesColors.text3
                                  : DunesColors.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: DunesColors.text3,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '延期原因（可选）',
                filled: true,
                fillColor: const Color(0xFFF5F6F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: Color(0xFFE35D6A)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: DunesColors.brandPurple,
          ),
          onPressed: _submit,
          child: const Text('确认延期'),
        ),
      ],
    );
  }
}
