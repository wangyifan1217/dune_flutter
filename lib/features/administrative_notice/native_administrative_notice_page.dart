import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/chat_file_preview_page.dart';
import '../chat/chat_file_type_icon.dart';
import '../chat/chat_media_widgets.dart';
import '../chat/chat_widgets.dart';
import '../chat/file_download.dart' as file_dl;
import '../chat/user_avatar_widget.dart';
import '../contacts/native_contacts_page.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import '../tasks/native_task_home_pane.dart';
import 'administrative_notice_attachment_field.dart';
import 'administrative_notice_models.dart';
import 'administrative_notice_service.dart';

const _noticeAccent = Color(0xFF3D7A8C);

enum _AdministrativeNoticePage { list, detail, compose }

class NativeAdministrativeNoticePage extends StatefulWidget {
  const NativeAdministrativeNoticePage({
    super.key,
    required this.session,
    this.conversationHint,
    this.initialNoticeId,
    this.embedded = false,
    this.showBackButton = false,
    this.onBack,
    this.onChromeChanged,
    this.onAcknowledged,
  });

  final AuthSession session;
  final NativeConversation? conversationHint;
  final int? initialNoticeId;
  final bool embedded;
  final bool showBackButton;
  final VoidCallback? onBack;
  final ValueChanged<TaskShellChrome>? onChromeChanged;
  final ValueChanged<int>? onAcknowledged;

  @override
  State<NativeAdministrativeNoticePage> createState() =>
      _NativeAdministrativeNoticePageState();
}

