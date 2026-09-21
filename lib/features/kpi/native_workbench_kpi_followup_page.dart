import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../profile/native_work_profile_perf_page.dart';
import '../profile/work_profile_kpi.dart';
import '../shell/dunes_toast.dart';
import '../tasks/native_task_home_pane.dart';
import 'kpi_followup.dart';
import 'workbench_kpi_service.dart';

const _accent = DunesColors.brandPurple;
const _pageBg = Color(0xFFF7F4FC);
const _line = Color(0xFFECE7F3);
const _tabular = <FontFeature>[FontFeature.tabularFigures()];

enum _MemberTab { unpublished, publishedUnacked, acked }

enum _FollowupView { progress, appeals }

enum _AppealFilter { open, done }

/// 考评页里的催办进度：按月看打分 / 发布 / 确认，用来催，不代替领导打分。
class NativeWorkbenchKpiFollowupPage extends StatefulWidget {
  const NativeWorkbenchKpiFollowupPage({
    super.key,
    required this.session,
    this.onChromeChanged,
    this.service,
    this.now,
    this.month,
    this.sector,
    this.embedded = false,
  });

  final AuthSession session;
  final ValueChanged<TaskShellChrome>? onChromeChanged;
  final WorkbenchKpiService? service;
  final DateTime? now;
  final DateTime? month;
  final String? sector;
  final bool embedded;

  @override
  State<NativeWorkbenchKpiFollowupPage> createState() =>
      _NativeWorkbenchKpiFollowupPageState();
}

