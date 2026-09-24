import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../auth/auth_session.dart';

class TravelImportAccess {
  const TravelImportAccess({required this.canImport, required this.viewAll});
  final bool canImport;
  final bool viewAll;
}

class TravelImportPreview {
  const TravelImportPreview({
    required this.previewToken,
    required this.fileName,
    required this.total,
    required this.byKind,
    required this.matched,
    required this.unmatched,
    required this.ambiguous,
    required this.shared,
    required this.unmatchedNames,
    required this.ambiguousNames,
  });
  final String previewToken;
  final String fileName;
  final int total;
  final Map<String, int> byKind;
  final int matched;
  final int unmatched;
  final int ambiguous;
  final int shared;
  final List<String> unmatchedNames;
  final List<String> ambiguousNames;
}

class TravelNameAssignment {
  const TravelNameAssignment({
    required this.travelerName,
    required this.userId,
    required this.displayName,
    this.dept = '',
    this.saveAlias = false,
  });
  final String travelerName;
  final int userId;
  final String displayName;
  final String dept;
  final bool saveAlias;

  Map<String, dynamic> toJson() => {
        'travelerName': travelerName,
        'userId': userId,
        'saveAlias': saveAlias,
      };
}

class TravelOrgPerson {
  const TravelOrgPerson({
    required this.userId,
    required this.displayName,
    this.dept = '',
    this.title = '',
  });
  final int userId;
  final String displayName;
  final String dept;
  final String title;

  factory TravelOrgPerson.fromJson(Map<String, dynamic> json) {
    return TravelOrgPerson(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      displayName: '${json['displayName'] ?? ''}',
      dept: '${json['departmentName'] ?? ''}',
      title: '${json['title'] ?? json['positionName'] ?? ''}',
    );
  }
}

class TravelImportCommit {
  const TravelImportCommit({
    required this.batchId,
    required this.inserted,
    required this.updated,
    required this.unmatched,
    required this.ambiguous,
  });
  final int batchId;
  final int inserted;
  final int updated;
  final int unmatched;
  final int ambiguous;
}

class TravelOrderRow {
  const TravelOrderRow({
    required this.id,
    required this.kind,
    required this.orderId,
    this.ticketNo = '',
    required this.travelerName,
    required this.userDisplayName,
    this.deptName = '',
    this.sectorName = '',
    required this.matchStatus,
    required this.startAt,
    this.endAt = '',
    required this.origin,
    required this.destination,
    this.originCity = '',
    this.destCity = '',
    this.originProvince = '',
    this.destProvince = '',
    required this.amountFen,
    this.amountFenOrder = 0,
    this.rebookFeeFen = 0,
    required this.shared,
    this.companionNames = '',
    this.status = '',
  });
  final int id;
  final String kind;
  final String orderId;
  final String ticketNo;
  final String travelerName;
  final String userDisplayName;
  final String deptName;
  final String sectorName;
  final String matchStatus;
  final String startAt;
  final String endAt;
  final String origin;
  final String destination;
  final String originCity;
  final String destCity;
  final String originProvince;
  final String destProvince;
  final int amountFen;
  final int amountFenOrder;
  final int rebookFeeFen;
  final bool shared;
  final String companionNames;
  final String status;

  bool get unmatched => matchStatus == 'unmatched';
  bool get ambiguous => matchStatus == 'ambiguous';

  String get amountLabel {
    final yuan = amountFen / 100.0;
    final base = '¥${yuan.toStringAsFixed(yuan.truncateToDouble() == yuan ? 0 : 2)}';
    if (rebookFeeFen <= 0) return base;
    final fee = rebookFeeFen / 100.0;
    return '$base · 改签¥${fee.toStringAsFixed(fee.truncateToDouble() == fee ? 0 : 2)}';
  }

  factory TravelOrderRow.fromJson(Map<String, dynamic> json) {
    return TravelOrderRow(
      id: (json['id'] as num?)?.toInt() ?? 0,
      kind: '${json['kind'] ?? ''}',
      orderId: '${json['orderId'] ?? ''}',
      ticketNo: '${json['ticketNo'] ?? ''}',
      travelerName: '${json['travelerName'] ?? ''}',
      userDisplayName: '${json['userDisplayName'] ?? ''}',
      deptName: '${json['deptName'] ?? ''}',
      sectorName: '${json['sectorName'] ?? ''}',
      matchStatus: '${json['matchStatus'] ?? ''}',
      startAt: '${json['startAt'] ?? ''}',
      endAt: '${json['endAt'] ?? ''}',
      origin: '${json['origin'] ?? ''}',
      destination: '${json['destination'] ?? ''}',
      originCity: '${json['originCity'] ?? ''}',
      destCity: '${json['destCity'] ?? ''}',
      originProvince: '${json['originProvince'] ?? ''}',
      destProvince: '${json['destProvince'] ?? ''}',
      amountFen: (json['amountFen'] as num?)?.toInt() ?? 0,
      amountFenOrder: (json['amountFenOrder'] as num?)?.toInt() ?? 0,
      rebookFeeFen: (json['rebookFeeFen'] as num?)?.toInt() ?? 0,
      shared: json['shared'] == true,
      companionNames: '${json['companionNames'] ?? ''}',
      status: '${json['status'] ?? ''}',
    );
  }
}

class TravelOrderListResult {
  const TravelOrderListResult({required this.items, required this.total});
  final List<TravelOrderRow> items;
  final int total;
}

