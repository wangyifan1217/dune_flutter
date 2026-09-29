import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/horizontal_drag_scroll_view.dart';
import '../auth/auth_session.dart';
import 'native_user_work_profile_page.dart';
import 'work_profile_service.dart';

const _profilePurple = Color(0xFF7651B8);
const _profileInk = Color(0xFF342740);
const _profileMuted = Color(0xFF817589);

enum _ProfileRangePreset { week, d7, d30, custom }

class NativeWorkProfileManagementPage extends StatefulWidget {
  const NativeWorkProfileManagementPage({
    super.key,
    required this.session,
    required this.onBack,
  });

  final AuthSession session;
  final VoidCallback onBack;

  @override
  State<NativeWorkProfileManagementPage> createState() =>
      _NativeWorkProfileManagementPageState();
}

class _NativeWorkProfileManagementPageState
    extends State<NativeWorkProfileManagementPage> {
  WorkProfileTeamSnapshot? _team;
  WorkProfileSafePerson? _person;
  bool _loading = true;
  String? _error;
  int _generation = 0;
  _ProfileRangePreset _rangePreset = _ProfileRangePreset.d7;
  DateTime? _customFrom;
  DateTime? _customTo;
  int? _selectedDepartmentId;
  final TextEditingController _keywordCtrl = TextEditingController();

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  (DateTime, DateTime) get _rangeBounds {
    final today = _today;
    switch (_rangePreset) {
      case _ProfileRangePreset.week:
        return (today.subtract(Duration(days: today.weekday - 1)), today);
      case _ProfileRangePreset.d7:
        return (today.subtract(const Duration(days: 6)), today);
      case _ProfileRangePreset.d30:
        return (today.subtract(const Duration(days: 29)), today);
      case _ProfileRangePreset.custom:
        return (_customFrom ?? today.subtract(const Duration(days: 6)), _customTo ?? today);
    }
  }

  String get _periodLabel {
    if (_rangePreset == _ProfileRangePreset.custom) return _customRangeLabel;
    final (from, to) = _rangeBounds;
    String fmt(DateTime day) =>
        '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return '${fmt(from)}~${fmt(to)}';
  }

  String get _customRangeLabel {
    final from = _customFrom;
    final to = _customTo;
    if (from == null || to == null) return '自定义';
    String fmt(DateTime day) =>
        '${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return '${fmt(from)}~${fmt(to)}';
  }

  bool get _viewAll => (_team?.scopeLabel ?? '').contains('全部');

  List<(int, String)> get _departments {
    final names = <int, String>{};
    for (final person in _team?.people ?? const <WorkProfileSafePerson>[]) {
      names.putIfAbsent(
        person.departmentId,
        () => person.departmentName.trim().isEmpty
            ? '未分配部门'
            : person.departmentName.trim(),
      );
    }
    final rows = names.entries.toList(growable: false)
      ..sort((a, b) => a.value.compareTo(b.value));
    return [for (final row in rows) (row.key, row.value)];
  }

  List<WorkProfileSafePerson> get _visiblePeople {
    final query = _keywordCtrl.text.trim().toLowerCase();
    return (_team?.people ?? const <WorkProfileSafePerson>[]).where((item) {
      if (_selectedDepartmentId != null &&
          item.departmentId != _selectedDepartmentId) {
        return false;
      }
      if (query.isEmpty) return true;
      return item.name.toLowerCase().contains(query) ||
          item.username.toLowerCase().contains(query) ||
          item.title.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadTeam());
  }

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTeam() async {
    final generation = ++_generation;
    final (from, to) = _rangeBounds;
    setState(() {
      _loading = true;
      _error = null;
      _person = null;
    });
    try {
      final result = await WorkProfileService(
        session: widget.session,
      ).fetchTeam(from: from, to: to);
      if (!mounted || generation != _generation) return;
      setState(() {
        _team = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _openPerson(WorkProfileSafePerson person) async {
    final generation = ++_generation;
    final (from, to) = _rangeBounds;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await WorkProfileService(
        session: widget.session,
      ).fetchPerson(userId: person.userId, from: from, to: to);
      if (!mounted || generation != _generation) return;
      setState(() {
        _person = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = '$error'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _setRangePreset(_ProfileRangePreset preset) {
    if (preset == _ProfileRangePreset.custom) {
      unawaited(_pickCustomRange());
      return;
    }
    if (_rangePreset == preset) return;
    setState(() => _rangePreset = preset);
    final person = _person;
    if (person == null) {
      unawaited(_loadTeam());
    } else {
      unawaited(_openPerson(person));
    }
  }

  Future<void> _pickCustomRange() async {
    final today = _today;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 1),
      lastDate: today,
      initialDateRange: DateTimeRange(
        start: _customFrom ?? today.subtract(const Duration(days: 6)),
        end: _customTo ?? today,
      ),
      helpText: '选择范围',
      cancelText: '取消',
      confirmText: '确定',
      saveText: '确定',
      builder: (ctx, child) {
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            colorScheme: const ColorScheme.light(
              primary: _profilePurple,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: _profileInk,
            ),
          ),
          child: child!,
        );
      },
    );
    if (range == null || !mounted) return;
    setState(() {
      _rangePreset = _ProfileRangePreset.custom;
      _customFrom = DateTime(range.start.year, range.start.month, range.start.day);
      _customTo = DateTime(range.end.year, range.end.month, range.end.day);
    });
    final person = _person;
    if (person == null) {
      unawaited(_loadTeam());
    } else {
      unawaited(_openPerson(person));
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = _person;
    final people = _visiblePeople;
    return ColoredBox(
      color: const Color(0xFFF8F6FA),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(person == null ? '员工画像' : person.name, person != null),
            if (person == null) _buildKeywordSearch(),
            _buildRangeFilter(),
            if (person == null) _buildDeptFilter(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: person == null
                    ? _loadTeam
                    : () async => _openPerson(person),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                  children: [
                    if (person != null) ...[
                      _personIdentity(person),
                      const SizedBox(height: 12),
                    ],
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 56),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: _profilePurple,
                          ),
                        ),
                      )
                    else if (_error != null)
                      _errorCard(_error!)
                    else if (person != null)
                      _personContent(person)
                    else if (people.isEmpty)
                      _errorCard('当前筛选下没有可显示的员工')
                    else
                      for (final employee in people) ...[
                        _employeeRow(employee),
                        const SizedBox(height: 8),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeywordSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: TextField(
        controller: _keywordCtrl,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: '按姓名或账号筛选',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _keywordCtrl.text.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _keywordCtrl.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE8EAED)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE8EAED)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _profilePurple),
          ),
        ),
      ),
    );
  }

  Widget _buildRangeFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: HorizontalDragScrollView(
        child: Row(
          children: [
            _ProfileChip(
              label: '本周',
              selected: _rangePreset == _ProfileRangePreset.week,
              onTap: () => _setRangePreset(_ProfileRangePreset.week),
            ),
            const SizedBox(width: 8),
            _ProfileChip(
              label: '近7天',
              selected: _rangePreset == _ProfileRangePreset.d7,
              onTap: () => _setRangePreset(_ProfileRangePreset.d7),
            ),
            const SizedBox(width: 8),
            _ProfileChip(
              label: '近30天',
              selected: _rangePreset == _ProfileRangePreset.d30,
              onTap: () => _setRangePreset(_ProfileRangePreset.d30),
            ),
            const SizedBox(width: 8),
            _ProfileChip(
              label: _rangePreset == _ProfileRangePreset.custom
                  ? _customRangeLabel
                  : '自定义',
              selected: _rangePreset == _ProfileRangePreset.custom,
              onTap: () => _setRangePreset(_ProfileRangePreset.custom),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeptFilter() {
    final depts = _departments;
    if (depts.isEmpty && _team == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '部门筛选',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _viewAll ? '全部门' : '管辖范围',
                style: const TextStyle(
                  fontSize: 11,
                  color: _profilePurple,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          HorizontalDragScrollView(
            child: Row(
              children: [
                _ProfileChip(
                  label: '全部',
                  selected: _selectedDepartmentId == null,
                  onTap: () => setState(() => _selectedDepartmentId = null),
                ),
                const SizedBox(width: 8),
                for (final dept in depts) ...[
                  _ProfileChip(
                    label: dept.$2,
                    selected: _selectedDepartmentId == dept.$1,
                    onTap: () =>
                        setState(() => _selectedDepartmentId = dept.$1),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(String title, bool viewingPerson) => Container(
    height: 56,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFE9E2EF))),
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: '返回',
          onPressed: viewingPerson
              ? () => setState(() => _person = null)
              : widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: _profileInk),
        ),
        Expanded(
          child: Text(
            title,
            style: DunesTypography.sans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _profileInk,
            ),
          ),
        ),
        if (viewingPerson)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Text(
              '管理参考',
              style: TextStyle(fontSize: 11, color: _profileMuted),
            ),
          ),
      ],
    ),
  );

  Widget _managementNotice() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF0EAF8),
      borderRadius: BorderRadius.circular(16),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 18, color: _profilePurple),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            '管理参考 · 展示任务、审批、会议和知识沉淀等业务记录，不读取聊天内容，不生成员工排名。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF5D536B),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _personContent(WorkProfileSafePerson person) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _managementNotice(),
      const SizedBox(height: 12),
      if (person.trend.isNotEmpty) ...[
        WorkProfileTrendCard(points: person.trend, updatedAt: person.updatedAt),
        const SizedBox(height: 12),
      ],
      _section('工作结果', [
        _detailMetric('任务总量', '${person.taskTotal}', '任务记录'),
        _detailMetric('已完成', '${person.taskCompleted}', '任务记录'),
        _detailMetric('进行中', '${person.taskDoing}', '任务记录'),
        _detailMetric('逾期', '${person.taskOverdue}', '任务记录'),
        _detailMetric('发起审批', '${person.approvalTotal}', '审批记录'),
        _detailMetric('待处理审批', '${person.approvalPending}', '审批记录'),
        _detailMetric('发起提案', '${person.proposalTotal}', '提案记录'),
        _detailMetric('退回提案', '${person.proposalRejected}', '提案记录'),
      ]),
      const SizedBox(height: 12),
      _section('协作与知识沉淀', [
        _detailMetric('会议', '${person.meetings}', '会议记录'),
        _detailMetric('已形成纪要', '${person.minutesGenerated}', '会议纪要'),
        _detailMetric('关联行动任务', '${person.meetingsLinkedTask}', '会议与任务记录'),
        _detailMetric('知识文档', '${person.knowledgeDocuments}', '知识库记录'),
        _detailMetric('知识引用', '${person.knowledgeReferences}', '知识库记录'),
      ]),
      if (person.performanceScore != null) ...[
        const SizedBox(height: 12),
        _section('已发布绩效', [
          _detailMetric(
            '考核月份',
            person.performanceMonth,
            '绩效发布记录',
            period: person.performanceMonth,
          ),
          _detailMetric(
            '绩效得分',
            person.performanceScore!.toStringAsFixed(2),
            '正式绩效结果',
            period: person.performanceMonth,
          ),
          _detailMetric(
            '等级',
            person.performanceGrade.isEmpty ? '—' : person.performanceGrade,
            '正式绩效结果',
            period: person.performanceMonth,
          ),
        ]),
      ],
      const SizedBox(height: 12),
      Text(
        '统计来源：任务、审批、提案、会议、知识库记录。绩效仅在已发布且有权限时显示。${person.updatedAt.isEmpty ? '' : ' · 查询于 ${person.updatedAt}'}',
        style: const TextStyle(fontSize: 10.5, color: _profileMuted),
      ),
    ],
  );

  Widget _personIdentity(WorkProfileSafePerson person) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF604084), Color(0xFF8E6BBC)],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: Colors.white24,
          child: Text(
            person.name.isEmpty ? '员' : person.name.characters.first,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                person.name,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                [
                  person.departmentName,
                  person.title,
                ].where((part) => part.trim().isNotEmpty).join(' · '),
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _employeeRow(WorkProfileSafePerson person) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: _loading ? null : () => _openPerson(person),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE9E2EF)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFF0EAF8),
              child: Text(
                person.name.isEmpty ? '员' : person.name.characters.first,
                style: const TextStyle(
                  color: _profilePurple,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _profileInk,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      person.departmentName,
                      person.title,
                    ].where((part) => part.trim().isNotEmpty).join(' · '),
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: _profileMuted,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '完成 ${person.taskCompleted}',
              style: const TextStyle(fontSize: 11, color: _profileMuted),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: _profileMuted,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _section(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE9E2EF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _profileInk,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );

  Widget _detailMetric(
    String label,
    String value,
    String source, {
    String? period,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: _profileMuted),
              ),
              const SizedBox(height: 2),
              Text(
                '来源 $source · ${period ?? _periodLabel}',
                style: const TextStyle(fontSize: 9.5, color: Color(0xFFAAA0B2)),
              ),
            ],
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            color: _profileInk,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _errorCard(String message) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE9E2EF)),
    ),
    child: Text(
      message,
      style: const TextStyle(fontSize: 12, height: 1.5, color: _profileMuted),
    ),
  );
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFF0EAF8) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? _profilePurple : const Color(0xFFE8EAED),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? _profilePurple : const Color(0xFF5C5566),
            ),
          ),
        ),
      ),
    );
  }
}
