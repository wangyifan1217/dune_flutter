import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import 'robot_character.dart';
import 'robot_models.dart';

class RobotSearchField extends StatelessWidget {
  const RobotSearchField({super.key, this.hint = '搜索', this.onChanged});

  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: DunesTypography.sans(
          fontSize: 13,
          color: DunesColors.resolve(context, RobotTheme.text3),
          context: context,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 20,
          color: DunesColors.resolve(context, RobotTheme.text3),
        ),
        filled: true,
        fillColor: DunesColors.resolve(
          context,
          const Color(0xFFF0F1F3),
          role: DunesColorRole.surface,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class RobotScenarioCard extends StatelessWidget {
  const RobotScenarioCard({
    super.key,
    required this.scenario,
    required this.onRun,
    this.onTap,
  });

  final RobotScenario scenario;
  final VoidCallback onRun;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap ?? onRun,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: DunesColors.resolve(
                context,
                RobotTheme.cardBorder,
                role: DunesColorRole.border,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: DunesColors.resolve(
                          context,
                          const Color(0xFFFFF1C9),
                          role: DunesColorRole.surface,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: DunesColors.resolveNullable(
                          context,
                          Color(0xFFD4A017),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        scenario.title,
                        style: DunesTypography.sans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: DunesColors.resolve(context, RobotTheme.text),
                          context: context,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  scenario.desc,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: DunesTypography.sans(
                    fontSize: 12,
                    height: 1.45,
                    color: DunesColors.resolve(context, RobotTheme.text2),
                    context: context,
                  ),
                ),
                const SizedBox(height: 14),
                RobotAvatarStack(roleIds: scenario.roleIds),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.account_tree_outlined,
                      size: 14,
                      color: DunesColors.resolve(context, RobotTheme.text3),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${scenario.stepCount} 步',
                      style: DunesTypography.sans(
                        fontSize: 12,
                        color: DunesColors.resolve(context, RobotTheme.text3),
                        context: context,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: onRun,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('运行'),
                      style: FilledButton.styleFrom(
                        backgroundColor: DunesColors.resolve(
                          context,
                          RobotTheme.purple,
                          role: DunesColorRole.surface,
                        ),
                        foregroundColor: DunesColors.resolve(
                          context,
                          Colors.white,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RobotRoleCard extends StatelessWidget {
  const RobotRoleCard({
    super.key,
    required this.role,
    this.selected = false,
    this.onTap,
    this.onRun,
    this.showRun = false,
  });

  final RobotRole role;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRun;
  final bool showRun;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DunesColors.resolve(
        context,
        Colors.white,
        role: DunesColorRole.surface,
      ),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? DunesColors.resolve(
                      context,
                      RobotTheme.purple,
                      role: DunesColorRole.border,
                    )
                  : DunesColors.resolve(
                      context,
                      RobotTheme.cardBorder,
                      role: DunesColorRole.border,
                    ),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RobotFaceAvatar(role: role, size: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            role.category,
                            style: DunesTypography.sans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: DunesColors.resolve(
                                context,
                                RobotTheme.purple,
                              ),
                              context: context,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            role.name,
                            style: DunesTypography.sans(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: DunesColors.resolve(
                                context,
                                RobotTheme.text,
                              ),
                              context: context,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            role.desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DunesTypography.sans(
                              fontSize: 12,
                              height: 1.4,
                              color: DunesColors.resolve(
                                context,
                                RobotTheme.text2,
                              ),
                              context: context,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!showRun) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? DunesColors.resolve(
                                    context,
                                    RobotTheme.purple,
                                    role: DunesColorRole.border,
                                  )
                                : DunesColors.resolve(
                                    context,
                                    const Color(0xFFC9CDD3),
                                    role: DunesColorRole.border,
                                  ),
                            width: 1.5,
                          ),
                          color: selected
                              ? DunesColors.resolve(
                                  context,
                                  RobotTheme.purple,
                                  role: DunesColorRole.surface,
                                )
                              : Colors.transparent,
                        ),
                        child: selected
                            ? Icon(
                                Icons.check,
                                size: 12,
                                color: DunesColors.resolve(
                                  context,
                                  Colors.white,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ],
                ),
                if (showRun) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.smart_toy_outlined,
                        size: 14,
                        color: DunesColors.resolve(context, RobotTheme.text3),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '数字员工',
                        style: DunesTypography.sans(
                          fontSize: 12,
                          color: DunesColors.resolve(context, RobotTheme.text3),
                          context: context,
                        ),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: onRun,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('运行'),
                        style: FilledButton.styleFrom(
                          backgroundColor: DunesColors.resolve(
                            context,
                            RobotTheme.purple,
                            role: DunesColorRole.surface,
                          ),
                          foregroundColor: DunesColors.resolve(
                            context,
                            Colors.white,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
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

Color robotStatusColor(RobotNodeStatus status) {
  return switch (status) {
    RobotNodeStatus.pending => RobotTheme.text3,
    RobotNodeStatus.running => RobotTheme.purple,
    RobotNodeStatus.success => const Color(0xFF2E7544),
    RobotNodeStatus.failed => const Color(0xFFC44949),
    RobotNodeStatus.skipped => RobotTheme.text3,
  };
}

String robotStatusLabel(RobotNodeStatus status) {
  return switch (status) {
    RobotNodeStatus.pending => '等待中',
    RobotNodeStatus.running => '进行中',
    RobotNodeStatus.success => '已完成',
    RobotNodeStatus.failed => '失败',
    RobotNodeStatus.skipped => '已跳过',
  };
}

IconData robotStatusIcon(RobotNodeStatus status) {
  return switch (status) {
    RobotNodeStatus.pending => Icons.radio_button_unchecked,
    RobotNodeStatus.running => Icons.sync_rounded,
    RobotNodeStatus.success => Icons.check_circle_rounded,
    RobotNodeStatus.failed => Icons.cancel_rounded,
    RobotNodeStatus.skipped => Icons.remove_circle_outline,
  };
}
