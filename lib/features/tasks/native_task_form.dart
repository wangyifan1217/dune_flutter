import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'task_api.dart';
import 'task_attachment_field.dart';
import 'task_avatar.dart';
import 'task_models.dart';
import 'task_widgets.dart';

const _themePurple = Color(0xFF7B5CD8);

/// PC 弹窗；APP / 窄屏全屏页。
Future<TaskItem?> openTaskEditor(
  BuildContext context, {
  required AuthSession session,
  int? parentTaskId,
  TaskItem? parentTask,
}) {
  final useFullScreen = !isDesktopCommOnly;
  if (useFullScreen) {
    return Navigator.of(context).push<TaskItem>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TaskEditorPage(
          session: session,
          parentTaskId: parentTaskId,
          parentTask: parentTask,
        ),
      ),
    );
  }
  return showDialog<TaskItem>(
    context: context,
    builder: (ctx) => TaskEditorDialog(
      session: session,
      parentTaskId: parentTaskId,
      parentTask: parentTask,
    ),
  );
}

/// APP 全屏新建页。
class TaskEditorPage extends StatelessWidget {
  const TaskEditorPage({
    super.key,
    required this.session,
    this.parentTaskId,
    this.parentTask,
  });

  final AuthSession session;
  final int? parentTaskId;
  final TaskItem? parentTask;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        child: _TaskEditorBody(
          session: session,
          parentTaskId: parentTaskId,
          parentTask: parentTask,
          fullscreen: true,
          onCancel: () => Navigator.pop(context),
          onCreated: (item) => Navigator.pop(context, item),
        ),
      ),
    );
  }
}

/// PC 弹窗新建。
class TaskEditorDialog extends StatelessWidget {
  const TaskEditorDialog({
    super.key,
    required this.session,
    this.parentTaskId,
    this.parentTask,
  });

  final AuthSession session;
  final int? parentTaskId;
  final TaskItem? parentTask;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: EdgeInsets.zero,
      contentPadding: EdgeInsets.zero,
      actionsPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: _TaskEditorBody(
            session: session,
            parentTaskId: parentTaskId,
            parentTask: parentTask,
            fullscreen: false,
            onCancel: () => Navigator.pop(context),
            onCreated: (item) => Navigator.pop(context, item),
          ),
        ),
      ),
    );
  }
}

class _TaskEditorBody extends StatefulWidget {
  const _TaskEditorBody({
    required this.session,
    this.parentTaskId,
    this.parentTask,
    required this.fullscreen,
    required this.onCancel,
    required this.onCreated,
  });

  final AuthSession session;
  final int? parentTaskId;
  final TaskItem? parentTask;
  final bool fullscreen;
  final VoidCallback onCancel;
  final ValueChanged<TaskItem> onCreated;

  @override
  State<_TaskEditorBody> createState() => _TaskEditorBodyState();
}

class _TaskEditorBodyState extends State<_TaskEditorBody> {
  late final TaskApi _api = TaskApi(widget.session);
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _acceptCtrl = TextEditingController();
  String _priority = 'medium';
  String _category = '业务';
  int? _ownerId;
  String _ownerName = '';
  DateTime? _startAt;
  DateTime? _dueAt;
  List<TaskAssignee> _assignees = const [];
  List<TaskAttachment> _attachments = const [];
  TaskItem? _parentTask;
  bool _loadingAssignees = false;
  bool _saving = false;
  String? _titleError;
  String? _dateError;

  bool get _isSub => widget.parentTaskId != null;

  /// 主任务由当前用户创建 → 自建子任务免审。
  bool get _parentSelfCreated =>
      _parentTask != null &&
      _parentTask!.creatorUserId == widget.session.userId;

  @override
  void initState() {
    super.initState();
    _ownerId = widget.session.userId;
    _ownerName = widget.session.displayName?.trim().isNotEmpty == true
        ? widget.session.displayName!.trim()
        : '我';
    if (_isSub) {
      _applyParentDefaults(widget.parentTask);
      unawaited(_loadParentIfNeeded());
      unawaited(_loadAssignees());
    }
  }

