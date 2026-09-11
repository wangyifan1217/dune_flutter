import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/payment_invoice/payment_invoice_catalog.dart';
import 'package:dunes_app/features/payment_invoice/payment_invoice_service.dart';

void main() {
  const session = AuthSession(
    phone: '13800138000',
    userId: 7,
    token: 'token',
    apiBase: 'http://example.test/api/v1',
    roles: [],
    paymentInvoiceAccess: true,
  );

  test('lists payment rows from proposals/all and enriches form fields', () async {
    final service = PaymentInvoiceService(
      session: session,
      progressStore: MemoryPaymentInvoiceProgressStore(),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/xflow/proposals/all')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': {
                  'items': [
                    {
                      'id': 11,
                      'businessId': 11,
                      'businessType': 'FINANCE_ADMIN_PROCUREMENT',
                      'templateKey': 'finance-admin-procurement',
                      'title': '行政采购审批',
                      'status': 'APPROVED',
                      'createdByName': '李四',
                      'createdAt': '2026-09-02T10:00:00Z',
                    },
                    {
                      'id': 99,
                      'businessType': 'PROPOSAL',
                      'title': '销售提案',
                      'status': 'APPROVED',
                    },
                  ],
                  'total': 2,
                  'page': 1,
                  'pageSize': 50,
                },
              }),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('/xflow/submissions/FINANCE_ADMIN_PROCUREMENT/11')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': {
                  'formData': {
                    'expensePurpose': '服务器托管费',
                    'payeeAccount': '招商银行 1234',
                    'payAccountType': '对公',
                  },
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

    final result = await service.fetchLedger(
      const PaymentInvoiceQuery(
        kind: PaymentInvoiceKind.payment,
        status: 'APPROVED',
      ),
    );
    expect(result.usedMineFallback, isFalse);
    expect(result.rows, hasLength(1));
    expect(result.rows.single.purpose, '服务器托管费');
    expect(result.rows.single.payAccountType, '对公');
  });

  test('falls back to mine when all-approvals is unavailable', () async {
    final service = PaymentInvoiceService(
      session: session,
      progressStore: MemoryPaymentInvoiceProgressStore(),
      client: MockClient((request) async {
        if (request.url.path.contains('/xflow/proposals/all')) {
          return http.Response('{"message":"forbidden"}', 403);
        }
        if (request.url.path.endsWith('/xflow/submissions/mine')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': [
                  {
                    'businessId': 5,
                    'businessType': 'INVOICE',
                    'title': '发票申请',
                    'status': 'APPROVED',
                    'formData': {
                      'appliedAmount': 500,
                      'issuedAmount': 0,
                      'customerName': '平安',
                    },
                  },
                ],
              }),
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    final result = await service.fetchLedger(
      const PaymentInvoiceQuery(
        kind: PaymentInvoiceKind.invoice,
        issueStatus: 'open',
      ),
    );
    expect(result.usedMineFallback, isTrue);
    expect(result.rows, hasLength(1));
    expect(result.rows.single.counterparty, '平安');
    expect(result.rows.single.unissuedAmount, 500);
  });

  test('keeps invoice progress locally when write API is missing', () async {
    final store = MemoryPaymentInvoiceProgressStore();
    final service = PaymentInvoiceService(
      session: session,
      progressStore: store,
      client: MockClient((request) async {
        return http.Response('{"message":"not found"}', 404);
      }),
    );
    final row = paymentInvoiceRowFromListJson({
      'businessId': 8,
      'businessType': 'INVOICE',
      'title': '发票申请',
      'formData': {'appliedAmount': 1000, 'issuedAmount': 0},
    });
    await expectLater(
      service.saveInvoiceProgress(
        row: row,
        issuedAmount: 300,
        issueStatus: InvoiceIssueStatus.partial,
      ),
      throwsA(isA<PaymentInvoiceProgressPendingException>()),
    );
    final local = await store.load();
    expect(local['INVOICE:8']?.issuedAmount, 300);
  });
}
