import 'package:flutter_test/flutter_test.dart';

import 'package:dunes_app/features/payment_invoice/payment_invoice_catalog.dart';
import 'package:dunes_app/features/payment_invoice/payment_invoice_print.dart';

void main() {
  test('classifies payment and invoice templates', () {
    expect(
      classifyPaymentInvoice(templateKey: 'finance-admin-procurement'),
      PaymentInvoiceKind.payment,
    );
    expect(
      classifyPaymentInvoice(templateKey: 'finance-promotion-payment'),
      PaymentInvoiceKind.payment,
    );
    expect(
      classifyPaymentInvoice(businessType: 'FINANCE_CONTRACT_PAYMENT'),
      PaymentInvoiceKind.payment,
    );
    expect(
      classifyPaymentInvoice(title: '预付款申请'),
      PaymentInvoiceKind.payment,
    );
    expect(
      classifyPaymentInvoice(businessType: 'INVOICE', title: '发票申请'),
      PaymentInvoiceKind.invoice,
    );
    expect(
      classifyPaymentInvoice(templateKey: 'electronic-reimbursement'),
      PaymentInvoiceKind.other,
    );
    expect(
      classifyPaymentInvoice(title: '招待费报销'),
      PaymentInvoiceKind.other,
    );
  });

  test('extracts purpose, corporate account and unissued amount', () {
    final row = paymentInvoiceRowFromListJson({
      'id': 88,
      'businessType': 'FINANCE_ADMIN_PROCUREMENT',
      'templateKey': 'finance-admin-procurement',
      'title': '行政采购审批',
      'status': 'APPROVED',
      'createdByName': '张三',
      'createdAt': '2026-09-01T08:00:00Z',
      'formData': {
        'expensePurpose': '对公采购办公设备',
        'payeeAccount': {'label': '平安银行', 'value': '6222****8888'},
        'payAccountType': '对公',
        'appliedAmount': '1,200.00',
        'issuedAmount': 200,
        'completed': false,
      },
    });
    expect(row.kind, PaymentInvoiceKind.payment);
    expect(row.purpose, '对公采购办公设备');
    expect(row.payeeAccount, '6222****8888');
    expect(row.payAccountType, '对公');
    expect(row.appliedAmount, 1200);
    expect(row.unissuedAmount, 1000);
    expect(row.paymentCompleted, isFalse);
  });

  test('invoice progress derives partial / completed / unissued', () {
    expect(
      parseInvoiceIssueStatus(applied: 1000, issued: 0),
      InvoiceIssueStatus.unissued,
    );
    expect(
      parseInvoiceIssueStatus(applied: 1000, issued: 400),
      InvoiceIssueStatus.partial,
    );
    expect(
      parseInvoiceIssueStatus(applied: 1000, issued: 1000),
      InvoiceIssueStatus.completed,
    );
    expect(
      parseInvoiceIssueStatus(explicit: '已完结', applied: 1000, issued: 10),
      InvoiceIssueStatus.completed,
    );
  });

  test('filters unfinished invoices by default', () {
    final open = paymentInvoiceRowFromListJson({
      'businessId': 1,
      'businessType': 'INVOICE',
      'title': '发票申请',
      'status': 'APPROVED',
      'formData': {'appliedAmount': 800, 'issuedAmount': 100},
    });
    final done = applyInvoiceProgress(
      open.copyWith(issueStatus: InvoiceIssueStatus.completed, issuedAmount: 800),
      const PaymentInvoiceProgress(
        issuedAmount: 800,
        issueStatus: InvoiceIssueStatus.completed,
      ),
    );
    const query = PaymentInvoiceQuery(
      kind: PaymentInvoiceKind.invoice,
      issueStatus: 'open',
    );
    expect(matchesPaymentInvoiceQuery(open, query), isTrue);
    expect(matchesPaymentInvoiceQuery(done, query), isFalse);
    expect(
      matchesPaymentInvoiceQuery(
        open,
        const PaymentInvoiceQuery(
          kind: PaymentInvoiceKind.payment,
        ),
      ),
      isFalse,
    );
  });

  test('formats money with thousands separators', () {
    expect(formatPaymentInvoiceMoney(null), '—');
    expect(formatPaymentInvoiceMoney(1234.5), '1,234.50');
  });

  test('builds a printable approval pdf', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await buildPaymentInvoicePdf(
      row: paymentInvoiceRowFromListJson({
        'businessId': 21,
        'businessType': 'FINANCE_ADMIN_PROCUREMENT',
        'title': '行政采购审批',
        'status': 'APPROVED',
        'createdByName': '洪梅',
        'createdAt': '2026-07-20T18:33:00',
        'formData': {
          'expensePurpose': '注销代理服务费',
          'payeeAccount': '苏州灵辰财税',
        },
      }),
      kind: PaymentInvoiceKind.payment,
    );
    expect(bytes.length, greaterThan(1000));
    expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]); // %PDF
  });
}