class TravelImportService {
  TravelImportService({required this.session});
  final AuthSession session;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${session.token}',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<TravelImportAccess> fetchAccess() async {
    final resp = await http.get(_uri('/travel-orders/access'), headers: _headers);
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    return TravelImportAccess(
      canImport: map['import'] == true,
      viewAll: map['viewAll'] == true,
    );
  }

  Future<TravelImportPreview> preview({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final req = http.MultipartRequest('POST', _uri('/travel-orders/import/preview'));
    req.headers['Authorization'] = 'Bearer ${session.token}';
    req.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: MediaType(
          'application',
          'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      ),
    );
    final streamed = await req.send();
    final resp = await http.Response.fromStream(streamed);
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final byKindRaw = map['byKind'];
    final byKind = <String, int>{};
    if (byKindRaw is Map) {
      byKindRaw.forEach((k, v) {
        byKind['$k'] = (v as num?)?.toInt() ?? 0;
      });
    }
    return TravelImportPreview(
      previewToken: '${map['previewToken'] ?? ''}',
      fileName: '${map['fileName'] ?? fileName}',
      total: (map['total'] as num?)?.toInt() ?? 0,
      byKind: byKind,
      matched: (map['matched'] as num?)?.toInt() ?? 0,
      unmatched: (map['unmatched'] as num?)?.toInt() ?? 0,
      ambiguous: (map['ambiguous'] as num?)?.toInt() ?? 0,
      shared: (map['shared'] as num?)?.toInt() ?? 0,
      unmatchedNames: _stringList(map['unmatchedNames']),
      ambiguousNames: _stringList(map['ambiguousNames']),
    );
  }

  Future<TravelImportCommit> commit(
    String previewToken, {
    List<TravelNameAssignment> assignments = const [],
  }) async {
    final resp = await http.post(
      _uri('/travel-orders/import/commit'),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'previewToken': previewToken,
        'assignments': [for (final a in assignments) a.toJson()],
      }),
    );
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    return TravelImportCommit(
      batchId: (map['batchId'] as num?)?.toInt() ?? 0,
      inserted: (map['inserted'] as num?)?.toInt() ?? 0,
      updated: (map['updated'] as num?)?.toInt() ?? 0,
      unmatched: (map['unmatched'] as num?)?.toInt() ?? 0,
      ambiguous: (map['ambiguous'] as num?)?.toInt() ?? 0,
    );
  }

  Future<int> assign(TravelNameAssignment assignment) async {
    final resp = await http.post(
      _uri('/travel-orders/assign'),
      headers: {
        ..._headers,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(assignment.toJson()),
    );
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    return (map['updated'] as num?)?.toInt() ?? 0;
  }

  Future<List<TravelOrgPerson>> searchPeople(String q) async {
    final needle = q.trim();
    if (needle.isEmpty) return const [];
    final resp = await http.get(
      _uri('/org/users', {'q': needle}),
      headers: _headers,
    );
    final data = _unwrap(resp);
    final rows = data is List ? data : const [];
    return rows
        .whereType<Map>()
        .map((e) => TravelOrgPerson.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.userId > 0 && e.displayName.isNotEmpty)
        .toList();
  }

  Future<TravelOrderListResult> list({
    required String kind,
    String match = '',
    String q = '',
    String from = '',
    String to = '',
    int page = 0,
    int pageSize = 20,
  }) async {
    final query = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (kind.trim().isNotEmpty) query['kind'] = kind.trim();
    if (match.isNotEmpty) query['match'] = match;
    if (q.trim().isNotEmpty) query['q'] = q.trim();
    if (from.trim().isNotEmpty) query['from'] = from.trim();
    if (to.trim().isNotEmpty) query['to'] = to.trim();
    final resp = await http.get(_uri('/travel-orders', query), headers: _headers);
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final items = ((map['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => TravelOrderRow.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return TravelOrderListResult(
      items: items,
      total: (map['total'] as num?)?.toInt() ?? items.length,
    );
  }

  /// Pull the full Ctrip settlement payload and wait until the workbook is ready.
  Future<Uint8List> exportAll() async {
    final start = await http.post(
      _uri('/travel-orders/export'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: '{}',
    );
    final started = _unwrap(start);
    final map = started is Map ? Map<String, dynamic>.from(started) : <String, dynamic>{};
    final id = '${map['id'] ?? ''}'.trim();
    if (id.isEmpty) {
      throw Exception('导出没有开始');
    }
    for (var i = 0; i < 180; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final statusResp = await http.get(
        _uri('/travel-orders/export/$id'),
        headers: _headers,
      );
      final statusData = _unwrap(statusResp);
      final statusMap = statusData is Map
          ? Map<String, dynamic>.from(statusData)
          : <String, dynamic>{};
      final status = '${statusMap['status'] ?? ''}';
      if (status == 'failed') {
        final message = '${statusMap['error'] ?? ''}'.trim();
        throw Exception(message.isEmpty ? '导出失败' : message);
      }
      if (status != 'success') continue;
      final fileResp = await http.get(
        _uri('/travel-orders/export/$id/file'),
        headers: {
          ..._headers,
          'Accept':
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        },
      );
      if (fileResp.statusCode < 200 || fileResp.statusCode >= 300) {
        _unwrap(fileResp);
      }
      return fileResp.bodyBytes;
    }
    throw Exception('导出时间较长，请稍后重试');
  }

  List<String> _stringList(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((e) => '$e').where((e) => e.isNotEmpty).toList();
  }

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
