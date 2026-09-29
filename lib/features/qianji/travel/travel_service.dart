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
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final raw = (map['people'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => _personFromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<TravelIssueSnapshot> fetchIssues({
    DateTime? from,
    DateTime? to,
    String type = '',
    String status = 'PENDING',
    String query = '',
    String department = '',
    String userId = '',
  }) async {
    final params = <String, String>{};
    if (from != null) params['from'] = _ymd(from);
    if (to != null) params['to'] = _ymd(to);
    if (from == null && to == null) params['range'] = 'all';
    if (type.isNotEmpty) params['type'] = type;
    if (status.isNotEmpty) params['status'] = status;
    if (query.trim().isNotEmpty) params['q'] = query.trim();
    if (department.trim().isNotEmpty) params['department'] = department.trim();
    if (userId.trim().isNotEmpty && userId != 'all') {
      params['userId'] = userId.trim();
    }
    final resp = await http.get(
      _uri('/travel-orders/issues', params),
      headers: _headers,
    );
    final data = _unwrap(resp);
    final json = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    return TravelIssueSnapshot(
      from: '${json['from'] ?? ''}',
      to: '${json['to'] ?? ''}',
      generatedAt: '${json['generatedAt'] ?? ''}',
      snapshotFrom: '${json['snapshotFrom'] ?? ''}',
      snapshotTo: '${json['snapshotTo'] ?? ''}',
      disclaimer: '${json['disclaimer'] ?? ''}',
      count: (json['count'] as num?)?.toInt() ?? 0,
      issues: (json['issues'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => TravelIssue.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false),
    );
  }

  Future<void> reviewIssue({
    required String fingerprint,
    required String status,
    String note = '',
  }) async {
    final resp = await http.patch(
      _uri('/travel-orders/issues/$fingerprint'),
      headers: <String, String>{
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{'status': status, 'note': note}),
    );
    _unwrap(resp);
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
    final jsonFee = (json['rebookFeeFen'] as num?)?.toInt() ?? 0;
    final fromLegs = travelRebookFeeFromLegs('${json['userId'] ?? ''}', legs);
    return TravelEmployee(
      id: '${json['userId'] ?? ''}',
      name: '${json['name'] ?? ''}',
      dept: '${json['dept'] ?? ''}',
      cost: (json['costFen'] as num?)?.toInt() ?? 0,
      fee: fromLegs > 0 ? fromLegs : jsonFee,
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
      rebookFee: (json['rebookFeeFen'] as num?)?.toInt() ?? 0,
      kind: travelKindFrom('${json['kind'] ?? ''}'),
      orderId: '${json['orderId'] ?? ''}',
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
      final msg = body is Map
          ? (body['message'] ?? body['error'] ?? body)
          : body;
      throw Exception('$msg');
    }
    if (body is Map && body.containsKey('data')) return body['data'];
    return body;
  }
}

class TravelIssueSnapshot {
  const TravelIssueSnapshot({
    required this.from,
    required this.to,
    required this.generatedAt,
    required this.snapshotFrom,
    required this.snapshotTo,
    required this.disclaimer,
    required this.count,
    required this.issues,
  });
  final String from;
  final String to;
  final String generatedAt;
  final String snapshotFrom;
  final String snapshotTo;
  final String disclaimer;
  final int count;
  final List<TravelIssue> issues;
}

class TravelIssue {
  const TravelIssue({
    required this.fingerprint,
    required this.type,
    required this.severity,
    required this.title,
    required this.explanation,
    required this.suggestion,
    required this.location,
    required this.startAt,
    required this.endAt,
    required this.amountFen,
    required this.reviewStatus,
    required this.reviewNote,
    required this.reviewer,
    required this.reviewedAt,
    required this.orders,
  });
  final String fingerprint;
  final String type;
  final String severity;
  final String title;
  final String explanation;
  final String suggestion;
  final String location;
  final String startAt;
  final String endAt;
  final int amountFen;
  final String reviewStatus;
  final String reviewNote;
  final String reviewer;
  final String reviewedAt;
  final List<TravelIssueOrder> orders;

  factory TravelIssue.fromJson(Map<String, dynamic> json) => TravelIssue(
    fingerprint: '${json['fingerprint'] ?? ''}',
    type: '${json['type'] ?? ''}',
    severity: '${json['severity'] ?? ''}',
    title: '${json['title'] ?? ''}',
    explanation: '${json['explanation'] ?? ''}',
    suggestion: '${json['suggestion'] ?? ''}',
    location: '${json['location'] ?? ''}',
    startAt: '${json['startAt'] ?? ''}',
    endAt: '${json['endAt'] ?? ''}',
    amountFen: (json['amountFen'] as num?)?.toInt() ?? 0,
    reviewStatus: '${json['reviewStatus'] ?? 'PENDING'}',
    reviewNote: '${json['reviewNote'] ?? ''}',
    reviewer: '${json['reviewer'] ?? ''}',
    reviewedAt: '${json['reviewedAt'] ?? ''}',
    orders: (json['orders'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => TravelIssueOrder.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false),
  );
}

class TravelIssueOrder {
  const TravelIssueOrder({
    required this.orderId,
    required this.kind,
    required this.place,
    required this.traveler,
    required this.department,
    required this.travelRequestId,
    required this.startAt,
    required this.endAt,
    required this.originCity,
    required this.destCity,
    required this.amountFen,
    required this.rebookFeeFen,
    required this.shared,
    required this.matchStatus,
  });
  final String orderId;
  final String kind;
  final String place;
  final String traveler;
  final String department;
  final String travelRequestId;
  final String startAt;
  final String endAt;
  final String originCity;
  final String destCity;
  final int amountFen;
  final int rebookFeeFen;
  final bool shared;
  final String matchStatus;

  factory TravelIssueOrder.fromJson(Map<String, dynamic> json) =>
      TravelIssueOrder(
        orderId: '${json['orderId'] ?? ''}',
        kind: '${json['kind'] ?? ''}',
        place: '${json['origin'] ?? ''}',
        traveler: '${json['traveler'] ?? ''}',
        department: '${json['department'] ?? ''}',
        travelRequestId: '${json['travelRequestId'] ?? ''}',
        startAt: '${json['startAt'] ?? ''}',
        endAt: '${json['endAt'] ?? ''}',
        originCity: '${json['originCity'] ?? ''}',
        destCity: '${json['destCity'] ?? ''}',
        amountFen: (json['amountFen'] as num?)?.toInt() ?? 0,
        rebookFeeFen: (json['rebookFeeFen'] as num?)?.toInt() ?? 0,
        shared: json['shared'] == true,
        matchStatus: '${json['matchStatus'] ?? ''}',
      );
}
