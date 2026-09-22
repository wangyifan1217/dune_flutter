import 'package:dunes_app/features/tasks/task_inbox.dart';
import 'package:dunes_app/features/tasks/task_models.dart';
import 'package:flutter_test/flutter_test.dart';

TaskItem _task({
  required int id,
  String title = '任务',
  String status = 'active',
  bool overdue = false,
  bool hasPendingChange = false,
  String pendingChangeKind = '',
  int progressPct = 0,
  DateTime? startAt,
  DateTime? dueAt,
}) {
  return TaskItem(
    id: id,
    title: title,
    ownerUserId: 1,
    creatorUserId: 2,
    status: status,
    overdue: overdue,
    hasPendingChange: hasPendingChange,
    pendingChangeKind: pendingChangeKind,
    progressPct: progressPct,
    startAt: startAt,
    dueAt: dueAt,
  );
}

void main() {
  final now = DateTime(2026, 9, 22, 11);

  test('decision tasks stay in their own buckets', () {
    final snapshot = TaskInboxSnapshot.build(
      now: now,
      pending: [
        _task(id: 1, status: 'pending_assignment', title: '待接收'),
        _task(
          id: 2,
          hasPendingChange: true,
          pendingChangeKind: 'assignment',
          title: '指派审批',
        ),
        _task(
          id: 3,
          hasPendingChange: true,
          pendingChangeKind: 'dueAt',
          title: '变更审批',
        ),
        _task(id: 4, status: 'pending_approval', title: '待确认'),
      ],
      actionable: [
        _task(id: 1, status: 'pending_assignment', title: '待接收'),
        _task(id: 9, title: '今天做'),
      ],
    );

    expect(snapshot.countOf(TaskInboxBucket.receive), 1);
    expect(snapshot.countOf(TaskInboxBucket.assignApproval), 1);
    expect(snapshot.countOf(TaskInboxBucket.changeApproval), 1);
    expect(snapshot.countOf(TaskInboxBucket.confirm), 1);
    expect(snapshot.today.map((task) => task.id), [9]);
  });

  test('overdue, due today, returned and full progress are attention', () {
    final snapshot = TaskInboxSnapshot.build(
      now: now,
      pending: const [],
      actionable: [
        _task(id: 1, overdue: true, title: '逾期'),
        _task(id: 2, dueAt: DateTime(2026, 9, 22, 18), title: '今天截止'),
        _task(id: 3, status: 'rejected', title: '退回'),
        _task(id: 4, progressPct: 100, title: '假完成'),
        _task(id: 5, title: '执行中'),
      ],
    );

    expect(snapshot.itemsOf(TaskInboxBucket.overdue).single.id, 1);
    expect(snapshot.itemsOf(TaskInboxBucket.dueToday).single.id, 2);
    expect(snapshot.itemsOf(TaskInboxBucket.returned).single.id, 3);
    expect(snapshot.itemsOf(TaskInboxBucket.readyToClose).single.id, 4);
    expect(snapshot.today.single.id, 5);
  });

  test('complete is blocked before the start date and while a change is pending', () {
    final future = _task(id: 1, startAt: DateTime(2026, 9, 23));
    final pending = _task(id: 2, hasPendingChange: true, pendingChangeKind: 'dueAt');
    final ready = _task(id: 3, startAt: DateTime(2026, 9, 22));

    expect(taskCompleteBlockReason(future, now: now), contains('开始日'));
    expect(taskCompleteBlockReason(pending, now: now), contains('待审批'));
    expect(taskCompleteBlockReason(ready, now: now), isNull);
  });

  test('future start dates stay out of today execution', () {
    final snapshot = TaskInboxSnapshot.build(
      now: now,
      pending: const [],
      actionable: [
        _task(id: 1, startAt: DateTime(2026, 9, 23), title: '明天开始'),
        _task(id: 2, startAt: DateTime(2026, 9, 22, 9), title: '今天开始'),
        _task(id: 3, status: 'completed', title: '已完成'),
      ],
    );

    expect(snapshot.plannedCount, 1);
    expect(snapshot.today.map((task) => task.id), [2]);
    expect(snapshot.isEmpty, isFalse);
  });
}