class _NativeWorkbenchKpiFollowupPageState
    extends State<NativeWorkbenchKpiFollowupPage> {
  late final WorkbenchKpiService _service;
  bool _loading = true;
  String? _error;
  KpiFollowupBoard? _board;
  late DateTime _month;
  _MemberTab _memberTab = _MemberTab.unpublished;
  String _sector = 'all';
  List<KpiAppeal> _appeals = const [];
  int? _closingAppealId;
  _FollowupView _view = _FollowupView.progress;
  _AppealFilter _appealFilter = _AppealFilter.open;
  String? _appealError;

  DateTime get _clock => widget.now ?? DateTime.now();
  DateTime get _currentMonth => kpiMonthStart(_clock);
  DateTime get _earliestMonth => DateTime(_currentMonth.year - 3, 1);

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? WorkbenchKpiService(session: widget.session);
    _month =
        widget.month ?? DateTime(_currentMonth.year, _currentMonth.month - 1);
    _sector = widget.sector ?? 'all';
    if (!widget.embedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onChromeChanged?.call(const TaskShellChrome());
        }
      });
    }
    unawaited(_load());
  }

  @override
  void didUpdateWidget(NativeWorkbenchKpiFollowupPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    var reload = false;
    if (widget.month != null && widget.month != oldWidget.month) {
      _month = widget.month!;
      reload = true;
    }
    if (widget.sector != null && widget.sector != _sector) {
      _sector = widget.sector!;
      if (_board != null) {
        _memberTab = _defaultMemberTab(_board!);
      }
    }
    if (reload) unawaited(_load());
  }

  @override
  void dispose() {
    if (!widget.embedded) {
      widget.onChromeChanged?.call(const TaskShellChrome());
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _appealError = null;
    });
    final month = formatKpiMonth(_month);
    KpiFollowupBoard? board;
    List<KpiAppeal> appeals = const [];
    String? boardError;
    String? appealError;
    try {
      board = await _service.fetchFollowup(month: month);
    } catch (e) {
      boardError = friendlyErrorText(e, fallback: '催办进度加载失败');
    }
    try {
      appeals = await _service.listAppeals(month: month);
    } catch (e) {
      appealError = friendlyErrorText(e, fallback: '申诉加载失败');
    }
    if (!mounted) return;
    setState(() {
      _board = board;
      _appeals = appeals;
      _error = boardError;
      _appealError = appealError;
      _loading = false;
      if (board != null) _memberTab = _defaultMemberTab(board);
    });
  }

  _MemberTab _defaultMemberTab(KpiFollowupBoard board) {
    final members = _membersOf(board);
    if (members.unpublished.isNotEmpty) return _MemberTab.unpublished;
    if (members.publishedUnacked.isNotEmpty) {
      return _MemberTab.publishedUnacked;
    }
    return _MemberTab.acked;
  }

  List<KpiFollowupSector> _visibleSectors(KpiFollowupBoard board) {
    if (_sector == 'all') return board.sectors;
    return [
      for (final s in board.sectors)
        if (s.key == _sector) s,
    ];
  }

  KpiFollowupMembers _membersOf(KpiFollowupBoard board) {
    final sectors = _visibleSectors(board);
    if (sectors.length == 1) return sectors.first.members;
    return KpiFollowupMembers(
      unpublished: [for (final s in sectors) ...s.members.unpublished],
      publishedUnacked: [
        for (final s in sectors) ...s.members.publishedUnacked,
      ],
      acked: [for (final s in sectors) ...s.members.acked],
    );
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month.isBefore(_earliestMonth)
          ? _earliestMonth
          : (_month.isAfter(_currentMonth) ? _currentMonth : _month),
      firstDate: _earliestMonth,
      lastDate: _currentMonth,
      helpText: '选择月份',
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null || !mounted) return;
    setState(() => _month = kpiMonthStart(picked));
    unawaited(_load());
  }

  void _shiftMonth(int delta) {
    final next = kpiShiftMonth(_month, delta);
    if (next.isBefore(_earliestMonth) || next.isAfter(_currentMonth)) return;
    setState(() => _month = next);
    unawaited(_load());
  }

  KpiFollowupCounts _visibleCounts(KpiFollowupBoard board) {
    if (_sector == 'all') return board.summary;
    final sectors = _visibleSectors(board);
    if (sectors.isEmpty) return const KpiFollowupCounts();
    return sectors.first.summary;
  }

  /// 同一位领导可能挂在多个板块，合并成一行，只催一次。
  List<KpiFollowupLeader> _leadersOf(List<KpiFollowupSector> sectors) {
    final merged = <String, KpiFollowupLeader>{};
    for (final sector in sectors) {
      for (final leader in sector.leaders) {
        final key = leader.userId > 0
            ? 'id:${leader.userId}'
            : 'name:${leader.userName.trim()}';
        final prev = merged[key];
        if (prev == null) {
          merged[key] = leader;
          continue;
        }
        final names = <String>{...prev.unscoredNames, ...leader.unscoredNames};
        merged[key] = KpiFollowupLeader(
          userId: prev.userId,
          userName: prev.userName,
          done: prev.done && leader.done,
          expected: prev.expected + leader.expected,
          scored: prev.scored + leader.scored,
          unscored: prev.unscored + leader.unscored,
          unscoredNames: names.toList(),
        );
      }
    }
    final list = merged.values.toList()
      ..sort((a, b) {
        if (a.done != b.done) return a.done ? 1 : -1;
        return b.unscored.compareTo(a.unscored);
      });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final embedded = widget.embedded;
    final board = _board;
    return ColoredBox(
      color: embedded ? Colors.transparent : _pageBg,
      child: ListView(
        padding: embedded
            ? const EdgeInsets.only(bottom: 16)
            : const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!embedded) ...[_standaloneHeader(), const SizedBox(height: 10)],
          _viewTabs(),
          const SizedBox(height: 10),
          if (_loading && board == null && _appeals.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 48),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _accent,
                ),
              ),
            )
          else if (_view == _FollowupView.appeals)
            ..._appealsBody()
          else if (_error != null && board == null)
            _errorCard()
          else if (board != null)
            ..._body(board),
        ],
      ),
    );
  }

  Widget _viewTabs() {
    final openCount = _appeals.where((row) => row.isOpen).length;
    return SegmentedButton<_FollowupView>(
      key: const Key('kpi-followup-view-tabs'),
      segments: [
        const ButtonSegment(value: _FollowupView.progress, label: Text('流程催办')),
        ButtonSegment(
          value: _FollowupView.appeals,
          label: Text(openCount > 0 ? '申诉处理 $openCount' : '申诉处理'),
        ),
      ],
      selected: {_view},
      onSelectionChanged: (value) => setState(() => _view = value.first),
      showSelectedIcon: false,
    );
  }

  List<Widget> _appealsBody() {
    if (_appealError != null) {
      return [
        _Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  _appealError!,
                  style: const TextStyle(color: DunesColors.text2),
                ),
                TextButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          ),
        ),
      ];
    }
    final filtered = [
      for (final row in _appeals)
        if ((_appealFilter == _AppealFilter.open) == row.isOpen &&
            (_sector == 'all' || row.sector == _sector))
          row,
    ];
    return [
      SegmentedButton<_AppealFilter>(
        segments: const [
          ButtonSegment(value: _AppealFilter.open, label: Text('待处理')),
          ButtonSegment(value: _AppealFilter.done, label: Text('已办结')),
        ],
        selected: {_appealFilter},
        onSelectionChanged: (value) =>
            setState(() => _appealFilter = value.first),
        showSelectedIcon: false,
      ),
      const SizedBox(height: 10),
      if (filtered.isEmpty)
        _Card(
          child: _EmptyHint(
            _appealFilter == _AppealFilter.open ? '当前没有待处理申诉' : '当前没有已办结申诉',
          ),
        )
      else
        _appealsCard(filtered, showDone: _appealFilter == _AppealFilter.done),
    ];
  }

  Widget _standaloneHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _MonthStepper(
                label: formatKpiMonthLabel(_month),
                onPick: _pickMonth,
                onPrev: _month.isAfter(_earliestMonth)
                    ? () => _shiftMonth(-1)
                    : null,
                onNext: _month.isBefore(_currentMonth)
                    ? () => _shiftMonth(1)
                    : null,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '催打分 / 发布 / 确认，不代替领导打分',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, color: DunesColors.text3),
                ),
              ),
            ],
          ),
          if (_board != null) ...[const SizedBox(height: 10), _sectorTabs()],
        ],
      ),
    );
  }

  Widget _sectorTabs() {
    const options = [
      MapEntry('all', '全部'),
      MapEntry('telecom', '运营商'),
      MapEntry('energy', '能源'),
      MapEntry('rd', '研发'),
      MapEntry('office', '职能'),
    ];
    return Container(
      key: const Key('kpi-followup-sector-filter'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFECE7F4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: InkWell(
                key: Key('kpi-followup-sector-${option.key}'),
                onTap: () => setState(() {
                  _sector = option.key;
                  if (_board != null) {
                    _memberTab = _defaultMemberTab(_board!);
                  }
                }),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _sector == option.key
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    option.value,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: _sector == option.key
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: _sector == option.key
                          ? DunesColors.text
                          : DunesColors.text2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return _Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Column(
          children: [
            Text(
              _error ?? '加载失败',
              style: const TextStyle(fontSize: 13, color: DunesColors.text2),
            ),
            const SizedBox(height: 6),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(KpiFollowupBoard board) {
    final sectors = _visibleSectors(board);
    if (sectors.isEmpty) {
      return [_Card(child: const _EmptyHint('这个月还没有需要催办的部门'))];
    }
    final leaders = _leadersOf(sectors);
    final groups = <({KpiFollowupSector sector, KpiFollowupGroup group})>[
      for (final sector in sectors)
        for (final group in sector.groups) (sector: sector, group: group),
    ];
    return [
      _PipelineCard(counts: _visibleCounts(board)),
      if (leaders.isNotEmpty) ...[
        const SizedBox(height: 10),
        _leadersCard(leaders),
      ],
      if (groups.isNotEmpty) ...[
        const SizedBox(height: 10),
        _groupsCard(groups, showSector: sectors.length > 1),
      ],
      const SizedBox(height: 10),
      _membersCard(_membersOf(board)),
    ];
  }

  Widget _appealsCard(List<KpiAppeal> rows, {bool showDone = false}) {
    return _Card(
      tone: DunesColors.coral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            title: showDone ? '已办结申诉' : '待处理申诉',
            count: rows.length,
            countColor: DunesColors.coral,
            hint: showDone ? '处理结果可追溯' : '请核验后填写处理结论',
          ),
          for (var i = 0; i < rows.length; i++) ...[
            const Divider(height: 1, color: _line),
            _AppealRow(
              appeal: rows[i],
              closing: _closingAppealId == rows[i].id,
              onClaim: showDone || rows[i].assignedTo > 0
                  ? null
                  : () => unawaited(_claimAppeal(rows[i])),
              onClose: showDone || rows[i].assignedTo == 0
                  ? null
                  : () => unawaited(_closeAppeal(rows[i])),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _closeAppeal(KpiAppeal appeal) async {
    if (appeal.id <= 0 || _closingAppealId != null) return;
    final result = await showDialog<({String decision, String resolution})>(
      context: context,
      builder: (context) => _AppealResolutionDialog(appeal: appeal),
    );
    if (result == null || !mounted) return;
    setState(() => _closingAppealId = appeal.id);
    try {
      final saved = await _service.resolveAppeal(
        appeal.id,
        decision: result.decision,
        resolution: result.resolution,
      );
      if (!mounted) return;
      setState(() {
        _appeals = [
          for (final row in _appeals)
            if (row.id == appeal.id) saved else row,
        ];
      });
      showDunesToast(context, '申诉已办结并通知员工');
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '处理失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _closingAppealId = null);
    }
  }

  Future<void> _claimAppeal(KpiAppeal appeal) async {
    if (appeal.id <= 0 || _closingAppealId != null) return;
    setState(() => _closingAppealId = appeal.id);
    try {
      final saved = await _service.claimAppeal(appeal.id);
      if (!mounted) return;
      setState(() {
        _appeals = [
          for (final row in _appeals)
            if (row.id == appeal.id) saved else row,
        ];
      });
      showDunesToast(context, '已领取，请在时限内完成核验');
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          friendlyErrorText(e, fallback: '领取失败'),
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _closingAppealId = null);
    }
  }

  Widget _leadersCard(List<KpiFollowupLeader> leaders) {
    final pending = [
      for (final l in leaders)
        if (!l.done) l,
    ];
    final done = [
      for (final l in leaders)
        if (l.done) l,
    ];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            title: '催领导打分',
            count: pending.length,
            countColor: pending.isEmpty ? DunesColors.green : DunesColors.amber,
            hint: pending.isEmpty ? '都评完了' : '${pending.length} 位还没评完',
          ),
          for (final leader in pending) ...[
            const Divider(height: 1, color: _line),
            _LeaderRow(leader: leader),
          ],
          if (done.isNotEmpty) ...[
            const Divider(height: 1, color: _line),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(right: 2),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 15,
                      color: DunesColors.green,
                    ),
                  ),
                  const Text(
                    '已评完',
                    style: TextStyle(fontSize: 12, color: DunesColors.text3),
                  ),
                  for (final leader in done)
                    Text(
                      '${leader.userName} ${leader.scored}/${leader.expected}',
                      key: Key('kpi-followup-leader-${leader.userName}'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: DunesColors.text2,
                        fontFeatures: _tabular,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _groupsCard(
    List<({KpiFollowupSector sector, KpiFollowupGroup group})> rows, {
    required bool showSector,
  }) {
    final seen = <String>{};
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(title: '各组打分进度', count: rows.length),
          for (final row in rows) ...[
            const Divider(height: 1, color: _line),
            _GroupRow(
              group: row.group,
              sectorLabel:
                  showSector && row.sector.name.trim() != row.group.name.trim()
                  ? row.sector.name
                  : '',
              keyed: seen.add(row.group.name),
            ),
          ],
        ],
      ),
    );
  }

  Widget _membersCard(KpiFollowupMembers members) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardHeader(title: '员工确认', hint: '发布后员工确认本月结果'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F0F8),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  _tab(
                    '未发布',
                    members.unpublished.length,
                    _MemberTab.unpublished,
                    const Key('kpi-followup-tab-unpublished'),
                  ),
                  _tab(
                    '待确认',
                    members.publishedUnacked.length,
                    _MemberTab.publishedUnacked,
                    const Key('kpi-followup-tab-unacked'),
                  ),
                  _tab(
                    '已确认',
                    members.acked.length,
                    _MemberTab.acked,
                    const Key('kpi-followup-tab-acked'),
                  ),
                ],
              ),
            ),
          ),
          _memberList(members),
        ],
      ),
    );
  }

  Widget _tab(String label, int count, _MemberTab value, Key key) {
    final selected = _memberTab == value;
    return Expanded(
      child: InkWell(
        key: key,
        onTap: () => setState(() => _memberTab = value),
        borderRadius: BorderRadius.circular(7),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x142B1A4F),
                      blurRadius: 3,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: label),
                TextSpan(
                  text: ' $count',
                  style: TextStyle(
                    color: selected ? _accent : DunesColors.text3,
                  ),
                ),
              ],
            ),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? DunesColors.text : DunesColors.text2,
              fontFeatures: _tabular,
            ),
          ),
        ),
      ),
    );
  }

  Widget _memberList(KpiFollowupMembers members) {
    final raw = switch (_memberTab) {
      _MemberTab.unpublished => members.unpublished,
      _MemberTab.publishedUnacked => members.publishedUnacked,
      _MemberTab.acked => members.acked,
    };
    final seen = <String>{};
    final people = [
      for (final p in raw)
        if (seen.add(p.userId > 0 ? 'id:${p.userId}' : 'name:${p.userName}')) p,
    ];
    if (people.isEmpty) {
      final text = switch (_memberTab) {
        _MemberTab.unpublished => '没有待发布的人',
        _MemberTab.publishedUnacked => '没有待确认的人',
        _MemberTab.acked => '还没有人确认',
      };
      return _EmptyHint(text);
    }
    final buckets = <String, List<KpiFollowupPerson>>{};
    for (final person in people) {
      final key = person.departmentName.trim().isEmpty
          ? '未分部门'
          : person.departmentName.trim();
      buckets.putIfAbsent(key, () => []).add(person);
    }
    final grouped = buckets.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in buckets.entries) ...[
          if (grouped)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 7, 14, 6),
              color: const Color(0xFFFAF8FD),
              child: Text(
                '${entry.key}  ${entry.value.length}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text3,
                  fontFeatures: _tabular,
                ),
              ),
            ),
          for (var i = 0; i < entry.value.length; i++) ...[
            const Divider(height: 1, color: _line),
            _MemberRow(
              person: entry.value[i],
              hideDept: grouped,
              tab: _memberTab,
            ),
          ],
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.tone});

  final Widget child;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = tone;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: t == null ? _line : t.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.title,
    this.count,
    this.countColor,
    this.hint = '',
  });

  final String title;
  final int? count;
  final Color? countColor;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final n = count;
    final c = countColor ?? DunesColors.text3;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
            ),
          ),
          if (n != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$n',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: c,
                  fontFeatures: _tabular,
                ),
              ),
            ),
          ],
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11.5, color: DunesColors.text3),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {super.key, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 11,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: color,
          fontFeatures: _tabular,
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 4,
        color: color,
        backgroundColor: const Color(0xFFF0ECF6),
      ),
    );
  }
}

