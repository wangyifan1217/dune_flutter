import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'hr_performance_detail.dart';
import 'hr_performance_sheets.dart';
import '../chat/user_avatar_widget.dart';
import '../contacts/contact_models.dart';
import '../contacts/contact_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../shell/dunes_toast.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'hr_performance_service.dart';
import 'hr_performance_template_ui.dart';

const _hrPageBg = Color(0xFFF7F4FC);
const _hrLine = Color(0xFFECE7F3);
const _hrTabular = <FontFeature>[FontFeature.tabularFigures()];
const _hrStageFlow = [
  'opening',
  'indicators',
  'self',
  'review',
  'calibration',
  'hr',
  'final',
  'result',
  'interview',
];
const _hrStageAside = ['archived', 'exempt'];
const _hrStageShort = <String, String>{
  'opening': '待补配',
  'self': '自评',
  'indicators': '待发起',
  'review': '主管初评',
  'calibration': '绩效校准',
  'hr': 'HR 审核',
  'final': '终审',
  'result': '结果确认',
  'interview': '面谈',
  'archived': '已归档',
  'exempt': '免考核',
};
const _hrStageColors = <String, Color>{
  'opening': Color(0xFF8E7CC3),
  'self': Color(0xFF5B6EE1),
  'indicators': Color(0xFF4C86E0),
  'review': Color(0xFF7B5CD8),
  'calibration': Color(0xFF2F9E8F),
  'hr': Color(0xFF3E8E5A),
  'final': Color(0xFFD0892B),
  'result': Color(0xFFE06A4A),
  'interview': Color(0xFFC45B8A),
  'archived': Color(0xFF8B8794),
  'exempt': Color(0xFFA08A62),
};
const _hrStageFallback = Color(0xFF7A8494);

bool hrPerformanceExcludedLeader(String name) {
  switch (name.replaceAll(RegExp(r'\s'), '')) {
    case '许正阳':
    case '郑咏熹':
      return true;
    default:
      return false;
  }
}

bool hrPerformanceExcludedDepartmentName(String name) =>
    name.replaceAll(RegExp(r'\s'), '') == '数字化解决方案中心';

bool hrPerformanceDepartmentExcluded({
  required int? departmentId,
  required String departmentName,
  required Map<int, int?> parents,
  required Map<int, String> names,
}) {
  if (hrPerformanceExcludedDepartmentName(departmentName)) return true;
  var id = departmentId;
  final seen = <int>{};
  while (id != null && seen.add(id)) {
    if (hrPerformanceExcludedDepartmentName(names[id] ?? '')) return true;
    id = parents[id];
  }
  return false;
}

String _hrStageName(String id) =>
    _hrStageShort[id] ?? hrPerformanceStageLabels[id] ?? id;

String? _hrStageTooltip(String id) {
  final full = hrPerformanceStageLabels[id] ?? id;
  return full == _hrStageName(id) ? null : full;
}

class NativeHrPerformancePage extends StatefulWidget {
  const NativeHrPerformancePage({
    super.key,
    required this.session,
    this.service,
    this.conversationService,
    this.initialMonth,
    this.initialRecordId,
  });
  final AuthSession session;
  final HrPerformanceService? service;
  final ConversationService? conversationService;
  final String? initialMonth;
  final int? initialRecordId;
  @override
  State<NativeHrPerformancePage> createState() =>
      _NativeHrPerformancePageState();
}

