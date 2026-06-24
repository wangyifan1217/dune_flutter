import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'approval_models.dart';

class ApprovalService {
  ApprovalService({
    required this.session,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse('${session.apiBase}$path');

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  Future<List<ApprovalTodoItem>> fetchApprovalTodos() async {
    final resp = await _client.get(_uri('/workbench/inbox?kind=APPROVAL'), headers: _headers);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('审批待办加载失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    final rows = (body['data'] as List<dynamic>? ?? const <dynamic>[]);
    return rows
        .whereType<Map<String, dynamic>>()
        .map(_mapTodo)
        .where((e) => e.id > 0 && e.businessId > 0)
        .toList(growable: false);
  }

  Future<ApprovalDetailPayload> fetchProposalDetail(int proposalId) async {
    final detailResp = await _client.get(
      _uri('/xflow/proposals/$proposalId/detail'),
      headers: _headers,
    );
    if (detailResp.statusCode < 200 || detailResp.statusCode >= 300) {
      throw Exception('审批详情加载失败: HTTP ${detailResp.statusCode}');
    }
    final detailBody = _decode(detailResp.body);
    final detail = (detailBody['data'] is Map<String, dynamic>)
        ? detailBody['data'] as Map<String, dynamic>
        : detailBody;
    Map<String, dynamic>? trail;
    try {
      final trailResp = await _client.get(
        _uri('/approvals/PROPOSAL/$proposalId'),
        headers: _headers,
      );
      if (trailResp.statusCode >= 200 && trailResp.statusCode < 300) {
        final trailBody = _decode(trailResp.body);
        final raw = trailBody['data'];
        if (raw is Map<String, dynamic>) trail = raw;
      }
    } catch (_) {}

    final title = (detail['proposalName'] ?? detail['title'] ?? '审批 #$proposalId').toString();
    final summary = (detail['summary'] ?? detail['remark'] ?? '').toString();
    final status = (detail['status'] ?? '').toString();
    final stepsRaw = (trail?['steps'] as List<dynamic>? ?? const <dynamic>[]);
    final steps = stepsRaw
        .whereType<Map<String, dynamic>>()
        .map(_mapStep)
        .toList(growable: false);
    return ApprovalDetailPayload(
      proposalId: proposalId,
      status: status,
      title: title,
      summary: summary,
      steps: steps,
    );
  }

  Future<ApprovalDetailPayload> fetchTodoDetail(ApprovalTodoItem item) async {
    final businessType = item.businessType.trim().toUpperCase();
    if (businessType == 'PROPOSAL') {
      return fetchProposalDetail(item.businessId);
    }
    final trailResp = await _client.get(
      _uri('/approvals/$businessType/${item.businessId}'),
      headers: _headers,
    );
    if (trailResp.statusCode < 200 || trailResp.statusCode >= 300) {
      throw Exception('审批详情加载失败: HTTP ${trailResp.statusCode}');
    }
    final trailBody = _decode(trailResp.body);
    final raw = trailBody['data'] is Map<String, dynamic>
        ? trailBody['data'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final title = (item.title ?? '').trim().isNotEmpty
        ? item.title!.trim()
        : '$businessType #${item.businessId}';
    final status = (raw['status'] ?? item.status).toString();
    final summary = (raw['summary'] ?? raw['remark'] ?? '').toString();
    final stepsRaw = (raw['steps'] as List<dynamic>? ?? const <dynamic>[]);
    final steps = stepsRaw
        .whereType<Map<String, dynamic>>()
        .map(_mapStep)
        .toList(growable: false);
    return ApprovalDetailPayload(
      proposalId: item.businessId,
      status: status,
      title: title,
      summary: summary,
      steps: steps,
    );
  }

  Future<void> completeTodo({
    required int todoId,
    required bool approve,
    required String comment,
  }) async {
    final resp = await _client.post(
      _uri('/todos/$todoId/complete'),
      headers: _headers,
      body: jsonEncode(<String, dynamic>{
        'decision': approve ? 'APPROVED' : 'REJECTED',
        'comment': comment,
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('审批提交失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '审批提交失败').toString());
    }
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const <String, dynamic>{};
  }

  ApprovalTodoItem _mapTodo(Map<String, dynamic> raw) {
    return ApprovalTodoItem(
      id: (raw['id'] as num?)?.toInt() ?? 0,
      businessType: (raw['businessType'] ?? '').toString(),
      businessId: (raw['businessId'] as num?)?.toInt() ?? 0,
      status: (raw['status'] ?? '').toString(),
      kind: (raw['kind'] ?? '').toString(),
      title: (raw['title'] ?? raw['businessTitle'] ?? '').toString(),
      subtitle: (raw['subtitle'] ?? raw['createdByName'] ?? '').toString(),
    );
  }

  ApprovalStep _mapStep(Map<String, dynamic> raw) {
    return ApprovalStep(
      stepNo: (raw['stepNo'] as num?)?.toInt() ?? 0,
      stepName: (raw['stepName'] ?? raw['name'] ?? '').toString(),
      decision: (raw['decision'] ?? '').toString(),
      assigneeName: (raw['assigneeName'] ?? raw['actorName'] ?? '').toString(),
      comment: (raw['comment'] ?? '').toString(),
      updatedAt: DateTime.tryParse((raw['updatedAt'] ?? raw['createdAt'] ?? '').toString()),
    );
  }
}
