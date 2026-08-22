import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../shell/dunes_toast.dart';
import 'xflow_models.dart';
import 'xflow_service.dart';

class TaskTodoConfirmCopy {
  const TaskTodoConfirmCopy({
    required this.title,
    required this.body,
    required this.okText,
    required this.needComment,
    this.danger = false,
  });

  final String title;
  final String body;
  final String okText;
  final bool needComment;
  final bool danger;
}

TaskTodoConfirmCopy taskTodoConfirmCopy(
  XflowProposalItem item, {
  bool? verifyPassed,
}) {
  if (verifyPassed == false) {
    return const TaskTodoConfirmCopy(
      title: '确认核验失败？',
      okText: '确认失败并退回补票',
      needComment: true,
      danger: true,
      body: '不会退回重审。确认后：\n'
          '1. 本条核验待办关闭\n'
          '2. 发起人收到「补传发票」，审批助手也会通知\n'
          '3. 补传完成后，核验人再次收到「核验发票」\n'
          '请填写失败原因，发起人可在单据详情评论中看到。',
    );
  }
  if (verifyPassed == true) {
    return const TaskTodoConfirmCopy(
      title: '确认核验通过？',
      okText: '确认通过',
      needComment: false,
      body: '请确认销方、购方、金额已核对一致。本条待办关闭，不重审。',
    );
  }
  final action = (item.primaryAction ?? '').toUpperCase();
  final body = switch (action) {
    'PAY' => '确认后进入「已付款」待办（填实付金额和凭证）。不重审。',
    'MARK_PAID' => '提交实付金额和支付凭证后，按先票/先款进入核验或补票。不重审。',
    'UPLOAD_INVOICE' => '发票提交后，核验人会收到「核验发票」。不重审。',
    'SEAL' => '确认盖章后，合同用印进入「填写快递单号」。不重审。',
    'REPAY' => '提交还款金额和凭证后关闭本条待办。不重审。',
    _ => '确认完成该待办？提交后写入原单，不重新走审批。',
  };
  return TaskTodoConfirmCopy(
    title: '确认${item.actionTitle ?? '办理'}？',
    okText: '确认办理',
    needComment: action == 'WRITE_OFF',
    body: body,
  );
}

/// 二次确认后调用 complete-task。成功返回 true。
Future<bool> confirmAndCompleteTaskTodo({
  required BuildContext context,
  required XflowService service,
  required XflowProposalItem item,
  bool? verifyPassed,
}) async {
  final todoId = item.todoHint?.id ?? 0;
  if (todoId <= 0) return false;
  final action = (item.primaryAction ?? '').toUpperCase();
  final extra = <String, dynamic>{};
  if (action == 'VERIFY_INVOICE') {
    extra['verifyResult'] = (verifyPassed ?? false) ? '通过' : '失败';
  }
  final keys = item.requiredFields.where((k) => k != 'verifyResult').toList();
  final payload = Map<String, dynamic>.from(extra);
  for (final key in keys) {
    payload[key] = '';
  }
  final commentCtrl = TextEditingController();
  final copy = taskTodoConfirmCopy(item, verifyPassed: verifyPassed);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(copy.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(copy.body),
          const SizedBox(height: 12),
          TextField(
            controller: commentCtrl,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: copy.needComment
                  ? '原因（必填，会写到单据详情评论）'
                  : '办理意见（会写到单据详情评论）',
            ),
          ),
          if (keys.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final key in keys)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  decoration: InputDecoration(labelText: key),
                  onChanged: (v) => payload[key] = v,
                ),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            if (copy.needComment && commentCtrl.text.trim().isEmpty) {
              showDunesToast(ctx, '请填写原因', kind: DunesToastKind.error);
              return;
            }
            Navigator.pop(ctx, true);
          },
          style: copy.danger
              ? FilledButton.styleFrom(backgroundColor: DunesColors.coral)
              : null,
          child: Text(copy.okText),
        ),
      ],
    ),
  );
  final comment = commentCtrl.text.trim();
  commentCtrl.dispose();
  if (ok != true) return false;
  try {
    await service.completeTask(
      todoId: todoId,
      action: item.primaryAction ?? '',
      payload: payload,
      comment: comment,
    );
    if (context.mounted) {
      showDunesToast(
        context,
        verifyPassed == false ? '已退回补票，发起人将收到「补传发票」' : '已办理',
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      showDunesToast(
        context,
        '办理失败：${friendlyErrorText(e)}',
        kind: DunesToastKind.error,
      );
    }
    return false;
  }
}
