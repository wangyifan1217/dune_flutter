import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import 'native_task_detail_page.dart';
import 'task_chat_share.dart';

Future<void> showTaskSharedDetailDialog({
  required BuildContext context,
  required AuthSession session,
  required TaskChatShare share,
}) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      final compact = size.width < 600;
      return Dialog(
        insetPadding: compact ? EdgeInsets.zero : const EdgeInsets.all(28),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 0 : 22),
        ),
        child: SizedBox(
          width: compact ? size.width : math.min(780, size.width - 56),
          height: compact ? size.height : math.min(900, size.height - 56),
          child: _TaskSharedDetailDialog(
            session: session,
            share: share,
            close: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      );
    },
  );
}

class _TaskSharedDetailDialog extends StatefulWidget {
  const _TaskSharedDetailDialog({
    required this.session,
    required this.share,
    required this.close,
  });

  final AuthSession session;
  final TaskChatShare share;
  final VoidCallback close;

  @override
  State<_TaskSharedDetailDialog> createState() =>
      _TaskSharedDetailDialogState();
}

class _TaskSharedDetailDialogState extends State<_TaskSharedDetailDialog> {
  late final List<int> _taskStack = [widget.share.taskId];

  void _openTask(int taskId) {
    if (taskId <= 0 || _taskStack.last == taskId) return;
    setState(() => _taskStack.add(taskId));
  }

  void _back() {
    if (_taskStack.length > 1) {
      setState(() => _taskStack.removeLast());
      return;
    }
    widget.close();
  }

  @override
  Widget build(BuildContext context) {
    final taskId = _taskStack.last;
    return ColoredBox(
      color: const Color(0xFFF5F4F8),
      child: NativeTaskDetailView(
        key: ValueKey('shared-task-${widget.share.shareRef}-$taskId'),
        session: widget.session,
        taskId: taskId,
        sharedShareRef: widget.share.shareRef,
        forceReadOnly: true,
        backLabel: _taskStack.length > 1 ? '上一级任务' : '返回会话',
        onBack: _back,
        onOpenTask: _openTask,
      ),
    );
  }
}
