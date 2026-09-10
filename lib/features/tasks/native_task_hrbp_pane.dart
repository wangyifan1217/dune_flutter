import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/widgets/horizontal_drag_scroll_view.dart';
import '../auth/auth_session.dart';
import 'native_task_action_page.dart';
import 'native_task_detail_page.dart';
import 'native_task_home_pane.dart';
import 'task_api.dart';
import 'task_models.dart';
import 'task_widgets.dart';

enum _HrbpPage { board, detail, action }

/// HRBP 任务汇总看板：部门筛选 + 进度柱状图（统计向，他人任务只读）。
class NativeTaskHrbpPane extends StatefulWidget {
  const NativeTaskHrbpPane({
    super.key,
    required this.session,
    this.onChromeChanged,
  });

  final AuthSession session;
  final ValueChanged<TaskShellChrome>? onChromeChanged;

  @override
  State<NativeTaskHrbpPane> createState() => _NativeTaskHrbpPaneState();
}

class _NativeTaskHrbpPaneState extends State<NativeTaskHrbpPane> {
  late final TaskApi _api = TaskApi(widget.session);
  final _scrollController = ScrollController();

  _HrbpPage _page = _HrbpPage.board;
  bool _pageNavBack = false;
  int? _detailId;
  final List<int> _detailStack = [];
  TaskItem? _actionTask;
  TaskActionMode? _actionMode;

  List<HrbpDeptStat> _depts = const [];
  List<TaskItem> _deptTasks = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMoreTasks = false;
  int _taskPage = 0;
  String? _error;
  static const int _pageSize = 20;

  /// null = 全部部门
  int? _deptFilter;
  double _boardScrollOffset = 0;
  late DateTime _dateFrom;
  late DateTime _dateTo;

