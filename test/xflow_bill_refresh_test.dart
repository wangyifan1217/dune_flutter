import 'package:dunes_app/features/xflow/xflow_bill_refresh.dart';
import 'package:dunes_app/features/xflow/xflow_detail_widgets.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:dunes_app/features/xflow/approval_chat_share.dart';
import 'package:dunes_app/features/xflow/approval_detail_dialog.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

XflowField billField(String key, String dir, {String kind = 'payable'}) =>
    XflowField.fromJson({
      'key': key,
      'type': 'billCascade',
      'label': key,
      'billDirection': dir,
      'remainingKind': kind,
    });
Map<String, dynamic> snapshot(
  int id,
  String dir, {
  String period = '2026.10',
}) => {
  'billId': id,
  'billNo': '$dir-$id',
  'billDirection': dir,
  'billTypeCode': 'TYPE',
  'billPeriod': period,
  'billAmount': 100,
  'paidAmount': 0,
  'invoiceAmount': 0,
  'remainingPayable': 100,
  'remainingInvoiceable': 100,
};
void main() {
  for (final (status, width) in [
    ('PENDING', 800.0),
    ('APPROVED', 800.0),
    ('APPROVED', 390.0),
    ('REJECTED', 800.0),
    ('WITHDRAWN', 800.0),
    ('VOIDED', 800.0),
  ]) {
    testWidgets('转发的 $status 审批打开时查询最新账单（宽度 $width）', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var queries = 0;
      final client = MockClient((request) async {
        final path = request.url.path;
        Object data = <String, dynamic>{};
        if (path.contains('/xflow/submissions/')) {
          data = {
            'id': 1,
            'businessId': 1291,
            'businessType': 'FINANCE_INVOICE_REQUEST',
            'templateKey': 'finance-invoice-request',
            'title': '发票申请',
            'status': status,
            'createdAt': '2026-11-11T10:54:18Z',
            'formData': {
              'linkedArBills': [snapshot(40999, 'AR')],
              'remainingInvoiceAmount': '100.00',
              'invoiceTotalLimit': '100.00',
            },
          };
        } else if (path.contains('/xflow/templates/')) {
          data = {
            'title': '发票申请',
            'fields': [
              {
                'key': 'linkedArBills',
                'type': 'billCascade',
                'label': '关联应收账单',
                'billDirection': 'AR',
                'remainingKind': 'invoice',
              },
            ],
          };
        } else if (path.endsWith('/asset/bills')) {
          queries++;
          data = [
            {
              ...snapshot(40999, 'AR'),
              'billAmount': 100,
              'invoiceAmount': 40,
              'remainingInvoiceable': 60,
            },
          ];
        } else if (path.endsWith('/todos') ||
            path.endsWith('/comments') ||
            path.endsWith('/org/users')) {
          data = <dynamic>[];
        }
        return http.Response(
          jsonEncode({'success': true, 'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showApprovalDetailOverlay(
                  context: context,
                  session: const AuthSession(
                    phone: '',
                    userId: 99,
                    token: 'test',
                    apiBase: 'https://example.com/api/v1',
                    roles: [],
                  ),
                  share: ApprovalChatShare(
                    businessType: 'FINANCE_INVOICE_REQUEST',
                    businessId: 1291,
                    title: '发票申请',
                    status: status,
                  ),
                  preferDialog: true,
                ),
                child: const Text('打开转发审批'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开转发审批'));
        await tester.pumpAndSettle();
        expect(queries, 1);
        expect(find.textContaining('账单信息已更新 · 审批金额以提交时为准'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('刷新账单'));
        await tester.tap(find.text('刷新账单'));
        await tester.pumpAndSettle();
        expect(queries, 2);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }, () => client);
    });
  }

  test('最新剩余可开同步到展示汇总，保留申请金额与原始快照', () async {
    final original = {
      'linkedArBills': [snapshot(1, 'AR')],
      'remainingInvoiceAmount': '100.00',
      'invoiceTotalLimit': '100.00',
    };
    final result = await refreshXflowApprovalBills(
      form: original,
      fields: [billField('linkedArBills', 'AR', kind: 'invoice')],
      fetch:
          ({
            required billDirection,
            required billTypeCode,
            required dateStart,
            required dateEnd,
            required pageNum,
          }) async => [
            {
              ...snapshot(1, 'AR'),
              'invoiceAmount': 40,
              'remainingInvoiceable': 60,
            },
          ],
    );
    expect(result.form['remainingInvoiceAmount'], '60.00');
    expect(result.form['invoiceTotalLimit'], '100.00');
    expect(original['remainingInvoiceAmount'], '100.00');
    expect((original['linkedArBills'] as List).first['invoiceAmount'], 0);
  });
  test('审批中刷新账单主体、项目、账期与金额，保留提交表单', () async {
    final original = {
      'bills': [
        {...snapshot(1, 'AP'), 'ourEntityName': '旧主体', 'projectName': '旧项目'},
        {...snapshot(2, 'AR'), 'ourEntityName': '原主体'},
      ],
      'paymentAmount': 30,
    };
    final result = await refreshXflowApprovalBills(
      form: original,
      fields: [billField('bills', 'AP')],
      fetch:
          ({
            required billDirection,
            required billTypeCode,
            required dateStart,
            required dateEnd,
            required pageNum,
          }) async => [
            if (billDirection == 'AP')
              {
                'billId': 1,
                'billNo': '新单号',
                'ourEntityName': '新主体',
                'counterpartyName': '新对方',
                'projectName': '新项目',
                'billPeriod': '2026.11',
                'province': '广东',
                'billTypeName': '采购款',
                'billAmount': 120,
                'paidAmount': 40,
                'remainingPayable': 80,
                'reconcileStatus': 'RECONCILED',
              }
            else
              {
                'billId': 2,
                'ourEntityName': '应收主体',
                'projectName': '应收项目',
                'billAmount': 200,
                'paidAmount': 60,
                'remainingPayable': 140,
              },
          ],
    );
    final rows = result.form['bills'] as List<Map<String, dynamic>>;
    expect(result.updated, 2);
    expect(rows[0]['ourEntityName'], '新主体');
    expect(rows[0]['projectName'], '新项目');
    expect(rows[0]['provinceName'], '广东');
    expect(rows[0]['billPeriod'], '2026.11');
    expect(rows[0]['remainingAmount'], 80);
    expect(rows[1]['ourEntityName'], '应收主体');
    expect(rows[1]['remainingAmount'], 140);
    expect((original['bills'] as List).first['ourEntityName'], '旧主体');
    expect(original['paymentAmount'], 30);
  });
  test('刷新跨分页账单并保留原审批快照和失败项', () async {
    final first = snapshot(1, 'AP'),
        second = snapshot(2, 'AP'),
        absent = snapshot(3, 'AR');
    final original = {
      'payable': [first, second],
      'receivable': [absent],
      'amount': 50,
    };
    final calls = <String>[];
    final result = await refreshXflowApprovalBills(
      form: original,
      fields: [billField('payable', 'AP'), billField('receivable', 'AR')],
      fetch:
          ({
            required billDirection,
            required billTypeCode,
            required dateStart,
            required dateEnd,
            required pageNum,
          }) async {
            calls.add('$billDirection-$pageNum');
            if (billDirection == 'AR') throw Exception('offline');
            if (pageNum == 1)
              return [
                {
                  'billId': 1,
                  'billAmount': 100,
                  'paidAmount': 40,
                  'remainingPayable': 60,
                  'invoiceAmount': 20,
                  'remainingInvoiceable': 80,
                },
                for (var i = 0; i < 199; i++) {'billId': 1000 + i},
              ];
            return [
              {
                'billId': 2,
                'billAmount': 100,
                'paidAmount': 25,
                'remainingPayable': 75,
                'invoiceAmount': 10,
                'remainingInvoiceable': 90,
              },
            ];
          },
    );
    expect(result.total, 3);
    expect(result.updated, 2);
    expect(calls, ['AP-1', 'AP-2', 'AR-1']);
    final pay = result.form['payable'] as List<Map<String, dynamic>>;
    expect(pay[0]['remainingPayable'], 60);
    expect(pay[1]['remainingPayable'], 75);
    expect(
      (result.form['receivable']
          as List<Map<String, dynamic>>)[0]['_billRefreshState'],
      'unavailable',
    );
    expect(first['remainingPayable'], 100);
    expect(first.containsKey('_billRefreshState'), isFalse);
    expect(original['amount'], 50);
  });
  test('旧账期缺年份时按提交年份向前查找并只接受相同账单 ID', () async {
    final original = {
      'bills': [snapshot(88, 'AR', period: '09.01-09.03')],
    };
    final starts = <String>[];
    final result = await refreshXflowApprovalBills(
      form: original,
      fields: [billField('bills', 'AR')],
      createdAt: DateTime(2026, 11),
      fetch:
          ({
            required billDirection,
            required billTypeCode,
            required dateStart,
            required dateEnd,
            required pageNum,
          }) async {
            starts.add(dateStart);
            if (dateStart.startsWith('2025'))
              return [
                {
                  'billId': 88,
                  'billAmount': 200,
                  'paidAmount': 80,
                  'remainingPayable': 120,
                },
              ];
            return [
              {'billId': 99, 'billAmount': 999, 'paidAmount': 0},
            ];
          },
    );
    expect(starts, ['2026-09-01', '2025-09-01']);
    expect(result.updated, 1);
    expect((result.form['bills'] as List).first['billAmount'], 200);
  });
  test('无账期线索和金额不完整时不冒充成功', () async {
    final rows = [snapshot(1, 'AP', period: '未知'), snapshot(2, 'AP')];
    final result = await refreshXflowApprovalBills(
      form: {'bills': rows},
      fields: [billField('bills', 'AP')],
      fetch:
          ({
            required billDirection,
            required billTypeCode,
            required dateStart,
            required dateEnd,
            required pageNum,
          }) async => [
            {'billId': 2, 'billAmount': 200},
          ],
    );
    expect(result.updated, 0);
    expect(result.failed, 2);
    expect(
      (result.form['bills'] as List).every(
        (r) => r['_billRefreshState'] == 'unavailable',
      ),
      isTrue,
    );
  });
  testWidgets('部分失败时标记旧数据并隐藏混合汇总', (tester) async {
    final rows = [
      {...snapshot(1, 'AP'), '_billRefreshState': 'updated'},
      {...snapshot(2, 'AP'), '_billRefreshState': 'unavailable'},
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: XfDetBillCascadeList(
              rows: rows,
              remainingKind: 'payable',
              billDirection: 'AP',
            ),
          ),
        ),
      ),
    );
    expect(find.text('账单信息已更新'), findsOneWidget);
    expect(find.text('未更新，显示提交时数据'), findsOneWidget);
    expect(find.textContaining('剩余应付合计'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
