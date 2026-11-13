import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'hr_performance_detail.dart';
import 'hr_performance_sheets.dart';
import '../conversation/conversation_service.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../shell/dunes_toast.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'hr_performance_service.dart';

const _hrPageBg = Color(0xFFF7F4FC);
const _hrLine = Color(0xFFECE7F3);
const _hrTabular = <FontFeature>[FontFeature.tabularFigures()];

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
  late DateTime _month;
  HrPerformanceAccess _access = const HrPerformanceAccess();
  List<HrPerformanceRecord> _records = [];
  HrPerformanceRecord? _selected;
  final Set<int> _selectedIds = {};
  List<Map<String, dynamic>> _alerts = [];
  bool _busy = false;
  String? _grade;
  String _scope = 'mine';
  String _query = '';
  String? _stage;
  String? _department;
  String? _tag;
  String? _error;
  bool _loading = true;
  int _epoch = 0;

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
      _month = DateTime(
        int.parse(month.group(1)!),
        int.parse(month.group(2)!),
      );
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
      if (!mounted || epoch != _epoch) return;
      final rows = results[1] as List<HrPerformanceRecord>;
      setState(() {
        _access = results[0] as HrPerformanceAccess;
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
        _records = [];
        _selected = null;
      });
    }
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

  Color get _purple => DunesColors.resolve(context, DunesColors.brandPurple);
  List<HrPerformanceRecord> get _visible => _records
      .where(
        (r) =>
            (_query.isEmpty ||
                '${r.name} ${r.department} ${r.position}'.contains(_query)) &&
            (_stage == null || r.stage == _stage) &&
            (_grade == null ||
                (r.scoresVisible && r.snapshot['grade'] == _grade)) &&
            (_department == null || r.department == _department) &&
            (_tag == null ||
                (_tag == 'probation' && r.probation) ||
                (_tag == 'eligible' && r.exemptionEligible) ||
                (_tag == 'blocked' && r.blockers.isNotEmpty)),
      )
      .toList();

  List<HrPerformanceRecord> get _operationRows => _selectedIds.isEmpty
      ? _visible
      : _visible.where((r) => _selectedIds.contains(r.id)).toList();
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
    final rows = _operationRows;
    if (rows.isEmpty) return;
    if (rows.any((r) => !r.actions.contains(action))) {
      showDunesToast(context, '选中名单包含当前无权办理的人员，请调整选择');
      return;
    }
    final reason = await showHrReasonSheet(
      context,
      title: action == 'urge' ? '批量督办' : '批量驳回至初评',
      minLength: 1,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _service.batch(rows, action, '${reason['reason']}');
      final failed = result.where((r) => r['success'] != true).toList();
      if (mounted) {
        showDunesToast(
          context,
          failed.isEmpty
              ? '已完成 ${result.length} 人'
              : '完成 ${result.length - failed.length} 人；${failed.map((r) => r['message']).join('；')}',
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
  List<(String?, String)> get _stageOptions => [
    (null, '全部节点'),
    ...hrPerformanceStageLabels.entries.map((e) => (e.key, e.value)),
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
        value: _stage,
        items: _stageOptions,
        expanded: expanded,
        onChanged: (v) => setState(() => _stage = v),
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 640;
      final rows = _visible;
      final rosterItems=<Object>[];
      if(_scope=='todo'){
        for(final group in const ['调整审批','初评','校准','HR 审核','终审','申诉','面谈','待补人','超时督办']){final people=rows.where((r)=>r.todoGroups.isNotEmpty&&r.todoGroups.first==group).toList();if(people.isNotEmpty){rosterItems.add('$group · ${people.length} 人');rosterItems.addAll(people);}}
      }else{rosterItems.addAll(rows);}

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
      final progress = <String, int>{};
      for (final r in rows) {
        progress[r.stageLabel] = (progress[r.stageLabel] ?? 0) + 1;
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
        if (_access.allowed)
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
                stats: _loading ? '加载中…' : stats,
                actions: actions,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _HrScopeTabs(
                  value: _scope,
                  expand: !wide && scopes.length > 1,
                  options: scopes,
                  onChanged: _loading ? null : _selectScope,
                ),
              ),
              const SizedBox(height: 8),
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
                          color: DunesColors.resolve(context, DunesColors.text2),
                        ),
                      ),
              ),
              if (wide) ...[const SizedBox(height: 8), _filters()],
              if (progress.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final e in progress.entries)
                      _HrCountPill(label: '${e.key} ${e.value}'),
                  ],
                ),
              ],
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
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Text(
                          _loading
                              ? '加载中…'
                              : _error == null
                              ? '本月暂无符合条件的考核表'
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
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: wide ? 300 : constraints.maxWidth - 24,
                            child: ListView.builder(
                              key: PageStorageKey('hr-$_monthKey-$_scope'),
                              padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
                              itemCount: rosterItems.length,
                              itemBuilder: (context, i) {
                                final item = rosterItems[i];
                                if (item is String) {
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      4,
                                      12,
                                      4,
                                      6,
                                    ),
                                    child: Text(
                                      item,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: DunesColors.resolve(
                                          context,
                                          DunesColors.text3,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                                final r = item as HrPerformanceRecord;
                                final selected =
                                    wide && _selected?.id == r.id;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Material(
                                    color: DunesColors.resolve(
                                      context,
                                      selected
                                          ? const Color(0xFFF4EFFB)
                                          : Colors.white,
                                      role: DunesColorRole.surface,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        setState(() => _selected = r);
                                        if (!wide) {
                                          Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => Scaffold(
                                                appBar: AppBar(
                                                  title: const Text(hrPerformanceTitle),
                                                ),
                                                body: HrPerformanceDetail(
                                                  session: widget.session,
                                                  record: r,
                                                  service: _service,
                                                  onChanged: () => _load(),
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: DunesColors.resolve(
                                              context,
                                              selected
                                                  ? DunesColors.brandPurpleLine
                                                  : _hrLine,
                                              role: DunesColorRole.border,
                                            ),
                                          ),
                                        ),
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 2,
                                              ),
                                          leading: _access.allowed
                                              ? Checkbox(
                                                  value: _selectedIds.contains(
                                                    r.id,
                                                  ),
                                                  activeColor: _purple,
                                                  onChanged: _busy
                                                      ? null
                                                      : (checked) => setState(
                                                          () {
                                                            if (checked ==
                                                                true) {
                                                              _selectedIds.add(
                                                                r.id,
                                                              );
                                                            } else {
                                                              _selectedIds
                                                                  .remove(r.id);
                                                            }
                                                          },
                                                        ),
                                                )
                                              : null,
                                          title: Text(
                                            r.name,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: DunesColors.resolve(
                                                context,
                                                DunesColors.text,
                                              ),
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${r.department.isEmpty ? '未分配部门' : r.department} · ${r.todoGroups.isEmpty ? r.stageLabel : r.todoGroups.join(' / ')}${r.probation ? ' · 试用期' : ''}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              height: 1.35,
                                              color: DunesColors.resolve(
                                                context,
                                                DunesColors.text3,
                                              ),
                                            ),
                                          ),
                                          trailing: Icon(
                                            Icons.chevron_right_rounded,
                                            color: DunesColors.resolve(
                                              context,
                                              DunesColors.text3,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
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
                                    onChanged: () => _load(),
                                  )
                                : const Center(child: Text('选择一位员工查看考核表')),
                          ),
                      ],
                    ),
              ),
              if (_selectedIds.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
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
                        _hrLine,
                        role: DunesColorRole.border,
                      ),
                    ),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '已选 ${_selectedIds.length} 人',
                        style: TextStyle(
                          fontSize: 13,
                          color: DunesColors.resolve(context, DunesColors.text2),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _selectedIds.clear()),
                        child: const Text('取消选择'),
                      ),
                      FilledButton.tonal(
                        onPressed: _busy ? null : () => _batch('urge'),
                        child: const Text('批量督办'),
                      ),
                      if (_operationRows.any(
                        (r) => r.actions.contains('reject_final'),
                      ))
                        FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _batch('reject_final'),
                          child: const Text('驳回选中人员'),
                        ),
                    ],
                  ),
                ),
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
                    color: DunesColors.resolve(context, DunesColors.brandPurple),
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
                  enabled ? DunesColors.brandPurpleSoft : const Color(0xFFF3F1F6),
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
        disabledForegroundColor: DunesColors.resolve(context, DunesColors.text3),
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
        color: DunesColors.resolve(context, _hrLine, role: DunesColorRole.border),
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
        prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 36),
        suffixIcon: trailing,
        suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
          DunesColors.resolve(context, Colors.white, role: DunesColorRole.surface),
        ),
        elevation: const WidgetStatePropertyAll(8),
        shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.12)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
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
                            open ? DunesColors.brandPurpleDeep : DunesColors.text,
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
                fontWeight: item.$1 == value ? FontWeight.w600 : FontWeight.w400,
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

class _HrCountPill extends StatelessWidget {
  const _HrCountPill({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            _hrLine,
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: DunesColors.resolve(context, DunesColors.text2),
        ),
      ),
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
