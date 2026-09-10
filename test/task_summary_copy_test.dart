import 'package:dunes_app/features/tasks/task_models.dart';
import 'package:dunes_app/features/tasks/task_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fill progress 100% is not treated as closed when overdue', () {
    expect(
      taskProgressTone(100, overdue: true, completed: false),
      const Color(0xFFB45309),
    );
    expect(
      taskProgressTone(100, overdue: false, completed: true),
      const Color(0xFF1F9D76),
    );
  });

  test('overdue hint explains 100% fill is not done', () {
    expect(
      taskUnfinishedOverdueHint(
        overdue: true,
        completed: false,
        progressPct: 100,
      ),
      contains('进度填满不等于已经完成'),
    );
    expect(
      taskUnfinishedOverdueHint(
        overdue: false,
        completed: false,
        progressPct: 100,
      ),
      isNull,
    );
  });

  test('department summary separates fill progress from closed count', () {
    const st = HrbpDeptStat(
      departmentId: 1,
      departmentName: '出行组',
      mainTotal: 1,
      mainCompleted: 0,
      mainOverdue: 1,
      avgProgress: 100,
      pendingApproval: 2,
    );
    expect(st.allClosed, isFalse);
    expect(st.summaryLine, contains('1 个主任务'));
    expect(st.summaryLine, contains('0 已办结'));
    expect(st.summaryLine, contains('1 已逾期未办结'));
    expect(st.summaryLine, isNot(contains('待审核')));
    expect(taskFillProgressLabel(st.avgProgress.round()), '填报 100%');
  });

  test('postpone only allows a later due date', () {
    expect(
      taskPostponeError(
        startAt: DateTime(2026, 9, 1),
        currentDue: DateTime(2026, 9, 10),
        newDue: null,
      ),
      '请选择新的截止日',
    );
    expect(
      taskPostponeError(
        startAt: DateTime(2026, 9, 1),
        currentDue: DateTime(2026, 9, 10),
        newDue: DateTime(2026, 9, 10),
      ),
      '新的截止日必须晚于当前截止日',
    );
    expect(
      taskPostponeError(
        startAt: DateTime(2026, 9, 8),
        currentDue: null,
        newDue: DateTime(2026, 9, 5),
      ),
      '结束时间不能早于开始时间',
    );
    expect(
      taskPostponeError(
        startAt: DateTime(2026, 9, 1),
        currentDue: DateTime(2026, 9, 10),
        newDue: DateTime(2026, 9, 18),
      ),
      isNull,
    );
  });

  test('card context prefers meeting source over duplicated description', () {
    const fromMeeting = TaskItem(
      id: 1,
      title: '跟进方案',
      ownerUserId: 1,
      creatorUserId: 1,
      description: '跟进方案',
      sourceMeetingTitle: '产品周会',
    );
    expect(taskCardContextLine(fromMeeting), '来自《产品周会》');
    expect(taskDistinctDescription(fromMeeting), isEmpty);

    const withDesc = TaskItem(
      id: 2,
      title: '跟进方案',
      ownerUserId: 1,
      creatorUserId: 1,
      description: '会后输出一版方案给客户确认',
    );
    expect(taskCardContextLine(withDesc), '会后输出一版方案给客户确认');
  });
}
