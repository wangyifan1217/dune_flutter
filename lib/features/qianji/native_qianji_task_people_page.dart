import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/widgets/horizontal_drag_scroll_view.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import '../tasks/native_task_action_page.dart';
import '../tasks/native_task_detail_page.dart';
import '../tasks/task_api.dart';
import '../tasks/task_avatar.dart';
import '../tasks/task_chat_forward.dart';
import '../tasks/task_models.dart';

const _themePurple = Color(0xFF7B5CD8);

enum TaskPeopleFocus { all, attention, doing, onTime, quiet }

class TaskPeopleRead {
  const TaskPeopleRead({
    required this.label,
    required this.focus,
    required this.why,
    required this.color,
    required this.soft,
  });

  final String label;
  final TaskPeopleFocus focus;
  final String why;
  final Color color;
  final Color soft;
}

class TaskPersonDept {
  const TaskPersonDept({required this.id, required this.name});

  final int id;
  final String name;
}

/// 某个负责人在所选月份里的任务。
class TaskPersonRollup {
  const TaskPersonRollup({
    required this.userId,
    required this.name,
    required this.departmentId,
    required this.departmentName,
    required this.tasks,
    this.avatarPreset = '',
    this.avatarObjectKey = '',
    this.avatarUrl = '',
  });

  final int userId;
  final String name;
  final int departmentId;
  final String departmentName;
  final List<TaskItem> tasks;
  final String avatarPreset;
  final String avatarObjectKey;
  final String avatarUrl;

  int get doing => tasks.where(_taskDoing).length;
  int get completed => tasks.where(_taskCompleted).length;
  int get overdue => tasks.where(_taskOverdueOpen).length;
  int get waiting => tasks.where(_taskWaiting).length;
  int get subtaskCount =>
      tasks.fold<int>(0, (sum, task) => sum + task.subtaskCount);
  int get counted => doing + completed + overdue + waiting;

  List<String> get facts {
    final open = tasks.where(
      (task) => !_taskIgnored(task) && !_taskCompleted(task),
    );
    final noAcceptance = open
        .where((task) => task.acceptanceCriteria.trim().isEmpty)
        .length;
    final noDue = open.where((task) => task.dueAt == null).length;
    final noProgress = open.where((task) => task.progressPct <= 0).length;
    final rejected = tasks.where((task) => task.status == 'rejected').length;
    return [
      if (noAcceptance > 0) '无验收 $noAcceptance',
      if (noDue > 0) '无截止 $noDue',
      if (noProgress > 0) '无进展 $noProgress',
      if (waiting > 0) '待确认 $waiting',
      if (rejected > 0) '已驳回 $rejected',
    ];
  }
}

class TaskPeopleSnapshot {
  const TaskPeopleSnapshot({required this.departments, required this.people});

  final List<TaskPersonDept> departments;
  final List<TaskPersonRollup> people;
}

typedef TaskPeopleSnapshotLoader =
    Future<TaskPeopleSnapshot> Function(DateTime month);

bool _taskIgnored(TaskItem task) =>
    task.status == 'cancelled' || task.status == 'draft';

bool _taskCompleted(TaskItem task) => task.status == 'completed';

bool _taskOverdueOpen(TaskItem task) =>
    !_taskIgnored(task) && !_taskCompleted(task) && task.overdue;

bool _taskWaiting(TaskItem task) =>
    !_taskIgnored(task) &&
    !_taskCompleted(task) &&
    !_taskOverdueOpen(task) &&
    (task.isPending || task.hasPendingChange);

bool _taskDoing(TaskItem task) =>
    !_taskIgnored(task) &&
    !_taskCompleted(task) &&
    !_taskOverdueOpen(task) &&
    !_taskWaiting(task) &&
    task.status != 'rejected';

