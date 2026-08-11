import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import '../chat/chat_widgets.dart';
import '../conversation/conversation_models.dart';
import '../shell/dunes_toast.dart';
import '../tasks/native_task_home_pane.dart';
import 'administrative_notice_models.dart';
import 'administrative_notice_service.dart';

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
  late final PageController _pageController = PageController();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _userSearchController = TextEditingController();
  _AdministrativeNoticePage _page = _AdministrativeNoticePage.list;
  List<AdministrativeNotice> _items = const <AdministrativeNotice>[];
  List<AdministrativeNoticeUser> _users = const <AdministrativeNoticeUser>[];
  AdministrativeNotice? _selected;
  final Set<int> _selectedUserIds = <int>{};
  final List<Map<String, dynamic>> _attachments = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _sending = false;
  bool _access = false;
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
    _pageController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    _userSearchController.dispose();
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
      final access =
          widget.session.effectiveAdministrativeNoticeAccess ||
          await _service.canAccess();
      if (!mounted) return;
      setState(() => _access = access);
      _publishChrome();
      if (!access) {
        setState(() {
          _loading = false;
          _error = '当前账号未开通行政通知权限';
        });
        return;
      }
      // Entering the list/detail records read_at.  It intentionally leaves
      // the business unread badge intact until the user confirms each notice.
      try {
        await _service.markConversationRead();
      } catch (_) {
        // A missing/old IM schema must not prevent the notice page from
        // loading; the ACK endpoint remains the source of truth for badges.
      }
      final rows = await _service.fetchNotices();
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
      final targetId = widget.initialNoticeId ?? 0;
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
    try {
      final users = await _service.fetchUsers();
      if (!mounted) return;
      setState(() {
        _users = users.where((u) => u.userId != widget.session.userId).toList();
        _selectedUserIds.clear();
        _attachments.clear();
        _titleController.clear();
        _bodyController.clear();
      });
      _showPage(_AdministrativeNoticePage.compose);
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          e.toString().replaceFirst('Exception: ', ''),
          kind: DunesToastKind.error,
        );
      }
    }
  }

  Future<void> _pickAttachments() async {
    final files = await openFiles();
    if (files.isEmpty) return;
    setState(() => _sending = true);
    try {
      for (final file in files) {
        _attachments.add(await _service.upload(file));
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        showDunesToast(
          context,
          '附件上传失败：${e.toString().replaceFirst('Exception: ', '')}',
          kind: DunesToastKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
    return Scaffold(
      backgroundColor: DunesColors.bgApp,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ChatConvHeader(
              title: '行政通知',
              subtitle: _loading ? '加载中…' : '确认后清除未读',
              onBack: widget.onBack ?? () => Navigator.maybePop(context),
              showBackButton: widget.showBackButton,
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
                if (!widget.embedded &&
                    _page == _AdministrativeNoticePage.list &&
                    _access)
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
    if (!_access) {
      return _emptyState(_error ?? '当前账号未开通行政通知权限', Icons.lock_outline);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '行政通知',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_items.isEmpty)
            _emptyState('暂无行政通知', Icons.campaign_outlined)
          else
            ..._items.map(_noticeCard),
        ],
      ),
    );
  }

  Widget _noticeCard(AdministrativeNotice notice) {
    final pending =
        notice.isPendingAcknowledgement &&
        notice.senderUserId != widget.session.userId;
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
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
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
                  ],
                ),
              ),
              if (notice.senderUserId == widget.session.userId)
                Text(
                  '${notice.acknowledgedCount}/${notice.recipientCount} 已确认',
                  style: const TextStyle(
                    color: Color(0xFF3D7A8C),
                    fontSize: 12,
                  ),
                )
              else if (pending)
                const Chip(
                  label: Text('待确认', style: TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Color(0xFFFFF1D7),
                )
              else
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF3D7A8C),
                  size: 21,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetail() {
    final notice = _selected;
    if (notice == null) {
      return _emptyState('请选择一条行政通知', Icons.campaign_outlined);
    }
    final isSender = notice.senderUserId == widget.session.userId;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _pageHeader(
          '通知详情',
          onBack: () => _showPage(_AdministrativeNoticePage.list),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0xFFE6E8EC)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${notice.senderName} · ${_formatDate(notice.createdAt)}',
                  style: const TextStyle(
                    color: DunesColors.text3,
                    fontSize: 12,
                  ),
                ),
                const Divider(height: 26),
                SelectableText(
                  notice.body.isEmpty ? '暂无正文' : notice.body,
                  style: const TextStyle(height: 1.6, color: DunesColors.text),
                ),
                if (notice.attachments.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text(
                    '附件',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
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
                    child: FilledButton.icon(
                      onPressed: _acknowledge,
                      icon: const Icon(Icons.check),
                      label: const Text('确认收到'),
                    ),
                  ),
                ] else if (!isSender) ...[
                  const SizedBox(height: 18),
                  const Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Color(0xFF3D7A8C),
                        size: 18,
                      ),
                      SizedBox(width: 6),
                      Text('你已确认', style: TextStyle(color: Color(0xFF3D7A8C))),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        if (isSender && notice.recipients.isNotEmpty) ...[
          const SizedBox(height: 14),
          _receiptCard(notice),
        ],
      ],
    );
  }

  Widget _receiptCard(AdministrativeNotice notice) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE6E8EC)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 10),
            ...notice.recipients.map((recipient) {
              final name = recipient.displayName.trim();
              final initial = name.isEmpty ? '行' : name.substring(0, 1);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: const Color(0xFFEDE7FF),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Color(0xFF7652B8),
                      fontSize: 12,
                    ),
                  ),
                ),
                title: Text(recipient.displayName),
                trailing: recipient.acknowledged
                    ? const Text(
                        '已确认',
                        style: TextStyle(color: Color(0xFF3D7A8C)),
                      )
                    : const Text(
                        '待确认',
                        style: TextStyle(color: DunesColors.text3),
                      ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _attachmentTile(AdministrativeNoticeAttachment attachment) {
    final isImage = attachment.mimeType.startsWith('image/');
    final url = attachment.url?.trim() ?? '';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
        color: const Color(0xFF3D7A8C),
      ),
      title: Text(
        attachment.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(_formatSize(attachment.sizeBytes)),
      onTap: url.isEmpty
          ? null
          : isImage
          ? () => showDialog<void>(
              context: context,
              builder: (_) =>
                  Dialog(child: InteractiveViewer(child: Image.network(url))),
            )
          : () async {
              final opened = await launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              );
              if (!opened && mounted) {
                showDunesToast(context, '无法打开附件', kind: DunesToastKind.error);
              }
            },
    );
  }

  Widget _buildComposer() {
    final query = _userSearchController.text.trim().toLowerCase();
    final users = query.isEmpty
        ? _users
        : _users
              .where(
                (u) =>
                    u.displayName.toLowerCase().contains(query) ||
                    (u.departmentName ?? '').toLowerCase().contains(query),
              )
              .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _pageHeader(
          '发布行政通知',
          onBack: () => _showPage(_AdministrativeNoticePage.list),
        ),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: '标题',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bodyController,
          minLines: 5,
          maxLines: 9,
          decoration: const InputDecoration(
            labelText: '通知内容',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(
              child: Text(
                '选择接收人员',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                if (_selectedUserIds.length == _users.length) {
                  _selectedUserIds.clear();
                } else {
                  _selectedUserIds.addAll(_users.map((u) => u.userId));
                }
              }),
              child: Text(
                _selectedUserIds.length == _users.length && _users.isNotEmpty
                    ? '取消全选'
                    : '全选',
              ),
            ),
          ],
        ),
        TextField(
          controller: _userSearchController,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '搜索姓名或部门',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        if (users.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('暂无可选人员', style: TextStyle(color: DunesColors.text3)),
          )
        else
          ...users.map(
            (user) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _selectedUserIds.contains(user.userId),
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _selectedUserIds.add(user.userId);
                } else {
                  _selectedUserIds.remove(user.userId);
                }
              }),
              title: Text(user.displayName),
              subtitle: user.departmentName == null
                  ? null
                  : Text(user.departmentName!),
              dense: true,
            ),
          ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _sending ? null : _pickAttachments,
          icon: const Icon(Icons.attach_file),
          label: Text(_attachments.isEmpty ? '添加图片或文件' : '继续添加附件'),
        ),
        if (_attachments.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._attachments.map(
            (attachment) => ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text((attachment['fileName'] ?? '附件').toString()),
              subtitle: Text(
                _formatSize((attachment['sizeBytes'] as num?)?.toInt() ?? 0),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 46,
          child: FilledButton(
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
                : const Text('发送行政通知'),
          ),
        ),
      ],
    );
  }

  Widget _pageHeader(String title, {required VoidCallback onBack}) => Row(
    children: [
      IconButton(
        onPressed: onBack,
        icon: const Icon(Icons.arrow_back_ios_new, size: 18),
      ),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: DunesColors.text,
          ),
        ),
      ),
    ],
  );

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
