import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/dunes_month_picker.dart';
import '../../core/widgets/horizontal_drag_scroll_view.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'native_user_work_profile_page.dart';
import 'work_profile_chat_share.dart';
import 'work_profile_controls.dart';
import 'work_profile_service.dart';

const _profilePurple = Color(0xFF7651B8);
const _profileInk = Color(0xFF342740);
const _profileMuted = Color(0xFF817589);

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
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int? _selectedDepartmentId;
  final TextEditingController _keywordCtrl = TextEditingController();

  DateTime get _currentMonth {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  DateTime get _earliestMonth =>
      DateTime(_currentMonth.year, _currentMonth.month - 11);

  String get _monthKey => formatWorkProfileMonth(_month);
  String get _periodLabel => formatWorkProfileMonthLabel(_month);

  bool get _viewAll => (_team?.scopeLabel ?? '').contains('全部');

  bool get _allowPersonDrilldown => _team?.allowPersonDrilldown == true;

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
    return (_team?.people ?? const <WorkProfileSafePerson>[])
        .where((item) {
          if (_selectedDepartmentId != null &&
              item.departmentId != _selectedDepartmentId) {
            return false;
          }
          if (query.isEmpty) return true;
          return item.name.toLowerCase().contains(query) ||
              item.username.toLowerCase().contains(query) ||
              item.title.toLowerCase().contains(query);
        })
        .toList(growable: false);
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
    setState(() {
      _loading = true;
      _error = null;
      _person = null;
    });
    try {
      final result = await WorkProfileService(
        session: widget.session,
      ).fetchTeam(month: _monthKey);
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await WorkProfileService(
        session: widget.session,
      ).fetchPerson(userId: person.userId, month: _monthKey);
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

  Future<void> _sharePerson(WorkProfileSafePerson person) async {
    final conversations = ConversationService(session: widget.session);
    final conversationId = await showConversationPickerSheet(
      context: context,
      service: conversations,
      title: '转发员工画像',
    );
    if (conversationId == null || conversationId <= 0 || !mounted) return;
    final share = WorkProfileChatShare(
      userId: person.userId,
      name: person.name,
      departmentName: person.departmentName,
      month: _monthKey,
      sharedAt: DateTime.now(),
    );
    try {
      final sent = await conversations.sendText(
        conversationId,
        '[员工画像] ${person.name} · $_periodLabel',
        payload: share.toMessagePayload(),
      );
      if (!mounted) return;
      if (sent == null || sent.id <= 0) throw Exception('IM 未返回消息记录');
      showDunesToast(context, '员工画像名片已转发');
    } catch (error) {
      if (mounted) {
        showDunesToast(
          context,
          '转发失败：${error.toString().replaceFirst('Exception: ', '')}',
          kind: DunesToastKind.error,
        );
      }
    }
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    if (next.isBefore(_earliestMonth) || next.isAfter(_currentMonth)) return;
    setState(() => _month = next);
    final person = _person;
    if (person == null) {
      unawaited(_loadTeam());
    } else {
      unawaited(_openPerson(person));
    }
  }

  Future<void> _pickMonth() async {
    final picked = await showDunesMonthPicker(
      context: context,
      initialMonth: _month,
      firstMonth: _earliestMonth,
      lastMonth: _currentMonth,
      title: '选择画像月份',
      accent: _profilePurple,
    );
    if (picked == null || !mounted) return;
    setState(() => _month = DateTime(picked.year, picked.month));
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
      color: DunesColors.resolve(
        context,
        const Color(0xFFF8F6FA),
        role: DunesColorRole.surface,
      ),
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
                    else if (!_allowPersonDrilldown || people.isEmpty)
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
          fillColor: DunesColors.resolve(
            context,
            Colors.white,
            role: DunesColorRole.surface,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: DunesColors.resolve(
                context,
                Color(0xFFE8EAED),
                role: DunesColorRole.border,
              ),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: DunesColors.resolve(
                context,
                Color(0xFFE8EAED),
                role: DunesColorRole.border,
              ),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: DunesColors.resolve(
                context,
                _profilePurple,
                role: DunesColorRole.border,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRangeFilter() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
    child: WorkProfileMonthBar(
      label: _periodLabel,
      canPrev: !_month.isAtSameMomentAs(_earliestMonth),
      canNext: !_month.isAtSameMomentAs(_currentMonth),
      onPrev: () => _shiftMonth(-1),
      onNext: () => _shiftMonth(1),
      onPick: () => unawaited(_pickMonth()),
      loading: _loading,
    ),
  );

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
              Text(
                '部门筛选',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.resolve(context, DunesColors.text2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _viewAll ? '全部门' : '管辖范围',
                style: TextStyle(
                  fontSize: 11,
                  color: DunesColors.resolveNullable(context, _profilePurple),
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
    decoration: BoxDecoration(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      border: Border(
        bottom: BorderSide(
          color: DunesColors.resolve(
            context,
            Color(0xFFE9E2EF),
            role: DunesColorRole.border,
          ),
        ),
      ),
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: '返回',
          onPressed: viewingPerson
              ? () => setState(() => _person = null)
              : widget.onBack,
          icon: Icon(
            Icons.arrow_back_rounded,
            color: DunesColors.resolveNullable(context, _profileInk),
          ),
        ),
        Expanded(
          child: Text(
            title,
            style: DunesTypography.sans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _profileInk,
              context: context,
            ),
          ),
        ),
        if (viewingPerson)
          IconButton(
            tooltip: '转发员工画像',
            onPressed: _loading || _person == null
                ? null
                : () => unawaited(_sharePerson(_person!)),
            icon: Icon(
              Icons.ios_share_rounded,
              color: DunesColors.resolveNullable(context, _profilePurple),
              size: 20,
            ),
          ),
        if (viewingPerson)
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Text(
              '管理参考',
              style: TextStyle(
                fontSize: 11,
                color: DunesColors.resolveNullable(context, _profileMuted),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _managementNotice() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF0EAF8),
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.shield_outlined,
          size: 18,
          color: DunesColors.resolveNullable(context, _profilePurple),
        ),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            '管理参考 · 展示任务、审批、会议和知识沉淀等业务记录，不读取聊天内容，不生成员工排名。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: DunesColors.resolveNullable(context, Color(0xFF5D536B)),
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
      WorkProfileRadarCard(
        dimensions: _personDimensions(person),
        monthLabel: _periodLabel,
      ),
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
        style: TextStyle(
          fontSize: 10.5,
          color: DunesColors.resolveNullable(context, _profileMuted),
        ),
      ),
    ],
  );

  Widget _personIdentity(WorkProfileSafePerson person) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          DunesColors.resolve(context, Color(0xFF604084)),
          DunesColors.resolve(context, Color(0xFF8E6BBC)),
        ],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: DunesColors.resolve(
            context,
            Colors.white24,
            role: DunesColorRole.surface,
          ),
          child: Text(
            person.name.isEmpty ? '员' : person.name.characters.first,
            style: TextStyle(
              color: DunesColors.resolve(context, Colors.white),
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
                style: TextStyle(
                  fontSize: 18,
                  color: DunesColors.resolve(context, Colors.white),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                [
                  person.departmentName,
                  person.title,
                ].where((part) => part.trim().isNotEmpty).join(' · '),
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolve(context, Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  List<UserWorkProfileDimension> _personDimensions(
    WorkProfileSafePerson person,
  ) => [
    UserWorkProfileDimension(
      label: '完成任务',
      value: person.taskCompleted,
      cap: 8,
      unit: '项',
      period: _periodLabel,
    ),
    UserWorkProfileDimension(
      label: '会议协作',
      value: person.meetings,
      cap: 20,
      unit: '场',
      period: _periodLabel,
    ),
    UserWorkProfileDimension(
      label: '知识沉淀',
      value: person.knowledgeDocuments,
      cap: 20,
      unit: '篇',
      period: '当前累计',
    ),
    UserWorkProfileDimension(
      label: '发起审批',
      value: person.approvalTotal,
      cap: 6,
      unit: '项',
      period: _periodLabel,
    ),
    UserWorkProfileDimension(
      label: '发起提案',
      value: person.proposalTotal,
      cap: 6,
      unit: '项',
      period: _periodLabel,
    ),
  ];

  Widget _employeeRow(WorkProfileSafePerson person) => Material(
    color: DunesColors.resolve(
      context,
      Colors.white,
      role: DunesColorRole.surface,
    ),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: _loading ? null : () => _openPerson(person),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: DunesColors.resolve(
              context,
              const Color(0xFFE9E2EF),
              role: DunesColorRole.border,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: DunesColors.resolve(
                    context,
                    const Color(0xFFF0EAF8),
                    role: DunesColorRole.surface,
                  ),
                  child: Text(
                    person.name.isEmpty ? '员' : person.name.characters.first,
                    style: TextStyle(
                      color: DunesColors.resolveNullable(
                        context,
                        _profilePurple,
                      ),
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
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: DunesColors.resolveNullable(
                            context,
                            _profileInk,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          person.departmentName,
                          person.title,
                        ].where((part) => part.trim().isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: DunesColors.resolveNullable(
                            context,
                            _profileMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '转发员工画像',
                  visualDensity: VisualDensity.compact,
                  onPressed: _loading
                      ? null
                      : () => unawaited(_sharePerson(person)),
                  icon: Icon(
                    Icons.ios_share_rounded,
                    size: 19,
                    color: DunesColors.resolveNullable(context, _profilePurple),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: DunesColors.resolveNullable(context, _profileMuted),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _employeeMetric('任务 ${person.taskTotal}', primary: true),
                _employeeMetric('完成 ${person.taskCompleted}'),
                _employeeMetric('进行中 ${person.taskDoing}'),
                _employeeMetric('逾期 ${person.taskOverdue}'),
                _employeeMetric('审批 ${person.approvalTotal}'),
                _employeeMetric('提案 ${person.proposalTotal}'),
                _employeeMetric('会议 ${person.meetings}'),
                _employeeMetric('知识 ${person.knowledgeDocuments}'),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _employeeMetric(String label, {bool primary = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: primary
          ? DunesColors.resolve(
              context,
              const Color(0xFFF0EAF8),
              role: DunesColorRole.surface,
            )
          : DunesColors.resolve(
              context,
              const Color(0xFFF7F5F9),
              role: DunesColorRole.surface,
            ),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10.5,
        color: primary
            ? DunesColors.resolve(context, _profilePurple)
            : DunesColors.resolve(context, _profileMuted),
        fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
  );

  Widget _section(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: DunesColors.resolve(
          context,
          const Color(0xFFE9E2EF),
          role: DunesColorRole.border,
        ),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: DunesColors.resolveNullable(context, _profileInk),
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
                style: TextStyle(
                  fontSize: 12,
                  color: DunesColors.resolveNullable(context, _profileMuted),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '来源 $source · ${period ?? _periodLabel}',
                style: TextStyle(
                  fontSize: 9.5,
                  color: DunesColors.resolveNullable(
                    context,
                    Color(0xFFAAA0B2),
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            color: DunesColors.resolveNullable(context, _profileInk),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _errorCard(String message) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: DunesColors.resolve(
          context,
          const Color(0xFFE9E2EF),
          role: DunesColorRole.border,
        ),
      ),
    ),
    child: Text(
      message,
      style: TextStyle(
        fontSize: 12,
        height: 1.5,
        color: DunesColors.resolveNullable(context, _profileMuted),
      ),
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
      color: selected
          ? DunesColors.resolve(
              context,
              const Color(0xFFF0EAF8),
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
                      _profilePurple,
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
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected
                  ? DunesColors.resolve(context, _profilePurple)
                  : DunesColors.resolve(context, const Color(0xFF5C5566)),
            ),
          ),
        ),
      ),
    );
  }
}
