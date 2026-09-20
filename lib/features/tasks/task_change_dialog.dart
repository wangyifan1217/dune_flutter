import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'task_models.dart';

class TaskChangeDraft {
  const TaskChangeDraft({
    this.title,
    this.description,
    this.dueAt,
  });

  final String? title;
  final String? description;
  final DateTime? dueAt;

  bool get isEmpty => title == null && description == null && dueAt == null;
}

Future<TaskChangeDraft?> showTaskChangeDialog(
  BuildContext context, {
  required TaskItem task,
}) {
  return showDialog<TaskChangeDraft>(
    context: context,
    builder: (ctx) => _TaskChangeDialog(task: task),
  );
}

class _TaskChangeDialog extends StatefulWidget {
  const _TaskChangeDialog({required this.task});

  final TaskItem task;

  @override
  State<_TaskChangeDialog> createState() => _TaskChangeDialogState();
}

class _TaskChangeDialogState extends State<_TaskChangeDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  DateTime? _dueAt;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.task.title);
    _descCtrl = TextEditingController(
      text: taskDistinctDescription(widget.task),
    );
    _dueAt = widget.task.dueAt?.toLocal();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime? d) {
    if (d == null) return '请选择';
    return formatTaskYmd(d);
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final current = _dueAt ?? widget.task.dueAt?.toLocal() ?? now;
    final first = widget.task.startAt?.toLocal() ?? DateTime(now.year - 1);
    var last = DateTime(now.year + 5);
    if (first.isAfter(last)) last = first;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: last,
      helpText: '选择截止日',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: DunesColors.brandPurple),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _dueAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      _error = null;
    });
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请填写标题');
      return;
    }
    if (widget.task.startAt != null &&
        _dueAt != null &&
        DateTime(
          _dueAt!.year,
          _dueAt!.month,
          _dueAt!.day,
        ).isBefore(
          DateTime(
            widget.task.startAt!.year,
            widget.task.startAt!.month,
            widget.task.startAt!.day,
          ),
        )) {
      setState(() => _error = '结束时间不能早于开始时间');
      return;
    }
    String? nextTitle;
    if (title != widget.task.title.trim()) nextTitle = title;
    final desc = _descCtrl.text.trim();
    final currentDesc = taskDistinctDescription(widget.task).trim();
    String? nextDesc;
    if (desc != currentDesc) nextDesc = desc;
    DateTime? nextDue;
    final oldDue = widget.task.dueAt?.toLocal();
    if (_dueAt != null &&
        (oldDue == null ||
            _dueAt!.year != oldDue.year ||
            _dueAt!.month != oldDue.month ||
            _dueAt!.day != oldDue.day)) {
      nextDue = _dueAt;
    }
    final draft = TaskChangeDraft(
      title: nextTitle,
      description: nextDesc,
      dueAt: nextDue,
    );
    if (draft.isEmpty) {
      setState(() => _error = '没有需要提交的修改');
      return;
    }
    Navigator.pop(context, draft);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('修改任务'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '标题、内容和截止日提交后由直属上级审批，通过前页面仍显示原文。',
                style: TextStyle(
                  fontSize: 13,
                  color: DunesColors.text2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: '标题',
                  filled: true,
                  fillColor: const Color(0xFFF5F6F8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: '内容',
                  filled: true,
                  fillColor: const Color(0xFFF5F6F8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
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
                              '截止日',
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
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFE35D6A),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('task-change-submit'),
          style: FilledButton.styleFrom(
            backgroundColor: DunesColors.brandPurple,
          ),
          onPressed: _submit,
          child: const Text('提交审批'),
        ),
      ],
    );
  }
}
