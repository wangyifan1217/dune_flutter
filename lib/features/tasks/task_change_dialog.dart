import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../core/theme/dunes_theme.dart';
import 'task_models.dart';
import 'task_widgets.dart';

class TaskChangeDraft {
  const TaskChangeDraft({this.title, this.description, this.dueAt});

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
    final picked = await showTaskDatePicker(
      context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: last,
      helpText: '选择截止日',
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
        DateTime(_dueAt!.year, _dueAt!.month, _dueAt!.day).isBefore(
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
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(520.0, screen.width - 24).toDouble();
    final height = math.min(680.0, screen.height * 0.84).toDouble();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(24),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFF6F1FF), Color(0xFFFFFFFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border(bottom: BorderSide(color: Color(0xFFEDE8F7))),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B5CD8).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.edit_note_rounded,
                        color: Color(0xFF7B5CD8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '修改任务信息',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: DunesColors.text,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: DunesColors.text2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: DunesColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: Color(0xFF7B5CD8),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '提交后由任务流上级审批，通过前仍显示原信息。',
                        style: TextStyle(
                          fontSize: 12,
                          color: DunesColors.text2,
                          height: 1.35,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4DE),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '需审批',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF986514),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _fieldLabel('任务标题'),
                      TextField(
                        controller: _titleCtrl,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration('输入清晰、可执行的任务标题'),
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('任务内容'),
                      TextField(
                        controller: _descCtrl,
                        minLines: 4,
                        maxLines: 7,
                        decoration: _inputDecoration('补充背景、目标或交付要求'),
                      ),
                      const SizedBox(height: 16),
                      _fieldLabel('截止日期'),
                      InkWell(
                        onTap: _pickDue,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F7FA),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE8E7EE)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_month_outlined,
                                color: Color(0xFF7B5CD8),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _fmt(_dueAt),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _dueAt == null
                                        ? DunesColors.text3
                                        : DunesColors.text,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: DunesColors.text3,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
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
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFF0EEF4))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          foregroundColor: DunesColors.text2,
                          side: const BorderSide(color: Color(0xFFE3E1E8)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        key: const Key('task-change-submit'),
                        onPressed: _submit,
                        icon: const Icon(Icons.send_rounded, size: 17),
                        label: const Text('提交修改'),
                        style: FilledButton.styleFrom(
                          backgroundColor: DunesColors.brandPurple,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: DunesColors.text,
      ),
    ),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: DunesColors.text3),
    filled: true,
    fillColor: const Color(0xFFF7F7FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE8E7EE)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE8E7EE)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF7B5CD8), width: 1.4),
    ),
  );
}
