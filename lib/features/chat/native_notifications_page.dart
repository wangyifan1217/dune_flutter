import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/inbox_format.dart';
import '../conversation/notification_service.dart';
import '../shell/dunes_toast.dart';
import 'chat_widgets.dart';

class NativeNotificationsPage extends StatefulWidget {
  const NativeNotificationsPage({
    super.key,
    required this.session,
    required this.onBack,
    this.onNotificationsRead,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final VoidCallback? onNotificationsRead;

  @override
  State<NativeNotificationsPage> createState() => _NativeNotificationsPageState();
}

class _NativeNotificationsPageState extends State<NativeNotificationsPage> {
  late final NotificationService _service;
  bool _loading = true;
  String? _error;
  int _unread = 0;
  List<NativeNotificationItem> _items = const <NativeNotificationItem>[];
  bool _markingRead = false;

  @override
  void initState() {
    super.initState();
    _service = NotificationService(session: widget.session);
    _load(markReadOnEnter: true);
  }

  Future<void> _load({bool markReadOnEnter = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _service.fetchSummary();
      final rows = await _service.fetchAll();
      if (!mounted) return;
      setState(() {
        _unread = summary.unreadCount;
        _items = rows;
        _loading = false;
      });
      if (markReadOnEnter && summary.unreadCount > 0) {
        await _markAllRead(reload: false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead({bool reload = true}) async {
    if (_markingRead) return;
    _markingRead = true;
    try {
      await _service.markAllRead();
      if (mounted) setState(() => _unread = 0);
      // 通知 host 刷新角标并清理残留通知，避免桌面角标按通知条数虚高。
      widget.onNotificationsRead?.call();
      if (reload) await _load();
    } catch (e) {
      if (!mounted) return;
      showDunesToast(context, '标记失败：${friendlyErrorText(e)}', kind: DunesToastKind.error);
    } finally {
      _markingRead = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommBackScaffold(
      crumb: '沙丘 · 通知',
      title: '全部消息${_unread > 0 ? ' · $_unread 未读' : ''}',
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
            OutlinedButton(
              onPressed: () => _load(markReadOnEnter: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(child: Text('暂无通知', style: TextStyle(color: DunesColors.text3)));
    }
    return RefreshIndicator(
      onRefresh: () => _load(markReadOnEnter: true),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        itemCount: _items.length,
        itemBuilder: (_, i) {
          final item = _items[i];
          return NotiCard(
            title: item.title.isEmpty ? '系统通知' : item.title,
            body: item.body,
            timeLabel: InboxFormat.formatTime(item.createdAt, withClock: true),
            tag: item.kind.isEmpty ? null : item.kind,
            unread: i < _unread,
          );
        },
      ),
    );
  }
}
