import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'task_api.dart';
import 'task_models.dart';
import 'task_widgets.dart';

/// 工作台轻量新建：一条事项或一组事，不走完整任务表单。
Future<TaskItem?> openTaskQuickCreate(
  BuildContext context, {
  required AuthSession session,
  required bool asGroup,
}) {
  return showModalBottomSheet<TaskItem>(
    context: context,
    isScrollControlled: true,
    backgroundColor: DunesColors.bgApp,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _QuickCreateSheet(session: session, asGroup: asGroup),
    ),
  );
}

class _QuickCreateSheet extends StatefulWidget {
  const _QuickCreateSheet({required this.session, required this.asGroup});

  final AuthSession session;
  final bool asGroup;

  @override
  State<_QuickCreateSheet> createState() => _QuickCreateSheetState();
}

class _QuickCreateSheetState extends State<_QuickCreateSheet> {
  late final TaskApi _api = TaskApi(widget.session);
  final _title = TextEditingController();
  final _desc = TextEditingController();
  DateTime? _due;
  int? _groupId;
  List<TaskItem> _groups = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (!widget.asGroup) {
      unawaited(_loadGroups());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    try {
      final page = await _api.listTasksPage(
        scope: 'initiated',
        page: 0,
        size: 50,
      );
      if (!mounted) return;
      setState(() => _groups = page.items);
    } catch (_) {}
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() => _due = picked);
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showDunesCenterToast(context, '请填写名称');
      return;
    }
    setState(() => _saving = true);
    try {
      final desc = _desc.text.trim();
      final body = <String, dynamic>{
        'title': title,
        if (desc.isNotEmpty)
          'description': desc
        else if (widget.asGroup || _groupId == null)
          'description': title,
        if (!widget.asGroup && _due != null)
          'dueAt': DateTime(
            _due!.year,
            _due!.month,
            _due!.day,
            23,
            59,
          ).toUtc().toIso8601String(),
      };
      final TaskItem created;
      if (widget.asGroup || _groupId == null) {
        created = await _api.createMain(body);
      } else {
        created = await _api.createSubtask(_groupId!, {
          ...body,
          'ownerUserId': widget.session.userId,
        });
      }
      if (!mounted) return;
      Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showDunesCenterToast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dueLabel = _due == null
        ? '可选'
        : '${_due!.year}/${_due!.month}/${_due!.day}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: DunesColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.asGroup ? '新建一组事' : '新建事项',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              widget.asGroup
                  ? '给这组起个名，进去后再添加事项。'
                  : '给自己记一条要做的事，不必先建组。',
              style: const TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.asGroup ? '例如：产品周会跟进' : '例如：周五前给客户闭环方案',
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
              controller: _desc,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: widget.asGroup ? '这组事要达成什么（可选）' : '补充背景或做法（可选）',
                filled: true,
                fillColor: const Color(0xFFF5F6F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (!widget.asGroup) ...[
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('截止', style: TextStyle(fontSize: 13)),
                trailing: Text(
                  dueLabel,
                  style: const TextStyle(color: DunesColors.text2),
                ),
                onTap: _pickDue,
              ),
              if (_groups.isNotEmpty)
                DropdownButtonFormField<int?>(
                  initialValue: _groupId,
                  decoration: const InputDecoration(
                    labelText: '属于哪一组（可选）',
                    border: InputBorder.none,
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('不挂组，只给自己做'),
                    ),
                    for (final g in _groups)
                      DropdownMenuItem<int?>(value: g.id, child: Text(g.title)),
                  ],
                  onChanged: (v) => setState(() => _groupId = v),
                ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kTaskPurple),
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }
}
