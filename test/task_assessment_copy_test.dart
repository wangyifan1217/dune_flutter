import 'package:dunes_app/features/tasks/task_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dunes_app/features/tasks/task_models.dart';

void main() {
  test('goal and item labels', () {
    const goal = TaskItem(
      id: 1,
      title: 'Q3 交付',
      ownerUserId: 1,
      creatorUserId: 1,
    );
    const item = TaskItem(
      id: 2,
      parentId: 1,
      title: '写方案',
      ownerUserId: 2,
      creatorUserId: 1,
    );
    expect(taskKindLabel(goal), '主目标');
    expect(taskKindLabel(item), '子目标');
    expect(taskDisplayStatusLabel(goal), '进行中');
    expect(taskStatusLabel('pending_approval'), '待确认');
  });

  test('daily report bundle parse', () {
    final bundle = TaskDailyReportBundle.fromJson({
      'canSubmit': true,
      'canBackfill': false,
      'businessDate': '2026-09-15',
      'candidates': [
        {
          'id': 8,
          'title': '跟进方案',
          'ownerUserId': 1,
          'creatorUserId': 1,
          'status': 'active',
        },
      ],
    });
    expect(bundle.canSubmit, isTrue);
    expect(bundle.candidates, hasLength(1));
    expect(bundle.candidates.first.title, '跟进方案');
  });

  test('daily report bundle reads leave exemption fields', () {
    final bundle = TaskDailyReportBundle.fromJson({
      'businessDate': '2026-09-21',
      'leaveExempt': true,
      'leaveReason': '已同步全日请假，不要求提交日报',
      'attendanceStatus': 4,
    });
    expect(bundle.leaveExempt, isTrue);
    expect(bundle.attendanceStatus, 4);
    expect(bundle.leaveReason, contains('全日请假'));
  });

  test('missing report model keeps resolved state', () {
    final missing = TaskDailyReportMissing.fromJson({
      'id': 1,
      'userId': 7,
      'reportDate': '2026-09-20',
      'detectedAt': '2026-09-21T04:00:00Z',
      'resolvedAt': '2026-09-21T05:00:00Z',
    });
    expect(missing.resolved, isTrue);
    expect(missing.reportDate, '2026-09-20');
  });
}
