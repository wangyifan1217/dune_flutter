import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'session_supervise_models.dart';

class SessionSuperviseService {
  SessionSuperviseService({required this.session});

  final AuthSession session;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/ai/sessions/$path').replace(queryParameters: query);
  }

  Future<SessionSuperviseListPageResult> fetchListPage({
    int page = 0,
    int size = 20,
    String keyword = '',
    int? departmentId,
    DateTime? from,
    DateTime? to,
  }) async {
    final q = <String, String>{
      'page': page.toString(),
      'size': size.toString(),
    };
    final k = keyword.trim();
    if (k.isNotEmpty) q['q'] = k;
    if (departmentId != null) {
      q['departmentId'] = departmentId.toString();
    }
    if (from != null) {
      q['from'] = from.toUtc().millisecondsSinceEpoch.toString();
    }
    if (to != null) {
      q['to'] = to.toUtc().millisecondsSinceEpoch.toString();
    }
    final resp = await http.get(_uri('supervise', q), headers: _headers);
    final map = _asMap(_unwrap(resp));
    final content =
        (map['content'] as List?) ?? (map['items'] as List?) ?? const [];
    final items = content
        .whereType<Map>()
        .map((e) => SessionSuperviseRow.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    return SessionSuperviseListPageResult(
      items: items,
      totalCount: (map['total'] as num?)?.toInt() ?? items.length,
    );
  }

  Future<SessionSuperviseDeptStatsResult> fetchDeptStats({
    DateTime? from,
    DateTime? to,
  }) async {
    final q = <String, String>{};
    if (from != null) {
      q['from'] = from.toUtc().millisecondsSinceEpoch.toString();
    }
    if (to != null) {
      q['to'] = to.toUtc().millisecondsSinceEpoch.toString();
    }
    final resp = await http.get(
      _uri('supervise/dept-stats', q.isEmpty ? null : q),
      headers: _headers,
    );
    return SessionSuperviseDeptStatsResult.fromJson(_asMap(_unwrap(resp)));
  }

  Future<List<SessionSuperviseSessionItem>> fetchUserSessions({
    required int userId,
    DateTime? from,
    DateTime? to,
  }) async {
    final q = <String, String>{'userId': userId.toString()};
    if (from != null) {
      q['from'] = from.toUtc().millisecondsSinceEpoch.toString();
    }
    if (to != null) {
      q['to'] = to.toUtc().millisecondsSinceEpoch.toString();
    }
    final resp = await http.get(
      _uri('supervise/user-sessions', q),
      headers: _headers,
    );
    final map = _asMap(_unwrap(resp));
    final content =
        (map['content'] as List?) ?? (map['items'] as List?) ?? const [];
    return content
        .whereType<Map>()
        .map(
          (e) => SessionSuperviseSessionItem.fromJson(
            Map<String, dynamic>.from(e),
          ),
        )
        .toList(growable: false);
  }

  dynamic _unwrap(http.Response resp) {
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    if (body is! Map) {
      throw Exception('invalid response');
    }
    if (resp.statusCode >= 400 || body['success'] == false) {
      throw Exception('${body['message'] ?? 'request failed'}');
    }
    return body['data'] ?? body;
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}
