import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'native_task_action_page.dart';
import 'native_task_daily_report_page.dart';
import 'native_task_detail_page.dart';
import 'native_task_form.dart';
import 'native_task_management_pane.dart';
import 'native_task_quick_create.dart';
import 'task_api.dart';
import 'task_approval_confirm.dart';
import 'task_first_use_guide.dart';
import 'task_inbox.dart';
import 'task_models.dart';
import 'task_widgets.dart';

enum _TaskPage { list, detail, action, daily, management }

class TaskShellChrome {
  const TaskShellChrome({
    this.hideShellHeader = false,
    this.trailing,
    this.onBack,
    this.backLabel,
    this.lockPageSwipe = false,
  });

  final bool hideShellHeader;
  final Widget? trailing;
  final VoidCallback? onBack;

  /// 顶栏返回文案；空则用「工作台」。
  final String? backLabel;

  /// 子页有横向列表时禁用工作台 PageView 抢手势。
  final bool lockPageSwipe;
}

/// 任务模块：统计条 + 筛选 + 小名片网格（风格对齐产品/能力）。
class NativeTaskHomePane extends StatefulWidget {
  const NativeTaskHomePane({
    super.key,
    required this.session,
    this.embedded = false,
    this.onChromeChanged,
  });

  final AuthSession session;
  final bool embedded;
  final ValueChanged<TaskShellChrome>? onChromeChanged;

  @override
  State<NativeTaskHomePane> createState() => _NativeTaskHomePaneState();
}

class _NativeTaskHomePaneState extends State<NativeTaskHomePane> {
  late final TaskApi _api = TaskApi(widget.session);
  final _search = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;
  _TaskPage _page = _TaskPage.list;

  /// 当前页切换是否为「返回」（决定滑动方向）。
  bool _pageNavBack = false;
  int? _detailId;
  int _detailReloadTick = 0;
  final List<int> _detailStack = [];
  TaskItem? _actionTask;
  TaskActionMode? _actionMode;
  TaskItem? _detailParentCache;

  List<TaskItem> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _listPage = 0;
  String? _error;
  static const int _pageSize = 20;

