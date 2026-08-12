import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'kb_supervise_models.dart';

class KbSuperviseService {
  KbSuperviseService({required this.session});

  final AuthSession session;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/kb/$path').replace(queryParameters: query);
  }

  Future<KbSuperviseListPageResult> fetchListPage({
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
    final resp = await http.get(_uri('supervise', q), headers: _headers);
    final map = _asMap(_unwrap(resp));
    final content =
        (map['content'] as List?) ?? (map['items'] as List?) ?? const [];
    final items = content
        .whereType<Map>()
        .map((e) => KbSuperviseRow.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    return KbSuperviseListPageResult(
      items: items,
      totalCount: (map['total'] as num?)?.toInt() ?? items.length,
    );
  }

  Future<KbSuperviseDeptStatsResult> fetchDeptStats() async {
    final resp = await http.get(
      _uri('supervise/dept-stats'),
      headers: _headers,
    );
    return KbSuperviseDeptStatsResult.fromJson(_asMap(_unwrap(resp)));
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
