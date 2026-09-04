import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/payroll/payroll_report_service.dart';

void main() {
  const session = AuthSession(
    phone: '13800138000',
    userId: 7,
    token: 'token',
    apiBase: 'http://example.test/api/v1',
    roles: [],
  );

  test('lists archive sheets from backend metadata payload', () async {
    final service = PayrollReportService(
      session: session,
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/payroll-reports');
        expect(request.url.queryParameters['yearmo'], '202608');
        return http.Response.bytes(
          utf8.encode(
            '{"data":[{"archiveId":"archive-1","archiveName":"2026年8月工资","sheets":[{"reportId":"report-1","subReportId":"sheet-1","reportName":"工资报表","rowCount":12}]}]}',
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final sheets = await service.listSheets('202608');
    expect(sheets, hasLength(1));
    expect(sheets.single.reportId, 'report-1');
    expect(sheets.single.subReportId, 'sheet-1');
    expect(sheets.single.name, '工资报表');
  });

  test('loads dynamic rows and encodes query parameters', () async {
    final sheet = PayrollReportSheet(
      reportId: 'r 1',
      subReportId: 's 1',
      name: '工资报表',
    );
    final service = PayrollReportService(
      session: session,
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/payroll-reports/rows');
        expect(request.url.queryParameters, {
          'yearmo': '202608',
          'reportId': 'r 1',
          'subReportId': 's 1',
          'q': '张 三',
        });
        return http.Response.bytes(
          utf8.encode(
            '{"data":{"columns":[{"key":"c0","name":"姓名"},{"key":"c1","name":"实发"}],"rows":[{"c0":"张三","c1":1000}]}}',
          ),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final table = await service.fetchRows(
      yearmo: '202608',
      sheet: sheet,
      q: '张 三',
    );
    expect(table.columns.map((column) => column.key), ['c0', 'c1']);
    expect(table.columns.map((column) => column.name), ['姓名', '实发']);
    expect(table.rows.single['c1'], 1000);
  });
}
