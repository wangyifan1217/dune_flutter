import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import 'chat_widgets.dart';

class NativeBroadcastPage extends StatefulWidget {
  const NativeBroadcastPage({
    super.key,
    required this.session,
    required this.onBack,
    this.conversationHint,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final NativeConversation? conversationHint;

  @override
  State<NativeBroadcastPage> createState() => _NativeBroadcastPageState();
}

class _NativeBroadcastPageState extends State<NativeBroadcastPage> {
  late final ConversationService _service;
  bool _loading = true;
  String? _error;
  List<NativeChatMessage> _messages = const <NativeChatMessage>[];
  String _title = '公司广播';

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      NativeConversation? conv = widget.conversationHint;
      if (conv == null) {
        final rows = await _service.fetchBroadcastConversations();
        if (rows.isNotEmpty) conv = rows.first;
      }
      if (conv == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _messages = const <NativeChatMessage>[];
        });
        return;
      }
      final msgs = await _service.fetchMessages(conv.id, size: 50);
      msgs.sort((a, b) => b.id.compareTo(a.id));
      if (!mounted) return;
      setState(() {
        _title = conv!.title.isEmpty ? '公司广播' : conv.title;
        _messages = msgs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommBackScaffold(
      crumb: '公司广播 · XYYT',
      title: '广播历史',
      onBack: widget.onBack,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: DunesColors.text3)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return const Center(child: Text('暂无广播消息', style: TextStyle(color: DunesColors.text3)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        itemCount: _messages.length,
        itemBuilder: (_, i) {
          final m = _messages[i];
          return NotiCard(
            title: _title,
            body: m.bodyText,
            timeLabel: InboxFormat.formatTime(m.createdAt, withClock: true),
            tag: '广播',
          );
        },
      ),
    );
  }
}
