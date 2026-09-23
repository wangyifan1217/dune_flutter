import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'task_api.dart';
import 'task_first_use_guide.dart';
import 'task_inbox.dart';
import 'task_models.dart';
import 'task_widgets.dart';

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: DunesColors.text3)),
      ],
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: DunesColors.text3),
        ),
      ),
    );
  }
}

class NativeTaskDailyReportPage extends StatefulWidget {
  const NativeTaskDailyReportPage({
    super.key,
    required this.session,
    this.initialDate,
    required this.onBack,
  });

  final AuthSession session;
  final DateTime? initialDate;
  final VoidCallback onBack;

  @override
  State<NativeTaskDailyReportPage> createState() =>
      _NativeTaskDailyReportPageState();
}

class _DraftLine {
  _DraftLine(this.task)
    : progress = task.progressPct.toDouble(),
      work = TextEditingController(),
      next = TextEditingController();

  final TaskItem task;
  double progress;
  final TextEditingController work;
  final TextEditingController next;
}

class _NativeTaskDailyReportPageState extends State<NativeTaskDailyReportPage> {
  late final TaskApi _api = TaskApi(widget.session);
  late DateTime _date = widget.initialDate ?? DateTime.now();
  TaskDailyReportBundle? _bundle;
  List<_DraftLine> _lines = [];
  final _blockers = TextEditingController();
  final _otherWork = TextEditingController();
  final _nextPlan = TextEditingController();
  List<TaskDailyReport> _history = const [];
  TaskDailyReportCalendar? _calendar;
  bool _loading = true;
  bool _calendarLoading = false;
  bool _saving = false;
  bool _showHistory = false;
  bool _showCalendar = false;
  bool _teamCalendar = false;
  bool _guideAutoStarted = false;
  bool _showQuiet = false;
  int? _viewUserId;
  String _viewUserName = '';
  final _comment = TextEditingController();
  bool _commenting = false;
  Map<int, String> _previousNext = const {};
  final _lineListeners = <TextEditingController, VoidCallback>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
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
      page: TaskGuidePage.dailyReport,
      force: force,
    );
  }

  @override
  void dispose() {
    _blockers.dispose();
    _otherWork.dispose();
    _nextPlan.dispose();
    _comment.dispose();
    _disposeLines(_lines);
    super.dispose();
  }

  void _disposeLines(List<_DraftLine> lines) {
    for (final line in lines) {
      final workListener = _lineListeners.remove(line.work);
      if (workListener != null) line.work.removeListener(workListener);
      final nextListener = _lineListeners.remove(line.next);
      if (nextListener != null) line.next.removeListener(nextListener);
      line.work.dispose();
      line.next.dispose();
    }
  }

  void _watchLine(_DraftLine line) {
    void listen(TextEditingController controller) {
      void listener() {
        if (mounted) setState(() {});
      }

      _lineListeners[controller] = listener;
      controller.addListener(listener);
    }

    listen(line.work);
    listen(line.next);
  }

  bool _lineNeedsAttention(_DraftLine line) {
    if (line.work.text.trim().isNotEmpty || line.next.text.trim().isNotEmpty) {
      return true;
    }
    if (line.progress.round() != line.task.progressPct) return true;
    if (line.task.overdue || taskDueOnDay(line.task, _date)) return true;
    return false;
  }

  void _markNoProgress() {
    for (final line in _lines) {
      if (line.work.text.trim().isEmpty) line.work.text = '无进展';
    }
    setState(() => _showQuiet = false);
  }

  void _reusePreviousNext() {
    var copied = 0;
    for (final line in _lines) {
      final previous = _previousNext[line.task.id];
      if (previous == null || previous.isEmpty || line.next.text.trim().isNotEmpty) {
        continue;
      }
      line.next.text = previous;
      copied++;
    }
    if (copied == 0) {
      showDunesCenterToast(context, '没有可沿用的下一步');
      return;
    }
    showDunesCenterToast(context, '已沿用 $copied 条下一步');
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final viewingOther =
          _viewUserId != null && _viewUserId != widget.session.userId;
      final bundle = await _api.getDailyReport(
        date: _date,
        userId: viewingOther ? _viewUserId : null,
      );
      if (!mounted) return;
      _disposeLines(_lines);
      final submitted = bundle.report;
      final lines = <_DraftLine>[];
      if (submitted != null && submitted.items.isNotEmpty) {
        for (final item in submitted.items) {
          final match = bundle.candidates.where((t) => t.id == item.taskId);
          final task = match.isNotEmpty
              ? match.first
              : TaskItem(
                  id: item.taskId,
                  title: item.taskTitle,
                  ownerUserId: 0,
                  creatorUserId: 0,
                  parentId: item.isItem ? item.mainTaskId : null,
                  progressPct: item.progressPct,
                );
          final line = _DraftLine(task);
          line.progress = item.progressPct.toDouble();
          line.work.text = item.workDone;
          line.next.text = item.nextAction;
          _watchLine(line);
          lines.add(line);
        }
      } else {
        for (final task in bundle.candidates) {
          final line = _DraftLine(task);
          _watchLine(line);
          lines.add(line);
        }
      }
      _blockers.text = submitted?.blockers ?? '';
      _otherWork.text = submitted?.summary ?? '';
      _nextPlan.text = submitted?.nextPlan ?? '';
      setState(() {
        _bundle = bundle;
        _lines = lines;
        _showQuiet = false;
        _loading = false;
      });
      if (!viewingOther) unawaited(_loadPreviousNext());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadPreviousNext() async {
    try {
      final history = await _api.listDailyReportHistory(size: 20);
      final day = DateTime(_date.year, _date.month, _date.day);
      TaskDailyReport? previous;
      for (final report in history) {
        final parsed = DateTime.tryParse(report.reportDate);
        if (parsed == null) continue;
        final reportDay = DateTime(parsed.year, parsed.month, parsed.day);
        if (reportDay.isBefore(day)) {
          previous = report;
          break;
        }
      }
      if (previous == null || !mounted) return;
      var items = previous.items;
      if (items.isEmpty) {
        final bundle = await _api.getDailyReport(
          date: DateTime.parse(previous.reportDate),
        );
        items = bundle.report?.items ?? const [];
      }
      final nextByTask = <int, String>{};
      for (final item in items) {
        final next = item.nextAction.trim();
        if (next.isNotEmpty) nextByTask[item.taskId] = next;
      }
      if (mounted) setState(() => _previousNext = nextByTask);
    } catch (_) {}
  }

  Future<void> _loadHistory() async {
    try {
      final list = await _api.listDailyReportHistory();
      if (mounted) setState(() => _history = list);
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    }
  }

  Future<void> _loadCalendar({bool team = false}) async {
    setState(() {
      _calendarLoading = true;
      _teamCalendar = team;
    });
    try {
      final calendar = team
          ? await _api.getTeamDailyReportCalendar(month: _date)
          : await _api.getDailyReportCalendar(month: _date);
      if (mounted) setState(() => _calendar = calendar);
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _calendarLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showTaskDatePicker(
      context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 14)),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
    await _reload();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final items = <Map<String, dynamic>>[];
    for (final line in _lines) {
      final work = line.work.text.trim();
      if (work.isEmpty) continue;
      items.add({
        'taskId': line.task.id,
        'progressPct': line.progress.round().clamp(0, 100),
        'workDone': work,
        'nextAction': line.next.text.trim(),
      });
    }
    if (items.isEmpty &&
        _otherWork.text.trim().isEmpty &&
        _nextPlan.text.trim().isEmpty) {
      showDunesCenterToast(context, '请至少填写一条任务进展、其他工作或明日计划');
      return;
    }
    for (final line in _lines) {
      if (line.work.text.trim().isEmpty &&
          line.progress != line.task.progressPct) {
        showDunesCenterToast(context, '「${line.task.title}」改了进度，请填写今日完成');
        return;
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认提交日报'),
        content: Text(
          _bundle?.canBackfill == true
              ? '这是补填，提交时间会如实记录，不会改成按时提交。'
              : '确认提交 ${formatTaskYmd(_date)} 的日报？进度会同步到对应任务。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kTaskPurple),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _api.submitDailyReport({
        'reportDate': formatTaskYmd(_date),
        'summary': _otherWork.text.trim(),
        'blockers': _blockers.text.trim(),
        'nextPlan': _nextPlan.text.trim(),
        'items': items,
      });
      if (!mounted) return;
      showDunesCenterToast(context, '日报已提交');
      await _reload();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TaskTheme(
      child: Material(
      color: DunesColors.bgApp,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.onBack,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.arrow_back_ios_new,
                          size: 14,
                          color: DunesColors.text2,
                        ),
                        SizedBox(width: 2),
                        Text(
                          '返回',
                          style: TextStyle(
                            fontSize: 13,
                            color: DunesColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '使用指引',
                            onPressed: () => unawaited(_showGuide(force: true)),
                            icon: const Icon(
                              Icons.help_outline,
                              color: DunesColors.text2,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _showHistory = !_showHistory;
                                _showCalendar = false;
                              });
                              if (_showHistory) unawaited(_loadHistory());
                            },
                            child: Text(_showHistory ? '返回填写' : '历史日报'),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _showCalendar = !_showCalendar;
                                _showHistory = false;
                              });
                              if (_showCalendar) unawaited(_loadCalendar());
                            },
                            child: Text(_showCalendar ? '返回填写' : '月历'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _showCalendar
                ? _buildCalendar()
                : (_showHistory ? _buildHistory() : _buildForm()),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildCalendar() {
    if (_calendarLoading && _calendar == null) {
      return const Center(child: CircularProgressIndicator(color: kTaskPurple));
    }
    final calendar = _calendar;
    if (calendar == null) {
      return const Center(
        child: Text('暂无日报日历数据', style: TextStyle(color: DunesColors.text3)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '上月',
              onPressed: () {
                setState(() => _date = DateTime(_date.year, _date.month - 1));
                unawaited(_loadCalendar(team: _teamCalendar));
              },
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                '${calendar.month} 日报状态',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: '下月',
              onPressed: () {
                setState(() => _date = DateTime(_date.year, _date.month + 1));
                unawaited(_loadCalendar(team: _teamCalendar));
              },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TaskFilterChipDropdown<bool>(
            value: _teamCalendar,
            label: _teamCalendar ? '团队月历' : '我的月历',
            items: const [
              (false, '我的日报月历'),
              (true, '团队日报月历'),
            ],
            onChanged: (team) => unawaited(_loadCalendar(team: team)),
          ),
        ),
        const SizedBox(height: 8),
        _calendarSummary(calendar.summary),
        const SizedBox(height: 14),
        if (_teamCalendar) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              '点某一天查看该成员的日报',
              style: TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
          ),
          _teamCalendarTable(calendar),
        ] else
          _personalCalendarGrid(calendar),
        const SizedBox(height: 12),
        const Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            _CalendarLegend('已填', Color(0xFF1F9D76)),
            _CalendarLegend('请假', Color(0xFF4C7FD4)),
            _CalendarLegend('漏交', Color(0xFFBE123C)),
            _CalendarLegend('待填', Color(0xFFB45309)),
            _CalendarLegend('休息日', Color(0xFF94A3B8)),
          ],
        ),
      ],
    );
  }

  Widget _calendarSummary(TaskDailyReportCalendarSummary summary) {
    return Row(
      children: [
        _summaryTile('应填', summary.expected, DunesColors.text),
        _summaryTile('已填', summary.submitted, const Color(0xFF1F9D76)),
        _summaryTile('请假', summary.leave, const Color(0xFF4C7FD4)),
        _summaryTile('漏交', summary.missing, const Color(0xFFBE123C)),
      ],
    );
  }

  Widget _summaryTile(String label, int value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text('$value', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(fontSize: 11, color: DunesColors.text3)),
          ],
        ),
      ),
    );
  }

  Widget _personalCalendarGrid(TaskDailyReportCalendar calendar) {
    final days = calendar.users.isEmpty
        ? const <TaskDailyReportCalendarDay>[]
        : calendar.users.first.days;
    final first = days.isEmpty ? null : DateTime.tryParse(days.first.date);
    // 周一为一列起点。接口从当月 1 号排起，前面补空格，避免日期和星期错位。
    final lead = first == null ? 0 : first.weekday - 1;
    return Column(
      children: [
        const Row(
          children: [
            _WeekdayLabel('一'),
            _WeekdayLabel('二'),
            _WeekdayLabel('三'),
            _WeekdayLabel('四'),
            _WeekdayLabel('五'),
            _WeekdayLabel('六'),
            _WeekdayLabel('日'),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 5,
        mainAxisSpacing: 5,
      ),
      itemCount: lead + days.length,
      itemBuilder: (_, index) {
        if (index < lead) return const SizedBox.shrink();
        final day = days[index - lead];
        final parsed = DateTime.tryParse(day.date);
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (parsed == null) return;
            setState(() {
              _date = parsed;
              _showCalendar = false;
            });
            unawaited(_reload());
          },
          child: Container(
            decoration: BoxDecoration(
              color: _calendarColor(day.status).withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _calendarColor(day.status).withValues(alpha: 0.28)),
            ),
            child: Center(
              child: Text(
                '${parsed?.day ?? ''}',
                style: TextStyle(fontWeight: FontWeight.w700, color: _calendarColor(day.status)),
              ),
            ),
          ),
        );
      },
    ),
      ],
    );
  }

  Widget _teamCalendarTable(TaskDailyReportCalendar calendar) {
    if (calendar.users.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: Text('暂无可查看的团队成员')),
      );
    }
    final limit = calendar.days.length.clamp(0, 31);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 6,
        horizontalMargin: 8,
        columns: [
          const DataColumn(label: Text('员工')),
          for (var i = 0; i < limit; i++)
            DataColumn(label: Text('${DateTime.tryParse(calendar.days[i])?.day ?? ''}')),
        ],
        rows: [
          for (final user in calendar.users)
            DataRow(
              cells: [
                DataCell(SizedBox(width: 72, child: Text(user.userName.isEmpty ? '员工${user.userId}' : user.userName, overflow: TextOverflow.ellipsis))),
                for (var i = 0; i < limit; i++)
                  DataCell(
                  _statusDot(i < user.days.length ? user.days[i].status : 'rest'),
                  onTap: () => _openMemberReport(
                    user.userId,
                    user.userName,
                    calendar.days[i],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _openMemberReport(int userId, String name, String day) {
    final parsed = DateTime.tryParse(day);
    if (userId <= 0 || parsed == null) return;
    setState(() {
      _viewUserId = userId == widget.session.userId ? null : userId;
      _viewUserName = userId == widget.session.userId ? '' : name;
      _date = parsed;
      _showCalendar = false;
      _comment.clear();
    });
    unawaited(_reload());
  }

  Widget _statusDot(String status) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(color: _calendarColor(status), shape: BoxShape.circle),
    );
  }

  Color _calendarColor(String status) => switch (status) {
    'submitted' => const Color(0xFF1F9D76),
    'leave' => const Color(0xFF4C7FD4),
    'missing' => const Color(0xFFBE123C),
    'pending' => const Color(0xFFB45309),
    _ => const Color(0xFF94A3B8),
  };

  Widget _buildHistory() {
    if (_history.isEmpty) {
      return const Center(
        child: Text('还没有历史日报', style: TextStyle(color: DunesColors.text3)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _history.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = _history[i];
        return ListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(r.reportDate),
          subtitle: Text(r.source == 'backfill' ? '补交' : '按时提交'),
          onTap: () {
            final parsed = DateTime.tryParse(r.reportDate);
            if (parsed == null) return;
            setState(() {
              _date = parsed;
              _showHistory = false;
            });
            unawaited(_reload());
          },
        );
      },
    );
  }

  Widget _buildForm() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: kTaskPurple));
    }
    if (_error != null) {
      return Center(
        child: TextButton(onPressed: _reload, child: Text('重试：$_error')),
      );
    }
    final bundle = _bundle;
    final submitted = bundle?.report?.submitted == true;
    final viewingOther =
        _viewUserId != null && _viewUserId != widget.session.userId;
    final readOnly = viewingOther || submitted || bundle?.canSubmit != true;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        if (viewingOther)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: const Color(0xFFF3EEFF),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '正在查看 ${_viewUserName.isEmpty ? '下级' : _viewUserName} 的日报',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _viewUserId = null;
                          _viewUserName = '';
                          _comment.clear();
                        });
                        unawaited(_reload());
                      },
                      child: const Text('返回我的日报'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        InkWell(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.event, color: kTaskPurple),
                const SizedBox(width: 8),
                Text(
                  formatTaskYmd(_date),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (submitted)
                        Text(
                          bundle?.report?.source == 'backfill'
                              ? '已补交'
                              : '已按时提交',
                          style: TextStyle(
                            color: bundle?.report?.source == 'backfill'
                                ? const Color(0xFFB45309)
                                : const Color(0xFF1F9D76),
                          ),
                        )
                      else if (bundle?.canBackfill == true)
                        Text(
                          '可补填至 ${bundle?.backfillUntil}',
                          style: const TextStyle(color: Color(0xFFB45309)),
                        )
                      else if (bundle?.canSubmit == true)
                        const Text(
                          '待填',
                          style: TextStyle(color: Color(0xFFB45309)),
                        ),
                      if (bundle?.leaveExempt == true)
                        const Text(
                          '请假免填',
                          style: TextStyle(color: Color(0xFF1F9D76)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (bundle?.leaveExempt == true) ...[
          _box(
            '请假免填',
            Text(
              bundle?.leaveReason.isNotEmpty == true
                  ? bundle!.leaveReason
                  : '已同步请假状态，当天不要求填写日报。',
              style: const TextStyle(color: Color(0xFF1F9D76), height: 1.4),
            ),
          ),
          const SizedBox(height: 10),
        ] else if (bundle != null && !bundle.isWorkday) ...[
          _box(
            '非工作日',
            Text(
              bundle.nonWorkReason.isEmpty
                  ? '当前日期无需提交日报。'
                  : bundle.nonWorkReason,
              style: const TextStyle(color: DunesColors.text2, height: 1.4),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (_lines.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '当天没有进行中的主目标或子目标，可填写其他工作。',
              style: TextStyle(color: DunesColors.text3),
            ),
          ),
        if (!readOnly && _lines.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _markNoProgress,
                  child: const Text('批量无进展'),
                ),
                OutlinedButton(
                  onPressed: _reusePreviousNext,
                  child: const Text('沿用上次下一步'),
                ),
              ],
            ),
          ),
        ..._reportLineCards(readOnly: readOnly),
        if (!submitted &&
            bundle?.canSubmit != true &&
            bundle?.leaveExempt != true)
          _box(
            '填报状态',
            Text(
              _lateReportHint(bundle),
              style: const TextStyle(color: DunesColors.text2, height: 1.4),
            ),
          ),
        if (!submitted &&
            bundle?.canSubmit != true &&
            bundle?.leaveExempt != true)
          const SizedBox(height: 10),
        _box(
          '阻塞',
          TextField(
            controller: _blockers,
            readOnly: readOnly,
            maxLines: 3,
            decoration: _inputDecoration('卡住的事（选填）'),
          ),
        ),
        const SizedBox(height: 10),
        _box(
          '其他工作',
          TextField(
            controller: _otherWork,
            readOnly: readOnly,
            maxLines: 3,
            decoration: _inputDecoration('未挂在主目标或子目标下的工作（选填）'),
          ),
        ),
        const SizedBox(height: 10),
        _box(
          '明日计划',
          TextField(
            controller: _nextPlan,
            readOnly: readOnly,
            maxLines: 3,
            decoration: _inputDecoration('明天准备继续推进什么（选填）'),
          ),
        ),
        if (submitted && bundle?.report != null) ...[
          const SizedBox(height: 10),
          _commentBox(bundle!.report!),
        ],
        if (!submitted && bundle?.canSubmit == true) ...[
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: kTaskPurple,
              minimumSize: const Size.fromHeight(44),
            ),
            child: Text(_saving ? '提交中…' : '提交日报'),
          ),
        ],
      ],
    );
  }

  List<Widget> _reportLineCards({required bool readOnly}) {
    final visible = readOnly
        ? _lines
        : _lines.where(_lineNeedsAttention).toList(growable: false);
    final quiet = readOnly
        ? const <_DraftLine>[]
        : _lines.where((line) => !_lineNeedsAttention(line)).toList(growable: false);
    return [
      for (final line in visible) ...[
        _lineCard(line, readOnly: readOnly),
        const SizedBox(height: 10),
      ],
      if (quiet.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _showQuiet = !_showQuiet),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '无变化 ${quiet.length} 项',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      _showQuiet ? '收起' : '展开',
                      style: const TextStyle(
                        color: kTaskPurple,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      if (_showQuiet)
        for (final line in quiet) ...[
          _lineCard(line, readOnly: readOnly),
          const SizedBox(height: 10),
        ],
    ];
  }

  Widget _lineCard(_DraftLine line, {required bool readOnly}) {
    final accent = _lineAccent(line.task);
    final period = taskCreateRangeLabel(line.task.startAt, line.task.dueAt);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 38,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.task.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (line.task.parentTitle.trim().isNotEmpty)
                      Text(
                        '所属主目标：${line.task.parentTitle}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    if (period != null)
                      Text(
                        '任务周期：$period',
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  line.task.isMain ? '主目标' : '子目标',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                '当前进度',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text2,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${line.progress.round()}%',
                  style: TextStyle(
                    color: accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: line.progress.clamp(0, 100),
            max: 100,
            divisions: 20,
            label: '${line.progress.round()}%',
            activeColor: accent,
            onChanged: readOnly
                ? null
                : (v) => setState(() => line.progress = v),
          ),
          const Text(
            '今日完成 *',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: line.work,
            readOnly: readOnly,
            minLines: 2,
            maxLines: 4,
            decoration: _inputDecoration('写清楚今天完成了什么', accent: accent),
          ),
          const SizedBox(height: 10),
          const Text(
            '下一步',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: line.next,
            readOnly: readOnly,
            minLines: 1,
            maxLines: 3,
            decoration: _inputDecoration('下一步准备做什么（选填）', accent: accent),
          ),
          if (!readOnly)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                children: [
                  if (line.work.text.trim().isEmpty)
                    TextButton(
                      onPressed: () => setState(() => line.work.text = '无进展'),
                      child: const Text('无进展'),
                    ),
                  if ((_previousNext[line.task.id] ?? '').isNotEmpty &&
                      line.next.text.trim().isEmpty)
                    TextButton(
                      onPressed: () => setState(
                        () => line.next.text = _previousNext[line.task.id]!,
                      ),
                      child: const Text('沿用上次'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _commentBox(TaskDailyReport report) {
    final comments = report.comments;
    return _box(
      '评论',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (comments.isEmpty)
            const Text('还没有评论', style: TextStyle(color: DunesColors.text3))
          else
            for (final comment in comments)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      comment.userName.isEmpty ? '用户${comment.userId}' : comment.userName,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(comment.body, style: const TextStyle(height: 1.4)),
                  ],
                ),
              ),
          TextField(
            controller: _comment,
            maxLines: 2,
            decoration: _inputDecoration('写一条评论'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _commenting ? null : () => _submitComment(report.id),
              style: FilledButton.styleFrom(backgroundColor: kTaskPurple),
              child: Text(_commenting ? '发送中…' : '发送评论'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitComment(int reportId) async {
    final text = _comment.text.trim();
    if (reportId <= 0 || text.isEmpty) {
      showDunesCenterToast(context, '请先写评论');
      return;
    }
    setState(() => _commenting = true);
    try {
      await _api.commentDailyReport(reportId, text);
      if (!mounted) return;
      _comment.clear();
      showDunesCenterToast(context, '已发送');
      await _reload();
    } catch (e) {
      if (!mounted) return;
      showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _commenting = false);
    }
  }

  Widget _box(String label, Widget child) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Color _lineAccent(TaskItem task) {
    const colors = <Color>[
      kTaskPurple,
      Color(0xFF5B6FC4),
      Color(0xFF4A7C9B),
      Color(0xFFB7791F),
      Color(0xFF9C5FB5),
    ];
    return colors[task.id.abs() % colors.length];
  }

  InputDecoration _inputDecoration(String hint, {Color accent = kTaskPurple}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: DunesColors.text3, fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF6F7F9),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
    );
  }

  String _lateReportHint(TaskDailyReportBundle? bundle) {
    if (bundle?.canBackfill == true) {
      return '这是补填时段，请在 ${bundle?.backfillUntil} 前完成提交；提交后会标记为补交。';
    }
    return '当前日期已超过填报或补填截止时间，不能再提交日报。';
  }
}
