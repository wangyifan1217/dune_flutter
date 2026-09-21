import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';

/// 任务模块新增管理能力的独立接口适配层。
///
/// 旧任务接口全部保留在 [TaskApi] 中，避免管理功能的接口变化影响任务
/// 列表、详情、操作和日报流程。后端尚未开放某一能力时，页面会把错误
/// 转换成可理解的空状态，而不是影响原有任务页面。
class TaskManagementApi {
  TaskManagementApi(this.session);

  final AuthSession session;

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    final normalized = path.replaceAll(RegExp(r'^/+'), '');
    final full = normalized.isEmpty
        ? '$base/qianji/tasks/management'
        : '$base/qianji/tasks/management/$normalized';
    return Uri.parse(full).replace(queryParameters: query);
  }

  dynamic _unwrap(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw Exception('任务管理服务返回格式异常');
    }
    if (body is! Map) throw Exception('任务管理服务返回格式异常');
    if (body['success'] == false || response.statusCode >= 400) {
      throw Exception('${body['message'] ?? '任务管理服务暂不可用'}');
    }
    return body['data'];
  }

  Future<List<TaskRecurringRule>> listRecurringRules() async {
    final response = await http.get(_uri('recurring-rules'), headers: _headers);
    final data = _unwrap(response);
    final items = data is Map ? data['items'] : data;
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) => TaskRecurringRule.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<TaskRecurringRule> createRecurringRule(
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      _uri('recurring-rules'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = _unwrap(response);
    return TaskRecurringRule.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<TaskRecurringRule> setRecurringRuleEnabled(
    String ruleId,
    bool enabled,
  ) async {
    final response = await http.patch(
      _uri('recurring-rules/$ruleId'),
      headers: _headers,
      body: jsonEncode({'enabled': enabled}),
    );
    final data = _unwrap(response);
    return TaskRecurringRule.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<TaskRecurringExecution>> listRecurringExecutions(
    String ruleId,
  ) async {
    final response = await http.get(
      _uri('recurring-rules/$ruleId/executions'),
      headers: _headers,
    );
    final data = _unwrap(response);
    final items = data is Map ? data['items'] : data;
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              TaskRecurringExecution.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<TaskRecurringExecution> executeRecurringRule(String ruleId) async {
    final response = await http.post(
      _uri('recurring-rules/$ruleId/execute'),
      headers: _headers,
    );
    final data = _unwrap(response);
    final execution = data is Map ? data['execution'] : data;
    return TaskRecurringExecution.fromJson(
      Map<String, dynamic>.from(execution as Map),
    );
  }

  Future<Map<String, dynamic>> getConfig() async {
    final response = await http.get(_uri('config'), headers: _headers);
    final data = _unwrap(response);
    if (data is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> saveConfig(Map<String, dynamic> config) async {
    final response = await http.put(
      _uri('config'),
      headers: _headers,
      body: jsonEncode(config),
    );
    final data = _unwrap(response);
    if (data is! Map) return <String, dynamic>{};
    return Map<String, dynamic>.from(data);
  }

  Future<TaskImportPreview> previewImport({
    required Uint8List bytes,
    required String fileName,
    required String importKind,
    int? targetUserId,
  }) async {
    final request = http.MultipartRequest('POST', _uri('imports/preview'));
    request.headers['Authorization'] = 'Bearer ${session.token}';
    request.fields['importKind'] = importKind;
    if (targetUserId != null && targetUserId > 0) {
      request.fields['targetUserId'] = '$targetUserId';
    }
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: fileName),
    );
    final response = await http.Response.fromStream(await request.send());
    final data = _unwrap(response);
    return TaskImportPreview.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<TaskImportCommitResult> commitImport(String importId) async {
    final response = await http.post(
      _uri('imports/commit'),
      headers: _headers,
      body: jsonEncode({'importId': importId}),
    );
    final data = _unwrap(response);
    if (data is Map) {
      return TaskImportCommitResult.fromJson(Map<String, dynamic>.from(data));
    }
    return const TaskImportCommitResult(status: 'success');
  }

  Future<Uint8List> downloadImportTemplate(String importKind) async {
    final response = await http.get(
      _uri('imports/template', {'kind': importKind}),
      headers: {'Authorization': 'Bearer ${session.token}'},
    );
    if (response.statusCode >= 400) {
      _unwrap(response);
    }
    if (response.bodyBytes.isEmpty) {
      throw Exception('模板下载失败');
    }
    return response.bodyBytes;
  }

  Future<List<TaskImportEmployee>> searchImportEmployees(String q) async {
    final query = q.trim().isEmpty ? null : {'q': q.trim()};
    final response = await http.get(
      _uri('imports/employees', query),
      headers: _headers,
    );
    final data = _unwrap(response);
    final items = data is List ? data : const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              TaskImportEmployee.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.id > 0)
        .toList(growable: false);
  }

  Future<TaskImportEmployee> lookupImportEmployee(int userId) async {
    final response = await http.get(
      _uri('imports/employee', {'userId': '$userId'}),
      headers: _headers,
    );
    final data = _unwrap(response);
    return TaskImportEmployee.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<TaskImportHistoryItem>> listImportHistory() async {
    final response = await http.get(_uri('imports/history'), headers: _headers);
    final data = _unwrap(response);
    final items = data is Map ? data['items'] : data;
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              TaskImportHistoryItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<TaskCalendarSnapshot> listTaskCalendar({int? year}) async {
    final query = year == null ? null : {'year': '$year'};
    final response = await http.get(_uri('calendar', query), headers: _headers);
    final data = _unwrap(response);
    if (data is! Map) return const TaskCalendarSnapshot();
    return TaskCalendarSnapshot.fromJson(Map<String, dynamic>.from(data));
  }

  Future<TaskCalendarSyncResult> syncTaskCalendar({int? year}) async {
    final response = await http.post(
      _uri('calendar/sync'),
      headers: _headers,
      body: jsonEncode({'year': year ?? DateTime.now().year}),
    );
    final data = _unwrap(response);
    if (data is! Map) return const TaskCalendarSyncResult();
    return TaskCalendarSyncResult.fromJson(Map<String, dynamic>.from(data));
  }
}

class TaskRecurringRule {
  const TaskRecurringRule({
    required this.id,
    required this.title,
    this.frequency = '',
    this.startDate = '',
    this.endDate = '',
    this.enabled = true,
    this.ownerName = '',
  });

  final String id;
  final String title;
  final String frequency;
  final String startDate;
  final String endDate;
  final bool enabled;
  final String ownerName;

  factory TaskRecurringRule.fromJson(Map<String, dynamic> json) {
    return TaskRecurringRule(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? json['name'] ?? ''}',
      frequency: '${json['frequency'] ?? json['cycle'] ?? ''}',
      startDate: '${json['startDate'] ?? ''}',
      endDate: '${json['endDate'] ?? ''}',
      enabled: json['enabled'] != false,
      ownerName: '${json['ownerName'] ?? ''}',
    );
  }
}

class TaskRecurringExecution {
  const TaskRecurringExecution({
    required this.id,
    required this.ruleId,
    this.scheduledDate = '',
    this.status = '',
    this.taskId,
    this.errorMessage = '',
    this.createdAt = '',
  });

  final String id;
  final String ruleId;
  final String scheduledDate;
  final String status;
  final String? taskId;
  final String errorMessage;
  final String createdAt;

  factory TaskRecurringExecution.fromJson(Map<String, dynamic> json) {
    return TaskRecurringExecution(
      id: '${json['id'] ?? ''}',
      ruleId: '${json['ruleId'] ?? ''}',
      scheduledDate: '${json['scheduledDate'] ?? ''}',
      status: '${json['status'] ?? ''}',
      taskId: json['taskId'] == null ? null : '${json['taskId']}',
      errorMessage: '${json['errorMessage'] ?? ''}',
      createdAt: '${json['createdAt'] ?? ''}',
    );
  }
}

class TaskImportPreview {
  const TaskImportPreview({
    this.importId = '',
    this.total = 0,
    this.valid = 0,
    this.invalid = 0,
    this.parentCount = 0,
    this.childCount = 0,
    this.targetUserName = '',
    this.probationStartAt = '',
    this.probationEndAt = '',
    this.errors = const [],
    this.warnings = const [],
  });

  final String importId;
  final int total;
  final int valid;
  final int invalid;
  final int parentCount;
  final int childCount;
  final String targetUserName;
  final String probationStartAt;
  final String probationEndAt;
  final List<String> errors;
  final List<String> warnings;

  bool get canCommit => importId.trim().isNotEmpty && invalid <= 0 && valid > 0;

  String get periodLabel {
    if (probationStartAt.isEmpty && probationEndAt.isEmpty) return '';
    if (probationStartAt.isEmpty) return probationEndAt;
    if (probationEndAt.isEmpty) return probationStartAt;
    return '$probationStartAt 至 $probationEndAt';
  }

  factory TaskImportPreview.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'] ?? json['errorRows'];
    final rawWarnings = json['warnings'];
    return TaskImportPreview(
      importId: '${json['importId'] ?? json['id'] ?? ''}',
      total: (json['total'] as num?)?.toInt() ?? 0,
      valid: (json['valid'] as num?)?.toInt() ?? 0,
      invalid: (json['invalid'] as num?)?.toInt() ?? 0,
      parentCount: (json['parentCount'] as num?)?.toInt() ?? 0,
      childCount: (json['childCount'] as num?)?.toInt() ?? 0,
      targetUserName: '${json['targetUserName'] ?? ''}',
      probationStartAt: '${json['probationStartAt'] ?? ''}',
      probationEndAt: '${json['probationEndAt'] ?? ''}',
      errors: rawErrors is List
          ? rawErrors.map((item) => '$item').toList(growable: false)
          : const [],
      warnings: rawWarnings is List
          ? rawWarnings.map((item) => '$item').toList(growable: false)
          : const [],
    );
  }
}

class TaskImportCommitResult {
  const TaskImportCommitResult({
    this.status = '',
    this.created = 0,
    this.createdParents = 0,
    this.createdChildren = 0,
    this.failed = 0,
    this.errors = const [],
  });

  final String status;
  final int created;
  final int createdParents;
  final int createdChildren;
  final int failed;
  final List<String> errors;

  bool get ok => status == 'success' || (created > 0 && failed == 0);

  String get summary {
    if (createdParents > 0 || createdChildren > 0) {
      return '已创建 $createdParents 项主任务、$createdChildren 项验收目标';
    }
    if (created > 0) return '已创建 $created 条任务';
    return status == 'failed' ? '导入失败' : '导入完成';
  }

  factory TaskImportCommitResult.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'];
    return TaskImportCommitResult(
      status: '${json['status'] ?? ''}',
      created: (json['created'] as num?)?.toInt() ?? 0,
      createdParents: (json['createdParents'] as num?)?.toInt() ?? 0,
      createdChildren: (json['createdChildren'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      errors: rawErrors is List
          ? rawErrors.map((item) => '$item').toList(growable: false)
          : const [],
    );
  }
}

class TaskImportEmployee {
  const TaskImportEmployee({
    required this.id,
    this.displayName = '',
    this.departmentName = '',
    this.probationStartAt = '',
    this.probationEndAt = '',
    this.supervisorName = '',
    this.avatarPreset = '',
    this.avatarObjectKey = '',
    this.avatarUrl = '',
  });

  final int id;
  final String displayName;
  final String departmentName;
  final String probationStartAt;
  final String probationEndAt;
  final String supervisorName;
  final String avatarPreset;
  final String avatarObjectKey;
  final String avatarUrl;

  String get periodLabel {
    if (probationStartAt.isEmpty && probationEndAt.isEmpty) return '';
    if (probationStartAt.isEmpty) return probationEndAt;
    if (probationEndAt.isEmpty) return probationStartAt;
    return '$probationStartAt 至 $probationEndAt';
  }

  factory TaskImportEmployee.fromJson(Map<String, dynamic> json) {
    return TaskImportEmployee(
      id:
          (json['id'] as num?)?.toInt() ??
          (json['userId'] as num?)?.toInt() ??
          0,
      displayName: '${json['displayName'] ?? ''}',
      departmentName: '${json['departmentName'] ?? ''}',
      probationStartAt: '${json['probationStartAt'] ?? json['hiredAt'] ?? ''}',
      probationEndAt: '${json['probationEndAt'] ?? ''}',
      supervisorName: '${json['supervisorName'] ?? ''}',
      avatarPreset: '${json['avatarPreset'] ?? ''}',
      avatarObjectKey: '${json['avatarObjectKey'] ?? ''}',
      avatarUrl: '${json['avatarUrl'] ?? json['avatarURL'] ?? ''}',
    );
  }
}

class TaskImportHistoryItem {
  const TaskImportHistoryItem({
    required this.id,
    this.fileName = '',
    this.importKind = '',
    this.status = '',
    this.total = 0,
    this.parentCount = 0,
    this.childCount = 0,
    this.targetUserName = '',
    this.createdAt = '',
  });

  final String id;
  final String fileName;
  final String importKind;
  final String status;
  final int total;
  final int parentCount;
  final int childCount;
  final String targetUserName;
  final String createdAt;

  String get kindLabel => importKind == 'probation' ? '试用期任务' : '任务';

  factory TaskImportHistoryItem.fromJson(Map<String, dynamic> json) {
    return TaskImportHistoryItem(
      id: '${json['id'] ?? ''}',
      fileName: '${json['fileName'] ?? ''}',
      importKind: '${json['importKind'] ?? ''}',
      status: '${json['status'] ?? ''}',
      total: (json['total'] as num?)?.toInt() ?? 0,
      parentCount: (json['parentCount'] as num?)?.toInt() ?? 0,
      childCount: (json['childCount'] as num?)?.toInt() ?? 0,
      targetUserName: '${json['targetUserName'] ?? ''}',
      createdAt: '${json['createdAt'] ?? ''}',
    );
  }
}

class TaskCalendarSnapshot {
  const TaskCalendarSnapshot({this.year = 0, this.items = const []});

  final int year;
  final List<TaskCalendarDay> items;

  factory TaskCalendarSnapshot.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return TaskCalendarSnapshot(
      year: (json['year'] as num?)?.toInt() ?? 0,
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) =>
                      TaskCalendarDay.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class TaskCalendarDay {
  const TaskCalendarDay({
    required this.date,
    this.dayType = '',
    this.isWorkday = false,
    this.holidayName = '',
  });

  final String date;
  final String dayType;
  final bool isWorkday;
  final String holidayName;

  factory TaskCalendarDay.fromJson(Map<String, dynamic> json) {
    return TaskCalendarDay(
      date: '${json['date'] ?? ''}',
      dayType: '${json['dayType'] ?? ''}',
      isWorkday: json['isWorkday'] == true,
      holidayName: '${json['holidayName'] ?? ''}',
    );
  }

  bool get isHoliday => dayType == 'holiday';
  bool get isAdjustedWorkday => dayType == 'adjusted_workday';

  String get typeLabel {
    if (isHoliday) return holidayName.isEmpty ? '法定节假日' : holidayName;
    if (isAdjustedWorkday) return '调休上班';
    if (dayType == 'weekend') return '周末';
    return '工作日';
  }
}

class TaskCalendarSyncResult {
  const TaskCalendarSyncResult({
    this.year = 0,
    this.count = 0,
    this.workdays = 0,
    this.nonWorkdays = 0,
    this.syncedAt = '',
  });

  final int year;
  final int count;
  final int workdays;
  final int nonWorkdays;
  final String syncedAt;

  factory TaskCalendarSyncResult.fromJson(Map<String, dynamic> json) {
    return TaskCalendarSyncResult(
      year: (json['year'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
      workdays: (json['workdays'] as num?)?.toInt() ?? 0,
      nonWorkdays: (json['nonWorkdays'] as num?)?.toInt() ?? 0,
      syncedAt: '${json['syncedAt'] ?? ''}',
    );
  }
}
