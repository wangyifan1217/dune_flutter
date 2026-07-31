import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
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

  int get _sumPending =>
      _visibleDepts.fold(0, (a, d) => a + d.pendingApproval);

  String get _deptFilterLabel {
    if (_deptFilter == null) return '全部部门';
    final d = _depts.where((e) => e.departmentId == _deptFilter).firstOrNull;
    if (d == null) return '全部部门';
    return d.departmentName.isEmpty ? '部门 ${d.departmentId}' : d.departmentName;
  }

  String get _dateRangeLabel {
    String fmt(DateTime d) => '${d.month}/${d.day}';
    return '${fmt(_dateFrom)}-${fmt(_dateTo)}';
  }

  Future<void> _pickDateRange() async {
    final picked = await showTaskDateRangePicker(
      context,
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
      helpText: '按任务起止时间筛选',
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

  void _openBoard() {
    setState(() {
      _pageNavBack = true;
      _page = _HrbpPage.board;
      _detailId = null;
      _detailStack.clear();
      _actionTask = null;
      _actionMode = null;
    });
    _publishChrome();
    unawaited(_reload());
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
      _page = _HrbpPage.detail;
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
    return switch (_page) {
      _HrbpPage.action => NativeTaskActionView(
          session: widget.session,
          task: _actionTask!,
          mode: _actionMode!,
          onBack: _backFromAction,
          onDone: _backFromAction,
        ),
      _HrbpPage.detail => NativeTaskDetailView(
          session: widget.session,
          taskId: _detailId!,
          onBack: _backFromDetail,
          onOpenTask: _openDetail,
          onOpenProgress: (t) => _openAction(t, TaskActionMode.progress),
          onOpenEvaluate: (t) => _openAction(t, TaskActionMode.evaluate),
        ),
      _HrbpPage.board => _buildBoard(),
    };
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
                constraints: const BoxConstraints(maxWidth: 140),
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
            label: _dateRangeLabel,
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
                      _buildToolbar(),
                      const SizedBox(height: 12),
                      _StatStrip(
                        total: _sumTotal,
                        completed: _sumCompleted,
                        overdue: _sumOverdue,
                        pending: _sumPending,
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
        title: '主任务进度',
        emptyText: '该部门暂无主任务',
        bars: [
          for (final t in tasks)
            _HrbpBarData(
              id: t.id,
              label: t.title.trim().isEmpty ? '未命名' : t.title.trim(),
              sublabel: t.ownerName.isEmpty ? '未指定' : t.ownerName,
              progress: t.progressPct.toDouble(),
              overdue: t.overdue,
              completed: t.status == 'completed',
            ),
        ],
        onBarTap: (id) => _openDetail(id),
      );
    }

    return _HrbpBarChart(
      title: '各部门平均进度',
      emptyText: '暂无部门数据',
      bars: [
        for (final d in _visibleDepts)
          _HrbpBarData(
            id: d.departmentId,
            label: d.departmentName.isEmpty
                ? '部门 ${d.departmentId}'
                : d.departmentName,
            sublabel: '${d.mainTotal} 主任务',
            progress: d.avgProgress,
            overdue: d.mainOverdue > 0,
            completed: d.avgProgress >= 100,
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
                    '任务明细',
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
                  '任务明细',
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
            '部门明细',
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
                  total: st.mainTotal,
                  completed: st.mainCompleted,
                  overdue: st.mainOverdue,
                  pending: st.pendingApproval,
                  avgProgress: st.avgProgress,
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
    this.onBarTap,
  });

  final String title;
  final List<_HrbpBarData> bars;
  final String emptyText;
  final ValueChanged<int>? onBarTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
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
          const SizedBox(height: 12),
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
              height: 230,
              child: LayoutBuilder(
                builder: (context, c) {
                  const barW = 52.0;
                  const gap = 14.0;
                  final need = bars.length * barW + (bars.length - 1) * gap + 8;
                  final width = need < c.maxWidth ? c.maxWidth : need;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < bars.length; i++) ...[
                            if (i > 0) const SizedBox(width: gap),
                            SizedBox(
                              width: barW,
                              child: _HrbpVerticalBar(
                                data: bars[i],
                                onTap: onBarTap == null
                                    ? null
                                    : () => onBarTap!(bars[i].id),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
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
      borderRadius: BorderRadius.circular(8),
      child: Column(
        children: [
          Text(
            '${data.progress.round()}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: tone,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final h = (c.maxHeight * (pct <= 0 ? 0.05 : pct))
                    .clamp(6.0, c.maxHeight);
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: h,
                    width: 30,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(9),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: colors,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: tone.withValues(alpha: 0.22),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.sublabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }
}

class _StatStrip extends StatelessWidget {
  const _StatStrip({
    required this.total,
    required this.completed,
    required this.overdue,
    required this.pending,
  });

  final int total;
  final int completed;
  final int overdue;
  final int pending;

  @override
  Widget build(BuildContext context) {
    Widget cell(String value, String label, Color color) {
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
                style: const TextStyle(fontSize: 11, color: DunesColors.text3),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        cell('$total', '主任务', kTaskPurple),
        const SizedBox(width: 8),
        cell('$completed', '已完成', const Color(0xFF1F9D76)),
        const SizedBox(width: 8),
        cell('$overdue', '逾期', const Color(0xFFB45309)),
        const SizedBox(width: 8),
        cell('$pending', '待审', const Color(0xFF4C7FD4)),
      ],
    );
  }
}

class _DeptStatCard extends StatelessWidget {
  const _DeptStatCard({
    required this.name,
    required this.total,
    required this.completed,
    required this.overdue,
    required this.pending,
    required this.avgProgress,
    required this.onTap,
  });

  final String name;
  final int total;
  final int completed;
  final int overdue;
  final int pending;
  final double avgProgress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pct = avgProgress.round().clamp(0, 100);
    final tone = taskProgressTone(pct, overdue: overdue > 0 && pct < 100);
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
                    '$pct%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '主任务 $total · 完成 $completed · 逾期 $overdue'
                '${pending > 0 ? ' · 待审 $pending' : ''}',
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
              const SizedBox(height: 10),
              TaskProgressBar(
                progressPct: pct,
                height: 12,
                overdue: overdue > 0 && pct < 100,
                completed: pct >= 100,
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
    if (d == null) return '—';
    final local = d.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$m-$day';
  }

  @override
  Widget build(BuildContext context) {
    final done = task.status == 'completed';
    final tone = taskProgressTone(
      task.progressPct,
      overdue: task.overdue,
      completed: done,
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
                    '${task.progressPct}%',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: tone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  taskStatusLabel(task.status),
                  taskPriorityLabel(task.priority),
                  if (task.ownerName.isNotEmpty) task.ownerName,
                  if (task.overdue) '逾期',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
              const SizedBox(height: 4),
              Text(
                '开始 ${_fmtDate(task.startAt)} · 结束 ${_fmtDate(task.dueAt)}',
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
              const SizedBox(height: 10),
              TaskProgressBar(
                progressPct: task.progressPct,
                height: 12,
                overdue: task.overdue,
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
