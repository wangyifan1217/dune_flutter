import 'package:flutter/material.dart';

import '../../core/layout/chat_layout.dart';
import '../../core/platform/desktop_features.dart';
import '../../core/theme/dunes_theme.dart';
import '../conversation/conversation_models.dart';
import '../conversation/conversation_service.dart';
import 'im_ui_kit.dart';
import 'user_avatar_widget.dart';

const _textPrimary = Color(0xFF191919);
const _textSecondary = Color(0xFF888888);

/// PC 群信息内容左右内边距（全宽铺平，不再居中限宽）。
const double kGroupInfoWidePadding = 24;

/// 群信息页壳：宽屏居中限宽，窄屏自动适配 iOS 分组留白。
Widget groupInfoPageShell({required Widget child}) {
  return Builder(
    builder: (context) => ColoredBox(
      color: ImVisualTokens.groupedBackground(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (isDesktopCommOnly) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: child,
                ),
              ),
            );
          }
          final wide = isWideChatLayout(context);
          if (!wide) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: child,
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kGroupInfoWidePadding,
            ),
            child: child,
          );
        },
      ),
    ),
  );
}

/// iOS 风格群信息顶部卡片。
class GroupInfoHero extends StatelessWidget {
  const GroupInfoHero({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.groups_outlined,
    this.leading,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final accent = ImVisualTokens.accent(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      decoration: BoxDecoration(
        color: ImVisualTokens.cardSurface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ImVisualTokens.hairlineBorder(context),
          width: 0.7,
        ),
        boxShadow: ImVisualTokens.softCardShadow(context),
      ),
      child: Column(
        children: [
          leading ??
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: ImVisualTokens.accentSoftSurface(context),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 26, color: accent),
              ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: DunesTypography.sans(
              fontSize: 17.5,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(context, DunesColors.text),
              context: context,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
            decoration: BoxDecoration(
              color: ImVisualTokens.accentSoftSurface(context),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: DunesTypography.sans(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: ImVisualTokens.accentText(context),
                context: context,
              ),
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
          color: isDesktopCommOnly
              ? DunesColors.resolve(context, DunesColors.text3)
              : _textSecondary,
          context: context,
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
    final accent = ImVisualTokens.accent(context);
    final row = Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accentIcon
                  ? accent
                  : ImVisualTokens.accentSoftSurface(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: accentIcon ? Colors.white : accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: DunesTypography.sans(
                    fontSize: isDesktopCommOnly ? 14.5 : 15,
                    fontWeight: FontWeight.w500,
                    color: DunesColors.resolve(context, DunesColors.text),
                    context: context,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: DunesTypography.sans(
                      fontSize: 12,
                      color: DunesColors.resolve(context, DunesColors.text3),
                      context: context,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: DefaultTextStyle.merge(
                  textAlign: TextAlign.end,
                  child: trailing!,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return ImTapScale(
      borderRadius: BorderRadius.zero,
      pressedScale: 0.992,
      onTap: onTap,
      child: row,
    );
  }
}

class GroupInfoToggle extends StatelessWidget {
  const GroupInfoToggle({super.key, required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final dark = ImVisualTokens.isDark(context);
    final accent = ImVisualTokens.accent(context);
    return AnimatedContainer(
      duration: ImVisualTokens.fastAnim,
      curve: ImVisualTokens.iosCurve,
      width: 48,
      height: 28,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: value
            ? accent
            : (dark
                  ? Colors.white.withValues(alpha: 0.16)
                  : const Color(0xFFE2DFEC)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedAlign(
        duration: ImVisualTokens.fastAnim,
        curve: Curves.easeOutBack,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 23,
          height: 23,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 4,
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
    return Padding(
      padding: EdgeInsets.only(left: 4),
      child: Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: DunesColors.resolveNullable(context, Color(0xFFC7C7C7)),
      ),
    );
  }
}

/// 企微式成员网格：按可用宽度自适应列数，单元格均分铺满，避免右侧留白。
class GroupInfoMemberGrid extends StatelessWidget {
  const GroupInfoMemberGrid({
    super.key,
    required this.members,
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
      decoration: BoxDecoration(
        color: ImVisualTokens.cardSurface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ImVisualTokens.hairlineBorder(context),
          width: 0.7,
        ),
        boxShadow: ImVisualTokens.softCardShadow(context),
      ),
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
          final avatarSize = ((maxW / cols) * 0.58).clamp(40.0, 52.0);

          final cells = <Widget>[
            for (final m in members)
              _MemberCell(
                label: m.displayName,
                seed: m.userId,
                avatarSize: avatarSize,
                avatarPreset: m.avatarPreset,
                avatarObjectKey: m.avatarObjectKey,
                avatarService: avatarService,
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
    this.onTap,
  });

  final String label;
  final int seed;
  final ConversationService avatarService;
  final double avatarSize;
  final String? avatarPreset;
  final String? avatarObjectKey;
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
              color: isDesktopCommOnly
                  ? DunesColors.resolve(context, DunesColors.text)
                  : _textPrimary,
              context: context,
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
              color: DunesColors.resolve(
                context,
                DunesColors.bgApp,
                role: DunesColorRole.surface,
              ),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: DunesColors.resolve(
                  context,
                  const Color(0xFFE5E5E5),
                  role: DunesColorRole.border,
                ),
              ),
            ),
            child: Icon(
              icon,
              size: avatarSize * 0.46,
              color: DunesColors.resolveNullable(context, _textSecondary),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DunesTypography.sans(
              fontSize: 12,
              color: isDesktopCommOnly
                  ? DunesColors.resolve(context, DunesColors.text)
                  : _textPrimary,
              context: context,
            ),
          ),
        ],
      ),
    );
  }
}

class GroupInfoDangerRow extends StatelessWidget {
  const GroupInfoDangerRow({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ImTapScale(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: ImVisualTokens.cardSurface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFA5151).withValues(alpha: 0.20),
              width: 0.7,
            ),
            boxShadow: ImVisualTokens.softCardShadow(context),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: DunesTypography.sans(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: DunesColors.resolve(context, const Color(0xFFFA5151)),
              context: context,
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
  // 已读不回工作群（reply_sla）才标；旧 WORKGROUP / 普通群 / 审批群外观不变。
  if (info.replySla && info.kind.toUpperCase() == 'WORKGROUP') bits.add('工作群');
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
