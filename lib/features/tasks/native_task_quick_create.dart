import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'task_api.dart';
import 'task_create_confirm.dart';
import 'task_first_use_guide.dart';
import 'task_models.dart';
import 'task_widgets.dart';

/// 快速创建界面只收名称和周期。当前创建接口仍校验验收标准，
/// 缺了会在服务端变成 internal error。这里用文案里约定的默认值补齐。
Map<String, dynamic> buildTaskQuickCreateBody({
  required String title,
  required String description,
  required DateTime startAt,
  required DateTime dueAt,
  required int ownerUserId,
  required bool asMain,
  int? groupId,
}) {
  final name = title.trim();
  final desc = description.trim();
  final standard = desc.isNotEmpty ? desc : name;
  return <String, dynamic>{
    'title': name,
    if (desc.isNotEmpty)
      'description': desc
    else if (asMain || groupId == null)
      'description': name,
    'acceptanceCriteria': standard,
    'priority': 'medium',
    'category': '业务 · 销售',
    'ownerUserId': ownerUserId,
    'startAt': startAt.toUtc().toIso8601String(),
    'dueAt': dueAt.toUtc().toIso8601String(),
  };
}

/// 工作台轻量新建：一个主目标或一个子目标，不走完整目标表单。
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
  DateTime? _startAt;
  DateTime? _dueAt;
  int? _groupId;
  List<TaskItem> _groups = const [];
  bool _saving = false;
  bool _guideAutoStarted = false;
  String? _dateError;

  @override
  void initState() {
    super.initState();
    if (!widget.asGroup) {
      unawaited(_loadGroups());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showGuide());
    });
  }

  Future<void> _showGuide({bool force = false}) async {
    if (!force && _guideAutoStarted) return;
    if (!force) _guideAutoStarted = true;
    await showTaskFirstUseGuide(
      context,
      userId: widget.session.userId,
      page: widget.asGroup
          ? TaskGuidePage.quickCreateMain
          : TaskGuidePage.quickCreateSub,
      force: force,
    );
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

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? (_startAt ?? now) : (_dueAt ?? _startAt ?? now);
    final picked = await showTaskDatePicker(
      context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: isStart ? '选择开始时间' : '选择结束时间',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startAt = DateTime(picked.year, picked.month, picked.day);
      } else {
        _dueAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
      _dateError = taskCreateRangeError(_startAt, _dueAt, required: false);
    });
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      showDunesCenterToast(context, '请填写名称');
      return;
    }
    final dateErr = taskCreateRangeError(_startAt, _dueAt);
    if (dateErr != null) {
      setState(() => _dateError = dateErr);
      return;
    }
    final kind = widget.asGroup ? '主目标' : '子目标';
    final ok = await confirmCreateTask(
      context,
      title: title,
      startAt: _startAt,
      dueAt: _dueAt,
      kind: kind,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      final body = buildTaskQuickCreateBody(
        title: title,
        description: _desc.text,
        startAt: _startAt!,
        dueAt: _dueAt!,
        ownerUserId: widget.session.userId,
        asMain: widget.asGroup,
        groupId: _groupId,
      );
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

  String _dateValue(DateTime? d) => d == null ? '请选择' : formatTaskYmd(d);

  @override
  Widget build(BuildContext context) {
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.asGroup ? '新建主目标' : '新建子目标',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TaskGuideHelpButton(
                  onPressed: () => unawaited(_showGuide(force: true)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.asGroup
                  ? '只需名称和周期。负责人就是创建人，分类默认「业务 · 销售」，保存后可以再完善。'
                  : '给自己记一条要做的子目标。',
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
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text.rich(
                TextSpan(
                  text: '开始时间',
                  style: TextStyle(fontSize: 13),
                  children: [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE35D6A),
                      ),
                    ),
                  ],
                ),
              ),
              trailing: Text(
                _dateValue(_startAt),
                style: TextStyle(
                  color: _startAt == null
                      ? DunesColors.text3
                      : DunesColors.text2,
                ),
              ),
              onTap: () => _pickDate(isStart: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text.rich(
                TextSpan(
                  text: '结束时间',
                  style: TextStyle(fontSize: 13),
                  children: [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFE35D6A),
                      ),
                    ),
                  ],
                ),
              ),
              trailing: Text(
                _dateValue(_dueAt),
                style: TextStyle(
                  color: _dueAt == null ? DunesColors.text3 : DunesColors.text2,
                ),
              ),
              onTap: () => _pickDate(isStart: false),
            ),
            if (_dateError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  _dateError!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFE35D6A),
                  ),
                ),
              ),
            if (!widget.asGroup && _groups.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '属于哪一组（可选）',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.text2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TaskDropdownField<int?>(
                    value: _groupId,
                    sheetTitle: '选择所属主目标',
                    items: [
                      (null, '不挂组，只给自己做'),
                      for (final g in _groups) (g.id, g.title),
                    ],
                    onChanged: (v) => setState(() => _groupId = v),
                  ),
                ],
              ),
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
