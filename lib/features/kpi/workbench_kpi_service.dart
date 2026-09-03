import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';
import '../profile/work_profile_kpi.dart';

class WorkbenchKpiAccess {
  const WorkbenchKpiAccess({required this.allowed});
  final bool allowed;
}

class WorkbenchKpiPersonRef {
  const WorkbenchKpiPersonRef({
    required this.userId,
    required this.displayName,
    this.dept = '',
    this.title = '',
  });

  final int userId;
  final String displayName;
  final String dept;
  final String title;

  factory WorkbenchKpiPersonRef.fromJson(Map<String, dynamic> json) {
    return WorkbenchKpiPersonRef(
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      displayName: '${json['displayName'] ?? ''}',
      dept: '${json['departmentName'] ?? ''}',
      title: '${json['title'] ?? json['positionName'] ?? ''}',
    );
  }
}

class WorkbenchKpiTask {
  const WorkbenchKpiTask({
    required this.id,
    required this.userId,
    required this.name,
    this.userName = '',
    this.phone = '',
    this.content = '',
    this.province = '',
    this.taskType = '',
    this.startDate = '',
    this.endDate = '',
    this.tagName = '',
    this.isCounted = true,
    this.isReported = false,
  });

  final int id;
  final int userId;
  final String userName;
  final String phone;
  final String name;
  final String content;
  final String province;
  final String taskType;
  final String startDate;
  final String endDate;
  final String tagName;
  final bool isCounted;
  final bool isReported;

  factory WorkbenchKpiTask.fromJson(Map<String, dynamic> json) {
    return WorkbenchKpiTask(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      userName: '${json['userName'] ?? ''}',
      phone: '${json['phone'] ?? ''}',
      name: '${json['name'] ?? ''}',
      content: '${json['content'] ?? ''}',
      province: '${json['province'] ?? ''}',
      taskType: '${json['taskType'] ?? ''}',
      startDate: '${json['startDate'] ?? ''}',
      endDate: '${json['endDate'] ?? ''}',
      tagName: '${json['tagName'] ?? ''}',
      isCounted: json['isCounted'] != false,
      isReported: json['isReported'] == true,
    );
  }

  Map<String, dynamic> toInputJson() => {
        'userId': userId,
        'name': name.trim(),
        'content': content.trim(),
        'province': province.trim(),
        'taskType': taskType.trim(),
        'startDate': startDate.trim(),
        'endDate': endDate.trim(),
        'tagName': tagName.trim(),
        'isCounted': isCounted,
        'isReported': isReported,
      };

  WorkbenchKpiTask copyWith({
    int? id,
    int? userId,
    String? userName,
    String? phone,
    String? name,
    String? content,
    String? province,
    String? taskType,
    String? startDate,
    String? endDate,
    String? tagName,
    bool? isCounted,
    bool? isReported,
  }) {
    return WorkbenchKpiTask(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      content: content ?? this.content,
      province: province ?? this.province,
      taskType: taskType ?? this.taskType,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      tagName: tagName ?? this.tagName,
      isCounted: isCounted ?? this.isCounted,
      isReported: isReported ?? this.isReported,
    );
  }
}

class WorkbenchKpiOverrideItem {
  const WorkbenchKpiOverrideItem({
    required this.taskId,
    this.weightPct,
    this.scoreAdj,
    this.remark = '',
  });

  final int taskId;
  final double? weightPct;
  final double? scoreAdj;
  final String remark;

  Map<String, dynamic> toJson() => {
        'taskId': taskId,
        if (weightPct != null) 'weightPct': weightPct,
        if (scoreAdj != null) 'scoreAdj': scoreAdj,
        'remark': remark.trim(),
      };
}

class WorkbenchKpiService {
  WorkbenchKpiService({required this.session, http.Client? client})
      : _client = client;

  final AuthSession session;
  final http.Client? _client;

