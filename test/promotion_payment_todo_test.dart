import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/xflow/task_todo_actions.dart';
import 'package:dunes_app/features/xflow/xflow_models.dart';
import 'package:dunes_app/features/xflow/xflow_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PaymentService extends XflowService {
  _PaymentService()
    : super(
        session: const AuthSession(
          phone: '',
          userId: 1,
          token: 'test',
          apiBase: 'https://example.com',
          roles: [],
        ),
      );

  final entries = <Map<String, dynamic>>[];
  bool finished = false;

  @override
  Future<XflowSubmissionDetail> fetchSubmissionDetail({
    required String businessType,
    required int businessId,
  }) async => XflowSubmissionDetail(
    id: businessId,
    templateKey: 'finance-promotion-payment',
    businessType: businessType,
    businessId: businessId,
    title: '推广费付款申请单',
    status: 'APPROVED',
    createdById: 1,
    createdAt: null,
    formData: {
      'paymentItems': [
        {'promoterName': '推广商甲', 'paymentAmount': '100.01'},
        {'promoterName': '推广商乙', 'paymentAmount': '200.02'},
      ],
      'promotionPaymentEntries': List.of(entries),
    },
  );

  @override
  Future<Map<String, dynamic>> uploadProposalFile({
    required Uint8List bytes,
    required String fileName,
    void Function(int)? onProgress,
  }) async => {'objectKey': 'voucher-${entries.length}'};

  @override
  Future<void> registerPromotionPayment({
    required int todoId,
    required int itemIndex,
    required String requestId,
    required Map<String, dynamic> payload,
    required String comment,
  }) async {
    expect(todoId, 20);
    expect(requestId, isNotEmpty);
    if (entries.isEmpty) {
      expect(payload.containsKey('paymentVoucher'), isFalse);
    } else {
      expect(payload['paymentVoucher'], isNotEmpty);
    }
    entries.add({
      'itemIndex': itemIndex,
      'actualPayAmount': payload['actualPayAmount'],
      'paymentVoucher': payload['paymentVoucher'],
    });
  }

  @override
  Future<void> finishPromotionPayment(int todoId) async {
    expect(todoId, 20);
    finished = true;
  }
}

void main() {
  testWidgets(
    'the active promotion todo saves separate payments before finishing',
    (tester) async {
      tester.view.physicalSize = const Size(430, 880);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _PaymentService();
      final item = XflowProposalItem(
        id: 10,
        businessType: 'FINANCE_PROMOTION_PAYMENT',
        code: 'PP-10',
        title: '推广费付款申请单',
        status: 'OPEN',
        createdByName: '',
        createdAt: null,
        templateKey: 'finance-promotion-payment',
        primaryAction: 'MARK_PAID',
        todoHint: const XflowTodoHint(
          id: 20,
          businessType: 'FINANCE_PROMOTION_PAYMENT',
          businessId: 10,
          status: 'OPEN',
          kind: 'TASK',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => confirmAndCompleteTaskTodo(
                  context: context,
                  service: service,
                  item: item,
                ),
                child: const Text('打开待办'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开待办'));
      await tester.pumpAndSettle();
      final finish = find.widgetWithText(FilledButton, '完结待办');
      expect(tester.widget<FilledButton>(finish).onPressed, isNull);

      final fixture = Directory.systemTemp.createTempSync(
        'promotion-payment-test',
      );
      final file = File('${fixture.path}/receipt.pdf')
        ..writeAsBytesSync([37, 80, 68, 70]);
      addTearDown(() {
        file.deleteSync();
        fixture.deleteSync();
      });
      Future<void> register(Finder action, String amount) async {
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        final amountField = find.widgetWithText(TextField, '实付金额');
        await tester.enterText(amountField, amount);
        if (amount != '40.01') {
          final drop = tester.widget<DropTarget>(find.byType(DropTarget).last);
          await tester.runAsync(() async {
            drop.onDragDone!(
              DropDoneDetails(
                files: [DropItemFile(file.path, name: 'receipt.pdf')],
                localPosition: Offset.zero,
                globalPosition: Offset.zero,
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 200));
          });
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('保存本次付款'));
        await tester.pumpAndSettle();
      }

      final actions = find.widgetWithText(TextButton, '登记付款');
      await register(actions.first, '40.01');
      expect(find.text('剩余 ¥60.00'), findsOneWidget);
      expect(tester.widget<FilledButton>(finish).onPressed, isNull);
      await register(actions.first, '60.00');
      await register(actions, '200.02');
      expect(service.entries.map((item) => item['itemIndex']), [0, 0, 1]);
      expect(service.finished, isFalse);
      await tester.tap(finish);
      await tester.pumpAndSettle();
      expect(service.finished, isTrue);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    },
  );
}
