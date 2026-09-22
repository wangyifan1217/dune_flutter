import 'task_models.dart';

/// 任务首页行动中心的分区。同一条任务只归入一个分区。
enum TaskInboxBucket {
  receive,
  assignApproval,
  changeApproval,
  confirm,
  overdue,
  dueToday,
  returned,
  readyToClose,
  today,
}

class TaskInboxSection {
  const TaskInboxSection({
    required this.bucket,
    required this.title,
    required this.items,
  });

  final TaskInboxBucket bucket;
  final String title;
  final List<TaskItem> items;
}

class TaskInboxSnapshot {
  const TaskInboxSnapshot({
    required this.decisions,
    required this.attention,
    required this.today,
    required this.plannedCount,
  });

  final List<TaskInboxSection> decisions;
  final List<TaskInboxSection> attention;
  final List<TaskItem> today;

  /// 开始日在今天之后，不进入今日执行。
  final int plannedCount;

  bool get isEmpty =>
      decisions.every((section) => section.items.isEmpty) &&
      attention.isEmpty &&
      today.isEmpty;

  int countOf(TaskInboxBucket bucket) {
    if (bucket == TaskInboxBucket.today) return today.length;
    for (final section in [...decisions, ...attention]) {
      if (section.bucket == bucket) return section.items.length;
    }
    return 0;
  }

  List<TaskItem> itemsOf(TaskInboxBucket bucket) {
    if (bucket == TaskInboxBucket.today) return today;
    for (final section in [...decisions, ...attention]) {
      if (section.bucket == bucket) return section.items;
    }
    return const [];
  }

