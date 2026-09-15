import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'task_models.dart';
import 'task_widgets.dart';

/// 新建任务提交前的二次确认，展示标题和已选周期。
Future<bool> confirmCreateTask(
  BuildContext context, {
  required String title,
  DateTime? startAt,
  DateTime? dueAt,
  String kind = '任务',
  String? message,
}) async {
  final range = taskCreateRangeLabel(startAt, dueAt);
  final ok = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('确认创建$kind'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message ?? '确认创建「$title」？'),
          if (range != null) ...[
            const SizedBox(height: 8),
            Text(
              '周期：$range',
              style: const TextStyle(color: DunesColors.text2, height: 1.4),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('task-create-confirm-ok'),
          style: FilledButton.styleFrom(backgroundColor: kTaskPurple),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确认创建'),
        ),
      ],
    ),
  );
  return ok == true;
}
