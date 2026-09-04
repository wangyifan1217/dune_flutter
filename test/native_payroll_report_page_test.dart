import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/payroll/native_payroll_report_page.dart';
import 'package:dunes_app/features/payroll/payroll_report_service.dart';

void main() {
  testWidgets('defaults to prior month and prefers the payroll sheet', (
    tester,
  ) async {
    final requests = <Uri>[];
    const session = AuthSession(
      phone: '13800138000',
      userId: 7,
      token: 'token',
      apiBase: 'http://example.test/api/v1',
      roles: [],
    );
    final service = PayrollReportService(
      session: session,
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/payroll-reports/rows')) {
          return http.Response.bytes(
            utf8.encode(
              '{"data":{"columns":[{"key":"c0","name":"姓名"},{"key":"c1","name":"实发"}],"rows":[{"c0":"张三","c1":1000}]}}',
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response.bytes(
          utf8.encode(
            '{"data":[{"archiveId":"archive-1","sheets":[{"reportId":"other","subReportId":"other-sheet","reportName":"其他表","rowCount":1},{"reportId":"payroll","subReportId":"payroll-sheet","reportName":"工资报表","rowCount":1}]}]}',
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NativePayrollReportPage(
          session: session,
          service: service,
          now: DateTime(2026, 9, 4),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026年8月'), findsOneWidget);
    expect(find.text('工资报表'), findsOneWidget);
    expect(find.text('张三'), findsOneWidget);
    expect(find.text('¥1,000.00'), findsNWidgets(2));
    expect(find.textContaining('1 人 · 实发'), findsOneWidget);
    expect(
      requests
          .where((uri) => uri.path.endsWith('/payroll-reports/rows'))
          .single
          .queryParameters['reportId'],
      'payroll',
    );
  });

  testWidgets('picks a payroll month without a day calendar', (tester) async {
    var yearmo = '';
    const session = AuthSession(
      phone: '13800138000',
      userId: 7,
      token: 'token',
      apiBase: 'http://example.test/api/v1',
      roles: [],
    );
    final service = PayrollReportService(
      session: session,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/payroll-reports/rows')) {
          yearmo = request.url.queryParameters['yearmo'] ?? '';
          return http.Response.bytes(
            utf8.encode(
              '{"data":{"columns":[{"key":"c0","name":"姓名"},{"key":"c1","name":"实发"}],"rows":[{"c0":"张三","c1":1000}]}}',
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response.bytes(
          utf8.encode(
            '{"data":[{"archiveId":"archive-1","sheets":[{"reportId":"payroll","subReportId":"payroll-sheet","reportName":"工资报表","rowCount":1}]}]}',
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NativePayrollReportPage(
          session: session,
          service: service,
          now: DateTime(2026, 9, 4),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payroll-month')));
    await tester.pumpAndSettle();

    expect(find.text('选择工资月份'), findsOneWidget);
    expect(find.text('2026年'), findsOneWidget);
    expect(find.text('7月'), findsOneWidget);
    expect(find.text('8月'), findsOneWidget);
    expect(find.text('1日'), findsNothing);

    await tester.tap(find.text('7月'));
    await tester.pumpAndSettle();

    expect(find.text('2026年7月'), findsOneWidget);
    expect(yearmo, '202607');
  });

  testWidgets('keeps identity numbers out of person cost cards', (
    tester,
  ) async {
    const session = AuthSession(
      phone: '13800138000',
      userId: 7,
      token: 'token',
      apiBase: 'http://example.test/api/v1',
      roles: [],
    );
    final service = PayrollReportService(
      session: session,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/payroll-reports/rows')) {
          return http.Response.bytes(
            utf8.encode(
              '{"data":{"columns":[{"key":"c0","name":"姓名"},{"key":"c1","name":"部门"},{"key":"c2","name":"身份证号"},{"key":"c3","name":"成本项合计"},{"key":"c4","name":"最新基本工资基数"}],"rows":[{"c0":"许正阳","c1":"总裁办","c2":"420106198204124032","c3":0,"c4":15000}]}}',
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response.bytes(
          utf8.encode(
            '{"data":[{"archiveId":"archive-1","sheets":[{"reportId":"payroll","subReportId":"payroll-sheet","reportName":"工资报表","rowCount":1}]}]}',
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await tester.binding.setSurfaceSize(const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: NativePayrollReportPage(
          session: session,
          service: service,
          now: DateTime(2026, 9, 4),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('许正阳'), findsOneWidget);
    expect(find.text('¥15,000.00'), findsNWidgets(2));
    expect(find.textContaining('身份证'), findsNothing);
    expect(find.textContaining('¥420'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('excludes summary rows and sorts cost high to low', (
    tester,
  ) async {
    const session = AuthSession(
      phone: '13800138000',
      userId: 7,
      token: 'token',
      apiBase: 'http://example.test/api/v1',
      roles: [],
    );
    final service = PayrollReportService(
      session: session,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/payroll-reports/rows')) {
          return http.Response.bytes(
            utf8.encode(
              '{"data":{"columns":[{"key":"c0","name":"姓名"},{"key":"c1","name":"部门"},{"key":"c2","name":"企业人工成本"}],"rows":[{"c0":"李四","c1":"技术中心","c2":800},{"c0":"张三","c1":"总裁办","c2":2000},{"c0":"【合计】","c1":"","c2":2800}]}}',
            ),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response.bytes(
          utf8.encode(
            '{"data":[{"archiveId":"archive-1","sheets":[{"reportId":"payroll","subReportId":"payroll-sheet","reportName":"工资报表","rowCount":3}]}]}',
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await tester.binding.setSurfaceSize(const Size(520, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: NativePayrollReportPage(
          session: session,
          service: service,
          now: DateTime(2026, 9, 4),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('合计'), findsNothing);
    expect(find.text('【合计】'), findsNothing);
    expect(find.textContaining('2 人'), findsOneWidget);
    expect(find.text('¥2,000.00'), findsWidgets);
    expect(find.text('¥800.00'), findsOneWidget);
    expect(find.text('¥2,800.00'), findsOneWidget);
    expect(find.text('¥5,600.00'), findsNothing);

    final high = tester.getTopLeft(find.text('张三'));
    final low = tester.getTopLeft(find.text('李四'));
    expect(high.dy, lessThan(low.dy));

    await tester.tap(find.byKey(const Key('payroll-sort')));
    await tester.pumpAndSettle();
    final lowFirst = tester.getTopLeft(find.text('李四'));
    final highSecond = tester.getTopLeft(find.text('张三'));
    expect(lowFirst.dy, lessThan(highSecond.dy));

    await tester.tap(find.byKey(const Key('payroll-group-dept')));
    await tester.pumpAndSettle();
    expect(find.text('总裁办'), findsWidgets);
    expect(find.textContaining('1 人 · ¥2,000.00'), findsOneWidget);

    await tester.tap(find.byKey(const Key('payroll-view-list')));
    await tester.pumpAndSettle();
    expect(find.text('张三'), findsOneWidget);
    expect(find.text('李四'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