  static ({DateTime from, DateTime to}) _currentMonthRange() {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, 1);
    final to = DateTime(now.year, now.month + 1, 0); // 当月最后一天
    return (from: from, to: to);
  }

  @override
  void initState() {
    super.initState();
    final month = _currentMonthRange();
    _dateFrom = month.from;
    _dateTo = month.to;
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishChrome());
    unawaited(_reload());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    widget.onChromeChanged?.call(const TaskShellChrome());
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMoreTasks ||
        _deptFilter == null ||
        _page != _HrbpPage.board) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 220) {
      unawaited(_loadMoreTasks());
    }
  }

  void _publishChrome() {
    if (_page == _HrbpPage.detail || _page == _HrbpPage.action) {
      widget.onChromeChanged?.call(
        TaskShellChrome(
          hideShellHeader: true,
          onBack: _page == _HrbpPage.action ? _backFromAction : _backFromDetail,
        ),
      );
      return;
    }
    if (_deptFilter != null) {
      widget.onChromeChanged?.call(
        TaskShellChrome(
          onBack: () => unawaited(_selectDept(null)),
          backLabel: '全部部门',
        ),
      );
      return;
    }
    widget.onChromeChanged?.call(const TaskShellChrome());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _deptTasks = const [];
      _hasMoreTasks = false;
      _taskPage = 0;
    });
    try {
      final depts = await _api.hrbpOverview(
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      if (!mounted) return;
      var filter = _deptFilter;
      if (filter != null && !depts.any((d) => d.departmentId == filter)) {
        filter = null;
      }
      setState(() {
        _depts = depts;
        _deptFilter = filter;
        _loading = false;
      });
      _publishChrome();
      if (filter != null) {
        await _loadDeptTasks(reset: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadDeptTasks({required bool reset}) async {
    final deptId = _deptFilter;
    if (deptId == null) return;
    if (reset) {
      setState(() {
        _loadingMore = false;
        _hasMoreTasks = true;
        _taskPage = 0;
      });
    }
    try {
      final result = await _api.hrbpDepartmentPage(
        deptId,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        page: 0,
        size: _pageSize,
      );
      if (!mounted || _deptFilter != deptId) return;
      setState(() {
        _deptTasks = result.items;
        _taskPage = 0;
        _hasMoreTasks = result.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadingMore = false;
      });
    }
  }

  Future<void> _loadMoreTasks() async {
    final deptId = _deptFilter;
    if (deptId == null || _loading || _loadingMore || !_hasMoreTasks) return;
    setState(() => _loadingMore = true);
    try {
      final next = _taskPage + 1;
      final result = await _api.hrbpDepartmentPage(
        deptId,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        page: next,
        size: _pageSize,
      );
      if (!mounted || _deptFilter != deptId) return;
      setState(() {
        _deptTasks = <TaskItem>[..._deptTasks, ...result.items];
        _taskPage = next;
        _hasMoreTasks = result.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _selectDept(int? deptId) async {
    setState(() {
      _deptFilter = deptId;
      _deptTasks = const [];
      _hasMoreTasks = false;
      _taskPage = 0;
      _error = null;
    });
    _publishChrome();
    if (deptId != null) {
      await _loadDeptTasks(reset: true);
    }
  }

  List<HrbpDeptStat> get _visibleDepts {
    if (_deptFilter == null) return _depts;
    return _depts.where((d) => d.departmentId == _deptFilter).toList();
  }

  int get _sumTotal =>
      _visibleDepts.fold(0, (a, d) => a + d.mainTotal);

  int get _sumCompleted =>
      _visibleDepts.fold(0, (a, d) => a + d.mainCompleted);

  int get _sumOverdue =>
      _visibleDepts.fold(0, (a, d) => a + d.mainOverdue);

  String get _deptFilterLabel {
    if (_deptFilter == null) return '全部部门';
    final d = _depts.where((e) => e.departmentId == _deptFilter).firstOrNull;
    if (d == null) return '全部部门';
    return d.departmentName.isEmpty ? '部门 ${d.departmentId}' : d.departmentName;
  }

  String get _dateRangeLabel {
    String fmt(DateTime d, {required bool withYear}) {
      return withYear ? '${d.year}/${d.month}/${d.day}' : '${d.month}/${d.day}';
    }

    final sameYear = _dateFrom.year == _dateTo.year;
    return '${fmt(_dateFrom, withYear: true)}–${fmt(_dateTo, withYear: !sameYear)}';
  }

  Future<void> _pickDateRange() async {
    final picked = await showTaskDateRangePicker(
      context,
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
      helpText: '有起止日的按周期筛选；没有起止日的（如会议纪要创建）按创建日计入',
    );
    if (!mounted || picked == null) return;
    setState(() {
      _dateFrom =
          DateTime(picked.start.year, picked.start.month, picked.start.day);
      _dateTo = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    unawaited(_reload());
  }

  void _resetDateToCurrentMonth() {
    final month = _currentMonthRange();
    setState(() {
      _dateFrom = month.from;
      _dateTo = month.to;
    });
    unawaited(_reload());
  }

  void _rememberBoardScroll() {
    if (_page == _HrbpPage.board && _scrollController.hasClients) {
      _boardScrollOffset = _scrollController.offset;
    }
  }

  void _restoreBoardScroll() {
    Future<void>.delayed(const Duration(milliseconds: 320), () {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(_boardScrollOffset.clamp(0.0, max));
    });
  }

  void _openBoard({bool refresh = false}) {
    setState(() {
      _pageNavBack = true;
      _page = _HrbpPage.board;
      _detailId = null;
      _detailStack.clear();
      _actionTask = null;
      _actionMode = null;
    });
    _publishChrome();
    if (refresh) {
      unawaited(_reload());
      return;
    }
    if (_deptFilter != null) {
      unawaited(_loadDeptTasks(reset: true).whenComplete(_restoreBoardScroll));
    } else {
      _restoreBoardScroll();
    }
  }

  void _backFromDetail() {
    if (_detailStack.isNotEmpty) {
      final prev = _detailStack.removeLast();
      setState(() {
        _pageNavBack = true;
        _page = _HrbpPage.detail;
        _detailId = prev;
        _actionTask = null;
        _actionMode = null;
      });
      _publishChrome();
      return;
    }
    _openBoard();
  }

  void _openDetail(int id) {
    _rememberBoardScroll();
    setState(() {
      _pageNavBack = false;
      if (_page == _HrbpPage.detail &&
          _detailId != null &&
          _detailId != id) {
        _detailStack.add(_detailId!);
      }
      _page = _HrbpPage.detail;
      _detailId = id;
      _actionTask = null;
      _actionMode = null;
    });
    _publishChrome();
  }

  void _openAction(TaskItem task, TaskActionMode mode) {
    setState(() {
      _pageNavBack = false;
      _page = _HrbpPage.action;
      _actionTask = task;
      _actionMode = mode;
    });
    _publishChrome();
  }

  void _backFromAction() {
    setState(() {
      _pageNavBack = true;
      _page = _detailId != null ? _HrbpPage.detail : _HrbpPage.board;
      _actionTask = null;
      _actionMode = null;
    });
    _publishChrome();
  }

  Key get _pageKey => switch (_page) {
        _HrbpPage.board => const ValueKey('hrbp-board'),
        _HrbpPage.detail => ValueKey('hrbp-detail-$_detailId'),
        _HrbpPage.action =>
          ValueKey('hrbp-action-$_actionMode-${_actionTask?.id}'),
      };

  Widget _pageBody() {
    switch (_page) {
      case _HrbpPage.action:
        final task = _actionTask;
        final mode = _actionMode;
        if (task == null || mode == null) return _buildBoard();
        return NativeTaskActionView(
          session: widget.session,
          task: task,
          mode: mode,
          onBack: _backFromAction,
          onDone: _backFromAction,
        );
      case _HrbpPage.detail:
        final id = _detailId;
        if (id == null) return _buildBoard();
        return NativeTaskDetailView(
          session: widget.session,
          taskId: id,
          backLabel: _deptFilter != null ? _deptFilterLabel : '任务汇总',
          viewerHint: '这是部门汇总里的只读查看，不能改进度或评价。',
          onBack: _backFromDetail,
          onOpenTask: _openDetail,
          onOpenProgress: (t) => _openAction(t, TaskActionMode.progress),
          onOpenEvaluate: (t) => _openAction(t, TaskActionMode.evaluate),
        );
      case _HrbpPage.board:
        return _buildBoard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBack = _pageNavBack;
    final child = KeyedSubtree(key: _pageKey, child: _pageBody());
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.hardEdge,
          children: isBack
              ? [?currentChild, ...previousChildren]
              : [...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (transitionChild, animation) {
        final isIncoming = transitionChild.key == child.key;
        final begin = isIncoming
            ? (isBack ? const Offset(-0.18, 0) : const Offset(1, 0))
            : (isBack ? const Offset(1, 0) : const Offset(-0.18, 0));
        return SlideTransition(
          position:
              Tween<Offset>(begin: begin, end: Offset.zero).animate(animation),
          child: transitionChild,
        );
      },
      child: child,
    );
  }

  Widget _filterChip({
    required String label,
    required bool active,
    required VoidCallback onTap,
    Widget? trailing,
    IconData? icon,
  }) {
    return Material(
      color: active ? kTaskPurple.withValues(alpha: 0.08) : const Color(0xFFF5F6F8),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: active ? kTaskPurple : DunesColors.text3,
                ),
                const SizedBox(width: 4),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active ? kTaskPurple : DunesColors.text2,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 2), trailing],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final deptItems = <(int?, String)>[
      (null, '全部部门'),
      for (final d in _depts)
        (
          d.departmentId,
          d.departmentName.isEmpty ? '部门 ${d.departmentId}' : d.departmentName,
        ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TaskFilterChipDropdown<int?>(
            value: _deptFilter,
            label: _deptFilterLabel,
            items: deptItems,
            onChanged: (v) => unawaited(_selectDept(v)),
            minMenuWidth: 180,
          ),
          _filterChip(
            label: '周期 $_dateRangeLabel',
            active: true,
            icon: Icons.date_range_outlined,
            onTap: _pickDateRange,
            trailing: InkWell(
              onTap: _resetDateToCurrentMonth,
              child: const Padding(
                padding: EdgeInsets.only(left: 2),
                child: Icon(Icons.restart_alt, size: 14, color: kTaskPurple),
              ),
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded, color: DunesColors.text2),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard() {
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: RefreshIndicator(
        onRefresh: _reload,
        color: kTaskPurple,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: kTaskPurple),
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                      TextButton(onPressed: _reload, child: const Text('重试')),
                    ],
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '看各部门主任务办得怎样。进度是填报比例，办结才算完成。没有起止日的任务按创建日计入所选周期。',
                        style: TextStyle(
                          fontSize: 13,
                          color: DunesColors.text3,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildToolbar(),
                      const SizedBox(height: 12),
                      _StatStrip(
                        total: _sumTotal,
                        completed: _sumCompleted,
                        overdue: _sumOverdue,
                      ),
                      const SizedBox(height: 14),
                      _buildChartCard(),
                    ],
                  ),
                ),
              ),
              ..._buildDeptOrTaskSlivers(),
              if (_loadingMore)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: kTaskPurple,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard() {
    final singleDept = _deptFilter != null;
    if (singleDept) {
      final tasks = _deptTasks;
      return _HrbpBarChart(
        title: '该部门主任务填报进度',
        hint: '柱高是每条主任务自己填的进度，点柱打开详情。',
        emptyText: '该部门暂无主任务',
        bars: [
          for (final t in tasks)
            _HrbpBarData(
              id: t.id,
              label: t.title.trim().isEmpty ? '未命名' : t.title.trim(),
              sublabel: [
                t.ownerName.isEmpty ? '未指定负责人' : t.ownerName,
                if (t.overdue && t.status != 'completed') '已逾期',
              ].join(' · '),
              progress: t.progressPct.toDouble(),
              overdue: t.overdue && t.status != 'completed',
              completed: t.status == 'completed',
            ),
        ],
        onBarTap: (id) => _openDetail(id),
      );
    }

    return _HrbpBarChart(
      title: '各部门填报进度',
      hint: '柱高是该部门主任务进度的平均值，点柱查看这个部门。',
      emptyText: '暂无部门数据',
      bars: [
        for (final d in _visibleDepts)
          _HrbpBarData(
            id: d.departmentId,
            label: d.departmentName.isEmpty
                ? '部门 ${d.departmentId}'
                : d.departmentName,
            sublabel: [
              '${d.mainTotal} 个主任务',
              if (d.mainOverdue > 0) '${d.mainOverdue} 逾期',
            ].join(' · '),
            progress: d.avgProgress,
            overdue: d.mainOverdue > 0,
            completed: d.allClosed,
          ),
      ],
      onBarTap: (id) => unawaited(_selectDept(id)),
    );
  }

  List<Widget> _buildDeptOrTaskSlivers() {
    if (_deptFilter != null) {
      final tasks = _deptTasks;
      if (tasks.isEmpty) {
        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                    const Text(
                    '这个部门的主任务',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => unawaited(_selectDept(null)),
                    child: const Text('返回全部部门'),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text('暂无任务', style: TextStyle(color: DunesColors.text3)),
              ),
            ),
          ),
        ];
      }
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                const Text(
                  '这个部门的主任务',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => unawaited(_selectDept(null)),
                  child: const Text('返回全部部门'),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                final t = tasks[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TaskStatCard(
                    task: t,
                    onTap: () => _openDetail(t.id),
                  ),
                );
              },
              childCount: tasks.length,
            ),
          ),
        ),
      ];
    }

    if (_visibleDepts.isEmpty) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: Text('暂无部门数据', style: TextStyle(color: DunesColors.text3)),
            ),
          ),
        ),
      ];
    }

    return [
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
        sliver: SliverToBoxAdapter(
          child: Text(
            '部门任务',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) {
              final st = _visibleDepts[i];
              final name = st.departmentName.isEmpty
                  ? '部门 ${st.departmentId}'
                  : st.departmentName;
                return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _DeptStatCard(
                  name: name,
                  summary: st.summaryLine,
                  overdue: st.mainOverdue,
                  avgProgress: st.avgProgress,
                  completed: st.allClosed,
                  onTap: () => unawaited(_selectDept(st.departmentId)),
                ),
              );
            },
            childCount: _visibleDepts.length,
          ),
        ),
      ),
    ];
  }
}

