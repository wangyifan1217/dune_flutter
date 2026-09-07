import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../chat/assistant_transcript_support.dart';
import '../chat/chat_widgets.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_realtime_hub.dart';
import '../conversation/conversation_realtime_service.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../desktop/windows_desktop_tray.dart';
import '../shell/dunes_toast.dart';
import '../tasks/native_task_action_page.dart';
import '../tasks/native_task_detail_page.dart';
import '../tasks/task_api.dart';
import '../tasks/task_link_models.dart';
import '../tasks/task_models.dart';
import '../tasks/task_widgets.dart';
import 'meeting_suggestion_im_card.dart';

/// 任务助手：只读通知流，入口仅展示当前用户负责的进行中子任务。
class NativeTaskAssistantPage extends StatefulWidget {
  const NativeTaskAssistantPage({
    super.key,
    required this.session,
    required this.conversationHint,
    this.navigation,
    this.showBackButton = true,
    this.autoMarkRead = true,
    this.onBack,
    this.onConversationRead,
  });

  final AuthSession session;
  final NativeConversation conversationHint;
  final DunesNavigationController? navigation;
  final bool showBackButton;
  final bool autoMarkRead;
  final VoidCallback? onBack;
  final ValueChanged<int>? onConversationRead;

  @override
  State<NativeTaskAssistantPage> createState() =>
      _NativeTaskAssistantPageState();
}

class _NativeTaskAssistantPageState extends State<NativeTaskAssistantPage> {
  late final ConversationService _service = ConversationService(
    session: widget.session,
  );
  late final TaskApi _taskApi = TaskApi(widget.session);
  final List<NativeChatMessage> _messages = [];
  final Map<int, String> _parentTitleById = {};
  final ScrollController _scroll = ScrollController();
  List<TaskItem> _tasks = const [];
  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = false;
  bool _awayFromLatest = false;
  bool _showTasks = false;
  bool _clearing = false;
  TaskItem? _actionTask;
  TaskActionMode _actionMode = TaskActionMode.progress;
  int? _detailTaskId;
  int _detailReloadTick = 0;
  int _resolvedConvId = 0;
  String? _error;
  StreamSubscription<ConversationRealtimeEvent>? _rtSub;
  Timer? _rtDebounce;

  int get _convId => widget.conversationHint.id;

  @override
  void initState() {
    super.initState();
    _syncBackInterceptor();
    _scroll.addListener(_onScroll);
    _loadMessages();
    // 页面常驻（尤其 PC 双栏）时新通知实时进屏，不依赖重新打开
    final realtime = ConversationRealtimeHub.instance.of(widget.session);
    unawaited(realtime.connect());
    _rtSub = realtime.events.listen(_onRealtime);
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _rtDebounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _clearBackInterceptor();
    super.dispose();
  }

