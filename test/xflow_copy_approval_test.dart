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

  test('copyableApprovalFormValues strips task todo completion fields', () {
    final copied = copyableApprovalFormValues({
      'title': '王奕凡 - 业务采购申请单',
      'amount': '1200',
      'remark': '按原合同付款',
      'actualPayAmount': '1180',
      'paymentVoucher': 'PZ-2026-001',
      'verifyResult': '通过',
      'invoiceFiles': [
        {'fileName': '发票.pdf', 'objectKey': 'xflow/a.pdf'},
      ],
      'expressTrackingNo': 'SF123',
      'expressSentAt': '2026-09-01',
      'signedAt': '2026-09-03',
      'bankAccountName': '沙丘科技',
      'bankName': '招行',
      'bankAccountNo': '6222',
      'openAccountFilledAt': '2026-09-02',
      'files': [
        {'fileName': '申请附件.pdf', 'objectKey': 'xflow/apply.pdf'},
      ],
      'attachments': [
        {'fileName': '报价单.pdf', 'objectKey': 'xflow/quote.pdf'},
      ],
      'scanCopies': [
        {'fileName': '扫描件.jpg', 'objectKey': 'xflow/scan.jpg'},
      ],
      'paymentItems': [
        {
          'promoterName': '推广商甲',
          'paymentAmount': '300',
          'attachments': [
            {'fileName': '明细.xlsx', 'objectKey': 'xflow/list.xlsx'},
          ],
        },
      ],
    });
    expect(copied['title'], '王奕凡 - 业务采购申请单');
    expect(copied['amount'], '1200');
    expect(copied['remark'], '按原合同付款');
    expect(copied.containsKey('files'), isFalse);
    expect(copied.containsKey('attachments'), isFalse);
    expect((copied['paymentItems'] as List).first['promoterName'], '推广商甲');
    expect(
      (copied['paymentItems'] as List).first.containsKey('attachments'),
      isFalse,
    );
    expect(copied.containsKey('actualPayAmount'), isFalse);
    expect(copied.containsKey('paymentVoucher'), isFalse);
    expect(copied.containsKey('verifyResult'), isFalse);
    expect(copied.containsKey('invoiceFiles'), isFalse);
    expect(copied.containsKey('expressTrackingNo'), isFalse);
    expect(copied.containsKey('expressSentAt'), isFalse);
    expect(copied.containsKey('signedAt'), isFalse);
    expect(copied.containsKey('bankAccountName'), isFalse);
    expect(copied.containsKey('bankAccountNo'), isFalse);
    expect(copied.containsKey('openAccountFilledAt'), isFalse);
    expect(copied.containsKey('scanCopies'), isFalse);
  });
}
