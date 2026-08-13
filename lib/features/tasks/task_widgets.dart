import 'package:flutter/material.dart';

import '../../core/theme/dunes_theme.dart';
import '../auth/auth_session.dart';
import 'task_avatar.dart';
import 'task_models.dart';

const kTaskPurple = Color(0xFF7B5CD8);

/// 按进度分段取色：低→红橙、中→琥珀、高→青绿、完成→翠绿；逾期偏琥珀棕。
Color taskProgressTone(
  num progressPct, {
  bool overdue = false,
  bool completed = false,
}) {
  if (overdue && !completed) return const Color(0xFFB45309);
  final p = progressPct.toDouble().clamp(0, 100);
  if (completed || p >= 100) return const Color(0xFF1F9D76);
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
  if (overdue && !completed) {
    return const [Color(0xFFB45309), Color(0xFFE8A868)];
  }
  final p = progressPct.toDouble().clamp(0, 100);
  if (completed || p >= 100) {
    return const [Color(0xFF1F9D76), Color(0xFF6ED4B0)];
  }
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
    this.overdue = false,
    this.colorIndex = 0,
  });

  final int taskId;
  final int userId;
  final String userName;
  final String taskTitle;
  final int progressPct;
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

/// 竖向柱状图：一柱 = 一个子任务；同一人多子任务并排多柱（同色系）。
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

    final barWidth = 56.0;
    final gap = 12.0;
    final chartWidth = bars.length * barWidth + (bars.length - 1) * gap + 8;

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
            bars.length > 1 ? '每个子任务一根柱；同一执行人多任务会并排显示（同色）' : '当前任务进度',
            style: const TextStyle(fontSize: 12, color: DunesColors.text3),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth < 280 ? 280 : chartWidth,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < bars.length; i++) ...[
                      if (i > 0) SizedBox(width: gap),
                      SizedBox(
                        width: barWidth,
                        child: _VerticalBar(
                          item: bars[i],
                          onTap: onBarTap == null
                              ? null
                              : () => onBarTap!(bars[i].taskId),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalBar extends StatelessWidget {
  const _VerticalBar({required this.item, this.onTap});

  final TaskProgressBarItem item;
  final VoidCallback? onTap;

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
      borderRadius: BorderRadius.circular(8),
      child: Column(
        children: [
          Text(
            '${item.progressPct}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final h = (c.maxHeight * (pct <= 0 ? 0.04 : pct)).clamp(
                  4.0,
                  c.maxHeight,
                );
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: h,
                    width: 28,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(8),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [color, color.withValues(alpha: 0.72)],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.userName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: DunesColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.taskTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              color: DunesColors.text3,
              height: 1.2,
            ),
          ),
        ],
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
      if (_dateRange != null) _dateRange!,
      if (task.subtaskCount > 0) '${task.subtaskCount} 子任务',
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
                    text: task.isMain ? '主任务' : '子任务',
                    color: _kindColor,
                  ),
                  if (task.category.isNotEmpty)
                    TaskMetaChip(text: task.category, color: kTaskPurple),
                  TaskMetaChip(
                    text: taskPriorityLabel(task.priority),
                    color: _priorityColor,
                  ),
                  TaskMetaChip(
                    text: task.overdue ? '已逾期' : taskStatusLabel(task.status),
                    color: _statusColor,
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

MenuStyle get kTaskMenuStyle => MenuStyle(
  backgroundColor: const WidgetStatePropertyAll(Colors.white),
  elevation: const WidgetStatePropertyAll(8),
  shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.12)),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
);

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
    builder: (context, child) {
      final light = ColorScheme.light(
        primary: kTaskPurple,
        onPrimary: Colors.white,
        secondary: kTaskPurple.withValues(alpha: 0.18),
        onSecondary: DunesColors.text,
        surface: Colors.white,
        onSurface: DunesColors.text,
      );
      return Theme(
        data: ThemeData(
          useMaterial3: true,
          colorScheme: light,
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
              if (states.contains(WidgetState.disabled)) {
                return DunesColors.text3;
              }
              return DunesColors.text;
            }),
            todayForegroundColor: const WidgetStatePropertyAll(kTaskPurple),
            todayBorder: const BorderSide(color: kTaskPurple),
          ),
        ),
        child: child!,
      );
    },
  );
}
