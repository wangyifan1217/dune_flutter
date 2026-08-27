import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/auth_session.dart';
import 'travel_mock_data.dart';

class TravelService {
  TravelService({required this.session});
  final AuthSession session;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${session.token}',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<List<TravelEmployee>> fetchSummary({
    String q = '',
    DateTime? from,
    DateTime? to,
  }) async {
    final query = <String, String>{};
    if (q.trim().isNotEmpty) query['q'] = q.trim();
    if (from != null) query['from'] = _ymd(from);
    if (to != null) query['to'] = _ymd(to);
    final resp = await http.get(
      _uri('/travel-orders/summary', query.isEmpty ? null : query),
      headers: _headers,
    );
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final raw = (map['people'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => _personFromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  TravelEmployee _personFromJson(Map<String, dynamic> json) {
    final visits = <String, int>{};
    final visitRaw = json['provinceVisits'];
    if (visitRaw is List) {
      for (final item in visitRaw.whereType<Map>()) {
        final name = '${item['province'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        visits[name] = (item['count'] as num?)?.toInt() ?? 0;
      }
    }
    final legs = ((json['legs'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => _legFromJson(Map<String, dynamic>.from(e)))
        .toList();
    var provinces = ((json['provinces'] as List?) ?? const [])
        .map((e) => '$e')
        .where((e) => e.isNotEmpty)
        .toList();
    if (provinces.isEmpty) {
      provinces = provincesFromLegs(legs);
    }
    final stay = visits.isEmpty ? provinceStayCounts(legs) : visits;
    return TravelEmployee(
      id: '${json['userId'] ?? ''}',
      name: '${json['name'] ?? ''}',
      dept: '${json['dept'] ?? ''}',
      cost: (json['costFen'] as num?)?.toInt() ?? 0,
      trips: (json['trips'] as num?)?.toInt() ?? legs.length,
      lastTrip: '${json['lastTrip'] ?? ''}',
      provinces: provinces,
      legs: legs,
      provinceVisits: stay,
    );
  }

  TravelLeg _legFromJson(Map<String, dynamic> json) {
    return TravelLeg(
      from: '${json['from'] ?? ''}',
      to: '${json['to'] ?? ''}',
      date: '${json['date'] ?? ''}',
      amount: (json['amountFen'] as num?)?.toInt() ?? 0,
      kind: travelKindFrom('${json['kind'] ?? ''}'),
      shared: json['shared'] == true,
      originProvince: '${json['originProvince'] ?? ''}',
      destProvince: '${json['destProvince'] ?? ''}',
    );
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  dynamic _unwrap(http.Response resp) {
    final body = resp.body.isEmpty ? null : jsonDecode(resp.body);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final msg = body is Map ? (body['message'] ?? body['error'] ?? body) : body;
      throw Exception('$msg');
    }
    if (body is Map && body.containsKey('data')) return body['data'];
    return body;
  }
}
