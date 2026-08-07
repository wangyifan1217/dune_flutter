import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/chat_widgets.dart';
import '../chat/group_info_widgets.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_service.dart';
import '../shell/dunes_toast.dart';
import 'contact_models.dart';
import 'contact_service.dart';

class NativeContactProfilePage extends StatefulWidget {
  const NativeContactProfilePage({
    super.key,
    required this.session,
    required this.contactHint,
    required this.onBack,
    required this.onOpenPrivateChat,
    this.conversationId,
    this.onOpenSearch,
    this.onChatSettingsChanged,
    this.onCreateGroupWithContact,
  });

  final AuthSession session;
  final NativeContact? contactHint;
  final VoidCallback onBack;
  final ValueChanged<int> onOpenPrivateChat;

  /// 从私聊打开时传入，用于展示免打扰 / 置顶 / 查找聊天内容。
  final int? conversationId;
  final ValueChanged<int>? onOpenSearch;
  final void Function({required int conversationId, bool? muted, bool? pinned})?
      onChatSettingsChanged;

  /// 企微式：头像旁「+」→ 通讯录选人，与当前联系人组成群聊。
  final ValueChanged<NativeContact>? onCreateGroupWithContact;

  @override
  State<NativeContactProfilePage> createState() =>
      _NativeContactProfilePageState();
}

class _NativeContactProfilePageState extends State<NativeContactProfilePage> {
  late final ContactService _service;
  late final ConversationService _conversationService;
  NativeContact? _contact;
  bool _loading = true;
  String? _error;

  bool _muted = false;
  bool _pinned = false;
  bool _settingsLoaded = false;

  bool get _showChatSettings {
    final id = widget.conversationId;
    return id != null && id > 0;
  }

  @override
  void initState() {
    super.initState();
    _service = ContactService(session: widget.session);
    _conversationService = ConversationService(session: widget.session);
    _load();
  }

  @override
  void didUpdateWidget(covariant NativeContactProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId ||
        oldWidget.contactHint?.userId != widget.contactHint?.userId) {
      _load();
    }
  }

  Future<void> _load() async {
    final hint = widget.contactHint;
    if (hint == null || hint.userId <= 0) {
      setState(() {
        _loading = false;
        _error = '联系人不存在';
        _settingsLoaded = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fresh = await _service.fetchContact(hint.userId);
      if (_showChatSettings) {
        await _loadChatSettings();
      } else if (mounted) {
        setState(() => _settingsLoaded = false);
      }
      if (!mounted) return;
      setState(() {
        _contact = fresh ?? hint;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _contact = hint;
        _error = friendlyErrorText(e);
        _loading = false;
      });
    }
  }

  Future<void> _onPhoneTap(String phone) async {
    final digits = phone.trim();
    if (digits.isEmpty || digits == '-') return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                digits,
                style: DunesTypography.sans(
                  fontSize: 13,
                  color: DunesColors.text3,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: const Text('呼叫'),
              onTap: () => Navigator.of(context).pop('call'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('复制号码'),
              onTap: () => Navigator.of(context).pop('copy'),
            ),
            ListTile(
              title: const Text('取消', textAlign: TextAlign.center),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'call':
        final uri = Uri(scheme: 'tel', path: digits);
        final ok = await launchUrl(uri);
        if (!mounted) return;
        if (!ok) {
          showDunesToast(context, '无法打开拨号', kind: DunesToastKind.error);
        }
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: digits));
        if (!mounted) return;
        showDunesToast(context, '已复制');
        break;
    }
  }

  Future<void> _loadChatSettings() async {
    final id = widget.conversationId;
    if (id == null || id <= 0) return;
    try {
      final conv = await _conversationService.fetchConversation(id);
      if (!mounted) return;
      setState(() {
        _muted = conv?.muted ?? false;
        _pinned = conv?.pinned ?? false;
        _settingsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _settingsLoaded = true);
    }
  }

  Future<void> _toggleMuted() async {
    final id = widget.conversationId;
    if (id == null || id <= 0) return;
    final next = !_muted;
    setState(() => _muted = next);
    try {
      await _conversationService.patchMySettings(id, muted: next);
      widget.onChatSettingsChanged?.call(
        conversationId: id,
        muted: next,
        pinned: _pinned,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _muted = !next);
      _toast(context, '设置失败');
    }
  }

  Future<void> _togglePinned() async {
    final id = widget.conversationId;
    if (id == null || id <= 0) return;
    final next = !_pinned;
    setState(() => _pinned = next);
    try {
      await _conversationService.patchMySettings(id, pinned: next);
      widget.onChatSettingsChanged?.call(
        conversationId: id,
        muted: _muted,
        pinned: next,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _pinned = !next);
      _toast(context, '设置失败');
    }
  }

  void _toast(BuildContext context, String message) {
    showDunesToast(
      context,
      message,
      kind: dunesToastLooksLikeError(message)
          ? DunesToastKind.error
          : DunesToastKind.normal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.contactHint;
    final subtitle = (_contact?.department ?? hint?.department ?? '')
        .trim()
        .isNotEmpty
        ? (_contact?.department ?? hint?.department)!.trim()
        : '联系人';

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ChatConvHeader(
              title: '详细资料',
              subtitle: subtitle,
              onBack: widget.onBack,
            ),
            Expanded(child: groupInfoPageShell(child: _buildBody())),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: DunesColors.accent,
        ),
      );
    }
    if (_contact == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error ?? '联系人不存在',
              style: const TextStyle(color: DunesColors.text3, fontSize: 12),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: widget.onBack, child: const Text('返回')),
          ],
        ),
      );
    }

    final c = _contact!;
    final name = c.displayLabel.isEmpty ? '未命名' : c.displayLabel;
    final title = c.primaryRole.trim();
    final department = (c.department ?? '').trim();
    final phone = (c.phone ?? '').trim();
    final isSelf = c.userId == widget.session.userId;
    final convId = widget.conversationId;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _ProfileHero(
          name: name,
          department: department,
          roleTag: title,
          seed: c.userId,
          avatarPreset: c.avatarPreset,
          avatarObjectKey: c.avatarObjectKey,
          avatarService: _conversationService,
          onAddToGroup: isSelf || widget.onCreateGroupWithContact == null
              ? null
              : () => widget.onCreateGroupWithContact!(c),
        ),
        const SizedBox(height: 10),
        GroupInfoRow(
          icon: Icons.phone_outlined,
          title: '手机',
          trailing: Text(
            phone.isEmpty ? '-' : phone,
            style: DunesTypography.sans(
              fontSize: 15,
              color: phone.isEmpty
                  ? const Color(0xFF888888)
                  : DunesColors.blue,
            ),
          ),
          onTap: phone.isEmpty ? null : () => _onPhoneTap(phone),
        ),
        GroupInfoRow(
          icon: Icons.apartment_outlined,
          title: '部门',
          trailing: Text(
            department.isEmpty ? '-' : department,
            style: DunesTypography.sans(
              fontSize: 15,
              color: const Color(0xFF888888),
            ),
          ),
        ),
        GroupInfoRow(
          icon: Icons.badge_outlined,
          title: '职位',
          trailing: Text(
            title.isEmpty ? '-' : title,
            style: DunesTypography.sans(
              fontSize: 15,
              color: const Color(0xFF888888),
            ),
          ),
        ),
        if (_showChatSettings && _settingsLoaded) ...[
          const SizedBox(height: 10),
          GroupInfoRow(
            icon: Icons.notifications_off_outlined,
            title: '消息免打扰',
            trailing: GroupInfoToggle(value: _muted),
            onTap: _toggleMuted,
          ),
          GroupInfoRow(
            icon: Icons.push_pin_outlined,
            title: '置顶聊天',
            trailing: GroupInfoToggle(value: _pinned),
            onTap: _togglePinned,
          ),
          const SizedBox(height: 10),
          GroupInfoRow(
            icon: Icons.search,
            title: '查找聊天内容',
            trailing: const GroupInfoChevron(),
            onTap: widget.onOpenSearch == null || convId == null
                ? null
                : () => widget.onOpenSearch!(convId),
          ),
        ],
        if (!isSelf)
          _ProfileMessageAction(
            onTap: () => widget.onOpenPrivateChat(c.userId),
          ),
      ],
    );
  }
}