/// 打分 → 发布 → 确认 三段流程，一眼看出卡在哪一步。
class _PipelineCard extends StatelessWidget {
  const _PipelineCard({required this.counts});

  final KpiFollowupCounts counts;

  @override
  Widget build(BuildContext context) {
    final c = counts;
    final published = c.publishedUnacked + c.acked;
    final allDone = c.expected > 0 && c.acked >= c.expected;
    final statusColor = allDone ? DunesColors.green : DunesColors.amber;
    return _Card(
      child: Padding(
        key: const Key('kpi-followup-pipeline'),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  '本月进度',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '应评 ${c.expected} 人',
                  style: const TextStyle(
                    fontSize: 12,
                    color: DunesColors.text3,
                    fontFeatures: _tabular,
                  ),
                ),
                const Spacer(),
                _Tag(
                  c.expected == 0 ? '暂无' : (allDone ? '全部确认' : '进行中'),
                  color: c.expected == 0 ? DunesColors.text3 : statusColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _Stage(
                    step: '1',
                    title: '领导打分',
                    done: c.scored,
                    total: c.expected,
                    todo: c.unscored,
                    todoLabel: '未打分',
                  ),
                ),
                const _StageArrow(),
                Expanded(
                  child: _Stage(
                    step: '2',
                    title: 'HR 发布',
                    done: published,
                    total: c.scored,
                    todo: c.unpublished,
                    todoLabel: '未发布',
                  ),
                ),
                const _StageArrow(),
                Expanded(
                  child: _Stage(
                    step: '3',
                    title: '员工确认',
                    done: c.acked,
                    total: published,
                    todo: c.publishedUnacked,
                    todoLabel: '待确认',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StageArrow extends StatelessWidget {
  const _StageArrow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 26, 4, 0),
      child: Icon(
        Icons.chevron_right_rounded,
        size: 16,
        color: Color(0xFFCFC8DA),
      ),
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.step,
    required this.title,
    required this.done,
    required this.total,
    required this.todo,
    required this.todoLabel,
  });

  final String step;
  final String title;
  final int done;
  final int total;
  final int todo;
  final String todoLabel;

  @override
  Widget build(BuildContext context) {
    final idle = total == 0;
    final complete = !idle && todo == 0;
    final color = idle
        ? DunesColors.text3
        : (complete ? DunesColors.green : DunesColors.amber);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: complete ? DunesColors.green : const Color(0xFFEDE9F3),
                shape: BoxShape.circle,
              ),
              child: complete
                  ? const Icon(
                      Icons.check_rounded,
                      size: 11,
                      color: Colors.white,
                    )
                  : Text(
                      step,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.text2,
                      ),
                    ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: DunesColors.text2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$done',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.text,
                ),
              ),
              TextSpan(
                text: '/$total',
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
            ],
          ),
          style: const TextStyle(fontFeatures: _tabular, height: 1.1),
        ),
        const SizedBox(height: 6),
        _ProgressBar(
          value: idle ? 0.0 : done / total,
          color: complete ? DunesColors.green : _accent,
        ),
        const SizedBox(height: 5),
        Text(
          idle ? '—' : (complete ? '已完成' : '$todoLabel $todo'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: color,
            fontFeatures: _tabular,
          ),
        ),
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.group,
    this.sectorLabel = '',
    this.keyed = true,
  });

  final KpiFollowupGroup group;
  final String sectorLabel;
  final bool keyed;

  @override
  Widget build(BuildContext context) {
    final expected = group.expected;
    final complete = expected > 0 && group.unscored == 0;
    final lighthouse = group.isLighthouse;
    return Padding(
      key: keyed ? Key('kpi-followup-group-${group.name}') : null,
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
              ),
              if (sectorLabel.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  sectorLabel,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: DunesColors.text3,
                  ),
                ),
              ],
              const SizedBox(width: 6),
              _Tag(
                lighthouse ? '灯塔自动' : '量表打分',
                color: lighthouse
                    ? DunesColors.blue
                    : DunesColors.brandPurpleDeep,
              ),
              const Spacer(),
              if (group.projectScore > 0)
                _Tag(
                  '项目绩效系数 ${formatKpiProjectCoefficient(group.projectCoefficient)}',
                  color: DunesColors.brandPurple,
                ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _ProgressBar(
                  value: expected == 0 ? 0.0 : group.scored / expected,
                  color: complete ? DunesColors.green : DunesColors.amber,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${group.scored}/$expected',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                  fontFeatures: _tabular,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 44,
                child: Text(
                  complete ? '已评完' : '差 ${group.unscored}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: complete ? DunesColors.green : DunesColors.amber,
                    fontFeatures: _tabular,
                  ),
                ),
              ),
            ],
          ),
          if (group.unscoredNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in group.unscoredNames) _NameChip(name),
              ],
            ),
          ] else if (lighthouse) ...[
            const SizedBox(height: 6),
            const Text(
              '灯塔自动算分，不用催领导打量表',
              style: TextStyle(fontSize: 11.5, color: DunesColors.text3),
            ),
          ],
        ],
      ),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.leader});

  final KpiFollowupLeader leader;

  @override
  Widget build(BuildContext context) {
    final name = leader.userName.trim();
    final extra = leader.unscored - leader.unscoredNames.length;
    return Padding(
      key: Key('kpi-followup-leader-${leader.userName}'),
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: DunesColors.amberSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              name.isEmpty ? '?' : name.characters.first,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DunesColors.amber,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text,
                        ),
                      ),
                    ),
                    Text(
                      '还差 ${leader.unscored} 人',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.amber,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: _ProgressBar(
                        value: leader.expected == 0
                            ? 0.0
                            : leader.scored / leader.expected,
                        color: DunesColors.amber,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '已评 ${leader.scored}/${leader.expected}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: DunesColors.text3,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ],
                ),
                if (leader.unscoredNames.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final n in leader.unscoredNames) _NameChip(n),
                      if (extra > 0) _NameChip('+$extra'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.person,
    required this.tab,
    this.hideDept = false,
  });

  final KpiFollowupPerson person;
  final _MemberTab tab;
  final bool hideDept;

  @override
  Widget build(BuildContext context) {
    final dept = hideDept ? '' : person.departmentName.trim();
    final position = person.position.trim();
    final supervisor = person.supervisorName.trim();
    final sub = [
      if (dept.isNotEmpty) dept,
      if (position.isNotEmpty) position,
      if (supervisor.isNotEmpty) '直属 $supervisor',
    ].join(' · ');
    final (String label, Color color) = switch (tab) {
      _MemberTab.unpublished => ('待发布', DunesColors.brandPurple),
      _MemberTab.publishedUnacked => ('待确认', DunesColors.amber),
      _MemberTab.acked => ('已确认', DunesColors.green),
    };
    return Padding(
      key: Key('kpi-followup-member-${person.userName}'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: DunesColors.text3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Tag(label, color: color),
        ],
      ),
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DunesColors.amberSoft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: DunesColors.amber,
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12.5, color: DunesColors.text3),
      ),
    );
  }
}

