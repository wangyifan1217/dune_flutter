import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/dunes_page_transition.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../../core/widgets/dunes_motion_kit.dart';
import '../auth/auth_session.dart';
import '../chat/im_celebration.dart';
import '../shell/dunes_toast.dart';
import 'native_task_action_page.dart';
import 'native_task_daily_report_page.dart';
import 'native_task_detail_page.dart';
import 'native_task_form.dart';
import 'native_task_management_pane.dart';
import 'native_task_quick_create.dart';
import 'task_api.dart';
import 'task_approval_confirm.dart';
import 'task_chat_forward.dart';
import 'task_first_use_guide.dart';
import 'task_helper_picker.dart';
import 'task_inbox.dart';
import 'task_models.dart';
import 'task_widgets.dart';
import 'task_subtasks_dialog.dart';

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
    this.onOpenSummary,
  });

  final AuthSession session;
  final bool embedded;
  final ValueChanged<TaskShellChrome>? onChromeChanged;
  final VoidCallback? onOpenSummary;

  @override
  State<NativeTaskHomePane> createState() => _NativeTaskHomePaneState();
}

class _NativeTaskHomePaneState extends State<NativeTaskHomePane> {
  late final TaskApi _api = TaskApi(widget.session);
  final _search = TextEditingController();
  final _scrollController = ScrollController();
  final _listStorage = PageStorageBucket();
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
  int _listGeneration = 0;
  String? _error;
  static const int _pageSize = 20;

  /// inbox | actionable | goals。进入任务板块直接打开主任务列表。
  String _scope = 'goals';
  bool _canCreateTasks = true;
  TaskInboxSnapshot? _inbox;
  TaskInboxBucket? _inboxFocus;
  String? _inboxWarning;
  static const int _inboxPreview = 3;
  String? _goalRole;
  String? _goalSource;
  TaskAssignee? _ownerFilter;
  DateTime? _completedMonth;
  bool _advancedFiltersOpen = false;
  bool _pcGridMode = true;

  /// 主目标列表的状态。除「我负责」外默认进行中。
  String? _goalStatus = 'active';

