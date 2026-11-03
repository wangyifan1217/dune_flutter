import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';

/// 一组汇总：报销人 × 报销主体、按报销人、按报销主体共用。
class ReimbursementGroup {
  const ReimbursementGroup({
    required this.applicant,
    required this.department,
    required this.entity,
    required this.count,
    required this.amount,
  });

  final String applicant;
  final String department;
  final String entity;
  final int count;
  final double amount;

  factory ReimbursementGroup.fromJson(Map<String, dynamic> json) =>
      ReimbursementGroup(
        applicant: '${json['applicant'] ?? ''}',
        department: '${json['department'] ?? ''}',
        entity: '${json['entity'] ?? ''}',
        count: (json['count'] as num?)?.toInt() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
      );
}

class ReimbursementDetail {
  const ReimbursementDetail({
    required this.businessId,
    required this.applicant,
    required this.department,
    required this.entity,
    required this.reimbursementType,
    required this.amount,
    required this.invoiceCount,
    required this.unrecognized,
    required this.approvedAt,
  });

  final String businessId;
  final String applicant;
  final String department;
  final String entity;
  final String reimbursementType;
  final double amount;
  final int invoiceCount;
  final int unrecognized;
  final String approvedAt;

  factory ReimbursementDetail.fromJson(Map<String, dynamic> json) =>
      ReimbursementDetail(
        businessId: '${json['businessId'] ?? ''}',
        applicant: '${json['applicant'] ?? ''}',
        department: '${json['department'] ?? ''}',
        entity: '${json['entity'] ?? ''}',
        reimbursementType: '${json['reimbursementType'] ?? ''}',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        invoiceCount: (json['invoiceCount'] as num?)?.toInt() ?? 0,
        unrecognized: (json['invoiceUnrecognizedCount'] as num?)?.toInt() ?? 0,
        approvedAt: '${json['approvedAt'] ?? json['submittedAt'] ?? ''}',
      );
}

class ReimbursementSummary {
  const ReimbursementSummary({
    required this.entityLabel,
    required this.amountLabel,
    required this.count,
    required this.amount,
    required this.groups,
    required this.byPerson,
    required this.byEntity,
    required this.details,
  });

  final String entityLabel;
  final String amountLabel;
  final int count;
  final double amount;
  final List<ReimbursementGroup> groups;
  final List<ReimbursementGroup> byPerson;
  final List<ReimbursementGroup> byEntity;
  final List<ReimbursementDetail> details;

  static List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) f) =>
      raw is List
      ? raw.whereType<Map>().map((m) => f(Map<String, dynamic>.from(m))).toList()
      : <T>[];

  factory ReimbursementSummary.fromJson(Map<String, dynamic> json) {
    final fields = json['fields'] is Map
        ? Map<String, dynamic>.from(json['fields'] as Map)
        : const <String, dynamic>{};
    final entityLabel = '${fields['entityLabel'] ?? ''}'.trim();
    final amountLabel = '${fields['amountLabel'] ?? ''}'.trim();
    return ReimbursementSummary(
      entityLabel: entityLabel.isEmpty ? '报销主体' : entityLabel,
      amountLabel: amountLabel.isEmpty ? '报销金额' : amountLabel,
      count: (json['count'] as num?)?.toInt() ?? 0,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      groups: _list(json['groups'], ReimbursementGroup.fromJson),
      byPerson: _list(json['byPerson'], ReimbursementGroup.fromJson),
      byEntity: _list(json['byEntity'], ReimbursementGroup.fromJson),
      details: _list(json['details'], ReimbursementDetail.fromJson),
    );
  }
}

/// 工作台「报销汇总」：已审批通过的电子报销，按报销人、报销主体汇总，导出 Excel。
class ReimbursementSummaryService {
  ReimbursementSummaryService({required this.session, http.Client? client})
    : _client = client;
  final AuthSession session;
  final http.Client? _client;

  dynamic _unwrap(http.Response response) {
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map
          ? decoded['message'] ?? decoded['error']
          : null;
      throw Exception(
        '${message ?? '报销汇总请求失败：HTTP ${response.statusCode}'}',
      );
    }
    if (decoded is Map && decoded['success'] == false) {
      throw Exception('${decoded['message'] ?? '报销汇总请求失败'}');
    }
    return decoded is Map && decoded.containsKey('data')
        ? decoded['data']
        : decoded;
  }

  Future<bool> fetchAccess() async {
    final response = await dunesHttpGet(
      session,
      '/reimbursement-summary/access',
      client: _client,
    );
    final data = _unwrap(response);
    return data is Map && data['view'] == true;
  }

  static String query({String from = '', String to = '', String q = ''}) {
    final values = {
      if (from.isNotEmpty) 'from': from,
      if (to.isNotEmpty) 'to': to,
      if (q.trim().isNotEmpty) 'q': q.trim(),
    };
    return values.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
  }

  Future<ReimbursementSummary> fetch({
    String from = '',
    String to = '',
    String q = '',
  }) async {
    final response = await dunesHttpGet(
      session,
      '/reimbursement-summary?${query(from: from, to: to, q: q)}',
      client: _client,
    );
    final data = _unwrap(response);
    return ReimbursementSummary.fromJson(
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{},
    );
  }

  Future<Uint8List> export({String from = '', String to = '', String q = ''}) async {
    final response = await dunesHttpGet(
      session,
      '/reimbursement-summary/export?${query(from: from, to: to, q: q)}',
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
}
