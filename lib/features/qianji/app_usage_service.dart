import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'app_usage_models.dart';

class AppUsageService {
  AppUsageService({required this.session});

  final AuthSession session;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/analytics/$path').replace(queryParameters: query);
  }

  Map<String, String> _rangeQuery({
    DateTime? from,
    DateTime? to,
    int? departmentId,
    String moduleKey = '',
    String platform = '',
    String q = '',
    int? page,
    int? size,
  }) {
    final query = <String, String>{};
    if (from != null) {
      query['from'] = from.toUtc().millisecondsSinceEpoch.toString();
    }
    if (to != null) {
      query['to'] = to.toUtc().millisecondsSinceEpoch.toString();
    }
    if (departmentId != null) {
      query['departmentId'] = departmentId.toString();
    }
    if (moduleKey.trim().isNotEmpty) query['moduleKey'] = moduleKey.trim();
    if (platform.trim().isNotEmpty) query['platform'] = platform.trim();
    if (q.trim().isNotEmpty) query['q'] = q.trim();
    if (page != null) query['page'] = page.toString();
    if (size != null) query['size'] = size.toString();
    return query;
  }

  Future<AppUsageHeatmap> fetchHeatmap({
    DateTime? from,
    DateTime? to,
    int? departmentId,
    String moduleKey = '',
    String q = '',
  }) async {
    final resp = await http.get(
      _uri(
        'heatmap',
        _rangeQuery(
          from: from,
          to: to,
          departmentId: departmentId,
          moduleKey: moduleKey,
          q: q,
        ),
      ),
      headers: _headers,
    );
    return AppUsageHeatmap.fromJson(_asMap(_unwrap(resp)));
  }

  Future<AppUsageUsersPage> fetchUsers({
    DateTime? from,
    DateTime? to,
    int? departmentId,
    String q = '',
    int page = 0,
    int size = 20,
  }) async {
    final resp = await http.get(
      _uri(
        'users',
        _rangeQuery(
          from: from,
          to: to,
          departmentId: departmentId,
          q: q,
          page: page,
          size: size,
        ),
      ),
      headers: _headers,
    );
    final map = _asMap(_unwrap(resp));
    final content = (map['content'] as List?) ?? const [];
    final items = content
        .whereType<Map>()
        .map((e) => AppUsageUserRow.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    return AppUsageUsersPage(
      items: items,
      total: (map['total'] as num?)?.toInt() ?? items.length,
      superviseAll: map['superviseAll'] == true,
    );
  }

  Future<AppUsageUserDetail> fetchUserDetail({
    required int userId,
    DateTime? from,
    DateTime? to,
  }) async {
    final resp = await http.get(
      _uri('users/$userId', _rangeQuery(from: from, to: to)),
      headers: _headers,
    );
    return AppUsageUserDetail.fromJson(_asMap(_unwrap(resp)));
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
