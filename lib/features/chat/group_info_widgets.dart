import 'package:flutter/material.dart';

import '../../core/layout/chat_layout.dart';
import '../../core/theme/dunes_theme.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import 'user_avatar_widget.dart';

/// 企微风格浅灰底。
const _bgPage = Color(0xFFF2F2F2);
const _bgCard = Colors.white;
const _rowDivider = Color(0xFFEFEFEF);
const _textPrimary = Color(0xFF191919);
const _textSecondary = Color(0xFF888888);

/// PC 群信息内容左右内边距（全宽铺平，不再居中限宽）。
const double kGroupInfoWidePadding = 24;

/// 群信息页壳：宽屏全宽铺平，窄屏保持原样。
Widget groupInfoPageShell({required Widget child}) {
  return ColoredBox(
    color: _bgPage,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide = isWideChatLayout(context);
        if (!wide) return child;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: kGroupInfoWidePadding),
          child: child,
        );
      },
    ),
  );
}

/// 企微式群信息顶部：无渐变 hero，仅白底成员区上方的轻提示。
class GroupInfoHero extends StatelessWidget {
  const GroupInfoHero({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.groups_outlined,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _bgCard,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 12,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 区块间距（企微灰条）。
class GroupInfoSectionLabel extends StatelessWidget {
  const GroupInfoSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty) {
      return const SizedBox(height: 10);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Text(
        label,
        style: DunesTypography.sans(
          fontSize: 13,
          color: _textSecondary,
        ),
      ),
    );
  }
}

/// 企微式设置行：左文案，右值/开关 + 箭头。
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
      color: _bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DunesTypography.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: _textPrimary,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: _textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
    final bordered = DecoratedBox(
      decoration: const BoxDecoration(
        color: _bgCard,
        border: Border(bottom: BorderSide(color: _rowDivider, width: 0.5)),
      ),
      child: row,
    );
    if (onTap == null) return bordered;
    return Material(
      color: _bgCard,
      child: InkWell(onTap: onTap, child: bordered),
    );
  }
}

class GroupInfoToggle extends StatelessWidget {
  const GroupInfoToggle({super.key, required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 46,
      height: 28,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? const Color(0xFF07C160) : const Color(0xFFE5E5E5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 150),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
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
      child: Icon(Icons.chevron_right_rounded, size: 18, color: Color(0xFFC7C7C7)),
    );
  }
}

/// 企微式成员网格：按可用宽度自适应列数，单元格均分铺满，避免右侧留白。
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

  /// 期望单元格宽度；实际列数按容器宽度推算，再均分铺满。
  static const double preferredCellWidth = 64;
  static const double cellGap = 8;
  static const int minColumns = 4;
  static const int maxColumns = 6;

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
      width: double.infinity,
      color: _bgCard,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth;
          var cols = (maxW / preferredCellWidth).floor();
          cols = cols.clamp(minColumns, maxColumns);
          final totalItems =
              members.length + (showAdd ? 1 : 0) + (showRemove ? 1 : 0);
          // 人数很少时按实际人数分列，同样铺满一行。
          if (totalItems > 0 && totalItems < cols) {
            cols = totalItems;
          }
          final avatarSize =
              ((maxW / cols) * 0.58).clamp(40.0, 52.0);

          final cells = <Widget>[
            for (final m in members)
              _MemberCell(
                label: m.displayName,
                seed: m.userId,
                avatarSize: avatarSize,
                avatarPreset: m.avatarPreset,
                avatarObjectKey: m.avatarObjectKey,
                avatarService: avatarService,
                isOwner: m.isOwner,
                isSelf: m.userId == selfUserId,
                onTap: onMemberTap == null ? null : () => onMemberTap!(m),
              ),
            if (showAdd)
              _ActionMemberCell(
                icon: Icons.add,
                label: '添加',
                avatarSize: avatarSize,
                onTap: onAdd,
              ),
            if (showRemove)
              _ActionMemberCell(
                icon: Icons.remove,
                label: '移除',
                avatarSize: avatarSize,
                onTap: onRemove,
              ),
          ];

          final rows = <Widget>[];
          for (var i = 0; i < cells.length; i += cols) {
            final rowChildren = <Widget>[];
            for (var j = 0; j < cols; j++) {
              if (j > 0) rowChildren.add(const SizedBox(width: cellGap));
              final idx = i + j;
              rowChildren.add(
                Expanded(
                  child: idx < cells.length
                      ? cells[idx]
                      : const SizedBox.shrink(),
                ),
              );
            }
            rows.add(
              Padding(
                padding: EdgeInsets.only(
                  bottom: i + cols < cells.length ? 14 : 0,
                ),
                child: Row(children: rowChildren),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
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
    required this.avatarSize,
    this.avatarPreset,
    this.avatarObjectKey,
    this.isOwner = false,
    this.isSelf = false,
    this.onTap,
  });

  final String label;
  final int seed;
  final ConversationService avatarService;
  final double avatarSize;
  final String? avatarPreset;
  final String? avatarObjectKey;
  final bool isOwner;
  final bool isSelf;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initial = label.isNotEmpty ? label.substring(0, 1) : '?';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ImUserAvatar(
            initial: initial,
            seed: seed,
            size: avatarSize,
            avatarPreset: avatarPreset,
            avatarObjectKey: avatarObjectKey,
            avatarService: avatarService,
            borderRadius: 6,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: 12,
              color: _textPrimary,
            ),
          ),
          if (isOwner || isSelf)
            Text(
              isOwner ? '群主' : '我',
              style: DunesTypography.sans(
                fontSize: 10,
                color: _textSecondary,
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
    required this.avatarSize,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final double avatarSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE5E5E5)),
            ),
            child: Icon(icon, size: avatarSize * 0.46, color: _textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(fontSize: 12, color: _textPrimary),
          ),
        ],
      ),
    );
  }
}

class GroupInfoDangerRow extends StatelessWidget {
  const GroupInfoDangerRow({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: _bgCard,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            alignment: Alignment.center,
            child: Text(
              label,
              style: DunesTypography.sans(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: const Color(0xFFFA5151),
              ),
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
  bits.add('${info.members.length} 名成员');
  return bits.join(' · ');
}

IconData groupInfoHeroIcon(String kind) {
  switch (kind.toUpperCase()) {
    case 'APPROVAL':
      return Icons.assignment_outlined;
    case 'BROADCAST':
      return Icons.campaign_outlined;
    default:
      return Icons.groups_outlined;
  }
}
