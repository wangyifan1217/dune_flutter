import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'task_avatar.dart';
import 'task_models.dart';

const kTaskPurple = Color(0xFF7B5CD8);

/// 按进度分段取色：低→红橙、中→琥珀、高→青绿；办结→翠绿；逾期未办结偏琥珀棕。
/// 填报 100% 不等于办结，逾期时即使进度拉满也走逾期色。
Color taskProgressTone(
  num progressPct, {
  bool overdue = false,
  bool completed = false,
}) {
  if (completed) return const Color(0xFF1F9D76);
  if (overdue) return const Color(0xFFB45309);
  final p = progressPct.toDouble().clamp(0, 100);
  if (p >= 100) return const Color(0xFF2F8F7E);
  if (p < 30) return const Color(0xFFE35D4C);
  if (p < 60) return const Color(0xFFE0A020);
  if (p < 85) return const Color(0xFF4C7FD4);
  return const Color(0xFF2F8F7E);
}

List<Color> taskProgressGradientColors(
  num progressPct, {
  bool overdue = false,
  bool completed = false,
}) {
  if (completed) {
    return const [Color(0xFF1F9D76), Color(0xFF6ED4B0)];
  }
  if (overdue) {
    return const [Color(0xFFB45309), Color(0xFFE8A868)];
  }
  final p = progressPct.toDouble().clamp(0, 100);
  if (p >= 100) return const [Color(0xFF2F8F7E), Color(0xFF7BCFBC)];
  if (p < 30) return const [Color(0xFFE35D4C), Color(0xFFF0A08A)];
  if (p < 60) return const [Color(0xFFE0A020), Color(0xFFF5D08A)];
  if (p < 85) return const [Color(0xFF4C7FD4), Color(0xFF9BB8F0)];
  return const [Color(0xFF2F8F7E), Color(0xFF7BCFBC)];
}

class TaskProgressBar extends StatelessWidget {
  const TaskProgressBar({
    super.key,
    required this.progressPct,
    this.height = 8,
    this.overdue = false,
    this.completed = false,
    this.showLabel = true,
  });

  final int progressPct;
  final double height;
  final bool overdue;
  final bool completed;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final pct = progressPct.clamp(0, 100) / 100.0;
    final tone = taskProgressTone(
      progressPct,
      overdue: overdue,
      completed: completed,
    );
    final colors = taskProgressGradientColors(
      progressPct,
      overdue: overdue,
      completed: completed,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFFE8EAED),
            borderRadius: BorderRadius.circular(999),
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final w = (c.maxWidth * pct).clamp(0.0, c.maxWidth);
              return Align(
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  width: w <= 0 ? 0 : (w < height ? height : w),
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: colors,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 4),
          Text(
            '$progressPct%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: tone,
            ),
          ),
        ],
      ],
    );
  }
}

/// 竖向进度柱：主任务下每个子任务一根柱（同一人多子任务 = 多根柱）。
class TaskProgressBarItem {
  const TaskProgressBarItem({
    required this.taskId,
    required this.userId,
    required this.userName,
    required this.taskTitle,
    required this.progressPct,
    this.startAt,
    this.dueAt,
    this.overdue = false,
    this.colorIndex = 0,
  });

  final int taskId;
  final int userId;
  final String userName;
  final String taskTitle;
  final int progressPct;
  final DateTime? startAt;
  final DateTime? dueAt;
  final bool overdue;
  final int colorIndex;
}

const _kBarPalette = <Color>[
  Color(0xFF7B5CD8),
  Color(0xFF3B6FD4),
  Color(0xFF2F8F7E),
  Color(0xFFD4A017),
  Color(0xFFE85D4C),
  Color(0xFF5B8FA8),
];

