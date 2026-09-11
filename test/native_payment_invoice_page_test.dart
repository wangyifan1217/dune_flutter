import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/payment_invoice/native_payment_invoice_page.dart';
import 'package:dunes_app/features/payment_invoice/payment_invoice_service.dart';

void main() {
  Future<void> pumpWide(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(child);
  }

  const denied = AuthSession(
    phone: '13800138000',
    userId: 7,
    token: 'token',
    apiBase: 'http://example.test/api/v1',
    roles: [],
  );
  const allowed = AuthSession(
    phone: '13800138000',
    userId: 7,
    token: 'token',
    apiBase: 'http://example.test/api/v1',
    roles: [],
    paymentInvoiceAccess: true,
  );

  testWidgets('hides ledger when payment invoice access is off', (tester) async {
    await pumpWide(
      tester,
      const MaterialApp(
        home: Scaffold(
          body: NativePaymentInvoicePage(session: denied, staticPreview: false),
        ),
      ),
    );
    expect(find.text('暂无权限查看付款发票审批'), findsOneWidget);
    expect(find.text('付款审批'), findsNothing);
  });

  testWidgets('shows payment ledger filters and purpose column', (tester) async {
    final service = PaymentInvoiceService(
      session: allowed,
      progressStore: MemoryPaymentInvoiceProgressStore(),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/xflow/proposals/all')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': {
                  'items': [
                    {
                      'businessId': 21,
                      'businessType': 'FINANCE_PROMOTION_PAYMENT',
                      'templateKey': 'finance-promotion-payment',
                      'title': '推广费付款',
                      'status': 'APPROVED',
                      'createdByName': '王五',
                      'createdAt': '2026-09-03T02:00:00Z',
                      'formData': {
                        'expensePurpose': '渠道推广投放',
                        'payeeAccount': '对公户 9988',
                        'payAccountType': '对公',
                      },
                    },
                    {
                      'businessId': 22,
                      'businessType': 'INVOICE',
                      'title': '发票申请',
                      'status': 'APPROVED',
                      'createdByName': '赵六',
                      'createdAt': '2026-09-04T02:00:00Z',
                      'formData': {
                        'appliedAmount': 2000,
                        'issuedAmount': 500,
                        'customerName': '平安',
                        'expensePurpose': '信息服务费',
                      },
                    },
                  ],
                  'total': 2,
                },
              }),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    await pumpWide(
      tester,
      MaterialApp(
        home: Scaffold(
          body: NativePaymentInvoicePage(
            session: allowed,
            service: service,
            staticPreview: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('付款审批'), findsOneWidget);
    expect(find.text('发票审批'), findsOneWidget);
    expect(find.text('ID'), findsNothing);
    expect(find.text('渠道推广投放'), findsOneWidget);
    expect(find.text('查看'), findsOneWidget);
    expect(find.text('打印'), findsOneWidget);

    await tester.tap(find.text('发票审批'));
    await tester.pumpAndSettle();
    expect(find.text('信息服务费'), findsOneWidget);
    expect(find.text('平安'), findsOneWidget);
    expect(find.text('完结'), findsOneWidget);
    expect(find.text('下一页'), findsOneWidget);
  });

  testWidgets('static preview shows sample payment ledger without access', (
    tester,
  ) async {
    await pumpWide(
      tester,
      const MaterialApp(
        home: Scaffold(
          body: NativePaymentInvoicePage(session: denied, staticPreview: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('叶子扬行政采购审批'), findsWidgets);
    expect(find.text('查看'), findsWidgets);
    expect(find.text('打印'), findsWidgets);
    expect(find.textContaining('每页 10 条'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('年会场地布置及物料'), findsOneWidget);
  });
}
