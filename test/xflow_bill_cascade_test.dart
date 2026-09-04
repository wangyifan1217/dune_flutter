import 'package:dunes_app/features/xflow/xflow_bill_cascade.dart';
import 'package:dunes_app/features/xflow/xflow_bill_cascade_field.dart';
import 'package:dunes_app/features/xflow/xflow_detail_logic.dart';
import 'package:dunes_app/features/xflow/xflow_form_styles.dart';
import 'package:dunes_app/features/xflow/xflow_linkage.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:flutter/material.dart';
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

  test('selected card keeps bill type and project', () {
    final snap = xflowBillSnapshot({
      'id': 184,
      'billTypeCode': 'COUPON',
      'billTypeName': '券包销售款',
      'projectName': '吉林移动',
      'ourEntityName': '宁波纵横',
      'counterpartyName': '能链石化',
      'billPeriod': '2026-07-31',
      'billAmount': 100,
      'remainingPayable': 100,
    }, remainingKind: 'payable', billDirection: 'AP');
    expect(snap['billTypeName'], '券包销售款');
    expect(snap['projectName'], '吉林移动');
    expect(xflowBillTypeProjectLine(snap), '券包销售款 · 吉林移动');
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

    final sections = buildFieldSections(
      [field],
      {
        'linkedArBills': [
          val.first,
          {
            'billId': 2,
            'label': '丙 - 丁 - 09月',
            'remainingInvoiceable': 15,
          },
        ],
      },
      const XflowProposalDetail(
        id: 1,
        code: 'T-1',
        title: 't',
        status: 'pending',
        summary: '',
        beaconId: '',
        ownerName: '',
        amountText: '',
        formValues: {},
        products: [],
        slots: [],
        createdById: 1,
        raw: {},
      ),
    );
    expect(sections, isNotEmpty);
    expect(sections.first.items.single.value, '2笔');
    expect(sections.first.items.single.expandable, isTrue);
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

  test('zero paymentAmount is treated as empty and fills from AP', () {
    final fields = [
      XflowField.fromJson({'key': 'paymentAmount', 'type': 'money'}),
    ];
    final values = <String, dynamic>{
      'paymentAmount': '0.00',
      'linkedApBills': [
        {'remainingPayable': 80},
      ],
    };
    XflowLinkage.recompute(fields, const {}, values);
    expect(values['paymentAmount'], '80.00');
  });

  test('zero totalAmount fills from AR remaining when AP is empty', () {
    final fields = [
      XflowField.fromJson({
        'key': 'linkedArBills',
        'type': 'billCascade',
        'billDirection': 'AR',
        'remainingKind': 'payable',
      }),
      XflowField.fromJson({'key': 'totalAmount', 'type': 'money'}),
    ];
    final values = <String, dynamic>{
      'totalAmount': '0.00',
      'linkedArBills': [
        {'remainingPayable': 24372},
        {'remainingPayable': 52738},
        {'remainingPayable': 25922.01},
      ],
    };
    XflowLinkage.recompute(fields, const {}, values);
    expect(values['totalAmount'], '103032.01');
    values['totalAmount'] = '30.00';
    XflowLinkage.recompute(fields, const {}, values);
    expect(values['totalAmount'], '30.00');
  });

  test('totalAmount prefers AP remaining when both AR and AP are selected', () {
    final fields = [
      XflowField.fromJson({
        'key': 'linkedArBills',
        'type': 'billCascade',
        'billDirection': 'AR',
        'remainingKind': 'payable',
      }),
      XflowField.fromJson({
        'key': 'linkedApBills',
        'type': 'billCascade',
        'billDirection': 'AP',
        'remainingKind': 'payable',
      }),
      XflowField.fromJson({'key': 'totalAmount', 'type': 'money'}),
    ];
    final values = <String, dynamic>{
      'totalAmount': 0,
      'linkedArBills': [
        {'remainingPayable': 100},
      ],
      'linkedApBills': [
        {'remainingPayable': 20},
      ],
    };
    XflowLinkage.recompute(fields, const {}, values);
    expect(values['totalAmount'], '20.00');
  });

  test('readonly totalAmount stays on payment card sum when non-zero', () {
    final fields = [
      XflowField.fromJson({
        'key': 'paymentItems',
        'type': 'dynamicList',
        'itemLayout': 'card',
        'columns': [
          {'key': 'paymentAmount', 'type': 'money'},
        ],
      }),
      XflowField.fromJson({
        'key': 'totalAmount',
        'type': 'money',
        'readonly': true,
      }),
      XflowField.fromJson({
        'key': 'linkedArBills',
        'type': 'billCascade',
        'billDirection': 'AR',
        'remainingKind': 'payable',
      }),
    ];
    final values = <String, dynamic>{
      'paymentItems': [
        {'paymentAmount': '50.00'},
      ],
      'linkedArBills': [
        {'remainingPayable': 100},
      ],
    };
    XflowLinkage.recompute(fields, const {}, values);
    expect(values['totalAmount'], '50.00');
  });

  test('readonly totalAmount fills from bills when payment cards are empty', () {
    final fields = [
      XflowField.fromJson({
        'key': 'paymentItems',
        'type': 'dynamicList',
        'itemLayout': 'card',
        'columns': [
          {'key': 'paymentAmount', 'type': 'money'},
        ],
      }),
      XflowField.fromJson({
        'key': 'totalAmount',
        'type': 'money',
        'readonly': true,
      }),
      XflowField.fromJson({
        'key': 'linkedArBills',
        'type': 'billCascade',
        'billDirection': 'AR',
        'remainingKind': 'payable',
      }),
    ];
    final values = <String, dynamic>{
      'paymentItems': [
        {'paymentAmount': '0.00'},
      ],
      'linkedArBills': [
        {'remainingPayable': 100},
      ],
    };
    XflowLinkage.recompute(fields, const {}, values);
    expect(values['totalAmount'], '100.00');
  });

  test('bill period start/end can be picked and swapped if reversed', () {
    expect(
      xflowBillFormatYmd(DateTime(2026, 9, 1)),
      '2026-09-01',
    );
    expect(
      xflowBillNormalizePeriod(
        start: DateTime(2026, 9, 30),
        end: DateTime(2026, 9, 1),
      ),
      (start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 30)),
    );
    expect(
      xflowBillNormalizePeriod(start: DateTime(2026, 9, 1), end: null),
      isNull,
    );
  });

  test('bill cycle query is a calendar month, display drops timestamps', () {
    expect(
      xflowBillMonthBounds(DateTime(2026, 9, 18)),
      (start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 30)),
    );
    expect(
      xflowBillMonthBounds(DateTime(2026, 2, 1)),
      (start: DateTime(2026, 2, 1), end: DateTime(2026, 2, 28)),
    );
    expect(
      xflowBillCompactPeriod('2026-09-03 00:00:00 至 2026-09-03 23:59:59'),
      '2026-09-03',
    );
    expect(
      xflowBillCompactPeriod('2026-09-01 00:00:00 至 2026-09-30 23:59:59'),
      '2026.09',
    );
    expect(
      xflowBillCompactPeriod('2026-09-03 00:00:00 至 2026-09-10 23:59:59'),
      '09.03-09.10',
    );
    expect(xflowBillCompactPeriod('09.01-09.03'), '09.01-09.03');
    expect(
      xflowBillLabelOf({
        'ourEntityName': '广州亿力',
        'counterpartyName': '深圳万里通',
        'billPeriod': '2026-09-03 00:00:00 至 2026-09-03 23:59:59',
      }),
      '广州亿力 - 深圳万里通 - 2026-09-03',
    );
  });

  testWidgets('selected cards stay on the form; picker opens as a dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: XflowBillCascadeField(
            field: XflowField.fromJson({
              'key': 'linkedArBills',
              'type': 'billCascade',
              'label': '关联应收账单',
            }),
            value: const [
              {
                'billId': 1,
                'label': '宁波纵横 - 能链石化 - 2026-07-31',
                'billTypeName': '券包销售款',
                'projectName': '吉林移动',
                'billAmount': 100,
                'paidAmount': 0,
                'remainingPayable': 100,
              },
            ],
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('宁波纵横 - 能链石化 - 2026-07-31'), findsOneWidget);
    expect(find.text('券包销售款 · 吉林移动'), findsOneWidget);
    expect(find.text('+ 添加账单'), findsOneWidget);
    expect(find.byType(XfAddRowButton), findsOneWidget);
    expect(find.text('账单类型'), findsNothing);
    expect(find.text('完成'), findsNothing);

    await tester.tap(find.text('+ 添加账单'));
    await tester.pump();
    expect(find.text('完成'), findsOneWidget);
    expect(find.text('账单类型'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    expect(find.text('账单周期'), findsOneWidget);
    expect(find.text('关键词'), findsOneWidget);
  });
}
