import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
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
    this.onConversationRead,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final NativeConversation? conversationHint;
  final ValueChanged<int>? onConversationRead;

  @override
  State<NativeBroadcastPage> createState() => _NativeBroadcastPageState();
}

class _NativeBroadcastPageState extends State<NativeBroadcastPage> {
  late final ConversationService _service;
  bool _loading = true;
  String? _error;
  List<NativeChatMessage> _messages = const <NativeChatMessage>[];
  String _title = '公司广播';
  int _convId = 0;
  Set<int> _readIds = <int>{};

  @override
  void initState() {
    super.initState();
    _service = ConversationService(session: widget.session);
    _load();
  }

  Future<void> _markAllReadOnEnter() async {
    if (_convId <= 0) return;
    final ids = _messages.map((m) => m.id).where((id) => id > 0).toSet();
    if (ids.isNotEmpty) {
      await _BroadcastReadStorage.addAll(ids);
      if (mounted) {
        setState(() => _readIds = {..._readIds, ...ids});
      }
    }
    try {
      await _service.markConversationRead(_convId);
      // 通知 host 刷新角标并清理残留通知，避免桌面角标按通知条数虚高。
      widget.onConversationRead?.call(_convId);
    } catch (_) {}
  }

  Future<void> _markRead(NativeChatMessage m) async {
    if (m.id <= 0 || _readIds.contains(m.id)) return;
    setState(() => _readIds = {..._readIds, m.id});
    await _BroadcastReadStorage.add(m.id);
    // 全部消息已读后，顺带把会话标记为已读，清除列表未读角标。
    final allRead = _messages.every((x) => x.id <= 0 || _readIds.contains(x.id));
    if (allRead && _convId > 0) {
      try {
        await _service.markConversationRead(_convId);
        // 通知 host 刷新角标：读完广播后若无其他未读，会清掉广播通知，
        // 避免桌面角标按残留通知条数继续计数。
        widget.onConversationRead?.call(_convId);
      } catch (_) {}
    }
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
      final readIds = await _BroadcastReadStorage.load();
      if (!mounted) return;
      setState(() {
        _title = conv!.title.isEmpty ? '公司广播' : conv.title;
        _convId = conv.id;
        _messages = msgs;
        _readIds = readIds;
        _loading = false;
      });
      // 进入广播详情页即视为全部已读（与微信公众号阅读一致）。
      unawaited(_markAllReadOnEnter());
    } catch (e) {
      if (!mounted) return;
      if (_isBroadcastEmptyLikeError(e)) {
        setState(() {
          _messages = const <NativeChatMessage>[];
          _loading = false;
          _error = null;
        });
        return;
      }
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  bool _isBroadcastEmptyLikeError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('http 403') ||
        text.contains('http 404') ||
        text.contains('forbidden');
  }

  @override
  Widget build(BuildContext context) {
    return CommBackScaffold(
      crumb: '公司广播',
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
      return const Center(
        child: Text('暂无广播消息', style: TextStyle(color: DunesColors.text3)),
      );
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
            showReadMark: true,
            read: _readIds.contains(m.id),
            onTap: () => _markRead(m),
          );
        },
      ),
    );
  }
}

/// 公司广播"按条已读"的本地持久化（后端仅支持会话级已读，按条状态存本地）。
abstract final class _BroadcastReadStorage {
  static const _key = 'dunes_broadcast_read_ids_v1';

  static Future<Set<int>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <int>{};
      return decoded
          .map((e) => (e as num?)?.toInt() ?? 0)
          .where((e) => e > 0)
          .toSet();
    } catch (_) {
      return <int>{};
    }
  }

  static Future<void> add(int messageId) async {
    if (messageId <= 0) return;
    final ids = await load()..add(messageId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(ids.toList()));
  }

  static Future<void> addAll(Set<int> messageIds) async {
    final ids = await load()..addAll(messageIds.where((id) => id > 0));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(ids.toList()));
  }
}
