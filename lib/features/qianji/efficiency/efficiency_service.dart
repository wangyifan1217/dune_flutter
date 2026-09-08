import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/http/session_http.dart';
import '../../auth/auth_session.dart';
import 'efficiency_models.dart';

class EfficiencyService {
  EfficiencyService({required this.session, http.Client? client})
    : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

  Future<EfficiencySnapshot> fetchOverview({
    required String scope,
    required String month,
  }) async {
    final query = Uri(
      queryParameters: <String, String>{'scope': scope, 'month': month},
    ).query;
    final response = await dunesHttpGet(
      session,
      '/efficiency/overview?$query',
      client: _client,
    );
    return EfficiencySnapshot.fromJson(_asMap(_unwrap(response)));
  }

  Future<WorkSituationBoard> fetchWorkSituation({required String month}) async {
    final query = Uri(queryParameters: <String, String>{'month': month}).query;
    final response = await dunesHttpGet(
      session,
      '/efficiency/work-situation?$query',
      client: _client,
    );
    return WorkSituationBoard.fromJson(_asMap(_unwrap(response)));
  }

  Future<WorkSituationPerson> fetchWorkSituationPerson({
    required String month,
    required int userId,
  }) async {
    final query = Uri(
      queryParameters: <String, String>{
        'month': month,
        'userId': '$userId',
      },
    ).query;
    final response = await dunesHttpGet(
      session,
      '/efficiency/work-situation/person?$query',
      client: _client,
    );
    return WorkSituationPerson.fromJson(_asMap(_unwrap(response)));
  }

  Future<EfficiencyAnalysis> startAnalysis({
    required String scope,
    required String month,
    String question = '',
  }) async {
    final response = await dunesHttpPost(
      session,
      '/efficiency/analyze',
      body: jsonEncode(<String, String>{
        'scope': scope,
        'month': month,
        if (question.trim().isNotEmpty) 'question': question.trim(),
      }),
      client: _client,
    );
    return EfficiencyAnalysis.fromJson(_asMap(_unwrap(response)));
  }

  Future<String> exportBriefing({
    required String scope,
    required String month,
  }) async {
    final query = Uri(
      queryParameters: <String, String>{'scope': scope, 'month': month},
    ).query;
    final response = await dunesHttpGet(
      session,
      '/efficiency/export?$query',
      client: _client,
    );
    final data = _asMap(_unwrap(response));
    final text = '${data['text'] ?? ''}'.trim();
    if (text.isEmpty) {
      throw Exception('导出内容为空');
    }
    return text;
  }

  Future<EfficiencyAnalysis> fetchAnalysis(int id) async {
    final response = await dunesHttpGet(
      session,
      '/efficiency/analyze/$id',
      client: _client,
    );
    return EfficiencyAnalysis.fromJson(_asMap(_unwrap(response)));
  }

  Future<EfficiencyAnalysis> analyzeAndWait({
    required String scope,
    required String month,
    String question = '',
    Duration interval = const Duration(seconds: 3),
    int maxAttempts = 80,
  }) async {
    var analysis = await startAnalysis(
      scope: scope,
      month: month,
      question: question,
    );
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (analysis.status != 'running') return analysis;
      await Future<void>.delayed(interval);
      analysis = await fetchAnalysis(analysis.id);
    }
    throw TimeoutException('AI分析时间较长，请稍后重试');
  }

  dynamic _unwrap(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw Exception('服务返回格式错误');
    }
    if (response.statusCode >= 400 || decoded['success'] == false) {
      throw Exception('${decoded['message'] ?? '效能分析请求失败'}');
    }
    return decoded['data'] ?? decoded;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
}
