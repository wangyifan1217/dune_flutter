import 'package:dunes_app/features/xflow/task_todo_actions.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter_test/flutter_test.dart';

XflowProposalItem _item(String action) => XflowProposalItem(
  id: 1,
  businessType: 'INVOICE',
  code: 'S-302',
  title: '发票申请',
  status: 'OPEN',
  createdByName: '李博睿',
  createdAt: DateTime(2026, 8, 28),
  primaryAction: action,
  actionTitle: '开具发票',
);

void main() {
  test('issue and re-upload invoice todos require files', () {
    expect(taskTodoNeedsInvoiceFiles('ISSUE_INVOICE'), isTrue);
    expect(taskTodoNeedsInvoiceFiles('UPLOAD_INVOICE'), isTrue);
    expect(taskTodoNeedsInvoiceFiles('PAY'), isFalse);
    expect(taskTodoNeedsInvoiceFiles('VERIFY_INVOICE'), isFalse);
  });

  test('issue invoice copy asks for drag-and-drop files', () {
    final copy = taskTodoConfirmCopy(_item('ISSUE_INVOICE'));
    expect(copy.body, contains('发票文件'));
    expect(copy.body, contains('拖拽'));
  });
}
