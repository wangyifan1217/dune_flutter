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

/// 通讯列表置顶的「沙丘公告」：系统通告和公司广播左右滑动切换。
class NativeMessageCenterPage extends StatefulWidget {
  const NativeMessageCenterPage({
    super.key,
    required this.session,
    required this.onBack,
    this.onNotificationsRead,
    this.onBroadcastRead,
    this.initialTab,
    this.markAllReadOnEnter = false,
  });

  final AuthSession session;
  final VoidCallback onBack;
  final VoidCallback? onNotificationsRead;
  final ValueChanged<int>? onBroadcastRead;

  /// `notice` 打开系统通告，`broadcast` 打开公司广播。
  /// 列表入口会按未读选择：仅广播未读进广播，其余（含两侧都未读）进系统通告。
  final String? initialTab;

  /// 从通讯列表点进「沙丘公告」时两侧都标已读，行上角标立刻消失。
  /// TPNS 点击只标对应一侧，避免误清另一侧未读。
  final bool markAllReadOnEnter;

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
  bool _pendingNoticeMarkRead = false;

  bool _broadcastLoading = false;
  bool _broadcastLoaded = false;
  String? _broadcastError;
  NativeConversation? _broadcast;
  List<NativeChatMessage> _broadcastMessages = const [];
  int _broadcastUnread = 0;
  bool _markingBroadcastRead = false;
  bool _pendingBroadcastMarkRead = false;

  @override
  void initState() {
    super.initState();
    final initialIndex =
        widget.initialTab?.trim().toLowerCase() == 'broadcast' ? 1 : 0;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialIndex,
    )..addListener(_onTabChanged);
    _notificationService = NotificationService(session: widget.session);
    _conversationService = ConversationService(session: widget.session);
    final markAll = widget.markAllReadOnEnter;
    unawaited(
      _loadNotifications(markReadOnEnter: markAll || initialIndex == 0),
    );
    unawaited(_loadBroadcast(markReadOnEnter: markAll || initialIndex == 1));
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
      _pendingNoticeMarkRead = true;
      if (_notificationsLoading) return;
      if (_notificationsError != null) {
        unawaited(_loadNotifications(markReadOnEnter: true));
      } else {
        unawaited(_markNotificationsRead(reload: false));
      }
    } else if (_broadcastLoaded) {
      unawaited(_markBroadcastRead());
    } else {
      unawaited(_loadBroadcast(markReadOnEnter: true));
    }
  }

  Future<void> _loadNotifications({bool markReadOnEnter = false}) async {
    if (markReadOnEnter) _pendingNoticeMarkRead = true;
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
      if (_pendingNoticeMarkRead) {
        _pendingNoticeMarkRead = false;
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
    _pendingNoticeMarkRead = false;
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

  Future<void> _loadBroadcast({bool markReadOnEnter = false}) async {
    if (markReadOnEnter) _pendingBroadcastMarkRead = true;
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
        _broadcastUnread = conversation?.unreadCount ?? 0;
        _broadcastLoaded = true;
        _broadcastLoading = false;
      });
      if (_pendingBroadcastMarkRead || markReadOnEnter) {
        _pendingBroadcastMarkRead = false;
        await _markBroadcastRead();
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

  Future<void> _markBroadcastRead() async {
    final conversation = _broadcast;
    if (_markingBroadcastRead || conversation == null) return;
    _markingBroadcastRead = true;
    try {
      await _conversationService.markConversationRead(conversation.id);
      if (mounted) {
        setState(() => _broadcastUnread = 0);
      }
      widget.onBroadcastRead?.call(conversation.id);
    } catch (_) {
      // 已读失败不挡阅读；角标下次刷新会校正。
    } finally {
      _markingBroadcastRead = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommBackScaffold(
      crumb: '沙丘公告',
      title: '沙丘公告',
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
                  child: _AnnouncementTabLabel(
                    text: '系统通告',
                    showDot: _notificationUnread > 0,
                  ),
                ),
                Tab(
                  child: _AnnouncementTabLabel(
                    text: '公司广播',
                    showDot: _broadcastUnread > 0,
                  ),
                ),
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
        child: Text('暂无系统通告', style: TextStyle(color: DunesColors.text3)),
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
            title: item.title.isEmpty ? '系统通告' : item.title,
            body: item.body,
            timeLabel: InboxFormat.formatTime(item.createdAt, withClock: true),
            tag: item.kind.isEmpty ? null : item.kind,
            unread: item.unread && _notificationUnread > 0,
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
      onRefresh: () => _loadBroadcast(markReadOnEnter: true),
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
            unread: index < _broadcastUnread,
          );
        },
      ),
    );
  }
}

class _AnnouncementTabLabel extends StatelessWidget {
  const _AnnouncementTabLabel({required this.text, required this.showDot});

  final String text;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        if (showDot) ...[
          const SizedBox(width: 5),
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: DunesColors.coral,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
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
