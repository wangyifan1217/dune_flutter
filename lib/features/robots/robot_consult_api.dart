import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'robot_consult_models.dart';

/// 灯塔机器人咨询 API：`/api/v1/lighthouse/bot/consults*`
class RobotConsultApi {
  RobotConsultApi({required this.session, http.Client? client})
      : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

  String get _base => session.apiBase.replaceAll(RegExp(r'/$'), '');

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse('$_base$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(
      queryParameters: <String, String>{...base.queryParameters, ...query},
    );
  }

  Map<String, String> get _headers => <String, String>{
        'Authorization': 'Bearer ${session.token}',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Future<RobotConsultRecord> start({
    required String question,
    String robotKey = 'r_lighthouse',
    String? scenarioKey,
    Map<String, dynamic>? context,
  }) async {
    final body = <String, dynamic>{
      'question': question.trim(),
      'robotKey': robotKey,
      if (scenarioKey != null && scenarioKey.isNotEmpty)
        'scenarioKey': scenarioKey,
      if (context != null && context.isNotEmpty) 'context': context,
    };
    final resp = await _client.post(
      _uri('/lighthouse/bot/consults'),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _parseJob(resp, action: '发起咨询');
  }

  Future<RobotConsultListResult> list({
    String? robotKey,
    String? status,
    bool unreadOnly = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final resp = await _client.get(
      _uri('/lighthouse/bot/consults', {
        if (robotKey != null && robotKey.isNotEmpty) 'robotKey': robotKey,
        if (status != null && status.isNotEmpty) 'status': status,
        if (unreadOnly) 'unread': '1',
        'limit': '$limit',
        'offset': '$offset',
      }),
      headers: _headers,
    );
    final decoded = _decode(resp);
    _ensureOk(resp, decoded, action: '加载咨询列表');
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) {
      return const RobotConsultListResult(items: [], total: 0, unreadCount: 0);
    }
    final rawItems = data['items'];
    final items = <RobotConsultRecord>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          items.add(RobotConsultRecord.fromApi(Map<String, dynamic>.from(e)));
        }
      }
    }
    return RobotConsultListResult(
      items: items,
      total: _asInt(data['total']) ?? items.length,
      unreadCount: _asInt(data['unreadCount']) ?? 0,
    );
  }

  Future<RobotConsultRecord> getJob(
    String jobId, {
    bool markRead = true,
  }) async {
    final resp = await _client.get(
      _uri(
        '/lighthouse/bot/consults/${Uri.encodeComponent(jobId)}',
        markRead ? null : {'markRead': '0'},
      ),
      headers: _headers,
    );
    return _parseJob(resp, action: '加载咨询详情');
  }

  Future<int> unreadCount() async {
    final resp = await _client.get(
      _uri('/lighthouse/bot/consults/unread-count'),
      headers: _headers,
    );
    final decoded = _decode(resp);
    if (resp.statusCode == 404) return 0;
    _ensureOk(resp, decoded, action: '加载未读数');
    final data = decoded is Map ? decoded['data'] : null;
    if (data is Map) return _asInt(data['unreadCount']) ?? 0;
    return 0;
  }

  Future<RobotConsultRecord> markRead(String jobId) async {
    final resp = await _client.post(
      _uri('/lighthouse/bot/consults/${Uri.encodeComponent(jobId)}/read'),
      headers: _headers,
      body: '{}',
    );
    return _parseJob(resp, action: '标记已读');
  }

  Future<int> markAllRead() async {
    final resp = await _client.post(
      _uri('/lighthouse/bot/consults/read-all'),
      headers: _headers,
      body: '{}',
    );
    final decoded = _decode(resp);
    _ensureOk(resp, decoded, action: '全部标已读');
    final data = decoded is Map ? decoded['data'] : null;
    if (data is Map) return _asInt(data['marked']) ?? 0;
    return 0;
  }

  Future<void> delete(String jobId) async {
    final resp = await _client.delete(
      _uri('/lighthouse/bot/consults/${Uri.encodeComponent(jobId)}'),
      headers: _headers,
    );
    final decoded = _decode(resp);
    _ensureOk(resp, decoded, action: '删除咨询');
  }

  RobotConsultRecord _parseJob(http.Response resp, {required String action}) {
    final decoded = _decode(resp);
    _ensureOk(resp, decoded, action: action);
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! Map) {
      throw Exception('$action失败：响应格式错误');
    }
    return RobotConsultRecord.fromApi(Map<String, dynamic>.from(data));
  }

  dynamic _decode(http.Response resp) {
    if (resp.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  void _ensureOk(http.Response resp, dynamic decoded, {required String action}) {
    if (resp.statusCode == 401) {
      throw Exception('登录已失效，请重新登录');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final msg = decoded is Map
          ? '${decoded['message'] ?? decoded['Message'] ?? ''}'
          : '';
      throw Exception(
        msg.isEmpty ? '$action失败 (HTTP ${resp.statusCode})' : msg,
      );
    }
    if (decoded is Map && decoded['success'] == false) {
      throw Exception('${decoded['message'] ?? '$action失败'}');
    }
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }
}
