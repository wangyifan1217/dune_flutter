import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'cursor_supervise_models.dart';

class CursorSuperviseService {
  CursorSuperviseService({required this.session});

  final AuthSession session;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/qianji/$path').replace(queryParameters: query);
  }

  Future<CursorSuperviseListPageResult> fetchListPage({
    int page = 0,
    int size = 20,
    String keyword = '',
    int? departmentId,
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
    final resp = await http.get(
      _uri('cursor/supervise', q),
      headers: _headers,
    );
    final data = _unwrap(resp);
    final map = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
    final content =
        (map['content'] as List?) ?? (map['items'] as List?) ?? const [];
    final items = content
        .whereType<Map>()
        .map((e) => CursorSuperviseRow.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    return CursorSuperviseListPageResult(
      items: items,
      totalCount: (map['total'] as num?)?.toInt() ?? items.length,
    );
  }

  Future<CursorSuperviseDeptStatsResult> fetchDeptStats() async {
    final resp = await http.get(
      _uri('cursor/supervise/dept-stats'),
      headers: _headers,
    );
    final data = _unwrap(resp);
    final map = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
    return CursorSuperviseDeptStatsResult.fromJson(map);
  }

  Future<CursorSuperviseDailySpendResult> fetchDailySpend({
    required int bindingId,
    int? startDateMs,
    int? endDateMs,
  }) async {
    final q = <String, String>{};
    if (startDateMs != null && endDateMs != null) {
      q['startDate'] = startDateMs.toString();
      q['endDate'] = endDateMs.toString();
    }
    final resp = await http.get(
      _uri(
        'cursor/supervise/$bindingId/daily-spend',
        q.isEmpty ? null : q,
      ),
      headers: _headers,
    );
    final data = _unwrap(resp);
    final map = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
    return CursorSuperviseDailySpendResult.fromJson(map);
  }

  dynamic _unwrap(http.Response resp) {
    final body = resp.body.isEmpty ? <String, dynamic>{} : jsonDecode(resp.body);
    if (resp.statusCode >= 400) {
      final msg = body is Map ? (body['message'] ?? body['error'] ?? body) : body;
      throw Exception('HTTP ${resp.statusCode}: $msg');
    }
    if (body is Map && body.containsKey('data')) {
      return body['data'];
    }
    return body;
  }
}