  dynamic _unwrap(http.Response response) {
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final msg = decoded is Map
          ? (decoded['message'] ?? decoded['error'] ?? decoded)
          : decoded;
      throw Exception('${msg ?? '绩效请求失败：HTTP ${response.statusCode}'}');
    }
    if (decoded is Map && decoded['success'] == false) {
      throw Exception((decoded['message'] ?? '绩效请求失败').toString());
    }
    if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
    return decoded;
  }

  Future<WorkbenchKpiAccess> fetchAccess() async {
    final resp = await dunesHttpGet(
      session,
      '/kpi/access',
      client: _client,
    );
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    return WorkbenchKpiAccess(allowed: map['allowed'] == true);
  }

  Future<List<WorkbenchKpiTask>> listTasks({
    String q = '',
    bool countedOnly = false,
  }) async {
    final query = <String, String>{};
    if (q.trim().isNotEmpty) query['q'] = q.trim();
    if (countedOnly) query['counted'] = '1';
    final qs = query.isEmpty
        ? ''
        : '?${query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    final resp = await dunesHttpGet(session, '/kpi/tasks$qs', client: _client);
    final data = _unwrap(resp);
    final rows = data is List ? data : const [];
    return rows
        .whereType<Map>()
        .map((e) => WorkbenchKpiTask.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<WorkbenchKpiTask> createTask(WorkbenchKpiTask draft) async {
    final resp = await dunesHttpPost(
      session,
      '/kpi/tasks',
      body: jsonEncode(draft.toInputJson()),
      client: _client,
    );
    final data = _unwrap(resp);
    return WorkbenchKpiTask.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<WorkbenchKpiTask> updateTask(WorkbenchKpiTask draft) async {
    final resp = await dunesHttpPatch(
      session,
      '/kpi/tasks/${draft.id}',
      body: jsonEncode(draft.toInputJson()),
      client: _client,
    );
    final data = _unwrap(resp);
    return WorkbenchKpiTask.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> deleteTask(int id) async {
    final resp = await dunesHttpDelete(
      session,
      '/kpi/tasks/$id',
      client: _client,
    );
    _unwrap(resp);
  }

  Future<WorkProfileKpiScore> rerunScore(String month) async {
    final resp = await dunesHttpPost(
      session,
      '/kpi/score',
      body: jsonEncode({'month': month.trim()}),
      client: _client,
    );
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    return WorkProfileKpiScore.fromJson(map);
  }

  Future<Uint8List> exportScore(String month) async {
    final q = Uri.encodeQueryComponent(month.trim());
    final resp = await dunesHttpGet(
      session,
      '/kpi/score/export?month=$q',
      headers: const {
        'Accept':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      },
      client: _client,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _unwrap(resp);
    }
    return resp.bodyBytes;
  }

  Future<WorkProfileKpiScore> fetchScore({
    required String month,
    int userId = 0,
  }) async {
    final query = <String, String>{'month': month.trim()};
    if (userId > 0) query['userId'] = '$userId';
    final qs = query.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final resp = await dunesHttpGet(session, '/kpi/score?$qs', client: _client);
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    return WorkProfileKpiScore.fromJson(map);
  }

  Future<WorkProfileKpiScore> saveOverrides({
    required String month,
    required int userId,
    required List<WorkbenchKpiOverrideItem> items,
  }) async {
    final resp = await dunesHttpPut(
      session,
      '/kpi/score/overrides',
      body: jsonEncode({
        'month': month.trim(),
        'userId': userId,
        'items': [for (final item in items) item.toJson()],
      }),
      client: _client,
    );
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    return WorkProfileKpiScore.fromJson(map);
  }

  Future<List<WorkbenchKpiPersonRef>> searchPeople(String q) async {
    final needle = q.trim();
    if (needle.isEmpty) return const [];
    final resp = await dunesHttpGet(
      session,
      '/org/users?q=${Uri.encodeQueryComponent(needle)}',
      client: _client,
    );
    final data = _unwrap(resp);
    final rows = data is List ? data : const [];
    return rows
        .whereType<Map>()
        .map((e) => WorkbenchKpiPersonRef.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.userId > 0 && e.displayName.isNotEmpty)
        .toList();
  }
}
