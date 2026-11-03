import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:dunes_app/features/xflow/xflow_upload_field.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _invoice(String no, String total, {bool blocked = false, String message = ''}) => {
  'id': 'uf-$no',
  'fileName': '$no.pdf',
  'status': 'done',
  'invoiceStatus': 'done',
  'invoiceRecordId': 1,
  'invoiceBlocked': blocked,
  'invoiceMessage': message,
  'invoice': {'recordId': 1, 'invoiceNo': no, 'total': total, 'invoiceDate': '2026-10-08', 'sellerName': '某酒店'},
};

void main() {
  final field = XflowField.fromJson({
    'key': 'invoiceFiles',
    'type': 'upload',
    'label': '发票',
    'visibleWhen': 'reimbursementType=日常报销',
    'meta': {'invoiceOcr': true},
  });

  test('sums recognized invoices and counts blocked ones', () {
    final items = [
      _invoice('26440000000000000001', '120.50'),
      _invoice('26440000000000000002', '80.00'),
      _invoice('26440000000000000003', '10.00', blocked: true, message: '发票 26440000000000000003 已在报销单中审批通过，不能重复提交'),
      {'fileName': 'x.pdf', 'status': 'done', 'invoiceStatus': 'recognizing'},
    ];
    final s = xflowInvoiceSummary([
      ...items,
      {'fileName': 'scan.pdf', 'status': 'done', 'invoiceStatus': 'done', 'invoiceUnrecognized': true, 'invoice': {'recordId': 9}},
    ]);
    expect(s.count, 2);
    expect(s.total, 200.5);
    expect(s.blocked, 1);
    expect(s.pending, 1);
    expect(s.unrecognized, 1);
    expect(xflowInvoiceLine(items[0]), '发票号 26440000000000000001 · 2026-10-08 · 某酒店 · ¥120.50');
  });

  test('fills amount, detail and tax from recognized invoices', () {
    final items = [
      _invoice('1', '46.00'),
      _invoice('2', '6.52'),
    ];
    items[0]['invoice']['goodsDesc'] = '*运输服务';
    items[0]['invoice']['taxAmount'] = '2.60';
    items[1]['invoice']['goodsDesc'] = '*运输服务';
    items[1]['invoice']['taxAmount'] = '0.37';
    expect(xflowInvoiceFormFill(items), {
      'invoiceAmount': '52.52',
      'taxAmount': '2.97',
      'invoiceDetail': '*运输服务 ¥46.00\n*运输服务 ¥6.52',
    });
    expect(
      xflowInvoiceFormFill([
        {'fileName': 'scan.pdf', 'status': 'done', 'invoiceUnrecognized': true},
      ]),
      isEmpty,
    );
    expect(xflowInvoiceFormFill(const []), {
      'invoiceAmount': '',
      'invoiceDetail': '',
      'taxAmount': '',
    });
  });

  test('blocks submit on duplicates or recognizing invoices, allows unrecognized ones', () {
    expect(xflowIsInvoiceField(field), isTrue);
    final ok = {'reimbursementType': '日常报销', 'invoiceFiles': [_invoice('1', '1.00'), _invoice('2', '2.00')]};
    expect(xflowInvoiceSubmitProblem([field], ok), isNull);

    final approved = {
      'reimbursementType': '日常报销',
      'invoiceFiles': [_invoice('1', '1.00', blocked: true, message: '已在报销单中审批通过')],
    };
    expect(xflowInvoiceSubmitProblem([field], approved), contains('审批通过'));

    final twice = {'reimbursementType': '日常报销', 'invoiceFiles': [_invoice('1', '1.00'), _invoice('1', '1.00')]};
    expect(xflowInvoiceSubmitProblem([field], twice), contains('重复上传'));

    final noRecord = {
      'reimbursementType': '日常报销',
      'invoiceFiles': [{'fileName': 'a.pdf', 'status': 'done'}],
    };
    // 识别不了的可以提交（审批页提示人工核对）。
    expect(xflowInvoiceSubmitProblem([field], noRecord), isNull);
    expect(
      xflowInvoiceUnrecognized(
        Map<String, dynamic>.from((noRecord['invoiceFiles'] as List).first as Map),
      ),
      isTrue,
    );
    final recognizing = {
      'reimbursementType': '日常报销',
      'invoiceFiles': [{'fileName': 'a.pdf', 'status': 'done', 'invoiceStatus': 'recognizing'}],
    };
    expect(xflowInvoiceSubmitProblem([field], recognizing), contains('还在识别'));

    // 补贴报销看不到发票字段，不检查。
    final subsidy = {'reimbursementType': '补贴报销', 'invoiceFiles': noRecord['invoiceFiles']};
    expect(xflowInvoiceSubmitProblem([field], subsidy), isNull);
  });
}