class _NativeHrPerformancePageState extends State<NativeHrPerformancePage> {
  late final _service = widget.service ?? HrPerformanceService(widget.session);
  late final _avatars = ConversationService(session: widget.session);
  late DateTime _month;
  List<NativeDepartment> _orgDepartments = const [];
  Map<int, NativeContact> _orgPeople = const {};
  final Map<int, int?> _deptParent = {};
  final Map<int, String> _deptName = {};
  final Map<int, int> _userDept = {};
  final Set<String> _collapsedRoster = {};
  HrPerformanceAccess _access = const HrPerformanceAccess();
  List<HrPerformanceRecord> _records = [];
  HrPerformanceRecord? _selected;
  final Set<int> _selectedIds = {};
  List<Map<String, dynamic>> _alerts = [];
  bool _busy = false;
  bool _rosterCollapsed = false;
  bool _filtersCollapsed = false;
  String? _grade;
  String _scope = 'mine';
  String _query = '';
  String? _stage;
  String? _department;
  String? _tag;
  String? _error;
  bool _loading = true;
  bool _monthStarted = true;
  bool _canStartMonth = false;
  bool _supportsBatchStart = false;
  int _epoch = 0;
  final Map<String, GlobalKey> _stageChipKeys = {};

  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
  int? _pendingSelectId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    _month = DateTime(now.year, now.month - 1);
    final month = RegExp(
      r'^(\d{4})-(\d{2})$',
    ).firstMatch(widget.initialMonth ?? '');
    if (month != null) {
      _month = DateTime(int.parse(month.group(1)!), int.parse(month.group(2)!));
    }
    _pendingSelectId = widget.initialRecordId;
    _load();
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<Object>([
        _service.access(),
        _service.records(_monthKey, _scope),
        _service.alerts(),
      ]);
      final access = results[0] as HrPerformanceAccess;
      var scope = _scope;
      var fetched = results[1] as List<HrPerformanceRecord>;
      final pendingId = _pendingSelectId;
      if (pendingId != null && !fetched.any((r) => r.id == pendingId)) {
        for (final candidate in [
          if (access.all) 'all',
          if (access.team) 'team',
          if (access.allowed) 'todo',
        ]) {
          if (candidate == scope) continue;
          final candidates = await _service.records(_monthKey, candidate);
          if (candidates.any((r) => r.id == pendingId)) {
            scope = candidate;
            fetched = candidates;
            break;
          }
        }
      }
      var started = true;
      var canStart = false;
      var supportsBatch = false;
      if (widget.service == null || access.hr) {
        try {
          final status = await _service.monthStatus(_monthKey);
          started = status.started;
          canStart = status.canStart;
          supportsBatch = status.supportsBatch;
        } catch (_) {}
      }
      if (widget.service == null) await _loadOrg();
      if (!mounted || epoch != _epoch) return;
      final rows = fetched
          .where(
            (r) =>
                !hrPerformanceExcludedLeader(r.name) &&
                !hrPerformanceDepartmentExcluded(
                  departmentId: _userDept[r.userId],
                  departmentName: r.department,
                  parents: _deptParent,
                  names: _deptName,
                ),
          )
          .toList();
      setState(() {
        _access = access;
        _scope = scope;
        _monthStarted = started;
        _canStartMonth = canStart;
        _supportsBatchStart = supportsBatch;
        _records = rows;
        _alerts = results[2] as List<Map<String, dynamic>>;
        _selectedIds.removeWhere((id) => !rows.any((r) => r.id == id));
        final preferred = _pendingSelectId ?? _selected?.id;
        _pendingSelectId = null;
        final matches = rows.where((r) => r.id == preferred);
        _selected = matches.isEmpty
            ? (rows.isEmpty ? null : rows.first)
            : matches.first;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _monthStarted = true;
        _canStartMonth = false;
        _records = [];
        _selected = null;
      });
    }
  }

  Future<void> _loadOrg() async {
    try {
      final org = await ContactService(
        session: widget.session,
      ).fetchOrgContacts();
      final people = <int, NativeContact>{};
      _deptParent.clear();
      _deptName.clear();
      _userDept.clear();
      void walk(NativeDepartment department, int? parent) {
        _deptParent[department.id] = parent;
        _deptName[department.id] = department.name.trim();
        for (final user in department.users) {
          people[user.userId] = user;
          _userDept[user.userId] = department.id;
        }
        for (final child in department.children) {
          walk(child, department.id);
        }
      }

      for (final department in org.departments) {
        walk(department, null);
      }
      _orgDepartments = org.departments;
      _orgPeople = people;
    } catch (_) {}
  }

  bool _supervisorInPresidentOffice(int? supervisorId) {
    var department = supervisorId == null ? null : _userDept[supervisorId];
    final seen = <int>{};
    while (department != null && seen.add(department)) {
      if (_deptName[department] == '总裁办') return true;
      department = _deptParent[department];
    }
    return false;
  }

  List<_HrRosterDept> _rosterTree(List<HrPerformanceRecord> rows) {
    final pending = {for (final row in rows) row.userId: row};
    _HrRosterDept? take(NativeDepartment department) {
      final people = <HrPerformanceRecord>[];
      for (final user in department.users) {
        final record = pending.remove(user.userId);
        if (record != null) people.add(record);
      }
      people.sort((a, b) => a.name.compareTo(b.name));
      final children = <_HrRosterDept>[];
      for (final child in department.children) {
        final node = take(child);
        if (node != null) children.add(node);
      }
      if (people.isEmpty && children.isEmpty) return null;
      return _HrRosterDept(
        'dept-${department.id}',
        department.name,
        people,
        children,
      );
    }

    final roots = <_HrRosterDept>[];
    for (final department in _orgDepartments) {
      final node = take(department);
      if (node != null) roots.add(node);
    }
    if (pending.isNotEmpty) {
      final grouped = <String, List<HrPerformanceRecord>>{};
      for (final record in pending.values) {
        final name = record.department.trim().isEmpty
            ? '未分配部门'
            : record.department.trim();
        grouped.putIfAbsent(name, () => []).add(record);
      }
      final names = grouped.keys.toList()..sort();
      for (final name in names) {
        final people = grouped[name]!..sort((a, b) => a.name.compareTo(b.name));
        roots.add(_HrRosterDept('name-$name', name, people, const []));
      }
    }
    return roots;
  }

  List<Object> get _rosterItems {
    final items = <Object>[];
    void walk(_HrRosterDept node, int depth) {
      items.add(_HrRosterHeader(node, depth));
      if (_query.isEmpty && _collapsedRoster.contains(node.key)) return;
      for (final child in node.children) {
        walk(child, depth + 1);
      }
      for (final person in node.people) {
        items.add(_HrRosterPerson(person, depth + 1));
      }
    }

    for (final node in _rosterTree(_visible)) {
      walk(node, 0);
    }
    return items;
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _selected = null;
      _records = [];
      _department = null;
      _stage = null;
      _tag = null;
      _grade = null;
      _selectedIds.clear();
    });
    _load();
  }

  void _selectStage(String? stage) {
    final next = stage != null && stage == _stage ? null : stage;
    setState(() => _stage = next);
    final id = next ?? 'all';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _stageChipKeys[id]?.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.15,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  GlobalKey _stageChipKey(String id) =>
      _stageChipKeys.putIfAbsent(id, GlobalKey.new);

  Color get _purple => DunesColors.resolve(context, DunesColors.brandPurple);
  bool _matchesStagePool(HrPerformanceRecord r) =>
      (_query.isEmpty ||
          '${r.name} ${r.department} ${r.position}'.contains(_query)) &&
      (_grade == null || (r.scoresVisible && r.snapshot['grade'] == _grade)) &&
      (_department == null || r.department == _department) &&
      (_tag == null ||
          (_tag == 'probation' && r.probation) ||
          (_tag == 'eligible' && r.exemptionEligible) ||
          (_tag == 'blocked' && r.blockers.isNotEmpty));
  List<HrPerformanceRecord> get _stagePool =>
      _records.where(_matchesStagePool).toList();
  List<HrPerformanceRecord> get _visible =>
      _stagePool.where((r) => _stage == null || r.stage == _stage).toList();

  List<HrPerformanceRecord> get _operationRows => _selectedIds.isEmpty
      ? _visible
      : _visible.where((r) => _selectedIds.contains(r.id)).toList();

  List<HrPerformanceRecord> _deptRecords(_HrRosterDept node) {
    final people = <HrPerformanceRecord>[...node.people];
    for (final child in node.children) {
      people.addAll(_deptRecords(child));
    }
    return people;
  }

  bool? _deptChecked(_HrRosterDept node) {
    final ids = _deptRecords(node).map((r) => r.id).toList();
    if (ids.isEmpty) return false;
    final selected = ids.where(_selectedIds.contains).length;
    if (selected == 0) return false;
    if (selected == ids.length) return true;
    return null;
  }

  void _toggleDept(_HrRosterDept node) {
    final ids = _deptRecords(node).map((r) => r.id);
    final clear = _deptChecked(node) == true;
    setState(() {
      if (clear) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  Widget _rosterHeader(_HrRosterHeader item) {
    final collapsed =
        _query.isEmpty && _collapsedRoster.contains(item.dept.key);
    final indent = item.depth.clamp(0, 4) * 10.0;
    final topLevel = item.depth == 0;
    final muted = DunesColors.resolve(context, DunesColors.text3);
    return Padding(
      padding: EdgeInsets.only(left: indent, top: topLevel ? 10 : 3, bottom: 3),
      child: Container(
        decoration: BoxDecoration(
          color: DunesColors.resolve(
            context,
            topLevel ? const Color(0xFFEEE9F7) : const Color(0xFFF7F4FC),
            role: DunesColorRole.surface,
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            if (_access.allowed)
              SizedBox(
                width: 36,
                height: 38,
                child: Checkbox(
                  key: ValueKey('hr-dept-select-${item.dept.key}'),
                  tristate: true,
                  value: _deptChecked(item.dept),
                  activeColor: _purple,
                  checkColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                  side: BorderSide(
                    color: DunesColors.resolve(
                      context,
                      const Color(0xFFC8BDDA),
                      role: DunesColorRole.border,
                    ),
                    width: 1.3,
                  ),
                  overlayColor: WidgetStatePropertyAll(
                    _purple.withValues(alpha: 0.10),
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  semanticLabel: '选择${item.dept.name}及下级',
                  onChanged: _busy ? null : (_) => _toggleDept(item.dept),
                ),
              ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => setState(() {
                  if (_collapsedRoster.contains(item.dept.key)) {
                    _collapsedRoster.remove(item.dept.key);
                  } else {
                    _collapsedRoster.add(item.dept.key);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 9, 10, 9),
                  child: Row(
                    children: [
                      Icon(
                        collapsed
                            ? Icons.chevron_right_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                        color: muted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.dept.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${item.dept.total} 人',
                        style: TextStyle(
                          fontSize: 11,
                          fontFeatures: _hrTabular,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rosterPerson(_HrRosterPerson item, bool wide) {
    final r = item.record;
    final selected = wide && _selected?.id == r.id;
    final contact = _orgPeople[r.userId];
    final indent = item.depth.clamp(0, 5) * 10.0;
    final initial = r.name.trim().isEmpty ? '?' : r.name.trim().substring(0, 1);
    final subtitle = [
      if (r.todoGroups.isNotEmpty) r.todoGroups.join(' / ') else r.stageLabel,
      if (r.stage != 'self' &&
          _supervisorInPresidentOffice(r.directSupervisorId))
        '启动后先自评',
      if (r.position.isNotEmpty) r.position,
      if (r.probation) '试用期',
    ].join(' · ');
    final secondary = DunesColors.resolve(context, DunesColors.text3);
    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 4),
      child: Material(
        color: DunesColors.resolve(
          context,
          selected ? const Color(0xFFF1EBFC) : Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() => _selected = r);
            if (!wide) {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text(hrPerformanceTitle)),
                    body: HrPerformanceDetail(
                      session: widget.session,
                      record: r,
                      service: _service,
                      monthStarted: _monthStarted,
                      onChanged: () => _load(),
                    ),
                  ),
                ),
              );
            }
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: DunesColors.resolve(
                  context,
                  selected ? DunesColors.brandPurpleLine : _hrLine,
                  role: DunesColorRole.border,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(2, 6, 8, 6),
            child: Row(
              children: [
                if (_access.allowed)
                  SizedBox(
                    width: 34,
                    height: 38,
                    child: Checkbox(
                      value: _selectedIds.contains(r.id),
                      activeColor: _purple,
                      checkColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                      side: BorderSide(
                        color: DunesColors.resolve(
                          context,
                          const Color(0xFFC8BDDA),
                          role: DunesColorRole.border,
                        ),
                        width: 1.3,
                      ),
                      overlayColor: WidgetStatePropertyAll(
                        _purple.withValues(alpha: 0.10),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      semanticLabel: '选择${r.name}',
                      onChanged: _busy
                          ? null
                          : (checked) => setState(() {
                              if (checked == true) {
                                _selectedIds.add(r.id);
                              } else {
                                _selectedIds.remove(r.id);
                              }
                            }),
                    ),
                  ),
                ImUserAvatar(
                  initial: initial,
                  seed: r.userId,
                  size: 32,
                  borderRadius: 9,
                  avatarPreset: contact?.avatarPreset,
                  avatarObjectKey: contact?.avatarObjectKey,
                  avatarService: _avatars,
                  fallbackBackground: const Color(0xFF7B5CD8),
                  fallbackForeground: Colors.white,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.resolve(
                            context,
                            selected
                                ? DunesColors.brandPurpleDeep
                                : DunesColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: selected
                      ? DunesColors.resolve(
                          context,
                          DunesColors.brandPurpleDeep,
                        )
                      : secondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _askStart(String title, String message, String submit) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(submit),
          ),
        ],
      ),
    );
    return answer == true;
  }

  List<int> get _selectedStartIds => [
    for (final r in _records)
      if (_selectedIds.contains(r.id) &&
          r.started != true &&
          r.stage != 'archived' &&
          r.stage != 'exempt')
        r.id,
  ];

  Widget _buildBatchActions() {
    final purple = DunesColors.resolve(context, DunesColors.brandPurple);
    final border = DunesColors.resolve(
      context,
      _hrLine,
      role: DunesColorRole.border,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    final actionStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      shape: shape,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      visualDensity: VisualDensity.standard,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final selection = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_rounded, size: 18, color: purple),
        const SizedBox(width: 8),
        Text(
          '已选 ${_selectedIds.length} 人',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DunesColors.resolve(context, DunesColors.text),
          ),
        ),
        const SizedBox(width: 12),
        TextButton(
          onPressed: () => setState(() => _selectedIds.clear()),
          style: actionStyle.copyWith(
            foregroundColor: WidgetStatePropertyAll(
              DunesColors.resolve(context, DunesColors.text2),
            ),
          ),
          child: const Text('取消选择'),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton(
          onPressed: _busy ? null : () => _batch('urge'),
          style: actionStyle.copyWith(
            foregroundColor: WidgetStatePropertyAll(purple),
            side: WidgetStatePropertyAll(BorderSide(color: border)),
          ),
          child: const Text('批量督办'),
        ),
        if (_operationRows.any((r) => r.actions.contains('reject_final')))
          OutlinedButton(
            onPressed: _busy ? null : () => _batch('reject_final'),
            style: actionStyle.copyWith(
              foregroundColor: WidgetStatePropertyAll(
                DunesColors.resolve(context, DunesColors.coral),
              ),
              side: WidgetStatePropertyAll(BorderSide(color: border)),
            ),
            child: const Text('驳回选中人员'),
          ),
        if (_access.hr)
          FilledButton(
            onPressed: _busy || _loading || _selectedStartIds.isEmpty
                ? null
                : _startSelected,
            style: actionStyle.copyWith(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? purple.withValues(alpha: 0.35)
                    : purple,
              ),
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
            ),
            child: const Text('批量考核'),
          ),
      ],
    );
    return Container(
      key: const ValueKey('hr-batch-actions'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [selection, const SizedBox(height: 8), actions],
            );
          }
          return Row(
            children: [
              selection,
              const SizedBox(width: 16),
              Expanded(child: actions),
            ],
          );
        },
      ),
    );
  }

  Future<void> _startSelected() async {
    final recordIds = _selectedStartIds;
    if (!_access.hr || _busy || recordIds.isEmpty) {
      return;
    }
    if (!await _ensureScopedStart() || !mounted) return;
    await _confirmStart('已勾选的 ${recordIds.length} 人', recordIds: recordIds);
  }

  Future<void> _startMonth() async {
    final recordIds = _selectedStartIds;
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择发起范围'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('发起全员考核'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'department'),
            child: const Text('按部门发起'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'people'),
            child: const Text('选择人员发起'),
          ),
          if (recordIds.isNotEmpty)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'selected'),
              child: Text('发起已勾选的 ${recordIds.length} 人'),
            ),
        ],
      ),
    );
    if (!mounted || mode == null) return;
    if (mode == 'all') {
      await _confirmStart('全员');
      return;
    }
    if (!await _ensureScopedStart() || !mounted) return;
    if (mode == 'selected') {
      await _confirmStart('已勾选的 ${recordIds.length} 人', recordIds: recordIds);
      return;
    }
    List<HrPerformanceRecord> candidates;
    setState(() => _busy = true);
    try {
      // Load the full permitted roster, regardless of the current tab and filters.
      final rows = await _service.records(_monthKey, 'all');
      candidates = rows
          .where(
            (r) =>
                (r.started == false || (r.started == null && !_monthStarted)) &&
                r.stage != 'archived' &&
                r.stage != 'exempt' &&
                !hrPerformanceExcludedLeader(r.name) &&
                !hrPerformanceDepartmentExcluded(
                  departmentId: r.departmentId ?? _userDept[r.userId],
                  departmentName: r.department,
                  parents: _deptParent,
                  names: _deptName,
                ),
          )
          .toList();
    } catch (e) {
      if (mounted) {
        showDunesToast(context, '待发起名单加载失败：$e', kind: DunesToastKind.error);
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      showDunesToast(context, '本月暂无待发起考核人员');
      return;
    }
    List<int> chosenIds;
    String scopeLabel;
    if (mode == 'department') {
      final groups = <String, List<HrPerformanceRecord>>{};
      final labels = <String, String>{};
      for (final r in candidates) {
        final deptId = r.departmentId ?? _userDept[r.userId];
        final name = _deptName[deptId] ?? r.department;
        final key = deptId == null ? 'name:$name' : 'id:$deptId';
        groups.putIfAbsent(key, () => []).add(r);
        labels[key] = name.isEmpty ? '未分配部门' : name;
        // Selecting an ancestor includes its eligible descendants.
        final seen = <int>{};
        var ancestor = _deptParent[deptId];
        while (ancestor != null && seen.add(ancestor)) {
          final parentKey = 'id:$ancestor';
          groups.putIfAbsent(parentKey, () => []).add(r);
          labels[parentKey] = _deptName[ancestor] ?? '部门 $ancestor';
          ancestor = _deptParent[ancestor];
        }
      }
      final chosen = await showHrConfigPicker<String>(
        context,
        title: '选择发起部门（含下级部门）',
        options: [
          for (final entry in groups.entries)
            HrConfigOption(
              entry.key,
              labels[entry.key]!,
              subtitle: '待发起 ${entry.value.length} 人',
            ),
        ],
        selected: const {},
      );
      if (!mounted || chosen == null || chosen.isEmpty) return;
      chosenIds = {
        for (final key in chosen)
          for (final r in groups[key]!) r.id,
      }.toList();
      scopeLabel = chosen.map((key) => labels[key]!).join('、');
    } else {
      final chosen = await showHrConfigPicker<int>(
        context,
        title: '选择发起人员',
        options: [
          for (final r in candidates)
            HrConfigOption(
              r.id,
              r.name,
              subtitle: '${r.department} · ${r.position}',
            ),
        ],
        selected: recordIds.toSet(),
      );
      if (!mounted || chosen == null || chosen.isEmpty) return;
      chosenIds = chosen.toList();
      scopeLabel = '所选 ${chosenIds.length} 人';
    }
    await _confirmStart(scopeLabel, recordIds: chosenIds);
  }

  Future<bool> _ensureScopedStart() async {
    if (_supportsBatchStart) return true;
    try {
      final status = await _service.monthStatus(_monthKey);
      if (!mounted) return false;
      if (status.supportsBatch) {
        setState(() => _supportsBatchStart = true);
        return true;
      }
    } catch (_) {}
    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('暂时无法分批发起'),
        content: const Text('当前考核服务尚未确认支持按部门或人员发起，请更新考核服务后重试。此次没有发起任何考核。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _confirmStart(
    String scopeLabel, {
    List<int> recordIds = const [],
    List<int> departmentIds = const [],
  }) async {
    final label = '${_month.year}年${_month.month}月';
    final month = _monthKey;
    final confirmed = await _askStart(
      '开始当月绩效考核',
      '$label · $scopeLabel\n资料齐全的人员将直接进入主管初评或自评。已发起的考核表会保留当前进度。',
      '确认发起',
    );
    if (!mounted || !confirmed) return;
    setState(() => _busy = true);
    try {
      final started = await _service.startMonth(
        month,
        departmentIds: departmentIds,
        recordIds: recordIds,
      );
      if (!mounted) return;
      showDunesToast(
        context,
        started == 0 ? '所选范围暂无待发起考核表' : '已发起 $started 人的绩效考核',
      );
      await _load();
    } catch (e) {
      if (mounted) {
        showDunesToast(context, '开始失败：$e', kind: DunesToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forward() async {
    final rows = _operationRows;
    if (rows.isEmpty) return;
    try {
      final conv =
          widget.conversationService ??
          ConversationService(session: widget.session);
      final id = await showConversationPickerSheet(
        context: context,
        service: conv,
        title: '转发绩效考核到会话',
      );
      if (id == null || !mounted) return;
      var confirmed = false;
      final hasScores =
          rows.every((r) => r.released || r.stage == 'exempt') &&
          rows.any((r) => r.snapshot['total'] != null);
      if (hasScores) {
        final answer = await showHrReasonSheet(
          context,
          title: '确认转发分数',
          message: '会话成员都能看到卡片上的分数。请确认当前会话适合接收这些人员的成绩。',
          submitLabel: '确认会话成员均可查看',
        );
        if (answer == null || !mounted) return;
        confirmed = true;
      }
      setState(() => _busy = true);
      final payload = await _service.summary(
        _monthKey,
        rows.map((r) => r.id).toList(),
        confirmScores: confirmed,
      );
      final people = hrMaps(payload['rows']);
      final markdown = StringBuffer('### $hrPerformanceTitle · $_monthKey\n');
      if (payload['hasScores'] == true) {
        markdown.writeln('| 姓名 | 部门 | 得分 | 等级 | 系数 |');
        markdown.writeln('|---|---|---|---|---|');
        for (final p in people) {
          markdown.writeln(
            '| ${p['name']} | ${p['department']} | ${p['total'] ?? '—'} | ${p['grade'] ?? '—'} | ${p['coefficient'] ?? '—'} |',
          );
        }
      } else {
        markdown.writeln('共 ${people.length} 人，仅包含进度。');
        final progress = Map<String, dynamic>.from(payload['progress'] as Map);
        for (final e in progress.entries) {
          markdown.writeln(
            '- ${hrPerformanceStageLabels[e.key] ?? e.key}：${e.value} 人',
          );
        }
      }
      await conv.sendText(
        id,
        markdown.toString(),
        payload: {...payload, 'robotMarkdown': true},
      );
      if (mounted) showDunesToast(context, '已转发到会话');
    } catch (e) {
      if (mounted) {
        showDunesToast(context, '转发失败：$e', kind: DunesToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final rows = _operationRows;
    if (rows.isEmpty) return;
    setState(() => _busy = true);
    try {
      final data = await _service.export(
        _monthKey,
        rows.map((r) => r.id).toList(),
      );
      final name = '${data['filename']}';
      final target = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV', extensions: ['csv']),
        ],
      );
      if (target == null) return;
      await XFile.fromData(
        Uint8List.fromList(utf8.encode('${data['content']}')),
        mimeType: 'text/csv',
        name: name,
      ).saveTo(target.path);
      if (mounted) showDunesToast(context, '已导出当前名单');
    } catch (e) {
      if (mounted) {
        showDunesToast(context, '导出失败：$e', kind: DunesToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _batch(String action) async {
    final selected = _operationRows;
    final rows = action == 'urge'
        ? selected.where((r) => r.actions.contains(action)).toList()
        : selected;
    if (rows.isEmpty) {
      if (action == 'urge') showDunesToast(context, '当前范围没有可督办的人员');
      return;
    }
    if (rows.any((r) => !r.actions.contains(action))) {
      showDunesToast(context, '选中名单包含当前无权办理的人员，请调整选择');
      return;
    }
    final reason = action == 'urge'
        ? await showHrUrgeSheet(
            context,
            targets: rows,
            skipped: selected
                .where((r) => !r.actions.contains(action))
                .toList(),
          )
        : await showHrReasonSheet(
            context,
            title: action == 'urge' ? '批量督办' : '批量驳回至初评',
            minLength: 1,
          );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _service.batch(rows, action, '${reason['reason']}');
      final failed = result.where((r) => r['success'] != true).toList();
      final names = {for (final r in rows) r.id: r.name};
      if (mounted) {
        showDunesToast(
          context,
          failed.isEmpty
              ? action == 'urge'
                    ? '已提交 ${result.length} 条督办，等待消息发送'
                    : '已完成 ${result.length} 人'
              : '完成 ${result.length - failed.length} 人；${failed.map((r) => '${names[r['id']] ?? r['id']}：${r['message']}').join('；')}',
        );
      }
      await _load();
    } catch (e) {
      if (mounted) showDunesToast(context, '$e', kind: DunesToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeAlert(Map<String, dynamic> alert) async {
    final reason = await showHrReasonSheet(
      context,
      title: '处理 ${alert['kind'] == 'pip' ? 'PIP' : '试用期预警'}',
      minLength: 1,
    );
    if (reason == null) return;
    try {
      await _service.closeAlert(
        (alert['id'] as num).toInt(),
        '${reason['reason']}',
      );
      await _load();
    } catch (e) {
      if (mounted) showDunesToast(context, '$e', kind: DunesToastKind.error);
    }
  }

  List<(String?, String)> get _departmentOptions => [
    (null, '全部部门'),
    ..._records
        .map((r) => r.department)
        .toSet()
        .map((d) => (d, d.isEmpty ? '未分配' : d)),
  ];
  List<(String?, String)> get _tagOptions => const [
    (null, '全部标签'),
    ('probation', '试用期'),
    ('eligible', '可免考核'),
    ('blocked', '待补配'),
  ];
  List<(String?, String)> get _gradeOptions => [
    (null, '全部等级'),
    ..._records
        .where(
          (r) =>
              r.scoresVisible &&
              r.snapshot['grade'] != null &&
              '${r.snapshot['grade']}'.isNotEmpty,
        )
        .map((r) => '${r.snapshot['grade']}')
        .toSet()
        .map((g) => (g, g)),
  ];

  Widget _filters({bool expanded = false}) {
    final menus = <Widget>[
      _HrFilterMenu(
        value: _department,
        items: _departmentOptions,
        expanded: expanded,
        onChanged: (v) => setState(() => _department = v),
      ),
      _HrFilterMenu(
        value: _tag,
        items: _tagOptions,
        expanded: expanded,
        onChanged: (v) => setState(() => _tag = v),
      ),
      if (_records.any((r) => r.scoresVisible))
        _HrFilterMenu(
          value: _grade,
          items: _gradeOptions,
          expanded: expanded,
          onChanged: (v) => setState(() => _grade = v),
        ),
    ];
    if (expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < menus.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            menus[i],
          ],
        ],
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: menus);
  }

  void _openFilters() {
    showModalBottomSheet<void>(
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
      builder: (_) => SafeArea(
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
                    color: DunesColors.resolve(
                      context,
                      _hrLine,
                      role: DunesColorRole.border,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '筛选',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolve(context, DunesColors.text),
                ),
              ),
              const SizedBox(height: 12),
              _filters(expanded: true),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: DunesColors.resolve(
                    context,
                    DunesColors.brandPurple,
                    role: DunesColorRole.surface,
                  ),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectScope(String scope) {
    setState(() {
      _scope = scope;
      _records = [];
      _selected = null;
      _department = null;
      _stage = null;
      _tag = null;
      _grade = null;
      _selectedIds.clear();
    });
    _load();
  }

  Widget _stageStrip() {
    final pool = _stagePool;
    final counts = <String, int>{};
    for (final row in pool) {
      counts[row.stage] = (counts[row.stage] ?? 0) + 1;
    }
    final known = {..._hrStageFlow, ..._hrStageAside};
    final extras = counts.keys.where((id) => !known.contains(id)).toList()
      ..sort();
    bool shown(String id) => (counts[id] ?? 0) > 0 || _stage == id;
    final flowIds = [..._hrStageFlow, ...extras].where(shown).toList();
    final asideIds = _hrStageAside.where(shown).toList();
    final segments = [
      for (final id in flowIds)
        if ((counts[id] ?? 0) > 0)
          (counts[id]!, _hrStageColors[id] ?? _hrStageFallback, false),
      for (final id in asideIds)
        if ((counts[id] ?? 0) > 0)
          (counts[id]!, _hrStageColors[id] ?? _hrStageFallback, true),
    ];
    Widget chip(String id) => Padding(
      key: _stageChipKey(id),
      padding: const EdgeInsets.only(right: 8),
      child: _HrStageChip(
        key: ValueKey('hr-stage-$id'),
        label: _hrStageName(id),
        count: counts[id] ?? 0,
        color: _hrStageColors[id] ?? _hrStageFallback,
        tooltip: _hrStageTooltip(id),
        selected: _stage == id,
        onTap: () => _selectStage(id),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (segments.length > 1) ...[
          _HrStageDistribution(segments: segments),
          const SizedBox(height: 8),
        ],
        SizedBox(
          height: 36,
          child: SingleChildScrollView(
            key: const ValueKey('hr-stage-strip'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  key: _stageChipKey('all'),
                  padding: const EdgeInsets.only(right: 8),
                  child: _HrStageChip(
                    key: const ValueKey('hr-stage-all'),
                    label: '全部',
                    count: pool.length,
                    selected: _stage == null,
                    onTap: () => _selectStage(null),
                  ),
                ),
                for (final id in flowIds) chip(id),
                if (flowIds.isNotEmpty && asideIds.isNotEmpty)
                  const _HrStageDivider(),
                for (final id in asideIds) chip(id),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 640;
      final mine = _scope == 'mine';
      final rows = _visible;
      final rosterItems = _rosterItems;

      final scored = rows
          .where(
            (r) =>
                r.scoresVisible &&
                r.snapshot['total'] is num &&
                r.stage != 'exempt',
          )
          .toList();
      final grades = <String, int>{};
      for (final r in scored) {
        final g = '${r.snapshot['grade'] ?? ''}';
        if (g.isNotEmpty) grades[g] = (grades[g] ?? 0) + 1;
      }
      final average = scored.isEmpty
          ? null
          : scored.fold<double>(
                  0,
                  (n, r) => n + (r.snapshot['total'] as num).toDouble(),
                ) /
                scored.length;
      final stats = [
        '当前 ${rows.length} 人',
        if (average != null) '均分 ${average.toStringAsFixed(1)}',
        for (final e in grades.entries) '${e.key} ${e.value}',
      ].join(' · ');
      final scopes = <MapEntry<String, String>>[
        const MapEntry('mine', '我的'),
        if (_access.allowed) const MapEntry('todo', '待办'),
        if (_access.team) const MapEntry('team', '团队'),
        if (_access.all) const MapEntry('all', '全员'),
      ];
      final actions = <_HrAction>[
        _HrAction(
          icon: Icons.forward_to_inbox_outlined,
          label: '转发',
          onTap: _busy || rows.isEmpty ? null : _forward,
        ),
        _HrAction(
          icon: Icons.file_download_outlined,
          label: '导出',
          onTap: _busy || rows.isEmpty ? null : _export,
        ),
        if (_access.allowed && !mine)
          _HrAction(
            icon: Icons.notifications_active_outlined,
            label: '督办',
            onTap: _busy || rows.isEmpty ? null : () => _batch('urge'),
          ),
        _HrAction(
          icon: Icons.refresh_rounded,
          label: '刷新',
          onTap: _loading ? null : _load,
        ),
        if (_access.hr && _canStartMonth)
          _HrAction(
            icon: Icons.play_circle_outline,
            label: '开始考核',
            onTap: _busy || _loading ? null : _startMonth,
          ),
      ];
      return Material(
        color: DunesColors.resolve(
          context,
          _hrPageBg,
          role: DunesColorRole.surface,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(wide ? 16 : 12, 8, wide ? 16 : 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HrControlCard(
                busy: _loading || _busy,
                compact: !wide,
                month: _HrMonthStepper(
                  label: '${_month.year}年${_month.month}月',
                  onPrev: _loading ? null : () => _shiftMonth(-1),
                  onNext: _loading ? null : () => _shiftMonth(1),
                ),
                stats: _loading
                    ? '加载中…'
                    : mine
                    ? ''
                    : stats,
                actions: actions,
              ),
              if (!_loading &&
                  _access.hr &&
                  _canStartMonth &&
                  _supportsBatchStart) ...[
                const SizedBox(height: 8),
                Text(
                  '可按部门或勾选人员分批发起，也可一次发起全员。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: DunesColors.resolve(context, DunesColors.text2),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (scopes.length > 1 || (!mine && wide))
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: scopes.length > 1
                            ? _HrScopeTabs(
                                value: _scope,
                                expand: !wide && scopes.length > 1,
                                options: scopes,
                                onChanged: _loading ? null : _selectScope,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    if (!mine && wide)
                      TextButton.icon(
                        key: const ValueKey('hr-filter-toggle'),
                        onPressed: () => setState(
                          () => _filtersCollapsed = !_filtersCollapsed,
                        ),
                        icon: Icon(
                          _filtersCollapsed
                              ? Icons.tune_rounded
                              : Icons.expand_less_rounded,
                          size: 17,
                        ),
                        label: Text(_filtersCollapsed ? '展开筛选' : '收起筛选'),
                        style: TextButton.styleFrom(
                          foregroundColor: DunesColors.resolve(
                            context,
                            DunesColors.brandPurpleDeep,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              if (!mine)
                Visibility(
                  visible: !wide || !_filtersCollapsed,
                  maintainState: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      if (constraints.maxWidth >= 900)
                        Row(
                          children: [
                            SizedBox(
                              width: 260,
                              child: _HrSearchField(
                                hint: '搜索姓名、部门或岗位',
                                onChanged: (v) => setState(() => _query = v),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: _filters()),
                          ],
                        )
                      else ...[
                        _HrSearchField(
                          hint: '搜索姓名、部门或岗位',
                          onChanged: (v) => setState(() => _query = v),
                          trailing: wide
                              ? null
                              : IconButton(
                                  tooltip: '筛选',
                                  onPressed: _openFilters,
                                  icon: Icon(
                                    Icons.filter_list_rounded,
                                    size: 20,
                                    color: DunesColors.resolve(
                                      context,
                                      DunesColors.text2,
                                    ),
                                  ),
                                ),
                        ),
                        if (wide) ...[const SizedBox(height: 8), _filters()],
                      ],
                      if (_stagePool.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _stageStrip(),
                      ],
                    ],
                  ),
                ),
              if (!mine &&
                  wide &&
                  _filtersCollapsed &&
                  (_query.isNotEmpty ||
                      _department != null ||
                      _tag != null ||
                      _grade != null ||
                      _stage != null))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '已启用筛选 · 当前 ${rows.length} 人',
                    style: TextStyle(
                      fontSize: 12,
                      color: DunesColors.resolve(context, DunesColors.text2),
                    ),
                  ),
                ),
              if (_scope == 'todo' && _alerts.isNotEmpty) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 132),
                  child: ListView(
                    children: [
                      for (final alert in _alerts)
                        _HrAlertTile(
                          title:
                              '${alert['kind'] == 'pip' ? 'PIP' : '试用期预警'} · ${alert['name']}',
                          subtitle: '${alert['month']} · ${alert['reason']}',
                          onClose: _access.hr ? () => _closeAlert(alert) : null,
                        ),
                    ],
                  ),
                ),
              ],
              if (_records.any((r) => r.blockers.any((b) => b.contains('未配置'))))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '部分考核表未配置 HR 或终审人，请在组织用户访问配置中补充处理人。',
                    style: TextStyle(
                      fontSize: 12,
                      color: DunesColors.resolve(context, DunesColors.amber),
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: DunesColors.resolve(context, DunesColors.coral),
                    ),
                  ),
                ),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          _loading
                              ? '加载中…'
                              : _error == null
                              ? (mine ? '本月暂无您的考核表' : '本月暂无符合条件的考核表')
                              : '加载失败，请重试',
                          style: TextStyle(
                            fontSize: 13,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text3,
                            ),
                          ),
                        ),
                      )
                    : mine
                    ? HrPerformanceDetail(
                        key: ValueKey('hr-mine-${rows.first.id}'),
                        session: widget.session,
                        record: rows.first,
                        service: _service,
                        monthStarted: _monthStarted,
                        onChanged: () => _load(),
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!wide || !_rosterCollapsed)
                            SizedBox(
                              width: wide
                                  ? (constraints.maxWidth < 1200 ? 300 : 360)
                                  : constraints.maxWidth - 24,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (wide)
                                    Row(
                                      children: [
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '人员名单 · ${rows.length}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: DunesColors.resolve(
                                                context,
                                                DunesColors.text2,
                                              ),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          key: const ValueKey(
                                            'hr-roster-collapse',
                                          ),
                                          tooltip: '收起人员名单',
                                          onPressed: () => setState(
                                            () => _rosterCollapsed = true,
                                          ),
                                          icon: const Icon(
                                            Icons
                                                .keyboard_double_arrow_left_rounded,
                                            size: 20,
                                          ),
                                          color: DunesColors.resolve(
                                            context,
                                            DunesColors.brandPurpleDeep,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ],
                                    ),
                                  Expanded(
                                    child: ListView.builder(
                                      key: PageStorageKey(
                                        'hr-$_monthKey-$_scope',
                                      ),
                                      padding: const EdgeInsets.fromLTRB(
                                        0,
                                        0,
                                        0,
                                        12,
                                      ),
                                      itemCount: rosterItems.length,
                                      itemBuilder: (context, i) {
                                        final item = rosterItems[i];
                                        if (item is _HrRosterHeader) {
                                          return _rosterHeader(item);
                                        }
                                        return _rosterPerson(
                                          item as _HrRosterPerson,
                                          wide,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            SizedBox(
                              width: 44,
                              child: Column(
                                children: [
                                  IconButton(
                                    key: const ValueKey('hr-roster-expand'),
                                    tooltip: '展开人员名单',
                                    onPressed: () => setState(
                                      () => _rosterCollapsed = false,
                                    ),
                                    icon: const Icon(
                                      Icons.keyboard_double_arrow_right_rounded,
                                      size: 20,
                                    ),
                                    color: DunesColors.resolve(
                                      context,
                                      DunesColors.brandPurpleDeep,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  if (_selectedIds.isNotEmpty)
                                    Tooltip(
                                      message: '已选 ${_selectedIds.length} 人',
                                      child: Text(
                                        '${_selectedIds.length}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: DunesColors.resolve(
                                            context,
                                            DunesColors.brandPurpleDeep,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          if (wide)
                            Expanded(
                              child:
                                  _selected != null &&
                                      rows.any((r) => r.id == _selected!.id)
                                  ? HrPerformanceDetail(
                                      key: ValueKey(_selected!.id),
                                      session: widget.session,
                                      record: _selected!,
                                      service: _service,
                                      monthStarted: _monthStarted,
                                      onChanged: () => _load(),
                                    )
                                  : const Center(child: Text('选择一位员工查看考核表')),
                            ),
                        ],
                      ),
              ),
              if (_selectedIds.isNotEmpty) _buildBatchActions(),
            ],
          ),
        ),
      );
    },
  );
}

class _HrAction {
  const _HrAction({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
}

class _HrMonthStepper extends StatelessWidget {
  const _HrMonthStepper({required this.label, this.onPrev, this.onNext});
  final String label;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final border = DunesColors.resolve(
      context,
      _hrLine,
      role: DunesColorRole.border,
    );
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          const Color(0xFFF8F6FB),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _arrow(context, Icons.chevron_left_rounded, '上月', onPrev),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: DunesColors.resolve(
                    context,
                    DunesColors.brandPurpleDeep,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, DunesColors.text),
                    fontFeatures: _hrTabular,
                  ),
                ),
              ],
            ),
          ),
          _arrow(context, Icons.chevron_right_rounded, '下月', onNext),
        ],
      ),
    );
  }

  Widget _arrow(
    BuildContext context,
    IconData icon,
    String tip,
    VoidCallback? onTap,
  ) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 30,
          height: 32,
          child: Icon(
            icon,
            size: 20,
            color: DunesColors.resolve(
              context,
              onTap == null ? DunesColors.border : DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _HrControlCard extends StatelessWidget {
  const _HrControlCard({
    required this.busy,
    required this.compact,
    required this.month,
    required this.stats,
    required this.actions,
  });
  final bool busy;
  final bool compact;
  final Widget month;
  final String stats;
  final List<_HrAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            _hrLine,
            role: DunesColorRole.border,
          ),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D2B1A4F),
            blurRadius: 12,
            spreadRadius: -2,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 2,
            child: busy
                ? LinearProgressIndicator(
                    minHeight: 2,
                    color: DunesColors.resolve(
                      context,
                      DunesColors.brandPurple,
                    ),
                    backgroundColor: Colors.transparent,
                  )
                : null,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(10, 8, 12, compact ? 4 : 10),
            child: Row(
              children: [
                month,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    stats,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: DunesColors.resolve(context, DunesColors.text3),
                      fontFeatures: _hrTabular,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: DunesColors.resolve(
              context,
              _hrLine,
              role: DunesColorRole.border,
            ),
          ),
          if (compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Row(
                children: [
                  for (final action in actions)
                    Expanded(child: _HrActionTile(action: action)),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in actions) _HrActionButton(action: action),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HrActionTile extends StatelessWidget {
  const _HrActionTile({required this.action});
  final _HrAction action;

  @override
  Widget build(BuildContext context) {
    final enabled = action.onTap != null;
    final iconColor = DunesColors.resolve(
      context,
      enabled ? DunesColors.brandPurpleDeep : DunesColors.text3,
    );
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DunesColors.resolve(
                  context,
                  enabled
                      ? DunesColors.brandPurpleSoft
                      : const Color(0xFFF3F1F6),
                  role: DunesColorRole.surface,
                ),
              ),
              child: Icon(action.icon, size: 18, color: iconColor),
            ),
            const SizedBox(height: 6),
            Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                color: DunesColors.resolve(
                  context,
                  enabled ? DunesColors.text2 : DunesColors.text3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HrActionButton extends StatelessWidget {
  const _HrActionButton({required this.action});
  final _HrAction action;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: action.onTap,
      style: TextButton.styleFrom(
        foregroundColor: DunesColors.resolve(
          context,
          DunesColors.brandPurpleDeep,
        ),
        backgroundColor: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        disabledForegroundColor: DunesColors.resolve(
          context,
          DunesColors.text3,
        ),
        disabledBackgroundColor: DunesColors.resolve(
          context,
          const Color(0xFFF3F1F6),
          role: DunesColorRole.surface,
        ),
        side: BorderSide(
          color: DunesColors.resolve(
            context,
            _hrLine,
            role: DunesColorRole.border,
          ),
        ),
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      icon: Icon(action.icon, size: 16),
      label: Text(action.label),
    );
  }
}

class _HrScopeTabs extends StatelessWidget {
  const _HrScopeTabs({
    required this.value,
    required this.options,
    required this.expand,
    this.onChanged,
  });
  final String value;
  final List<MapEntry<String, String>> options;
  final bool expand;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          const Color(0xFFECE7F4),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final option in options)
            expand
                ? Expanded(child: _segment(context, option))
                : _segment(context, option),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, MapEntry<String, String> option) {
    final selected = value == option.key;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: DunesColors.resolveNullable(
          context,
          selected ? Colors.white : Colors.transparent,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x1A2B1A4F),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onChanged == null ? null : () => onChanged!(option.key),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expand ? 8 : 16,
              vertical: 6,
            ),
            child: Text(
              option.value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: DunesColors.resolve(
                  context,
                  selected ? DunesColors.text : DunesColors.text2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HrSearchField extends StatelessWidget {
  const _HrSearchField({
    required this.hint,
    required this.onChanged,
    this.trailing,
  });
  final String hint;
  final ValueChanged<String> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: DunesColors.resolve(
          context,
          _hrLine,
          role: DunesColorRole.border,
        ),
      ),
    );
    return TextField(
      onChanged: onChanged,
      style: TextStyle(
        fontSize: 13.5,
        color: DunesColors.resolve(context, DunesColors.text),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 13.5,
          color: DunesColors.resolve(context, DunesColors.text3),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: DunesColors.resolve(context, DunesColors.text3),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 38,
          minHeight: 36,
        ),
        suffixIcon: trailing,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 36,
        ),
        isDense: true,
        filled: true,
        fillColor: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(
            color: DunesColors.resolve(
              context,
              DunesColors.brandPurpleLine,
              role: DunesColorRole.border,
            ),
          ),
        ),
      ),
    );
  }
}

class _HrFilterMenu extends StatelessWidget {
  const _HrFilterMenu({
    required this.value,
    required this.items,
    required this.onChanged,
    this.expanded = false,
  });
  final String? value;
  final List<(String?, String)> items;
  final ValueChanged<String?> onChanged;
  final bool expanded;

  String get _label {
    for (final item in items) {
      if (item.$1 == value) return item.$2;
    }
    return items.isEmpty ? '' : items.first.$2;
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
        ),
        elevation: const WidgetStatePropertyAll(8),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: 0.12),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
      ),
      builder: (context, controller, child) {
        final open = controller.isOpen;
        final purple = DunesColors.resolve(context, DunesColors.brandPurple);
        return Material(
          color: DunesColors.resolve(
            context,
            open ? const Color(0xFFF4EFFB) : const Color(0xFFF5F6F8),
            role: DunesColorRole.surface,
          ),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => open ? controller.close() : controller.open(),
            child: Container(
              width: expanded ? double.infinity : null,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: open
                      ? purple.withValues(alpha: 0.45)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  if (expanded)
                    Expanded(
                      child: Text(
                        _label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: open ? FontWeight.w600 : FontWeight.w500,
                          color: DunesColors.resolve(
                            context,
                            open
                                ? DunesColors.brandPurpleDeep
                                : DunesColors.text,
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      _label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: open ? FontWeight.w600 : FontWeight.w500,
                        color: DunesColors.resolve(
                          context,
                          open ? DunesColors.brandPurpleDeep : DunesColors.text,
                        ),
                      ),
                    ),
                  const SizedBox(width: 2),
                  Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: DunesColors.resolve(
                      context,
                      open ? DunesColors.brandPurpleDeep : DunesColors.text3,
                    ),
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
              backgroundColor: WidgetStatePropertyAll(
                item.$1 == value
                    ? DunesColors.brandPurple.withValues(alpha: 0.1)
                    : Colors.transparent,
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              minimumSize: const WidgetStatePropertyAll(Size(160, 40)),
            ),
            trailingIcon: item.$1 == value
                ? Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: DunesColors.resolve(
                      context,
                      DunesColors.brandPurpleDeep,
                    ),
                  )
                : null,
            child: Text(
              item.$2,
              style: TextStyle(
                fontSize: 13,
                fontWeight: item.$1 == value
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: DunesColors.resolve(
                  context,
                  item.$1 == value
                      ? DunesColors.brandPurpleDeep
                      : DunesColors.text,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HrStageDistribution extends StatelessWidget {
  const _HrStageDistribution({required this.segments});
  final List<(int, Color, bool)> segments;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(0, (sum, segment) => sum + segment.$1);
    if (total == 0) return const SizedBox.shrink();
    return ExcludeSemantics(
      child: SizedBox(
        height: 6,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gapBefore = <double>[];
            for (var i = 0; i < segments.length; i++) {
              if (i == 0) {
                gapBefore.add(0);
              } else if (segments[i].$3 && !segments[i - 1].$3) {
                gapBefore.add(8);
              } else {
                gapBefore.add(3);
              }
            }
            final gaps = gapBefore.fold<double>(0, (sum, gap) => sum + gap);
            final width = constraints.maxWidth - gaps;
            final usable = width > 0 ? width : 0.0;
            var minSeg = 4.0;
            if (segments.isNotEmpty && minSeg * segments.length > usable) {
              minSeg = usable / segments.length;
            }
            final extra = usable - minSeg * segments.length;
            return Row(
              children: [
                for (var i = 0; i < segments.length; i++) ...[
                  if (gapBefore[i] > 0) SizedBox(width: gapBefore[i]),
                  SizedBox(
                    width: minSeg + extra * (segments[i].$1 / total),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: segments[i].$2,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HrStageDivider extends StatelessWidget {
  const _HrStageDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: SizedBox(
          width: 1,
          height: 16,
          child: ColoredBox(
            color: DunesColors.resolve(
              context,
              _hrLine,
              role: DunesColorRole.border,
            ),
          ),
        ),
      ),
    );
  }
}

class _HrStageChip extends StatelessWidget {
  const _HrStageChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.color,
    this.tooltip,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? DunesColors.brandPurple;
    final border = selected ? accent : _hrLine;
    final fill = selected ? accent.withValues(alpha: 0.12) : Colors.white;
    final chip = Material(
      color: DunesColors.resolve(context, fill, role: DunesColorRole.surface),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                border,
                role: DunesColorRole.border,
              ),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (color != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: DunesColors.resolve(
                    context,
                    selected ? DunesColors.text : DunesColors.text2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: _hrTabular,
                  color: DunesColors.resolve(context, DunesColors.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '$label $count 人',
      child: tooltip == null ? chip : Tooltip(message: tooltip!, child: chip),
    );
  }
}

class _HrAlertTile extends StatelessWidget {
  const _HrAlertTile({
    required this.title,
    required this.subtitle,
    this.onClose,
  });
  final String title;
  final String subtitle;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          const Color(0xFFFFF8EE),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFF0E2C8),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.resolve(context, DunesColors.text),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: DunesColors.resolve(context, DunesColors.text3),
                  ),
                ),
              ],
            ),
          ),
          if (onClose != null)
            TextButton(onPressed: onClose, child: const Text('处理')),
        ],
      ),
    );
  }
}

class _HrRosterDept {
  _HrRosterDept(this.key, this.name, this.people, this.children);
  final String key;
  final String name;
  final List<HrPerformanceRecord> people;
  final List<_HrRosterDept> children;
  int get total =>
      people.length + children.fold<int>(0, (sum, child) => sum + child.total);
}

class _HrRosterHeader {
  const _HrRosterHeader(this.dept, this.depth);
  final _HrRosterDept dept;
  final int depth;
}

class _HrRosterPerson {
  const _HrRosterPerson(this.record, this.depth);
  final HrPerformanceRecord record;
  final int depth;
}
