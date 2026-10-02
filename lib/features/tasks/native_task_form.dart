import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'task_api.dart';
import 'task_attachment_field.dart';
import 'task_avatar.dart';
import 'task_create_confirm.dart';
import 'task_first_use_guide.dart';
import 'task_helper_picker.dart';
import 'task_models.dart';
import 'task_widgets.dart';

const _themePurple = Color(0xFF7B5CD8);

const _taskCategoryOptions = <String, List<(String, String)>>{
  '业务': [('销售', '销售'), ('市场', '市场'), ('运营', '运营'), ('客服', '客服'), ('商务', '商务')],
  '研发': [
    ('技术', '技术'),
    ('产品', '产品'),
    ('设计', '设计'),
    ('测试', '测试'),
    ('运维', '运维'),
    ('运营', '运营'),
  ],
  '管理': [('团队管理', '团队管理'), ('人才培养', '人才培养'), ('组织建设', '组织建设')],
  '职能': [
    ('财务', '财务'),
    ('人事', '人事'),
    ('行政', '行政'),
    ('IT 支持', 'IT 支持'),
    ('采购', '采购'),
  ],
};

class _SubDraft {
  _SubDraft()
    : title = TextEditingController(),
      accept = TextEditingController();

  final TextEditingController title;
  final TextEditingController accept;

  /// self 自己执行，assist 分派协助，team 给团队成员。
  String kind = 'self';
  int? ownerId;
  String ownerName = '';
  final List<TaskAssignee> helpers = [];

