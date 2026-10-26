import 'package:dunes_app/features/xflow/approval_todo_export.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('csv quotes commas and keeps the visible columns', () {
    final csv = approvalTodoCsv([
      XflowProposalItem(
        id: 1,
        businessType: 'FINANCE',
        code: 'S-1',
        title: '采购,补票',
        status: 'OPEN',
        createdByName: '朱子姝',
        createdAt: DateTime.utc(2026, 10, 26, 2, 8),
        actionTitle: '补传发票',
        templateKey: 'finance-admin-procurement',
        highlights: const [
          ApprovalListHighlight(label: '付款类型', value: '先款后票'),
        ],
        todoHint: const XflowTodoHint(
          id: 9,
          businessType: 'FINANCE',
          businessId: 1,
          status: 'OPEN',
        ),
      ),
    ]);
    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(csv, contains('编号,单据名称,提交人,办理动作,待办状态,模板,摘要,创建时间'));
    expect(csv, contains('"采购,补票"'));
    expect(csv, contains('朱子姝'));
    expect(csv, contains('补传发票'));
    expect(csv, contains('待办理'));
    expect(csv, contains('付款类型:先款后票'));
  });
}
