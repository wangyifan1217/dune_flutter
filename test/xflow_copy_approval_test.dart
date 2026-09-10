import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('copyableApprovalFormValues strips identity fields and keeps content', () {
    final copied = copyableApprovalFormValues({
      'id': 519,
      'proposalId': 519,
      'businessId': 519,
      'code': '#519',
      'status': 'DRAFT',
      'title': '王奕凡 - 业务采购申请单',
      'amount': '1200',
      'createdById': 7,
      'createdAt': '2026-09-10',
    });
    expect(copied.containsKey('id'), isFalse);
    expect(copied.containsKey('proposalId'), isFalse);
    expect(copied.containsKey('businessId'), isFalse);
    expect(copied.containsKey('code'), isFalse);
    expect(copied.containsKey('status'), isFalse);
    expect(copied.containsKey('createdById'), isFalse);
    expect(copied.containsKey('createdAt'), isFalse);
    expect(copied['title'], '王奕凡 - 业务采购申请单');
    expect(copied['amount'], '1200');
  });
}