/// 主任务：每个子任务一根柱；子任务详情：仅当前任务。
List<TaskProgressBarItem> buildTaskProgressBars(TaskDetail detail) {
  final task = detail.task;
  final source = task.isMain && detail.subtasks.isNotEmpty
      ? detail.subtasks
      : <TaskItem>[task];

  final colorOf = <int, int>{};
  var nextColor = 0;
  final out = <TaskProgressBarItem>[];
  for (final t in source) {
    final uid = t.ownerUserId;
    final colorIndex = colorOf.putIfAbsent(uid, () => nextColor++);
    out.add(
      TaskProgressBarItem(
        taskId: t.id,
        userId: uid,
        userName: t.ownerName.trim().isEmpty ? '未指定' : t.ownerName.trim(),
        taskTitle: t.title.trim().isEmpty ? '未命名' : t.title.trim(),
        progressPct: t.progressPct.clamp(0, 100),
        startAt: t.startAt,
        dueAt: t.dueAt,
        overdue: t.overdue,
        colorIndex: colorIndex,
      ),
    );
  }
  // 同执行人相邻，便于对比一人多任务
  out.sort((a, b) {
    final byUser = a.userName.compareTo(b.userName);
    if (byUser != 0) return byUser;
    return a.taskId.compareTo(b.taskId);
  });
  return out;
}

/// 横向进度列表：一行 = 一个子目标；同一负责人使用相同颜色。
class TaskMemberProgressChart extends StatelessWidget {
  const TaskMemberProgressChart({super.key, required this.bars, this.onBarTap});

  final List<TaskProgressBarItem> bars;
  final ValueChanged<int>? onBarTap;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8EAED)),
        ),
        child: const Text('暂无进度数据', style: TextStyle(color: DunesColors.text3)),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            bars.length > 1 ? '每个子目标横向展示，同一负责人使用相同颜色。' : '当前这条任务的填报进度',
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < bars.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _HorizontalProgressRow(
              item: bars[i],
              onTap: onBarTap == null ? null : () => onBarTap!(bars[i].taskId),
            ),
          ],
        ],
      ),
    );
  }
}

class _HorizontalProgressRow extends StatelessWidget {
  const _HorizontalProgressRow({required this.item, this.onTap});

  final TaskProgressBarItem item;
  final VoidCallback? onTap;

  String get _period {
    String fmt(DateTime value) => formatTaskYmd(value.toLocal());
    if (item.startAt != null && item.dueAt != null) {
      return '${fmt(item.startAt!)} — ${fmt(item.dueAt!)}';
    }
    if (item.startAt != null) return '开始 ${fmt(item.startAt!)}';
    if (item.dueAt != null) return '截止 ${fmt(item.dueAt!)}';
    return '未设置任务周期';
  }

  @override
  Widget build(BuildContext context) {
    final pct = item.progressPct.clamp(0, 100) / 100.0;
    final base = _kBarPalette[item.colorIndex % _kBarPalette.length];
    final color = item.overdue
        ? const Color(0xFFB45309)
        : item.progressPct >= 100
        ? const Color(0xFF2F8F7E)
        : base;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  item.userName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: DunesColors.text,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.taskTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: DunesColors.text2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _period,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: DunesColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${item.progressPct}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(999),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth * pct;
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        width: width,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            colors: [color, color.withValues(alpha: 0.65)],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TaskSummaryRow extends StatelessWidget {
  const TaskSummaryRow({
    super.key,
    required this.total,
    required this.active,
    required this.pending,
    required this.done,
  });

  final int total;
  final int active;
  final int pending;
  final int done;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _SummaryCard(
        icon: Icons.task_alt_outlined,
        title: '任务总数',
        value: '$total',
        subtitle: '我的任务',
        valueColor: kTaskPurple,
      ),
      _SummaryCard(
        icon: Icons.timelapse_outlined,
        title: '进行中',
        value: '$active',
        subtitle: '执行中',
        valueColor: const Color(0xFFE8A838),
      ),
      _SummaryCard(
        icon: Icons.hourglass_top_outlined,
        title: '待审核',
        value: '$pending',
        subtitle: '需处理',
        valueColor: const Color(0xFF5B8DEF),
      ),
      _SummaryCard(
        icon: Icons.check_circle_outline,
        title: '已完成',
        value: '$done',
        subtitle: '已闭环',
        valueColor: const Color(0xFF3CBFA9),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 720) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[3]),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.valueColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: DunesColors.text3),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: DunesColors.text3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: valueColor,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: DunesColors.text3),
          ),
        ],
      ),
    );
  }
}