  /// 今日等其他列表的状态，不跟主目标的默认进行中绑在一起。
  String? _otherStatus;
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
    unawaited(_loadCreateAccess());
  }

  @override
  void didUpdateWidget(NativeTaskHomePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onOpenSummary != widget.onOpenSummary) {
      _publishChrome();
    }
  }

  Future<void> _loadCreateAccess() async {
    try {
      final intake = await _api.rdIntake();
      if (!mounted) return;
      setState(() => _canCreateTasks = intake.canCreate);
      _publishChrome();
    } catch (_) {}
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

  String? get _status => _scope == 'goals' ? _goalStatus : _otherStatus;
  String? get _statusQuery => _status == 'active' ? 'active_or_in_progress' : _status;
  String? get _priorityQuery => _listFocus == 'high' ? 'high_or_urgent' : _priority;

  void _setStatus(String? value) {
    if (value != 'completed') _completedMonth = null;
    if (_scope == 'goals') {
      _goalStatus = value;
    } else {
      _otherStatus = value;
    }
  }

  String? get _goalRoleQuery => _scope == 'goals' ? _goalRole : null;

  String? get _sourceQuery =>
      _scope == 'goals' && _goalSource != 'regular'
      ? (_goalSource ?? 'all')
      : null;

  String? get _excludeSourceQuery =>
      _scope == 'goals' && _goalSource == 'regular' ? 'probation' : null;

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
    final wide = MediaQuery.sizeOf(context).width >= 720;
    widget.onChromeChanged?.call(
      TaskShellChrome(
        trailing: wide ? _wideListActions() : _compactListActions(),
      ),
    );
  }

  Widget _wideListActions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFF3F1FA),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.045),
              width: hairline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TaskTopActionBtn(
                tooltip: '任务功能',
                icon: Icons.grid_view_rounded,
                onTap: _openManagement,
              ),
              if (widget.onOpenSummary != null)
                _TaskTopActionBtn(
                  tooltip: '任务汇总',
                  icon: Icons.bar_chart_rounded,
                  onTap: widget.onOpenSummary!,
                ),
              _TaskTopActionBtn(
                tooltip: '使用指引',
                icon: Icons.help_outline_rounded,
                onTap: () => unawaited(_showGuide(force: true)),
              ),
            ],
          ),
        ),
        if (_canCreateTasks) ...[
          const SizedBox(width: 8),
          _TaskTopPillButton(
            tooltip: '快速新建',
            icon: Icons.bolt_rounded,
            label: '快速',
            primary: false,
            onTap: () => unawaited(_openQuickCreate()),
          ),
          const SizedBox(width: 6),
          _TaskTopPillButton(
            tooltip: '完整创建',
            icon: Icons.add_rounded,
            label: '新建任务',
            primary: true,
            onTap: () => unawaited(_openCreate()),
          ),
        ],
      ],
    );
  }

  Widget _compactListActions() {
    if (widget.onOpenSummary == null && !_canCreateTasks) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      tooltip: '任务操作',
      icon: Icon(
        Icons.more_horiz_rounded,
        color: DunesColors.resolve(context, DunesColors.text2),
      ),
      offset: const Offset(0, 8),
      position: PopupMenuPosition.under,
      color: DunesColors.resolve(context, Colors.white),
      surfaceTintColor: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      elevation: 8,
      shadowColor: const Color(0x1F29203A),
      constraints: const BoxConstraints(minWidth: 204),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: DunesColors.resolve(
            context,
            Color(0xFFECE8F3),
            role: DunesColorRole.border,
          ),
        ),
      ),
      onSelected: (value) {
        switch (value) {
          case 'summary':
            widget.onOpenSummary?.call();
            break;
          case 'quick':
            unawaited(_openQuickCreate());
            break;
          case 'create':
            unawaited(_openCreate());
            break;
        }
      },
      itemBuilder: (context) => [
        if (widget.onOpenSummary != null)
          _taskActionMenuItem(
            value: 'summary',
            icon: Icons.bar_chart_rounded,
            label: '任务汇总',
          ),
        if (_canCreateTasks) ...[
          _taskActionMenuItem(
            value: 'quick',
            icon: Icons.bolt_rounded,
            label: '快速新建',
          ),
          _taskActionMenuItem(
            value: 'create',
            icon: Icons.add_task_rounded,
            label: '完整创建',
          ),
        ],
      ],
    );
  }

  PopupMenuItem<String> _taskActionMenuItem({
    required String value,
    required IconData icon,
    required String label,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: DunesColors.resolve(
                context,
                const Color(0xFFF3EFFB),
                role: DunesColorRole.surface,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 17,
              color: DunesColors.resolveNullable(context, kTaskPurple),
            ),
          ),
          const SizedBox(width: 11),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(context, DunesColors.text),
            ),
          ),
          const Spacer(),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: DunesColors.resolve(context, DunesColors.text3),
          ),
        ],
      ),
    );
  }

  Widget _toolIcon({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool filled = false,
  }) {
    final button = IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      style: filled
          ? IconButton.styleFrom(
              backgroundColor: kTaskPurple,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            )
          : null,
      icon: Icon(
        icon,
        size: 20,
        color: filled
            ? DunesColors.resolve(context, Colors.white)
            : DunesColors.resolve(context, DunesColors.text2),
      ),
    );
    if (!filled) return button;
    return Padding(padding: const EdgeInsets.only(left: 4), child: button);
  }

  Future<TaskListPage> _fetchListPage(int page) => _api.listTasksPage(
        scope: _apiScope,
        status: _statusQuery,
        priority: _priorityQuery,
        q: _search.text,
        goalRole: _goalRoleQuery,
        source: _sourceQuery,
        excludeSource: _excludeSourceQuery,
        ownerId: _ownerFilter?.id,
        overdueOnly: _listFocus == 'overdue',
        dueToday: _listFocus == 'dueToday',
        dueOrder: true,
        completedMonth: _completedMonth,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        page: page,
        size: _pageSize,
      );

  Future<void> _reload({bool preserveList = false}) async {
    final generation = ++_listGeneration;
    final lastPage = preserveList ? _listPage : 0;
    setState(() {
      _loading = !preserveList;
      _loadingMore = preserveList;
      _error = null;
      _inboxWarning = null;
      if (!preserveList) {
        _hasMore = true;
        _listPage = 0;
      }
    });
    if (_scope == 'inbox') {
      await _reloadInbox(generation);
      return;
    }
    try {
      var page = 0;
      var list = await _fetchListPage(page);
      final items = [...list.items];
      while (list.hasMore && page < lastPage) {
        if (!mounted || generation != _listGeneration) return;
        list = await _fetchListPage(++page);
        items.addAll(list.items);
      }
      TaskDailyReportBundle? daily;
      try {
        daily = await _api.getDailyReport();
      } catch (_) {}
      if (!mounted || generation != _listGeneration) return;
      setState(() {
        _items = dedupeTasksById(items);
        _listPage = page;
        _hasMore = list.hasMore;
        _loading = false;
        _loadingMore = false;
        _dailyPending =
            daily != null && daily.canSubmit && daily.report?.submitted != true;
      });
    } catch (e) {
      if (!mounted || generation != _listGeneration) return;
      setState(() {
        if (!preserveList) _error = '$e';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _reloadInbox(int generation) async {
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
    if (!mounted || generation != _listGeneration) return;
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
      userId: widget.session.userId,
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
    final generation = _listGeneration;
    try {
      final next = _listPage + 1;
      final result = await _fetchListPage(next);
      if (!mounted || generation != _listGeneration) return;
      setState(() {
        _items = dedupeTasksById(<TaskItem>[..._items, ...result.items]);
        _listPage = next;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted && generation == _listGeneration) setState(() => _loadingMore = false);
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
    unawaited(_reload(preserveList: true));
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

  Future<void> _shareTask(TaskItem task) => forwardTaskToConversation(
    context: context,
    session: widget.session,
    task: task,
  );

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
          ? DunesColors.resolve(
              context,
              DunesColors.brandPurpleSoft,
              role: DunesColorRole.surface,
            )
          : DunesColors.resolve(
              context,
              const Color(0xFFF2F2F7),
              role: DunesColorRole.surface,
            ),
      shape: const StadiumBorder(),
      child: SizedBox(
        height: 34,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              customBorder: const StadiumBorder(),
              hoverColor: Colors.transparent,
              onTap: () {
                HapticFeedback.selectionClick();
                _pickDateRange();
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, 0, active ? 4 : 12, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  Icon(
                    Icons.date_range_outlined,
                    size: 16,
                    color: active
                        ? DunesColors.resolve(context, kTaskPurple)
                        : DunesColors.resolve(context, DunesColors.text3),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _dateRangeLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? DunesColors.resolve(context, kTaskPurple)
                          : DunesColors.resolve(context, DunesColors.text2),
                    ),
                  ),
                ],
              ),
            ),
          ),
            if (active)
              InkWell(
                customBorder: const StadiumBorder(),
                hoverColor: Colors.transparent,
                onTap: () {
                  HapticFeedback.selectionClick();
                  _clearDateRange();
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 10, 0),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: DunesColors.resolveNullable(context, kTaskPurple),
                  ),
                ),
              ),
          ],
        ),
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
        return PageStorage(bucket: _listStorage, child: _buildList());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBack = _pageNavBack;
    final child = KeyedSubtree(
      key: _pageKey,
      // 点击输入框外的空白处收起软键盘（覆盖任务列表/详情/进度/评价等各级页）
      child: TaskCopyableScope(child: _pageBody()),
    );
    return TaskTheme(
      child: DunesBlurExpandSwitcher(
        isBack: isBack,
        child: child,
      ),
    );
  }

  Widget _buildList() {
    final screenW = MediaQuery.sizeOf(context).width;
    final isWide = screenW >= 780;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scopeHint = switch (_scope) {
      'goals' => switch (_goalRole) {
        'reports' => '任务流下级负责的主目标，点击卡片查看子目标',
        'owned' => '本人负责的主目标，点击卡片查看子目标',
        'assigned' => '本人分派的主目标，点击卡片查看子目标',
        _ => '本人负责、分派、下级及关联的主目标',
      },
      'actionable' => '今天要执行的子目标、未拆解的主目标和待确认子目标',
      _ => '先处理待你决定的事，再看逾期、今天截止和今日执行',
    };

    final inboxBadge =
        (_inbox?.decisions.fold<int>(0, (s, sec) => s + sec.items.length) ??
            0) +
        (_inbox?.attention.fold<int>(0, (s, sec) => s + sec.items.length) ?? 0);

    return ColoredBox(
      color: DunesColors.resolve(
        context,
        const Color(0xFFF5F5F7),
        role: DunesColorRole.surface,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1140),
          child: RefreshIndicator(
            onRefresh: _reload,
            color: kTaskPurple,
            child: CustomScrollView(
              key: const PageStorageKey('task-list-scroll'),
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    isWide ? 24 : 16,
                    14,
                    isWide ? 24 : 16,
                    12,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              flex: isWide ? 0 : 1,
                              child: _TaskScopeSegmentedControl(
                                value: _scope,
                                expand: !isWide,
                                inboxBadgeCount: inboxBadge,
                                onChanged: (value) {
                                  if (_scope == value) return;
                                  setState(() {
                                    _scope = value;
                                    _inboxFocus = null;
                                  });
                                  unawaited(_reload());
                                },
                              ),
                            ),
                            if (isWide) ...[
                              const SizedBox(width: 14),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, anim) =>
                                      FadeTransition(
                                        opacity: anim,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(0, 0.14),
                                            end: Offset.zero,
                                          ).animate(anim),
                                          child: child,
                                        ),
                                      ),
                                  child: Align(
                                    key: ValueKey('$_scope-$_goalRole'),
                                    alignment: Alignment.centerLeft,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: kTaskPurple.withValues(
                                              alpha: isDark ? 0.8 : 0.65,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            scopeHint,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
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
                                ),
                              ),
                              const SizedBox(width: 12),
                              _dailyStatusChip(compact: true),
                            ],
                            if (screenW < 720) ...[
                              const SizedBox(width: 6),
                              _TaskTopActionBtn(
                                tooltip: '任务功能',
                                icon: Icons.grid_view_rounded,
                                onTap: _openManagement,
                              ),
                              _TaskTopActionBtn(
                                tooltip: scopeHint,
                                icon: Icons.help_outline_rounded,
                                onTap: () =>
                                    unawaited(_showGuide(force: true)),
                              ),
                            ],
                          ],
                        ),
                        if (!isWide) ...[
                          const SizedBox(height: 10),
                          _dailyStatusChip(compact: false),
                        ],
                        if (_scope == 'goals') ...[
                          const SizedBox(height: 10),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _roleChip(null, '全部'),
                                const SizedBox(width: 6),
                                _roleChip('owned', '我负责'),
                                const SizedBox(width: 6),
                                _roleChip('assigned', '我分派'),
                                const SizedBox(width: 6),
                                _roleChip('participant', '我参与'),
                                const SizedBox(width: 6),
                                _roleChip('reports', '下级'),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        if (_scope == 'inbox')
                          _buildInboxSearch()
                        else
                          _buildToolbar(),
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
        ),
      ),
    );
  }

  Widget _roleChip(String? value, String label) {
    final on = _goalRole == value;
    return _TaskTactilePill(
      label: label,
      active: on,
      height: 31,
      radius: 10,
      onTap: () {
        if (_goalRole == value) return;
        setState(() {
          final wasUnfiltered = _goalRole == 'owned' || _goalRole == 'assigned';
          _goalRole = value;
          if (value == 'owned' || value == 'assigned') {
            if (_completedMonth == null) _goalStatus = null;
          } else if (wasUnfiltered) {
            if (_completedMonth == null) _goalStatus = 'active';
          }
        });
        unawaited(_reload());
      },
    );
  }

  Widget _dailyStatusChip({bool compact = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );
    final accent = _dailyPending
        ? const Color(0xFFD97706)
        : const Color(0xFF1F9D76);
    return _TaskInteractiveSurface(
      borderRadius: BorderRadius.circular(compact ? 11 : 14),
      hoverColor: accent.withValues(alpha: isDark ? 0.14 : 0.08),
      baseColor: isDark ? const Color(0xFF1F1D2C) : Colors.white,
      borderColor: _dailyPending
          ? accent.withValues(alpha: 0.35)
          : (isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.055)),
      hoverBorderColor: accent.withValues(alpha: 0.45),
      borderWidth: hairline,
      onTap: _openDaily,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 8 : 11,
        ),
        child: Row(
          mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Icon(
              _dailyPending
                  ? Icons.edit_calendar_rounded
                  : Icons.task_alt_rounded,
              size: compact ? 16 : 18,
              color: DunesColors.resolve(context, accent),
            ),
            const SizedBox(width: 7),
            if (compact)
              Text(
                _dailyPending ? '今日日报待填' : '今日日报',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Expanded(
                child: Text(
                  _dailyPending ? '今日日报待填' : '打开日报',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            if (_dailyPending) ...[
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF5B61),
                  shape: BoxShape.circle,
                ),
              ),
            ],
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInboxSearch() {
    return TaskSearchField(
      controller: _search,
      hintText: '搜索标题或负责人',
      elevated: true,
    );
  }

  int get _activeAdvancedFilterCount {
    var n = 0;
    if (_goalSource != null) n++;
    if (_ownerFilter != null) n++;
    if (_completedMonth != null) n++;
    if (_dateFrom != null || _dateTo != null) n++;
    return n;
  }

  Widget _buildToolbar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isWide = MediaQuery.sizeOf(context).width >= 780;
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );
    final advCount = _activeAdvancedFilterCount;

    final statusDropdown = TaskFilterChipDropdown<String?>(
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
        HapticFeedback.selectionClick();
        setState(() => _setStatus(v));
        unawaited(_reload());
      },
      minMenuWidth: 156,
    );

    final filterToggle = _uniformFilterPill(
      label: advCount > 0 ? '筛选 ($advCount)' : '筛选',
      active: _advancedFiltersOpen || advCount > 0,
      onTap: () => setState(
        () => _advancedFiltersOpen = !_advancedFiltersOpen,
      ),
    );

    final viewToggle = isWide
        ? Tooltip(
            message: _pcGridMode ? '切换为紧凑单列' : '切换为双列网格',
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _pcGridMode = !_pcGridMode);
              },
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFF3F2F8),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  _pcGridMode
                      ? Icons.view_agenda_rounded
                      : Icons.grid_view_rounded,
                  size: 17,
                  color: DunesColors.resolve(context, kTaskPurple),
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    final refreshBtn = Tooltip(
      message: '刷新',
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () {
          HapticFeedback.selectionClick();
          unawaited(_reload());
        },
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : const Color(0xFFF3F2F8),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            Icons.refresh_rounded,
            size: 17.5,
            color: DunesColors.resolve(context, kTaskPurple),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1D2C) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.055),
          width: hairline,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color(0x1C000000)
                : const Color(0x083D2C7A),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isWide)
            Row(
              children: [
                Expanded(
                  child: TaskSearchField(
                    controller: _search,
                    hintText: '搜索标题或负责人',
                  ),
                ),
                const SizedBox(width: 10),
                statusDropdown,
                const SizedBox(width: 6),
                _listFocusChip('overdue', '逾期'),
                const SizedBox(width: 6),
                _listFocusChip('dueToday', '今天截止'),
                const SizedBox(width: 6),
                _listFocusChip('high', '高优'),
                const SizedBox(width: 6),
                filterToggle,
                const SizedBox(width: 6),
                viewToggle,
                const SizedBox(width: 6),
                refreshBtn,
              ],
            )
          else ...[
            TaskSearchField(
              controller: _search,
              hintText: '搜索标题或负责人',
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        statusDropdown,
                        const SizedBox(width: 6),
                        _listFocusChip('overdue', '逾期'),
                        const SizedBox(width: 6),
                        _listFocusChip('dueToday', '今天截止'),
                        const SizedBox(width: 6),
                        _listFocusChip('high', '高优'),
                        const SizedBox(width: 6),
                        filterToggle,
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                refreshBtn,
              ],
            ),
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _advancedFiltersOpen
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: hairline,
                          child: ColoredBox(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.045),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _dateRangeChip(),
                            if (_scope == 'goals')
                              TaskFilterChipDropdown<String?>(
                                value: _goalSource,
                                label: switch (_goalSource) {
                                  'regular' => '常规',
                                  'probation' => '试用期',
                                  _ => '全部来源',
                                },
                                items: const [
                                  (null, '全部来源'),
                                  ('regular', '常规'),
                                  ('probation', '试用期'),
                                ],
                                onChanged: (source) {
                                  setState(() => _goalSource = source);
                                  unawaited(_reload());
                                },
                              ),
                            _uniformFilterPill(
                              label: _ownerFilter?.displayName ?? '负责人',
                              active: _ownerFilter != null,
                              onTap: _filterByOwner,
                            ),
                            _uniformFilterPill(
                              label: _completedMonth == null
                                  ? '完成月份'
                                  : '${_completedMonth!.year}年${_completedMonth!.month}月',
                              active: _completedMonth != null,
                              onTap: _filterByCompletedMonth,
                            ),
                            if (advCount > 0)
                              _uniformFilterPill(
                                label: '清除筛选',
                                active: false,
                                onTap: () {
                                  setState(() {
                                    _goalSource = null;
                                    _ownerFilter = null;
                                    _completedMonth = null;
                                    _dateFrom = null;
                                    _dateTo = null;
                                  });
                                  unawaited(_reload());
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _filterByOwner() async {
    final picked = await showTaskHelperPicker(
      context,
      api: _api,
      selectedIds: const {},
      excludeUserId: 0,
      title: '按负责人筛选',
      single: true,
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    setState(() => _ownerFilter = picked.first);
    await _reload();
  }

  Future<void> _filterByCompletedMonth() async {
    final now = DateTime.now();
    final picked = await showTaskDatePicker(
      context,
      initialDate: _completedMonth ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: '选择完成月份中的任意一天',
    );
    if (!mounted || picked == null) return;
    setState(() {
      _completedMonth = DateTime(picked.year, picked.month);
      _setStatus('completed');
      _listFocus = null;
    });
    await _reload();
  }

  Widget _uniformFilterPill({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return _TaskTactilePill(
      label: label,
      active: active,
      height: 34,
      radius: 999,
      onTap: onTap,
    );
  }

  Widget _listFocusChip(String value, String label) {
    final on = _listFocus == value;
    return _uniformFilterPill(
      label: label,
      active: on,
      onTap: () {
        setState(() {
          _listFocus = on ? null : value;
          if (!on &&
              value != 'high' &&
              _status != null &&
              _status != 'active' &&
              _status != 'in_progress') {
            _setStatus(null);
          }
        });
        unawaited(_reload());
      },
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
      _ => list,
    };
    return list;
  }

  List<Widget> _buildBodySlivers() {
    if (_loading) {
      return [
        const SliverFillRemaining(
          hasScrollBody: true,
          child: DunesListSkeleton(),
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
                Icon(
                  Icons.error_outline,
                  color: DunesColors.resolve(context, Colors.redAccent),
                  size: 36,
                ),
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(
                    color: DunesColors.resolve(context, Colors.redAccent),
                  ),
                ),
                TextButton(onPressed: _reload, child: const Text('重试')),
              ],
            ),
          ),
        ),
      ];
    }

    if (_scope == 'inbox') return _buildInboxSlivers();

    final items = _focusItems(_items);
    final defaultActive =
        _scope == 'goals' && _goalRole != 'owned' && _status == 'active';
    final hasFilters =
        ((_status != null && _status!.isNotEmpty) && !defaultActive) ||
        (_priority != null && _priority!.isNotEmpty) ||
        _listFocus != null ||
        _search.text.trim().isNotEmpty ||
        _dateFrom != null ||
        _dateTo != null;

    if (items.isEmpty) {
      if (hasFilters) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyCard(
              icon: Icons.filter_alt_off_rounded,
              title: '没有符合条件的结果',
              subtitle: '试试调整筛选条件或清空搜索关键词',
              actionLabel: '重置筛选',
              actionIcon: Icons.refresh_rounded,
              onAction: () {
                setState(() {
                  _search.clear();
                  _listFocus = null;
                  _priority = null;
                  _goalSource = null;
                  _ownerFilter = null;
                  _completedMonth = null;
                  _dateFrom = null;
                  _dateTo = null;
                  if (_scope == 'goals') {
                    _goalStatus = _goalRole == 'owned' ? null : 'active';
                  } else {
                    _setStatus(null);
                  }
                });
                unawaited(_reload());
              },
            ),
          ),
        ];
      }
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyCard(
            icon: _scope == 'goals'
                ? Icons.flag_rounded
                : Icons.wb_sunny_rounded,
            title: _scope == 'goals' ? '还没有主目标' : '今日暂无待执行任务',
            subtitle: _scope == 'goals'
                ? '点击右上角「新建任务」，可同时规划主目标与子任务'
                : '今天需要执行的子目标和待确认任务会展示在这里',
            actionLabel: _canCreateTasks ? '新建任务' : null,
            actionIcon: Icons.add_rounded,
            onAction: _canCreateTasks ? () => unawaited(_openCreate()) : null,
          ),
        ),
      ];
    }

    if (_scope == 'goals') {
      return _goalGroupSlivers(
        items,
        wide: MediaQuery.sizeOf(context).width >= 780 && _pcGridMode,
      );
    }
    final horiz = MediaQuery.sizeOf(context).width >= 780 ? 24.0 : 16.0;
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(horiz, 0, horiz, 24),
        sliver: SliverList(
          delegate: SliverChildListDelegate(_buildItemCards(items)),
        ),
      ),
    ];
  }

  Widget _buildEmptyCard({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    IconData? actionIcon,
    VoidCallback? onAction,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1F1D2C) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.055),
              width: hairline,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? const Color(0x22000000)
                    : const Color(0x0A3D2C7A),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      kTaskPurple.withValues(alpha: isDark ? 0.24 : 0.14),
                      const Color(
                        0xFF9C7CF4,
                      ).withValues(alpha: isDark ? 0.10 : 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  icon,
                  color: DunesColors.resolveNullable(context, kTaskPurple),
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: DunesColors.resolve(context, DunesColors.text),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: DunesColors.resolve(context, DunesColors.text3),
                  height: 1.45,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                _TaskTopPillButton(
                  tooltip: actionLabel,
                  icon: actionIcon ?? Icons.add_rounded,
                  label: actionLabel,
                  primary: true,
                  onTap: onAction,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<({String title, List<TaskItem> items})> _goalGroups(
    List<TaskItem> items,
  ) {
    final overdue = <TaskItem>[];
    final active = <TaskItem>[];
    final rest = <String, List<TaskItem>>{};
    final restOrder = <String>[];
    for (final task in items) {
      final open = task.status != 'completed' && task.status != 'cancelled';
      if (task.overdue && open) {
        overdue.add(task);
        continue;
      }
      if (task.status == 'active' || task.status == 'in_progress') {
        active.add(task);
        continue;
      }
      final completed = task.completedAtInferred
          ? null
          : task.completedAt?.toUtc().add(const Duration(hours: 8));
      final label = task.status != 'completed'
          ? taskStatusLabel(task.status)
          : completed == null
          ? '完成时间未记录'
          : '${completed.year}年${completed.month}月完成';
      rest
          .putIfAbsent(label, () {
            restOrder.add(label);
            return <TaskItem>[];
          })
          .add(task);
    }
    final groups = <({String title, List<TaskItem> items})>[];
    if (overdue.isNotEmpty) {
      groups.add((title: '已逾期', items: overdue));
    }
    if (_listFocus == 'overdue') return groups;
    if (active.isNotEmpty) {
      groups.add((title: '进行中', items: active));
    }
    for (final label in restOrder) {
      final bucket = rest[label];
      if (bucket != null && bucket.isNotEmpty) {
        groups.add((title: label, items: bucket));
      }
    }
    return groups;
  }

  Widget _sectionHeaderBar(String title, {int? count, Color? accent}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tone = accent ?? kTaskPurple;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 14,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: DunesColors.resolve(context, DunesColors.text),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
              decoration: BoxDecoration(
                color: tone.withValues(alpha: isDark ? 0.20 : 0.11),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolve(context, tone),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _goalGroupSlivers(List<TaskItem> items, {required bool wide}) {
    final groups = _goalGroups(items);
    final horiz = MediaQuery.sizeOf(context).width >= 780 ? 24.0 : 16.0;
    final slivers = <Widget>[];
    for (var i = 0; i < groups.length; i++) {
      final group = groups[i];
      final accent = group.title == '已逾期'
          ? const Color(0xFFFF4D57)
          : group.title == '进行中'
          ? kTaskPurple
          : const Color(0xFF1F9D76);
      slivers.add(
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horiz, i == 0 ? 2 : 10, horiz, 0),
          sliver: SliverToBoxAdapter(
            child: _sectionHeaderBar(
              group.title,
              count: group.items.length,
              accent: accent,
            ),
          ),
        ),
      );
      if (wide) {
        slivers.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horiz, 0, horiz, 12),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.crossAxisExtent / 340)
                    .floor()
                    .clamp(1, 4)
                    .toInt();
                final extent =
                    (group.items.any((t) => t.isPending)
                        ? 280
                        : group.items.any((t) => t.hasPendingChange)
                        ? 244
                        : 220) +
                    (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
                          0,
                          60,
                        ) *
                        8;
                final cardExtent = extent.toDouble();
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: cardExtent,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _goalCard(group.items[index], wide: true),
                    childCount: group.items.length,
                  ),
                );
              },
            ),
          ),
        );
      } else {
        slivers.add(
          SliverPadding(
            padding: EdgeInsets.fromLTRB(horiz, 0, horiz, 12),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                for (final task in group.items) ...[
                  _goalCard(task, wide: false),
                  const SizedBox(height: 10),
                ],
              ]),
            ),
          ),
        );
      }
    }
    if (slivers.isNotEmpty) {
      slivers.add(const SliverPadding(padding: EdgeInsets.only(bottom: 12)));
    }
    return slivers;
  }

  Widget _goalCard(TaskItem task, {required bool wide}) {
    return TaskWorkbenchCard(
      task: task,
      groupMode: true,
      onTap: () => _openDetail(task.id),
      onShare: () => unawaited(_shareTask(task)),
      onSubtasks: () => _openSubtasks(task),
      groupTrailingAction: wide ? _goalCardCompleteAction(task) : null,
    );
  }

  Widget _goalCardCompleteAction(TaskItem task) {
    if (task.status == 'completed') {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          '已完成',
          style: TextStyle(
            color: DunesColors.resolve(context, DunesColors.text3),
          ),
        ),
      );
    }
    if (!_canCompleteFromList(task)) {
      final hint = _completeHint(task);
      if (hint == null || hint.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          hint,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: DunesColors.resolve(context, DunesColors.text3),
          ),
        ),
      );
    }
    return TextButton(
      onPressed: () => unawaited(_completeFromList(task)),
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
      child: const Text('标记完成'),
    );
  }

  void _openSubtasks(TaskItem task) {
    showDialog<void>(
      context: context,
      builder: (_) => TaskSubtasksDialog(
        task: task,
        loadDetail: () => _api.getDetail(task.id),
        onOpenTask: (id) {
          if (mounted) _openDetail(id);
        },
      ),
    );
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
            onShare: () => unawaited(_shareTask(t)),
            onSubtasks: () => _openSubtasks(t),
          ),
          const SizedBox(height: 10),
        ],
      ];
    }
    final work = items.where((t) => !t.isPending).toList(growable: false);
    final pending = items.where((t) => t.isPending).toList(growable: false);
    final out = <Widget>[];
    if (work.isNotEmpty) {
      out.add(_sectionHeaderBar('今天要做', count: work.length));
      for (final t in work) {
        out.add(
          TaskWorkbenchCard(
            task: t,
            onTap: () => _openDetail(t.id),
            onShare: () => unawaited(_shareTask(t)),
            onProgress: () => _openAction(t, TaskActionMode.progress),
            onComplete: _canCompleteFromList(t)
                ? () => _completeFromList(t)
                : null,
            completeHint: _completeHint(t),
          ),
        );
        out.add(const SizedBox(height: 10));
      }
    }
    if (pending.isNotEmpty) {
      out.add(
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _sectionHeaderBar(
            '待我审核',
            count: pending.length,
            accent: const Color(0xFFD97706),
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
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolveNullable(context, Color(0xFFB45309)),
            ),
          ),
        ),
      _inboxCountRow(snapshot),
      const SizedBox(height: 12),
    ];
    final horiz = MediaQuery.sizeOf(context).width >= 780 ? 24.0 : 16.0;
    if (snapshot.isEmpty && snapshot.plannedCount == 0) {
      children.add(
        _buildEmptyCard(
          icon: searching
              ? Icons.search_off_rounded
              : Icons.check_circle_outline_rounded,
          title: searching ? '没有符合条件的结果' : '当前待办已全部清空',
          subtitle: searching
              ? '试试更换搜索关键词'
              : '待你确认、审批、逾期或今日截止的任务都会集中在这里',
          actionLabel: searching
              ? '清空搜索'
              : (_canCreateTasks ? '新建任务' : null),
          actionIcon: searching ? Icons.clear_rounded : Icons.add_rounded,
          onAction: searching
              ? () {
                  _search.clear();
                  unawaited(_reload());
                }
              : (_canCreateTasks ? () => unawaited(_openCreate()) : null),
        ),
      );
      return [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horiz, 0, horiz, 24),
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
        padding: EdgeInsets.fromLTRB(horiz, 0, horiz, 24),
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
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final bucket = chips[index].$1;
          final emphasis = chips[index].$2;
          final selected = _inboxFocus == bucket;
          final count = snapshot.countOf(bucket);
          return _TaskTactilePill(
            label: '${taskInboxBucketTitle(bucket)} $count',
            active: selected,
            emphasized: emphasis && !selected,
            height: 34,
            radius: 999,
            onTap: () {
              setState(() {
                _inboxFocus = selected ? null : bucket;
              });
            },
          );
        },
      ),
    );
  }

  List<Widget> _inboxFocused(
    TaskInboxSnapshot snapshot,
    TaskInboxBucket bucket,
  ) {
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
          style: TextStyle(
            fontSize: 12,
            color: DunesColors.resolve(context, DunesColors.text3),
          ),
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
            style: TextStyle(
              fontSize: 12,
              color: DunesColors.resolve(context, DunesColors.text3),
            ),
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
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: DunesColors.resolve(context, DunesColors.text),
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
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DunesColors.resolve(context, DunesColors.text3),
              ),
            ),
          ),
          if (trailing != null)
            InkWell(
              onTap: onTrailing,
              child: Text(
                trailing,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: DunesColors.resolveNullable(context, kTaskPurple),
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
      onShare: () => unawaited(_shareTask(task)),
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
          showDunesCenterToast(context, pass ? '已接收，可以开始执行' : '已拒绝，发起人会收到结果');
        case TaskInboxBucket.assignApproval:
          if (pass) {
            await _api.approveChange(task.id, comment: result.comment);
          } else {
            await _api.rejectChange(task.id, comment: result.comment);
          }
          if (!mounted) return;
          showDunesCenterToast(context, pass ? '指派已通过，负责人已变更' : '指派已驳回，负责人未变更');
        case TaskInboxBucket.changeApproval:
          if (pass) {
            await _api.approveChange(task.id, comment: result.comment);
          } else {
            await _api.rejectChange(task.id, comment: result.comment);
          }
          if (!mounted) return;
          showDunesCenterToast(context, pass ? '变更已生效' : '变更已驳回，保留原内容');
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
    if (!taskViewerCanComplete(task, widget.session.userId)) return false;
    return taskCompleteBlockReason(task) == null;
  }

  String? _completeHint(TaskItem task) {
    if (task.status == 'completed' || task.status == 'cancelled') return null;
    if (!taskViewerCanComplete(task, widget.session.userId)) return null;
    return taskCompleteBlockReason(task);
  }

  Future<void> _completeFromList(TaskItem task) async {
    if (!taskViewerCanComplete(task, widget.session.userId)) {
      showDunesCenterToast(context, '仅负责人和创建人可以标记完成');
      return;
    }
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
      maybeShowTaskCompletionEffect(context, widget.session.userId);
      await _reload();
    } catch (e) {
      if (mounted) {
        showDunesCenterToast(
          context,
          friendlyErrorText(e, fallback: '标记完成失败，请稍后重试'),
        );
      }
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

/// Apple 风格真滑动分段胶囊：主目标 / 待办 / 今日
class _TaskScopeSegmentedControl extends StatefulWidget {
  const _TaskScopeSegmentedControl({
    required this.value,
    required this.expand,
    required this.inboxBadgeCount,
    required this.onChanged,
  });

  final String value;
  final bool expand;
  final int inboxBadgeCount;
  final ValueChanged<String> onChanged;

  @override
  State<_TaskScopeSegmentedControl> createState() =>
      _TaskScopeSegmentedControlState();
}

class _TaskScopeSegmentedControlState
    extends State<_TaskScopeSegmentedControl> {
  static const _tabs = [
    (value: 'goals', label: '主目标', icon: Icons.flag_rounded),
    (value: 'inbox', label: '待办', icon: Icons.inbox_rounded),
    (value: 'actionable', label: '今日', icon: Icons.wb_sunny_rounded),
  ];

  int? _hoveredIndex;
  int? _pressedIndex;

  int get _selectedIndex {
    final idx = _tabs.indexWhere((t) => t.value == widget.value);
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );
    const pad = 3.0;
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : const Color(0xFFEBE8F4);
    final thumbColor = isDark ? const Color(0xFF2D2942) : Colors.white;
    final selectedIdx = _selectedIndex;

    Widget buildTrack(double totalWidth) {
      final segWidth = (totalWidth - pad * 2) / _tabs.length;
      return Container(
        height: 40,
        width: totalWidth,
        padding: const EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.045),
            width: hairline,
          ),
        ),
        child: Stack(
          children: [
            // 真滑动白色胶囊滑块
            AnimatedPositioned(
              duration: disableAnim
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              left: selectedIdx * segWidth,
              top: 0,
              bottom: 0,
              width: segWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: thumbColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.04),
                    width: hairline,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? const Color(0x38000000)
                          : const Color(0x143D2C7A),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  _buildSegment(
                    index: i,
                    selected: i == selectedIdx,
                    isDark: isDark,
                    disableAnim: disableAnim,
                  ),
              ],
            ),
          ],
        ),
      );
    }

    if (!widget.expand) {
      return buildTrack(294);
    }
    return LayoutBuilder(
      builder: (context, constraints) => buildTrack(constraints.maxWidth),
    );
  }

  Widget _buildSegment({
    required int index,
    required bool selected,
    required bool isDark,
    required bool disableAnim,
  }) {
    final tab = _tabs[index];
    final hovered = _hoveredIndex == index && !selected;
    final pressed = _pressedIndex == index;
    final showBadge = tab.value == 'inbox' && widget.inboxBadgeCount > 0;
    final textColor = selected
        ? DunesColors.resolve(context, kTaskPurple)
        : hovered
        ? DunesColors.resolve(context, DunesColors.text)
        : DunesColors.resolve(context, DunesColors.text2);

    return Expanded(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (mounted) setState(() => _hoveredIndex = index);
        },
        onExit: (_) {
          if (mounted && _hoveredIndex == index) {
            setState(() => _hoveredIndex = null);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressedIndex = index),
          onTapUp: (_) => setState(() => _pressedIndex = null),
          onTapCancel: () => setState(() => _pressedIndex = null),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onChanged(tab.value);
          },
          child: AnimatedScale(
            scale: pressed && !disableAnim ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: disableAnim
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: hovered
                    ? (isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.035))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tab.icon,
                    size: 14.5,
                    color: textColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    tab.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  if (showBadge) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 0.5,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? kTaskPurple.withValues(alpha: isDark ? 0.28 : 0.14)
                            : const Color(0xFFFF4D57),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        widget.inboxBadgeCount > 99
                            ? '99+'
                            : '${widget.inboxBadgeCount}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? DunesColors.resolve(context, kTaskPurple)
                              : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶栏分组工具图标按钮（带悬停高光与轻弹按压）
class _TaskTopActionBtn extends StatefulWidget {
  const _TaskTopActionBtn({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_TaskTopActionBtn> createState() => _TaskTopActionBtnState();
}

class _TaskTopActionBtnState extends State<_TaskTopActionBtn> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          child: AnimatedScale(
            scale: _pressed && !disableAnim ? 0.90 : 1.0,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 32,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _hovered
                    ? (isDark
                          ? Colors.white.withValues(alpha: 0.11)
                          : Colors.white)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: _hovered && !isDark
                    ? const [
                        BoxShadow(
                          color: Color(0x103D2C7A),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ]
                    : const [],
              ),
              child: Icon(
                widget.icon,
                size: 18,
                color: _hovered
                    ? DunesColors.resolve(context, kTaskPurple)
                    : DunesColors.resolve(context, DunesColors.text2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 顶栏 / 空态 触感胶囊按钮（支持品牌紫渐变主按钮 & 轻紫次按钮）
class _TaskTopPillButton extends StatefulWidget {
  const _TaskTopPillButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.primary,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  State<_TaskTopPillButton> createState() => _TaskTopPillButtonState();
}

class _TaskTopPillButtonState extends State<_TaskTopPillButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (mounted) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (mounted) setState(() => _hovered = false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: () {
            HapticFeedback.selectionClick();
            widget.onTap();
          },
          child: AnimatedScale(
            scale: _pressed && !disableAnim ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 36,
              padding: EdgeInsets.symmetric(
                horizontal: widget.primary ? 13 : 11,
              ),
              decoration: BoxDecoration(
                gradient: widget.primary
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _hovered
                            ? const [Color(0xFF8C6CE6), Color(0xFF6B4BC7)]
                            : const [Color(0xFF8363DF), kTaskPurple],
                      )
                    : null,
                color: widget.primary
                    ? null
                    : (_hovered
                          ? kTaskPurple.withValues(alpha: isDark ? 0.22 : 0.14)
                          : kTaskPurple.withValues(
                              alpha: isDark ? 0.14 : 0.08,
                            )),
                borderRadius: BorderRadius.circular(11),
                border: widget.primary
                    ? null
                    : Border.all(
                        color: kTaskPurple.withValues(
                          alpha: _hovered ? 0.32 : 0.18,
                        ),
                        width: hairline,
                      ),
                boxShadow: widget.primary
                    ? [
                        BoxShadow(
                          color: kTaskPurple.withValues(
                            alpha: _hovered ? 0.34 : 0.22,
                          ),
                          blurRadius: _hovered ? 12 : 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : const [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.icon,
                    size: 16.5,
                    color: widget.primary
                        ? Colors.white
                        : DunesColors.resolve(context, kTaskPurple),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: widget.primary
                          ? Colors.white
                          : DunesColors.resolve(context, kTaskPurple),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 统一触感筛选胶囊（带悬停边界高光 + 轻弹按压）
class _TaskTactilePill extends StatefulWidget {
  const _TaskTactilePill({
    required this.label,
    required this.active,
    required this.onTap,
    this.emphasized = false,
    this.height = 34,
    this.radius = 999,
  });

  final String label;
  final bool active;
  final bool emphasized;
  final double height;
  final double radius;
  final VoidCallback onTap;

  @override
  State<_TaskTactilePill> createState() => _TaskTactilePillState();
}

class _TaskTactilePillState extends State<_TaskTactilePill> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final hairline = (1 / MediaQuery.devicePixelRatioOf(context)).clamp(
      0.33,
      0.6,
    );
    final bg = widget.active
        ? (isDark
              ? kTaskPurple.withValues(alpha: 0.26)
              : DunesColors.brandPurpleSoft)
        : widget.emphasized
        ? (isDark
              ? kTaskPurple.withValues(alpha: 0.14)
              : const Color(0xFFF3EEFA))
        : _hovered
        ? (isDark
              ? Colors.white.withValues(alpha: 0.11)
              : const Color(0xFFEBE8F4))
        : (isDark
              ? Colors.white.withValues(alpha: 0.06)
              : const Color(0xFFF2F2F7));
    final borderColor = widget.active
        ? kTaskPurple.withValues(alpha: isDark ? 0.55 : 0.35)
        : _hovered
        ? kTaskPurple.withValues(alpha: 0.25)
        : Colors.transparent;
    final fg = widget.active || widget.emphasized
        ? DunesColors.resolve(context, kTaskPurple)
        : DunesColors.resolve(context, DunesColors.text);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed && !disableAnim ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: widget.height,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(widget.radius),
              border: Border.all(color: borderColor, width: hairline),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: widget.active ? FontWeight.w700 : FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 通用触感卡片/胶囊容器（悬停边框提亮 + 轻弹按压）
class _TaskInteractiveSurface extends StatefulWidget {
  const _TaskInteractiveSurface({
    required this.borderRadius,
    required this.baseColor,
    required this.hoverColor,
    required this.borderColor,
    required this.hoverBorderColor,
    required this.borderWidth,
    required this.onTap,
    required this.child,
  });

  final BorderRadius borderRadius;
  final Color baseColor;
  final Color hoverColor;
  final Color borderColor;
  final Color hoverBorderColor;
  final double borderWidth;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_TaskInteractiveSurface> createState() =>
      _TaskInteractiveSurfaceState();
}

class _TaskInteractiveSurfaceState extends State<_TaskInteractiveSurface> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed && !disableAnim ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: _hovered ? widget.hoverColor : widget.baseColor,
              borderRadius: widget.borderRadius,
              border: Border.all(
                color: _hovered ? widget.hoverBorderColor : widget.borderColor,
                width: widget.borderWidth,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
