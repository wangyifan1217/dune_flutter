import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/xflow/issue_invoice_todo.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:dunes_app/features/xflow/xflow_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class InvoiceService extends XflowService {
  InvoiceService()
    : super(
        session: const AuthSession(
          phone: '1',
          userId: 1,
          token: 't',
          apiBase: 'https://example.com',
          roles: [],
        ),
      );
  int finishCalls = 0;
  final previewAmounts = <double>[];
  final appendedAmounts = <double>[];
  bool failLoad = false;
  bool failFinish = false;
  @override
  Future<Map<String, dynamic>> uploadProposalFile({
    required Uint8List bytes,
    required String fileName,
    void Function(int)? onProgress,
  }) async => {'objectKey': 'new-file'};
  @override
  Future<Map<String, dynamic>> recognizeInvoice({
    required Uint8List bytes,
    required String fileName,
    String objectKey = '',
    String templateKey = '',
    String businessType = '',
    String businessId = '',
  }) async => {
    'invoice': {'recordId': 7, 'invoiceNo': 'new-1', 'total': 100},
  };
  @override
  Future<Map<String, dynamic>> previewIssuedInvoices({
    required int todoId,
    required double invoiceAmount,
  }) async {
    previewAmounts.add(invoiceAmount);
    return {
      'invoiceAmount': invoiceAmount,
      'unallocatedAmount': 0,
      'bills': [
        {'billNo': 'AR-1', 'allocateAmount': invoiceAmount},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> appendIssuedInvoices({
    required int todoId,
    required List<Map<String, dynamic>> invoiceFiles,
    required double invoiceAmount,
    String comment = '',
  }) async {
    appendedAmounts.add(invoiceAmount);
    return {};
  }

  @override
  Future<XflowSubmissionDetail> fetchSubmissionDetail({
    required String businessType,
    required int businessId,
  }) async {
    if (failLoad) throw Exception('读取失败');
    return XflowSubmissionDetail(
      id: businessId,
      templateKey: 'finance-invoice-request',
      businessType: businessType,
      businessId: businessId,
      title: '发票申请',
      status: 'APPROVED',
      formData: {
        'invoiceFiles': [
          {'fileName': '已开发票.pdf', 'status': 'done'},
        ],
      },
      createdById: 1,
      createdAt: null,
    );
  }

  @override
  Future<void> finishIssuedInvoices({
    required int todoId,
    String comment = '',
  }) async {
    finishCalls++;
    if (failFinish) throw Exception('待办已被其他人处理');
  }
}

final item = XflowProposalItem(
  id: 10,
  businessType: 'FINANCE_INVOICE_REQUEST',
  code: 'S-10',
  title: '发票申请',
  status: 'OPEN',
  createdByName: '申请人',
  createdAt: null,
  primaryAction: 'ISSUE_INVOICE',
  todoHint: const XflowTodoHint(
    id: 20,
    businessType: 'FINANCE_INVOICE_REQUEST',
    businessId: 10,
    status: 'OPEN',
    kind: 'TASK',
  ),
);

Future<void> openInvoice(WidgetTester tester, InvoiceService service) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => confirmIssueInvoiceBatch(
              context: context,
              service: service,
              item: item,
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

Future<void> addInvoice(WidgetTester tester) async {
  final file = File(
    '${Directory.systemTemp.path}/codex-invoice-finish-test-${DateTime.now().microsecondsSinceEpoch}.pdf',
  );
  file.writeAsBytesSync([0x25, 0x50, 0x44, 0x46]);
  addTearDown(file.deleteSync);
  final target = tester.widget<DropTarget>(find.byType(DropTarget).first);
  await tester.runAsync(() async {
    target.onDragDone!(
      DropDoneDetails(
        files: [DropItemFile(file.path, name: 'new.pdf')],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pumpAndSettle();
}

void main() {
  test(
    'finish sends an explicit completion request without invoice payload',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/todos/20/complete-task'));
        final body = jsonDecode(request.body) as Map;
        expect(body['action'], 'ISSUE_INVOICE');
        expect(body['finishIssueInvoice'], isTrue);
        expect(body.containsKey('payload'), isFalse);
        return http.Response('{"success":true,"data":{"status":"DONE"}}', 200);
      });
      final service = XflowService(
        session: const AuthSession(
          phone: '1',
          userId: 1,
          token: 't',
          apiBase: 'https://example.com',
          roles: [],
        ),
        client: client,
      );
      await service.finishIssuedInvoices(todoId: 20);
      client.close();
    },
  );
  testWidgets('unregistered invoice must be handled before finishing', (
    tester,
  ) async {
    final service = InvoiceService();
    await openInvoice(tester, service);
    await addInvoice(tester);
    expect(find.text('请先登记或移除本次发票，再完结待办。'), findsOneWidget);
    await tester.tap(find.text('完结待办'));
    await tester.pump();
    expect(service.finishCalls, 0);
    expect(find.text('确认完结'), findsNothing);
  });

  testWidgets('preview and submit use the final amount in the input', (
    tester,
  ) async {
    final service = InvoiceService();
    await openInvoice(tester, service);
    await addInvoice(tester);
    final amountField = find.byType(TextField).first;
    final confirm = find.text('确认本次开票');
    await tester.ensureVisible(amountField);
    expect(tester.widget<TextField>(amountField).controller!.text, '100.00');

    await tester.enterText(amountField, '');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(service.previewAmounts, isEmpty);
    expect(service.appendedAmounts, isEmpty);

    await tester.enterText(amountField, '90.00');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.enterText(amountField, '87.65');
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.textContaining('本次开票金额 ¥87.65'), findsOneWidget);
    await tester.tap(find.text('确认开票'));
    await tester.pumpAndSettle();
    expect(service.previewAmounts, [90, 87.65]);
    expect(service.appendedAmounts, [87.65]);
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgets('completion requires confirmation and closes the task', (
    tester,
  ) async {
    final service = InvoiceService();
    await openInvoice(tester, service);
    expect(find.text('完结待办'), findsOneWidget);
    await tester.tap(find.text('完结待办'));
    await tester.pumpAndSettle();
    expect(find.textContaining('当前已登记 1 个发票文件'), findsOneWidget);
    expect(service.finishCalls, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.finishCalls, 0);
    await tester.tap(find.text('完结待办'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认完结'));
    await tester.pumpAndSettle();
    expect(service.finishCalls, 1);
    expect(find.text('完结待办'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
  testWidgets('loading failure blocks completion and allows retry', (
    tester,
  ) async {
    final service = InvoiceService()..failLoad = true;
    await openInvoice(tester, service);
    expect(find.text('已开发票读取失败'), findsOneWidget);
    await tester.tap(find.text('完结待办'));
    await tester.pump();
    expect(service.finishCalls, 0);
    service.failLoad = false;
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完结待办'));
    await tester.pumpAndSettle();
    expect(find.text('确认完结'), findsOneWidget);
  });
  testWidgets('server error keeps the task dialog open', (tester) async {
    final service = InvoiceService()..failFinish = true;
    await openInvoice(tester, service);
    await tester.tap(find.text('完结待办'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认完结'));
    await tester.pumpAndSettle();
    expect(service.finishCalls, 1);
    expect(find.text('完结待办'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
