import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';

class PayrollReportAccess {
  const PayrollReportAccess({required this.allowed});
  final bool allowed;

  factory PayrollReportAccess.fromJson(Map<String, dynamic> json) =>
      PayrollReportAccess(
        allowed: json['allowed'] == true || json['access'] == true,
      );
}

class PayrollReportSheet {
  const PayrollReportSheet({
    required this.reportId,
    required this.subReportId,
    required this.name,
  });

  final String reportId;
  final String subReportId;
  final String name;

  factory PayrollReportSheet.fromJson(Map<String, dynamic> json) {
    return PayrollReportSheet(
      reportId: '${json['reportId'] ?? json['id'] ?? ''}',
      subReportId:
          '${json['subReportId'] ?? json['sheetId'] ?? json['subId'] ?? ''}',
      name:
          '${json['subReportName'] ?? json['sheetName'] ?? json['name'] ?? json['reportName'] ?? '未命名报表'}',
    );
  }
}

class PayrollReportTable {
  const PayrollReportTable({required this.columns, required this.rows});
  final List<PayrollReportColumn> columns;
  final List<Map<String, dynamic>> rows;

  factory PayrollReportTable.fromJson(Object? raw) {
    final data = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final rawRows = data['rows'] ?? data['list'] ?? data['items'] ?? const [];
    final rows = rawRows is List
        ? rawRows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : <Map<String, dynamic>>[];
    final rawColumns =
        data['columns'] ?? data['headers'] ?? data['fields'] ?? const [];
    final columns = rawColumns is List
        ? rawColumns
              .map((value) {
                if (value is Map) {
                  return PayrollReportColumn.fromJson(
                    Map<String, dynamic>.from(value),
                  );
                }
                final key = '$value';
                return PayrollReportColumn(key: key, name: key);
              })
              .where((value) => value.key.isNotEmpty)
              .toList()
        : <PayrollReportColumn>[];
    return PayrollReportTable(
      columns: columns.isNotEmpty
          ? columns
          : rows
                .expand((row) => row.keys)
                .toSet()
                .map((key) => PayrollReportColumn(key: key, name: key))
                .toList(growable: false),
      rows: rows,
    );
  }
}

class PayrollReportColumn {
  const PayrollReportColumn({required this.key, required this.name});
  final String key;
  final String name;

  factory PayrollReportColumn.fromJson(Map<String, dynamic> json) {
    final key = '${json['key'] ?? json['field'] ?? json['name'] ?? ''}';
    return PayrollReportColumn(
      key: key,
      name: '${json['name'] ?? json['label'] ?? key}',
    );
  }
}

class PayrollReportService {
  PayrollReportService({required this.session, http.Client? client})
    : _client = client;
  final AuthSession session;
  final http.Client? _client;

  dynamic _unwrap(http.Response response) {
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? decoded['message'] ?? decoded['error']
          : decoded;
      throw Exception('${message ?? '工资报表请求失败：HTTP ${response.statusCode}'}');
    }
    if (decoded is Map && decoded['success'] == false) {
      throw Exception('${decoded['message'] ?? '工资报表请求失败'}');
    }
    return decoded is Map && decoded.containsKey('data')
        ? decoded['data']
        : decoded;
  }

  Future<PayrollReportAccess> fetchAccess() async {
    final response = await dunesHttpGet(
      session,
      '/payroll-reports/access',
      client: _client,
    );
    final data = _unwrap(response);
    return PayrollReportAccess.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
    );
  }

  Future<List<PayrollReportSheet>> listSheets(String yearmo) async {
    final response = await dunesHttpGet(
      session,
      '/payroll-reports?yearmo=${Uri.encodeQueryComponent(yearmo)}',
      client: _client,
    );
    final data = _unwrap(response);
    final root = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final source = data is List
        ? data
        : root['reports'] ?? root['sheets'] ?? root['items'] ?? const [];
    final output = <PayrollReportSheet>[];
    if (source is List) {
      for (final item in source.whereType<Map>()) {
        final report = Map<String, dynamic>.from(item);
        final children = report['sheets'] ?? report['subReports'];
        if (children is List) {
          for (final child in children.whereType<Map>()) {
            output.add(
              PayrollReportSheet.fromJson({
                ...report,
                ...Map<String, dynamic>.from(child),
              }),
            );
          }
        } else {
          output.add(PayrollReportSheet.fromJson(report));
        }
      }
    }
    return output.where((sheet) => sheet.reportId.isNotEmpty).toList();
  }

  Future<void> sync(String yearmo) async {
    final response = await dunesHttpPost(
      session,
      '/payroll-reports/sync',
      body: jsonEncode({'yearmo': yearmo}),
      client: _client,
    );
    _unwrap(response);
  }

  Future<PayrollReportTable> fetchRows({
    required String yearmo,
    required PayrollReportSheet sheet,
    String q = '',
  }) async {
    final query = <String, String>{
      'yearmo': yearmo,
      'reportId': sheet.reportId,
      if (sheet.subReportId.isNotEmpty) 'subReportId': sheet.subReportId,
      if (q.trim().isNotEmpty) 'q': q.trim(),
    };
    final response = await dunesHttpGet(
      session,
      '/payroll-reports/rows?${_query(query)}',
      client: _client,
    );
    return PayrollReportTable.fromJson(_unwrap(response));
  }

  Future<Uint8List> export({
    required String yearmo,
    required PayrollReportSheet sheet,
    String q = '',
  }) async {
    final response = await dunesHttpGet(
      session,
      '/payroll-reports/export?${_query({'yearmo': yearmo, 'reportId': sheet.reportId, if (sheet.subReportId.isNotEmpty) 'subReportId': sheet.subReportId, if (q.trim().isNotEmpty) 'q': q.trim()})}',
      headers: const {
        'Accept':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      },
      client: _client,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _unwrap(response);
    }
    return response.bodyBytes;
  }

  String _query(Map<String, String> values) => values.entries
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
      )
      .join('&');
}