class _NativeAdministrativeNoticePageState
    extends State<NativeAdministrativeNoticePage> {
  late final AdministrativeNoticeService _service = AdministrativeNoticeService(
    session: widget.session,
  );
  late final ConversationService _chatService = ConversationService(
    session: widget.session,
  );
  late final PageController _pageController = PageController();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  _AdministrativeNoticePage _page = _AdministrativeNoticePage.list;
  List<AdministrativeNotice> _items = const <AdministrativeNotice>[];
  AdministrativeNotice? _selected;
  final Set<int> _selectedUserIds = <int>{};
  final Map<int, String> _selectedUserNames = <int, String>{};
  final List<Map<String, dynamic>> _attachments = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _sending = false;
  bool _openingAttachment = false;
  bool _access = false;
  bool _receiveAccess = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishChrome());
    unawaited(_load());
  }

  @override
  void dispose() {
    _service.close();
    _chatService.close();
    _pageController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _publishChrome() {
    if (!widget.embedded) return;
    widget.onChromeChanged?.call(
      TaskShellChrome(
        onBack: _page == _AdministrativeNoticePage.list
            ? widget.onBack
            : () => _showPage(_AdministrativeNoticePage.list),
        trailing: _page == _AdministrativeNoticePage.list && _access
            ? IconButton(
                tooltip: '新建行政通知',
                onPressed: _openComposer,
                icon: const Icon(Icons.add_circle_outline),
              )
            : null,
      ),
    );
  }

  Future<void> _load() async {
    try {
      var publishAccess = widget.session.effectiveAdministrativeNoticeAccess;
      try {
        publishAccess = await _service.canAccess();
      } catch (_) {
        // 使用登录态作为网络异常时的回退；发布接口仍由后端最终鉴权。
      }
      var receiveAccess =
          widget.conversationHint?.id != null &&
          (widget.conversationHint?.id ?? 0) > 0;
      final targetId = widget.initialNoticeId ?? 0;
      if (!publishAccess && !receiveAccess) {
        // 普通接收人没有工作台发布权限，但收到通知后可以通过固定会话
        // 进入详情；没有历史会话的用户不能凭空创建行政通知会话。
        try {
          receiveAccess = await _service.ensureConversation() > 0;
        } catch (_) {
          receiveAccess = false;
        }
      }
      final canReceive = publishAccess || receiveAccess || targetId > 0;
      if (!mounted) return;
      setState(() {
        _access = publishAccess;
        _receiveAccess = canReceive;
      });
      _publishChrome();
      if (!canReceive) {
        setState(() {
          _loading = false;
          _error = '当前账号暂无行政通知';
        });
        return;
      }
      // 行政通知未读以确认（ACK）为准，进入列表/详情不 mark-read，
      // 否则会清掉 Tab 红点与会话角标，返回后要等刷新才恢复。
      // IM（非 embedded）只看需要自己确认的接收通知；工作台保留发送+接收。
      final rows = await _service.fetchNotices(inboxOnly: !widget.embedded);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
      if (targetId > 0) {
        final matches = rows.where((item) => item.id == targetId);
        if (matches.isNotEmpty) {
          final target = matches.first;
          _showPage(_AdministrativeNoticePage.detail, notice: target);
          unawaited(_openDetail(target));
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _showPage(
    _AdministrativeNoticePage page, {
    AdministrativeNotice? notice,
  }) {
    if (!mounted) return;
    setState(() {
      _page = page;
      _selected = notice;
    });
    _publishChrome();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          page.index,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _openDetail(AdministrativeNotice notice) async {
    _showPage(_AdministrativeNoticePage.detail, notice: notice);
    try {
      final detail = await _service.fetchNotice(notice.id);
      if (mounted) setState(() => _selected = detail);
    } catch (_) {}
  }

  Future<void> _openComposer() async {
    setState(() {
      _selectedUserIds.clear();
      _selectedUserNames.clear();
      _attachments.clear();
      _titleController.clear();
      _bodyController.clear();
    });
    _showPage(_AdministrativeNoticePage.compose);
  }

  Widget _recipientPickerPage({
    required VoidCallback onCancel,
    required void Function(Set<int> ids, Map<int, String> names) onConfirm,
  }) {
    return NativeContactsPage(
      session: widget.session,
      initialGroupPickMode: true,
      initialSelectedUserIds: _selectedUserIds,
      initialSelectedNames: _selectedUserNames,
      groupPickTitle: '选择接收人员',
      groupPickSubtitle: '从通讯录选择',
      minPickCount: 1,
      allowSelfInPickMode: true,
      onBack: onCancel,
      onOpenContact: (_) {},
      onStartPrivateChat: (_) {},
      onPickCompleted: onConfirm,
    );
  }

  Future<void> _pickRecipients() async {
    (Set<int>, Map<int, String>)? picked;
    if (isDesktopCommOnly) {
      picked = await showModalBottomSheet<(Set<int>, Map<int, String>)>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.28),
        builder: (sheetContext) {
          final screenHeight = MediaQuery.sizeOf(sheetContext).height;
          final sheetHeight = (screenHeight * 0.72).clamp(480.0, 760.0);
          return Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: const Color(0xFFF5F6F8),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: sheetHeight,
                width: double.infinity,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD8DCE2),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Expanded(
                      child: _recipientPickerPage(
                        onCancel: () => Navigator.pop(sheetContext),
                        onConfirm: (ids, names) =>
                            Navigator.pop(sheetContext, (ids, names)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } else {
      picked = await Navigator.of(context)
          .push<(Set<int>, Map<int, String>)>(
        MaterialPageRoute(
          builder: (ctx) => _recipientPickerPage(
            onCancel: () => Navigator.pop(ctx),
            onConfirm: (ids, names) => Navigator.pop(ctx, (ids, names)),
          ),
        ),
      );
    }
    final selection = picked;
    if (selection == null || !mounted) return;
    final ids = selection.$1;
    final names = selection.$2;
    setState(() {
      _selectedUserIds
        ..clear()
        ..addAll(ids);
      _selectedUserNames
        ..clear()
        ..addAll(names);
    });
  }

  void _removeRecipient(int userId) {
    setState(() {
      _selectedUserIds.remove(userId);
      _selectedUserNames.remove(userId);
    });
  }

  Future<void> _send() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty) {
      showDunesToast(context, '请输入通知标题', kind: DunesToastKind.error);
      return;
    }
    if (_selectedUserIds.isEmpty) {
      showDunesToast(context, '请选择接收人员', kind: DunesToastKind.error);
      return;
    }
    final count = _selectedUserIds.length;
    final previewNames = _selectedUserIds
        .take(3)
        .map((id) => _selectedUserNames[id] ?? '成员')
        .join('、');
    final more = count > 3 ? ' 等' : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认发送行政通知？'),
        content: Text(
          '将向 $previewNames$more共 $count 人发送通知「$title」。\n\n发送后接收人将收到推送，请确认内容无误。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _noticeAccent),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认发送'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _sending = true);
    try {
      final created = await _service.createNotice(
        title: title,
        body: body,
        recipientUserIds: _selectedUserIds.toList(),
        attachments: _attachments,
      );
      if (!mounted) return;
      setState(() {
        _items = <AdministrativeNotice>[created, ..._items];
        _sending = false;
      });
      showDunesToast(context, '行政通知已发送');
      _showPage(_AdministrativeNoticePage.detail, notice: created);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        showDunesToast(
          context,
          '发送失败：${e.toString().replaceFirst('Exception: ', '')}',
          kind: DunesToastKind.error,
        );
      }
    }
  }

  Future<void> _acknowledge() async {
    final notice = _selected;
    if (notice == null || notice.acknowledged) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认收到行政通知？'),
        content: const Text('确认后，行政人员可以看到你的确认状态。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final updated = await _service.acknowledge(notice.id);
      if (!mounted) return;
      setState(() {
        _selected = updated;
        _items = _items
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
      });
      final conversationId =
          widget.conversationHint?.id ?? await _service.ensureConversation();
      if (!mounted) return;
      if (conversationId > 0) {
        widget.onAcknowledged?.call(conversationId);
      }
      showDunesToast(context, '已确认');
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          '确认失败：${e.toString().replaceFirst('Exception: ', '')}',
          kind: DunesToastKind.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ColoredBox(
      color: const Color(0xFFF5F6F8),
      child: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (index) {
          if (_page.index != index) {
            setState(() => _page = _AdministrativeNoticePage.values[index]);
            _publishChrome();
          }
        },
        children: [_buildList(), _buildDetail(), _buildComposer()],
      ),
    );
    if (widget.embedded) return content;
    final onDetail = _page == _AdministrativeNoticePage.detail;
    final onCompose = _page == _AdministrativeNoticePage.compose;
    final detailTitle = (_selected?.title ?? '').trim();
    // IM 会话入口不展示「+」发布；发布入口只在工作台 embedded。
    final showComposeAction =
        widget.embedded &&
        _page == _AdministrativeNoticePage.list &&
        _access;
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ChatConvHeader(
              title: onCompose
                  ? '发布行政通知'
                  : onDetail && detailTitle.isNotEmpty
                  ? detailTitle
                  : '行政通知',
              subtitle: onDetail
                  ? ((_selected?.senderName.trim().isNotEmpty ?? false)
                        ? '${_selected!.senderName} · ${_formatDate(_selected!.createdAt)}'
                        : ' ')
                  : (_loading ? '加载中…' : '确认后清除未读'),
              onBack: onDetail || onCompose
                  ? () => _showPage(_AdministrativeNoticePage.list)
                  : (widget.onBack ?? () => Navigator.maybePop(context)),
              showBackButton:
                  onDetail || onCompose || widget.showBackButton,
              leadingAvatar: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.campaign_outlined,
                  color: Color(0xFF7652B8),
                ),
              ),
              actions: [
                if (showComposeAction)
                  IconButton(
                    tooltip: '新建行政通知',
                    onPressed: _openComposer,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
              ],
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_receiveAccess) {
      return _emptyState(_error ?? '当前账号暂无行政通知', Icons.lock_outline);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        // 会话名已在左侧列表 / 顶部 Header 展示，正文不再重复「行政通知」标题。
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
        children: [
          if (_items.isEmpty)
            _emptyState('暂无行政通知', Icons.campaign_outlined)
          else
            ..._items.map(_noticeCard),
        ],
      ),
    );
  }

  Widget _noticeCard(AdministrativeNotice notice) {
    final total = notice.recipientCount < 0 ? 0 : notice.recipientCount;
    final acked = notice.acknowledgedCount.clamp(0, total);
    final pendingCount = (total - acked).clamp(0, total);
    final personalPending =
        notice.isPendingAcknowledgement &&
        notice.senderUserId != widget.session.userId;
    final allConfirmed = total > 0 && pendingCount == 0;
    // 与详情页一致：人数进度只给工作台发布端；IM 入口只看自己是否确认。
    final showProgress = widget.embedded;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6E8EC)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openDetail(notice),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 14, showProgress ? 14 : 12, 14),
          child: Row(
            crossAxisAlignment:
                showProgress ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEDE7FF),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.campaign_outlined,
                  color: Color(0xFF7652B8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notice.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: DunesColors.text,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      notice.body.isEmpty ? '暂无正文' : notice.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: DunesColors.text3,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${notice.senderName} · ${_formatDate(notice.createdAt)}',
                      style: const TextStyle(
                        color: DunesColors.text3,
                        fontSize: 11,
                      ),
                    ),
                    if (showProgress) ...[
                      const SizedBox(height: 8),
                      _noticeProgressSummary(
                        total: total,
                        acked: acked,
                        pendingCount: pendingCount,
                        allConfirmed: allConfirmed,
                      ),
                    ],
                  ],
                ),
              ),
              if (!showProgress) ...[
                const SizedBox(width: 8),
                if (personalPending)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      '待确认',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB07A2B),
                        height: 1.15,
                      ),
                    ),
                  )
                else
                  const Text(
                    '已确认',
                    style: TextStyle(
                      color: Color(0xFF3D7A8C),
                      fontSize: 12,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _noticeProgressSummary({
    required int total,
    required int acked,
    required int pendingCount,
    required bool allConfirmed,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(
            '$acked/$total',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: allConfirmed
                  ? const Color(0xFF3D7A8C)
                  : DunesColors.text,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            allConfirmed ? '全部已确认' : '已确认',
            style: TextStyle(
              fontSize: 11,
              color: allConfirmed
                  ? const Color(0xFF3D7A8C)
                  : DunesColors.text2,
              height: 1.1,
            ),
          ),
          const Spacer(),
          if (pendingCount > 0)
            Text(
              '待确认 $pendingCount',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB07A2B),
                height: 1.1,
              ),
            )
          else
            Text(
              '共 $total 人',
              style: const TextStyle(
                fontSize: 11,
                color: DunesColors.text3,
                height: 1.1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetail() {
    final notice = _selected;
    if (notice == null) {
      return _emptyState('请选择一条行政通知', Icons.campaign_outlined);
    }
    final isSender = notice.senderUserId == widget.session.userId;
    final senderName = notice.senderName.trim().isEmpty
        ? '行政'
        : notice.senderName.trim();
    final senderInitial = senderName.substring(0, 1);
    // 与 APP 一致：正文可点选长按复制，不额外套「通知详情」页内标题。
    // IM 会话里只展示自己是否确认；完整确认进度仅工作台 embedded 发布方可见。
    final showProgress =
        widget.embedded && isSender && notice.recipients.isNotEmpty;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ImUserAvatar(
                    initial: senderInitial,
                    seed: notice.senderUserId,
                    size: 40,
                    avatarService: _chatService,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notice.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: DunesColors.text,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$senderName · ${_formatDate(notice.createdAt)}',
                          style: const TextStyle(
                            color: DunesColors.text3,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                notice.body.isEmpty ? '暂无正文' : notice.body,
                style: const TextStyle(
                  height: 1.65,
                  fontSize: 15,
                  color: DunesColors.text,
                ),
              ),
              if (notice.attachments.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  '附件',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                ...notice.attachments.map(_attachmentTile),
              ],
              if (!isSender && !notice.acknowledged) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _noticeAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _acknowledge,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('确认收到'),
                  ),
                ),
              ] else if (!isSender) ...[
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF3D7A8C),
                      size: 18,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '你已确认',
                      style: TextStyle(color: Color(0xFF3D7A8C)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (showProgress) ...[
          const SizedBox(height: 12),
          _receiptCard(notice),
        ],
      ],
    );
  }

  Widget _receiptCard(AdministrativeNotice notice) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '确认进度 ${notice.acknowledgedCount}/${notice.recipientCount}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 6),
          ...notice.recipients.map((recipient) {
            final name = recipient.displayName.trim();
            final initial = name.isEmpty ? '行' : name.substring(0, 1);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  ImUserAvatar(
                    initial: initial,
                    seed: recipient.userId,
                    size: 34,
                    avatarPreset: recipient.avatarPreset,
                    avatarObjectKey: recipient.avatarObjectKey,
                    avatarUrl: recipient.avatarUrl,
                    avatarService: _chatService,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      recipient.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                  Text(
                    recipient.acknowledged ? '已确认' : '待确认',
                    style: TextStyle(
                      fontSize: 12,
                      color: recipient.acknowledged
                          ? const Color(0xFF3D7A8C)
                          : DunesColors.text3,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Map<String, dynamic> _attachmentPayload(
    AdministrativeNoticeAttachment attachment,
  ) {
    return <String, dynamic>{
      'fileName': attachment.fileName,
      'mimeType': attachment.mimeType,
      'sizeBytes': attachment.sizeBytes,
      if ((attachment.url ?? '').trim().isNotEmpty) 'url': attachment.url,
      if ((attachment.objectKey ?? '').trim().isNotEmpty)
        'objectKey': attachment.objectKey,
    };
  }

  Widget _attachmentTile(AdministrativeNoticeAttachment attachment) {
    final isImage =
        attachment.mimeType.toLowerCase().startsWith('image/') ||
        _isImageFileName(attachment.fileName);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _openingAttachment
              ? null
              : () => unawaited(_openAttachment(attachment)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            child: Row(
              children: [
                ChatFileTypeIcon(fileName: attachment.fileName, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: DunesColors.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isImage
                            ? '图片 · ${_formatSize(attachment.sizeBytes)}'
                            : _formatSize(attachment.sizeBytes),
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isImageFileName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  Future<void> _openAttachment(
    AdministrativeNoticeAttachment attachment,
  ) async {
    if (_openingAttachment) return;
    final payload = _attachmentPayload(attachment);
    final fileName = attachment.fileName.trim().isEmpty
        ? '附件'
        : attachment.fileName.trim();
    final conversationId = widget.conversationHint?.id;
    final isImage =
        attachment.mimeType.toLowerCase().startsWith('image/') ||
        _isImageFileName(fileName);

    setState(() => _openingAttachment = true);
    try {
      if (isImage) {
        await showChatImagePreview(
          context,
          service: _chatService,
          payload: payload,
          fileName: fileName,
          conversationId: conversationId,
        );
        return;
      }

      // PC：优先本地下载并用系统应用打开，与会话文件一致。
      if (isDesktopCommOnly && !kIsWeb) {
        await _openAttachmentOnDesktop(payload, fileName, conversationId);
        return;
      }

      await showChatFilePreview(
        context: context,
        service: _chatService,
        payload: payload,
        fileName: fileName,
        conversationId: conversationId,
        saveToDriveSession: widget.session,
      );
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          '打开失败：${friendlyErrorText(e)}',
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _openingAttachment = false);
    }
  }

  Future<void> _openAttachmentOnDesktop(
    Map<String, dynamic> payload,
    String fileName,
    int? conversationId,
  ) async {
    final cacheKey = () {
      final objectKey = (payload['objectKey'] ?? '').toString().trim();
      if (objectKey.isNotEmpty) return objectKey;
      return ConversationService.mediaDirectUrl(payload);
    }();

    if (cacheKey.isNotEmpty || (conversationId ?? 0) > 0) {
      final cached = await file_dl.findCachedChatFile(
        cacheKey,
        fileName,
        conversationId: conversationId,
      );
      if (cached != null && cached.isNotEmpty) {
        await file_dl.openLocalFile(cached);
        return;
      }
    }

    if (ConversationService.hasAuthMedia(payload)) {
      final bytes = await _chatService.downloadAttachmentBytes(
        objectKey: ConversationService.mediaObjectKey(payload),
        fileName: fileName,
      );
      final path = await file_dl.saveBytesAsCachedFile(
        bytes,
        cacheKey,
        fileName,
        conversationId: conversationId,
      );
      if (path != null && path.isNotEmpty) {
        await file_dl.openLocalFile(path);
        return;
      }
    }

    final url = ConversationService.mediaDirectUrl(payload);
    if (url.isEmpty) {
      throw Exception('附件地址为空');
    }
    await file_dl.openUrlAsFile(
      url,
      fileName,
      cacheKey: cacheKey.isEmpty ? null : cacheKey,
      conversationId: conversationId,
    );
  }

  Widget _buildComposer() {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          // 工作台 shell 已有返回与「行政通知」标题，此处不再重复「发布行政通知」。
          _composeCard(
            title: '通知内容',
            child: Column(
              children: [
                _composeField(
                  controller: _titleController,
                  hintText: '请输入通知标题',
                  maxLines: 1,
                ),
                const SizedBox(height: 10),
                _composeField(
                  controller: _bodyController,
                  hintText: '请输入通知正文（选填）',
                  minLines: 5,
                  maxLines: 9,
                ),
              ],
            ),
          ),
          _composeCard(
            title: '接收人员',
            trailing: TextButton(
              onPressed: _pickRecipients,
              child: const Text('从通讯录选择'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: const Color(0xFFF5F6F8),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: _pickRecipients,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE8EAED)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE4ECEB),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.contacts_outlined,
                              color: _noticeAccent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _selectedUserIds.isEmpty
                                  ? '点击选择接收人员'
                                  : '已选 ${_selectedUserIds.length} 人',
                              style: TextStyle(
                                fontSize: 14,
                                color: _selectedUserIds.isEmpty
                                    ? DunesColors.text3
                                    : DunesColors.text,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: DunesColors.text3.withValues(alpha: 0.8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_selectedUserIds.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedUserIds.map((userId) {
                      final name =
                          _selectedUserNames[userId] ?? '用户 $userId';
                      return InputChip(
                        label: Text(name),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => _removeRecipient(userId),
                        backgroundColor: const Color(0xFFE4ECEB),
                        side: BorderSide.none,
                        labelStyle: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          _composeCard(
            title: '附件',
            child: AdministrativeNoticeAttachmentField(
              service: _service,
              attachments: _attachments,
              enabled: !_sending,
              onChanged: (next) => setState(() {
                _attachments
                  ..clear()
                  ..addAll(next);
              }),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _noticeAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '发送行政通知',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composeCard({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: _noticeAccent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: DunesColors.text,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _composeField({
    required TextEditingController controller,
    required String hintText,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 14, color: DunesColors.text),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: const TextStyle(color: DunesColors.text3, fontSize: 14),
        ),
      ),
    );
  }

  Widget _emptyState(String text, IconData icon) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: DunesColors.text3),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: DunesColors.text3),
          ),
        ],
      ),
    ),
  );

  String _formatDate(DateTime? date) => date == null
      ? ''
      : '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
