import 'package:flutter/material.dart';

import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'task_api.dart';
import 'task_chat_share.dart';
import 'task_models.dart';

Future<void> forwardTaskToConversation({
  required BuildContext context,
  required AuthSession session,
  required TaskItem task,
  String? sourceShareRef,
}) async {
  if (task.id <= 0) {
    showDunesToast(context, '任务尚未保存，无法转发', kind: DunesToastKind.error);
    return;
  }
  final conversations = ConversationService(session: session);
  final conversationId = await showConversationPickerSheet(
    context: context,
    service: conversations,
    title: '转发到 IM',
  );
  if (conversationId == null || conversationId <= 0 || !context.mounted) return;

  final api = TaskApi(session);
  String? shareRef;
  Object? failure;
  try {
    await _withTaskForwardLoading(context, () async {
      try {
        shareRef = await api.createTaskShareGrant(
          taskId: task.id,
          conversationId: conversationId,
          sourceShareRef: sourceShareRef,
        );
        final sharedAt = DateTime.now();
        final share = TaskChatShare.fromTask(
          task,
          shareRef: shareRef!,
          sharedAt: sharedAt,
        );
        final sent = await conversations.sendText(
          conversationId,
          '[任务] ${task.title}',
          payload: share.toMessagePayload(),
        );
        if (sent == null || sent.id <= 0) {
          throw Exception('IM 没有返回消息记录');
        }
        await api.bindTaskShareMessage(shareRef!, sent.id);
      } catch (error) {
        failure = error;
      }
    });
  } catch (error) {
    failure ??= error;
  }
  if (failure != null && shareRef != null) {
    try {
      await api.revokeTaskShareGrant(shareRef!);
    } catch (_) {}
  }
  if (context.mounted) {
    if (failure == null) {
      showDunesToast(context, '任务名片已转发');
    } else {
      showDunesToast(
        context,
        '转发失败：${friendlyErrorText(failure, fallback: '请稍后重试')}',
        kind: DunesToastKind.error,
      );
    }
  }
}

Future<void> forwardTasksToConversation({
  required BuildContext context,
  required AuthSession session,
  required List<TaskItem> tasks,
  required String ownerName,
}) async {
  final uniqueTasks = <int, TaskItem>{
    for (final task in tasks)
      if (task.id > 0) task.id: task,
  }.values.toList(growable: false);
  if (uniqueTasks.length < 2) {
    showDunesToast(context, '至少需要两条已保存的任务才能合并转发');
    return;
  }

  final conversations = ConversationService(session: session);
  final conversationId = await showConversationPickerSheet(
    context: context,
    service: conversations,
    title: '合并转发到 IM',
  );
  if (conversationId == null || conversationId <= 0 || !context.mounted) return;

  final api = TaskApi(session);
  final createdRefs = <String>[];
  final boundRefs = <String>{};
  Object? failure;
  try {
    await _withTaskForwardLoading(context, () async {
      try {
        final sharedAt = DateTime.now();
        final grantResults = await _mapInBatches(uniqueTasks, (task) async {
          try {
            return (
              shareRef: await api.createTaskShareGrant(
                taskId: task.id,
                conversationId: conversationId,
              ),
              error: null,
            );
          } catch (error) {
            return (shareRef: null, error: error);
          }
        });
        createdRefs.addAll(
          grantResults.map((result) => result.shareRef).whereType<String>(),
        );
        final grantError = _firstTaskShareError(
          grantResults.map((result) => result.error),
        );
        if (grantError != null) throw grantError;

        final shares = <TaskChatShare>[];
        for (var index = 0; index < uniqueTasks.length; index++) {
          shares.add(
            TaskChatShare.fromTask(
              uniqueTasks[index],
              shareRef: grantResults[index].shareRef!,
              sharedAt: sharedAt,
            ),
          );
        }
        final safeOwnerName = ownerName.trim().isEmpty
            ? '同一负责人'
            : ownerName.trim();
        final bundle = TaskChatShareBundle(
          ownerName: safeOwnerName,
          sharedAt: sharedAt,
          shares: shares,
        );
        final sent = await conversations.sendText(
          conversationId,
          '[任务合集] $safeOwnerName 的主目标（${uniqueTasks.length}项）',
          payload: bundle.toMessagePayload(),
        );
        if (sent == null || sent.id <= 0) {
          throw Exception('IM 没有返回合并转发消息记录');
        }

        final bindResults = await _mapInBatches(createdRefs, (shareRef) async {
          try {
            await api.bindTaskShareMessage(shareRef, sent.id);
            return (shareRef: shareRef, error: null);
          } catch (error) {
            return (shareRef: shareRef, error: error);
          }
        });
        for (final result in bindResults) {
          if (result.error == null) boundRefs.add(result.shareRef);
        }
        final bindError = _firstTaskShareError(
          bindResults.map((result) => result.error),
        );
        if (bindError != null) throw bindError;
      } catch (error) {
        failure = error;
      }
    });
  } catch (error) {
    failure ??= error;
  }
  for (final shareRef in createdRefs.where(
    (ref) => failure != null && !boundRefs.contains(ref),
  )) {
    try {
      await api.revokeTaskShareGrant(shareRef);
    } catch (_) {}
  }
  if (!context.mounted) return;
  if (failure == null) {
    showDunesToast(context, '已合并转发 ${uniqueTasks.length} 个主目标');
  } else {
    showDunesToast(
      context,
      '合并转发失败：${friendlyErrorText(failure, fallback: '请稍后重试')}',
      kind: DunesToastKind.error,
    );
  }
}

Future<List<R>> _mapInBatches<T, R>(
  List<T> values,
  Future<R> Function(T value) transform, {
  int batchSize = 8,
}) async {
  final results = <R>[];
  for (var start = 0; start < values.length; start += batchSize) {
    final end = (start + batchSize).clamp(0, values.length);
    results.addAll(
      await Future.wait(values.sublist(start, end).map(transform)),
    );
  }
  return results;
}

Object? _firstTaskShareError(Iterable<Object?> errors) {
  for (final error in errors) {
    if (error != null) return error;
  }
  return null;
}

Future<void> _withTaskForwardLoading(
  BuildContext context,
  Future<void> Function() action,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final dialog = showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => const _TaskForwardLoadingDialog(),
  );
  try {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await action();
  } finally {
    if (navigator.mounted && navigator.canPop()) navigator.pop();
    await dialog;
  }
}

class _TaskForwardLoadingDialog extends StatelessWidget {
  const _TaskForwardLoadingDialog();

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Color(0xFF7054D8),
            ),
          ),
          SizedBox(width: 14),
          Flexible(
            child: Text(
              '正在转发任务，请稍候…',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ),
  );
}
