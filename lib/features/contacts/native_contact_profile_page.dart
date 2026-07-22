import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../chat/chat_widgets.dart';
import '../chat/group_info_widgets.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_service.dart';
import 'contact_models.dart';
import 'contact_service.dart';

class NativeContactProfilePage extends StatefulWidget {
  const NativeContactProfilePage({
    super.key,
    required this.session,
    required this.contactHint,
    required this.onBack,
    required this.onOpenPrivateChat,
  });

  final AuthSession session;
  final NativeContact? contactHint;
  final VoidCallback onBack;
  final ValueChanged<int> onOpenPrivateChat;

  @override
  State<NativeContactProfilePage> createState() =>
      _NativeContactProfilePageState();
}

class _NativeContactProfilePageState extends State<NativeContactProfilePage> {
  late final ContactService _service;
  late final ConversationService _avatarService;
  NativeContact? _contact;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = ContactService(session: widget.session);
    _avatarService = ConversationService(session: widget.session);
    _load();
  }

  Future<void> _load() async {
    final hint = widget.contactHint;
    if (hint == null || hint.userId <= 0) {
      setState(() {
        _loading = false;
        _error = '联系人不存在';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fresh = await _service.fetchContact(hint.userId);
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
          avatarService: _avatarService,
        ),
        const SizedBox(height: 10),
        GroupInfoRow(
          icon: Icons.phone_outlined,
          title: '手机',
          trailing: Text(
            phone.isEmpty ? '-' : phone,
            style: DunesTypography.sans(
              fontSize: 15,
              color: const Color(0xFF888888),
            ),
          ),
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
        if (!isSelf)
          _ProfileMessageAction(
            onTap: () => widget.onOpenPrivateChat(c.userId),
          ),
      ],
    );
  }
}

/// 企微式联系人头部：白底、左头像右信息，无渐变。
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.department,
    required this.roleTag,
    required this.seed,
    this.avatarPreset,
    this.avatarObjectKey,
    this.avatarService,
  });

  final String name;
  final String department;
  final String roleTag;
  final int seed;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final ConversationService? avatarService;

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name.substring(0, 1) : '?';
    final subtitleBits = <String>[
      if (department.isNotEmpty) department,
      if (roleTag.isNotEmpty) roleTag,
    ];

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
            size: 64,
            avatarPreset: avatarPreset,
            avatarObjectKey: avatarObjectKey,
            avatarService: avatarService,
            borderRadius: 8,
          ),
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