  factory TaskInboxSnapshot.build({
    required List<TaskItem> pending,
    required List<TaskItem> actionable,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final actionableIds = actionable.map((task) => task.id).toSet();
    final byId = <int, TaskItem>{};
    for (final task in [...pending, ...actionable]) {
      byId[task.id] = task;
    }

    final receive = <TaskItem>[];
    final assignApproval = <TaskItem>[];
    final changeApproval = <TaskItem>[];
    final confirm = <TaskItem>[];
    final claimed = <int>{};

    final ordered = byId.values.toList(growable: false)..sort(_byDue);
    for (final task in ordered) {
      final bucket = taskDecisionBucket(task);
      if (bucket == null) continue;
      claimed.add(task.id);
      switch (bucket) {
        case TaskInboxBucket.receive:
          receive.add(task);
        case TaskInboxBucket.assignApproval:
          assignApproval.add(task);
        case TaskInboxBucket.changeApproval:
          changeApproval.add(task);
        case TaskInboxBucket.confirm:
          confirm.add(task);
        default:
          break;
      }
    }

    final overdue = <TaskItem>[];
    final dueToday = <TaskItem>[];
    final returned = <TaskItem>[];
    final readyToClose = <TaskItem>[];
    final today = <TaskItem>[];
    var plannedCount = 0;

    for (final task in ordered) {
      if (claimed.contains(task.id) || taskIsClosed(task)) continue;
      if (task.status == 'rejected') {
        returned.add(task);
        continue;
      }
      if (taskStartsAfterToday(task, clock)) {
        plannedCount++;
        continue;
      }
      if (task.overdue) {
        overdue.add(task);
        continue;
      }
      if (taskDueOnDay(task, clock)) {
        dueToday.add(task);
        continue;
      }
      if (task.progressPct >= 100) {
        readyToClose.add(task);
        continue;
      }
      if (actionableIds.contains(task.id)) today.add(task);
    }

    return TaskInboxSnapshot(
      decisions: [
        TaskInboxSection(
          bucket: TaskInboxBucket.receive,
          title: taskInboxBucketTitle(TaskInboxBucket.receive),
          items: receive,
        ),
        TaskInboxSection(
          bucket: TaskInboxBucket.assignApproval,
          title: taskInboxBucketTitle(TaskInboxBucket.assignApproval),
          items: assignApproval,
        ),
        TaskInboxSection(
          bucket: TaskInboxBucket.changeApproval,
          title: taskInboxBucketTitle(TaskInboxBucket.changeApproval),
          items: changeApproval,
        ),
        if (confirm.isNotEmpty)
          TaskInboxSection(
            bucket: TaskInboxBucket.confirm,
            title: taskInboxBucketTitle(TaskInboxBucket.confirm),
            items: confirm,
          ),
      ],
      attention: [
        if (overdue.isNotEmpty)
          TaskInboxSection(
            bucket: TaskInboxBucket.overdue,
            title: taskInboxBucketTitle(TaskInboxBucket.overdue),
            items: overdue,
          ),
        if (dueToday.isNotEmpty)
          TaskInboxSection(
            bucket: TaskInboxBucket.dueToday,
            title: taskInboxBucketTitle(TaskInboxBucket.dueToday),
            items: dueToday,
          ),
        if (returned.isNotEmpty)
          TaskInboxSection(
            bucket: TaskInboxBucket.returned,
            title: taskInboxBucketTitle(TaskInboxBucket.returned),
            items: returned,
          ),
        if (readyToClose.isNotEmpty)
          TaskInboxSection(
            bucket: TaskInboxBucket.readyToClose,
            title: taskInboxBucketTitle(TaskInboxBucket.readyToClose),
            items: readyToClose,
          ),
      ],
      today: today,
      plannedCount: plannedCount,
    );
  }
}

/// 需要本人决策的事项。其余状态返回 null。
TaskInboxBucket? taskDecisionBucket(TaskItem task) {
  if (task.status == 'pending_assignment') return TaskInboxBucket.receive;
  if (task.hasPendingChange && task.pendingChangeKind == 'assignment') {
    return TaskInboxBucket.assignApproval;
  }
  if (task.hasPendingChange) return TaskInboxBucket.changeApproval;
  if (task.status == 'pending_approval') return TaskInboxBucket.confirm;
  return null;
}

bool taskIsClosed(TaskItem task) =>
    task.status == 'completed' || task.status == 'cancelled';

bool taskStartsAfterToday(TaskItem task, DateTime now) {
  final start = task.startAt;
  if (start == null) return false;
  final local = start.toLocal();
  final startDay = DateTime(local.year, local.month, local.day);
  final today = DateTime(now.year, now.month, now.day);
  return startDay.isAfter(today);
}

bool taskDueOnDay(TaskItem task, DateTime now) {
  final due = task.dueAt;
  if (due == null) return false;
  final local = due.toLocal();
  return local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
}

String taskInboxBucketTitle(TaskInboxBucket bucket) {
  return switch (bucket) {
    TaskInboxBucket.receive => '待接收',
    TaskInboxBucket.assignApproval => '待指派审批',
    TaskInboxBucket.changeApproval => '待变更审批',
    TaskInboxBucket.confirm => '待确认',
    TaskInboxBucket.overdue => '逾期',
    TaskInboxBucket.dueToday => '今天截止',
    TaskInboxBucket.returned => '被退回',
    TaskInboxBucket.readyToClose => '进度已满未办结',
    TaskInboxBucket.today => '今日执行',
  };
}

/// 还不能标记完成时返回原因；可以完成时返回 null。已结束的任务也返回说明。
String? taskCompleteBlockReason(TaskItem task, {DateTime? now}) {
  if (task.status == 'completed' || task.status == 'cancelled') {
    return '任务已结束';
  }
  if (task.status == 'pending_assignment' || task.status == 'pending_approval') {
    return '还在待确认，不能标记完成';
  }
  if (task.hasPendingChange) {
    return '有待审批的变更，通过或驳回前不能完成';
  }
  if (taskStartsAfterToday(task, now ?? DateTime.now())) {
    return '尚未到开始日，不能标记完成';
  }
  if (task.isMain && task.openItemCount > 0 && !task.itemsReadyToClose) {
    return '还有 ${task.openItemCount} 个子目标未完成';
  }
  return null;
}

String taskInboxCardHint(TaskInboxBucket bucket) {
  return switch (bucket) {
    TaskInboxBucket.receive => '下一步：接受或拒绝。接受后才会开始执行。',
    TaskInboxBucket.assignApproval => '下一步：审批通过后，负责人变更为被指派人。',
    TaskInboxBucket.changeApproval => '下一步：审批通过后，变更才会生效。',
    TaskInboxBucket.confirm => '下一步：通过后，任务进入执行。',
    TaskInboxBucket.overdue => '已过截止日，尚未办结。',
    TaskInboxBucket.dueToday => '今天截止，需要推进或申请变更。',
    TaskInboxBucket.returned => '已被退回，需要处理后重新提交。',
    TaskInboxBucket.readyToClose => '进度已到 100%，任务仍未办结。',
    TaskInboxBucket.today => '今天可以执行。',
  };
}

int _byDue(TaskItem a, TaskItem b) {
  final ad = a.dueAt;
  final bd = b.dueAt;
  if (ad == null && bd == null) return a.id.compareTo(b.id);
  if (ad == null) return 1;
  if (bd == null) return -1;
  final compared = ad.compareTo(bd);
  if (compared != 0) return compared;
  return a.id.compareTo(b.id);
}
