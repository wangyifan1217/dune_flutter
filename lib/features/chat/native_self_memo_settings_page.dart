import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import 'chat_widgets.dart';
import 'group_info_widgets.dart';
import 'im_ui_kit.dart';

class NativeSelfMemoSettingsPage extends StatefulWidget {
  const NativeSelfMemoSettingsPage({
    super.key,
    required this.conversation,
    required this.session,
    required this.onBack,
    required this.onOpenSearch,
    required this.onSettingsChanged,
  });

  final NativeConversation conversation;
  final AuthSession session;
  final VoidCallback onBack;
  final ValueChanged<int> onOpenSearch;
  final void Function({required int conversationId, bool? muted, bool? pinned})
  onSettingsChanged;

  @override
  State<NativeSelfMemoSettingsPage> createState() =>
      _NativeSelfMemoSettingsPageState();
}

class _NativeSelfMemoSettingsPageState
    extends State<NativeSelfMemoSettingsPage> {
  late bool _muted = widget.conversation.muted;
  late bool _pinned = widget.conversation.pinned;
  late final ConversationService _service = ConversationService(
    session: widget.session,
  );

  Future<void> _patch({bool? muted, bool? pinned}) async {
    await _service.patchMySettings(
      widget.conversation.id,
      muted: muted,
      pinned: pinned,
    );
    if (!mounted) return;
    widget.onSettingsChanged(
      conversationId: widget.conversation.id,
      muted: muted,
      pinned: pinned,
    );
    setState(() {
      if (muted != null) _muted = muted;
      if (pinned != null) _pinned = pinned;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ImVisualTokens.groupedBackground(context),
      body: SafeArea(
        child: Column(
          children: [
            ChatConvHeader(
              title: '文件传输助手',
              subtitle: '个人备忘与跨端文件传输',
              onBack: widget.onBack,
            ),
            Expanded(
              child: groupInfoPageShell(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 28),
                  children: [
                    GroupInfoHero(
                      title: '文件传输助手',
                      subtitle: '安全存放个人消息与临时文件',
                      leading: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: ImVisualTokens.primaryGradient(context),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: ImVisualTokens.softCardShadow(context),
                        ),
                        child: const Icon(
                          Icons.folder_copy_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ImGroupedCard(
                      dividerIndent: 16,
                      children: [
                        GroupInfoRow(
                          icon: Icons.notifications_off_outlined,
                          title: '消息免打扰',
                          trailing: GroupInfoToggle(value: _muted),
                          onTap: () => _patch(muted: !_muted),
                        ),
                        GroupInfoRow(
                          icon: Icons.push_pin_outlined,
                          title: '置顶聊天',
                          trailing: GroupInfoToggle(value: _pinned),
                          onTap: () => _patch(pinned: !_pinned),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ImGroupedCard(
                      dividerIndent: 16,
                      children: [
                        GroupInfoRow(
                          icon: Icons.search_rounded,
                          title: '查找聊天内容',
                          trailing: const GroupInfoChevron(),
                          onTap: () =>
                              widget.onOpenSearch(widget.conversation.id),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
