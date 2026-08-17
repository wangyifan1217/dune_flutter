import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'fund_secondment_models.dart';

class FundSecondmentService {
  FundSecondmentService({required this.session});

  final AuthSession session;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<FundSecondmentListPageResult> fetchListPage({
    int page = 0,
    int size = 20,
    String keyword = '',
    bool? settled,
  }) async {
    final q = <String, String>{
      'page': page.toString(),
      'pageSize': size.toString(),
    };
    final k = keyword.trim();
    if (k.isNotEmpty) q['q'] = k;
    if (settled != null) q['settled'] = settled ? 'true' : 'false';
    final resp = await http.get(
      _uri('/xflow/fund-secondments', q),
      headers: _headers,
    );
    final data = _unwrap(resp);
    final map = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
    final content =
        (map['items'] as List?) ?? (map['content'] as List?) ?? const [];
    final items = content
        .whereType<Map>()
        .map((e) => FundSecondmentRow.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    final summaryRaw = map['summary'];
    return FundSecondmentListPageResult(
      items: items,
      totalCount: (map['total'] as num?)?.toInt() ?? items.length,
      summary: FundSecondmentSummary.fromJson(
        summaryRaw is Map ? Map<String, dynamic>.from(summaryRaw) : null,
      ),
    );
  }

  Future<FundSecondmentDetail> fetchDetail(int id) async {
    final resp = await http.get(
      _uri('/xflow/fund-secondments/$id'),
      headers: _headers,
    );
    final data = _unwrap(resp);
    final map = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);
    return FundSecondmentDetail.fromJson(map);
  }

  dynamic _unwrap(http.Response resp) {
    final body = resp.body.isEmpty ? <String, dynamic>{} : jsonDecode(resp.body);
    if (resp.statusCode >= 400) {
      final msg =
          body is Map ? (body['message'] ?? body['error'] ?? body) : body;
      throw Exception('HTTP ${resp.statusCode}: $msg');
    }
    if (body is Map && body.containsKey('data')) {
      return body['data'];
    }
    return body;
  }
}
