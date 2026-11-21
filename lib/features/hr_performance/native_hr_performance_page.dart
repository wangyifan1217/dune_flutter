import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'hr_performance_detail.dart';
import 'hr_performance_management_ui.dart';
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
  'ready_final',
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
  'ready_final': '待发送终审',
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
  'calibration': Color(0xFF9274D4),
  'hr': Color(0xFF6949BC),
  'ready_final': Color(0xFF6F55C7),
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

// Verified organization identities; both ID and name must match while the
// server-side exclusion rollout is pending.
bool hrPerformanceExcludedPerson(int userId, String name) {
  final expected = <int, String>{72: 'IOS审核专用', 77: '肖喜凌', 91: '李俊昊'};
  return expected[userId] == name.trim();
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
  bool _initialScopeResolved = false;
  final _tableHorizontalController = ScrollController();

  @override
  void dispose() {
    _tableHorizontalController.dispose();
    super.dispose();
  }

  bool _onlyTodo = false;
  String? _supervisor;
  String _query = '';
  String? _stage;
  String? _department;
  String? _tag;
  String? _error;
  bool _loading = true;
  bool _monthStarted = true;
  bool _monthStatusKnown = false;
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
      if (!_initialScopeResolved) {
        _initialScopeResolved = true;
        if (access.allowed) {
          scope = access.all ? 'all' : 'team';
          _onlyTodo = !access.hr;
          fetched = await _service.records(_monthKey, scope);
        }
      }
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
      bool? started;
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
                !hrPerformanceExcludedPerson(r.userId, r.name) &&
                !hrPerformanceDepartmentExcluded(
                  departmentId: _userDept[r.userId],
                  departmentName: r.department,
                  parents: _deptParent,
                  names: _deptName,
                ),
          )
          .toList();
      final requestedRecordId = _pendingSelectId;
      setState(() {
        _access = access;
        _scope = scope;
        _monthStarted = started ?? true;
        _monthStatusKnown = started != null;
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
      final requestedRecord = _selected;
      if (requestedRecordId != null &&
          requestedRecord?.id == requestedRecordId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openAssessment(requestedRecord!);
        });
      }
    } catch (e) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _monthStarted = true;
        _monthStatusKnown = false;
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
      (!_onlyTodo || r.todoGroups.isNotEmpty) &&
      (_supervisor == null ||
          r.snapshot['directSupervisorName'] == _supervisor ||
          r.snapshot['divisionSupervisorName'] == _supervisor) &&
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
      : _records.where((r) => _selectedIds.contains(r.id)).toList();

  Set<int> get _visibleIds => _visible.map((r) => r.id).toSet();

  String get _selectionLabel {
    final visible = _visibleIds;
    final hidden = _selectedIds.where((id) => !visible.contains(id)).length;
    return '已选 ${_selectedIds.length} 人${hidden == 0 ? '' : ' · 筛选外 $hidden 人'}';
  }

  String _recordStartLabel(HrPerformanceRecord r) {
    if (r.stage == 'exempt') return '免考核';
    if (r.started == true) return '已发起';
    if (r.started == false ||
        (!_monthStarted && _monthStatusKnown) ||
        const ['opening', 'indicators'].contains(r.stage)) {
      return r.stage == 'archived' ? '未发起' : '待发起';
    }
    return '已发起';
  }

  String _assignees(HrPerformanceRecord r) {
    if (_recordStartLabel(r) != '已发起') return '—';
    final direct = hrText(r.snapshot['directSupervisorName']);
    final pending = r.requests.where(
      (request) => request['status'] == 'pending',
    );
    if (pending.any((request) => request['kind'] == 'appeal')) {
      return direct.isEmpty || r.skipsDirectReview ? 'HR' : '$direct / HR';
    }
    if (r.stage == 'self' &&
        pending.any((request) => request['kind'] == 'adjustment')) {
      return direct.isEmpty ? '—' : direct;
    }
    final handler = switch (r.stage) {
      'opening' when r.blockers.isNotEmpty => 'HR',
      'self' || 'result' => r.name,
      'review' => direct,
      'calibration' => hrText(r.snapshot['divisionSupervisorName']),
      'hr' || 'ready_final' => 'HR',
      'final' => '总裁办终审',
      'interview' => r.skipsDirectReview ? 'HR' : direct,
      _ => '—',
    };
    return handler.isEmpty ? '—' : handler;
  }

  String _batchPreview(
    List<HrPerformanceRecord> candidates,
    Map<HrPerformanceRecord, String> skipped,
    Set<int> visible,
  ) {
    final eligible = candidates.where((r) => !skipped.containsKey(r)).toList();
    final hidden = candidates.where((r) => !visible.contains(r.id)).length;
    return [
      '范围：${_selectedIds.isEmpty ? '当前筛选结果' : '已勾选人员'}'
          '${hidden == 0 ? '' : '（含筛选外 $hidden 人）'}',
      '将处理 ${eligible.length} 人'
          '${eligible.isEmpty ? '' : '：${eligible.map((r) => r.name).join('、')}'}',
      if (skipped.isNotEmpty)
        '将跳过 ${skipped.length} 人：\n'
            '${skipped.entries.map((e) => '${e.key.name}（${e.value}）').join('、')}',
    ].join('\n');
  }

  String _unavailableReason(HrPerformanceRecord r) {
    if (r.stage == 'archived') return '已归档';
    if (r.stage == 'exempt') return '免考核';
    if (r.workflow['confirmedAt'] != null &&
        r.workflow['confirmationSource'] != 'auto') {
      return '已确认锁定';
    }
    return '${r.stageLabel} · 当前环节或权限不支持此操作';
  }

  Future<void> _showBatchUnavailable(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('没有可办理的人员'),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

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
      _recordStartLabel(r),
      r.stageLabel,
      if (_assignees(r) != '—' && _assignees(r).isNotEmpty) _assignees(r),
      if (r.blockers.isNotEmpty) r.blockers.first,
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
          onTap: () => _openAssessment(r),
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
                        maxLines: 2,
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
        content: SingleChildScrollView(child: Text(message)),
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

  String? _startSkipReason(HrPerformanceRecord r) {
    if (r.stage == 'archived') return '已归档';
    if (r.stage == 'exempt') return '免考核';
    if (r.started == true) return '已发起';
    if (r.started == null && _monthStarted) return '未取得个人发起状态';
    return null;
  }

  List<int> get _selectedStartIds => [
    for (final r in _operationRows)
      if (_selectedIds.contains(r.id) && _startSkipReason(r) == null) r.id,
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
          _selectionLabel,
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
            onPressed: _busy || _loading ? null : _startSelected,
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
    if (!_access.hr || _busy || _selectedIds.isEmpty) {
      return;
    }
    final selected = _operationRows;
    final visible = _visibleIds;
    final skipped = <HrPerformanceRecord, String>{
      for (final r in selected) r: ?_startSkipReason(r),
    };
    final preview = _batchPreview(selected, skipped, visible);
    if (recordIds.isEmpty) {
      await _showBatchUnavailable(preview);
      return;
    }
    if (!await _ensureScopedStart() || !mounted) return;
    await _confirmStart(
      '已勾选的 ${selected.length} 人',
      recordIds: recordIds,
      preview: preview,
    );
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
    if (mode == 'selected') {
      await _startSelected();
      return;
    }
    if (!await _ensureScopedStart() || !mounted) return;
    List<HrPerformanceRecord> candidates;
    setState(() => _busy = true);
    try {
      // Load the full permitted roster, regardless of the current tab and filters.
      final rows = await _service.records(_monthKey, 'all');
      candidates = rows
          .where(
            (r) =>
                _startSkipReason(r) == null &&
                !hrPerformanceExcludedLeader(r.name) &&
                !hrPerformanceExcludedPerson(r.userId, r.name) &&
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
    if (mode == 'all') {
      await _confirmStart(
        '全部符合条件的 ${candidates.length} 人',
        recordIds: candidates.map((r) => r.id).toList(),
        preview:
            '将处理 ${candidates.length} 人：${candidates.map((r) => r.name).join('、')}',
      );
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
    final chosenIdSet = chosenIds.toSet();
    final chosenNames = candidates.where((r) => chosenIdSet.contains(r.id));
    await _confirmStart(
      scopeLabel,
      recordIds: chosenIds,
      preview:
          '将处理 ${chosenIds.length} 人：${chosenNames.map((r) => r.name).join('、')}',
    );
  }

  Future<void> _sendDepartmentFinal() async {
    setState(() => _busy = true);
    List<HrPerformanceRecord> all;
    try {
      all = await _service.records(_monthKey, 'all');
    } catch (e) {
      if (mounted) {
        showDunesToast(context, '部门名单加载失败：$e', kind: DunesToastKind.error);
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final groups = <int, List<HrPerformanceRecord>>{};
    for (final r in all) {
      final id = r.departmentId;
      if (id == null ||
          hrPerformanceExcludedLeader(r.name) ||
          hrPerformanceExcludedPerson(r.userId, r.name) ||
          hrPerformanceDepartmentExcluded(
            departmentId: id,
            departmentName: r.department,
            parents: _deptParent,
            names: _deptName,
          )) {
        continue;
      }
      groups.putIfAbsent(id, () => []).add(r);
      final seen = <int>{id};
      var ancestor = _deptParent[id];
      while (ancestor != null && seen.add(ancestor)) {
        groups.putIfAbsent(ancestor, () => []).add(r);
        ancestor = _deptParent[ancestor];
      }
    }
    String departmentPath(int id, String fallback) {
      final names = <String>[];
      final seen = <int>{};
      int? current = id;
      while (current != null && seen.add(current)) {
        names.add(
          _deptName[current] ?? (current == id ? fallback : '部门 $current'),
        );
        current = _deptParent[current];
      }
      return names.reversed.join(' / ');
    }

    final candidates = groups.entries.toList()
      ..sort(
        (a, b) => departmentPath(
          a.key,
          a.value.first.department,
        ).compareTo(departmentPath(b.key, b.value.first.department)),
      );
    if (candidates.isEmpty) {
      showDunesToast(context, '本月暂无可选择的部门');
      return;
    }
    bool pending(HrPerformanceRecord r) => !const {
      'ready_final',
      'final',
      'result',
      'interview',
      'archived',
      'exempt',
    }.contains(r.stage);
    final chosen = await showHrConfigPicker<int>(
      context,
      title: '选择发送终审的部门或子部门',
      options: [
        for (final entry in candidates)
          HrConfigOption(
            entry.key,
            departmentPath(entry.key, entry.value.first.department),
            subtitle:
                '${entry.value.any((r) => r.departmentId != entry.key) ? '含下级部门' : '本部门'} · 待发送 ${entry.value.where((r) => r.stage == 'ready_final').length} 人 · 未完成 ${entry.value.where(pending).length} 人',
          ),
      ],
      selected: const {},
    );
    if (!mounted || chosen == null || chosen.isEmpty) return;
    final effective = chosen.where((id) {
      final seen = <int>{id};
      var parent = _deptParent[id];
      while (parent != null && seen.add(parent)) {
        if (chosen.contains(parent)) return false;
        parent = _deptParent[parent];
      }
      return true;
    }).toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发送部门终审'),
        content: Text(
          '将检查所选 ${effective.length} 个部门及其下级部门。全部人员完成 HR 审核后才能发送终审；免考核及已归档人员不阻塞。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认发送'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    final results = <String>[];
    for (final id in effective) {
      final rows = groups[id]!;
      final name = _deptName[id] ?? rows.first.department;
      final waiting = rows.where(pending).length;
      final ready = rows.where((r) => r.stage == 'ready_final').toList();
      if (waiting > 0) {
        results.add('$name：还有 $waiting 人未完成 HR 审核，暂不能发送');
        continue;
      }
      if (ready.isEmpty) {
        results.add('$name：暂无待发送终审的人员');
        continue;
      }
      final anchor = ready.first;
      try {
        await _service.action(anchor, {
          'action': 'send_department_final',
          'departmentId': id,
        });
        results.add('$name：已发送');
      } catch (e) {
        results.add('$name：$e');
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('发送结果'),
        content: SingleChildScrollView(child: Text(results.join('\n'))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
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
    required List<int> recordIds,
    required String preview,
  }) async {
    final label = '${_month.year}年${_month.month}月';
    final month = _monthKey;
    final confirmed = await _askStart(
      '开始当月绩效考核',
      '$label · $scopeLabel\n$preview\n资料齐全的人员将进入主管初评或自评。待补配的考核表会显示缺失资料。',
      '确认发起',
    );
    if (!mounted || !confirmed) return;
    setState(() => _busy = true);
    try {
      final started = await _service.startMonth(month, recordIds: recordIds);
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
    final month = _monthKey;
    try {
      final fetchedCandidates = await _service.records(
        month,
        _access.all
            ? 'all'
            : _access.team
            ? 'team'
            : 'mine',
      );
      if (!mounted) return;
      final ownRecords = !_access.all && _access.team
          ? await _service.records(month, 'mine')
          : const <HrPerformanceRecord>[];
      if (!mounted) return;
      final candidates =
          {
                for (final r in [...fetchedCandidates, ...ownRecords]) r.id: r,
              }.values
              .where((r) => !hrPerformanceExcludedPerson(r.userId, r.name))
              .toList();
      final departments = [
        for (final id in _deptName.keys)
          {'id': id, 'name': _deptName[id], 'parentId': _deptParent[id]},
      ];
      // The organization catalog can be unavailable offline; retain directly
      // assigned departments so selection remains possible within visible scope.
      for (final record in candidates) {
        final id = record.departmentId;
        if (id != null && !departments.any((d) => d['id'] == id)) {
          departments.add({
            'id': id,
            'name': record.department,
            'parentId': null,
          });
        }
      }
      final selection = await showHrExportSheet(
        context,
        records: candidates,
        departments: departments,
        selectedIds: _selectedIds,
        month: month,
        forForward: true,
      );
      if (selection == null || !mounted) return;
      final ids = (selection['ids'] as List).whereType<int>().toSet();
      final rows = candidates.where((r) => ids.contains(r.id)).toList();
      if (rows.isEmpty) return;
      final conv =
          widget.conversationService ??
          ConversationService(session: widget.session);
      final id = await showConversationPickerSheet(
        context: context,
        service: conv,
        title: '转发绩效考核到会话',
      );
      if (id == null || !mounted) return;
      final progress = <String, int>{};
      final people = <Map<String, dynamic>>[];
      var coefficientSum = 0.0;
      var coefficientCount = 0;
      var hasScores = false;
      for (final record in rows) {
        progress.update(record.stage, (count) => count + 1, ifAbsent: () => 1);
        final person = <String, dynamic>{
          'id': record.id,
          'name': record.name,
          'department': record.department,
          'stage': record.stage,
        };
        // Use the viewer-filtered roster response and copy only card fields.
        final total = record.snapshot['total'];
        if (record.scoresVisible && total is num) {
          hasScores = true;
          person['total'] = total;
          person['grade'] = record.snapshot['grade'];
          final coefficient = record.snapshot['coefficient'];
          if (coefficient is num) {
            person['coefficient'] = coefficient;
            coefficientSum += coefficient;
            coefficientCount++;
          }
        }
        people.add(person);
      }
      if (!await hrConfirmAction(
        context,
        title: '转发绩效考核',
        message:
            '将向所选会话发送 $month 的 ${rows.length} 人考核快照：${rows.map((r) => r.name).join('、')}。${hasScores ? '包含分数、等级和系数，会话成员均可查看。' : '当前无可发送的分数。'}',
      )) {
        return;
      }
      if (!mounted) return;
      setState(() => _busy = true);
      final names = rows
          .map((r) => r.department)
          .where((v) => v.isNotEmpty)
          .toSet();
      final caption = names.length == 1 ? names.first : '所选人员';
      await conv.sendText(
        id,
        '$month · $caption · ${people.length} 人绩效考核快照',
        payload: {
          'type': 'hrPerformanceSummary',
          'hrPerformanceSummary': true,
          'month': month,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'rows': people,
          'progress': progress,
          'hasScores': hasScores,
          if (coefficientCount > 0)
            'averageCoefficient': coefficientSum / coefficientCount,
          'hrPerformanceReadOnlySummary': true,
          'department': caption,
        },
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

  Future<void> _exportAssessment({HrPerformanceRecord? person}) async {
    try {
      final all = (await _service.records(
        _monthKey,
        'all',
      )).where((r) => !hrPerformanceExcludedPerson(r.userId, r.name)).toList();
      if (!mounted) return;
      final catalog = await _service.catalog();
      if (!mounted) return;
      final selection = person == null
          ? await showHrExportSheet(
              context,
              records: all,
              departments: hrMaps(catalog['departments']),
              selectedIds: _selectedIds,
              month: _monthKey,
            )
          : <String, dynamic>{
              'ids': [person.id],
            };
      if (selection == null || !mounted) return;
      if (person != null &&
          !await hrConfirmAction(
            context,
            title: '导出考核表',
            message:
                '月份：$_monthKey\n人员：${person.name} · ${person.department}\n将导出 1 人的考核表。',
          )) {
        return;
      }
      if (!mounted) return;
      setState(() => _busy = true);
      final data = await _service.exportXlsx(_monthKey, selection);
      final name = '${data['filename']}';
      final target = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Excel', extensions: ['xlsx']),
        ],
      );
      if (target == null) return;
      await XFile.fromData(
        base64Decode('${data['content']}'),
        mimeType: '${data['mimeType']}',
        name: name,
      ).saveTo(target.path);
      if (mounted) showDunesToast(context, '已导出 ${data['count']} 份考核表');
    } catch (e) {
      if (mounted) {
        showDunesToast(context, '导出失败：$e', kind: DunesToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manageBatch(String action) async {
    if (_selectedIds.isEmpty) return;
    final candidates = _operationRows;
    final visible = _visibleIds;
    final skipped = <HrPerformanceRecord, String>{
      for (final r in candidates)
        if (!r.actions.contains(action))
          r: _unavailableReason(r)
        else if (action == 'hr_skip' &&
            r.scoresVisible &&
            (r.lines.isEmpty || r.lines.any((line) => line['score'] == null)))
          r: '评分未填完整',
    };
    var records = candidates.where((r) => !skipped.containsKey(r)).toList();
    String preview() => _batchPreview(candidates, skipped, visible);
    if (records.isEmpty) {
      await _showBatchUnavailable(preview());
      return;
    }
    try {
      Map<String, dynamic>? values;
      if (action == 'hr_assign') {
        final options = await _service.options(records.first.id);
        if (!mounted) return;
        final assignment = await showHrSupervisorSheet(
          context,
          hrMaps(options['users']),
          scope: preview(),
        );
        if (assignment == null) return;
        values = {'assignment': assignment, 'reason': assignment['reason']};
      } else {
        final allowedByRecord = <HrPerformanceRecord, Set<String>>{};
        List<String>? targets;
        if (action == 'hr_return') {
          for (final r in records) {
            final allowed = r.hrReturnTargets;
            if (allowed != null) {
              allowedByRecord[r] = allowed.toSet();
            } else {
              final options = await _service.options(r.id);
              if (!mounted) return;
              allowedByRecord[r] = (options['hrReturnTargets'] as List? ?? [])
                  .map((v) => '$v')
                  .toSet();
            }
          }
          targets = _hrStageFlow
              .where(
                (stage) => allowedByRecord.values.any((v) => v.contains(stage)),
              )
              .toList();
        }
        if (!mounted) return;
        if (targets?.isEmpty == true) {
          for (final r in records) {
            skipped[r] = '${r.stageLabel} · 无可回退阶段';
          }
          await _showBatchUnavailable(preview());
          return;
        }
        Map<HrPerformanceRecord, String> skippedFor(String target) => {
          ...skipped,
          for (final r in records)
            if (!allowedByRecord[r]!.contains(target))
              r: '${r.stageLabel} · 无法回退到${hrPerformanceStageLabels[target] ?? target}',
        };
        values = await showHrReasonSheet(
          context,
          title: action == 'hr_skip' ? '批量跳过当前审批' : '批量回退阶段',
          targets: targets,
          minLength: 1,
          message: action == 'hr_skip'
              ? '${preview()}${records.any((r) => r.stage == 'final') ? '\n跳过终审的考核将立即下发结果。' : ''}'
              : '目标阶段及后续审批将失效。已下发的结果和自动确认将被撤销，历史记录保留。',
          scopePreview: targets == null
              ? null
              : (target) =>
                    _batchPreview(candidates, skippedFor(target), visible),
        );
        if (values != null && targets != null) {
          final ineligible = skippedFor(hrText(values['target']));
          records = records.where((r) => !ineligible.containsKey(r)).toList();
        }
      }
      if (values == null || !mounted) return;
      setState(() => _busy = true);
      final result = await _service.batchManaged(
        records,
        action,
        '${values['reason']}',
        values: values,
      );
      if (!mounted) return;
      final failures = result.where((v) => v['success'] != true).toList();
      final names = {for (final r in records) r.id: r.name};
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            '成功 ${result.length - failures.length} 人 · 失败 ${failures.length} 人',
          ),
          content: SingleChildScrollView(
            child: Text(
              failures.isEmpty
                  ? '操作已完成'
                  : failures
                        .map(
                          (v) => '${names[v['id']] ?? v['id']}：${v['message']}',
                        )
                        .join('\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) showDunesToast(context, '$e', kind: DunesToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAssessmentActions(HrPerformanceRecord record) async {
    final actions = hrAssessmentActions(record);
    final selection = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Theme(
        data: hrConfigTheme(dialogContext),
        child: SimpleDialog(
          title: Text('${record.name} · 考核操作'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, 'detail'),
              child: const Text('查看考核详情'),
            ),
            for (final action in actions)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, action),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hrAssessmentActionLabel(record, action)),
                    if (hrAssessmentActionImpact(record, action)
                        case final impact?)
                      Text(
                        impact,
                        style: Theme.of(dialogContext).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            if (_access.hr && !actions.contains('hr_edit_scores'))
              if (hrAssessmentScoreBlocked(record) case final blocked?)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 6,
                  ),
                  child: Text(
                    blocked,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ),
            if (_access.hr)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, 'export'),
                child: const Text('导出考核表'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selection == null) return;
    if (selection == 'export') {
      await _exportAssessment(person: record);
    } else {
      await _openAssessment(
        record,
        initialAction: selection == 'detail' ? null : selection,
      );
    }
  }

  Future<void> _openAssessment(
    HrPerformanceRecord record, {
    String? initialAction,
  }) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭考核详情',
      pageBuilder: (context, animation, secondary) => Align(
        alignment: Alignment.center,
        child: SizedBox(
          key: const ValueKey('hr-assessment-dialog'),
          width: (MediaQuery.sizeOf(context).width - 48)
              .clamp(0, 1180)
              .toDouble(),
          height: MediaQuery.sizeOf(context).height - 64,
          child: Theme(
            data: hrConfigTheme(context),
            child: Material(
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                        Expanded(child: Text('${record.name} · 考核详情')),
                        if (_access.hr)
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _exportAssessment(person: record),
                            icon: const Icon(Icons.download),
                            label: const Text('导出考核表'),
                          ),
                      ],
                    ),
                    Expanded(
                      child: HrPerformanceDetail(
                        session: widget.session,
                        record: record,
                        service: _service,
                        monthStarted: _monthStarted,
                        hrAccess: _access.hr,
                        onChanged: _load,
                        initialAction: initialAction,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _assessmentTable(List<HrPerformanceRecord> records) {
    const columns = [
      ('得分', 64.0, true),
      ('绩效等级', 82.0, true),
      ('部门', 120.0, false),
      ('岗位', 146.0, false),
      ('发起状态', 84.0, true),
      ('当前节点', 104.0, true),
      ('当前处理人', 128.0, true),
      ('待处理事项', 200.0, false),
      ('直属主管', 96.0, true),
      ('分管主管', 96.0, true),
      ('节点截止', 142.0, true),
    ];
    const checkWidth = 40.0;
    const nameWidth = 112.0;
    const leadingWidth = checkWidth + nameWidth;
    const actionWidth = 100.0;
    const rowHeight = 42.0;
    const scrollGutter = 12.0;
    final tableWidth = columns.fold(
      leadingWidth + actionWidth,
      (width, column) => width + column.$2,
    );
    final line = DunesColors.resolve(
      context,
      _hrLine,
      role: DunesColorRole.border,
    );
    Color surface(Color color) =>
        DunesColors.resolve(context, color, role: DunesColorRole.surface);
    final headerColor = surface(DunesColors.brandPurpleSoft);
    final text = DunesColors.resolve(context, DunesColors.text);
    final mutedText = DunesColors.resolve(context, DunesColors.text2);
    final actionStyle = TextButton.styleFrom(
      foregroundColor: DunesColors.resolve(
        context,
        DunesColors.brandPurpleDeep,
      ),
      minimumSize: const Size(44, 32),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    );
    Widget cell(
      String value,
      double width, {
      bool centered = false,
      bool header = false,
      bool emphasize = false,
    }) => SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: centered ? Alignment.center : Alignment.centerLeft,
          child: Text(
            value.isEmpty ? '—' : value,
            textAlign: centered ? TextAlign.center : TextAlign.left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: header || emphasize ? text : mutedText,
              fontWeight: header || emphasize
                  ? FontWeight.w600
                  : FontWeight.w400,
              fontFeatures: centered ? _hrTabular : null,
            ),
          ),
        ),
      ),
    );
    Widget pinned(
      Widget child,
      Color background,
      double viewportWidth, {
      bool leading = false,
    }) => AnimatedBuilder(
      animation: _tableHorizontalController,
      child: Container(
        width: leading ? leadingWidth : actionWidth,
        height: rowHeight,
        decoration: BoxDecoration(
          color: background,
          boxShadow: [
            BoxShadow(
              color: const Color(0x0D473060),
              blurRadius: 6,
              offset: Offset(leading ? 3 : -3, 0),
            ),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          border: Border(
            left: leading ? BorderSide.none : BorderSide(color: line),
            right: leading ? BorderSide(color: line) : BorderSide.none,
          ),
        ),
        child: child,
      ),
      builder: (context, child) => Positioned(
        left:
            (leading ? 0 : viewportWidth - actionWidth) +
            (_tableHorizontalController.hasClients
                ? _tableHorizontalController.offset
                : 0),
        top: 0,
        child: child!,
      ),
    );
    return Material(
      key: const ValueKey('hr-assessment-table'),
      color: surface(Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: line),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) => ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: false,
            dragDevices: PointerDeviceKind.values.toSet(),
          ),
          child: Scrollbar(
            key: const ValueKey('hr-table-horizontal-scrollbar'),
            controller: _tableHorizontalController,
            thumbVisibility: true,
            trackVisibility: true,
            interactive: true,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.only(bottom: scrollGutter),
              child: SingleChildScrollView(
                key: const ValueKey('hr-table-horizontal-scroll'),
                controller: _tableHorizontalController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: c.maxWidth > tableWidth ? c.maxWidth : tableWidth,
                  height: (c.maxHeight - scrollGutter)
                      .clamp(0, c.maxHeight)
                      .toDouble(),
                  child: Column(
                    children: [
                      Container(
                        key: const ValueKey('hr-table-header'),
                        height: rowHeight,
                        color: headerColor,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Row(
                              children: [
                                const SizedBox(width: leadingWidth),
                                for (final col in columns)
                                  cell(
                                    col.$1,
                                    col.$2,
                                    header: true,
                                    centered: col.$3,
                                  ),
                              ],
                            ),
                            pinned(
                              Row(
                                children: [
                                  SizedBox(
                                    width: checkWidth,
                                    child: Checkbox(
                                      semanticLabel: '选择当前筛选中的全部人员',
                                      activeColor: _purple,
                                      checkColor: Colors.white,
                                      value:
                                          records.isNotEmpty &&
                                          records.every(
                                            (r) => _selectedIds.contains(r.id),
                                          ),
                                      onChanged: _busy
                                          ? null
                                          : (checked) => setState(() {
                                              if (checked == true) {
                                                _selectedIds.addAll(
                                                  records.map((r) => r.id),
                                                );
                                              } else {
                                                _selectedIds.removeAll(
                                                  records.map((r) => r.id),
                                                );
                                              }
                                            }),
                                    ),
                                  ),
                                  cell('姓名', nameWidth, header: true),
                                ],
                              ),
                              headerColor,
                              c.maxWidth,
                              leading: true,
                            ),
                            pinned(
                              cell(
                                '操作',
                                actionWidth,
                                header: true,
                                centered: true,
                              ),
                              headerColor,
                              c.maxWidth,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          key: PageStorageKey('hr-table-$_monthKey-$_scope'),
                          primary: false,
                          itemExtent: rowHeight,
                          itemCount: records.length,
                          itemBuilder: (context, index) {
                            final r = records[index];
                            final values = [
                              r.scoresVisible && r.snapshot['total'] != null
                                  ? '${r.snapshot['total']}'
                                  : '—',
                              r.scoresVisible
                                  ? hrText(r.snapshot['grade']).isEmpty
                                        ? '—'
                                        : hrText(r.snapshot['grade'])
                                  : '—',
                              r.department,
                              r.position,
                              _recordStartLabel(r),
                              r.stageLabel,
                              _assignees(r),
                              r.blockers.isEmpty ? '—' : r.blockers.join('；'),
                              hrText(r.snapshot['directSupervisorName']),
                              hrText(r.snapshot['divisionSupervisorName']),
                              hrDate(r.workflow['dueAt']),
                            ];
                            final rowColor = surface(
                              _selectedIds.contains(r.id)
                                  ? DunesColors.brandPurpleSoft
                                  : index.isEven
                                  ? Colors.white
                                  : const Color(0xFFFAF8FD),
                            );
                            return Material(
                              key: ValueKey('hr-table-row-${r.id}'),
                              color: rowColor,
                              child: InkWell(
                                onTap: () => _openAssessment(r),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Row(
                                      children: [
                                        const SizedBox(width: leadingWidth),
                                        for (var i = 0; i < columns.length; i++)
                                          cell(
                                            values[i],
                                            columns[i].$2,
                                            centered: columns[i].$3,
                                            emphasize:
                                                i == 0 && values[i] != '—',
                                          ),
                                      ],
                                    ),
                                    pinned(
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: checkWidth,
                                            child: Checkbox(
                                              semanticLabel: '选择${r.name}',
                                              activeColor: _purple,
                                              checkColor: Colors.white,
                                              value: _selectedIds.contains(
                                                r.id,
                                              ),
                                              onChanged: _busy
                                                  ? null
                                                  : (b) => setState(() {
                                                      if (b == true) {
                                                        _selectedIds.add(r.id);
                                                      } else {
                                                        _selectedIds.remove(
                                                          r.id,
                                                        );
                                                      }
                                                    }),
                                            ),
                                          ),
                                          cell(
                                            r.name,
                                            nameWidth,
                                            emphasize: true,
                                          ),
                                        ],
                                      ),
                                      rowColor,
                                      c.maxWidth,
                                      leading: true,
                                    ),
                                    pinned(
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          TextButton(
                                            style: actionStyle,
                                            onPressed: () => _openAssessment(r),
                                            child: const Text('查看'),
                                          ),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            key: ValueKey(
                                              'hr-row-actions-${r.id}',
                                            ),
                                            tooltip: '${r.name}的操作',
                                            onPressed: _busy
                                                ? null
                                                : () =>
                                                      _showAssessmentActions(r),
                                            style: IconButton.styleFrom(
                                              fixedSize: const Size(32, 32),
                                              minimumSize: const Size(32, 32),
                                              padding: EdgeInsets.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              foregroundColor: mutedText,
                                            ),
                                            icon: const Icon(
                                              Icons.more_horiz,
                                              size: 19,
                                            ),
                                          ),
                                        ],
                                      ),
                                      rowColor,
                                      c.maxWidth,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _export() async {
    if (_access.hr) {
      await _exportAssessment();
      return;
    }
    final rows = _operationRows;
    if (rows.isEmpty) return;
    if (!await hrConfirmAction(
      context,
      title: '导出考核数据',
      message: '月份：$_monthKey\n${_batchPreview(rows, {}, _visibleIds)}',
    )) {
      return;
    }
    if (!mounted) return;
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
    final skipped = <HrPerformanceRecord, String>{
      for (final r in selected)
        if (!r.actions.contains(action))
          r: _unavailableReason(r)
        else if (action == 'urge' && r.urgeUnavailableReason.isNotEmpty)
          r: r.urgeUnavailableReason,
    };
    final rows = selected.where((r) => !skipped.containsKey(r)).toList();
    final preview = _batchPreview(selected, skipped, _visibleIds);
    if (rows.isEmpty) {
      await _showBatchUnavailable(preview);
      return;
    }
    final reason = action == 'urge'
        ? await showHrUrgeSheet(context, scope: preview)
        : await showHrReasonSheet(
            context,
            title: '批量驳回至初评',
            minLength: 1,
            message: '$preview\n驳回后需重新初评和送审。',
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
    final supervisors = {
      for (final r in _records) ...[
        hrText(r.snapshot['directSupervisorName']),
        hrText(r.snapshot['divisionSupervisorName']),
      ],
    }..remove('');
    final menus = <Widget>[
      _HrFilterMenu(
        value: _supervisor,
        items: [(null, '全部主管'), ...supervisors.map((s) => (s, s))],
        expanded: expanded,
        onChanged: (v) => setState(() => _supervisor = v),
      ),
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

  Widget _stageStrip({required bool wrap}) {
    final pool = _stagePool;
    final counts = <String, int>{};
    for (final row in pool) {
      counts[row.stage] = (counts[row.stage] ?? 0) + 1;
    }
    final known = {..._hrStageFlow, ..._hrStageAside};
    final extras = counts.keys.where((id) => !known.contains(id)).toList()
      ..sort();
    final flowIds = [..._hrStageFlow, ...extras];
    const asideIds = _hrStageAside;
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
      padding: EdgeInsets.only(right: wrap ? 0 : 8),
      child: _HrStageChip(
        key: ValueKey('hr-stage-$id'),
        compact: wrap,
        label: _hrStageName(id),
        count: counts[id] ?? 0,
        color: _hrStageColors[id] ?? _hrStageFallback,
        tooltip: _hrStageTooltip(id),
        selected: _stage == id,
        onTap: () => _selectStage(id),
      ),
    );
    final chips = [
      Padding(
        key: _stageChipKey('all'),
        padding: EdgeInsets.only(right: wrap ? 0 : 8),
        child: _HrStageChip(
          key: const ValueKey('hr-stage-all'),
          compact: wrap,
          label: '全部',
          count: pool.length,
          selected: _stage == null,
          onTap: () => _selectStage(null),
        ),
      ),
      for (final id in flowIds) chip(id),
      if (!wrap) const _HrStageDivider(),
      for (final id in asideIds) chip(id),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (segments.length > 1) ...[
          _HrStageDistribution(segments: segments),
          const SizedBox(height: 8),
        ],
        if (wrap)
          Wrap(
            key: const ValueKey('hr-stage-strip'),
            spacing: 6,
            runSpacing: 6,
            children: chips,
          )
        else
          SizedBox(
            height: 36,
            child: SingleChildScrollView(
              key: const ValueKey('hr-stage-strip'),
              scrollDirection: Axis.horizontal,
              child: Row(children: chips),
            ),
          ),
      ],
    );
  }

  @override
  // Flutter Windows AXTree can be corrupted by Tooltip overlay reparenting.
  // Keep the controls' own semantics; only omit redundant tooltip semantics.
  Widget build(BuildContext context) => Theme(
    data: hrConfigTheme(context),
    child: Builder(builder: (context) => _buildPage(context)),
  );

  Widget _buildPage(BuildContext context) => TooltipTheme(
    data: TooltipTheme.of(context).copyWith(excludeFromSemantics: true),
    child: LayoutBuilder(
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
          if (_access.allowed) const MapEntry('list', '考核列表'),
        ];
        final actions = <_HrAction>[
          _HrAction(
            icon: Icons.forward_to_inbox_outlined,
            label: '转发',
            onTap: _busy || _loading ? null : _forward,
          ),
          _HrAction(
            icon: Icons.file_download_outlined,
            label: _access.hr ? '导出考核表' : '导出',
            onTap: _busy ? null : _export,
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
          if (_access.hr)
            _HrAction(
              icon: Icons.send_outlined,
              label: '发送部门终审',
              onTap: _busy || _loading ? null : _sendDepartmentFinal,
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
                  status: _loading
                      ? '考核状态加载中'
                      : !_monthStatusKnown
                      ? '考核状态未获取'
                      : !_monthStarted
                      ? '本月未开启'
                      : _canStartMonth
                      ? '本月已开启 · 仍有待发起'
                      : '本月已开启',
                  started: !_loading && _monthStatusKnown && _monthStarted,
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
                                  value: mine ? 'mine' : 'list',
                                  expand: !wide && scopes.length > 1,
                                  options: scopes,
                                  onChanged: _loading
                                      ? null
                                      : (scope) => _selectScope(
                                          scope == 'list'
                                              ? (_access.all ? 'all' : 'team')
                                              : scope,
                                        ),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SegmentedButton<bool>(
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.selected)
                                  ? _purple
                                  : Colors.transparent,
                            ),
                            foregroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.selected)
                                  ? Colors.white
                                  : DunesColors.resolve(
                                      context,
                                      DunesColors.text2,
                                    ),
                            ),
                            side: WidgetStatePropertyAll(
                              BorderSide(
                                color: DunesColors.resolve(
                                  context,
                                  DunesColors.brandPurpleLine,
                                ),
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: const [
                            ButtonSegment(value: false, label: Text('全部')),
                            ButtonSegment(value: true, label: Text('待我处理')),
                          ],
                          selected: {_onlyTodo},
                          onSelectionChanged: (s) =>
                              setState(() => _onlyTodo = s.first),
                        ),
                        if (_access.team && !_access.all)
                          const Chip(label: Text('我的团队')),
                        if (_access.all && _access.team)
                          FilterChip(
                            label: const Text('我的团队'),
                            selected: _scope == 'team',
                            onSelected: _loading
                                ? null
                                : (b) => _selectScope(b ? 'team' : 'all'),
                          ),
                        if (_access.hr && _selectedIds.isNotEmpty) ...[
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _manageBatch('hr_skip'),
                            child: const Text('跳过审批'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _manageBatch('hr_return'),
                            child: const Text('回退阶段'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _manageBatch('hr_assign'),
                            child: const Text('修改主管'),
                          ),
                        ],
                      ],
                    ),
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
                      ],
                    ),
                  ),
                if (!mine) ...[
                  const SizedBox(height: 8),
                  _stageStrip(wrap: wide),
                ],
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
                if (_onlyTodo && _alerts.isNotEmpty) ...[
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
                            onClose: _access.hr
                                ? () => _closeAlert(alert)
                                : null,
                          ),
                      ],
                    ),
                  ),
                ],
                if (_records.any(
                  (r) => r.blockers.any((b) => b.contains('未配置')),
                ))
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
                if (!mine) SizedBox(height: wide ? 12 : 10),
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
                          hrAccess: _access.hr,
                          onChanged: _load,
                        )
                      : wide
                      ? _assessmentTable(rows)
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!wide || !_rosterCollapsed)
                              SizedBox(
                                width: wide
                                    ? (constraints.maxWidth < 1200 ? 300 : 360)
                                    : constraints.maxWidth - 24,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
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
                                            visualDensity:
                                                VisualDensity.compact,
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
                                        Icons
                                            .keyboard_double_arrow_right_rounded,
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
                                        hrAccess: _access.hr,
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
    ),
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
    required this.status,
    required this.started,
    required this.actions,
  });
  final bool busy;
  final bool compact;
  final Widget month;
  final String stats;
  final String status;
  final bool started;
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
                Flexible(
                  flex: 3,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 5,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      month,
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: DunesColors.resolve(
                            context,
                            started ? const Color(0xFFE9F6EF) : _hrPageBg,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.resolve(
                                context,
                                started
                                    ? const Color(0xFF24734F)
                                    : DunesColors.text2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
        maximumSize: const WidgetStatePropertyAll(Size(340, 420)),
        elevation: const WidgetStatePropertyAll(4),
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
        final highlighted = open || value != null;
        final purple = DunesColors.resolve(context, DunesColors.brandPurple);
        return Material(
          color: DunesColors.resolve(
            context,
            highlighted ? DunesColors.brandPurpleSoft : Colors.white,
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
                  color: highlighted
                      ? purple.withValues(alpha: 0.45)
                      : DunesColors.resolve(
                          context,
                          _hrLine,
                          role: DunesColorRole.border,
                        ),
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
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
    this.compact = false,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  final String? tooltip;
  final bool compact;

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
          height: compact ? 30 : 36,
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
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
                  fontSize: compact ? 12 : 13,
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
                  fontSize: compact ? 12 : 13,
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
