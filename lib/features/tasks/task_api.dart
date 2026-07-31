import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'task_models.dart';

class TaskApi {
  TaskApi(this.session);

  final AuthSession session;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    final p = path.replaceAll(RegExp(r'^/+'), '');
    final full = p.isEmpty ? '$base/qianji/tasks' : '$base/qianji/tasks/$p';
    return Uri.parse(full).replace(queryParameters: query);
  }

  Uri _root([Map<String, String>? query]) => _uri('', query);

  dynamic _unwrap(http.Response resp) {
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    if (body is! Map) {
      throw Exception('invalid response');
    }
    if (body['success'] == false) {
      throw Exception('${body['message'] ?? '请求失败'}');
    }
    if (resp.statusCode >= 400) {
      throw Exception('${body['message'] ?? 'HTTP ${resp.statusCode}'}');
    }
    return body['data'];
  }

  static String? _dateQuery(DateTime? d) {
    if (d == null) return null;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  Future<TaskListPage> listTasksPage({
    String scope = 'mine',
    String? status,
    String? priority,
    String? q,
    DateTime? dateFrom,
    DateTime? dateTo,
    int page = 0,
    int size = 20,
  }) async {
    final query = <String, String>{
      'scope': scope,
      'page': '$page',
      'size': '$size',
    };
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (priority != null && priority.isNotEmpty) query['priority'] = priority;
    if (q != null && q.trim().isNotEmpty) query['q'] = q.trim();
    final from = _dateQuery(dateFrom);
    final to = _dateQuery(dateTo);
    if (from != null) query['dateFrom'] = from;
    if (to != null) query['dateTo'] = to;
    final resp = await http.get(_root(query), headers: _headers);
    final data = _unwrap(resp);
    if (data is Map) {
      return TaskListPage.fromJson(Map<String, dynamic>.from(data));
    }
    // 兼容旧版直接返回数组
    if (data is List) {
      final items = data
          .whereType<Map>()
          .map((e) => TaskItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      return TaskListPage(items: items, hasMore: false, total: items.length);
    }
    return const TaskListPage(items: []);
  }

  /// 拉取多页合并（任务助手等需要尽量全量时使用）。
  Future<List<TaskItem>> listTasks({
    String scope = 'mine',
    String? status,
    String? priority,
    String? q,
    DateTime? dateFrom,
    DateTime? dateTo,
    int size = 100,
    int maxPages = 5,
  }) async {
    final out = <TaskItem>[];
    for (var page = 0; page < maxPages; page++) {
      final result = await listTasksPage(
        scope: scope,
        status: status,
        priority: priority,
        q: q,
        dateFrom: dateFrom,
        dateTo: dateTo,
        page: page,
        size: size,
      );
      out.addAll(result.items);
      if (!result.hasMore) break;
    }
    return out;
  }

  Future<TaskItem> createMain(Map<String, dynamic> body) async {
    final resp = await http.post(
      _root(),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = _unwrap(resp);
    return TaskItem.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<TaskDetail> getDetail(int id) async {
    final resp = await http.get(_uri('$id'), headers: _headers);
    final data = _unwrap(resp);
    final map = Map<String, dynamic>.from(data as Map);
    final task = TaskItem.fromJson(Map<String, dynamic>.from(map['task'] as Map));
    final subs = (map['subtasks'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => TaskItem.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    final logs = (map['logs'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => TaskProgressLog.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    final attachments = (map['attachments'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => TaskAttachment.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    final evalLogs = (map['evalLogs'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => TaskEvalLog.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    return TaskDetail(
      task: task,
      subtasks: subs,
      logs: logs,
      evalLogs: evalLogs,
      attachments: attachments,
    );
  }

  Future<void> deleteProgressLog(int taskId, int logId) async {
    final resp = await http.delete(
      _uri('$taskId/progress-logs/$logId'),
      headers: _headers,
    );
    _unwrap(resp);
  }

  Future<void> deleteEvalLog(int taskId, int logId) async {
    final resp = await http.delete(
      _uri('$taskId/eval-logs/$logId'),
      headers: _headers,
    );
    _unwrap(resp);
  }

  /// 复用 flow `/storage/upload`（bucket: xflow-proposals）。
  Future<TaskAttachment> uploadAttachment({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/storage/upload');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer ${session.token}';
    req.fields['bucket'] = 'xflow-proposals';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    final streamed = await req.send();
    final bodyText = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('上传失败: HTTP ${streamed.statusCode}');
    }
    final map = jsonDecode(bodyText);
    if (map is! Map || map['success'] == false) {
      throw Exception('${(map is Map ? map['message'] : null) ?? '上传失败'}');
    }
    final data = map['data'];
    if (data is! Map) throw Exception('上传失败: 返回数据异常');
    return TaskAttachment(
      id: 0,
      taskId: 0,
      fileName: fileName,
      objectKey: '${data['objectKey'] ?? data['url'] ?? ''}',
      url: '${data['url'] ?? ''}',
      bucket: '${data['bucket'] ?? 'xflow-proposals'}',
      sizeBytes: bytes.length,
      mimeType: '${data['contentType'] ?? ''}',
    );
  }

  Future<TaskItem> createSubtask(int parentId, Map<String, dynamic> body) async {
    final resp = await http.post(
      _uri('$parentId/subtasks'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = _unwrap(resp);
    return TaskItem.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<TaskItem> patchTask(int id, Map<String, dynamic> body) async {
    final resp = await http.patch(
      _uri('$id'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = _unwrap(resp);
    return TaskItem.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<TaskItem> approve(int id, {String comment = ''}) async {
    final resp = await http.post(
      _uri('$id/approve'),
      headers: _headers,
      body: jsonEncode({'comment': comment}),
    );
    final data = _unwrap(resp);
    return TaskItem.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<TaskItem> reject(int id, {String comment = ''}) async {
    final resp = await http.post(
      _uri('$id/reject'),
      headers: _headers,
      body: jsonEncode({'comment': comment}),
    );
    final data = _unwrap(resp);
    return TaskItem.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> deleteTask(int id) async {
    final resp = await http.delete(_uri('$id'), headers: _headers);
    _unwrap(resp);
  }

  Future<TaskItem> evaluate(
    int id, {
    required String level,
    String comment = '',
    List<TaskAttachment> attachments = const [],
  }) async {
    final resp = await http.post(
      _uri('$id/evaluate'),
      headers: _headers,
      body: jsonEncode({
        'level': level,
        'comment': comment,
        if (attachments.isNotEmpty)
          'attachments': attachments.map((e) => e.toCreateJson()).toList(),
      }),
    );
    final data = _unwrap(resp);
    return TaskItem.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// 解析附件可下载地址（优先直链，其次预签名）。
  Future<String> resolveAttachmentUrl(TaskAttachment a) async {
    final direct = a.url.trim();
    if (direct.startsWith('http://') || direct.startsWith('https://')) {
      return direct;
    }
    final key = a.objectKey.trim().isNotEmpty ? a.objectKey.trim() : direct;
    if (key.isEmpty) return '';
    if (key.startsWith('http://') || key.startsWith('https://')) return key;
    final bucket = a.bucket.trim().isEmpty ? 'xflow-proposals' : a.bucket.trim();
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    try {
      final uri = Uri.parse(
        '$base/storage/presigned-get?bucket=${Uri.encodeQueryComponent(bucket)}&objectKey=${Uri.encodeQueryComponent(key)}',
      );
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer ${session.token}',
      });
      final data = _unwrap(resp);
      if (data is Map) {
        final url = '${data['url'] ?? ''}'.trim();
        if (url.isNotEmpty) return url;
      }
    } catch (_) {}
    return '$base/storage/download?bucket=${Uri.encodeQueryComponent(bucket)}&objectKey=${Uri.encodeQueryComponent(key)}&proxy=1';
  }

  /// 带鉴权拉取附件字节，保证 PC/APP 真正落到本地。
  Future<Uint8List> downloadAttachmentBytes(TaskAttachment a) async {
    final key = a.objectKey.trim().isNotEmpty ? a.objectKey.trim() : a.url.trim();
    final bucket = a.bucket.trim().isEmpty ? 'xflow-proposals' : a.bucket.trim();
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    final headers = <String, String>{
      'Authorization': 'Bearer ${session.token}',
    };

    if (key.isNotEmpty &&
        !key.startsWith('http://') &&
        !key.startsWith('https://')) {
      final authUri = Uri.parse(
        '$base/storage/download?bucket=${Uri.encodeQueryComponent(bucket)}&objectKey=${Uri.encodeQueryComponent(key)}&proxy=1',
      );
      final resp = await http.get(authUri, headers: headers);
      if (resp.statusCode >= 200 && resp.statusCode < 300 && resp.bodyBytes.isNotEmpty) {
        return resp.bodyBytes;
      }
    }

    final url = await resolveAttachmentUrl(a);
    if (url.isEmpty) throw Exception('无法获取文件链接');
    final resp = await http.get(Uri.parse(url), headers: headers);
    if (resp.statusCode < 200 || resp.statusCode >= 300 || resp.bodyBytes.isEmpty) {
      throw Exception('下载失败: HTTP ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  Future<List<TaskAssignee>> listAssignees({String? q}) async {
    final query = <String, String>{};
    if (q != null && q.trim().isNotEmpty) query['q'] = q.trim();
    final resp = await http.get(
      _uri('assignees', query.isEmpty ? null : query),
      headers: _headers,
    );
    final data = _unwrap(resp);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => TaskAssignee.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  Future<List<HrbpDeptStat>> hrbpOverview({
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final query = <String, String>{};
    final from = _dateQuery(dateFrom);
    final to = _dateQuery(dateTo);
    if (from != null) query['dateFrom'] = from;
    if (to != null) query['dateTo'] = to;
    final resp = await http.get(
      _uri('hrbp/overview', query.isEmpty ? null : query),
      headers: _headers,
    );
    final data = _unwrap(resp);
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((e) => HrbpDeptStat.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// 是否可进「任务汇总」：完全以后端鉴权为准，前端不写死角色。
  Future<bool> canAccessHrbpOverview() async {
    try {
      final resp = await http.get(_uri('hrbp/overview'), headers: _headers);
      if (resp.statusCode == 401 || resp.statusCode == 403) return false;
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is Map && body['success'] == false) return false;
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<TaskListPage> hrbpDepartmentPage(
    int deptId, {
    DateTime? dateFrom,
    DateTime? dateTo,
    int page = 0,
    int size = 20,
  }) async {
    final query = <String, String>{
      'page': '$page',
      'size': '$size',
    };
    final from = _dateQuery(dateFrom);
    final to = _dateQuery(dateTo);
    if (from != null) query['dateFrom'] = from;
    if (to != null) query['dateTo'] = to;
    final resp = await http.get(
      _uri('hrbp/department/$deptId', query),
      headers: _headers,
    );
    final data = _unwrap(resp);
    if (data is Map) {
      return TaskListPage.fromJson(Map<String, dynamic>.from(data));
    }
    if (data is List) {
      final items = data
          .whereType<Map>()
          .map((e) => TaskItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      return TaskListPage(items: items, hasMore: false, total: items.length);
    }
    return const TaskListPage(items: []);
  }
}