class TaskMetaChip extends StatelessWidget {
  const TaskMetaChip({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// AI 运行态角标（分析中 / 匹配中），带闪烁图标以示进行中。
class TaskAiStateChip extends StatelessWidget {
  const TaskAiStateChip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: kTaskPurple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 9,
            height: 9,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: kTaskPurple,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: kTaskPurple,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 产品页同款小名片。
class TaskNameCard extends StatelessWidget {
  const TaskNameCard({
    super.key,
    required this.session,
    required this.task,
    required this.onTap,
  });

  final AuthSession session;
  final TaskItem task;
  final VoidCallback onTap;

  Color get _kindColor => task.isMain ? kTaskPurple : const Color(0xFF3CBFA9);

  Color get _statusColor {
    if (task.overdue) return const Color(0xFFB45309);
    return switch (task.status) {
      'pending_approval' => const Color(0xFF5B8DEF),
      'pending_assignment' => const Color(0xFF8B5CF6),
      'completed' => const Color(0xFF22A06B),
      'rejected' => const Color(0xFFE35D6A),
      'cancelled' => const Color(0xFF6B7280),
      _ => const Color(0xFF22A06B),
    };
  }

  Color get _priorityColor => switch (task.priority) {
    'urgent' => const Color(0xFFE35D6A),
    'high' => const Color(0xFFE8A838),
    'low' => const Color(0xFF6B7280),
    _ => kTaskPurple,
  };

  String? get _dateRange {
    String fmt(DateTime d) {
      final local = d.toLocal();
      return '${local.month}/${local.day}';
    }

    if (task.startAt == null && task.dueAt == null) return null;
    if (task.startAt != null && task.dueAt != null) {
      return '${fmt(task.startAt!)} - ${fmt(task.dueAt!)}';
    }
    if (task.startAt != null) return '起 ${fmt(task.startAt!)}';
    return '止 ${fmt(task.dueAt!)}';
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (task.ownerName.isNotEmpty) task.ownerName,
      ?_dateRange,
      if (task.subtaskCount > 0) '${task.subtaskCount} 子目标',
      '${task.progressPct}%',
    ].join(' · ');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EAED)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  buildTaskUserAvatar(
                    session: session,
                    name: task.ownerName.isNotEmpty
                        ? task.ownerName
                        : task.title,
                    userId: task.ownerUserId,
                    avatarPreset: task.ownerAvatarPreset,
                    avatarObjectKey: task.ownerAvatarObjectKey,
                    avatarUrl: task.ownerAvatarUrl,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: DunesColors.text,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: DunesColors.text3.withValues(alpha: 0.8),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                subtitle.isEmpty ? '暂无负责人' : subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: DunesColors.text3),
              ),
              const Spacer(),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  TaskMetaChip(
                    text: task.isMain ? '主目标' : '子目标',
                    color: _kindColor,
                  ),
                  if (task.category.isNotEmpty)
                    TaskMetaChip(text: task.categoryLabel, color: kTaskPurple),
                  TaskMetaChip(
                    text: taskPriorityLabel(task.priority),
                    color: _priorityColor,
                  ),
                  TaskMetaChip(
                    text: task.overdue ? '已逾期' : taskStatusLabel(task.status),
                    color: _statusColor,
                  ),
                  if (task.hasPendingChange)
                    TaskMetaChip(
                      text: taskPendingChangeLabel(task.pendingChangeKind),
                      color: const Color(0xFFB45309),
                    ),
                  if (task.aiState == 'analyzing')
                    const TaskAiStateChip(text: 'AI 分析中')
                  else if (task.aiState == 'binding')
                    const TaskAiStateChip(text: 'AI 匹配中'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 兼容旧引用。
class TaskListTileCard extends StatelessWidget {
  const TaskListTileCard({
    super.key,
    required this.session,
    required this.task,
    required this.onTap,
  });

  final AuthSession session;
  final TaskItem task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 148,
      child: TaskNameCard(session: session, task: task, onTap: onTap),
    );
  }
}

/// 工作台简化卡片：待我处理 / 我发起的，不展示主/子徽章。
class TaskWorkbenchCard extends StatelessWidget {
  const TaskWorkbenchCard({
    super.key,
    required this.task,
    required this.onTap,
    this.onProgress,
    this.onComplete,
    this.completeHint,
    this.onApprove,
    this.onReject,
    this.groupMode = false,
    this.statusHint,
    this.approveLabel = '通过',
    this.rejectLabel = '驳回',
  });

  final TaskItem task;
  final VoidCallback onTap;
  final VoidCallback? onProgress;
  final VoidCallback? onComplete;
  final String? completeHint;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool groupMode;
  final String? statusHint;
  final String approveLabel;
  final String rejectLabel;

  String? get _period {
    String fmt(DateTime value) => formatTaskYmd(value.toLocal());
    if (task.startAt != null && task.dueAt != null) {
      return '${fmt(task.startAt!)} — ${fmt(task.dueAt!)}';
    }
    if (task.startAt != null) return '开始 ${fmt(task.startAt!)}';
    if (task.dueAt != null) return '截止 ${fmt(task.dueAt!)}';
    return null;
  }

  Color get _statusColor {
    if (task.overdue) return const Color(0xFFD97706);
    return switch (task.status) {
      'completed' => const Color(0xFF23856D),
      'pending_approval' => const Color(0xFF2563A9),
      'pending_assignment' => const Color(0xFF7C3AED),
      'rejected' => const Color(0xFFC24156),
      _ => kTaskPurple,
    };
  }

  @override
  Widget build(BuildContext context) {
    final pending = task.isPending;
    final belong = task.parentTitle.trim();
    final contextLine = taskCardContextLine(task);
    final statusColor = _statusColor;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE3E5EA)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4,
                    height: 38,
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        if (!groupMode && belong.isNotEmpty)
                          Text(
                            '所属主目标：$belong',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: DunesColors.text3,
                            ),
                          ),
                        if (statusHint != null && statusHint!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              statusHint!,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: DunesColors.text2,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TaskMetaChip(
                    text: task.overdue ? '已逾期' : taskStatusLabel(task.status),
                    color: statusColor,
                  ),
                  if (task.hasPendingChange)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: TaskMetaChip(
                        text: taskPendingChangeLabel(task.pendingChangeKind),
                        color: const Color(0xFFB45309),
                      ),
                    ),
                ],
              ),
              if (groupMode) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F6FC),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _TaskInfoItem(
                        icon: Icons.account_tree_outlined,
                        text: task.subtaskCount > 0
                            ? '${task.subtaskCount} 个子目标'
                            : '暂无子目标',
                      ),
                      if (task.ownerName.isNotEmpty)
                        _TaskInfoItem(
                          icon: Icons.person_outline,
                          text: task.ownerName,
                        ),
                      if (_period != null)
                        _TaskInfoItem(
                          icon: Icons.event_outlined,
                          text: _period!,
                        ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    if (task.ownerName.isNotEmpty)
                      _TaskInfoItem(
                        icon: Icons.person_outline,
                        text: pending ? '${task.ownerName}提交' : task.ownerName,
                      ),
                    if (contextLine != null)
                      _TaskInfoItem(
                        icon: Icons.label_outline,
                        text: contextLine,
                      ),
                    if (_period != null)
                      _TaskInfoItem(icon: Icons.event_outlined, text: _period!),
                  ],
                ),
              ],
              if (!pending) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      '目标进度',
                      style: TextStyle(fontSize: 12, color: DunesColors.text3),
                    ),
                    const Spacer(),
                    Text(
                      '${task.progressPct}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TaskProgressBar(
                  progressPct: task.progressPct,
                  overdue: task.overdue,
                  completed: task.status == 'completed',
                  height: 7,
                  showLabel: false,
                ),
              ],
              const SizedBox(height: 12),
              if (pending || onApprove != null || onReject != null)
                Row(
                  children: [
                    if (pending || onApprove != null)
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: kTaskPurple,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: onApprove,
                        child: Text(approveLabel),
                      ),
                    if (pending || onReject != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: onReject,
                        child: Text(rejectLabel),
                      ),
                    ],
                  ],
                )
              else if (groupMode)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: kTaskPurple,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onTap,
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('查看详情与拆解'),
                  ),
                )
              else if (onProgress != null || onComplete != null || completeHint != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (completeHint != null && completeHint!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          completeHint!,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (onProgress != null)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: onProgress,
                            icon: const Icon(Icons.tune, size: 16),
                            label: const Text('更新进度'),
                          ),
                        if (onComplete != null) ...[
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: kTaskPurple,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                            ),
                            onPressed: onComplete,
                            icon: const Icon(Icons.check_circle_outline, size: 16),
                            label: const Text('标记完成'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskInfoItem extends StatelessWidget {
  const _TaskInfoItem({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: DunesColors.text3),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(fontSize: 12, color: DunesColors.text2),
        ),
      ],
    );
  }
}

