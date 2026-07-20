import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import 'native_chat_view.dart';

class NativePrivateChatPage extends StatelessWidget {
  const NativePrivateChatPage({
    super.key,
    required this.session,
    this.conversationHint,
    this.peerUserIdHint,
    this.focusMessageId,
    this.focusMessageHint,
    required this.onBack,
    required this.onOpenProfile,
    required this.onOpenSearch,
    this.onOpenAiSummary,
    this.onConversationRead,
    this.onClearFocusMessage,
    this.autoMarkRead = false,
    this.showBackButton = true,
  });

  final AuthSession session;
  final NativeConversation? conversationHint;
  final int? peerUserIdHint;
  final int? focusMessageId;
  final NativeChatMessage? focusMessageHint;
  final VoidCallback onBack;
  final VoidCallback onOpenProfile;
  final ValueChanged<int> onOpenSearch;
  final ValueChanged<int>? onOpenAiSummary;
  final ValueChanged<int>? onConversationRead;
  final VoidCallback? onClearFocusMessage;
  final bool autoMarkRead;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return NativeChatView(
      session: session,
      kind: NativeChatKind.private,
      conversationHint: conversationHint,
      peerUserIdHint: peerUserIdHint,
      focusMessageId: focusMessageId,
      focusMessageHint: focusMessageHint,
      onBack: onBack,
      onOpenProfile: onOpenProfile,
      onOpenSearch: onOpenSearch,
      onOpenAiSummary: onOpenAiSummary,
      onConversationRead: onConversationRead,
      onClearFocusMessage: onClearFocusMessage,
      autoMarkRead: autoMarkRead,
      showBackButton: showBackButton,
    );
  }
}
