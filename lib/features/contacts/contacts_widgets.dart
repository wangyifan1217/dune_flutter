import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../chat/user_avatar_widget.dart';
import '../conversation/conversation_service.dart';
import 'contact_models.dart';

/// 通讯录无自定义头像时的统一底色（与 [InboxFormat.personStyle] 一致）。
const _contactsFallbackBg = DunesColors.brandPurple;
const _contactsFallbackFg = Colors.white;

class ContactsHeader extends StatelessWidget {
  const ContactsHeader({
    super.key,
    required this.total,
    required this.onBack,
    required this.onToggleSearch,
    this.searchOpen = false,
    this.groupPickMode = false,
    this.creating = false,
    this.onCreateGroup,
    this.onConfirmCreate,
  });

  final int total;
  final VoidCallback onBack;
  final VoidCallback onToggleSearch;
  final bool searchOpen;
  final bool groupPickMode;
  final bool creating;
  final VoidCallback? onCreateGroup;
  final VoidCallback? onConfirmCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      child: SizedBox(
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: _HeaderIconBtn(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: onBack,
                tooltip: '返回',
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  groupPickMode ? '创建群聊' : '通讯录',
                  style: DunesTypography.sans(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  groupPickMode ? '选择成员' : '$total 人',
                  style: DunesTypography.sans(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: groupPickMode
                  ? Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: creating
                          ? const SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          : _HeaderIconBtn(
                              icon: Icons.check_rounded,
                              onTap: onConfirmCreate ?? () {},
                              tooltip: '完成',
                              active: true,
                              activeColor: DunesColors.accent,
                            ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onCreateGroup != null)
                          _HeaderIconBtn(
                            icon: Icons.group_add_outlined,
                            onTap: onCreateGroup!,
                            tooltip: '创建群聊',
                          ),
                        _HeaderIconBtn(
                          icon: Icons.search_rounded,
                          onTap: onToggleSearch,
                          tooltip: '搜索',
                          active: searchOpen,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExternalSectionLabel extends StatelessWidget {
  const ExternalSectionLabel({super.key, required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Text(
            '外部用户',
            style: DunesTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$total',
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFF7B5CD8),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '组织架构',
            style: DunesTypography.sans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DunesColors.text2,
            ),
          ),
          const Spacer(),
          Text(
            '$total 人',
            style: DunesTypography.sans(fontSize: 12, color: DunesColors.text3),
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
    this.pickMode = false,
    this.selected = false,
    this.onToggleSelect,
  });

  final NativeContact contact;
  final int currentUserId;
  final VoidCallback onOpenProfile;
  final VoidCallback onMessage;
  final bool showOnline;
  final ConversationService? avatarService;
  final bool pickMode;
  final bool selected;
  final VoidCallback? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final isMe = contact.userId == currentUserId;
    final disabled = !contact.enabled || (pickMode && isMe);
    final onTap = pickMode
        ? (disabled ? null : onToggleSelect)
        : onOpenProfile;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                if (pickMode) ...[
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? DunesColors.accent : Colors.white,
                      border: Border.all(
                        color: selected ? DunesColors.accent : DunesColors.border,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 10),
                ],
                ImUserAvatar(
                  initial: contact.displayLabel.isNotEmpty
                      ? contact.displayLabel.substring(0, 1)
                      : '?',
                  seed: contact.userId,
                  size: 40,
                  showOnline: showOnline,
                  avatarPreset: contact.avatarPreset,
                  avatarObjectKey: contact.avatarObjectKey,
                  avatarService: avatarService,
                  borderRadius: 10,
                  fallbackBackground: _contactsFallbackBg,
                  fallbackForeground: _contactsFallbackFg,
                ),
                const SizedBox(width: 12),
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
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: disabled
                                    ? DunesColors.text3
                                    : DunesColors.text,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF7B5CD8).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '我',
                                style: DunesTypography.sans(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF7B5CD8),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (contact.primaryRole.isNotEmpty) contact.primaryRole,
                          if ((contact.department ?? '').trim().isNotEmpty)
                            contact.department!.trim(),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DunesTypography.sans(
                          fontSize: 12,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!pickMode && !isMe && contact.enabled)
                  _ActionIconBtn(
                    icon: Icons.chat_bubble_outline_rounded,
                    primary: true,
                    onTap: onMessage,
                  )
                else if (!pickMode && isMe)
                  _ActionIconBtn(
                    icon: Icons.person_outline_rounded,
                    onTap: onOpenProfile,
                  ),
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
    this.pickMode = false,
    this.selectedUserIds = const <int>{},
    this.onToggleContact,
  });

  final NativeDepartment department;
  final int currentUserId;
  final ValueChanged<NativeContact> onOpenContact;
  final ValueChanged<NativeContact> onMessageContact;
  final Set<int> onlineUsers;
  final ConversationService? avatarService;
  final bool pickMode;
  final Set<int> selectedUserIds;
  final ValueChanged<NativeContact>? onToggleContact;

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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: DunesColors.text3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B5CD8).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      size: 16,
                      color: Color(0xFF7B5CD8),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      dep.name,
                      style: DunesTypography.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                  Text(
                    '${dep.userCount}',
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: DunesColors.text3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F7FB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                for (var i = 0; i < dep.users.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      indent: 66,
                      color: Color(0xFFEDECF2),
                    ),
                  ContactRowTile(
                    contact: dep.users[i],
                    currentUserId: widget.currentUserId,
                    showOnline: widget.onlineUsers.contains(dep.users[i].userId),
                    onOpenProfile: () => widget.onOpenContact(dep.users[i]),
                    onMessage: () => widget.onMessageContact(dep.users[i]),
                    avatarService: widget.avatarService,
                    pickMode: widget.pickMode,
                    selected: widget.selectedUserIds.contains(dep.users[i].userId),
                    onToggleSelect: widget.onToggleContact == null
                        ? null
                        : () => widget.onToggleContact!(dep.users[i]),
                  ),
                ],
                for (final child in dep.children)
                  DeptBlockTile(
                    department: child,
                    currentUserId: widget.currentUserId,
                    onOpenContact: widget.onOpenContact,
                    onMessageContact: widget.onMessageContact,
                    onlineUsers: widget.onlineUsers,
                    avatarService: widget.avatarService,
                    pickMode: widget.pickMode,
                    selectedUserIds: widget.selectedUserIds,
                    onToggleContact: widget.onToggleContact,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  const _HeaderIconBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final accent = activeColor ?? const Color(0xFF7B5CD8);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? accent.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: icon == Icons.arrow_back_ios_new_rounded ? 18 : 22,
              color: active ? accent : DunesColors.text2,
            ),
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
      color: primary
          ? const Color(0xFF7B5CD8).withValues(alpha: 0.1)
          : const Color(0xFFF0F1F3),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 16,
            color: primary ? const Color(0xFF7B5CD8) : DunesColors.text2,
          ),
        ),
      ),
    );
  }
}
