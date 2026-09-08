import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'native_task_action_page.dart';
import 'native_task_detail_page.dart';
import 'native_task_form.dart';
import 'native_task_quick_create.dart';
import 'task_api.dart';
import 'task_models.dart';
import 'task_widgets.dart';

enum _TaskPage { list, detail, action }

class TaskShellChrome {
  const TaskShellChrome({
    this.hideShellHeader = false,
    this.trailing,
    this.onBack,
  });

  final bool hideShellHeader;
  final Widget? trailing;
  final VoidCallback? onBack;
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

  /// actionable | initiated
  String _scope = 'actionable';
  String? _status;
  String? _priority;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _search.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishChrome());
    unawaited(_reload());
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
    if (_page == _TaskPage.detail || _page == _TaskPage.action) {
      widget.onChromeChanged?.call(
        TaskShellChrome(
          hideShellHeader: true,
          onBack: _page == _TaskPage.action ? _backFromAction : _backFromDetail,
        ),
      );
      return;
    }
    widget.onChromeChanged?.call(
      TaskShellChrome(
        trailing: FilledButton.icon(
          onPressed: () => _openQuickCreate(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新建'),
          style: FilledButton.styleFrom(
            backgroundColor: kTaskPurple,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = true;
      _listPage = 0;
    });
    try {
      final list = await _api.listTasksPage(
        scope: _apiScope,
        status: _status,
        priority: _priority,
        q: _search.text,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        page: 0,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = list.items;
        _listPage = 0;
        _hasMore = list.hasMore;
        _loading = false;
        _loadingMore = false;
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

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _listPage + 1;
      final result = await _api.listTasksPage(
        scope: _apiScope,
        status: _status,
        priority: _priority,
        q: _search.text,
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

  void _openAction(TaskItem task, TaskActionMode mode) {
    setState(() {
      _pageNavBack = false;
      _page = _TaskPage.action;
      _actionTask = task;
      _actionMode = mode;
    });
    _publishChrome();
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
      asGroup: _scope == 'initiated',
    );
    if (created == null || !mounted) return;
    showDunesCenterToast(
      context,
      _scope == 'initiated' ? '已创建一组事「${created.title}」' : '已创建「${created.title}」',
    );
    await _reload();
    if (_scope == 'initiated' && mounted) {
      _openDetail(created.id);
    }
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
    showDunesCenterToast(context, parentId == null ? '已创建' : '事项已添加');
    await _reload();
    if (parentId != null && mounted) {
      _openDetail(parentId);
    }
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
      helpText: '按任务起止时间筛选',
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
    'pending_approval' => '待审核',
    'completed' => '已完成',
    'rejected' => '已驳回',
    'active' => '进行中',
    _ => '全部状态',
  };

  Key get _pageKey => switch (_page) {
    _TaskPage.list => const ValueKey('task-list'),
    _TaskPage.detail => ValueKey('task-detail-$_detailId'),
    _TaskPage.action => ValueKey('task-action-$_actionMode-${_actionTask?.id}'),
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
      case _TaskPage.detail:
        final id = _detailId;
        if (id == null) return _buildList();
        return NativeTaskDetailView(
          session: widget.session,
          taskId: id,
          onBack: _backFromDetail,
          onAddSubtask: () => _openCreate(
            parentId: id,
            parentTask: _detailParentCache?.id == id ? _detailParentCache : null,
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
          position: Tween<Offset>(
            begin: begin,
            end: Offset.zero,
          ).animate(animation),
          child: transitionChild,
        );
      },
      child: child,
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
                        _tabChip('actionable', '待我处理'),
                        const SizedBox(width: 8),
                        _tabChip('initiated', '我发起的'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _scope == 'initiated'
                          ? '你发起的一组事，进度由下面的事项汇总'
                          : '只列出需要你动手的事',
                      style: const TextStyle(
                        fontSize: 13,
                        color: DunesColors.text3,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 12),
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
            setState(() => _scope = value);
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
                  ('pending_approval', '待审核'),
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
        ],
      ),
    );
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

    final items = _items;
    final hasFilters =
        (_status != null && _status!.isNotEmpty) ||
        (_priority != null && _priority!.isNotEmpty) ||
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
                    _scope == 'initiated' ? '还没有你发起的一组事' : '还没有待处理的事项',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _scope == 'initiated'
                        ? '点右上角新建一组事，再往里面加事项'
                        : '点右上角记一条要做的事，不必先建组',
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
                    label: const Text('新建'),
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
    final groupMode = _scope == 'initiated';
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
      out.add(const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          '今天要做',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: DunesColors.text3,
          ),
        ),
      ));
      for (final t in work) {
        out.add(TaskWorkbenchCard(
          task: t,
          onTap: () => _openDetail(t.id),
          onProgress: () => _openAction(t, TaskActionMode.progress),
        ));
        out.add(const SizedBox(height: 10));
      }
    }
    if (pending.isNotEmpty) {
      out.add(const Padding(
        padding: EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          '待我审核',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: DunesColors.text3,
          ),
        ),
      ));
      for (final t in pending) {
        out.add(TaskWorkbenchCard(
          task: t,
          onTap: () => _openDetail(t.id),
          onApprove: () => _decide(t, pass: true),
          onReject: () => _decide(t, pass: false),
        ));
        out.add(const SizedBox(height: 10));
      }
    }
    return out;
  }

  Future<void> _decide(TaskItem t, {required bool pass}) async {
    try {
      if (pass) {
        await _api.approve(t.id);
        if (!mounted) return;
        showDunesCenterToast(context, '已通过');
      } else {
        await _api.reject(t.id);
        if (!mounted) return;
        showDunesCenterToast(context, '已驳回');
      }
      await _reload();
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    }
  }
}