MenuStyle get kTaskMenuStyle => MenuStyle(
  backgroundColor: const WidgetStatePropertyAll(Colors.white),
  elevation: const WidgetStatePropertyAll(8),
  shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.12)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
);

ThemeData taskThemeData(BuildContext context) {
  final base = Theme.of(context);
  final colorScheme = base.colorScheme.copyWith(
    primary: kTaskPurple,
    onPrimary: Colors.white,
    secondary: kTaskPurple,
    onSecondary: Colors.white,
    primaryContainer: kTaskPurple.withValues(alpha: 0.12),
    onPrimaryContainer: kTaskPurple,
    secondaryContainer: kTaskPurple.withValues(alpha: 0.12),
    onSecondaryContainer: kTaskPurple,
  );
  return base.copyWith(
    colorScheme: colorScheme,
    primaryColor: kTaskPurple,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kTaskPurple,
        foregroundColor: Colors.white,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kTaskPurple),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(foregroundColor: kTaskPurple),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: kTaskPurple,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        return Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return kTaskPurple;
        return const Color(0xFFD1D5DB);
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return kTaskPurple;
        return Colors.transparent;
      }),
      checkColor: const WidgetStatePropertyAll(Colors.white),
      side: const BorderSide(color: Color(0xFFC4C8CC), width: 1.6),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: kTaskPurple,
      thumbColor: kTaskPurple,
      overlayColor: kTaskPurple.withValues(alpha: 0.12),
      inactiveTrackColor: kTaskPurple.withValues(alpha: 0.18),
    ),
    chipTheme: base.chipTheme.copyWith(
      selectedColor: kTaskPurple.withValues(alpha: 0.14),
      checkmarkColor: kTaskPurple,
      labelStyle: const TextStyle(color: DunesColors.text2),
      secondaryLabelStyle: const TextStyle(
        color: kTaskPurple,
        fontWeight: FontWeight.w600,
      ),
      side: const BorderSide(color: Color(0xFFE8EAED)),
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: kTaskPurple,
      selectedTileColor: kTaskPurple.withValues(alpha: 0.08),
      iconColor: DunesColors.text2,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(menuStyle: kTaskMenuStyle),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: Colors.white,
      headerBackgroundColor: kTaskPurple,
      headerForegroundColor: Colors.white,
      rangeSelectionBackgroundColor: kTaskPurple.withValues(alpha: 0.14),
      rangeSelectionOverlayColor: WidgetStatePropertyAll(
        kTaskPurple.withValues(alpha: 0.08),
      ),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return kTaskPurple;
        return null;
      }),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        if (states.contains(WidgetState.disabled)) return DunesColors.text3;
        return DunesColors.text;
      }),
      todayForegroundColor: const WidgetStatePropertyAll(kTaskPurple),
      todayBackgroundColor: WidgetStatePropertyAll(
        kTaskPurple.withValues(alpha: 0.12),
      ),
      todayBorder: const BorderSide(color: kTaskPurple),
      confirmButtonStyle: TextButton.styleFrom(foregroundColor: kTaskPurple),
      cancelButtonStyle: TextButton.styleFrom(foregroundColor: kTaskPurple),
    ),
  );
}