  @override
  void didUpdateWidget(NativeTaskAssistantPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.autoMarkRead && widget.autoMarkRead) {
      unawaited(_markReadIfViewing());
    }
  }

  void _onRealtime(ConversationRealtimeEvent event) {
    if (_resolvedConvId <= 0 || event.conversationId != _resolvedConvId) {
      return;
    }
    if (event.type != 'message' && event.type != 'conversation_updated') {
      return;
    }
    _rtDebounce?.cancel();
    _rtDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_showTasks) unawaited(_loadMessages(silent: true));
    });
  }

  bool get _hasInternalBack =>
      _actionTask != null || _detailTaskId != null || _showTasks;

  void _installBackInterceptor() {
    final nav = widget.navigation;
    if (nav == null) return;
    nav.canBackInterceptor = _canHandleInternalBack;
    nav.backInterceptor = _handleInternalBack;
  }

  void _clearBackInterceptor() {
    final nav = widget.navigation;
    if (nav == null) return;
    if (nav.canBackInterceptor == _canHandleInternalBack) {
      nav.canBackInterceptor = null;
    }
    if (nav.backInterceptor == _handleInternalBack) {
      nav.backInterceptor = null;
    }
  }

  void _syncBackInterceptor() {
    if (_hasInternalBack) {
      _installBackInterceptor();
    } else {
      _clearBackInterceptor();
    }
  }

  bool _canHandleInternalBack() => _hasInternalBack;

  bool _handleInternalBack() {
    if (_actionTask != null) {
      _closeProgress(refresh: false);
      return true;
    }
    if (_detailTaskId != null) {
      _closeTaskDetail();
      return true;
    }
    if (_showTasks) {
      setState(() {
        _showTasks = false;
        _error = null;
        _loading = false;
      });
      _syncBackInterceptor();
      return true;
    }
    return false;
  }

  void _openTaskDetail(int taskId) {
    if (taskId <= 0) return;
    setState(() {
      _detailTaskId = taskId;
      _detailReloadTick++;
    });
    _syncBackInterceptor();
  }

  void _closeTaskDetail() {
    setState(() => _detailTaskId = null);
    _syncBackInterceptor();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      var id = _convId;
      if (id <= 0) {
        id = (await _service.ensureTaskAssistantSession()).id;
      }
      if (id <= 0) throw Exception('任务助手会话无效');
      _resolvedConvId = id;
      unawaited(
        ConversationRealtimeHub.instance
            .of(widget.session)
            .ensureConversationSubscription(id),
      );
      final messages = await _service.fetchMessagePage(id);
      await _markReadIfViewing();
      if (!mounted) return;
      setState(() {
        final next = silent
            ? mergeLatestAssistantMessages(
                current: List<NativeChatMessage>.from(_messages),
                latest: messages.items,
              )
            : messages.items;
        _messages
          ..clear()
          ..addAll(next);
        if (!silent) {
          _hasMore = messages.hasMore;
          _loading = false;
        }
      });
      if (!silent) {
        _scrollToLatestOnEnter();
      } else if (!_awayFromLatest) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpBottom());
      }
    } catch (e) {
      if (!silent && mounted) setState(() => _error = '$e');
    } finally {
      if (!silent && mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markReadIfViewing() async {
    if (!widget.autoMarkRead || windowsTrayIsWindowInactive()) return;
    final id = _resolvedConvId > 0 ? _resolvedConvId : _convId;
    if (id <= 0) return;
    await _service.markConversationRead(id);
    widget.onConversationRead?.call(id);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final away = assistantIsAwayFromLatest(pos);
    if (away != _awayFromLatest && mounted) {
      setState(() => _awayFromLatest = away);
    }
    if (assistantShouldLoadOlder(
      hasMore: _hasMore,
      loadingOlder: _loadingOlder,
      pos: pos,
    )) {
      unawaited(_loadOlder());
    }
  }

  void _scrollToLatestOnEnter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpBottom();
      Future<void>.delayed(const Duration(milliseconds: 80), _jumpBottom);
      Future<void>.delayed(const Duration(milliseconds: 240), _jumpBottom);
    });
  }

  void _jumpBottom({bool animate = false}) {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (animate) {
      _scroll.animateTo(
        max,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(max);
    }
    if (_awayFromLatest && mounted) {
      setState(() => _awayFromLatest = false);
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _messages.isEmpty) return;
    final convId = _resolvedConvId > 0 ? _resolvedConvId : _convId;
    if (convId <= 0) return;
    setState(() => _loadingOlder = true);
    final firstId = _messages.first.id;
    final oldMax = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
    final oldPixels = _scroll.hasClients ? _scroll.position.pixels : 0.0;
    try {
      final page = await _service.fetchMessagePage(convId, before: firstId);
      if (!mounted) return;
      final current = List<NativeChatMessage>.from(_messages);
      setState(() {
        _messages
          ..clear()
          ..addAll(
            mergeOlderAssistantMessages(current: current, older: page.items),
          );
        _hasMore = page.hasMore;
        _loadingOlder = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        _scroll.jumpTo(
          assistantOlderScrollRestore(
            oldPixels: oldPixels,
            oldMax: oldMax,
            newMax: _scroll.position.maxScrollExtent,
          ),
        );
      });
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// 右上角清空：仅清掉自己可见的通知历史，任务本身不受影响。
  Future<void> _clearHistory() async {
    if (_clearing) return;
    if (_resolvedConvId <= 0) {
      try {
        _resolvedConvId = (await _service.ensureTaskAssistantSession()).id;
      } catch (_) {}
      if (_resolvedConvId <= 0 || !mounted) {
        if (mounted) showDunesCenterToast(context, '会话未就绪，请稍后再试');
        return;
      }
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空通知记录'),
        content: const Text(
          '将清空任务助手里的历史通知（仅自己不可见），任务与进展数据不受影响。确定清空吗？',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE35D6A),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await _service.clearConversationHistory(_resolvedConvId);
      if (!mounted) return;
      setState(() => _messages.clear());
      showDunesCenterToast(context, '已清空通知记录');
    } catch (e) {
      if (mounted) showDunesCenterToast(context, '$e');
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _openActiveTasks() async {
    setState(() {
      _showTasks = true;
      _actionTask = null;
      _loading = true;
      _error = null;
    });
    _syncBackInterceptor();
    try {
      final tasks = await _loadOwnedActiveSubtasks();
      if (mounted) setState(() => _tasks = tasks);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 优先走 `owned_subtasks`；旧后端会把它当 mine 返回主任务，再回退按详情拆子任务。
  Future<List<TaskItem>> _loadOwnedActiveSubtasks() async {
    final page = await _taskApi.listTasksPage(
      scope: 'owned_subtasks',
      page: 0,
      size: 100,
    );
    final items = page.items;
    final looksLikeLegacyMains =
        items.isNotEmpty && items.every((t) => t.isMain);
    if (items.isEmpty || looksLikeLegacyMains) {
      return _loadOwnedActiveSubtasksViaDetails(
        seedMains: looksLikeLegacyMains ? items : null,
      );
    }
    return items
        .where(
          (t) =>
              !t.isMain &&
              t.ownerUserId == widget.session.userId &&
              (t.status == 'active' || t.status == 'in_progress'),
        )
        .toList(growable: false);
  }

  Future<List<TaskItem>> _loadOwnedActiveSubtasksViaDetails({
    List<TaskItem>? seedMains,
  }) async {
    final mains =
        seedMains ??
        await _taskApi.listTasks(scope: 'mine', size: 100, maxPages: 3);
    final out = <TaskItem>[];
    final parentTitles = <int, String>{};
    for (final m in mains) {
      parentTitles[m.id] = m.title;
      if (m.subtaskCount <= 0) continue;
      final detail = await _taskApi.getDetail(m.id);
      for (final s in detail.subtasks) {
        if (s.ownerUserId == widget.session.userId &&
            (s.status == 'active' || s.status == 'in_progress')) {
          out.add(s);
        }
      }
    }
    _parentTitleById
      ..clear()
      ..addAll(parentTitles);
    return out;
  }

  List<TaskItem> get _activeSubtasks => _tasks
      .where(
        (t) =>
            !t.isMain &&
            t.ownerUserId == widget.session.userId &&
            (t.status == 'active' || t.status == 'in_progress'),
      )
      .toList(growable: false);

  String _parentTitle(TaskItem task) {
    final fromApi = task.parentTitle.trim();
    if (fromApi.isNotEmpty) return fromApi;
    final pid = task.parentId;
    if (pid == null) return '';
    final cached = _parentTitleById[pid];
    if (cached != null && cached.trim().isNotEmpty) return cached;
    for (final item in _tasks) {
      if (item.id == pid) return item.title;
    }
    return '主任务 #$pid';
  }

  void _openProgress(
    TaskItem task, {
    TaskActionMode mode = TaskActionMode.progress,
  }) {
    setState(() {
      _actionTask = task;
      _actionMode = mode;
    });
    _syncBackInterceptor();
  }

  void _closeProgress({required bool refresh}) {
    setState(() {
      _actionTask = null;
      if (refresh && _detailTaskId != null) {
        // 从内嵌任务详情发起的操作：完成后强制详情重新拉取
        _detailReloadTick++;
      }
    });
    _syncBackInterceptor();
    if (refresh && _detailTaskId == null && _showTasks) {
      unawaited(_openActiveTasks());
    }
  }

  void _backFromTasks() {
    setState(() {
      _showTasks = false;
      _error = null;
      _loading = false;
    });
    _syncBackInterceptor();
  }

  @override
  Widget build(BuildContext context) {
    final action = _actionTask;
    if (action != null) {
      // 嵌在任务助手右侧栏内，避免 Navigator.push 全屏/双栏撑破布局。
      // APP 需 SafeArea，否则状态栏会压住「返回 / 调整进度」顶栏。
      return Scaffold(
        backgroundColor: DunesColors.bgApp,
        body: SafeArea(
          bottom: false,
          child: NativeTaskActionView(
            session: widget.session,
            task: action,
            mode: _actionMode,
            accentColor: const Color(0xFF2F8F7E),
            backgroundColor: DunesColors.bgApp,
            onBack: () => _closeProgress(refresh: false),
            onDone: () => _closeProgress(refresh: true),
          ),
        ),
      );
    }

    final detailTaskId = _detailTaskId;
    if (detailTaskId != null) {
      // 点通知卡片打开的内嵌任务详情（进度/评价复用上面的三级页）。
      return Scaffold(
        backgroundColor: DunesColors.bgApp,
        body: SafeArea(
          bottom: false,
          child: NativeTaskDetailView(
            key: ValueKey('ta-task-$detailTaskId-$_detailReloadTick'),
            session: widget.session,
            taskId: detailTaskId,
            onBack: _closeTaskDetail,
            onOpenTask: _openTaskDetail,
            onOpenProgress: (t) => _openProgress(t),
            onOpenEvaluate: (t) =>
                _openProgress(t, mode: TaskActionMode.evaluate),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ChatConvHeader(
              title: _showTasks ? '进行中的任务' : '任务助手',
              subtitle: _loading ? '加载中…' : '',
              onBack: _showTasks
                  ? _backFromTasks
                  : (widget.onBack ?? () => Navigator.maybePop(context)),
              // 双栏主会话可隐藏返回；进入「进行中的任务」子页时必须能返回消息流。
              showBackButton: _showTasks || widget.showBackButton,
              leadingAvatar: const TaskAssistantAvatar(size: 45),
              actions: [
                if (!_showTasks)
                  IconButton(
                    tooltip: '清空通知记录',
                    onPressed: _clearing ? null : _clearHistory,
                    icon: _clearing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.delete_sweep_outlined,
                            size: 22,
                            color: DunesColors.text2,
                          ),
                  ),
              ],
            ),
            Expanded(child: _showTasks ? _buildTasks() : _buildMessages()),
            // 「进行中的任务」入口暂时下线（产品要求先隐藏，代码保留随时可恢复）。
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: TextButton(onPressed: _loadMessages, child: Text('重试：$_error')),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          '任务相关的信息会在这里通知你',
          style: TextStyle(color: DunesColors.text3),
        ),
      );
    }
    return Stack(
      children: [
        ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: _messages.length + (_loadingOlder ? 1 : 0),
          itemBuilder: (context, index) {
            if (_loadingOlder && index == 0) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final m = _messages[_loadingOlder ? index - 1 : index];
            final payload = m.payload ?? const <String, dynamic>{};
            final noticeType = (payload['type'] ?? '').toString();
            final title = (payload['taskTitle'] ?? '').toString();
            final parent = (payload['parentTitle'] ?? '').toString();
            final taskId = (payload['taskId'] as num?)?.toInt() ?? 0;
            final meetingId = (payload['meetingId'] as num?)?.toInt() ?? 0;
            final meetingTitle = (payload['meetingTitle'] ?? title).toString();
            final snapshot = (payload['suggestions'] as List? ?? const [])
                .whereType<Map>()
                .map(
                  (e) => MeetingTaskSuggestion.fromJson(
                    Map<String, dynamic>.from(e),
                  ),
                )
                .toList(growable: false);
            final isSug = noticeType == 'meetingTaskSuggestions' && meetingId > 0;
            return ChatMessageRow(
              message: m,
              mine: false,
              showSenderMeta: true,
              readLabel: null,
              timeLabel: InboxFormat.formatTime(m.createdAt, withClock: true),
              avatar: const TaskAssistantAvatar(size: 45),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ChatTextBubble(text: m.bodyText, mine: false),
                  if (isSug)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: MeetingSuggestionImCard(
                        session: widget.session,
                        meetingId: meetingId,
                        meetingTitle: meetingTitle,
                        snapshot: snapshot,
                      ),
                    )
                  else if (title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _TaskAssignmentCard(
                        title: title,
                        parentTitle: parent,
                        onTap: taskId > 0 ? () => _openTaskDetail(taskId) : null,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        if (_awayFromLatest)
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: AssistantBackToLatestChip(
              onTap: () => _jumpBottom(animate: true),
            ),
          ),
      ],
    );
  }

  Widget _buildTasks() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: TextButton(
          onPressed: _openActiveTasks,
          child: Text('重试：$_error'),
        ),
      );
    }
    final tasks = _activeSubtasks;
    if (tasks.isEmpty) {
      return const Center(
        child: Text('暂无你负责的进行中子任务', style: TextStyle(color: DunesColors.text3)),
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _ActiveSubtaskCard(
          task: task,
          parentTitle: _parentTitle(task),
          canUpdate: task.ownerUserId == widget.session.userId,
          onUpdate: () => _openProgress(task),
        );
      },
    );
  }
}

class TaskAssistantAvatar extends StatelessWidget {
  const TaskAssistantAvatar({super.key, this.size = 45});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F8F7E), Color(0xFF5EAEDE)],
        ),
      ),
      child: Icon(
        Icons.assignment_turned_in_outlined,
        color: Colors.white,
        size: size * .42,
      ),
    );
  }
}

