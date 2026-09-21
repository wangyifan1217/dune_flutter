import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/tasks/task_management_api.dart';
import 'package:dunes_app/features/tasks/task_models.dart';

void main() {
  test('recurring rule accepts both title and name payloads', () {
    final rule = TaskRecurringRule.fromJson({
      'id': 7,
      'name': '月度目标复盘',
      'cycle': '每月',
      'enabled': false,
    });

    expect(rule.id, '7');
    expect(rule.title, '月度目标复盘');
    expect(rule.frequency, '每月');
    expect(rule.enabled, isFalse);
  });

  test('import preview keeps validation summary and errors', () {
    final preview = TaskImportPreview.fromJson({
      'importId': 'imp-1',
      'total': 21,
      'valid': 21,
      'invalid': 0,
      'parentCount': 4,
      'childCount': 17,
      'targetUserName': '李晨阳',
      'probationStartAt': '2026-06-01',
      'probationEndAt': '2026-09-01',
      'errors': [],
      'warnings': ['已忽略工作表：岗位职责、能力要求，本期不生成任务'],
    });

    expect(preview.importId, 'imp-1');
    expect(preview.total, 21);
    expect(preview.valid, 21);
    expect(preview.canCommit, isTrue);
    expect(preview.periodLabel, '2026-06-01 至 2026-09-01');
    expect(preview.warnings.single, contains('岗位职责'));
  });

  test('import preview with errors cannot be committed', () {
    final preview = TaskImportPreview.fromJson({
      'importId': 'imp-2',
      'total': 3,
      'valid': 0,
      'invalid': 1,
      'errors': ['第 2 行验收标准不能为空'],
    });
    expect(preview.canCommit, isFalse);
    expect(preview.errors, ['第 2 行验收标准不能为空']);
  });

  test('import history tolerates omitted optional fields', () {
    final item = TaskImportHistoryItem.fromJson({'id': 9});

    expect(item.id, '9');
    expect(item.fileName, isEmpty);
    expect(item.total, 0);
    expect(item.kindLabel, '任务');
  });

  test('probation import history shows employee and kind label', () {
    final item = TaskImportHistoryItem.fromJson({
      'id': 12,
      'importKind': 'probation',
      'targetUserName': '李晨阳',
      'parentCount': 4,
    });
    expect(item.kindLabel, '试用期任务');
    expect(item.targetUserName, '李晨阳');
  });

  test('import employee maps hiredAt as probation start', () {
    final employee = TaskImportEmployee.fromJson({
      'userId': 42,
      'displayName': '李晨阳',
      'hiredAt': '2026-06-01',
      'probationEndAt': '2026-09-01',
      'departmentName': '客服',
    });
    expect(employee.id, 42);
    expect(employee.periodLabel, '2026-06-01 至 2026-09-01');
  });

  test('commit result summarizes parent and child counts', () {
    final result = TaskImportCommitResult.fromJson({
      'status': 'success',
      'created': 21,
      'createdParents': 4,
      'createdChildren': 17,
      'failed': 0,
    });
    expect(result.ok, isTrue);
    expect(result.summary, '已创建 4 项主任务、17 项验收目标');
  });

  test('task category label includes the selected second-level category', () {
    final task = TaskItem.fromJson({
      'id': 1,
      'title': '跟进客户',
      'category': '业务',
      'subCategory': '销售',
    });

    expect(task.categoryLabel, '业务 · 销售');
  });

  test('daily report calendar parses leave and missing states', () {
    final calendar = TaskDailyReportCalendar.fromJson({
      'month': '2026-09',
      'days': ['2026-09-01', '2026-09-02'],
      'summary': {'expected': 1, 'submitted': 0, 'leave': 1, 'missing': 1},
      'users': [
        {
          'userId': 8,
          'userName': '李晨阳',
          'days': [
            {'date': '2026-09-01', 'status': 'leave', 'attendanceStatus': 4},
            {'date': '2026-09-02', 'status': 'missing'},
          ],
        },
      ],
    });

    expect(calendar.users.single.days.first.status, 'leave');
    expect(calendar.users.single.days.first.attendanceStatus, 4);
    expect(calendar.summary.missing, 1);
  });
}