/// 按负责人把任务收成一人一张卡。同一人出现在多个部门时，归到任务更多的部门。
List<TaskPersonRollup> groupTaskPeople(
  List<TaskItem> tasks, {
  Map<int, String> departmentNames = const {},
  Map<int, TaskAssignee> avatars = const {},
}) {
  final byOwner = <int, List<TaskItem>>{};
  for (final task in tasks) {
    if (_taskIgnored(task)) continue;
    byOwner.putIfAbsent(task.ownerUserId, () => []).add(task);
  }
  final people = <TaskPersonRollup>[];
  for (final entry in byOwner.entries) {
    final rows = entry.value;
    final name = rows
        .map((task) => task.ownerName.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final counts = <int, int>{};
    for (final task in rows) {
      final deptId = task.departmentId;
      if (deptId == null || deptId <= 0) continue;
      counts[deptId] = (counts[deptId] ?? 0) + 1;
    }
    var departmentId = 0;
    var best = -1;
    for (final item in counts.entries) {
      if (item.value > best) {
        best = item.value;
        departmentId = item.key;
      }
    }
    final departmentName =
        departmentNames[departmentId] ??
        (departmentId <= 0 ? '' : '部门 $departmentId');
    final avatar = _personAvatar(rows, avatars[entry.key]);
    people.add(
      TaskPersonRollup(
        userId: entry.key,
        name: name,
        departmentId: departmentId,
        departmentName: departmentName,
        tasks: rows,
        avatarPreset: avatar.$1,
        avatarObjectKey: avatar.$2,
        avatarUrl: avatar.$3,
      ),
    );
  }
  return people;
}

(String, String, String) _personAvatar(
  List<TaskItem> tasks,
  TaskAssignee? assignee,
) {
  String preset = '';
  String objectKey = '';
  String url = '';
  void take(String nextPreset, String nextKey, String nextUrl) {
    if (preset.isEmpty && nextPreset.trim().isNotEmpty)
      preset = nextPreset.trim();
    if (objectKey.isEmpty && nextKey.trim().isNotEmpty)
      objectKey = nextKey.trim();
    if (url.isEmpty && nextUrl.trim().isNotEmpty) url = nextUrl.trim();
  }

  for (final task in tasks) {
    take(
      task.ownerAvatarPreset,
      task.ownerAvatarObjectKey,
      task.ownerAvatarUrl,
    );
  }
  if (assignee != null) {
    take(assignee.avatarPreset, assignee.avatarObjectKey, assignee.avatarUrl);
  }
  return (preset, objectKey, url);
}

TaskPeopleRead taskPeopleRead(TaskPersonRollup person) {
  if (person.overdue > 0) {
    return TaskPeopleRead(
      label: '超期未结',
      focus: TaskPeopleFocus.attention,
      why: '有 ${person.overdue} 件已过截止日还没办结',
      color: DunesColors.coral,
      soft: DunesColors.coralSoft,
    );
  }
  if (person.waiting > 0 && person.doing == 0) {
    return TaskPeopleRead(
      label: '待确认',
      focus: TaskPeopleFocus.doing,
      why: '有 ${person.waiting} 件还在等确认或接收',
      color: DunesColors.amber,
      soft: DunesColors.amberSoft,
    );
  }
  if (person.doing > 0 || person.waiting > 0) {
    return TaskPeopleRead(
      label: '在办',
      focus: TaskPeopleFocus.doing,
      why: person.waiting > 0
          ? '有 ${person.doing} 件在办，${person.waiting} 件待确认'
          : '有 ${person.doing} 件还在办',
      color: DunesColors.blue,
      soft: DunesColors.blueSoft,
    );
  }
  if (person.completed > 0) {
    return const TaskPeopleRead(
      label: '按期',
      focus: TaskPeopleFocus.onTime,
      why: '这个月的任务已经办完，没有超期',
      color: DunesColors.green,
      soft: DunesColors.greenSoft,
    );
  }
  return const TaskPeopleRead(
    label: '本月少事',
    focus: TaskPeopleFocus.quiet,
    why: '这个月名下没有在办的任务',
    color: DunesColors.text2,
    soft: Color(0xFFF3F4F6),
  );
}

Future<TaskPeopleSnapshot> loadTaskPeopleSnapshot(
  TaskApi api,
  DateTime month,
) async {
  final from = DateTime(month.year, month.month, 1);
  final to = DateTime(month.year, month.month + 1, 0);
  final deptsFuture = api.hrbpOverview(
    dateFrom: from,
    dateTo: to,
    forLookup: true,
  );
  final assigneesFuture = api.listAssignees(scope: 'reports');
  final depts = await deptsFuture;
  List<TaskAssignee> assignees = const [];
  try {
    assignees = await assigneesFuture;
  } catch (_) {
    assignees = const [];
  }
  final names = <int, String>{
    for (final dept in depts)
      dept.departmentId: dept.departmentName.trim().isEmpty
          ? '部门 ${dept.departmentId}'
          : dept.departmentName.trim(),
  };
  final pages = await Future.wait(
    depts.map((dept) => _loadDepartmentTasks(api, dept.departmentId, from, to)),
  );
  final tasks = <TaskItem>[];
  final seen = <int>{};
  for (final page in pages) {
    for (final task in page) {
      if (task.id > 0 && !seen.add(task.id)) continue;
      tasks.add(task);
    }
  }
  return TaskPeopleSnapshot(
    departments: [
      for (final dept in depts)
        TaskPersonDept(
          id: dept.departmentId,
          name: names[dept.departmentId] ?? '部门 ${dept.departmentId}',
        ),
    ],
    people: groupTaskPeople(
      tasks,
      departmentNames: names,
      avatars: {for (final user in assignees) user.id: user},
    ),
  );
}

Future<List<TaskItem>> _loadDepartmentTasks(
  TaskApi api,
  int departmentId,
  DateTime from,
  DateTime to,
) async {
  final out = <TaskItem>[];
  for (var page = 0; page < 20; page++) {
    final result = await api.hrbpDepartmentPage(
      departmentId,
      dateFrom: from,
      dateTo: to,
      page: page,
      size: 100,
      forLookup: true,
    );
    out.addAll(result.items);
    if (!result.hasMore || result.items.isEmpty) break;
  }
  return out;
}

/// 业务查阅 · 任务：按员工看所选月份的任务状态。
class NativeQianjiTaskPeoplePage extends StatefulWidget {
  const NativeQianjiTaskPeoplePage({
    super.key,
    required this.session,
    required this.onBack,
    this.loadSnapshot,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final TaskPeopleSnapshotLoader? loadSnapshot;

  @override
  State<NativeQianjiTaskPeoplePage> createState() =>
      _NativeQianjiTaskPeoplePageState();
}

class _NativeQianjiTaskPeoplePageState
    extends State<NativeQianjiTaskPeoplePage> {
  TaskApi? _api;
  final TextEditingController _keywordCtrl = TextEditingController();
  final Set<int> _expanded = <int>{};

  TaskPeopleSnapshot? _snapshot;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int? _departmentId;
  TaskPeopleFocus _focus = TaskPeopleFocus.all;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.loadSnapshot == null) _api = TaskApi(widget.session);
    _keywordCtrl.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = widget.loadSnapshot != null
          ? await widget.loadSnapshot!(_month)
          : await loadTaskPeopleSnapshot(_api!, _month);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _expanded.clear();
        if (_departmentId != null &&
            !snapshot.departments.any((dept) => dept.id == _departmentId) &&
            !snapshot.people.any(
              (person) => person.departmentId == _departmentId,
            )) {
          _departmentId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TaskItem> _shareableGoals(TaskPersonRollup person) {
    final saved = person.tasks
        .where((task) => task.id > 0)
        .toList(growable: false);
    final mains = saved.where((task) => task.isMain).toList(growable: false);
    return mains.isNotEmpty ? mains : saved;
  }

  Future<void> _shareTask(TaskItem task) => forwardTaskToConversation(
    context: context,
    session: widget.session,
    task: task,
  );

  Future<void> _sharePerson(TaskPersonRollup person) async {
    final tasks = _shareableGoals(person);
    if (tasks.isEmpty) {
      showDunesCenterToast(context, '这个人没有可转发的主目标');
      return;
    }
    if (tasks.length == 1) {
      await _shareTask(tasks.first);
      return;
    }
    await forwardTasksToConversation(
      context: context,
      session: widget.session,
      tasks: tasks,
      ownerName: person.name,
    );
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final now = DateTime.now();
    if (next.isAfter(DateTime(now.year, now.month))) return;
    setState(() => _month = next);
    unawaited(_load());
  }

  List<TaskPersonRollup> get _people {
    final snapshot = _snapshot;
    if (snapshot == null) return const [];
    final keyword = _keywordCtrl.text.trim();
    final rows = snapshot.people.where((person) {
      if (_departmentId != null && person.departmentId != _departmentId) {
        return false;
      }
      if (_focus != TaskPeopleFocus.all &&
          taskPeopleRead(person).focus != _focus) {
        return false;
      }
      if (keyword.isEmpty) return true;
      final haystack = [
        person.name,
        person.departmentName,
        for (final task in person.tasks) task.title,
      ].join(' ');
      return haystack.contains(keyword);
    }).toList();
    rows.sort((a, b) {
      final rank = _focusRank(
        taskPeopleRead(a).focus,
      ).compareTo(_focusRank(taskPeopleRead(b).focus));
      if (rank != 0) return rank;
      final overdue = b.overdue.compareTo(a.overdue);
      if (overdue != 0) return overdue;
      final doing = b.doing.compareTo(a.doing);
      if (doing != 0) return doing;
      return a.name.compareTo(b.name);
    });
    return rows;
  }

  int _focusRank(TaskPeopleFocus focus) => switch (focus) {
    TaskPeopleFocus.attention => 0,
    TaskPeopleFocus.doing => 1,
    TaskPeopleFocus.onTime => 2,
    TaskPeopleFocus.quiet => 3,
    TaskPeopleFocus.all => 4,
  };

  @override
  Widget build(BuildContext context) {
    final people = _people;
    return ColoredBox(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF5F6F8),
        role: DunesColorRole.surface,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            _toolbar(),
            if (!_loading && _error == null) ...[
              _focusChips(people.length),
              _summary(people),
            ],
            Expanded(child: _body(people)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 4),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onBack,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_ios_new,
                    size: 14,
                    color: DunesColors.resolve(context, DunesColors.text2),
                  ),
                  SizedBox(width: 2),
                  Text(
                    '饕',
                    style: TextStyle(
                      fontSize: 13,
                      color: DunesColors.resolve(context, DunesColors.text2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '任务',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolveNullable(context, _themePurple),
              ),
            ),
          ),
          _monthButton(Icons.chevron_left, () => _shiftMonth(-1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${_month.year}年${_month.month}月',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          _monthButton(
            Icons.chevron_right,
            _isCurrentMonth ? null : () => _shiftMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _monthButton(IconData icon, VoidCallback? onTap) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 18,
        color: onTap == null
            ? DunesColors.resolve(context, DunesColors.text3)
            : DunesColors.resolve(context, DunesColors.text2),
      ),
    );
  }

  Widget _toolbar() {
    final departments = _snapshot?.departments ?? const <TaskPersonDept>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _keywordCtrl,
            decoration: InputDecoration(
              hintText: '搜索员工、部门、任务',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _keywordCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: _keywordCtrl.clear,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
              filled: true,
              fillColor: DunesColors.resolve(
                context,
                Colors.white,
                role: DunesColorRole.surface,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: _fieldBorder(
                DunesColors.resolve(
                  context,
                  const Color(0xFFE8EAED),
                  role: DunesColorRole.border,
                ),
              ),
              enabledBorder: _fieldBorder(
                DunesColors.resolve(
                  context,
                  const Color(0xFFE8EAED),
                  role: DunesColorRole.border,
                ),
              ),
              focusedBorder: _fieldBorder(
                DunesColors.resolve(
                  context,
                  _themePurple,
                  role: DunesColorRole.border,
                ),
              ),
            ),
          ),
          if (departments.isNotEmpty) ...[
            const SizedBox(height: 8),
            HorizontalDragScrollView(
              child: Row(
                children: [
                  _chip(
                    label: '全部部门',
                    selected: _departmentId == null,
                    onTap: () => setState(() => _departmentId = null),
                  ),
                  for (final dept in departments) ...[
                    const SizedBox(width: 8),
                    _chip(
                      label: dept.name,
                      selected: _departmentId == dept.id,
                      onTap: () => setState(() => _departmentId = dept.id),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  OutlineInputBorder _fieldBorder(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: DunesColors.resolve(context, color, role: DunesColorRole.border),
      ),
    );
  }

  Widget _focusChips(int shown) {
    final options = <(TaskPeopleFocus, String)>[
      (TaskPeopleFocus.all, '全部'),
      (TaskPeopleFocus.attention, '需关注'),
      (TaskPeopleFocus.doing, '在办'),
      (TaskPeopleFocus.onTime, '按期'),
      (TaskPeopleFocus.quiet, '本月少事'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: HorizontalDragScrollView(
              child: Row(
                children: [
                  for (final option in options) ...[
                    _chip(
                      label: option.$2,
                      selected: _focus == option.$1,
                      onTap: () => setState(() => _focus = option.$1),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ),
          Text(
            '$shown 人',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? DunesColors.resolve(
              context,
              const Color(0xFFF0EEF7),
              role: DunesColorRole.surface,
            )
          : DunesColors.resolve(
              context,
              Colors.white,
              role: DunesColorRole.surface,
            ),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? DunesColors.resolve(
                      context,
                      _themePurple,
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      const Color(0xFFE8EAED),
                      role: DunesColorRole.border,
                    ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? DunesColors.resolve(context, _themePurple)
                  : DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summary(List<TaskPersonRollup> people) {
    final doing = people.fold<int>(0, (sum, person) => sum + person.doing);
    final done = people.fold<int>(0, (sum, person) => sum + person.completed);
    final overdue = people.fold<int>(0, (sum, person) => sum + person.overdue);
    final waiting = people.fold<int>(0, (sum, person) => sum + person.waiting);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          _stat(
            '$doing',
            '进行中',
            DunesColors.resolve(context, DunesColors.blue),
          ),
          const SizedBox(width: 8),
          _stat(
            '$done',
            '已完成',
            DunesColors.resolve(context, DunesColors.green),
          ),
          const SizedBox(width: 8),
          _stat(
            '$overdue',
            '超期',
            DunesColors.resolve(context, DunesColors.coral),
          ),
          const SizedBox(width: 8),
          _stat(
            '$waiting',
            '待确认',
            DunesColors.resolve(context, DunesColors.amber),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              const Color(0xFFE8EAED),
              role: DunesColorRole.border,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolveNullable(context, color),
                height: 1.05,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(List<TaskPersonRollup> people) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: _themePurple),
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 80),
          Text(
            friendlyErrorText(_error, fallback: '加载失败，请稍后重试'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(onPressed: _load, child: const Text('重试')),
          ),
        ],
      );
    }
    if (people.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 120),
          Center(
            child: Text(
              '这个范围内暂无任务',
              style: TextStyle(
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      color: _themePurple,
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 0, 16, isDesktopCommOnly ? 48 : 28),
        itemCount: people.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _personCard(people[index]),
      ),
    );
  }

  Widget _personCard(TaskPersonRollup person) {
    final read = taskPeopleRead(person);
    final expanded = _expanded.contains(person.userId);
    final total = person.counted;
    final doneRate = total <= 0
        ? 0
        : (person.completed / total).clamp(0.0, 1.0);
    final ordered = [...person.tasks]..sort(_compareTasks);
    final shareable = _shareableGoals(person);
    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          if (expanded) {
            _expanded.remove(person.userId);
          } else {
            _expanded.add(person.userId);
          }
        }),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                const Color(0xFFE8EAED),
                role: DunesColorRole.border,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  buildTaskUserAvatar(
                    session: widget.session,
                    name: person.name,
                    userId: person.userId,
                    avatarPreset: person.avatarPreset,
                    avatarObjectKey: person.avatarObjectKey,
                    avatarUrl: person.avatarUrl,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                person.name.isEmpty ? '未指定负责人' : person.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _pill(read.label, read.color, read.soft),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (person.departmentName.isNotEmpty)
                              person.departmentName,
                            if (total > 0) '完成 ${(doneRate * 100).round()}%',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (shareable.isNotEmpty)
                    IconButton(
                      tooltip: shareable.length > 1 ? '合并转发此人的主目标' : '转发到 IM',
                      onPressed: () => unawaited(_sharePerson(person)),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      padding: const EdgeInsets.all(6),
                      icon: Icon(
                        Icons.ios_share_rounded,
                        size: 18,
                        color: DunesColors.resolveNullable(
                          context,
                          _themePurple,
                        ),
                      ),
                    ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: DunesColors.resolve(context, DunesColors.text3),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                read.why,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: DunesColors.resolve(context, DunesColors.text),
                ),
              ),
              const SizedBox(height: 10),
              _bar(person),
              const SizedBox(height: 10),
              Row(
                children: [
                  _count(
                    person.doing,
                    '进行中',
                    DunesColors.resolve(context, DunesColors.blue),
                  ),
                  _count(
                    person.completed,
                    '已完成',
                    DunesColors.resolve(context, DunesColors.green),
                  ),
                  _count(
                    person.overdue,
                    '超期',
                    DunesColors.resolve(context, DunesColors.coral),
                  ),
                  _count(
                    person.subtaskCount,
                    '子任务',
                    DunesColors.resolve(context, _themePurple),
                  ),
                ],
              ),
              if (person.facts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final fact in person.facts)
                      _pill(
                        fact,
                        DunesColors.resolve(context, DunesColors.text2),
                        DunesColors.resolve(context, const Color(0xFFF3F4F6)),
                      ),
                  ],
                ),
              ],
              if (expanded) ...[
                const SizedBox(height: 10),
                Divider(
                  height: 1,
                  color: DunesColors.resolve(
                    context,
                    Color(0xFFE8EAED),
                    role: DunesColorRole.border,
                  ),
                ),
                const SizedBox(height: 8),
                if (ordered.isEmpty)
                  Text(
                    '这个月没有任务明细',
                    style: TextStyle(
                      fontSize: 12,
                      color: DunesColors.resolve(context, DunesColors.text3),
                    ),
                  )
                else
                  for (final task in ordered) _taskRow(task),
              ],
            ],
          ),
        ),
      ),
    );
  }

  int _compareTasks(TaskItem a, TaskItem b) {
    int rank(TaskItem task) {
      if (_taskOverdueOpen(task)) return 0;
      if (_taskWaiting(task)) return 1;
      if (_taskDoing(task)) return 2;
      if (_taskCompleted(task)) return 4;
      return 3;
    }

    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    return a.title.compareTo(b.title);
  }

  Widget _pill(String label, Color color, Color soft) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: DunesColors.resolveNullable(
          context,
          soft,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: DunesColors.resolveNullable(context, color),
        ),
      ),
    );
  }

  Widget _bar(TaskPersonRollup person) {
    final slices = <(int, Color)>[
      (person.completed, DunesColors.resolve(context, DunesColors.green)),
      (person.doing, DunesColors.resolve(context, DunesColors.blue)),
      (person.overdue, DunesColors.resolve(context, DunesColors.coral)),
      (person.waiting, DunesColors.resolve(context, DunesColors.amber)),
    ];
    final sum = slices.fold<int>(0, (total, slice) => total + slice.$1);
    if (sum <= 0) {
      return Container(
        height: 8,
        decoration: BoxDecoration(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE8EAED),
            role: DunesColorRole.surface,
          ),
          borderRadius: BorderRadius.circular(99),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            for (final slice in slices)
              if (slice.$1 > 0)
                Expanded(
                  flex: slice.$1,
                  child: ColoredBox(
                    color: DunesColors.resolve(
                      context,
                      slice.$2,
                      role: DunesColorRole.surface,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _count(int value, String label, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: DunesColors.resolveNullable(context, color),
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _taskRow(TaskItem task) {
    final (label, color, soft) = _taskPill(task);
    final hint = [
      if (task.parentTitle.trim().isNotEmpty) '主目标 ${task.parentTitle.trim()}',
      if (task.dueAt != null) '截止 ${formatTaskYmd(task.dueAt)}',
      '进度 ${task.progressPct}%',
    ].join(' · ');
    return InkWell(
      onTap: task.id > 0 ? () => _openTask(task.id) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pill(label, color, soft),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title.trim().isEmpty ? '未命名任务' : task.title.trim(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    hint,
                    style: TextStyle(
                      fontSize: 12,
                      color: DunesColors.resolve(context, DunesColors.text3),
                    ),
                  ),
                ],
              ),
            ),
            if (task.id > 0)
              IconButton(
                tooltip: '转发到 IM',
                onPressed: () => unawaited(_shareTask(task)),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.ios_share_rounded,
                  size: 16,
                  color: DunesColors.resolveNullable(context, _themePurple),
                ),
              ),
            if (task.id > 0)
              Icon(
                Icons.chevron_right,
                size: 16,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
          ],
        ),
      ),
    );
  }

  (String, Color, Color) _taskPill(TaskItem task) {
    if (_taskOverdueOpen(task)) {
      return (
        '已超期',
        DunesColors.resolve(context, DunesColors.coral),
        DunesColors.resolve(context, DunesColors.coralSoft),
      );
    }
    if (_taskWaiting(task)) {
      return (
        taskStatusLabel(task.status),
        DunesColors.resolve(context, DunesColors.amber),
        DunesColors.resolve(context, DunesColors.amberSoft),
      );
    }
    if (_taskCompleted(task)) {
      return (
        '已完成',
        DunesColors.resolve(context, DunesColors.green),
        DunesColors.resolve(context, DunesColors.greenSoft),
      );
    }
    return (
      taskStatusLabel(task.status),
      DunesColors.resolve(context, DunesColors.blue),
      DunesColors.resolve(context, DunesColors.blueSoft),
    );
  }

  void _openTask(int taskId) {
    if (taskId <= 0) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Material(
          color: DunesColors.resolve(
            ctx,
            DunesColors.bgApp,
            role: DunesColorRole.surface,
          ),
          child: NativeTaskDetailView(
            session: widget.session,
            taskId: taskId,
            backLabel: '任务',
            onBack: () => Navigator.of(ctx).pop(),
            onOpenTask: (id) => _openTask(id),
            onOpenProgress: (task) =>
                _openAction(ctx, task, TaskActionMode.progress),
            onOpenEvaluate: (task) =>
                _openAction(ctx, task, TaskActionMode.evaluate),
          ),
        ),
      ),
    );
  }

  void _openAction(BuildContext ctx, TaskItem task, TaskActionMode mode) {
    Navigator.of(ctx).push(
      MaterialPageRoute<void>(
        builder: (pageCtx) => Material(
          color: DunesColors.resolve(
            ctx,
            DunesColors.bgApp,
            role: DunesColorRole.surface,
          ),
          child: NativeTaskActionView(
            session: widget.session,
            task: task,
            mode: mode,
            onBack: () => Navigator.of(pageCtx).pop(),
            onDone: () => Navigator.of(pageCtx).pop(),
          ),
        ),
      ),
    );
  }
}
