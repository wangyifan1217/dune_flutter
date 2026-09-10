import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../tasks/task_api.dart';
import '../tasks/task_models.dart';

class MeetingTaskCreateDraft {
  const MeetingTaskCreateDraft({
    this.title,
    this.description,
    this.acceptanceCriteria,
    this.ownerUserId,
    this.priority = 'medium',
    required this.startAt,
    required this.dueAt,
  });

  final String? title;
  final String? description;
  final String? acceptanceCriteria;
  final int? ownerUserId;
  final String priority;
  final DateTime startAt;
  final DateTime dueAt;
}

String? meetingTaskRangeError(DateTime? startAt, DateTime? dueAt) {
  if (startAt == null || dueAt == null) {
    return '请选择开始时间和结束时间';
  }
  final start = DateTime(startAt.year, startAt.month, startAt.day);
  final due = DateTime(dueAt.year, dueAt.month, dueAt.day);
  if (due.isBefore(start)) return '结束时间不能早于开始时间';
  return null;
}

/// 纪要创建任务：填写负责人、优先级、验收和周期后再提交。
Future<MeetingTaskCreateDraft?> showMeetingTaskCreateDialog(
  BuildContext context, {
  required AuthSession session,
  required String title,
  String description = '',
  String acceptanceCriteria = '',
  int batchCount = 1,
}) {
  return showDialog<MeetingTaskCreateDraft>(
    context: context,
    builder: (ctx) => _MeetingTaskCreateDialog(
      session: session,
      title: title,
      description: description,
      acceptanceCriteria: acceptanceCriteria,
      batchCount: batchCount,
    ),
  );
}

class _MeetingTaskCreateDialog extends StatefulWidget {
  const _MeetingTaskCreateDialog({
    required this.session,
    required this.title,
    required this.description,
    required this.acceptanceCriteria,
    required this.batchCount,
  });

  final AuthSession session;
  final String title;
  final String description;
  final String acceptanceCriteria;
  final int batchCount;

  @override
  State<_MeetingTaskCreateDialog> createState() =>
      _MeetingTaskCreateDialogState();
}

class _MeetingTaskCreateDialogState extends State<_MeetingTaskCreateDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _acceptCtrl;
  late final TaskApi _api = TaskApi(widget.session);
  DateTime? _startAt;
  DateTime? _dueAt;
  String? _error;
  String _priority = 'medium';
  late int _ownerId;
  late String _ownerName;
  List<TaskAssignee> _assignees = const [];

  bool get _batch => widget.batchCount > 1;
  bool get _showCopy => !_batch;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.title);
    _descCtrl = TextEditingController(text: widget.description);
    _acceptCtrl = TextEditingController(text: widget.acceptanceCriteria);
    _ownerId = widget.session.userId;
    _ownerName = (widget.session.displayName ?? '').trim().isEmpty
        ? '我'
        : widget.session.displayName!.trim();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _acceptCtrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime? d) {
    if (d == null) return '请选择';
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  Future<void> _pickOwner() async {
    if (_assignees.isEmpty) {
      try {
        final list = await _api.listAssignees();
        if (!mounted) return;
        setState(() => _assignees = list);
      } catch (_) {}
    }
    final picked = await showModalBottomSheet<TaskAssignee>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final items = _assignees;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.5,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '选择负责人（自己或下级）',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const Center(
                          child: Text(
                            '暂可先创建给自己',
                            style: TextStyle(color: DunesColors.text3),
                          ),
                        )
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final a = items[i];
                            return ListTile(
                              title: Text(a.displayName),
                              subtitle: a.departmentName.isEmpty
                                  ? null
                                  : Text(a.departmentName),
                              onTap: () => Navigator.pop(ctx, a),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _ownerId = picked.id;
      _ownerName = picked.displayName;
    });
  }

  Future<void> _pick({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? (_startAt ?? now) : (_dueAt ?? _startAt ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: isStart ? '选择开始时间' : '选择结束时间',
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
      if (isStart) {
        _startAt = DateTime(picked.year, picked.month, picked.day);
      } else {
        _dueAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
      _error = meetingTaskRangeError(_startAt, _dueAt);
    });
  }

  void _submit() {
    final err = meetingTaskRangeError(_startAt, _dueAt);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (_showCopy && _titleCtrl.text.trim().isEmpty) {
      setState(() => _error = '请填写任务标题');
      return;
    }
    Navigator.pop(
      context,
      MeetingTaskCreateDraft(
        title: _showCopy ? _titleCtrl.text.trim() : null,
        description: _showCopy ? _descCtrl.text.trim() : null,
        acceptanceCriteria: _showCopy ? _acceptCtrl.text.trim() : null,
        ownerUserId: _ownerId,
        priority: _priority,
        startAt: _startAt!,
        dueAt: _dueAt!,
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF5F6F8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _tile({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool placeholder = false,
    IconData icon = Icons.expand_more,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DunesColors.text3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: placeholder ? DunesColors.text3 : DunesColors.text,
                    ),
                  ),
                ],
              ),
            ),
            Icon(icon, size: 16, color: DunesColors.text3),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heading = _batch ? '全部创建任务' : '创建任务';
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(heading),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _batch
                    ? '将创建 ${widget.batchCount} 个任务，共用负责人、优先级和周期。'
                    : '补全负责人、周期和验收标准，创建后会同步到负责人的任务列表。',
                style: const TextStyle(
                  fontSize: 13,
                  color: DunesColors.text2,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              if (_showCopy) ...[
                TextField(
                  controller: _titleCtrl,
                  decoration: _fieldDecoration('任务标题'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: _fieldDecoration('任务描述（背景 / 要做什么）'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _acceptCtrl,
                  maxLines: 3,
                  decoration: _fieldDecoration('验收标准（做到什么算完成）'),
                ),
                const SizedBox(height: 10),
              ],
              _tile(
                label: '负责人',
                value: _ownerName,
                onTap: _pickOwner,
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _priority,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'low', child: Text('优先级 低')),
                      DropdownMenuItem(value: 'medium', child: Text('优先级 中')),
                      DropdownMenuItem(value: 'high', child: Text('优先级 高')),
                      DropdownMenuItem(value: 'urgent', child: Text('优先级 紧急')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _priority = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _tile(
                label: '开始时间',
                value: _fmt(_startAt),
                onTap: () => _pick(isStart: true),
                placeholder: _startAt == null,
                icon: Icons.calendar_today_outlined,
              ),
              const SizedBox(height: 10),
              _tile(
                label: '结束时间',
                value: _fmt(_dueAt),
                onTap: () => _pick(isStart: false),
                placeholder: _dueAt == null,
                icon: Icons.calendar_today_outlined,
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
          style: FilledButton.styleFrom(
            backgroundColor: DunesColors.brandPurple,
          ),
          onPressed: _submit,
          child: Text(_batch ? '全部创建' : '确认创建'),
        ),
      ],
    );
  }
}
