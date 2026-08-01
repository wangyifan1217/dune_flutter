import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../shell/dunes_toast.dart';
import 'native_task_action_page.dart';
import 'native_task_detail_page.dart';
import 'native_task_form.dart';
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

  int _mineTotal = 0;
  int _mineActive = 0;
  int _mineDone = 0;
  int _pendingTotal = 0;

  /// mine | pending
  String _scope = 'mine';
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

  String get _apiScope =>
      _scope == 'pending' ? 'pending_approval' : 'mine';

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
          onPressed: () => _openCreate(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新建'),
          style: FilledButton.styleFrom(
            backgroundColor: kTaskPurple,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      final listFuture = _api.listTasksPage(
        scope: _apiScope,
        status: _status,
        priority: _priority,
        q: _search.text,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        page: 0,
        size: _pageSize,
      );
      final mineStatsFuture = _api.listTasksPage(scope: 'mine', page: 0, size: 1);
      final pendingStatsFuture =
          _api.listTasksPage(scope: 'pending_approval', page: 0, size: 1);
      final list = await listFuture;
      final mineStats = await mineStatsFuture;
      final pendingStats = await pendingStatsFuture;
      if (!mounted) return;
      setState(() {
        _items = list.items;
        _listPage = 0;
        _hasMore = list.hasMore;
        _mineTotal = mineStats.total;
        _mineActive = mineStats.active;
        _mineDone = mineStats.completed;
        _pendingTotal = pendingStats.total;
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
      if (_page == _TaskPage.detail &&
          _detailId != null &&
          _detailId != id) {
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

  void _backFromAction() {
    setState(() {
      _pageNavBack = true;
      _page = _TaskPage.detail;
      _actionTask = null;
      _actionMode = null;
    });
    _publishChrome();
  }

  void _doneAction() {
    setState(() {
      _pageNavBack = true;
      _page = _TaskPage.detail;
      _actionTask = null;
      _actionMode = null;
    });
    _publishChrome();
  }

  Future<void> _openCreate({int? parentId, TaskItem? parentTask}) async {
    final created = await openTaskEditor(
      context,
      session: widget.session,
      parentTaskId: parentId,
      parentTask: parentTask ??
          (parentId != null && _detailParentCache?.id == parentId
              ? _detailParentCache
              : null),
    );
    if (created == null || !mounted) return;
    showDunesCenterToast(
      context,
      parentId == null ? '主任务已创建' : '子任务已创建',
    );
    await _reload();
    if (parentId != null && mounted) {
      _openDetail(parentId);
    }
  }

  int get _totalCount => _mineTotal;
  int get _activeCount => _mineActive;
  int get _pendingCount => _pendingTotal;
  int get _doneCount => _mineDone;

  String get _scopeLabel => switch (_scope) {
        'pending' => '待我审核',
        _ => '我的任务',
      };

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
      _dateFrom = DateTime(picked.start.year, picked.start.month, picked.start.day);
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
      color: active ? kTaskPurple.withValues(alpha: 0.08) : const Color(0xFFF5F6F8),
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

  String get _priorityLabel => switch (_priority) {
        'low' => '低',
        'medium' => '中',
        'high' => '高',
        'urgent' => '紧急',
        _ => '全部优先级',
      };

  Key get _pageKey => switch (_page) {
        _TaskPage.list => const ValueKey('task-list'),
        _TaskPage.detail => ValueKey('task-detail-$_detailId'),
        _TaskPage.action =>
          ValueKey('task-action-$_actionMode-${_actionTask?.id}'),
      };

  Widget _pageBody() {
    return switch (_page) {
      _TaskPage.action => NativeTaskActionView(
          session: widget.session,
          task: _actionTask!,
          mode: _actionMode!,
          onBack: _backFromAction,
          onDone: _doneAction,
        ),
      _TaskPage.detail => NativeTaskDetailView(
          session: widget.session,
          taskId: _detailId!,
          onBack: _backFromDetail,
          onAddSubtask: () => _openCreate(
            parentId: _detailId,
            parentTask: _detailParentCache?.id == _detailId
                ? _detailParentCache
                : null,
          ),
          onOpenTask: _openDetail,
          onOpenProgress: (t) => _openAction(t, TaskActionMode.progress),
          onOpenEvaluate: (t) => _openAction(t, TaskActionMode.evaluate),
          onTaskLoaded: (t) {
            if (t.isMain) _detailParentCache = t;
          },
        ),
      _TaskPage.list => _buildList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final isBack = _pageNavBack;
    final child = KeyedSubtree(
      key: _pageKey,
      child: _pageBody(),
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
          position: Tween<Offset>(begin: begin, end: Offset.zero)
              .animate(animation),
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
                    const Text(
                      '主任务可自建 · 子任务仅分给自己或下级 · 自建子任务需上级审核',
                      style: TextStyle(fontSize: 13, color: DunesColors.text3, height: 1.3),
                    ),
                    const SizedBox(height: 12),
                    TaskSummaryRow(
                      total: _totalCount,
                      active: _activeCount,
                      pending: _pendingCount,
                      done: _doneCount,
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

  Widget _buildToolbar() {
    const scopeItems = <(String, String)>[
      ('mine', '我的任务'),
      ('pending', '待我审核'),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final wrap = c.maxWidth < 860;
          final search = Expanded(
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: '搜索标题 / 负责人 / 分类',
                hintStyle: const TextStyle(color: DunesColors.text3, fontSize: 13),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF5F6F8),
                prefixIcon: const Icon(Icons.search, size: 20, color: DunesColors.text3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          );
          final filters = [
            _dateRangeChip(),
            TaskFilterChipDropdown<String>(
              value: _scope,
              label: _scopeLabel,
              items: scopeItems,
              onChanged: (v) {
                setState(() => _scope = v);
                unawaited(_reload());
              },
              minMenuWidth: 160,
            ),
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
            TaskFilterChipDropdown<String?>(
              value: _priority,
              label: _priorityLabel,
              items: const [
                (null, '全部优先级'),
                ('low', '低'),
                ('medium', '中'),
                ('high', '高'),
                ('urgent', '紧急'),
              ],
              onChanged: (v) {
                setState(() => _priority = v);
                unawaited(_reload());
              },
              minMenuWidth: 160,
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded, color: DunesColors.text2),
            ),
          ];

          if (wrap) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [search]),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: filters,
                ),
              ],
            );
          }

          return Row(
            children: [
              search,
              const SizedBox(width: 10),
              for (final w in filters) ...[
                const SizedBox(width: 8),
                w,
              ],
            ],
          );
        },
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
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
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
    final hasFilters = (_status != null && _status!.isNotEmpty) ||
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
                    child: const Icon(Icons.task_alt_outlined, color: kTaskPurple, size: 30),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _scope == 'pending' ? '暂无待审核任务' : '还没有任务',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: DunesColors.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _scope == 'pending' ? '下级自建的子任务会显示在这里' : '创建第一条主任务，开始拆解与跟进',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: DunesColors.text3, height: 1.4),
                  ),
                  if (_scope == 'mine') ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => _openCreate(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新建第一条'),
                      style: FilledButton.styleFrom(
                        backgroundColor: kTaskPurple,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
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
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            // APP/PC 统一一行三个，纵向滑动浏览。
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 10,
            mainAxisExtent: 148,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final t = items[i];
              return TaskNameCard(
                session: widget.session,
                task: t,
                onTap: () => _openDetail(t.id),
              );
            },
            childCount: items.length,
          ),
        ),
      ),
    ];
  }
}
