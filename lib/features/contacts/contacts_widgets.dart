import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_service.dart';
import 'contact_models.dart';

class ContactsHeader extends StatelessWidget {
  const ContactsHeader({
    super.key,
    required this.total,
    required this.onBack,
    required this.onToggleSearch,
    this.searchOpen = false,
  });

  final int total;
  final VoidCallback onBack;
  final VoidCallback onToggleSearch;
  final bool searchOpen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 11),
      child: Row(
        children: [
          RichText(
            text: TextSpan(
              style: DunesTypography.sans(
                fontSize: 21,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.025 * 21,
                color: DunesColors.text,
              ),
              children: [
                const TextSpan(text: '通讯录'),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      'CONTACTS · $total',
                      style: DunesTypography.mono(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.06 * 9.5,
                        color: DunesColors.text3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _HeaderIconBtn(
            icon: Icons.arrow_back_rounded,
            onTap: onBack,
            tooltip: '返回消息',
          ),
          _HeaderIconBtn(
            icon: Icons.search,
            onTap: onToggleSearch,
            tooltip: '搜索人',
            active: searchOpen,
          ),
        ],
      ),
    );
  }
}

class OrgSectionLabel extends StatelessWidget {
  const OrgSectionLabel({super.key, required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 6),
      child: Row(
        children: [
          Text(
            '组织树',
            style: DunesTypography.sans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DunesColors.accent,
            ),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              height: 1,
              color: DunesColors.borderSoft,
            ),
          ),
          Text(
            '$total 人',
            style: DunesTypography.mono(
              fontSize: 9.5,
              color: DunesColors.text3,
            ),
          ),
        ],
      ),
    );
  }
}

class ContactRowTile extends StatelessWidget {
  const ContactRowTile({
    super.key,
    required this.contact,
    required this.currentUserId,
    required this.onOpenProfile,
    required this.onMessage,
    this.showOnline = false,
    this.avatarService,
  });

  final NativeContact contact;
  final int currentUserId;
  final VoidCallback onOpenProfile;
  final VoidCallback onMessage;
  final bool showOnline;
  final ConversationService? avatarService;

  @override
  Widget build(BuildContext context) {
    final isMe = contact.userId == currentUserId;
    final disabled = !contact.enabled;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: DunesColors.bgApp,
        child: InkWell(
          onTap: onOpenProfile,
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: DunesColors.borderSoft),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                ImUserAvatar(
                  initial: contact.displayLabel.isNotEmpty
                      ? contact.displayLabel.substring(0, 1)
                      : '?',
                  seed: contact.userId,
                  size: 34,
                  showOnline: showOnline,
                  avatarPreset: contact.avatarPreset,
                  avatarObjectKey: contact.avatarObjectKey,
                  avatarService: avatarService,
                  borderRadius: 34 * 0.18,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              contact.displayLabel,
                              style: DunesTypography.sans(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: disabled
                                    ? DunesColors.text3
                                    : DunesColors.text,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: DunesColors.accent,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '我',
                                style: DunesTypography.mono(
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 5,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (contact.primaryRole.isNotEmpty)
                            _RoleChip(label: contact.primaryRole),
                          if ((contact.department ?? '').trim().isNotEmpty)
                            Text(
                              contact.department!.trim(),
                              style: DunesTypography.mono(
                                fontSize: 9,
                                color: DunesColors.text3,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!isMe && contact.enabled) ...[
                  _ActionIconBtn(
                    icon: Icons.chat_bubble_outline,
                    primary: true,
                    onTap: onMessage,
                  ),
                ] else if (isMe) ...[
                  _ActionIconBtn(
                    icon: Icons.person_outline,
                    onTap: onOpenProfile,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DeptBlockTile extends StatefulWidget {
  const DeptBlockTile({
    super.key,
    required this.department,
    required this.currentUserId,
    required this.onOpenContact,
    required this.onMessageContact,
    this.onlineUsers = const <int>{},
    this.avatarService,
  });

  final NativeDepartment department;
  final int currentUserId;
  final ValueChanged<NativeContact> onOpenContact;
  final ValueChanged<NativeContact> onMessageContact;
  final Set<int> onlineUsers;
  final ConversationService? avatarService;

  @override
  State<DeptBlockTile> createState() => _DeptBlockTileState();
}

class _DeptBlockTileState extends State<DeptBlockTile> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.department.expanded;
  }

  @override
  Widget build(BuildContext context) {
    final dep = widget.department;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(9),
            child: Container(
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    DunesColors.bgSoft,
                    DunesColors.bgApp.withValues(alpha: 0.2),
                  ],
                ),
                border: Border.all(color: DunesColors.border),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.chevron_right,
                      size: 13,
                      color: DunesColors.text3,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: DunesColors.accentSoft,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: DunesColors.borderSoft),
                    ),
                    child: const Icon(
                      Icons.business_outlined,
                      size: 13,
                      color: DunesColors.accentDeep,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dep.name,
                          style: DunesTypography.sans(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if ((dep.subtitle ?? '').isNotEmpty)
                          Text(
                            dep.subtitle!,
                            style: DunesTypography.mono(
                              fontSize: 9,
                              color: DunesColors.text3,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '${dep.userCount}',
                    style: DunesTypography.mono(
                      fontSize: 9,
                      color: DunesColors.text3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: Column(
              children: [
                ...dep.users.map(
                  (c) => ContactRowTile(
                    contact: c,
                    currentUserId: widget.currentUserId,
                    showOnline: widget.onlineUsers.contains(c.userId),
                    onOpenProfile: () => widget.onOpenContact(c),
                    onMessage: () => widget.onMessageContact(c),
                    avatarService: widget.avatarService,
                  ),
                ),
                ...dep.children.map(
                  (child) => DeptBlockTile(
                    department: child,
                    currentUserId: widget.currentUserId,
                    onOpenContact: widget.onOpenContact,
                    onMessageContact: widget.onMessageContact,
                    onlineUsers: widget.onlineUsers,
                    avatarService: widget.avatarService,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: DunesColors.borderSoft),
      ),
      child: Text(
        label,
        style: DunesTypography.mono(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: DunesColors.text3,
        ),
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  const _HeaderIconBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? DunesColors.bgSoft : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 16, color: DunesColors.text2),
          ),
        ),
      ),
    );
  }
}

class _ActionIconBtn extends StatelessWidget {
  const _ActionIconBtn({
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? DunesColors.accentSoft : DunesColors.bgSoft,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: primary ? DunesColors.accent : DunesColors.borderSoft,
            ),
          ),
          child: Icon(
            icon,
            size: 13,
            color: primary ? DunesColors.accentDeep : DunesColors.text2,
          ),
        ),
      ),
    );
  }
}
