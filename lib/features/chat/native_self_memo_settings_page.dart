import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import 'group_info_widgets.dart';

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
      backgroundColor: DunesColors.bgApp,
      appBar: AppBar(
        leading: IconButton(
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('文件传输助手'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
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
          const SizedBox(height: 10),
          GroupInfoRow(
            icon: Icons.search,
            title: '查找聊天内容',
            trailing: const GroupInfoChevron(),
            onTap: () => widget.onOpenSearch(widget.conversation.id),
          ),
        ],
      ),
    );
  }
}