class TaskTheme extends StatelessWidget {
  const TaskTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(data: taskThemeData(context), child: child);
  }
}

class TaskDropdownField<T> extends StatelessWidget {
  const TaskDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.sheetTitle = '请选择',
    this.forceSheet = false,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final String sheetTitle;
  final bool forceSheet;

  @override
  Widget build(BuildContext context) {
    final current = items.firstWhere(
      (e) => e.$1 == value,
      orElse: () => (value, '$value'),
    );
    final useSheet = forceSheet || MediaQuery.sizeOf(context).width < 700;
    if (useSheet) {
      return Material(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () async {
            final picked = await showModalBottomSheet<(T,)>(
              context: context,
              backgroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (ctx) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          sheetTitle,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    for (final item in items)
                      ListTile(
                        selected: item.$1 == value,
                        selectedColor: kTaskPurple,
                        selectedTileColor: kTaskPurple.withValues(alpha: 0.08),
                        title: Text(item.$2),
                        trailing: item.$1 == value
                            ? const Icon(
                                Icons.check_rounded,
                                color: kTaskPurple,
                              )
                            : null,
                        onTap: () => Navigator.pop(ctx, (item.$1,)),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
            if (picked != null) onChanged(picked.$1);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    current.$2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: DunesColors.text,
                    ),
                  ),
                ),
                const Icon(
                  Icons.expand_more,
                  size: 20,
                  color: DunesColors.text3,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final menuWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 220.0;
        return MenuAnchor(
          alignmentOffset: const Offset(0, 6),
          style: kTaskMenuStyle,
          builder: (context, controller, child) {
            final open = controller.isOpen;
            return Material(
              color: open
                  ? kTaskPurple.withValues(alpha: 0.08)
                  : const Color(0xFFF5F6F8),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => open ? controller.close() : controller.open(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          current.$2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: open ? kTaskPurple : DunesColors.text,
                            fontWeight: open
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.expand_more,
                        size: 20,
                        color: open ? kTaskPurple : DunesColors.text3,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          menuChildren: [
            for (final item in items)
              MenuItemButton(
                onPressed: () => onChanged(item.$1),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (item.$1 == value) {
                      return kTaskPurple.withValues(alpha: 0.1);
                    }
                    if (states.contains(WidgetState.hovered)) {
                      return const Color(0xFFF5F6F8);
                    }
                    return Colors.transparent;
                  }),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  minimumSize: WidgetStatePropertyAll(Size(menuWidth, 44)),
                ),
                trailingIcon: item.$1 == value
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: kTaskPurple,
                      )
                    : null,
                child: SizedBox(
                  width: menuWidth - 48,
                  child: Text(
                    item.$2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: item.$1 == value
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: item.$1 == value ? kTaskPurple : DunesColors.text,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class TaskFilterChipDropdown<T> extends StatelessWidget {
  const TaskFilterChipDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
    this.minMenuWidth = 180,
  });

  final T value;
  final String label;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final double minMenuWidth;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      alignmentOffset: const Offset(0, 6),
      style: kTaskMenuStyle,
      builder: (context, controller, child) {
        final open = controller.isOpen;
        return Material(
          color: open
              ? kTaskPurple.withValues(alpha: 0.08)
              : const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => open ? controller.close() : controller.open(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: open ? kTaskPurple : DunesColors.text2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.expand_more,
                    size: 18,
                    color: open ? kTaskPurple : DunesColors.text3,
                  ),
                ],
              ),
            ),
          ),
        );
      },
      menuChildren: [
        for (final item in items)
          MenuItemButton(
            onPressed: () => onChanged(item.$1),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (item.$1 == value) return kTaskPurple.withValues(alpha: 0.1);
                if (states.contains(WidgetState.hovered)) {
                  return const Color(0xFFF5F6F8);
                }
                return Colors.transparent;
              }),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              minimumSize: WidgetStatePropertyAll(Size(minMenuWidth, 44)),
            ),
            trailingIcon: item.$1 == value
                ? const Icon(Icons.check_rounded, size: 16, color: kTaskPurple)
                : null,
            child: SizedBox(
              width: minMenuWidth - 48,
              child: Text(
                item.$2,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: item.$1 == value
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: item.$1 == value ? kTaskPurple : DunesColors.text,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<DateTime?> showTaskDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: helpText,
    cancelText: '取消',
    confirmText: '确定',
    builder: (context, child) =>
        Theme(data: taskThemeData(context), child: child!),
  );
}

/// 浅色区间选中，避免沿用深色 ColorScheme 导致中间日期发黑。
Future<DateTimeRange?> showTaskDateRangePicker(
  BuildContext context, {
  DateTimeRange? initialDateRange,
  String helpText = '选择时间段',
}) {
  final now = DateTime.now();
  final initial =
      initialDateRange ??
      DateTimeRange(
        start: now.subtract(const Duration(days: 30)),
        end: now.add(const Duration(days: 30)),
      );
  return showDateRangePicker(
    context: context,
    firstDate: DateTime(now.year - 3),
    lastDate: DateTime(now.year + 3),
    initialDateRange: initial,
    helpText: helpText,
    cancelText: '取消',
    confirmText: '确定',
    saveText: '确定',
    builder: (context, child) =>
        Theme(data: taskThemeData(context), child: child!),
  );
}
