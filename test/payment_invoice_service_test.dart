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

  test('lists payment rows from payment-invoices using list formData only', () async {
    var detailHits = 0;
    String? kind;
    final service = PaymentInvoiceService(
      session: session,
      progressStore: MemoryPaymentInvoiceProgressStore(),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/payment-invoices')) {
          kind = request.url.queryParameters['kind'];
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
                      'tagLabel': '付款审批',
                      'title': '行政采购审批',
                      'status': 'APPROVED',
                      'createdByName': '李四',
                      'createdAt': '2026-09-02T10:00:00Z',
                      'formData': {
                        'expensePurpose': '服务器托管费',
                        'payeeAccount': '招商银行 1234',
                        'payAccountType': '对公',
                      },
                    },
                    {
                      'id': 99,
                      'businessType': 'PROPOSAL',
                      'title': '销售提案',
                      'status': 'APPROVED',
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
        if (request.url.path.contains('/xflow/submissions/FINANCE_ADMIN_PROCUREMENT/')) {
          detailHits += 1;
        }
        return http.Response('not found', 404);
      }),
    );

    final result = await service.fetchLedger(
      const PaymentInvoiceQuery(kind: PaymentInvoiceKind.payment),
    );
    expect(kind, 'payment');
    expect(detailHits, 0);
    expect(result.usedMineFallback, isFalse);
    expect(result.rows, hasLength(1));
    expect(result.rows.single.purpose, '服务器托管费');
    expect(result.rows.single.payAccountType, '对公');
    expect(result.rows.single.paymentCompleted, isTrue);
  });

  test('uses backend page payload without slicing extra rows', () async {
    String? page;
    String? pageSize;
    final service = PaymentInvoiceService(
      session: session,
      progressStore: MemoryPaymentInvoiceProgressStore(),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/payment-invoices')) {
          page = request.url.queryParameters['page'];
          pageSize = request.url.queryParameters['pageSize'];
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': {
                  'items': [
                    {
                      'businessId': 11,
                      'businessType': 'FINANCE_ADMIN_PROCUREMENT',
                      'templateKey': 'finance-admin-procurement',
                      'tagLabel': '付款审批',
                      'title': '行政采购审批',
                      'status': 'APPROVED',
                      'formData': {'expensePurpose': '第一页'},
                    },
                  ],
                  'total': 23,
                  'page': 2,
                  'pageSize': 10,
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
        page: 2,
        pageSize: 10,
      ),
    );
    expect(page, '2');
    expect(pageSize, '10');
    expect(result.serverPaged, isTrue);
    expect(result.total, 23);
    expect(result.rows, hasLength(1));
    expect(result.rows.single.purpose, '第一页');
  });

  test('slices locally when backend omits page metadata', () async {
    final service = PaymentInvoiceService(
      session: session,
      progressStore: MemoryPaymentInvoiceProgressStore(),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/payment-invoices')) {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': {
                  'items': [
                    for (var i = 1; i <= 12; i++)
                      {
                        'businessId': i,
                        'businessType': 'FINANCE_ADMIN_PROCUREMENT',
                        'templateKey': 'finance-admin-procurement',
                        'tagLabel': '付款审批',
                        'title': '行政采购$i',
                        'status': 'APPROVED',
                      },
                  ],
                  'total': 12,
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
        page: 2,
        pageSize: 10,
      ),
    );
    expect(result.serverPaged, isFalse);
    expect(result.total, 12);
    expect(result.rows, hasLength(2));
    expect(result.rows.first.id, 11);
  });

  test('empty dedicated list does not fall back to mine', () async {
    var mineHits = 0;
    final service = PaymentInvoiceService(
      session: session,
      progressStore: MemoryPaymentInvoiceProgressStore(),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/payment-invoices')) {
          return http.Response.bytes(
            utf8.encode(jsonEncode({'data': {'items': <dynamic>[], 'total': 0}})),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('/xflow/submissions/mine')) {
          mineHits += 1;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': [
                  {
                    'businessId': 5,
                    'businessType': 'INVOICE',
                    'tagLabel': '发票审批',
                    'title': '发票申请',
                    'status': 'APPROVED',
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
      const PaymentInvoiceQuery(kind: PaymentInvoiceKind.invoice),
    );
    expect(mineHits, 0);
    expect(result.usedMineFallback, isFalse);
    expect(result.rows, isEmpty);
  });

  test('falls back to mine when dedicated list is unavailable', () async {
    final service = PaymentInvoiceService(
      session: session,
      progressStore: MemoryPaymentInvoiceProgressStore(),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/payment-invoices')) {
          return http.Response('{"message":"not found"}', 404);
        }
        if (request.url.path.endsWith('/xflow/submissions') &&
            !request.url.path.contains('/mine')) {
          return http.Response('{"message":"not found"}', 404);
        }
        if (request.url.path.endsWith('/xflow/submissions/mine')) {
          if (request.url.queryParameters['viewAll'] == '1') {
            return http.Response('{"message":"not found"}', 404);
          }
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'data': [
                  {
                    'businessId': 5,
                    'businessType': 'INVOICE',
                    'tagLabel': '发票审批',
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