  void _applyParentDefaults(TaskItem? parent) {
    if (parent == null) return;
    _parentTask = parent;
    if (parent.priority.trim().isNotEmpty) {
      _priority = parent.priority;
    }
    if (parent.category.trim().isNotEmpty) {
      _category = parent.category;
    }
  }

  Future<void> _loadParentIfNeeded() async {
    final id = widget.parentTaskId;
    if (id == null) return;
    if (_parentTask != null && _parentTask!.id == id) return;
    try {
      final detail = await _api.getDetail(id);
      if (!mounted) return;
      setState(() => _applyParentDefaults(detail.task));
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _acceptCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAssignees() async {
    setState(() => _loadingAssignees = true);
    try {
      final list = await _api.listAssignees();
      if (!mounted) return;
      setState(() {
        _assignees = list;
        _loadingAssignees = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingAssignees = false);
    }
  }

  Future<void> _pickAssignee() async {
    if (_assignees.isEmpty && !_loadingAssignees) await _loadAssignees();
    if (!mounted) return;
    final picked = await showModalBottomSheet<TaskAssignee>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.55,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '选择执行人（自己或下级）',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                Expanded(
                  child: _loadingAssignees
                      ? const Center(child: CircularProgressIndicator(color: _themePurple))
                      : ListView.builder(
                          itemCount: _assignees.length,
                          itemBuilder: (_, i) {
                            final a = _assignees[i];
                            return ListTile(
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

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_startAt ?? now)
        : (_dueAt ?? _startAt ?? now);
    final first = DateTime(now.year - 1);
    final last = DateTime(now.year + 5);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: isStart ? '选择开始时间' : '选择结束时间',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: _themePurple,
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
      _dateError = null;
    });
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '请选择';
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '请填写标题');
      return;
    }
    if (_startAt != null && _dueAt != null && _dueAt!.isBefore(_startAt!)) {
      setState(() => _dateError = '结束时间不能早于开始时间');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_isSub ? '确认创建子任务' : '确认创建主任务'),
        content: Text(_isSub ? '确认保存该子任务吗？' : '确认保存该主任务吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _themePurple),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认保存'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _titleError = null;
      _dateError = null;
      _saving = true;
    });
    try {
      final body = <String, dynamic>{
        'title': title,
        'description': _descCtrl.text.trim(),
        'priority': _priority,
        'category': _category,
        'acceptanceCriteria': _acceptCtrl.text.trim(),
        'ownerUserId': _ownerId ?? widget.session.userId,
        if (_attachments.isNotEmpty)
          'attachments': _attachments.map((e) => e.toCreateJson()).toList(),
      };
      if (_startAt != null) body['startAt'] = _startAt!.toUtc().toIso8601String();
      if (_dueAt != null) body['dueAt'] = _dueAt!.toUtc().toIso8601String();
      final TaskItem created;
      if (_isSub) {
        created = await _api.createSubtask(widget.parentTaskId!, body);
      } else {
        created = await _api.createMain(body);
      }
      if (!mounted) return;
      widget.onCreated(created);
    } catch (e) {
      if (!mounted) return;
      showDunesCenterToast(context, '$e');
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = widget.fullscreen || MediaQuery.sizeOf(context).width < 640;
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (narrow) ...[
          _field(
            _titleCtrl,
            '标题',
            required: true,
            hint: '简明描述任务目标',
            errorText: _titleError,
          ),
          const SizedBox(height: 14),
          _pickerField(
            label: _isSub ? '执行人' : '负责人',
            value: _ownerName.isEmpty ? '选择人员' : _ownerName,
            onTap: _isSub ? _pickAssignee : null,
          ),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _field(
                  _titleCtrl,
                  '标题',
                  required: true,
                  hint: '简明描述任务目标',
                  errorText: _titleError,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _pickerField(
                  label: _isSub ? '执行人' : '负责人',
                  value: _ownerName.isEmpty ? '选择人员' : _ownerName,
                  onTap: _isSub ? _pickAssignee : null,
                ),
              ),
            ],
          ),
        const SizedBox(height: 14),
        if (narrow) ...[
          _dropdownField(
            label: '优先级',
            value: _priority,
            items: const [
              ('low', '低'),
              ('medium', '中'),
              ('high', '高'),
              ('urgent', '紧急'),
            ],
            onChanged: (v) => setState(() => _priority = v),
          ),
          const SizedBox(height: 14),
          _dropdownField(
            label: '分类',
            value: _category,
            items: const [
              ('业务', '业务'),
              ('研发', '研发'),
              ('管理', '管理'),
              ('其他', '其他'),
            ],
            onChanged: (v) => setState(() => _category = v),
          ),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _dropdownField(
                  label: '优先级',
                  value: _priority,
                  items: const [
                    ('low', '低'),
                    ('medium', '中'),
                    ('high', '高'),
                    ('urgent', '紧急'),
                  ],
                  onChanged: (v) => setState(() => _priority = v),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _dropdownField(
                  label: '分类',
                  value: _category,
                  items: const [
                    ('业务', '业务'),
                    ('研发', '研发'),
                    ('管理', '管理'),
                    ('其他', '其他'),
                  ],
                  onChanged: (v) => setState(() => _category = v),
                ),
              ),
            ],
          ),
        const SizedBox(height: 14),
        if (narrow) ...[
          _pickerField(
            label: '开始时间',
            value: _fmtDate(_startAt),
            onTap: () => _pickDate(isStart: true),
            placeholder: _startAt == null,
          ),
          const SizedBox(height: 14),
          _pickerField(
            label: '结束时间',
            value: _fmtDate(_dueAt),
            onTap: () => _pickDate(isStart: false),
            placeholder: _dueAt == null,
          ),
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _pickerField(
                  label: '开始时间',
                  value: _fmtDate(_startAt),
                  onTap: () => _pickDate(isStart: true),
                  placeholder: _startAt == null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _pickerField(
                  label: '结束时间',
                  value: _fmtDate(_dueAt),
                  onTap: () => _pickDate(isStart: false),
                  placeholder: _dueAt == null,
                ),
              ),
            ],
          ),
        if (_dateError != null) ...[
          const SizedBox(height: 6),
          Text(
            _dateError!,
            style: const TextStyle(fontSize: 12, color: Color(0xFFE35D6A)),
          ),
        ],
        const SizedBox(height: 14),
        _field(_descCtrl, '描述', hint: '背景 / 目标（可选）', maxLines: 2),
        if (!_isSub) ...[
          const SizedBox(height: 14),
          _field(_acceptCtrl, '验收标准', hint: '可选', maxLines: 2),
        ],
        const SizedBox(height: 14),
        TaskAttachmentField(
          session: widget.session,
          files: _attachments,
          onChanged: (list) => setState(() => _attachments = list),
        ),
        if (_isSub) ...[
          const SizedBox(height: 8),
          Text(
            _parentSelfCreated
                ? '仅可分配给自己或下级；主任务由你创建时，自建子任务无需审核。'
                : '仅可分配给自己或下级；分给自己时需上级审核。',
            style: const TextStyle(fontSize: 12, color: DunesColors.text3, height: 1.4),
          ),
        ],
      ],
    );

    if (widget.fullscreen) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: _saving ? null : widget.onCancel,
                  icon: const Icon(Icons.close_rounded),
                  color: DunesColors.text2,
                ),
                Expanded(
                  child: Text(
                    _isSub ? '新建子任务' : '新建主任务',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _themePurple,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('保存'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE8EAED)),
                  ),
                  child: form,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          child: Text(
            _isSub ? '新建子任务' : '新建主任务',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
            child: form,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : widget.onCancel,
                child: const Text('取消', style: TextStyle(color: DunesColors.text2)),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _themePurple,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    String? errorText,
    int maxLines = 1,
    bool required = false,
  }) {
    final hasError = errorText != null && errorText.isNotEmpty;
    return _Labeled(
      label: label,
      required: required,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: c,
            maxLines: maxLines,
            style: const TextStyle(fontSize: 14, color: DunesColors.text, height: 1.3),
            onChanged: (_) {
              if (_titleError != null && c == _titleCtrl && c.text.trim().isNotEmpty) {
                setState(() => _titleError = null);
              }
            },
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 14,
                color: DunesColors.text3.withValues(alpha: 0.85),
              ),
              filled: true,
              fillColor: hasError ? const Color(0xFFFFF1F2) : const Color(0xFFF5F6F8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: hasError
                    ? const BorderSide(color: Color(0xFFE35D6A))
                    : BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: hasError
                      ? const Color(0xFFE35D6A)
                      : _themePurple.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          if (hasError) ...[
            const SizedBox(height: 6),
            Text(errorText, style: const TextStyle(fontSize: 12, color: Color(0xFFE35D6A))),
          ],
        ],
      ),
    );
  }

  Widget _pickerField({
    required String label,
    required String value,
    VoidCallback? onTap,
    bool placeholder = false,
  }) {
    return _Labeled(
      label: label,
      child: Material(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      color: placeholder ? DunesColors.text3 : DunesColors.text,
                    ),
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.expand_more, size: 20, color: DunesColors.text3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropdownField({
    required String label,
    required String value,
    required List<(String, String)> items,
    required ValueChanged<String> onChanged,
  }) {
    final current = items.firstWhere(
      (e) => e.$1 == value,
      orElse: () => (value, value),
    );
    final useSheet =
        widget.fullscreen || MediaQuery.sizeOf(context).width < 700;
    if (useSheet) {
      return _Labeled(
        label: label,
        child: Material(
          color: const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              final picked = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '选择$label',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      for (final item in items)
                        ListTile(
                          title: Text(item.$2),
                          trailing: item.$1 == value
                              ? const Icon(Icons.check_rounded, color: _themePurple)
                              : null,
                          onTap: () => Navigator.pop(ctx, item.$1),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
              if (picked != null) onChanged(picked);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      current.$2,
                      style: const TextStyle(fontSize: 14, color: DunesColors.text),
                    ),
                  ),
                  const Icon(Icons.expand_more, size: 20, color: DunesColors.text3),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // PC：MenuAnchor 锚定字段本身，避免 Dialog 内 showMenu 错位。
    return _Labeled(
      label: label,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final menuWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 220.0;
          return MenuAnchor(
            alignmentOffset: const Offset(0, 6),
            style: kTaskMenuStyle,
            builder: (context, controller, child) {
              final open = controller.isOpen;
              return Material(
                color: open
                    ? _themePurple.withValues(alpha: 0.08)
                    : const Color(0xFFF5F6F8),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => open ? controller.close() : controller.open(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            current.$2,
                            style: TextStyle(
                              fontSize: 14,
                              color: open ? _themePurple : DunesColors.text,
                              fontWeight:
                                  open ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.expand_more,
                          size: 20,
                          color: open ? _themePurple : DunesColors.text3,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            menuChildren: [
              for (final item in items)
                MenuItemButton(
                  onPressed: () => onChanged(item.$1),
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (item.$1 == value) {
                        return _themePurple.withValues(alpha: 0.1);
                      }
                      if (states.contains(WidgetState.hovered)) {
                        return const Color(0xFFF5F6F8);
                      }
                      return Colors.transparent;
                    }),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    minimumSize: WidgetStatePropertyAll(Size(menuWidth, 44)),
                  ),
                  trailingIcon: item.$1 == value
                      ? const Icon(Icons.check_rounded, size: 16, color: _themePurple)
                      : null,
                  child: SizedBox(
                    width: menuWidth - 48,
                    child: Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            item.$1 == value ? FontWeight.w600 : FontWeight.w400,
                        color: item.$1 == value ? _themePurple : DunesColors.text,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({
    required this.label,
    required this.child,
    this.required = false,
  });

  final String label;
  final Widget child;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DunesColors.text2,
              ),
            ),
            if (required)
              const Text(
                ' *',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE35D6A),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