  /// inbox | actionable | goals。进入任务板块默认展示待办行动中心。
  String _scope = 'inbox';
  TaskInboxSnapshot? _inbox;
  TaskInboxBucket? _inboxFocus;
  String? _inboxWarning;
  static const int _inboxPreview = 3;
  String? _goalRole;
  String? _status;
  String? _priority;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  bool _dailyPending = false;
  String? _listFocus;
  bool _guideAutoStarted = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _search.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishChrome();
      unawaited(_showGuide());
    });
    unawaited(_reload());
  }

  Future<void> _showGuide({bool force = false}) async {
    if (!force && _guideAutoStarted) return;
    if (!force) _guideAutoStarted = true;
    await showTaskFirstUseGuide(
      context,
      userId: widget.session.userId,
      page: TaskGuidePage.home,
      force: force,
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    widget.onChromeChanged?.call(const TaskShellChrome());
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _loading ||
        _loadingMore ||
        !_hasMore ||
        _page != _TaskPage.list) {
      return;
    }
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 220) {
      unawaited(_loadMore());
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_reload());
    });
  }

  String get _apiScope => _scope;

  void _publishChrome() {
    if (_page == _TaskPage.detail ||
        _page == _TaskPage.action ||
        _page == _TaskPage.daily ||
        _page == _TaskPage.management) {
      widget.onChromeChanged?.call(
        TaskShellChrome(
          hideShellHeader: true,
          onBack: _page == _TaskPage.action
              ? _backFromAction
              : _page == _TaskPage.daily
              ? _backFromDaily
              : _page == _TaskPage.management
              ? _backFromManagement
              : _backFromDetail,
        ),
      );
      return;
    }
    widget.onChromeChanged?.call(
      TaskShellChrome(
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '任务功能',
              onPressed: _openManagement,
              icon: const Icon(
                Icons.widgets_outlined,
                color: DunesColors.text2,
              ),
            ),
            const SizedBox(width: 2),
            IconButton(
              tooltip: '使用指引',
              onPressed: () => unawaited(_showGuide(force: true)),
              icon: const Icon(Icons.help_outline, color: DunesColors.text2),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () => _openCreate(),
              child: const Text('完整创建'),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: _openQuickCreate,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('快速新建'),
              style: FilledButton.styleFrom(
                backgroundColor: kTaskPurple,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _inboxWarning = null;
      _hasMore = true;
      _listPage = 0;
    });
    if (_scope == 'inbox') {
      await _reloadInbox();
      return;
    }
    try {
      final list = await _api.listTasksPage(
        scope: _apiScope,
        status: _status,
        priority: _priority,
        q: _search.text,
        goalRole: _scope == 'goals' ? _goalRole : null,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        page: 0,
        size: _pageSize,
      );
      TaskDailyReportBundle? daily;
      try {
        daily = await _api.getDailyReport();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _items = list.items;
        _listPage = 0;
        _hasMore = list.hasMore;
        _loading = false;
        _loadingMore = false;
        _dailyPending =
            daily != null && daily.canSubmit && daily.report?.submitted != true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _reloadInbox() async {
    List<TaskItem> pending = const [];
    List<TaskItem> today = const [];
    String? warning;
    Object? failure;
    try {
      pending = await _api.listTasks(
        scope: 'pending_actions',
        q: _search.text,
        size: 100,
        maxPages: 2,
      );
    } catch (e) {
      failure = e;
      warning = '待处理事项暂时加载失败';
    }
    try {
      today = await _api.listTasks(
        scope: 'actionable',
        q: _search.text,
        size: 50,
        maxPages: 2,
      );
    } catch (e) {
      failure ??= e;
      warning = warning == null ? '今日任务暂时加载失败' : '待办暂时加载失败';
    }
    TaskDailyReportBundle? daily;
    try {
      daily = await _api.getDailyReport();
    } catch (_) {}
    if (!mounted) return;
    final bothFailed = failure != null && warning == '待办暂时加载失败';
    if (bothFailed) {
      setState(() {
        _error = '$failure';
        _loading = false;
        _loadingMore = false;
        _inbox = null;
      });
      return;
    }
    final snapshot = TaskInboxSnapshot.build(
      pending: pending,
      actionable: today,
    );
    setState(() {
      _inbox = snapshot;
      _items = const [];
      _hasMore = false;
      _loading = false;
      _loadingMore = false;
      _inboxWarning = warning;
      _dailyPending =
          daily != null && daily.canSubmit && daily.report?.submitted != true;
      if (_inboxFocus != null && snapshot.countOf(_inboxFocus!) == 0) {
        _inboxFocus = null;
      }
    });
  }

  Future<void> _loadMore() async {
    if (_scope == 'inbox' || _loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _listPage + 1;
      final result = await _api.listTasksPage(
        scope: _apiScope,
        status: _status,
        priority: _priority,
        q: _search.text,
        goalRole: _scope == 'goals' ? _goalRole : null,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        page: next,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = <TaskItem>[..._items, ...result.items];
        _listPage = next;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _openList() {
    setState(() {
      _pageNavBack = true;
      _page = _TaskPage.list;
      _detailId = null;
      _detailStack.clear();
      _actionTask = null;
      _actionMode = null;
      _detailParentCache = null;
    });
    _publishChrome();
    unawaited(_reload());
  }

  void _backFromDetail() {
    if (_detailStack.isNotEmpty) {
      final prev = _detailStack.removeLast();
      setState(() {
        _pageNavBack = true;
        _page = _TaskPage.detail;
        _detailId = prev;
        _actionTask = null;
        _actionMode = null;
      });
      _publishChrome();
      return;
    }
    _openList();
  }

  void _openDetail(int id, {TaskItem? asParentCache}) {
    setState(() {
      _pageNavBack = false;
      if (_page == _TaskPage.detail && _detailId != null && _detailId != id) {
        _detailStack.add(_detailId!);
      }
      _page = _TaskPage.detail;
      _detailId = id;
      _actionTask = null;
      _actionMode = null;
      if (asParentCache != null) {
        _detailParentCache = asParentCache;
      }
    });
    _publishChrome();
  }

  Future<void> _openAction(TaskItem task, TaskActionMode mode) async {
    final changed = await showTaskActionDialog(
      context,
      session: widget.session,
      task: task,
      mode: mode,
    );
    if (changed && mounted) {
      unawaited(_reload());
    }
  }

  void _backFromAction() => _closeAction(refresh: false);

  void _doneAction() => _closeAction(refresh: true);

  void _closeAction({required bool refresh}) {
    setState(() {
      _pageNavBack = true;
      _page = _detailId != null ? _TaskPage.detail : _TaskPage.list;
      _actionTask = null;
      _actionMode = null;
    });
    _publishChrome();
    if (refresh) unawaited(_reload());
  }

  Future<void> _openQuickCreate() async {
    final created = await openTaskQuickCreate(
      context,
      session: widget.session,
      asGroup: true,
    );
    if (created == null || !mounted) return;
    await _reload();
    if (!mounted) return;
    showDunesActionToast(
      context,
      '已创建，可继续完善',
      actionLabel: '查看详情',
      icon: Icons.task_alt,
      onTap: () {
        if (mounted) _openDetail(created.id);
      },
    );
  }

  void _openDaily() {
    setState(() {
      _pageNavBack = false;
      _page = _TaskPage.daily;
    });
    _publishChrome();
  }

  void _backFromDaily() {
    setState(() {
      _pageNavBack = true;
      _page = _TaskPage.list;
    });
    _publishChrome();
    unawaited(_reload());
  }

  void _openManagement() {
    setState(() {
      _pageNavBack = false;
      _page = _TaskPage.management;
    });
    _publishChrome();
  }

  void _backFromManagement() {
    setState(() {
      _pageNavBack = true;
      _page = _TaskPage.list;
    });
    _publishChrome();
    unawaited(_reload());
  }

  Future<void> _openCreate({int? parentId, TaskItem? parentTask}) async {
    final created = await openTaskEditor(
      context,
      session: widget.session,
      parentTaskId: parentId,
      parentTask:
          parentTask ??
          (parentId != null && _detailParentCache?.id == parentId
              ? _detailParentCache
              : null),
    );
    if (created == null || !mounted) return;
    await _reload();
    if (!mounted) return;
    if (parentId == null) {
      showDunesActionToast(
        context,
        '已创建，可继续完善',
        actionLabel: '查看详情',
        icon: Icons.task_alt,
        onTap: () {
          if (mounted) _openDetail(created.id);
        },
      );
    } else {
      showDunesCenterToast(context, _createdTaskHint(created));
      setState(() => _detailReloadTick++);
      _openDetail(parentId);
    }
  }

  String _createdTaskHint(TaskItem created) {
    return switch (created.status) {
      'pending_assignment' => '已提交，对方接受后才会开始执行',
      'pending_approval' => '已提交，审批通过后才会生效',
      _ => '子目标已生效，可以开始执行',
    };
  }

  String get _dateRangeLabel {
    if (_dateFrom == null && _dateTo == null) return '时间段';
    String fmt(DateTime d) => '${d.month}/${d.day}';
    if (_dateFrom != null && _dateTo != null) {
      return '${fmt(_dateFrom!)}-${fmt(_dateTo!)}';
    }
    if (_dateFrom != null) return '${fmt(_dateFrom!)}起';
    return '至${fmt(_dateTo!)}';
  }

  Future<void> _pickDateRange() async {
    final picked = await showTaskDateRangePicker(
      context,
      initialDateRange: (_dateFrom != null && _dateTo != null)
          ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
          : null,
      helpText: '有起止日的按周期筛选；没有起止日的按创建日筛选',
    );
    if (!mounted || picked == null) return;
    setState(() {
      _dateFrom = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _dateTo = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    unawaited(_reload());
  }

  void _clearDateRange() {
    if (_dateFrom == null && _dateTo == null) return;
    setState(() {
      _dateFrom = null;
      _dateTo = null;
    });
    unawaited(_reload());
  }

  Widget _dateRangeChip() {
    final active = _dateFrom != null || _dateTo != null;
    return Material(
      color: active
          ? kTaskPurple.withValues(alpha: 0.08)
          : const Color(0xFFF5F6F8),
      borderRadius: BorderRadius.circular(10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _pickDateRange,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 10, active ? 4 : 12, 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.date_range_outlined,
                    size: 16,
                    color: active ? kTaskPurple : DunesColors.text3,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _dateRangeLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active ? kTaskPurple : DunesColors.text2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (active)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _clearDateRange,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(2, 10, 10, 10),
                child: Icon(Icons.close, size: 14, color: kTaskPurple),
              ),
            ),
        ],
      ),
    );
  }

  String get _statusLabel => switch (_status) {
    'pending_approval' => '待确认',
    'completed' => '已完成',
    'rejected' => '已驳回',
    'active' => '进行中',
    _ => '全部状态',
  };

  Key get _pageKey => switch (_page) {
    _TaskPage.list => const ValueKey('task-list'),
    _TaskPage.detail => ValueKey('task-detail-$_detailId-$_detailReloadTick'),
    _TaskPage.action => ValueKey('task-action-$_actionMode-${_actionTask?.id}'),
    _TaskPage.daily => const ValueKey('task-daily'),
    _TaskPage.management => const ValueKey('task-management'),
  };

  Widget _pageBody() {
    switch (_page) {
      case _TaskPage.action:
        final task = _actionTask;
        final mode = _actionMode;
        if (task == null || mode == null) return _buildList();
        return NativeTaskActionView(
          session: widget.session,
          task: task,
          mode: mode,
          onBack: _backFromAction,
          onDone: _doneAction,
        );
      case _TaskPage.daily:
        return NativeTaskDailyReportPage(
          session: widget.session,
          onBack: _backFromDaily,
        );
      case _TaskPage.management:
        return NativeTaskManagementPane(
          session: widget.session,
          onBack: _backFromManagement,
          onOpenTask: (id) {
            _backFromManagement();
            _openDetail(id);
          },
        );
      case _TaskPage.detail:
        final id = _detailId;
        if (id == null) return _buildList();
        return NativeTaskDetailView(
          session: widget.session,
          taskId: id,
          reloadToken: _detailReloadTick,
          onBack: _backFromDetail,
          onAddSubtask: () => _openCreate(
            parentId: id,
            parentTask: _detailParentCache?.id == id
                ? _detailParentCache
                : null,
          ),
          onOpenTask: _openDetail,
          onOpenProgress: (t) => _openAction(t, TaskActionMode.progress),
          onOpenEvaluate: (t) => _openAction(t, TaskActionMode.evaluate),
          onTaskLoaded: (t) {
            if (t.isMain) _detailParentCache = t;
          },
        );
      case _TaskPage.list:
        return _buildList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBack = _pageNavBack;
    final child = KeyedSubtree(
      key: _pageKey,
      // 点击输入框外的空白处收起软键盘（覆盖任务列表/详情/进度/评价等各级页）
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: _pageBody(),
      ),
    );
    return TaskTheme(
      child: AnimatedSwitcher(
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
          position: Tween<Offset>(
            begin: begin,
            end: Offset.zero,
          ).animate(animation),
          child: transitionChild,
        );
      },
      child: child,
    ),
    );
  }

  Widget _buildList() {
    return ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: RefreshIndicator(
        onRefresh: _reload,
        color: kTaskPurple,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _tabChip('inbox', '待办'),
                        const SizedBox(width: 8),
                        _tabChip('actionable', '今日'),
                        const SizedBox(width: 8),
                        _tabChip('goals', '主目标'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      switch (_scope) {
                        'goals' => switch (_goalRole) {
                          'reports' => '下级负责的主目标，含管理员导入的任务。进入详情后再看子目标。',
                          'owned' => '本人负责的主目标。进入详情后再看子目标。',
                          'assigned' => '本人分派的主目标。进入详情后再看子目标。',
                          _ => '本人负责或分派的主目标。进入详情后再看子目标。',
                        },
                        'actionable' =>
                          '今天要执行的子目标、未拆解的主目标和待确认子目标。',
                        _ => '先处理待你决定的事，再看逾期、今天截止和今日执行。',
                      },
                      style: const TextStyle(
                        fontSize: 13,
                        color: DunesColors.text3,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _dailyStatusChip(),
                    if (_scope == 'goals') ...[
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _roleChip(null, '全部'),
                            const SizedBox(width: 8),
                            _roleChip('owned', '我负责'),
                            const SizedBox(width: 8),
                            _roleChip('assigned', '我分派'),
                            const SizedBox(width: 8),
                            _roleChip('reports', '下级'),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_scope == 'inbox') _buildInboxSearch() else _buildToolbar(),
                  ],
                ),
              ),
            ),
            ..._buildBodySlivers(),
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
        ),
      ),
    );
  }

  Widget _roleChip(String? value, String label) {
    final on = _goalRole == value;
    return Material(
      color: on ? kTaskPurple.withValues(alpha: 0.12) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (_goalRole == value) return;
          setState(() => _goalRole = value);
          unawaited(_reload());
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: on ? kTaskPurple : DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dailyStatusChip() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openDaily,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                _dailyPending ? Icons.edit_calendar_outlined : Icons.task_alt,
                size: 18,
                color: _dailyPending
                    ? const Color(0xFFB45309)
                    : const Color(0xFF1F9D76),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _dailyPending ? '今日日报待填' : '打开日报',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (_dailyPending)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE11D48),
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: DunesColors.text3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabChip(String value, String label) {
    final on = _scope == value;
    return Expanded(
      child: Material(
        color: on ? kTaskPurple : Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (_scope == value) return;
            setState(() {
              _scope = value;
              _inboxFocus = null;
            });
            unawaited(_reload());
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : DunesColors.text2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInboxSearch() {
    return TextField(
      controller: _search,
      decoration: InputDecoration(
        hintText: '搜索标题',
        hintStyle: const TextStyle(color: DunesColors.text3, fontSize: 13),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        prefixIcon: const Icon(Icons.search, size: 20, color: DunesColors.text3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE8EAED)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE8EAED)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: '搜索标题',
              hintStyle: const TextStyle(
                color: DunesColors.text3,
                fontSize: 13,
              ),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF5F6F8),
              prefixIcon: const Icon(
                Icons.search,
                size: 20,
                color: DunesColors.text3,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _dateRangeChip(),
              const SizedBox(width: 8),
              TaskFilterChipDropdown<String?>(
                value: _status,
                label: _statusLabel,
                items: const [
                  (null, '全部状态'),
                  ('active', '进行中'),
                  ('pending_approval', '待确认'),
                  ('completed', '已完成'),
                  ('rejected', '已驳回'),
                ],
                onChanged: (v) {
                  setState(() => _status = v);
                  unawaited(_reload());
                },
                minMenuWidth: 160,
              ),
              const Spacer(),
              IconButton(
                tooltip: '刷新',
                onPressed: _reload,
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: DunesColors.text2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _listFocusChip('overdue', '逾期'),
              _listFocusChip('dueToday', '今天截止'),
              _listFocusChip('high', '高优先级'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _listFocusChip(String value, String label) {
    final on = _listFocus == value;
    return Material(
      color: on ? kTaskPurple.withValues(alpha: 0.12) : const Color(0xFFF5F6F8),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _listFocus = on ? null : value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: on ? kTaskPurple : DunesColors.text2,
            ),
          ),
        ),
      ),
    );
  }

  List<TaskItem> _focusItems(List<TaskItem> items) {
    final now = DateTime.now();
    var list = items;
    if (_scope == 'actionable') {
      list = list
          .where((task) => !taskStartsAfterToday(task, now))
          .toList(growable: false);
    }
    list = switch (_listFocus) {
      'overdue' => list.where((task) => task.overdue).toList(growable: false),
      'dueToday' =>
        list.where((task) => taskDueOnDay(task, now)).toList(growable: false),
      'high' => list
          .where(
            (task) => task.priority == 'high' || task.priority == 'urgent',
          )
          .toList(growable: false),
      _ => list,
    };
    return list;
  }

  List<Widget> _buildBodySlivers() {
    if (_loading) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator(color: kTaskPurple)),
        ),
      ];
    }
    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 36,
                ),
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                TextButton(onPressed: _reload, child: const Text('重试')),
              ],
            ),
          ),
        ),
      ];
    }

    if (_scope == 'inbox') return _buildInboxSlivers();

    final items = _focusItems(_items);
    final hasFilters =
        (_status != null && _status!.isNotEmpty) ||
        (_priority != null && _priority!.isNotEmpty) ||
        _listFocus != null ||
        _search.text.trim().isNotEmpty ||
        _dateFrom != null ||
        _dateTo != null;

    if (items.isEmpty) {
      if (hasFilters) {
        return [
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                '没有符合条件的结果',
                style: TextStyle(fontSize: 14, color: DunesColors.text3),
              ),
            ),
          ),
        ];
      }
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Container(
              width: 380,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE8EAED)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          kTaskPurple.withValues(alpha: 0.18),
                          kTaskPurple.withValues(alpha: 0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.task_alt_outlined,
                      color: kTaskPurple,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _scope == 'goals' ? '还没有主目标' : '还没有待处理的子目标',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _scope == 'goals'
                        ? '点右上角新建主目标，再在详情里添加子目标'
                        : '今天要做的子目标会列在这里',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: DunesColors.text3,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _openQuickCreate(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('快速新建'),
                    style: FilledButton.styleFrom(
                      backgroundColor: kTaskPurple,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        sliver: SliverList(
          delegate: SliverChildListDelegate(_buildItemCards(items)),
        ),
      ),
    ];
  }

  List<Widget> _buildItemCards(List<TaskItem> items) {
    final groupMode = _scope == 'goals';
    if (groupMode) {
      return [
        for (final t in items) ...[
          TaskWorkbenchCard(
            task: t,
            groupMode: true,
            onTap: () => _openDetail(t.id),
          ),
          const SizedBox(height: 10),
        ],
      ];
    }
    final work = items.where((t) => !t.isPending).toList(growable: false);
    final pending = items.where((t) => t.isPending).toList(growable: false);
    final out = <Widget>[];
    if (work.isNotEmpty) {
      out.add(
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            '今天要做',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: DunesColors.text3,
            ),
          ),
        ),
      );
      for (final t in work) {
        out.add(
          TaskWorkbenchCard(
            task: t,
            onTap: () => _openDetail(t.id),
            onProgress: () => _openAction(t, TaskActionMode.progress),
            onComplete: _canCompleteFromList(t) ? () => _completeFromList(t) : null,
            completeHint: _completeHint(t),
          ),
        );
        out.add(const SizedBox(height: 10));
      }
    }
    if (pending.isNotEmpty) {
      out.add(
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            '待我审核',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: DunesColors.text3,
            ),
          ),
        ),
      );
      for (final t in pending) {
        out.add(
          TaskWorkbenchCard(
            task: t,
            onTap: () => _openDetail(t.id),
            onApprove: () => _decide(t, pass: true),
            onReject: () => _decide(t, pass: false),
          ),
        );
        out.add(const SizedBox(height: 10));
      }
    }
    return out;
  }

  List<Widget> _buildInboxSlivers() {
    final snapshot = _inbox;
    if (snapshot == null) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('待办还没有加载出来')),
        ),
      ];
    }
    final searching = _search.text.trim().isNotEmpty;
    final children = <Widget>[
      if (_inboxWarning != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _inboxWarning!,
            style: const TextStyle(fontSize: 12, color: Color(0xFFB45309)),
          ),
        ),
      _inboxCountRow(snapshot),
      const SizedBox(height: 12),
    ];
    if (snapshot.isEmpty && snapshot.plannedCount == 0) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Center(
            child: Text(
              searching ? '没有符合条件的结果' : '现在没有待你处理的事',
              style: const TextStyle(fontSize: 14, color: DunesColors.text3),
            ),
          ),
        ),
      );
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          sliver: SliverList(delegate: SliverChildListDelegate(children)),
        ),
      ];
    }

    final focus = _inboxFocus;
    if (focus != null) {
      children.addAll(_inboxFocused(snapshot, focus));
    } else {
      children.addAll(_inboxOverview(snapshot));
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        sliver: SliverList(delegate: SliverChildListDelegate(children)),
      ),
    ];
  }

  Widget _inboxCountRow(TaskInboxSnapshot snapshot) {
    final chips = <(TaskInboxBucket, bool)>[
      (TaskInboxBucket.receive, true),
      (TaskInboxBucket.assignApproval, true),
      (TaskInboxBucket.changeApproval, true),
      if (snapshot.countOf(TaskInboxBucket.confirm) > 0)
        (TaskInboxBucket.confirm, true),
      if (snapshot.countOf(TaskInboxBucket.overdue) > 0)
        (TaskInboxBucket.overdue, false),
      if (snapshot.countOf(TaskInboxBucket.dueToday) > 0)
        (TaskInboxBucket.dueToday, false),
      if (snapshot.countOf(TaskInboxBucket.returned) > 0)
        (TaskInboxBucket.returned, false),
      if (snapshot.countOf(TaskInboxBucket.readyToClose) > 0)
        (TaskInboxBucket.readyToClose, false),
      if (snapshot.today.isNotEmpty) (TaskInboxBucket.today, false),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final bucket = chips[index].$1;
          final emphasis = chips[index].$2;
          final selected = _inboxFocus == bucket;
          final count = snapshot.countOf(bucket);
          return Material(
            color: selected
                ? kTaskPurple
                : emphasis
                ? const Color(0xFFF3EEFA)
                : Colors.white,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () {
                setState(() {
                  _inboxFocus = selected ? null : bucket;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  '${taskInboxBucketTitle(bucket)} $count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : emphasis
                        ? kTaskPurple
                        : DunesColors.text2,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _inboxFocused(TaskInboxSnapshot snapshot, TaskInboxBucket bucket) {
    final items = snapshot.itemsOf(bucket);
    return [
      _inboxSectionTitle(
        taskInboxBucketTitle(bucket),
        trailing: '返回全部',
        onTrailing: () => setState(() => _inboxFocus = null),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          taskInboxCardHint(bucket),
          style: const TextStyle(fontSize: 12, color: DunesColors.text3),
        ),
      ),
      for (final task in items) ...[
        _inboxCard(task, bucket),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _inboxOverview(TaskInboxSnapshot snapshot) {
    final out = <Widget>[];
    final decisionSections = snapshot.decisions
        .where((section) => section.items.isNotEmpty)
        .toList(growable: false);
    if (decisionSections.isNotEmpty) {
      out.add(_inboxGroupTitle('待我决策'));
      for (final section in decisionSections) {
        out.addAll(_inboxPreviewSection(section));
      }
    }
    if (snapshot.attention.isNotEmpty) {
      out.add(_inboxGroupTitle('需要关注'));
      for (final section in snapshot.attention) {
        out.addAll(_inboxPreviewSection(section));
      }
    }
    if (snapshot.today.isNotEmpty) {
      out.add(_inboxGroupTitle('今日执行'));
      out.addAll(
        _inboxPreviewSection(
          TaskInboxSection(
            bucket: TaskInboxBucket.today,
            title: '今天正在进行',
            items: snapshot.today,
          ),
        ),
      );
    }
    if (snapshot.plannedCount > 0) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '另有 ${snapshot.plannedCount} 项尚未到开始日，不在今日执行里。',
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
        ),
      );
    }
    return out;
  }

  List<Widget> _inboxPreviewSection(TaskInboxSection section) {
    final preview = section.items.take(_inboxPreview).toList(growable: false);
    return [
      _inboxSectionTitle(
        '${section.title} ${section.items.length}',
        trailing: section.items.length > _inboxPreview ? '查看全部' : null,
        onTrailing: section.items.length > _inboxPreview
            ? () => setState(() => _inboxFocus = section.bucket)
            : null,
      ),
      for (final task in preview) ...[
        _inboxCard(task, section.bucket),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _inboxGroupTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: DunesColors.text,
        ),
      ),
    );
  }

  Widget _inboxSectionTitle(
    String title, {
    String? trailing,
    VoidCallback? onTrailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DunesColors.text3,
              ),
            ),
          ),
          if (trailing != null)
            InkWell(
              onTap: onTrailing,
              child: Text(
                trailing,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: kTaskPurple,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _inboxCard(TaskItem task, TaskInboxBucket bucket) {
    final decision = switch (bucket) {
      TaskInboxBucket.receive ||
      TaskInboxBucket.assignApproval ||
      TaskInboxBucket.changeApproval ||
      TaskInboxBucket.confirm => true,
      _ => false,
    };
    final complete = bucket == TaskInboxBucket.readyToClose;
    return TaskWorkbenchCard(
      task: task,
      statusHint: taskInboxCardHint(bucket),
      approveLabel: switch (bucket) {
        TaskInboxBucket.receive => '接受',
        TaskInboxBucket.readyToClose => '标记完成',
        _ => '通过',
      },
      rejectLabel: bucket == TaskInboxBucket.receive ? '拒绝' : '驳回',
      onTap: () => _openDetail(task.id),
      onApprove: decision || complete
          ? () => _actOnInbox(task, bucket, pass: true)
          : null,
      onReject: decision ? () => _actOnInbox(task, bucket, pass: false) : null,
      onProgress: decision || complete
          ? null
          : () => _openAction(task, TaskActionMode.progress),
    );
  }

  Future<void> _actOnInbox(
    TaskItem task,
    TaskInboxBucket bucket, {
    required bool pass,
  }) async {
    if (bucket == TaskInboxBucket.readyToClose) {
      final ok = await confirmTaskComplete(context, title: task.title);
      if (!ok || !mounted) return;
      try {
        await _api.patchTask(task.id, {
          'status': 'completed',
          'forceComplete': true,
        });
        if (!mounted) return;
        showDunesCenterToast(context, '已办结');
        await _reload();
      } catch (e) {
        if (mounted) showDunesCenterToast(context, '$e');
      }
      return;
    }

    final result = await confirmTaskApproval(
      context,
      pass: pass,
      title: switch (bucket) {
        TaskInboxBucket.receive => pass ? '接受任务' : '拒绝任务',
        TaskInboxBucket.assignApproval => pass ? '通过指派' : '驳回指派',
        TaskInboxBucket.changeApproval => pass ? '通过变更' : '驳回变更',
        _ => pass ? '通过' : '驳回',
      },
      hint: pass ? '意见（选填）' : '原因（选填）',
    );
    if (!result.confirmed || !mounted) return;
    try {
      switch (bucket) {
        case TaskInboxBucket.receive:
          await _api.respondAssignment(
            task.id,
            accept: pass,
            comment: result.comment,
          );
          if (!mounted) return;
          showDunesCenterToast(
            context,
            pass ? '已接收，可以开始执行' : '已拒绝，发起人会收到结果',
          );
        case TaskInboxBucket.assignApproval:
          if (pass) {
            await _api.approveChange(task.id, comment: result.comment);
          } else {
            await _api.rejectChange(task.id, comment: result.comment);
          }
          if (!mounted) return;
          showDunesCenterToast(
            context,
            pass ? '指派已通过，负责人已变更' : '指派已驳回，负责人未变更',
          );
        case TaskInboxBucket.changeApproval:
          if (pass) {
            await _api.approveChange(task.id, comment: result.comment);
          } else {
            await _api.rejectChange(task.id, comment: result.comment);
          }
          if (!mounted) return;
          showDunesCenterToast(
            context,
            pass ? '变更已生效' : '变更已驳回，保留原内容',
          );
        case TaskInboxBucket.confirm:
          if (pass) {
            await _api.approve(task.id, comment: result.comment);
          } else {
            await _api.reject(task.id, comment: result.comment);
          }
          if (!mounted) return;
          showDunesCenterToast(context, pass ? '已通过，任务进入执行' : '已驳回');
        default:
          return;
      }
      await _reload();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    }
  }

  bool _canCompleteFromList(TaskItem task) {
    if (task.status == 'completed' || task.status == 'cancelled') return false;
    return taskCompleteBlockReason(task) == null;
  }

  String? _completeHint(TaskItem task) {
    if (task.status == 'completed' || task.status == 'cancelled') return null;
    return taskCompleteBlockReason(task);
  }

  Future<void> _completeFromList(TaskItem task) async {
    final blocked = taskCompleteBlockReason(task);
    if (blocked != null) {
      showDunesCenterToast(context, blocked);
      return;
    }
    final ok = await confirmTaskComplete(context, title: task.title);
    if (!ok || !mounted) return;
    try {
      await _api.patchTask(task.id, {
        'status': 'completed',
        'forceComplete': true,
      });
      if (!mounted) return;
      showDunesCenterToast(context, '已办结');
      await _reload();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    }
  }

  Future<void> _decide(TaskItem t, {required bool pass}) async {
    final result = await confirmTaskApproval(context, pass: pass);
    if (!result.confirmed || !mounted) return;
    try {
      if (pass) {
        await _api.approve(t.id, comment: result.comment);
        if (!mounted) return;
        showDunesCenterToast(context, '已通过');
      } else {
        await _api.reject(t.id, comment: result.comment);
        if (!mounted) return;
        showDunesCenterToast(context, '已驳回');
      }
      await _reload();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    }
  }
}