  void dispose() {
    title.dispose();
    accept.dispose();
  }
}

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
    return TaskTheme(
      child: Scaffold(
        backgroundColor: DunesColors.resolve(
          context,
          const Color(0xFFF5F6F8),
          role: DunesColorRole.surface,
        ),
        // 点击空白处收起软键盘
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SafeArea(
            child: _TaskEditorBody(
              session: session,
              parentTaskId: parentTaskId,
              parentTask: parentTask,
              fullscreen: true,
              onCancel: () => Navigator.pop(context),
              onCreated: (item) => Navigator.pop(context, item),
            ),
          ),
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
    return TaskTheme(
      child: AlertDialog(
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
  String _subCategory = '销售';
  int? _ownerId;
  String _ownerName = '';
  DateTime? _startAt;
  DateTime? _dueAt;
  List<TaskAttachment> _attachments = const [];
  TaskItem? _parentTask;
  bool _saving = false;
  bool _canAssignTeam = false;
  String _dispatchKind = 'self';
  final List<TaskAssignee> _helpers = [];
  final List<TaskAssignee> _participants = [];
  List<TaskAssignee> _rdOwners = const [];
  final List<_SubDraft> _subDrafts = [];
  bool _guideAutoStarted = false;
  bool _rulesLoaded = false;
  bool _assignmentConfirmation = false;
  String? _titleError;
  String? _dateError;

  bool get _isSub => widget.parentTaskId != null;
  List<(String, String)> get _subCategoryOptions =>
      _taskCategoryOptions[_category] ?? const [];

  bool get _parentIsMine =>
      _parentTask != null && _parentTask!.ownerUserId == widget.session.userId;

  Future<void> _loadRules() async {
    try {
      final rules = await _api.taskRules();
      if (!mounted) return;
      setState(() {
        _assignmentConfirmation = rules.assignmentConfirmation;
        _rulesLoaded = true;
      });
    } catch (_) {}
  }

  String get _pathHint {
    if (!_rulesLoaded) return '';
    if (!_isSub) {
      if (_handsOff) return '提交后由需求负责人接收。对方接收后才能拆子任务。';
      if (!_canAssignTeam) {
        return '自己负责即可创建，协助人谁都可以添加。只有沙丘职级为 M 序列的人可以把负责人设成团队成员。';
      }
      return '需求方就是创建人。自己负责时可以同时拆子任务。';
    }
    final self = _ownerId == null || _ownerId == widget.session.userId;
    if (!_parentIsMine) return '提交后由主任务负责人审核，通过后子任务才会生效。';
    if (self) return '你是主任务负责人，创建的子任务会直接生效。';
    if (_assignmentConfirmation) {
      return '指派给他人后，对方接受才会开始执行。对方拒绝则不会生效。';
    }
    return '指派给他人后直接生效，对方可以开始执行。';
  }

  @override
  void initState() {
    super.initState();
    _ownerId = widget.session.userId;
    _ownerName = widget.session.displayName?.trim().isNotEmpty == true
        ? widget.session.displayName!.trim()
        : '我';
    unawaited(_loadRules());
    unawaited(_loadRdIntake());
    if (_isSub) {
      _applyParentDefaults(widget.parentTask);
      unawaited(_loadParentIfNeeded());
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
      page: _isSub ? TaskGuidePage.createSub : TaskGuidePage.createMain,
      force: force,
    );
  }

  void _applyParentDefaults(TaskItem? parent) {
    if (parent == null) return;
    _parentTask = parent;
    if (parent.priority.trim().isNotEmpty) {
      _priority = parent.priority;
    }
    final parentCategory = parent.category.trim();
    if (_taskCategoryOptions.containsKey(parentCategory)) {
      _category = parentCategory;
      final options = _subCategoryOptions;
      _subCategory = options.any((item) => item.$1 == parent.subCategory)
          ? parent.subCategory
          : options.first.$1;
    }
    final parentStart = parent.startAt?.toLocal();
    if (_startAt == null && parentStart != null) {
      _startAt = DateTime(parentStart.year, parentStart.month, parentStart.day);
    }
    final parentDue = parent.dueAt?.toLocal();
    if (_dueAt == null && parentDue != null) {
      _dueAt = DateTime(
        parentDue.year,
        parentDue.month,
        parentDue.day,
        23,
        59,
        59,
      );
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

  bool get _handsOff => taskCreateHandsOffToRd(
    ownerUserId: _ownerId ?? widget.session.userId,
    selfUserId: widget.session.userId,
    rdOwnerIds: _rdOwners.map((owner) => owner.id),
  );

  String get _requesterName {
    final name = widget.session.displayName?.trim() ?? '';
    return name.isEmpty ? '我' : name;
  }

  Future<void> _loadRdIntake() async {
    try {
      final intake = await _api.rdIntake();
      if (!mounted) return;
      setState(() {
        _canAssignTeam = intake.canAssignTeam;
        _rdOwners = intake.owners;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _acceptCtrl.dispose();
    for (final draft in _subDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAssignee() async {
    final picked = await showTaskColleaguePicker(
      context,
      api: _api,
      excludeUserId: widget.session.userId,
      title: '选择团队成员',
    );
    if (picked == null || !mounted) return;
    if (_rejectTeamAssign(picked.id)) return;
    setState(() {
      _ownerId = picked.id;
      _ownerName = picked.displayName;
    });
  }

  bool _rejectTeamAssign(int userId) {
    if (userId == widget.session.userId || _canAssignTeam) return false;
    showDunesCenterToast(context, '只有沙丘职级为 M 序列的人员可以给团队成员创建任务');
    return true;
  }

  Future<void> _pickHelpers() async {
    final picked = await showTaskHelperPicker(
      context,
      api: _api,
      selectedIds: _helpers.map((e) => e.id).toSet(),
      known: _helpers,
      excludeUserId: widget.session.userId,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _helpers
        ..clear()
        ..addAll(picked);
    });
  }

  Future<void> _pickParticipants() async {
    final picked = await showTaskHelperPicker(
      context,
      api: _api,
      selectedIds: _participants.map((e) => e.id).toSet(),
      known: _participants,
      excludeUserId: 0,
      title: '选择主任务参与人',
      scope: 'participants',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _participants
        ..clear()
        ..addAll(picked);
    });
  }

  Widget _participantPicker() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE6E1EF),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.groups_2_outlined,
                size: 18,
                color: DunesColors.resolveNullable(context, _themePurple),
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  '主任务参与人',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: _pickParticipants,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: Text(_participants.isEmpty ? '添加人员' : '调整人员'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: _themePurple,
                ),
              ),
            ],
          ),
          Text(
            '选择自己或自己的下属。参与人可以查看主任务并提交子任务，子任务需主任务负责人审核。',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
          ),
          if (_participants.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final person in _participants)
                  Container(
                    padding: const EdgeInsets.fromLTRB(5, 4, 9, 4),
                    decoration: BoxDecoration(
                      color: DunesColors.resolve(
                        context,
                        const Color(0xFFF5F1FC),
                        role: DunesColorRole.surface,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        buildTaskUserAvatar(
                          session: widget.session,
                          name: person.displayName,
                          userId: person.id,
                          avatarPreset: person.avatarPreset,
                          avatarObjectKey: person.avatarObjectKey,
                          avatarUrl: person.avatarUrl,
                          size: 24,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          person.displayName,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? (_startAt ?? now) : (_dueAt ?? _startAt ?? now);
    final first = DateTime(now.year - 1);
    final last = DateTime(now.year + 5);
    final picked = await showTaskDatePicker(
      context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
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

  TaskAssignee? _personById(
    int? id, {
    String fallbackName = '',
    List<TaskAssignee> extra = const [],
  }) {
    if (id == null || id <= 0) return null;
    if (id == widget.session.userId) {
      return TaskAssignee(id: id, displayName: _requesterName);
    }
    for (final person in [
      ..._rdOwners,
      ..._participants,
      ..._helpers,
      ...extra,
    ]) {
      if (person.id == id) return person;
    }
    if (fallbackName.trim().isEmpty) return null;
    return TaskAssignee(id: id, displayName: fallbackName.trim());
  }

  Widget _personAvatar(TaskAssignee? person, {double size = 28}) {
    if (person == null) return SizedBox(width: size, height: size);
    return buildTaskUserAvatar(
      session: widget.session,
      name: person.displayName,
      userId: person.id,
      avatarPreset: person.avatarPreset,
      avatarObjectKey: person.avatarObjectKey,
      avatarUrl: person.avatarUrl,
      size: size,
    );
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '请选择';
    return formatTaskYmd(d);
  }

  Future<void> _pickRequirementOwner() async {
    final selfName = _requesterName;
    final options = <TaskAssignee>[
      TaskAssignee(id: widget.session.userId, displayName: selfName),
      for (final owner in _rdOwners)
        if (owner.id != widget.session.userId) owner,
    ];
    if (!mounted) return;
    final picked = await showModalBottomSheet<TaskAssignee>(
      context: context,
      backgroundColor: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  '选择需求负责人',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              for (final owner in options)
                ListTile(
                  leading: buildTaskUserAvatar(
                    session: widget.session,
                    name: owner.displayName,
                    userId: owner.id,
                    avatarPreset: owner.avatarPreset,
                    avatarObjectKey: owner.avatarObjectKey,
                    avatarUrl: owner.avatarUrl,
                    size: 38,
                  ),
                  title: Text(owner.displayName),
                  subtitle: owner.id == widget.session.userId
                      ? const Text('自己负责，创建后直接生效')
                      : Text(
                          owner.departmentName.isEmpty
                              ? '科技研发中心，接收后拆子任务'
                              : owner.departmentName,
                        ),
                  onTap: () => Navigator.pop(ctx, owner),
                ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    if (_rejectTeamAssign(picked.id)) return;
    setState(() {
      _ownerId = picked.id;
      _ownerName = picked.displayName;
      if (_handsOff) {
        for (final draft in _subDrafts) {
          draft.dispose();
        }
        _subDrafts.clear();
      }
    });
  }

  Future<void> _submit() async {
    final selfId = widget.session.userId;
    final ownerId = _isSub && _dispatchKind != 'team'
        ? selfId
        : (_ownerId ?? selfId);
    if (_isSub && _dispatchKind == 'team' && ownerId == selfId) {
      showDunesCenterToast(context, '请选择团队成员');
      return;
    }
    if (_isSub && _dispatchKind == 'assist' && _helpers.isEmpty) {
      showDunesCenterToast(context, '请选择协助人');
      return;
    }
    if (_rejectTeamAssign(ownerId)) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '请填写标题');
      return;
    }
    final dateErr = taskCreateRangeError(_startAt, _dueAt);
    if (dateErr != null) {
      setState(() => _dateError = dateErr);
      return;
    }
    if (_acceptCtrl.text.trim().isEmpty) {
      showDunesCenterToast(context, '请填写验收标准');
      return;
    }
    final drafts = _isSub || _handsOff
        ? const <_SubDraft>[]
        : List<_SubDraft>.from(_subDrafts);
    for (final draft in drafts) {
      if (draft.kind == 'team' &&
          _rejectTeamAssign(draft.ownerId ?? widget.session.userId)) {
        return;
      }
      if (draft.kind == 'team' &&
          (draft.ownerId == null || draft.ownerId == widget.session.userId)) {
        showDunesCenterToast(context, '请选择团队成员');
        return;
      }
      if (draft.kind == 'assist' && draft.helpers.isEmpty) {
        showDunesCenterToast(context, '请选择协助人');
        return;
      }
      if (draft.title.text.trim().isEmpty) {
        showDunesCenterToast(context, '请填写子任务名称，或删除空行');
        return;
      }
      if (draft.accept.text.trim().isEmpty) {
        showDunesCenterToast(context, '请填写子任务验收标准');
        return;
      }
    }
    if (!mounted) return;
    final ok = await confirmCreateTask(
      context,
      title: title,
      startAt: _startAt,
      dueAt: _dueAt,
      kind: _isSub ? '子目标' : '主目标',
    );
    if (!ok || !mounted) return;
    setState(() {
      _titleError = null;
      _dateError = null;
      _saving = true;
    });
    try {
      final body = <String, dynamic>{
        'title': title,
        'description': _descCtrl.text.trim().isEmpty
            ? title
            : _descCtrl.text.trim(),
        'priority': _priority,
        'category': _category,
        'subCategory': _subCategory,
        'acceptanceCriteria': _acceptCtrl.text.trim(),
        'ownerUserId': ownerId,
        if (!_isSub && _participants.isNotEmpty)
          'participantUserIds': _participants.map((e) => e.id).toList(),
        if (_isSub && _dispatchKind == 'assist' && _helpers.isNotEmpty)
          'coOwnerUserIds': _helpers.map((e) => e.id).toList(),
        if (_attachments.isNotEmpty)
          'attachments': _attachments.map((e) => e.toCreateJson()).toList(),
        'startAt': _startAt!.toUtc().toIso8601String(),
        'dueAt': _dueAt!.toUtc().toIso8601String(),
      };
      final TaskItem created;
      if (_isSub) {
        created = await _api.createSubtask(widget.parentTaskId!, body);
      } else {
        created = await _api.createMain(body);
        for (var i = 0; i < drafts.length; i++) {
          final draft = drafts[i];
          try {
            final selfId = widget.session.userId;
            final teamOwner = draft.kind == 'team'
                ? (draft.ownerId ?? selfId)
                : selfId;
            if (draft.kind == 'team' && teamOwner == selfId) {
              showDunesCenterToast(context, '请为第 ${i + 1} 条子任务选择团队成员');
              break;
            }
            if (draft.kind == 'assist' && draft.helpers.isEmpty) {
              showDunesCenterToast(context, '请为第 ${i + 1} 条子任务选择协助人');
              break;
            }
            await _api.createSubtask(created.id, {
              'title': draft.title.text.trim(),
              'description': draft.title.text.trim(),
              'acceptanceCriteria': draft.accept.text.trim(),
              'priority': _priority,
              'category': _category,
              'ownerUserId': teamOwner,
              if (draft.kind == 'assist')
                'coOwnerUserIds': draft.helpers.map((e) => e.id).toList(),
              'startAt': _startAt!.toUtc().toIso8601String(),
              'dueAt': _dueAt!.toUtc().toIso8601String(),
            });
          } catch (e) {
            if (mounted) {
              showDunesCenterToast(context, '主任务已创建，第 ${i + 1} 条子任务失败：$e');
            }
            break;
          }
        }
      }
      if (!mounted) return;
      widget.onCreated(created);
    } catch (e) {
      if (!mounted) return;
      showDunesCenterToast(context, '$e');
      setState(() => _saving = false);
    }
  }

  Widget _dispatchKindChips({
    required String kind,
    required ValueChanged<String> onChanged,
  }) {
    const options = [('self', '自己执行'), ('assist', '分派协助'), ('team', '给团队成员')];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option.$2),
            selected: kind == option.$1,
            selectedColor: DunesColors.resolve(
              context,
              const Color(0xFFEDE7FA),
            ),
            labelStyle: TextStyle(
              fontSize: 13,
              color: kind == option.$1
                  ? DunesColors.resolve(context, _themePurple)
                  : DunesColors.resolve(context, DunesColors.text2),
              fontWeight: kind == option.$1 ? FontWeight.w700 : FontWeight.w500,
            ),
            side: BorderSide(
              color: kind == option.$1
                  ? DunesColors.resolve(
                      context,
                      _themePurple,
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      const Color(0xFFE4E6EB),
                      role: DunesColorRole.border,
                    ),
            ),
            onSelected: (_) {
              if (option.$1 == 'team' && !_canAssignTeam) {
                showDunesCenterToast(context, '只有沙丘职级为 M 序列的人员可以给团队成员创建任务');
                return;
              }
              onChanged(option.$1);
            },
          ),
      ],
    );
  }

  Future<void> _pickDraftOwner(_SubDraft draft) async {
    final picked = await showTaskColleaguePicker(
      context,
      api: _api,
      excludeUserId: widget.session.userId,
      title: '选择团队成员',
    );
    if (picked == null || !mounted) return;
    if (_rejectTeamAssign(picked.id)) return;
    setState(() {
      draft.ownerId = picked.id;
      draft.ownerName = picked.displayName;
    });
  }

  Future<void> _pickDraftHelpers(_SubDraft draft) async {
    final picked = await showTaskHelperPicker(
      context,
      api: _api,
      selectedIds: draft.helpers.map((e) => e.id).toSet(),
      known: draft.helpers,
      excludeUserId: widget.session.userId,
    );
    if (picked == null || !mounted) return;
    setState(() {
      draft.helpers
        ..clear()
        ..addAll(picked);
    });
  }

  Widget _subDraftCard(int index) {
    final draft = _subDrafts[index];
    final ownerLabel = draft.ownerName.isEmpty ? '请选择团队成员' : draft.ownerName;
    final helperLabel = draft.helpers.isEmpty
        ? '请选择协助人'
        : draft.helpers.map((e) => e.displayName).join('、');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: DunesColors.resolve(
          context,
          const Color(0xFFF7F8FA),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '子任务 ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '删除',
                    onPressed: () {
                      setState(() {
                        _subDrafts.removeAt(index).dispose();
                      });
                    },
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              _dispatchKindChips(
                kind: draft.kind,
                onChanged: (kind) => setState(() {
                  draft.kind = kind;
                  if (kind != 'team') {
                    draft.ownerId = null;
                    draft.ownerName = '';
                  }
                  if (kind != 'assist') draft.helpers.clear();
                }),
              ),
              const SizedBox(height: 8),
              _field(draft.title, '名称', hint: '简明描述子任务'),
              const SizedBox(height: 8),
              _field(draft.accept, '验收标准', hint: '怎样算完成'),
              if (draft.kind == 'assist') ...[
                const SizedBox(height: 8),
                _pickerField(
                  label: '协助人',
                  value: helperLabel,
                  leading: draft.helpers.isEmpty
                      ? null
                      : _personAvatar(draft.helpers.first),
                  placeholder: draft.helpers.isEmpty,
                  onTap: () => _pickDraftHelpers(draft),
                ),
              ],
              if (draft.kind == 'team') ...[
                const SizedBox(height: 8),
                _pickerField(
                  label: '执行人',
                  value: ownerLabel,
                  leading: _personAvatar(
                    _personById(
                      draft.ownerId,
                      fallbackName: draft.ownerName,
                      extra: draft.helpers,
                    ),
                  ),
                  placeholder: draft.ownerId == null,
                  onTap: () => _pickDraftOwner(draft),
                ),
              ],
              if (draft.kind == 'self')
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '负责人是你自己，创建后直接由你执行。',
                    style: TextStyle(
                      fontSize: 12,
                      color: DunesColors.resolve(context, DunesColors.text3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
          if (_isSub)
            _dispatchKindChips(
              kind: _dispatchKind,
              onChanged: (kind) => setState(() {
                _dispatchKind = kind;
                if (kind != 'team') {
                  _ownerId = widget.session.userId;
                  _ownerName = _requesterName;
                }
                if (kind != 'assist') _helpers.clear();
              }),
            )
          else
            _pickerField(
              label: '需求负责人',
              value: _ownerName.isEmpty ? '选择人员' : _ownerName,
              leading: _personAvatar(
                _personById(_ownerId, fallbackName: _ownerName),
              ),
              onTap: _pickRequirementOwner,
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
                child: _isSub
                    ? _dispatchKindChips(
                        kind: _dispatchKind,
                        onChanged: (kind) => setState(() {
                          _dispatchKind = kind;
                          if (kind != 'team') {
                            _ownerId = widget.session.userId;
                            _ownerName = _requesterName;
                          }
                          if (kind != 'assist') _helpers.clear();
                        }),
                      )
                    : _pickerField(
                        label: '需求负责人',
                        value: _ownerName.isEmpty ? '选择人员' : _ownerName,
                        leading: _personAvatar(
                          _personById(_ownerId, fallbackName: _ownerName),
                        ),
                        onTap: _pickRequirementOwner,
                      ),
              ),
            ],
          ),
        if (_pathHint.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _pathHint,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
        ],
        if (!_isSub) ...[const SizedBox(height: 14), _participantPicker()],
        if (_isSub && _dispatchKind == 'assist')
          _pickerField(
            label: '协助人',
            value: _helpers.isEmpty
                ? '请选择协助人'
                : _helpers.map((e) => e.displayName).join('、'),
            leading: _helpers.isEmpty ? null : _personAvatar(_helpers.first),
            placeholder: _helpers.isEmpty,
            onTap: _pickHelpers,
          ),
        if (_isSub && _dispatchKind == 'team')
          _pickerField(
            label: '执行人',
            value: _ownerName.isEmpty || _ownerId == widget.session.userId
                ? '请选择团队成员'
                : _ownerName,
            leading: _personAvatar(
              _personById(_ownerId, fallbackName: _ownerName),
            ),
            onTap: _pickAssignee,
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
            label: '一级分类',
            value: _category,
            items: const [
              ('业务', '业务'),
              ('研发', '研发'),
              ('管理', '管理'),
              ('职能', '职能'),
            ],
            onChanged: (v) => setState(() {
              _category = v;
              _subCategory = _subCategoryOptions.first.$1;
            }),
          ),
          const SizedBox(height: 14),
          _dropdownField(
            label: '二级分类',
            value: _subCategory,
            items: _subCategoryOptions,
            onChanged: (v) => setState(() => _subCategory = v),
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
                  label: '一级分类',
                  value: _category,
                  items: const [
                    ('业务', '业务'),
                    ('研发', '研发'),
                    ('管理', '管理'),
                    ('职能', '职能'),
                  ],
                  onChanged: (v) => setState(() {
                    _category = v;
                    _subCategory = _subCategoryOptions.first.$1;
                  }),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _dropdownField(
                  label: '二级分类',
                  value: _subCategory,
                  items: _subCategoryOptions,
                  onChanged: (v) => setState(() => _subCategory = v),
                ),
              ),
            ],
          ),
        if (!_isSub) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '需求方：$_requesterName',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '当前分类是「$_category · $_subCategory」，提交前可以修改。',
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text3),
                height: 1.35,
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (narrow) ...[
          _pickerField(
            label: '开始时间',
            value: _fmtDate(_startAt),
            onTap: () => _pickDate(isStart: true),
            placeholder: _startAt == null,
            required: true,
          ),
          const SizedBox(height: 14),
          _pickerField(
            label: '结束时间',
            value: _fmtDate(_dueAt),
            onTap: () => _pickDate(isStart: false),
            placeholder: _dueAt == null,
            required: true,
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
                  required: true,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _pickerField(
                  label: '结束时间',
                  value: _fmtDate(_dueAt),
                  onTap: () => _pickDate(isStart: false),
                  placeholder: _dueAt == null,
                  required: true,
                ),
              ),
            ],
          ),
        if (_dateError != null) ...[
          const SizedBox(height: 6),
          Text(
            _dateError!,
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolveNullable(context, Color(0xFFE35D6A)),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _field(_descCtrl, '描述', hint: '背景 / 目标（可选）', maxLines: 2),
        const SizedBox(height: 14),
        _field(
          _acceptCtrl,
          '验收标准',
          hint: _isSub ? '填写子目标完成的判断标准' : '填写目标完成的判断标准',
          maxLines: 2,
          required: true,
        ),
        const SizedBox(height: 14),
        TaskAttachmentField(
          session: widget.session,
          files: _attachments,
          onChanged: (list) => setState(() => _attachments = list),
        ),
        if (!_isSub && !_handsOff) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '子任务',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _subDrafts.add(_SubDraft())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
          Text(
            '和主任务一起保存。自己执行谁都可以。分派协助是找人一起做，负责人仍是你。给团队成员只有沙丘职级为 M 序列可以，对方成为执行人。',
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
              height: 1.4,
            ),
          ),
          for (var i = 0; i < _subDrafts.length; i++) _subDraftCard(i),
        ],
        if (!_isSub && _handsOff)
          Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              '交给科技研发中心后，由需求负责人接收并创建子任务。',
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text3),
                height: 1.4,
              ),
            ),
          ),
        if (_isSub) ...[
          const SizedBox(height: 8),
          Text(
            _parentIsMine
                ? '作为主任务负责人，你创建的子任务会直接生效。'
                : '作为主任务参与人，你创建的子任务会提交给主任务负责人审核，通过后才开始执行。',
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
              height: 1.4,
            ),
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
                  color: DunesColors.resolve(context, DunesColors.text2),
                ),
                Expanded(
                  child: Text(
                    _isSub ? '添加子目标' : '新建主目标',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.resolve(context, DunesColors.text),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '使用指引',
                  onPressed: () => unawaited(_showGuide(force: true)),
                  icon: Icon(
                    Icons.help_outline,
                    color: DunesColors.resolve(context, DunesColors.text2),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _themePurple,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: DunesColors.resolve(context, Colors.white),
                          ),
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
                    color: DunesColors.resolve(
                      context,
                      Colors.white,
                      role: DunesColorRole.surface,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: DunesColors.resolve(
                        context,
                        const Color(0xFFE8EAED),
                        role: DunesColorRole.border,
                      ),
                    ),
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
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _isSub ? '添加子目标' : '新建主目标',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '使用指引',
                onPressed: () => unawaited(_showGuide(force: true)),
                icon: Icon(
                  Icons.help_outline,
                  color: DunesColors.resolve(context, DunesColors.text2),
                ),
              ),
            ],
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
                child: Text(
                  '取消',
                  style: TextStyle(
                    color: DunesColors.resolve(context, DunesColors.text2),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _themePurple,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: DunesColors.resolve(context, Colors.white),
                        ),
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
            style: TextStyle(
              fontSize: 14,
              color: DunesColors.resolve(context, DunesColors.text),
              height: 1.3,
            ),
            onChanged: (_) {
              if (_titleError != null &&
                  c == _titleCtrl &&
                  c.text.trim().isNotEmpty) {
                setState(() => _titleError = null);
              }
            },
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 14,
                color: DunesColors.resolve(
                  context,
                  DunesColors.text3,
                ).withValues(alpha: 0.85),
              ),
              filled: true,
              fillColor: hasError
                  ? DunesColors.resolve(
                      context,
                      const Color(0xFFFFF1F2),
                      role: DunesColorRole.surface,
                    )
                  : DunesColors.resolve(
                      context,
                      const Color(0xFFF5F6F8),
                      role: DunesColorRole.surface,
                    ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: hasError
                    ? BorderSide(
                        color: DunesColors.resolve(
                          context,
                          Color(0xFFE35D6A),
                          role: DunesColorRole.border,
                        ),
                      )
                    : BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: hasError
                      ? DunesColors.resolve(
                          context,
                          const Color(0xFFE35D6A),
                          role: DunesColorRole.border,
                        )
                      : DunesColors.resolve(
                          context,
                          _themePurple,
                          role: DunesColorRole.border,
                        ).withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          if (hasError) ...[
            const SizedBox(height: 6),
            Text(
              errorText,
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolveNullable(context, Color(0xFFE35D6A)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pickerField({
    required String label,
    required String value,
    Widget? leading,
    VoidCallback? onTap,
    bool placeholder = false,
    bool required = false,
  }) {
    return _Labeled(
      label: label,
      required: required,
      child: Material(
        color: DunesColors.resolve(
          context,
          const Color(0xFFF5F6F8),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 9)],
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      color: placeholder
                          ? DunesColors.resolve(context, DunesColors.text3)
                          : DunesColors.resolve(context, DunesColors.text),
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.expand_more,
                    size: 20,
                    color: DunesColors.resolve(context, DunesColors.text3),
                  ),
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
    return _Labeled(
      label: label,
      child: TaskDropdownField<String>(
        value: value,
        items: items,
        sheetTitle: '选择$label',
        forceSheet: widget.fullscreen,
        onChanged: onChanged,
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
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
            if (required)
              Text(
                ' *',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolveNullable(
                    context,
                    Color(0xFFE35D6A),
                  ),
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
