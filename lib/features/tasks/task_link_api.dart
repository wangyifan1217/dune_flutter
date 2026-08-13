import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'task_link_models.dart';
import 'task_models.dart';

/// 任务 × 会议 × 知识库绑定接口（全部为新增端点，不影响既有 TaskApi）。
class TaskLinkApi {
  TaskLinkApi(this.session);

  final AuthSession session;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = session.apiBase.replaceAll(RegExp(r'/+$'), '');
    final p = path.replaceAll(RegExp(r'^/+'), '');
    return Uri.parse('$base/qianji/$p').replace(queryParameters: query);
  }

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

  Future<TaskLinksResult> fetchLinks(int taskId) async {
    final resp = await http.get(_uri('tasks/$taskId/links'), headers: _headers);
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    final links = (map['links'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => TaskLink.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
    return TaskLinksResult(
      links: links,
      bindRun: TaskBindRun.fromJson(map['bindRun']),
    );
  }

  Future<TaskLink> addLink(int taskId, Map<String, dynamic> body) async {
    final resp = await http.post(
      _uri('tasks/$taskId/links'),
      headers: _headers,
      body: jsonEncode(body),
    );
    final data = _unwrap(resp);
    return TaskLink.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// 删除关联，返回被删行（用于撤销时原样加回）。
  Future<TaskLink> deleteLink(int taskId, int linkId) async {
    final resp = await http.delete(
      _uri('tasks/$taskId/links/$linkId'),
      headers: _headers,
    );
    final data = _unwrap(resp);
    return TaskLink.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<TaskLinkCandidates> fetchCandidates(int taskId, {String? q}) async {
    final query = <String, String>{};
    if (q != null && q.trim().isNotEmpty) query['q'] = q.trim();
    final resp = await http.get(
      _uri('tasks/$taskId/links/candidates', query.isEmpty ? null : query),
      headers: _headers,
    );
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    return TaskLinkCandidates(
      meetings: (map['meetings'] as List? ?? const [])
          .whereType<Map>()
          .map((e) =>
              TaskLinkCandidateMeeting.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      docs: (map['kbDocs'] as List? ?? const [])
          .whereType<Map>()
          .map((e) =>
              TaskLinkCandidateDoc.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }

  Future<void> rematch(int taskId) async {
    final resp = await http.post(
      _uri('tasks/$taskId/links/rematch'),
      headers: _headers,
      body: jsonEncode(const <String, dynamic>{}),
    );
    _unwrap(resp);
  }

  Future<MeetingTaskBindData> fetchMeetingSuggestions(int meetingId) async {
    final resp = await http.get(
      _uri('meetings/$meetingId/task-suggestions'),
      headers: _headers,
    );
    final data = _unwrap(resp);
    final map = data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    return MeetingTaskBindData(
      suggestions: (map['suggestions'] as List? ?? const [])
          .whereType<Map>()
          .map((e) =>
              MeetingTaskSuggestion.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      syncedTasks: (map['syncedTasks'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => MeetingSyncedTask.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      bindRun: TaskBindRun.fromJson(map['bindRun']),
    );
  }

  Future<TaskItem> acceptSuggestion(
    int meetingId,
    int suggestionId, {
    String? title,
    String? description,
  }) async {
    final resp = await http.post(
      _uri('meetings/$meetingId/task-suggestions/$suggestionId/accept'),
      headers: _headers,
      body: jsonEncode({
        'title': ?title,
        'description': ?description,
      }),
    );
    final data = _unwrap(resp);
    return TaskItem.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> dismissSuggestion(int meetingId, int suggestionId) async {
    final resp = await http.post(
      _uri('meetings/$meetingId/task-suggestions/$suggestionId/dismiss'),
      headers: _headers,
      body: jsonEncode(const <String, dynamic>{}),
    );
    _unwrap(resp);
  }
}
