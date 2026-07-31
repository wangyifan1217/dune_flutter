import 'package:flutter/material.dart';

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
    this.showBackButton = true,
    this.onBack,
    this.onConversationRead,
  });

  final AuthSession session;
  final NativeConversation conversationHint;
  final bool showBackButton;
  final VoidCallback? onBack;
  final ValueChanged<int>? onConversationRead;

  @override
  State<NativeTaskAssistantPage> createState() =>
      _NativeTaskAssistantPageState();
}

class _NativeTaskAssistantPageState extends State<NativeTaskAssistantPage> {
  late final ConversationService _service = ConversationService(session: widget.session);
  late final TaskApi _taskApi = TaskApi(widget.session);
  final List<NativeChatMessage> _messages = [];
  List<TaskItem> _tasks = const [];
  bool _loading = true;
  bool _showTasks = false;
  String? _error;

  int get _convId => widget.conversationHint.id;

  @override
  void initState() {
    super.initState();
    _loadMessages();
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
      _loading = true;
      _error = null;
    });
    try {
      final tasks = await _taskApi.listTasks(scope: 'mine');
      if (mounted) setState(() => _tasks = tasks);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TaskItem> get _activeSubtasks => _tasks
      .where((t) =>
          !t.isMain &&
          t.ownerUserId == widget.session.userId &&
          (t.status == 'active' || t.status == 'in_progress'))
      .toList(growable: false);

  String _parentTitle(TaskItem task) {
    if (task.parentId == null) return '';
    for (final item in _tasks) {
      if (item.id == task.parentId) return item.title;
    }
    return '主任务 #${task.parentId}';
  }

  @override
  Widget build(BuildContext context) {
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
                  ? () => setState(() {
                        _showTasks = false;
                        _error = null;
                      })
                  : (widget.onBack ?? () => Navigator.maybePop(context)),
              showBackButton: widget.showBackButton,
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
      return Center(child: TextButton(onPressed: _loadMessages, child: Text('重试：$_error')));
    }
    if (_messages.isEmpty) {
      return const Center(
        child: Text('子任务分配后会在这里提醒你', style: TextStyle(color: DunesColors.text3)),
      );
    }
    return ListView.builder(
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
      return Center(child: TextButton(onPressed: _openActiveTasks, child: Text('重试：$_error')));
    }
    final tasks = _activeSubtasks;
    if (tasks.isEmpty) {
      return const Center(
        child: Text('暂无你负责的进行中子任务', style: TextStyle(color: DunesColors.text3)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _ActiveSubtaskCard(
          task: task,
          parentTitle: _parentTitle(task),
          canUpdate: task.ownerUserId == widget.session.userId,
          onUpdate: () async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => NativeTaskActionView(
                  session: widget.session,
                  task: task,
                  mode: TaskActionMode.progress,
                  onBack: () => Navigator.pop(context),
                  onDone: () => Navigator.pop(context),
                ),
              ),
            );
            if (mounted) _openActiveTasks();
          },
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
      child: Icon(Icons.assignment_turned_in_outlined, color: Colors.white, size: size * .42),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          if (parentTitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('主任务：$parentTitle', style: const TextStyle(fontSize: 12, color: DunesColors.text3)),
          ],
          const SizedBox(height: 10),
          TaskProgressBar(progressPct: task.progressPct, overdue: task.overdue),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: canUpdate ? onUpdate : null,
              icon: const Icon(Icons.tune, size: 17),
              label: const Text('更新进度'),
            ),
          ),
        ],
      ),
    );
  }
}
