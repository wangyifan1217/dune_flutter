import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/navigation/navigation_controller.dart';
import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../chat/chat_widgets.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../tasks/native_task_action_page.dart';
import '../tasks/task_api.dart';
import '../tasks/task_models.dart';
import '../tasks/task_widgets.dart';

/// 任务助手：只读通知流，入口仅展示当前用户负责的进行中子任务。
class NativeTaskAssistantPage extends StatefulWidget {
  const NativeTaskAssistantPage({
    super.key,
    required this.session,
    required this.conversationHint,
    this.navigation,
    this.showBackButton = true,
    this.onBack,
    this.onConversationRead,
  });

  final AuthSession session;
  final NativeConversation conversationHint;
  final DunesNavigationController? navigation;
  final bool showBackButton;
  final VoidCallback? onBack;
  final ValueChanged<int>? onConversationRead;

  @override
  State<NativeTaskAssistantPage> createState() =>
      _NativeTaskAssistantPageState();
}

class _NativeTaskAssistantPageState extends State<NativeTaskAssistantPage> {
  late final ConversationService _service =
      ConversationService(session: widget.session);
  late final TaskApi _taskApi = TaskApi(widget.session);
  final List<NativeChatMessage> _messages = [];
  final Map<int, String> _parentTitleById = {};
  List<TaskItem> _tasks = const [];
  bool _loading = true;
  bool _showTasks = false;
  TaskItem? _actionTask;
  String? _error;

  int get _convId => widget.conversationHint.id;

  @override
  void initState() {
    super.initState();
    _syncBackInterceptor();
    _loadMessages();
  }

  @override
  void dispose() {
    _clearBackInterceptor();
    super.dispose();
  }

  bool get _hasInternalBack => _actionTask != null || _showTasks;

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

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var id = _convId;
      if (id <= 0) {
        id = (await _service.ensureTaskAssistantSession()).id;
      }
      if (id <= 0) throw Exception('任务助手会话无效');
      final messages = await _service.fetchMessages(id);
      await _service.markConversationRead(id);
      widget.onConversationRead?.call(id);
      if (!mounted) return;
      setState(() => _messages
        ..clear()
        ..addAll(messages));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
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
        .where((t) =>
            !t.isMain &&
            t.ownerUserId == widget.session.userId &&
            (t.status == 'active' || t.status == 'in_progress'))
        .toList(growable: false);
  }

  Future<List<TaskItem>> _loadOwnedActiveSubtasksViaDetails({
    List<TaskItem>? seedMains,
  }) async {
    final mains = seedMains ??
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
      .where((t) =>
          !t.isMain &&
          t.ownerUserId == widget.session.userId &&
          (t.status == 'active' || t.status == 'in_progress'))
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

  void _openProgress(TaskItem task) {
    setState(() => _actionTask = task);
    _syncBackInterceptor();
  }

  void _closeProgress({required bool refresh}) {
    setState(() => _actionTask = null);
    _syncBackInterceptor();
    if (refresh) unawaited(_openActiveTasks());
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
            mode: TaskActionMode.progress,
            accentColor: const Color(0xFF2F8F7E),
            backgroundColor: DunesColors.bgApp,
            onBack: () => _closeProgress(refresh: false),
            onDone: () => _closeProgress(refresh: true),
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
            ),
            Expanded(child: _showTasks ? _buildTasks() : _buildMessages()),
            if (!_showTasks)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openActiveTasks,
                      icon: const Icon(Icons.playlist_add_check_circle_outlined),
                      label: const Text('进行中的任务'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2F8F7E),
                        padding: const EdgeInsets.symmetric(vertical: 13),
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

  Widget _buildMessages() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: TextButton(
          onPressed: _loadMessages,
          child: Text('重试：$_error'),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          '子任务分配后会在这里提醒你',
          style: TextStyle(color: DunesColors.text3),
        ),
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final m = _messages[index];
        final payload = m.payload ?? const <String, dynamic>{};
        final title = (payload['taskTitle'] ?? '').toString();
        final parent = (payload['parentTitle'] ?? '').toString();
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
              if (title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _TaskAssignmentCard(title: title, parentTitle: parent),
                ),
            ],
          ),
        );
      },
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
        child: Text(
          '暂无你负责的进行中子任务',
          style: TextStyle(color: DunesColors.text3),
        ),
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
  const _TaskAssignmentCard({required this.title, required this.parentTitle});
  final String title;
  final String parentTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5F3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        parentTitle.isEmpty ? title : '$title\n主任务：$parentTitle',
        style: const TextStyle(fontSize: 12, height: 1.4),
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
