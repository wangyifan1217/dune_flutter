import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../tasks/task_api.dart';
import '../tasks/task_avatar.dart';
import '../tasks/task_create_confirm.dart';
import '../tasks/task_first_use_guide.dart';
import '../tasks/task_models.dart';
import '../tasks/task_widgets.dart';

class MeetingTaskCreateDraft {
  const MeetingTaskCreateDraft({
    this.title,
    this.description,
    this.acceptanceCriteria,
    this.ownerUserId,
    this.priority = 'medium',
    required this.startAt,
    required this.dueAt,
    this.parentTaskId,
  });

  final String? title;
  final String? description;
  final String? acceptanceCriteria;
  final int? ownerUserId;
  final String priority;
  final DateTime startAt;
  final DateTime dueAt;
  final int? parentTaskId;
}

String? meetingTaskRangeError(DateTime? startAt, DateTime? dueAt) {
  return taskCreateRangeError(startAt, dueAt, required: true);
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
  List<TaskItem> _goals = const [];
  bool _linkExisting = false;
  int? _parentTaskId;
  bool _guideAutoStarted = false;

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
    _loadGoals();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showGuide();
    });
  }

  Future<void> _showGuide({bool force = false}) async {
    if (!force && _guideAutoStarted) return;
    if (!force) _guideAutoStarted = true;
    await showTaskFirstUseGuide(
      context,
      userId: widget.session.userId,
      page: TaskGuidePage.meetingCreate,
      force: force,
    );
  }

  Future<void> _loadGoals() async {
    try {
      final list = await _api.listTasks(scope: 'goals', size: 50);
      if (!mounted) return;
      setState(() => _goals = list.where((t) => t.isMain).toList());
    } catch (_) {}
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
    return formatTaskYmd(d);
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
      backgroundColor: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '选择负责人',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              '自己或有权限分配的下级',
                              style: TextStyle(
                                fontSize: 12,
                                color: DunesColors.resolve(
                                  ctx,
                                  DunesColors.text3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(
                            '暂可先创建给自己',
                            style: TextStyle(
                              color: DunesColors.resolve(
                                ctx,
                                DunesColors.text3,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final a = items[i];
                            return ListTile(
                              leading: buildTaskUserAvatar(
                                session: widget.session,
                                name: a.displayName,
                                userId: a.id,
                                avatarPreset: a.avatarPreset,
                                avatarObjectKey: a.avatarObjectKey,
                                avatarUrl: a.avatarUrl,
                                size: 40,
                              ),
                              title: Text(
                                a.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: a.departmentName.isEmpty
                                  ? null
                                  : Text(a.departmentName),
                              trailing: a.id == _ownerId
                                  ? Icon(
                                      Icons.check_circle,
                                      color: DunesColors.resolve(
                                        ctx,
                                        DunesColors.brandPurple,
                                      ),
                                    )
                                  : null,
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
      _error = meetingTaskRangeError(_startAt, _dueAt);
    });
  }

  Future<void> _submit() async {
    final err = meetingTaskRangeError(_startAt, _dueAt);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (_showCopy && _titleCtrl.text.trim().isEmpty) {
      setState(() => _error = '请填写任务标题');
      return;
    }
    if (_linkExisting && (_parentTaskId == null || _parentTaskId! <= 0)) {
      setState(() => _error = '请选择要关联的主目标');
      return;
    }
    if (!_linkExisting && _showCopy && _acceptCtrl.text.trim().isEmpty) {
      setState(() => _error = '新建主目标请填写验收标准');
      return;
    }
    final title = _showCopy ? _titleCtrl.text.trim() : widget.title;
    final ok = await confirmCreateTask(
      context,
      title: title,
      startAt: _startAt,
      dueAt: _dueAt,
      kind: _linkExisting ? '子目标' : '主目标',
      message: _batch
          ? '确认创建 ${widget.batchCount} 个${_linkExisting ? '子目标' : '主目标'}？它们将共用该周期。'
          : null,
    );
    if (!ok || !mounted) return;
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
        parentTaskId: _linkExisting ? _parentTaskId : null,
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: DunesColors.resolve(
        context,
        const Color(0xFFF5F6F8),
        role: DunesColorRole.surface,
      ),
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: DunesColors.resolve(
              context,
              const Color(0xFFE8E5EF),
              role: DunesColorRole.border,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: DunesColors.resolve(context, DunesColors.brandPurple),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: DunesColors.resolve(context, DunesColors.text3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: placeholder
                          ? DunesColors.resolve(context, DunesColors.text3)
                          : DunesColors.resolve(context, DunesColors.text),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label, {bool required = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: DunesColors.resolve(context, DunesColors.text),
          ),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          Text(
            '*',
            style: TextStyle(
              color: DunesColors.resolveNullable(context, Color(0xFFE35D6A)),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _ownerTile() {
    TaskAssignee? selected;
    for (final assignee in _assignees) {
      if (assignee.id == _ownerId) {
        selected = assignee;
        break;
      }
    }
    return InkWell(
      onTap: _pickOwner,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: DunesColors.resolve(
              context,
              const Color(0xFFE8E5EF),
              role: DunesColorRole.border,
            ),
          ),
        ),
        child: Row(
          children: [
            buildTaskUserAvatar(
              session: widget.session,
              name: _ownerName,
              userId: _ownerId,
              avatarPreset: selected?.avatarPreset ?? '',
              avatarObjectKey: selected?.avatarObjectKey ?? '',
              avatarUrl: selected?.avatarUrl ?? '',
              size: 38,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ownerName,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.resolve(context, DunesColors.text),
                    ),
                  ),
                  if (selected?.departmentName.isNotEmpty == true)
                    Text(
                      selected!.departmentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: DunesColors.resolve(context, DunesColors.text3),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.swap_horiz_rounded,
              color: DunesColors.resolve(context, DunesColors.brandPurple),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeCard({
    required bool selected,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final color = selected
        ? DunesColors.resolve(context, DunesColors.brandPurple)
        : DunesColors.resolve(context, DunesColors.text2);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? DunesColors.resolve(
                    context,
                    const Color(0xFFF2EDFF),
                    role: DunesColorRole.surface,
                  )
                : DunesColors.resolve(
                    context,
                    Colors.white,
                    role: DunesColorRole.surface,
                  ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? DunesColors.resolve(
                      context,
                      DunesColors.brandPurple,
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      const Color(0xFFE8E5EF),
                      role: DunesColorRole.border,
                    ),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: DunesColors.resolveNullable(context, color),
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? DunesColors.resolve(
                                context,
                                DunesColors.brandPurple,
                              )
                            : DunesColors.resolve(context, DunesColors.text),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.25,
                        color: DunesColors.resolve(context, DunesColors.text3),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle,
                  size: 17,
                  color: DunesColors.resolve(context, DunesColors.brandPurple),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final heading = _batch ? '全部创建任务' : '创建任务';
    final screen = MediaQuery.sizeOf(context);
    final width = math.min(600.0, screen.width - 28).toDouble();
    final height = math.min(760.0, screen.height * 0.88).toDouble();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          color: DunesColors.resolve(
            context,
            const Color(0xFFFCFBFE),
            role: DunesColorRole.surface,
          ),
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(24),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 17, 10, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      DunesColors.resolve(
                        context,
                        Color(0xFFF4EFFF),
                        role: DunesColorRole.surface,
                      ),
                      DunesColors.resolve(
                        context,
                        Color(0xFFFCFBFE),
                        role: DunesColorRole.surface,
                      ),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: DunesColors.resolve(
                        context,
                        Color(0xFFECE6F5),
                        role: DunesColorRole.border,
                      ),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: DunesColors.resolve(
                          context,
                          DunesColors.brandPurple,
                          role: DunesColorRole.surface,
                        ).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.event_note_rounded,
                        color: DunesColors.resolve(
                          context,
                          DunesColors.brandPurple,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            heading,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _batch
                                ? '来自会议纪要 · ${widget.batchCount} 项建议'
                                : '来自会议纪要的任务建议',
                            style: TextStyle(
                              fontSize: 12,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TaskGuideHelpButton(
                      onPressed: () => _showGuide(force: true),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close_rounded,
                        color: DunesColors.resolve(context, DunesColors.text3),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionLabel('任务归属'),
                      Row(
                        children: [
                          _modeCard(
                            selected: !_linkExisting,
                            title: '新建主目标',
                            subtitle: '独立创建一项主任务',
                            icon: Icons.add_task_rounded,
                            onTap: () => setState(() {
                              _linkExisting = false;
                              _parentTaskId = null;
                            }),
                          ),
                          const SizedBox(width: 10),
                          _modeCard(
                            selected: _linkExisting,
                            title: '关联已有主目标',
                            subtitle: '作为所选主目标的子任务',
                            icon: Icons.account_tree_outlined,
                            onTap: () => setState(() => _linkExisting = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: DunesColors.resolve(
                            context,
                            const Color(0xFFF3F0FA),
                            role: DunesColorRole.surface,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 17,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.brandPurple,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _linkExisting
                                    ? '会议建议会作为子任务挂到主目标下。'
                                    : '会议建议会创建为新的主目标。',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: DunesColors.resolve(
                                    context,
                                    DunesColors.text2,
                                  ),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_linkExisting) ...[
                        const SizedBox(height: 14),
                        _sectionLabel('选择主目标', required: true),
                        DropdownButtonFormField<int>(
                          initialValue: _parentTaskId,
                          isExpanded: true,
                          decoration: _fieldDecoration(
                            _goals.isEmpty ? '正在加载主目标…' : '选择要关联的主目标',
                          ),
                          items: [
                            for (final goal in _goals)
                              DropdownMenuItem(
                                value: goal.id,
                                child: Text(
                                  goal.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _parentTaskId = value),
                        ),
                      ],
                      if (_showCopy) ...[
                        const SizedBox(height: 18),
                        _sectionLabel('任务标题', required: true),
                        TextField(
                          controller: _titleCtrl,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDecoration('写一个清楚、可执行的标题'),
                        ),
                        const SizedBox(height: 16),
                        _sectionLabel('任务描述'),
                        TextField(
                          controller: _descCtrl,
                          minLines: 3,
                          maxLines: 5,
                          decoration: _fieldDecoration('补充背景和需要完成的工作'),
                        ),
                        const SizedBox(height: 16),
                        _sectionLabel('验收标准', required: !_linkExisting),
                        TextField(
                          controller: _acceptCtrl,
                          minLines: 2,
                          maxLines: 4,
                          decoration: _fieldDecoration('说明做到什么状态算完成'),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _sectionLabel('负责人', required: true),
                      _ownerTile(),
                      const SizedBox(height: 16),
                      _sectionLabel('优先级'),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: DunesColors.resolve(
                            context,
                            Colors.white,
                            role: DunesColorRole.surface,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: DunesColors.resolve(
                              context,
                              const Color(0xFFE8E5EF),
                              role: DunesColorRole.border,
                            ),
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _priority,
                            isExpanded: true,
                            icon: const Icon(Icons.expand_more_rounded),
                            items: const [
                              DropdownMenuItem(value: 'low', child: Text('低')),
                              DropdownMenuItem(
                                value: 'medium',
                                child: Text('中'),
                              ),
                              DropdownMenuItem(value: 'high', child: Text('高')),
                              DropdownMenuItem(
                                value: 'urgent',
                                child: Text('紧急'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null)
                                setState(() => _priority = value);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _sectionLabel('任务周期', required: true),
                      Row(
                        children: [
                          Expanded(
                            child: _tile(
                              label: '开始日期',
                              value: _fmt(_startAt),
                              onTap: () => _pick(isStart: true),
                              placeholder: _startAt == null,
                              icon: Icons.calendar_today_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _tile(
                              label: '截止日期',
                              value: _fmt(_dueAt),
                              onTap: () => _pick(isStart: false),
                              placeholder: _dueAt == null,
                              icon: Icons.event_available_outlined,
                            ),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: DunesColors.resolve(
                              context,
                              const Color(0xFFFFF1F2),
                              role: DunesColorRole.surface,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: 17,
                                color: DunesColors.resolveNullable(
                                  context,
                                  Color(0xFFE35D6A),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: DunesColors.resolveNullable(
                                      context,
                                      Color(0xFFE35D6A),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: DunesColors.resolve(
                        context,
                        Color(0xFFECE8F0),
                        role: DunesColorRole.border,
                      ),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          foregroundColor: DunesColors.resolve(
                            context,
                            DunesColors.text2,
                          ),
                          side: BorderSide(
                            color: DunesColors.resolve(
                              context,
                              Color(0xFFE2DFE8),
                              role: DunesColorRole.border,
                            ),
                          ),
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
                        onPressed: _submit,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: Text(
                          _batch ? '创建 ${widget.batchCount} 项' : '确认创建',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: DunesColors.resolve(
                            context,
                            DunesColors.brandPurple,
                            role: DunesColorRole.surface,
                          ),
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
}