/// 企微式联系人头部：白底、左头像（可带头像旁 +）右信息。
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.department,
    required this.roleTag,
    required this.seed,
    this.avatarPreset,
    this.avatarObjectKey,
    this.avatarService,
    this.onAddToGroup,
  });

  final String name;
  final String department;
  final String roleTag;
  final int seed;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final ConversationService? avatarService;
  final VoidCallback? onAddToGroup;

  static const double _avatarSize = kImListAvatarSize;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.substring(0, 1) : '?';
    final subtitleBits = <String>[
      if (department.isNotEmpty) department,
      if (roleTag.isNotEmpty) roleTag,
    ];
    final avatarRadius = _avatarSize * 0.18;

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ImUserAvatar(
            initial: initial,
            seed: seed,
            size: _avatarSize,
            avatarPreset: avatarPreset,
            avatarObjectKey: avatarObjectKey,
            avatarService: avatarService,
            borderRadius: avatarRadius,
          ),
          if (onAddToGroup != null) ...[
            const SizedBox(width: 12),
            _ProfileAddCell(size: _avatarSize, onTap: onAddToGroup!),
          ],
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF191919),
                  ),
                ),
                if (subtitleBits.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitleBits.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: DunesTypography.sans(
                      fontSize: 13,
                      color: const Color(0xFF888888),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 企微式「头像旁 +」：选通讯录与当前人组成群。
class _ProfileAddCell extends StatelessWidget {
  const _ProfileAddCell({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.18;
    return Tooltip(
      message: '添加成员发起群聊',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: const Color(0xFFE5E5E5)),
            ),
            child: Icon(
              Icons.add,
              size: size * 0.48,
              color: const Color(0xFF888888),
            ),
          ),
        ),
      ),
    );
  }
}

/// 企微式底部主操作：白底居中「发消息」。
class _ProfileMessageAction extends StatelessWidget {
  const _ProfileMessageAction({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            alignment: Alignment.center,
            child: Text(
              '发消息',
              style: DunesTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: DunesColors.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
