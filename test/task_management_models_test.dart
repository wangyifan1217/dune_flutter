import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/tasks/task_management_api.dart';

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
      'total': 3,
      'valid': 2,
      'invalid': 1,
      'errors': ['第 2 行负责人为空'],
    });

    expect(preview.importId, 'imp-1');
    expect(preview.total, 3);
    expect(preview.valid, 2);
    expect(preview.invalid, 1);
    expect(preview.errors, ['第 2 行负责人为空']);
  });

  test('import history tolerates omitted optional fields', () {
    final item = TaskImportHistoryItem.fromJson({'id': 9});

    expect(item.id, '9');
    expect(item.fileName, isEmpty);
    expect(item.total, 0);
  });
}
