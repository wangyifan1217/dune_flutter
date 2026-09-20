import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'task_api.dart';
import 'task_avatar.dart';
import 'task_models.dart';

class TaskAssignDraft {
  const TaskAssignDraft({required this.ownerUserId, this.comment = ''});

  final int ownerUserId;
  final String comment;
}

Future<TaskAssignDraft?> showTaskAssignDialog(
  BuildContext context, {
  required AuthSession session,
  required TaskItem task,
}) {
  return showDialog<TaskAssignDraft>(
    context: context,
    builder: (ctx) => _TaskAssignDialog(session: session, task: task),
  );
}

class _TaskAssignDialog extends StatefulWidget {
  const _TaskAssignDialog({required this.session, required this.task});

  final AuthSession session;
  final TaskItem task;

  @override
  State<_TaskAssignDialog> createState() => _TaskAssignDialogState();
}

class _TaskAssignDialogState extends State<_TaskAssignDialog> {
  late final TaskApi _api = TaskApi(widget.session);
  final _searchCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();
  List<TaskAssignee> _assignees = const [];
  bool _loading = true;
  TaskAssignee? _picked;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load([String? q]) async {
    setState(() => _loading = true);
    try {
      final list = await _api.listAssignees(q: q);
      if (!mounted) return;
      setState(() {
        _assignees = list
            .where((e) => e.id != widget.task.ownerUserId)
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _submit() {
    final picked = _picked;
    if (picked == null) {
      setState(() => _error = '请选择被指派人');
      return;
    }
    Navigator.pop(
      context,
      TaskAssignDraft(
        ownerUserId: picked.id,
        comment: _commentCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('指派任务'),
      content: SizedBox(
        width: 460,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '指派后由你的直属上级审批，通过后负责人变更为被指派人，原负责人转为协作人。',
              style: const TextStyle(
                fontSize: 13,
                color: DunesColors.text2,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchCtrl,
              onSubmitted: (v) => _load(v.trim()),
              decoration: InputDecoration(
                hintText: '搜索同事姓名',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  onPressed: () => _load(_searchCtrl.text.trim()),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                ),
                filled: true,
                fillColor: const Color(0xFFF5F6F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: DunesColors.brandPurple,
                        ),
                      )
                    : _assignees.isEmpty
                    ? const Center(
                        child: Text(
                          '没有可指派的同事',
                          style: TextStyle(color: DunesColors.text3),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _assignees.length,
                        itemBuilder: (_, i) {
                          final a = _assignees[i];
                          final selected = _picked?.id == a.id;
                          return ListTile(
                            selected: selected,
                            leading: buildTaskUserAvatar(
                              session: widget.session,
                              name: a.displayName,
                              userId: a.id,
                              avatarPreset: a.avatarPreset,
                              avatarObjectKey: a.avatarObjectKey,
                              avatarUrl: a.avatarUrl,
                              size: 36,
                            ),
                            title: Text(a.displayName),
                            subtitle: a.departmentName.isEmpty
                                ? null
                                : Text(a.departmentName),
                            trailing: selected
                                ? const Icon(
                                    Icons.check_circle,
                                    color: DunesColors.brandPurple,
                                  )
                                : null,
                            onTap: () => setState(() {
                              _picked = a;
                              _error = null;
                            }),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _commentCtrl,
              decoration: InputDecoration(
                hintText: '指派说明（可选）',
                filled: true,
                fillColor: const Color(0xFFF5F6F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
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
          key: const Key('task-assign-submit'),
          style: FilledButton.styleFrom(
            backgroundColor: DunesColors.brandPurple,
          ),
          onPressed: _submit,
          child: const Text('提交指派'),
        ),
      ],
    );
  }
}
