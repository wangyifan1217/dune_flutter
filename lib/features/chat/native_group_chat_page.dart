import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../xflow/approval_chat_share.dart';
import 'native_chat_view.dart';

class NativeGroupChatPage extends StatelessWidget {
  const NativeGroupChatPage({
    super.key,
    required this.session,
    this.conversationHint,
    this.focusMessageId,
    this.focusMessageHint,
    required this.onBack,
    required this.onOpenSearch,
    required this.onOpenMedia,
    required this.onOpenGroupInfo,
    this.onOpenUser,
    this.onOpenAiSummary,
    this.onOpenApprovalShare,
    this.onConversationRead,
    this.onClearFocusMessage,
    this.autoMarkRead = false,
    this.showBackButton = true,
  });

  final AuthSession session;
  final NativeConversation? conversationHint;
  final int? focusMessageId;
  final NativeChatMessage? focusMessageHint;
  final VoidCallback onBack;
  final ValueChanged<int> onOpenSearch;
  final ValueChanged<int> onOpenMedia;
  final VoidCallback onOpenGroupInfo;
  final void Function(int userId, String displayName)? onOpenUser;
  final ValueChanged<int>? onOpenAiSummary;
  final ValueChanged<ApprovalChatShare>? onOpenApprovalShare;
  final ValueChanged<int>? onConversationRead;
  final VoidCallback? onClearFocusMessage;
  final bool autoMarkRead;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return NativeChatView(
      session: session,
      kind: NativeChatKind.group,
      conversationHint: conversationHint,
      focusMessageId: focusMessageId,
      focusMessageHint: focusMessageHint,
      onBack: onBack,
      onOpenSearch: onOpenSearch,
      onOpenMedia: onOpenMedia,
      onOpenGroupInfo: onOpenGroupInfo,
      onOpenUser: onOpenUser,
      onOpenAiSummary: onOpenAiSummary,
      onOpenApprovalShare: onOpenApprovalShare,
      onConversationRead: onConversationRead,
      onClearFocusMessage: onClearFocusMessage,
      autoMarkRead: autoMarkRead,
      showBackButton: showBackButton,
    );
  }
}
