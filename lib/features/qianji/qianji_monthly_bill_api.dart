import 'dart:convert';

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';
import 'qianji_monthly_bill_demo.dart';

class MonthlyBillItemPage {
  const MonthlyBillItemPage({
    required this.total,
    required this.page,
    required this.pageSize,
    required this.items,
  });

  final int total;
  final int page;
  final int pageSize;
  final List<MonthlyBillRow> items;

  factory MonthlyBillItemPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => MonthlyBillRow.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false)
        : const <MonthlyBillRow>[];
    return MonthlyBillItemPage(
      total: _asInt(json['total']),
      page: _asInt(json['page']),
      pageSize: _asInt(json['pageSize']),
      items: items,
    );
  }
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('$v') ?? 0;
}

class QianjiMonthlyBillApi {
  QianjiMonthlyBillApi(this.session);

  final AuthSession session;

  Future<MonthlyBillBoard> board({required String month}) async {
    final data = await _get('/qianji/monthly-bills/board', {'month': month});
    return MonthlyBillBoard.fromJson(data);
  }

  Future<MonthlyBillItemPage> items({
    required String month,
    required String side,
    String kind = '',
    bool overdue = false,
    int page = 1,
    int pageSize = 100,
  }) async {
    final query = <String, String>{
      'month': month,
      'side': side,
      'page': '$page',
      'pageSize': '$pageSize',
    };
    if (kind.isNotEmpty) query['kind'] = kind;
    if (overdue) query['overdue'] = '1';
    final data = await _get('/qianji/monthly-bills/items', query);
    return MonthlyBillItemPage.fromJson(data);
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final qs = query.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    final resp = await dunesHttpGet(session, '$path?$qs');
    final body = resp.body.isEmpty ? <String, dynamic>{} : jsonDecode(resp.body);
    if (resp.statusCode >= 400) {
      final msg = body is Map
          ? (body['message'] ?? body['error'] ?? resp.body)
          : resp.body;
      throw Exception('$msg');
    }
    final data = body is Map && body.containsKey('data') ? body['data'] : body;
    return Map<String, dynamic>.from(data as Map);
  }
}