class _MonthStepper extends StatelessWidget {
  const _MonthStepper({
    required this.label,
    this.onPick,
    this.onPrev,
    this.onNext,
  });

  final String label;
  final VoidCallback? onPick;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _arrow(Icons.chevron_left_rounded, onPrev),
          InkWell(
            key: const Key('kpi-followup-month-pick'),
            onTap: onPick,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                  fontFeatures: _tabular,
                ),
              ),
            ),
          ),
          _arrow(Icons.chevron_right_rounded, onNext),
        ],
      ),
    );
  }

  Widget _arrow(IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 28,
        height: 32,
        child: Icon(
          icon,
          size: 20,
          color: onTap == null ? DunesColors.border : DunesColors.text2,
        ),
      ),
    );
  }
}

class _AppealRow extends StatelessWidget {
  const _AppealRow({
    required this.appeal,
    required this.closing,
    required this.onClose,
    required this.onClaim,
  });

  final KpiAppeal appeal;
  final bool closing;
  final VoidCallback? onClose;
  final VoidCallback? onClaim;

  @override
  Widget build(BuildContext context) {
    final name = appeal.userName.trim().isEmpty
        ? '未命名'
        : appeal.userName.trim();
    final dept = appeal.departmentName.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
              ),
              if (dept.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  dept,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: DunesColors.text3,
                  ),
                ),
              ],
              const SizedBox(width: 6),
              _Tag(
                appeal.resolvedKindLabel,
                key: Key('kpi-followup-appeal-kind-${appeal.id}'),
                color: DunesColors.coral,
              ),
              const Spacer(),
              if (onClaim != null)
                TextButton(
                  onPressed: closing ? null : onClaim,
                  child: const Text('领取'),
                ),
              if (onClose != null)
                TextButton(
                  key: Key('kpi-followup-appeal-done-${appeal.id}'),
                  onPressed: closing ? null : onClose,
                  style: TextButton.styleFrom(
                    foregroundColor: DunesColors.brandPurpleDeep,
                    backgroundColor: DunesColors.brandPurpleSoft,
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  child: closing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('处理申诉'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            appeal.assignedToName.trim().isNotEmpty
                ? '当前责任人：${appeal.assignedToName}'
                : (appeal.assignedRole == 'supervisor'
                      ? '待直属领导处理'
                      : '数据负责人待领取'),
            style: const TextStyle(fontSize: 11.5, color: DunesColors.text3),
          ),
          if (appeal.dueAt.trim().isNotEmpty)
            Text(
              _appealDueLabel(appeal.dueAt),
              style: TextStyle(
                fontSize: 11.5,
                color: _appealIsOverdue(appeal.dueAt)
                    ? DunesColors.coral
                    : DunesColors.text3,
                fontWeight: _appealIsOverdue(appeal.dueAt)
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          const SizedBox(height: 6),
          if (appeal.subjectName.trim().isNotEmpty) ...[
            Text(
              '申诉指标：${appeal.subjectName}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: DunesColors.text,
              ),
            ),
            if (appeal.snapshot.trim().isNotEmpty)
              Text(
                '提交时快照：${appeal.snapshot}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: DunesColors.text3,
                ),
              ),
            if (appeal.expectedChange.trim().isNotEmpty)
              Text(
                '期望修正：${appeal.expectedChange}',
                style: const TextStyle(fontSize: 12, color: DunesColors.coral),
              ),
            const SizedBox(height: 8),
          ],
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFAF8FD),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              appeal.comment,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: DunesColors.text,
              ),
            ),
          ),
          if (!appeal.isOpen && appeal.resolution.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '处理结论：${_appealDecisionLabel(appeal.decision)}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              appeal.resolution,
              style: const TextStyle(fontSize: 12.5, color: DunesColors.text2),
            ),
            if (appeal.handledByName.trim().isNotEmpty)
              Text(
                '处理人：${appeal.handledByName}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: DunesColors.text3,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

String _appealDecisionLabel(String decision) => switch (decision) {
  'approved' => '申诉成立',
  'partial' => '部分成立',
  'rejected' => '申诉驳回',
  _ => '已办结',
};

bool _appealIsOverdue(String raw) {
  final due = DateTime.tryParse(raw)?.toLocal();
  return due != null && due.isBefore(DateTime.now());
}

String _appealDueLabel(String raw) {
  final due = DateTime.tryParse(raw)?.toLocal();
  if (due == null) return '';
  final date = '${due.month}月${due.day}日';
  return _appealIsOverdue(raw) ? '已逾期 · 应于$date前处理' : '处理时限 · $date';
}

class _AppealResolutionDialog extends StatefulWidget {
  const _AppealResolutionDialog({required this.appeal});
  final KpiAppeal appeal;

  @override
  State<_AppealResolutionDialog> createState() =>
      _AppealResolutionDialogState();
}

class _AppealResolutionDialogState extends State<_AppealResolutionDialog> {
  final _controller = TextEditingController();
  String _decision = 'approved';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('处理 ${widget.appeal.userName} 的申诉'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.appeal.comment,
              style: const TextStyle(color: DunesColors.text2),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _decision,
              decoration: const InputDecoration(labelText: '处理结论'),
              items: const [
                DropdownMenuItem(value: 'approved', child: Text('申诉成立')),
                DropdownMenuItem(value: 'partial', child: Text('部分成立')),
                DropdownMenuItem(value: 'rejected', child: Text('申诉驳回')),
              ],
              onChanged: (value) =>
                  setState(() => _decision = value ?? 'approved'),
            ),
            const SizedBox(height: 12),
            const Text(
              '选择“申诉成立/部分成立”前，请先在灯塔修正源数据，或由评分人完成重评。系统会校验指标已变化，然后自动重算、重新发布并通知员工。',
              style: TextStyle(fontSize: 12, color: DunesColors.text3),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('kpi-appeal-resolution'),
              controller: _controller,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '处理说明',
                hintText: '填写核验结果、修正内容或驳回理由',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('kpi-appeal-resolution-submit'),
          onPressed: _controller.text.trim().length < 4
              ? null
              : () => Navigator.pop(context, (
                  decision: _decision,
                  resolution: _controller.text.trim(),
                )),
          child: const Text('办结并通知'),
        ),
      ],
    );
  }
}
