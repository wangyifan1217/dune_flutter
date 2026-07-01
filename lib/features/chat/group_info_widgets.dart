import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import 'user_avatar_widget.dart';

const _bgSunken = Color(0xFFE8E4D9);

/// 群信息 hero，对齐 `.group-info-hero`。
class GroupInfoHero extends StatelessWidget {
  const GroupInfoHero({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.assignment_outlined,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DunesColors.accentDeep, DunesColors.accent],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -40,
            right: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Colors.white.withValues(alpha: 0.16), Colors.transparent],
                  stops: const [0.0, 0.65],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: DunesTypography.sans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.01 * 14,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: DunesTypography.mono(
                    fontSize: 9.5,
                    color: Colors.white.withValues(alpha: 0.7),
                    letterSpacing: 0.02 * 9.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 对齐 `.gi-section`。
class GroupInfoSectionLabel extends StatelessWidget {
  const GroupInfoSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty) {
      return Container(
        height: 8,
        decoration: const BoxDecoration(
          color: _bgSunken,
          border: Border(
            top: BorderSide(color: DunesColors.borderSoft),
            bottom: BorderSide(color: DunesColors.borderSoft),
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 7),
      decoration: const BoxDecoration(
        color: _bgSunken,
        border: Border(
          top: BorderSide(color: DunesColors.borderSoft),
          bottom: BorderSide(color: DunesColors.borderSoft),
        ),
      ),
      child: Text(
        label.toUpperCase(),
        style: DunesTypography.mono(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: DunesColors.text3,
          letterSpacing: 0.06 * 8.5,
        ),
      ),
    );
  }
}

/// 对齐 `.gi-row`。
class GroupInfoRow extends StatelessWidget {
  const GroupInfoRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.accentIcon = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool accentIcon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accentIcon ? DunesColors.accentSoft : DunesColors.bgSoft,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: accentIcon ? DunesColors.accentLine : DunesColors.borderSoft),
            ),
            child: Icon(icon, size: 14, color: accentIcon ? DunesColors.accentDeep : DunesColors.text2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DunesTypography.sans(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: DunesColors.text,
                    letterSpacing: -0.005 * 11.5,
                    height: 1.3,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle!,
                    style: DunesTypography.mono(fontSize: 9, color: DunesColors.text3, letterSpacing: 0.02 * 9),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

/// 对齐 `.toggle`。
class GroupInfoToggle extends StatelessWidget {
  const GroupInfoToggle({super.key, required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 32,
      height: 18,
      decoration: BoxDecoration(
        color: value ? DunesColors.accent : DunesColors.bgSoft,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: value ? DunesColors.accent : DunesColors.border),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 150),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 14,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 2, offset: const Offset(0, 1))],
          ),
        ),
      ),
    );
  }
}

class GroupInfoChevron extends StatelessWidget {
  const GroupInfoChevron({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 4),
      child: Icon(Icons.chevron_right_rounded, size: 16, color: DunesColors.text3),
    );
  }
}

/// 对齐 `.gi-member-grid`。
class GroupInfoMemberGrid extends StatelessWidget {
  const GroupInfoMemberGrid({
    super.key,
    required this.members,
    required this.selfUserId,
    required this.avatarService,
    this.showAdd = false,
    this.showRemove = false,
    this.onMemberTap,
    this.onAdd,
    this.onRemove,
  });

  final List<NativeGroupMember> members;
  final int selfUserId;
  final ConversationService avatarService;
  final bool showAdd;
  final bool showRemove;
  final ValueChanged<NativeGroupMember>? onMemberTap;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      decoration: const BoxDecoration(
        color: DunesColors.bgApp,
        border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 9,
          crossAxisSpacing: 9,
          childAspectRatio: 0.72,
        ),
        itemCount: members.length + (showAdd ? 1 : 0) + (showRemove ? 1 : 0),
        itemBuilder: (_, i) {
          var idx = i;
          if (idx < members.length) {
            final m = members[idx];
            return _MemberCell(
              label: m.displayName,
              seed: m.userId,
              avatarPreset: m.avatarPreset,
              avatarObjectKey: m.avatarObjectKey,
              avatarService: avatarService,
              suffix: m.userId == selfUserId ? '·我' : null,
              onTap: onMemberTap == null ? null : () => onMemberTap!(m),
            );
          }
          idx -= members.length;
          if (showAdd && idx == 0) {
            return _ActionMemberCell(icon: Icons.add, label: '添加', dashed: true, onTap: onAdd);
          }
          return _ActionMemberCell(
            icon: Icons.remove,
            label: '移除',
            dashed: true,
            danger: true,
            onTap: onRemove,
          );
        },
      ),
    );
  }
}

class _MemberCell extends StatelessWidget {
  const _MemberCell({
    required this.label,
    required this.seed,
    required this.avatarService,
    this.avatarPreset,
    this.avatarObjectKey,
    this.suffix,
    this.onTap,
  });

  final String label;
  final int seed;
  final ConversationService avatarService;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final String? suffix;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initial = label.isNotEmpty ? label.substring(0, 1) : '?';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          ImUserAvatar(
            initial: initial,
            seed: seed,
            size: 38,
            avatarPreset: avatarPreset,
            avatarObjectKey: avatarObjectKey,
            avatarService: avatarService,
            borderRadius: 38 * 0.18,
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 48,
            child: RichText(
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: DunesTypography.sans(fontSize: 9.5, fontWeight: FontWeight.w500, color: DunesColors.text2),
                children: [
                  TextSpan(text: label),
                  if (suffix != null)
                    TextSpan(
                      text: suffix,
                      style: DunesTypography.sans(
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionMemberCell extends StatelessWidget {
  const _ActionMemberCell({
    required this.icon,
    required this.label,
    this.dashed = false,
    this.danger = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool dashed;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: DunesColors.bgSoft,
              shape: BoxShape.circle,
              border: dashed
                  ? Border.all(
                      color: danger ? DunesColors.coral : DunesColors.border,
                      width: 1.5,
                      strokeAlign: BorderSide.strokeAlignInside,
                    )
                  : null,
            ),
            child: Icon(icon, size: 18, color: danger ? DunesColors.coral : DunesColors.text3),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(fontSize: 9.5, fontWeight: FontWeight.w500, color: DunesColors.text2),
          ),
        ],
      ),
    );
  }
}

/// 对齐 `.gi-danger`。
class GroupInfoDangerRow extends StatelessWidget {
  const GroupInfoDangerRow({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DunesColors.bgApp,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: DunesColors.borderSoft)),
          ),
          child: Text(
            label,
            style: DunesTypography.sans(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: DunesColors.coral,
              letterSpacing: -0.005 * 11.5,
            ),
          ),
        ),
      ),
    );
  }
}

List<NativeGroupMember> sortGroupMembers(List<NativeGroupMember> members) {
  final out = [...members];
  out.sort((a, b) {
    if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
    return a.displayName.compareTo(b.displayName);
  });
  return out;
}

String groupInfoHeroSubtitle(NativeGroupInfo info) {
  final bits = <String>[];
  if (info.dissolved) bits.add('已解散');
  bits.add(info.kindLabel);
  if (info.createdAt != null) {
    final d = info.createdAt!.toLocal();
    final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    bits.add('创建于 $date');
  }
  return bits.join(' · ');
}

IconData groupInfoHeroIcon(String kind) {
  if (kind == 'WORKGROUP_APPROVAL') return Icons.assignment_outlined;
  return Icons.groups_outlined;
}
