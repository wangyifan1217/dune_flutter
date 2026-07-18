import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';

class QianjiProduct {
  const QianjiProduct({
    required this.id,
    required this.code,
    required this.name,
    required this.kind,
    required this.tag,
    required this.ownerName,
    required this.industry,
    required this.status,
    required this.application,
    required this.description,
    required this.sortOrder,
  });

  final int id;
  final String code;
  final String name;
  final String kind;
  final int tag;
  final String ownerName;
  final String industry;
  final String status;
  final String application;
  final String description;
  final int sortOrder;

  factory QianjiProduct.fromJson(Map<String, dynamic> json) {
    return QianjiProduct(
      id: (json['id'] as num?)?.toInt() ?? 0,
      code: '${json['code'] ?? ''}',
      name: '${json['name'] ?? ''}',
      kind: '${json['kind'] ?? 'product'}',
      tag: (json['tag'] as num?)?.toInt() ?? 1,
      ownerName: '${json['ownerName'] ?? ''}',
      industry: '${json['industry'] ?? ''}',
      status: '${json['status'] ?? 'active'}',
      application: '${json['application'] ?? ''}',
      description: '${json['description'] ?? ''}',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toWriteBody() => {
        'code': code,
        'name': name,
        'kind': kind,
        'tag': tag,
        'ownerName': ownerName,
        'industry': industry,
        'status': status,
        'application': application,
        'description': description,
        'sortOrder': sortOrder,
      };
}

class QianjiDisplaySetting {
  const QianjiDisplaySetting({
    required this.mode,
    required this.fieldVisibility,
  });

  final String mode;
  final Map<String, dynamic> fieldVisibility;

  factory QianjiDisplaySetting.fromJson(Map<String, dynamic> json) {
    final raw = json['fieldVisibility'];
    return QianjiDisplaySetting(
      mode: '${json['mode'] ?? 'internal'}',
      fieldVisibility: raw is Map<String, dynamic>
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{},
    );
  }
}

class QianjiRequirement {
  const QianjiRequirement({
    required this.id,
    required this.code,
    required this.summary,
    required this.background,
    required this.platform,
    required this.product,
    required this.capability,
    required this.receiver,
    required this.submitter,
    required this.priority,
    required this.status,
    this.dueDate,
    required this.note,
    required this.assignedToMe,
    required this.proposalLabel,
    required this.taskLabel,
    required this.submittedAt,
  });

  final int id;
  final String code;
  final String summary;
  final String background;
  final String platform;
  final String product;
  final String capability;
  final String receiver;
  final String submitter;
  final String priority;
  final String status;
  final String? dueDate;
  final String note;
  final bool assignedToMe;
  final String proposalLabel;
  final String taskLabel;
  final DateTime submittedAt;

  factory QianjiRequirement.fromJson(Map<String, dynamic> json) {
    return QianjiRequirement(
      id: (json['id'] as num?)?.toInt() ?? 0,
      code: '${json['code'] ?? ''}',
      summary: '${json['summary'] ?? ''}',
      background: '${json['background'] ?? ''}',
      platform: '${json['platform'] ?? ''}',
      product: '${json['product'] ?? ''}',
      capability: '${json['capability'] ?? ''}',
      receiver: '${json['receiver'] ?? ''}',
      submitter: '${json['submitter'] ?? ''}',
      priority: '${json['priority'] ?? 'mid'}',
      status: '${json['status'] ?? 'pending'}',
      dueDate: json['dueDate']?.toString(),
      note: '${json['note'] ?? ''}',
      assignedToMe: json['assignedToMe'] == true,
      proposalLabel: '${json['proposalLabel'] ?? ''}',
      taskLabel: '${json['taskLabel'] ?? ''}',
      submittedAt: DateTime.tryParse('${json['submittedAt'] ?? ''}') ?? DateTime.now(),
    );
  }
}

class QianjiRequirementStats {
  const QianjiRequirementStats({
    required this.pending,
    required this.done,
    required this.rejected,
    required this.voided,
  });

  final int pending;
  final int done;
  final int rejected;
  final int voided;

  factory QianjiRequirementStats.fromJson(Map<String, dynamic> json) {
    return QianjiRequirementStats(
      pending: (json['pending'] as num?)?.toInt() ?? 0,
      done: (json['done'] as num?)?.toInt() ?? 0,
      rejected: (json['rejected'] as num?)?.toInt() ?? 0,
      voided: (json['voided'] as num?)?.toInt() ?? 0,
    );
  }

  static const empty = QianjiRequirementStats(
    pending: 0,
    done: 0,
    rejected: 0,
    voided: 0,
  );
}

class QianjiAdminApi {
  QianjiAdminApi(this.session);

  final AuthSession session;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/qianji/$path').replace(queryParameters: query);
  }

  Future<List<QianjiProduct>> listProducts({
    int? tag,
    String? kind,
    String? status,
    String? q,
  }) async {
    final query = <String, String>{};
    if (tag != null && tag > 0) query['tag'] = '$tag';
    if (kind != null && kind.isNotEmpty) query['kind'] = kind;
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (q != null && q.trim().isNotEmpty) query['q'] = q.trim();
    final resp = await http.get(_uri('admin/products', query.isEmpty ? null : query), headers: _headers);
    final data = _unwrap(resp);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => QianjiProduct.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<QianjiProduct> createProduct(Map<String, dynamic> body) async {
    final resp = await http.post(
      _uri('admin/products'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = _unwrap(resp);
    return QianjiProduct.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<QianjiProduct> updateProduct(int id, Map<String, dynamic> body) async {
    final resp = await http.patch(
      _uri('admin/products/$id'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = _unwrap(resp);
    return QianjiProduct.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> deleteProduct(int id) async {
    final resp = await http.delete(_uri('admin/products/$id'), headers: _headers);
    _unwrap(resp);
  }

  Future<List<QianjiRequirement>> listRequirements({
    String? status,
    String? priority,
    String? q,
  }) async {
    final query = <String, String>{};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (priority != null && priority.isNotEmpty) query['priority'] = priority;
    if (q != null && q.trim().isNotEmpty) query['q'] = q.trim();
    final resp = await http.get(
      _uri('admin/requirements', query.isEmpty ? null : query),
      headers: _headers,
    );
    final data = _unwrap(resp);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => QianjiRequirement.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<QianjiRequirementStats> requirementStats({
    String? priority,
    String? q,
  }) async {
    final query = <String, String>{};
    if (priority != null && priority.isNotEmpty) query['priority'] = priority;
    if (q != null && q.trim().isNotEmpty) query['q'] = q.trim();
    final resp = await http.get(
      _uri('admin/requirements/stats', query.isEmpty ? null : query),
      headers: _headers,
    );
    final data = _unwrap(resp);
    return QianjiRequirementStats.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<QianjiRequirement> createRequirement(Map<String, dynamic> body) async {
    final resp = await http.post(
      _uri('admin/requirements'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = _unwrap(resp);
    return QianjiRequirement.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<QianjiRequirement> updateRequirement(int id, Map<String, dynamic> body) async {
    final resp = await http.patch(
      _uri('admin/requirements/$id'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = _unwrap(resp);
    return QianjiRequirement.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<QianjiDisplaySetting> getDisplaySettings() async {
    final resp = await http.get(_uri('admin/display-settings'), headers: _headers);
    final data = _unwrap(resp);
    return QianjiDisplaySetting.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<QianjiDisplaySetting> putDisplaySettings({
    required String mode,
    required Map<String, dynamic> fieldVisibility,
  }) async {
    final resp = await http.put(
      _uri('admin/display-settings'),
      headers: _headers,
      body: jsonEncode({
        'mode': mode,
        'fieldVisibility': fieldVisibility,
      }),
    );
    final data = _unwrap(resp);
    return QianjiDisplaySetting.fromJson(Map<String, dynamic>.from(data as Map));
  }

  dynamic _unwrap(http.Response resp) {
    final body = resp.body.isEmpty ? <String, dynamic>{} : jsonDecode(resp.body);
    if (resp.statusCode >= 400) {
      final msg = body is Map ? (body['message'] ?? body['error'] ?? resp.body) : resp.body;
      throw Exception('HTTP ${resp.statusCode}: $msg');
    }
    if (body is Map && body.containsKey('data')) return body['data'];
    return body;
  }
}
