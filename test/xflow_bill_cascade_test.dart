import 'package:dunes_app/features/xflow/xflow_bill_cascade.dart';
import 'package:dunes_app/features/xflow/xflow_detail_logic.dart';
import 'package:dunes_app/features/xflow/xflow_linkage.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bill cascade remaining follows 开票看可开、付款看应付', () {
    final row = {
      'billAmount': 100,
      'paidAmount': 20,
      'invoiceAmount': 10,
      'remainingPayable': 80,
      'remainingInvoiceable': 90,
    };
    expect(xflowBillPrimaryRemaining(row, 'payable'), 80);
    expect(xflowBillPrimaryRemaining(row, 'invoice'), 90);
    expect(xflowBillAmountLabels('payable'), ['默认金额', '已付', '剩余应付']);
    expect(xflowBillAmountLabels('payable', billDirection: 'AR'), [
      '默认金额',
      '已还',
      '剩余应还',
    ]);
    expect(xflowBillAmountLabels('invoice'), ['默认金额', '已开票', '剩余可开']);
  });

  test('selected snapshot keeps billId and label', () {
    final snap = xflowBillSnapshot({
      'id': 184,
      'billNo': 'AR-20260903-184',
      'ourEntityName': '上海卓悦',
      'counterpartyName': '湖北电信',
      'billPeriod': '09.01-09.03',
      'billAmount': 100,
      'paidAmount': 0,
      'remainingPayable': 100,
      'remainingInvoiceable': 100,
      'label': '上海卓悦 - 湖北电信 - 09.01-09.03',
    }, remainingKind: 'payable', billDirection: 'AR');
    expect(snap['billId'], 184);
    expect(snap['billDirection'], 'AR');
    expect(snap['label'], '上海卓悦 - 湖北电信 - 09.01-09.03');
    expect(xflowBillHasId(snap, 184), isTrue);
    expect(xflowBillHasId(snap, 1), isFalse);
  });

  test('detail line lists selected bills, expandable', () {
    final field = XflowField.fromJson({
      'key': 'linkedArBills',
      'type': 'billCascade',
      'label': '关联应收账单',
      'remainingKind': 'invoice',
    });
    final val = [
      {
        'billId': 1,
        'label': '甲 - 乙 - 09月',
        'billAmount': 100,
        'remainingInvoiceable': 40,
      },
    ];
    expect(formatFieldValue(field, val), '甲 - 乙 - 09月（剩余可开 40.00 元）');
    expect(isExpandableField(field, val), isTrue);
    expect(formatFieldValue(field, []), '');
  });

  test('selected remaining sum and preview keep 对应金额', () {
    final rows = [
      {'billAmount': 100, 'paidAmount': 20, 'remainingPayable': 80},
      {'billAmount': 50, 'paidAmount': 50, 'remainingPayable': 0},
    ];
    expect(xflowBillSelectedRemainingSum(rows, 'payable'), 80);
    expect(
      xflowBillRemainingSummaryLabel('payable', billDirection: 'AP'),
      '剩余应付合计',
    );
    expect(
      xflowBillRemainingSummaryLabel('invoice'),
      '剩余可开合计',
    );
    expect(
      xflowBillPreviewLine(rows.first, 'payable', billDirection: 'AP'),
      contains('剩余应付 80.00 元'),
    );
  });

  test('invoice remaining computed field follows selected AR bills', () {
    final fields = [
      XflowField.fromJson({
        'key': 'remainingInvoiceAmount',
        'type': 'computed',
        'readonly': true,
      }),
    ];
    final values = <String, dynamic>{
      'linkedArBills': [
        {'remainingInvoiceable': 40},
        {'remainingInvoiceable': 15},
      ],
    };
    XflowLinkage.recompute(fields, const {}, values);
    expect(values['remainingInvoiceAmount'], '55.00');
  });

  test('empty paymentAmount fills from selected AP remaining', () {
    final fields = [
      XflowField.fromJson({'key': 'paymentAmount', 'type': 'money'}),
    ];
    final values = <String, dynamic>{
      'linkedApBills': [
        {'remainingPayable': 80},
        {'remainingPayable': 20},
      ],
    };
    XflowLinkage.recompute(fields, const {}, values);
    expect(values['paymentAmount'], '100.00');
    values['paymentAmount'] = '30.00';
    XflowLinkage.recompute(fields, const {}, values);
    expect(values['paymentAmount'], '30.00');
  });
}
