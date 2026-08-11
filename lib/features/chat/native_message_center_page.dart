import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../conversation/inbox_format.dart';
import '../conversation/notification_service.dart';
import '../shell/dunes_toast.dart';
import 'chat_widgets.dart';

/// 通讯页右上角的统一消息中心：系统通知和公司广播在同一页面内切换。
class NativeMessageCenterPage extends StatefulWidget {
  const NativeMessageCenterPage({
    super.key,
    required this.session,
    required this.onBack,
    this.onNotificationsRead,
    this.onBroadcastRead,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final VoidCallback? onNotificationsRead;
  final ValueChanged<int>? onBroadcastRead;

  @override
  State<NativeMessageCenterPage> createState() =>
      _NativeMessageCenterPageState();
}

class _NativeMessageCenterPageState extends State<NativeMessageCenterPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final NotificationService _notificationService;
  late final ConversationService _conversationService;

  bool _notificationsLoading = true;
  String? _notificationsError;
  int _notificationUnread = 0;
  List<NativeNotificationItem> _notifications = const [];
  bool _markingNotificationsRead = false;

  bool _broadcastLoading = false;
  bool _broadcastLoaded = false;
  String? _broadcastError;
  NativeConversation? _broadcast;
  List<NativeChatMessage> _broadcastMessages = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_onTabChanged);
    _notificationService = NotificationService(session: widget.session);
    _conversationService = ConversationService(session: widget.session);
    _loadNotifications(markReadOnEnter: true);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
    if (_tabController.index == 0) {
      unawaited(_loadNotifications(markReadOnEnter: true));
    } else {
      unawaited(_loadBroadcast());
    }
  }

  Future<void> _loadNotifications({bool markReadOnEnter = false}) async {
    setState(() {
      _notificationsLoading = true;
      _notificationsError = null;
    });
    try {
      final results = await Future.wait([
        _notificationService.fetchSummary(),
        _notificationService.fetchAll(),
      ]);
      if (!mounted) return;
      final summary = results[0] as NativeNotificationSummary;
      setState(() {
        _notificationUnread = summary.unreadCount;
        _notifications = results[1] as List<NativeNotificationItem>;
        _notificationsLoading = false;
      });
      if (markReadOnEnter && summary.unreadCount > 0) {
        await _markNotificationsRead(reload: false);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _notificationsError = friendlyErrorText(error);
        _notificationsLoading = false;
      });
    }
  }

  Future<void> _markNotificationsRead({bool reload = true}) async {
    if (_markingNotificationsRead) return;
    _markingNotificationsRead = true;
    try {
      await _notificationService.markAllRead();
      if (mounted) {
        setState(() => _notificationUnread = 0);
      }
      widget.onNotificationsRead?.call();
      if (reload) await _loadNotifications();
    } catch (error) {
      if (!mounted) return;
      showDunesToast(
        context,
        '标记失败：${friendlyErrorText(error)}',
        kind: DunesToastKind.error,
      );
    } finally {
      _markingNotificationsRead = false;
    }
  }

  Future<void> _loadBroadcast() async {
    if (_broadcastLoading) return;
    setState(() {
      _broadcastLoading = true;
      _broadcastError = null;
    });
    try {
      final rows = await _conversationService.fetchBroadcastConversations();
      final conversation = rows.isEmpty ? null : rows.first;
      final messages = conversation == null
          ? const <NativeChatMessage>[]
          : await _conversationService.fetchMessages(conversation.id, size: 50);
      messages.sort((a, b) => b.id.compareTo(a.id));
      if (!mounted) return;
      setState(() {
        _broadcast = conversation;
        _broadcastMessages = messages;
        _broadcastLoaded = true;
        _broadcastLoading = false;
      });
      if (conversation != null && conversation.unreadCount > 0) {
        await _conversationService.markConversationRead(conversation.id);
        widget.onBroadcastRead?.call(conversation.id);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _broadcastError = friendlyErrorText(error);
        _broadcastLoaded = true;
        _broadcastLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommBackScaffold(
      crumb: '沙丘 · 消息中心',
      title: '系统消息与广播',
      onBack: widget.onBack,
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            decoration: BoxDecoration(
              color: DunesColors.bgSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: DunesColors.accentSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              labelColor: DunesColors.accentDeep,
              unselectedLabelColor: DunesColors.text3,
              labelStyle: DunesTypography.sans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              tabs: [
                Tab(
                  text:
                      '系统通知${_notificationUnread > 0 ? ' · $_notificationUnread' : ''}',
                ),
                const Tab(text: '公司广播'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildNotifications(), _buildBroadcast()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifications() {
    if (_notificationsLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_notificationsError != null) {
      return _ErrorState(
        error: _notificationsError!,
        onRetry: () => _loadNotifications(markReadOnEnter: true),
      );
    }
    if (_notifications.isEmpty) {
      return const Center(
        child: Text('暂无系统通知', style: TextStyle(color: DunesColors.text3)),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadNotifications(markReadOnEnter: true),
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: _notifications.length,
        itemBuilder: (_, index) {
          final item = _notifications[index];
          return NotiCard(
            title: item.title.isEmpty ? '系统通知' : item.title,
            body: item.body,
            timeLabel: InboxFormat.formatTime(item.createdAt, withClock: true),
            tag: item.kind.isEmpty ? null : item.kind,
            unread: index < _notificationUnread,
          );
        },
      ),
    );
  }

  Widget _buildBroadcast() {
    if (!_broadcastLoaded || _broadcastLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_broadcastError != null) {
      return _ErrorState(error: _broadcastError!, onRetry: _loadBroadcast);
    }
    if (_broadcastMessages.isEmpty) {
      return const Center(
        child: Text('暂无公司广播', style: TextStyle(color: DunesColors.text3)),
      );
    }
    final title = _broadcast?.title.trim();
    return RefreshIndicator(
      onRefresh: _loadBroadcast,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: _broadcastMessages.length,
        itemBuilder: (_, index) {
          final message = _broadcastMessages[index];
          return NotiCard(
            title: title == null || title.isEmpty ? '公司广播' : title,
            body: message.bodyText,
            timeLabel: InboxFormat.formatTime(
              message.createdAt,
              withClock: true,
            ),
            tag: '广播',
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error, style: const TextStyle(color: DunesColors.text3)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
