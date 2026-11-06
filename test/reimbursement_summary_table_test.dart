import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/reimbursement/native_reimbursement_summary_page.dart';
import 'package:dunes_app/features/reimbursement/reimbursement_summary_service.dart';

void main() {
  testWidgets('明细和主体表显示来源数据及待核算金额', (tester) async {
    tester.view.physicalSize = const Size(2200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const session = AuthSession(
      phone: '',
      userId: 1,
      token: 'test',
      apiBase: 'https://example.test',
      roles: [],
    );
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'data': {
            'fields': {'entityLabel': '报销主体', 'amountLabel': '报销金额'},
            'count': 1,
            'amount': 100,
            'groups': [],
            'byPerson': [],
            'byEntity': [
              {'entity': '甲公司', 'count': 1, 'amount': 100},
            ],
            'details': [
              {
                'businessId': '101',
                'applicant': '张三',
                'department': '研发',
                'entity': '甲公司',
                'project': '项目甲',
                'amount': 100,
                'expenses': [
                  {'type': '差旅打车', 'amount': 25, 'description': '车费'},
                ],
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final service = ReimbursementSummaryService(
      session: session,
      client: client,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeReimbursementSummaryPage(
            session: session,
            service: service,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('明细'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('项目甲'), findsOneWidget);
    expect(find.textContaining('差旅打车'), findsOneWidget);
    expect(find.text('待核算'), findsNWidgets(2));
    await tester.tap(find.text('按报销主体'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('甲公司'), findsOneWidget);
    expect(find.text('待核算'), findsNWidgets(2));
    client.close();
  });

  testWidgets('汇总审批提交当前筛选条件', (tester) async {
    tester.view.physicalSize = const Size(2200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const session = AuthSession(
      phone: '',
      userId: 1,
      token: 'test',
      apiBase: 'https://example.test',
      roles: [],
    );
    Uri? submitted;
    final client = MockClient((request) async {
      if (request.method == 'POST') submitted = request.url;
      return http.Response(
        jsonEncode({
          'data': {
            'count': 1,
            'amount': 100,
            'groups': [],
            'byPerson': [],
            'byEntity': [],
            'details': [
              {
                'businessId': '101',
                'applicant': '张三',
                'entity': '甲公司',
                'amount': 100,
                'offsetAmount': 25,
                'paymentAmount': 75,
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = ReimbursementSummaryService(
      session: session,
      client: client,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeReimbursementSummaryPage(
            session: session,
            service: service,
            now: DateTime(2026, 11, 6),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reimbursement-submit-approval')));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未汇总的 1 张'), findsOneWidget);
    await tester.tap(find.text('发起审批'));
    await tester.pumpAndSettle();
    expect(submitted?.path, '/reimbursement-summary/submit');
    expect(submitted?.queryParameters['from'], '2026-11-01');
    expect(submitted?.queryParameters['to'], '2026-11-30');
    await tester.pump(const Duration(seconds: 3));
    client.close();
  });
}
