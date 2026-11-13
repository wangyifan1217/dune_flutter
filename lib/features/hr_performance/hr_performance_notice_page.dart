import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import 'hr_performance_chat_card.dart';
import 'hr_performance_service.dart';

class HrPerformanceNoticePage extends StatefulWidget {
  const HrPerformanceNoticePage({
    super.key,
    required this.session,
    required this.conversationId,
  });
  final AuthSession session;
  final int conversationId;
  @override
  State<HrPerformanceNoticePage> createState() =>
      _HrPerformanceNoticePageState();
}

class _HrPerformanceNoticePageState extends State<HrPerformanceNoticePage> {
  late final _service = ConversationService(session: widget.session);
  List<NativeChatMessage> _messages = [];
  bool _busy = false;
  String? _error;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool earlier = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final page = await _service.fetchMessages(
        widget.conversationId,
        size: 50,
        before: earlier && _messages.isNotEmpty
            ? _messages.map((m) => m.id).reduce((a, b) => a < b ? a : b)
            : null,
      );
      if (!mounted) return;
      final all = {
        for (final m in _messages) m.id: m,
        for (final m in page) m.id: m,
      };
      final rows = all.values.toList()..sort((a, b) => b.id.compareTo(a.id));
      setState(() {
        _messages = rows;
        _error = null;
      });
      await _service.markConversationRead(widget.conversationId);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(hrPerformanceTitle),
      actions: [
        IconButton(
          onPressed: _busy ? null : () => _load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        Expanded(
          child: ListView(
            reverse: true,
            padding: const EdgeInsets.all(16),
            children: [
              for (final message in _messages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child:
                      message.payload != null &&
                          isHrPerformancePayload(message.payload)
                      ? HrPerformanceChatCard(
                          payload: message.payload!,
                          session: widget.session,
                        )
                      : Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(message.bodyText),
                          ),
                        ),
                ),
              TextButton(
                onPressed: _busy ? null : () => _load(earlier: true),
                child: const Text('更早消息'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
