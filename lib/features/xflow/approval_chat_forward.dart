import 'package:flutter/material.dart';

import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_picker_sheet.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'approval_chat_share.dart';

/// 审批详情 → 选会话转发（与会议纪要同一套会话选择器）。
Future<void> forwardApprovalToConversation({
  required BuildContext context,
  required AuthSession session,
  required ApprovalChatShare share,
}) async {
  final st = share.status.toUpperCase();
  if (st == 'DRAFT' || st == 'VOIDED') {
    showDunesToast(context, '草稿或已作废单据不可转发', kind: DunesToastKind.error);
    return;
  }
  final chat = ConversationService(session: session);
  final conversationId = await showConversationPickerSheet(
    context: context,
    service: chat,
    title: '转发至',
  );
  if (conversationId == null || conversationId <= 0 || !context.mounted) {
    return;
  }
  try {
    await chat.sendText(
      conversationId,
      share.bodyText,
      payload: share.toMessagePayload(),
    );
    if (context.mounted) {
      showDunesToast(context, '已转发到会话');
    }
  } catch (e) {
    if (context.mounted) {
      showDunesToast(
        context,
        '转发失败：${friendlyErrorText(e, fallback: '请稍后重试')}',
        kind: DunesToastKind.error,
      );
    }
  }
}
