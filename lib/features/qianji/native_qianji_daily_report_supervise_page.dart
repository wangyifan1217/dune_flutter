import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/widgets/horizontal_drag_scroll_view.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_service.dart';
import '../tasks/task_api.dart';
import '../tasks/task_avatar.dart';
import '../tasks/task_models.dart';
import '../shell/dunes_toast.dart';
import 'qianji_record_supervise_service.dart';

const _purple = Color(0xFF7054D8);

class NativeQianjiDailyReportSupervisePage extends StatefulWidget {
  const NativeQianjiDailyReportSupervisePage({
    super.key,
    required this.session,
    required this.onBack,
  });

  final AuthSession session;
  final VoidCallback onBack;

  @override
  State<NativeQianjiDailyReportSupervisePage> createState() =>
      _NativeQianjiDailyReportSupervisePageState();
}

class _NativeQianjiDailyReportSupervisePageState
    extends State<NativeQianjiDailyReportSupervisePage> {
  late final TaskApi _api = TaskApi(widget.session);
  late final QianjiRecordSuperviseService _records =
      QianjiRecordSuperviseService(
        session: widget.session,
        kind: QianjiRecordSuperviseKind.dailyReport,
      );
  final _search = TextEditingController();
  Timer? _searchDebounce;
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selectedDate = DateTime.now();
  TaskDailyReportCalendar? _calendar;
  int _loadVersion = 0;
  int _selectedDateRequest = 0;
  List<QianjiRecordSuperviseHit> _dayReports = const [];
  List<TaskAssignee> _people = const [];
  Map<int, TaskAssignee> _peopleById = const {};
  String? _department;
  bool _loading = true;
  bool _loadingReports = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final calendar = await _api.getTeamDailyReportCalendar(
        month: _month,
        q: _search.text,
      );
      if (!mounted || request != _loadVersion) return;
      setState(() {
        _calendar = calendar;
        if (_department != null &&
            !calendar.users.any((user) => user.departmentName == _department)) {
          _department = null;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _loadVersion) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
      return;
    }
    // Render the calendar first; avatar lookup and the selected day's details
    // are independent requests and should not hold up the initial screen.
    unawaited(_loadPeople());
    unawaited(_loadSelectedDateReports());
  }

  Future<void> _loadPeople() async {
    if (_people.isNotEmpty) return;
    try {
      final people = await _api.listAssignees(scope: 'reports');
      if (!mounted) return;
      setState(() {
        _people = people;
        _peopleById = {for (final person in people) person.id: person};
      });
    } catch (_) {}
  }

  Future<void> _loadSelectedDateReports() async {
    final request = ++_selectedDateRequest;
    final date = _dateKey(_selectedDate);
    setState(() => _loadingReports = true);
    try {
      final page = await _records.fetchListPage(
        page: 0,
        size: 100,
        reportDate: date,
      );
      if (!mounted || request != _selectedDateRequest) return;
      setState(() => _dayReports = page.items);
    } catch (_) {
      if (mounted && request == _selectedDateRequest) {
        setState(() => _dayReports = const []);
      }
    } finally {
      if (mounted && request == _selectedDateRequest) {
        setState(() => _loadingReports = false);
      }
    }
  }

  void _onSearchChanged() {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_load());
    });
  }

  Future<void> _changeMonth(int delta) async {
    final next = DateTime(_month.year, _month.month + delta);
    final lastDay = DateTime(next.year, next.month + 1, 0).day;
    setState(() {
      _month = next;
      _selectedDate = DateTime(
        next.year,
        next.month,
        _selectedDate.day.clamp(1, lastDay).toInt(),
      );
    });
    await _load();
  }

  List<TaskDailyReportCalendarUser> get _visibleUsers {
    final users = _calendar?.users ?? const <TaskDailyReportCalendarUser>[];
    final department = _department;
    if (department == null) return users;
    return users.where((user) => user.departmentName == department).toList();
  }

  List<String> get _departments {
    final users = _calendar?.users ?? const <TaskDailyReportCalendarUser>[];
    final departments =
        users
            .map((user) => user.departmentName.trim())
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return departments;
  }

  TaskDailyReportCalendarDay? _dayFor(
    TaskDailyReportCalendarUser user,
    DateTime date,
  ) {
    final key = _dateKey(date);
    for (final day in user.days) {
      if (day.date == key) return day;
    }
    return null;
  }

  Map<String, int> _countsFor(DateTime date) {
    final counts = <String, int>{
      'submitted': 0,
      'missing': 0,
      'pending': 0,
      'leave': 0,
      'rest': 0,
      'upcoming': 0,
    };
    for (final user in _visibleUsers) {
      final status = _dayFor(user, date)?.status ?? 'pending';
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _monthLabel(DateTime date) => '${date.year}年${date.month}月';

  String _selectedDateLabel(DateTime date) =>
      '${date.year}年${date.month}月${date.day}日 · ${_weekday(date.weekday)}';

  String _weekday(int weekday) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][weekday - 1];

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF5F6F8),
        role: DunesColorRole.surface,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            _searchBox(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _loadError()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 36),
                        children: [
                          _departmentFilter(),
                          const SizedBox(height: 12),
                          _monthHeader(),
                          const SizedBox(height: 10),
                          _monthOverview(),
                          const SizedBox(height: 10),
                          _calendarGrid(),
                          const SizedBox(height: 18),
                          _selectedDateReports(),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(8, 10, 16, 4),
    child: Row(
      children: [
        IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
          color: DunesColors.resolve(context, DunesColors.text2),
          tooltip: '返回',
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Text(
            '日报监控',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: DunesColors.resolveNullable(context, _purple),
            ),
          ),
        ),
        Text(
          '${_calendar?.users.length ?? 0} 位员工',
          style: TextStyle(
            fontSize: 12,
            color: DunesColors.resolve(context, DunesColors.text2),
          ),
        ),
      ],
    ),
  );

  Widget _searchBox() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: TextField(
      controller: _search,
      onChanged: (_) => _onSearchChanged(),
      decoration: InputDecoration(
        hintText: '搜索员工姓名',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        filled: true,
        fillColor: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: DunesColors.resolve(
              context,
              Color(0xFFE7E8EC),
              role: DunesColorRole.border,
            ),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: DunesColors.resolve(
              context,
              Color(0xFFE7E8EC),
              role: DunesColorRole.border,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _departmentFilter() {
    final departments = _departments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '部门筛选',
              style: TextStyle(
                fontSize: 12,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '当前范围 ${_visibleUsers.length} 人',
              style: TextStyle(
                fontSize: 11,
                color: DunesColors.resolveNullable(context, _purple),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        HorizontalDragScrollView(
          child: Row(
            children: [
              _departmentChip('全部部门', null),
              for (final department in departments) ...[
                const SizedBox(width: 7),
                _departmentChip(department, department),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _departmentChip(String label, String? value) {
    final selected = _department == value;
    return Material(
      color: selected
          ? DunesColors.resolve(
              context,
              const Color(0xFFF0EBFC),
              role: DunesColorRole.surface,
            )
          : DunesColors.resolve(
              context,
              Colors.white,
              role: DunesColorRole.surface,
            ),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _department = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? DunesColors.resolve(
                      context,
                      _purple,
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      const Color(0xFFE5E6EB),
                      role: DunesColorRole.border,
                    ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? DunesColors.resolve(context, _purple)
                  : DunesColors.resolve(context, DunesColors.text2),
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _monthHeader() => Row(
    children: [
      IconButton(
        onPressed: () => unawaited(_changeMonth(-1)),
        icon: const Icon(Icons.chevron_left_rounded),
        tooltip: '上个月',
      ),
      Expanded(
        child: Center(
          child: Text(
            _monthLabel(_month),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      TextButton(
        onPressed: () {
          final now = DateTime.now();
          setState(() {
            _month = DateTime(now.year, now.month);
            _selectedDate = now;
          });
          unawaited(_load());
        },
        child: const Text('本月'),
      ),
      IconButton(
        onPressed: () => unawaited(_changeMonth(1)),
        icon: const Icon(Icons.chevron_right_rounded),
        tooltip: '下个月',
      ),
    ],
  );

  Widget _monthOverview() {
    var submitted = 0;
    var missing = 0;
    var pending = 0;
    for (final user in _visibleUsers) {
      for (final day in user.days) {
        switch (day.status) {
          case 'submitted':
            submitted++;
            break;
          case 'missing':
            missing++;
            break;
          case 'pending':
            pending++;
            break;
        }
      }
    }
    final expected = submitted + missing + pending;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: DunesColors.resolve(
          context,
          Colors.white,
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: DunesColors.resolve(
            context,
            const Color(0xFFE8E8ED),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Row(
        children: [
          _summaryValue(
            '本月应填',
            expected,
            DunesColors.resolve(context, DunesColors.text),
          ),
          _summaryValue(
            '已提交',
            submitted,
            DunesColors.resolve(context, const Color(0xFF23866B)),
          ),
          _summaryValue(
            '漏交',
            missing,
            DunesColors.resolve(context, const Color(0xFFBE123C)),
          ),
          _summaryValue(
            '待填',
            pending,
            DunesColors.resolve(context, const Color(0xFFB7791F)),
          ),
        ],
      ),
    );
  }

  Widget _summaryValue(String label, int value, Color color) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: DunesColors.resolveNullable(context, color),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: DunesColors.resolve(context, DunesColors.text3),
          ),
        ),
      ],
    ),
  );

  Widget _calendarGrid() {
    final calendar = _calendar;
    if (calendar == null || calendar.days.isEmpty)
      return const SizedBox.shrink();
    final first = DateTime.tryParse(calendar.days.first);
    final leading = first?.weekday == null ? 0 : first!.weekday - 1;
    final count = calendar.days.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 13),
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
            const Color(0xFFE8E8ED),
            role: DunesColorRole.border,
          ),
        ),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              _WeekLabel('一'),
              _WeekLabel('二'),
              _WeekLabel('三'),
              _WeekLabel('四'),
              _WeekLabel('五'),
              _WeekLabel('六'),
              _WeekLabel('日'),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 5,
              mainAxisSpacing: 5,
              childAspectRatio: .92,
            ),
            itemCount: leading + count,
            itemBuilder: (context, index) {
              if (index < leading) return const SizedBox.shrink();
              final date = DateTime.tryParse(calendar.days[index - leading]);
              if (date == null) return const SizedBox.shrink();
              final counts = _countsFor(date);
              final expected =
                  counts['submitted']! +
                  counts['missing']! +
                  counts['pending']!;
              final selected = _dateKey(date) == _dateKey(_selectedDate);
              final submitted = counts['submitted']!;
              final complete = expected > 0 && submitted == expected;
              final partial = submitted > 0 && submitted < expected;
              final color = expected == 0
                  ? DunesColors.resolve(context, const Color(0xFF8290A5))
                  : complete
                  ? DunesColors.resolve(context, const Color(0xFF168567))
                  : partial
                  ? DunesColors.resolve(context, const Color(0xFFB7791F))
                  : counts['missing']! > 0
                  ? DunesColors.resolve(context, const Color(0xFFBE123C))
                  : DunesColors.resolve(context, const Color(0xFFD97706));
              final background = expected == 0
                  ? (selected
                        ? DunesColors.resolve(
                            context,
                            const Color(0xFFEFE9FF),
                            role: DunesColorRole.surface,
                          )
                        : DunesColors.resolve(
                            context,
                            const Color(0xFFF9F8FB),
                            role: DunesColorRole.surface,
                          ))
                  : Color.alphaBlend(
                      color.withValues(alpha: complete ? 0.13 : 0.09),
                      selected
                          ? DunesColors.resolve(
                              context,
                              const Color(0xFFEFE9FF),
                              role: DunesColorRole.surface,
                            )
                          : DunesColors.resolve(
                              context,
                              const Color(0xFFF9F8FB),
                              role: DunesColorRole.surface,
                            ),
                    );
              final noDueLabel = counts['leave']! > 0
                  ? '请假'
                  : counts['upcoming']! > 0
                  ? '未到'
                  : '休息';
              return InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () {
                  setState(() => _selectedDate = date);
                  unawaited(_loadSelectedDateReports());
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: DunesColors.resolveNullable(
                      context,
                      background,
                      role: DunesColorRole.surface,
                    ),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: selected
                          ? DunesColors.resolve(
                              context,
                              _purple,
                              role: DunesColorRole.border,
                            )
                          : expected > 0
                          ? color.withValues(alpha: 0.42)
                          : DunesColors.resolve(
                              context,
                              const Color(0xFFEDEBF1),
                              role: DunesColorRole.border,
                            ),
                      width: selected ? 1.4 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? DunesColors.resolve(context, _purple)
                              : DunesColors.resolve(context, DunesColors.text),
                        ),
                      ),
                      if (expected > 0) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${counts['submitted']}/$expected',
                          style: TextStyle(
                            fontSize: 8,
                            color: DunesColors.resolveNullable(context, color),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ] else
                        Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            noDueLabel,
                            style: TextStyle(
                              fontSize: 8,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text3,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              _LegendDot(
                '全部提交',
                DunesColors.resolve(context, Color(0xFF168567)),
              ),
              _LegendDot(
                '部分提交',
                DunesColors.resolve(context, Color(0xFFB7791F)),
              ),
              _LegendDot('待填', DunesColors.resolve(context, Color(0xFFD97706))),
              _LegendDot('漏交', DunesColors.resolve(context, Color(0xFFBE123C))),
              _LegendDot('未到', DunesColors.resolve(context, Color(0xFF8290A5))),
              _LegendDot(
                '请假 / 休息',
                DunesColors.resolve(context, Color(0xFF8290A5)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _selectedDateReports() {
    final counts = _countsFor(_selectedDate);
    final users = _visibleUsers;
    final order = {
      'missing': 0,
      'pending': 1,
      'submitted': 2,
      'leave': 3,
      'rest': 4,
    };
    final sorted = [...users]
      ..sort((a, b) {
        final sa = _dayFor(a, _selectedDate)?.status ?? 'pending';
        final sb = _dayFor(b, _selectedDate)?.status ?? 'pending';
        return (order[sa] ?? 5).compareTo(order[sb] ?? 5);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _selectedDateLabel(_selectedDate),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '已填 ${counts['submitted']} / 应填 ${counts['submitted']! + counts['missing']! + counts['pending']!}',
              style: TextStyle(
                fontSize: 11,
                color: DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingReports)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (sorted.isEmpty)
          const _EmptyReportPeople()
        else
          for (final user in sorted) ...[
            _DailyReportPersonRow(
              session: widget.session,
              user: user,
              status: _dayFor(user, _selectedDate)?.status ?? 'pending',
              report: _reportForUser(user.userId),
              date: _dateKey(_selectedDate),
              avatar: _peopleById[user.userId],
              onOpen: () => _openReport(user),
              onForward: () => unawaited(_forwardReport(user)),
            ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  QianjiRecordSuperviseHit? _reportForUser(int userId) {
    for (final report in _dayReports) {
      if (report.userId == userId) return report;
    }
    return null;
  }

  Future<TaskDailyReport?> _loadReport(TaskDailyReportCalendarUser user) async {
    final bundle = await _api.getDailyReport(
      date: _selectedDate,
      userId: user.userId,
    );
    return bundle.report;
  }

  Future<void> _openReport(TaskDailyReportCalendarUser user) async {
    final day = _dayFor(user, _selectedDate);
    if (day == null || day.status != 'submitted') return;
    try {
      final report = await _loadReport(user);
      if (!mounted || report == null) return;
      await showQianjiDailyReportDetail(
        context: context,
        userName: user.userName,
        departmentName: user.departmentName,
        report: report,
      );
    } catch (error) {
      if (mounted) {
        showDunesToast(
          context,
          '读取日报失败：${friendlyErrorText(error, fallback: '请稍后重试')}',
          kind: DunesToastKind.error,
        );
      }
    }
  }

  Future<void> _forwardReport(TaskDailyReportCalendarUser user) async {
    final status = _dayFor(user, _selectedDate)?.status ?? 'pending';
    TaskDailyReport? report;
    if (status == 'submitted') {
      try {
        report = await _loadReport(user);
      } catch (error) {
        if (mounted) {
          showDunesToast(
            context,
            '读取日报失败：${friendlyErrorText(error)}',
            kind: DunesToastKind.error,
          );
        }
        return;
      }
    }
    if (!mounted) return;
    final conversationId = await showConversationPickerSheet(
      context: context,
      service: ConversationService(session: widget.session),
      title: '转发日报名片',
    );
    if (conversationId == null || conversationId <= 0 || !mounted) return;
    final payload = QianjiDailyReportShareCard.toPayload(
      userName: user.userName,
      departmentName: user.departmentName,
      reportDate: _dateKey(_selectedDate),
      status: status,
      userId: user.userId,
      avatar: _peopleById[user.userId],
      report: report,
    );
    try {
      await ConversationService(session: widget.session).sendText(
        conversationId,
        '[日报名片] ${user.userName} · ${_dateKey(_selectedDate)} · ${_statusLabel(status)}',
        payload: payload,
      );
      if (mounted) showDunesToast(context, '日报名片已转发');
    } catch (error) {
      if (mounted) {
        showDunesToast(
          context,
          '转发失败：${friendlyErrorText(error, fallback: '请稍后重试')}',
          kind: DunesToastKind.error,
        );
      }
    }
  }

  Widget _loadError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            friendlyErrorText(_error, fallback: '加载失败，请稍后重试'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('重试')),
        ],
      ),
    ),
  );
}

String _statusLabel(String status) => switch (status) {
  'submitted' => '已提交',
  'missing' => '漏交',
  'pending' => '待填',
  'leave' => '请假',
  'upcoming' => '未到',
  _ => '休息日',
};

Color _statusColor(String status) => switch (status) {
  'submitted' => const Color(0xFF23866B),
  'missing' => const Color(0xFFBE123C),
  'pending' => const Color(0xFFB7791F),
  'leave' => const Color(0xFF4C7FD4),
  'upcoming' => const Color(0xFF8290A5),
  _ => const Color(0xFF8290A5),
};

class _DailyReportPersonRow extends StatelessWidget {
  const _DailyReportPersonRow({
    required this.session,
    required this.user,
    required this.status,
    required this.report,
    required this.date,
    required this.avatar,
    required this.onOpen,
    required this.onForward,
  });

  final AuthSession session;
  final TaskDailyReportCalendarUser user;
  final String status;
  final QianjiRecordSuperviseHit? report;
  final String date;
  final TaskAssignee? avatar;
  final VoidCallback onOpen;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: status == 'submitted' ? onOpen : null,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.fromLTRB(13, 12, 8, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                const Color(0xFFE8E8ED),
                role: DunesColorRole.border,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildTaskUserAvatar(
                session: session,
                name: user.userName,
                userId: user.userId,
                avatarPreset: avatar?.avatarPreset ?? '',
                avatarObjectKey: avatar?.avatarObjectKey ?? '',
                avatarUrl: avatar?.avatarUrl ?? '',
                size: 42,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.userName.isEmpty
                                ? '员工${user.userId}'
                                : user.userName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: DunesColors.resolveNullable(
                              context,
                              color.withValues(alpha: .10),
                              role: DunesColorRole.surface,
                            ),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Text(
                            _statusLabel(status),
                            style: TextStyle(
                              fontSize: 10,
                              color: DunesColors.resolveNullable(
                                context,
                                color,
                              ),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (user.departmentName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        user.departmentName,
                        style: TextStyle(
                          fontSize: 11,
                          color: DunesColors.resolve(
                            context,
                            DunesColors.text3,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      status == 'submitted'
                          ? (report?.subtitle.isNotEmpty == true
                                ? report!.subtitle
                                : '日报已提交，点击查看内容')
                          : status == 'missing'
                          ? '工作日未提交，已计入漏交'
                          : status == 'pending'
                          ? '尚未到补交截止时间'
                          : status == 'leave'
                          ? '已同步请假记录'
                          : status == 'upcoming'
                          ? '日期未到'
                          : '非工作日',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: DunesColors.resolve(context, DunesColors.text2),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            date,
                            style: TextStyle(
                              fontSize: 10,
                              color: DunesColors.resolve(
                                context,
                                DunesColors.text3,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: onForward,
                          visualDensity: VisualDensity.compact,
                          tooltip: '转发日报名片',
                          icon: Icon(
                            Icons.forward_to_inbox_rounded,
                            color: DunesColors.resolveNullable(
                              context,
                              _purple,
                            ),
                            size: 19,
                          ),
                        ),
                        if (status == 'submitted')
                          Icon(
                            Icons.chevron_right_rounded,
                            color: DunesColors.resolveNullable(
                              context,
                              Color(0xFF9A95A3),
                            ),
                            size: 20,
                          ),
                      ],
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

class _WeekLabel extends StatelessWidget {
  const _WeekLabel(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Center(
      child: Text(
        value,
        style: TextStyle(
          fontSize: 10,
          color: DunesColors.resolve(context, DunesColors.text3),
        ),
      ),
    ),
  );
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.label, this.color);
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: DunesColors.resolveNullable(
            context,
            color,
            role: DunesColorRole.surface,
          ),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: DunesColors.resolve(context, DunesColors.text3),
        ),
      ),
    ],
  );
}

class _EmptyReportPeople extends StatelessWidget {
  const _EmptyReportPeople();
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(22),
    child: Center(
      child: Text(
        '当前筛选下没有员工记录',
        style: TextStyle(
          color: DunesColors.resolve(context, DunesColors.text3),
        ),
      ),
    ),
  );
}

Future<void> showQianjiDailyReportDetail({
  required BuildContext context,
  required String userName,
  required String departmentName,
  required TaskDailyReport report,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) => SafeArea(
    top: false,
    child: Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * .86,
      ),
      decoration: BoxDecoration(
        color: DunesColors.resolveNullable(
          context,
          Color(0xFFF5F4F8),
          role: DunesColorRole.surface,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: DunesColors.resolve(
                context,
                const Color(0xFFD6D2DC),
                role: DunesColorRole.surface,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 10, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$userName · ${report.reportDate} 日报',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (departmentName.isNotEmpty)
                        Text(
                          departmentName,
                          style: TextStyle(
                            fontSize: 11,
                            color: DunesColors.resolve(
                              context,
                              DunesColors.text3,
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        _statusLabel(report.status),
                        style: TextStyle(
                          fontSize: 11,
                          color: DunesColors.resolveNullable(
                            context,
                            _statusColor(report.status),
                          ),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(15),
              children: [
                if (report.summary.trim().isNotEmpty)
                  _reportSection('今日总结', report.summary),
                if (report.items.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(2, 12, 2, 8),
                    child: Text(
                      '任务进展',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final item in report.items)
                    _reportSection(
                      item.taskTitle.isEmpty ? '工作事项' : item.taskTitle,
                      item.workDone.isEmpty ? item.nextAction : item.workDone,
                    ),
                ],
                if (report.blockers.trim().isNotEmpty)
                  _reportSection('困难与阻塞', report.blockers),
                if (report.nextPlan.trim().isNotEmpty)
                  _reportSection('明日计划', report.nextPlan),
                if (report.summary.trim().isEmpty &&
                    report.items.isEmpty &&
                    report.blockers.trim().isEmpty &&
                    report.nextPlan.trim().isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      report.status == 'submitted'
                          ? '日报已提交，暂无可展示内容'
                          : '当前状态：${_statusLabel(report.status)}',
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

Widget _reportSection(String title, String body) => Container(
  margin: const EdgeInsets.only(bottom: 8),
  padding: const EdgeInsets.all(13),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: _purple,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        body,
        style: const TextStyle(
          fontSize: 13,
          height: 1.5,
          color: DunesColors.text2,
        ),
      ),
    ],
  ),
);

class QianjiDailyReportShareCard extends StatelessWidget {
  const QianjiDailyReportShareCard({
    super.key,
    required this.session,
    required this.payload,
    required this.onTap,
  });
  final AuthSession session;
  final Map<String, dynamic> payload;
  final VoidCallback onTap;

  static Map<String, dynamic>? payloadData(Map<String, dynamic>? message) {
    final raw = message?['dailyReportPersonCard'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  static Map<String, dynamic> toPayload({
    required String userName,
    required String departmentName,
    required String reportDate,
    required String status,
    int userId = 0,
    TaskAssignee? avatar,
    TaskDailyReport? report,
  }) => {
    'dailyReportPersonCard': {
      'version': 1,
      'userName': userName,
      'departmentName': departmentName,
      'reportDate': reportDate,
      'status': status,
      'userId': userId,
      'avatarPreset': avatar?.avatarPreset ?? '',
      'avatarObjectKey': avatar?.avatarObjectKey ?? '',
      'avatarUrl': avatar?.avatarUrl ?? '',
      if (report != null) 'summary': report.summary,
      if (report != null) 'blockers': report.blockers,
      if (report != null) 'nextPlan': report.nextPlan,
      if (report != null)
        'items': [
          for (final item in report.items)
            {
              'taskTitle': item.taskTitle,
              'workDone': item.workDone,
              'nextAction': item.nextAction,
            },
        ],
    },
  };

  static TaskDailyReport? reportFromPayload(Map<String, dynamic>? message) {
    final data = payloadData(message);
    if (data == null) return null;
    final rawItems = data['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map((raw) {
                final item = Map<String, dynamic>.from(raw);
                return TaskDailyReportItem(
                  taskId: 0,
                  taskTitle: '${item['taskTitle'] ?? ''}',
                  workDone: '${item['workDone'] ?? ''}',
                  nextAction: '${item['nextAction'] ?? ''}',
                );
              })
              .toList(growable: false)
        : const <TaskDailyReportItem>[];
    return TaskDailyReport(
      userId: (data['userId'] as num?)?.toInt() ?? 0,
      reportDate: '${data['reportDate'] ?? ''}',
      status: '${data['status'] ?? ''}',
      summary: '${data['summary'] ?? ''}',
      blockers: '${data['blockers'] ?? ''}',
      nextPlan: '${data['nextPlan'] ?? ''}',
      items: items,
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = '${payload['status'] ?? 'pending'}';
    final color = _statusColor(status);
    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                const Color(0xFFE8E3F4),
                role: DunesColorRole.border,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  buildTaskUserAvatar(
                    session: session,
                    name: '${payload['userName'] ?? ''}',
                    userId: (payload['userId'] as num?)?.toInt() ?? 0,
                    avatarPreset: '${payload['avatarPreset'] ?? ''}',
                    avatarObjectKey: '${payload['avatarObjectKey'] ?? ''}',
                    avatarUrl: '${payload['avatarUrl'] ?? ''}',
                    size: 36,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '沙丘日报',
                      style: TextStyle(
                        fontSize: 11,
                        color: DunesColors.resolveNullable(context, _purple),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    _statusLabel(status),
                    style: TextStyle(
                      fontSize: 10,
                      color: DunesColors.resolveNullable(context, color),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                '${payload['userName'] ?? '员工'} · ${payload['reportDate'] ?? ''}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if ('${payload['departmentName'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  '${payload['departmentName']}',
                  style: TextStyle(
                    fontSize: 11,
                    color: DunesColors.resolve(context, DunesColors.text3),
                  ),
                ),
              ],
              if ('${payload['summary'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '${payload['summary']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: DunesColors.resolve(context, DunesColors.text2),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '点击查看日报明细',
                      style: TextStyle(
                        fontSize: 10,
                        color: DunesColors.resolve(context, DunesColors.text3),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: DunesColors.resolveNullable(context, _purple),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
