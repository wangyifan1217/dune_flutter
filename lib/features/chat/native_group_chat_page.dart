import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
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
    required     this.onOpenGroupInfo,
    this.onConversationRead,
    this.autoMarkRead = false,
  });

  final AuthSession session;
  final NativeConversation? conversationHint;
  final int? focusMessageId;
  final NativeChatMessage? focusMessageHint;
  final VoidCallback onBack;
  final ValueChanged<int> onOpenSearch;
  final ValueChanged<int> onOpenMedia;
  final VoidCallback onOpenGroupInfo;
  final ValueChanged<int>? onConversationRead;
  final bool autoMarkRead;

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
      onConversationRead: onConversationRead,
      autoMarkRead: autoMarkRead,
    );
  }
}