class _TaskAssignmentCard extends StatelessWidget {
  const _TaskAssignmentCard({
    required this.title,
    required this.parentTitle,
    this.onTap,
  });
  final String title;
  final String parentTitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAF5F3),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  parentTitle.isEmpty ? title : '$title\n主任务：$parentTitle',
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Color(0xFF2F8F7E),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveSubtaskCard extends StatelessWidget {
  const _ActiveSubtaskCard({
    required this.task,
    required this.parentTitle,
    required this.canUpdate,
    required this.onUpdate,
  });
  final TaskItem task;
  final String parentTitle;
  final bool canUpdate;
  final VoidCallback onUpdate;

  String? get _dateRange {
    String fmt(DateTime d) {
      final local = d.toLocal();
      return '${local.month}/${local.day}';
    }

    if (task.startAt == null && task.dueAt == null) return null;
    if (task.startAt != null && task.dueAt != null) {
      return '${fmt(task.startAt!)} - ${fmt(task.dueAt!)}';
    }
    if (task.startAt != null) return '起 ${fmt(task.startAt!)}';
    return '止 ${fmt(task.dueAt!)}';
  }

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      '优先级 ${taskPriorityLabel(task.priority)}',
      taskStatusLabel(task.status),
      ?_dateRange,
      if (task.ownerName.isNotEmpty) '负责人 ${task.ownerName}',
      if (task.overdue) '已逾期',
    ];
    final desc = task.description.trim();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8EAED)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              task.title.trim().isEmpty ? '未命名子任务' : task.title.trim(),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            if (parentTitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '主任务：$parentTitle',
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              meta.join(' · '),
              style: const TextStyle(
                fontSize: 12,
                color: DunesColors.text2,
                height: 1.35,
              ),
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                desc,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: DunesColors.text3,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 10),
            TaskProgressBar(
              progressPct: task.progressPct,
              overdue: task.overdue,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: canUpdate ? onUpdate : null,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2F8F7E),
                ),
                icon: const Icon(Icons.tune, size: 17),
                label: const Text('更新进度'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