class _HrbpBarData {
  const _HrbpBarData({
    required this.id,
    required this.label,
    required this.sublabel,
    required this.progress,
    this.overdue = false,
    this.completed = false,
  });

  final int id;
  final String label;
  final String sublabel;
  final double progress;
  final bool overdue;
  final bool completed;
}

class _HrbpBarChart extends StatelessWidget {
  const _HrbpBarChart({
    required this.title,
    required this.bars,
    required this.emptyText,
    this.hint,
    this.onBarTap,
  });

  final String title;
  final String? hint;
  final List<_HrbpBarData> bars;
  final String emptyText;
  final ValueChanged<int>? onBarTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (hint != null && hint!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              style: const TextStyle(
                fontSize: 12,
                color: DunesColors.text3,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (bars.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  emptyText,
                  style: const TextStyle(color: DunesColors.text3),
                ),
              ),
            )
          else
            SizedBox(
              height: 248,
              child: LayoutBuilder(
                builder: (context, c) {
                  const minColW = 96.0;
                  const maxColW = 120.0;
                  const gap = 18.0;
                  final n = bars.length;
                  final evenW = n <= 0
                      ? minColW
                      : (c.maxWidth - gap * (n - 1)) / n;
                  final scroll = evenW < minColW;
                  final colW = scroll
                      ? minColW
                      : evenW.clamp(minColW, maxColW);
                  final rowWidth = n * colW + (n - 1) * gap;
                  final row = Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < n; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        SizedBox(
                          width: colW,
                          child: _HrbpVerticalBar(
                            data: bars[i],
                            onTap: onBarTap == null
                                ? null
                                : () => onBarTap!(bars[i].id),
                          ),
                        ),
                      ],
                    ],
                  );
                  final body = scroll
                      ? MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: HorizontalDragScrollView(
                            child: SizedBox(width: rowWidth, child: row),
                          ),
                        )
                      : rowWidth < c.maxWidth
                      ? Align(
                          alignment: Alignment.center,
                          child: SizedBox(width: rowWidth, child: row),
                        )
                      : row;
                  return body;
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _HrbpVerticalBar extends StatelessWidget {
  const _HrbpVerticalBar({required this.data, this.onTap});

  final _HrbpBarData data;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pct = data.progress.clamp(0, 100) / 100.0;
    final tone = taskProgressTone(
      data.progress,
      overdue: data.overdue,
      completed: data.completed,
    );
    final colors = taskProgressGradientColors(
      data.progress,
      overdue: data.overdue,
      completed: data.completed,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) {
                  const labelH = 20.0;
                  final maxBarH = (c.maxHeight - labelH).clamp(8.0, c.maxHeight);
                  final barH = pct <= 0
                      ? 5.0
                      : (maxBarH * pct).clamp(8.0, maxBarH);
                  final barW = (c.maxWidth * 0.46).clamp(26.0, 36.0);
                  return Column(
                    children: [
                      const Spacer(),
                      Text(
                        '${data.progress.round()}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: tone,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: barH,
                        width: barW,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(7),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: colors,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Container(height: 1, color: const Color(0xFFE6E8EC)),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: Column(
                children: [
                  Text(
                    data.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.sublabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      color: DunesColors.text3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatStrip extends StatelessWidget {
  const _StatStrip({
    required this.total,
    required this.completed,
    required this.overdue,
  });

  final int total;
  final int completed;
  final int overdue;

  @override
  Widget build(BuildContext context) {
    Widget cell(String value, String label, String hint, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DunesColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hint,
                style: const TextStyle(fontSize: 11, color: DunesColors.text3),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        cell('$total', '主任务', '当期一共几条', kTaskPurple),
        const SizedBox(width: 8),
        cell('$completed', '已办结', '已经闭环', const Color(0xFF1F9D76)),
        const SizedBox(width: 8),
        cell('$overdue', '已逾期', '过期还未办结', const Color(0xFFB45309)),
      ],
    );
  }
}

class _DeptStatCard extends StatelessWidget {
  const _DeptStatCard({
    required this.name,
    required this.summary,
    required this.overdue,
    required this.avgProgress,
    required this.completed,
    required this.onTap,
  });

  final String name;
  final String summary;
  final int overdue;
  final double avgProgress;
  final bool completed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = avgProgress.round().clamp(0, 100);
    final unfinishedOverdue = overdue > 0 && !completed;
    final tone = taskProgressTone(
      pct,
      overdue: unfinishedOverdue,
      completed: completed,
    );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    taskFillProgressLabel(pct),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tone,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: DunesColors.text3.withValues(alpha: 0.8),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                summary,
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
              const SizedBox(height: 10),
              TaskProgressBar(
                progressPct: pct,
                height: 12,
                overdue: unfinishedOverdue,
                completed: completed,
                showLabel: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskStatCard extends StatelessWidget {
  const _TaskStatCard({
    required this.task,
    required this.onTap,
  });

  final TaskItem task;
  final VoidCallback onTap;

  String _fmtDate(DateTime? d) {
    if (d == null) return '未定';
    final local = d.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final done = task.status == 'completed';
    final overdueOpen = task.overdue && !done;
    final tone = taskProgressTone(
      task.progressPct,
      overdue: overdueOpen,
      completed: done,
    );
    final hint = taskUnfinishedOverdueHint(
      overdue: task.overdue,
      completed: done,
      progressPct: task.progressPct,
    );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    taskFillProgressLabel(task.progressPct),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  TaskMetaChip(
                    text: overdueOpen ? '已逾期未办结' : taskStatusLabel(task.status),
                    color: overdueOpen
                        ? const Color(0xFFB45309)
                        : (done
                            ? const Color(0xFF1F9D76)
                            : kTaskPurple),
                  ),
                  if (task.ownerName.isNotEmpty)
                    TaskMetaChip(
                      text: '负责人 ${task.ownerName}',
                      color: DunesColors.text2,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '任务周期 ${_fmtDate(task.startAt)} ~ ${_fmtDate(task.dueAt)}',
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
              if (taskCardContextLine(task) != null) ...[
                const SizedBox(height: 4),
                Text(
                  taskCardContextLine(task)!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: DunesColors.text3),
                ),
              ],
              if (hint != null) ...[
                const SizedBox(height: 6),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB45309),
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TaskProgressBar(
                progressPct: task.progressPct,
                height: 12,
                overdue: overdueOpen,
                completed: done,
                showLabel: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
