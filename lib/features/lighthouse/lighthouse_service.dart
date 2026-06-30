import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'lighthouse_data.dart';

const _lighthouseApiBaseOverride = String.fromEnvironment(
  'LIGHTHOUSE_API_BASE',
  defaultValue: '',
);

class LighthouseService {
  LighthouseService({
    required AuthSession session,
    http.Client? client,
  })  : _session = session,
        _client = client ?? http.Client();

  final AuthSession _session;
  final http.Client _client;

  /// 局域网访问时跟登录网关一致（`session.apiBase`），避免写死 localhost。
  String get _apiBase {
    if (_lighthouseApiBaseOverride.isNotEmpty) {
      return _lighthouseApiBaseOverride.replaceAll(RegExp(r'/$'), '');
    }
    return _session.apiBase.replaceAll(RegExp(r'/$'), '');
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse('$_apiBase$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: <String, String>{
      ...base.queryParameters,
      ...query,
    });
  }

  Map<String, String> get _headers => <String, String>{
        'Authorization': 'Bearer ${_session.token}',
        'Content-Type': 'application/json',
      };

  Future<LighthouseDataBundle> fetchOverview({
    String? period,
    String? date,
    String? fuel,
    int? offset,
  }) async {
    final resp = await _client.get(
      _uri('/lighthouse/overview', {
        if (period != null && period.isNotEmpty) 'period': period,
        if (date != null && date.isNotEmpty) 'date': date,
        if (fuel != null && fuel.isNotEmpty && fuel != '全部') 'fuel': fuel,
        if (offset != null && offset != 0) 'offset': '$offset',
      }),
      headers: _headers,
    );
    if (resp.statusCode == 403) {
      throw Exception('暂无权限');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('灯塔数据加载失败: HTTP ${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('灯塔数据格式错误');
    }

    final map = Map<String, dynamic>.from(decoded);
    final payload = _unwrapPayload(map);
    return LighthouseDataBundle.fromJson(payload);
  }

  /// 分析 tab 3D 坐标 + 机会清单（懒加载）。
  Future<Map<String, dynamic>> fetchAnalysisCube({
    String? period,
    String? date,
    String? fuel,
    int? offset,
    int topP = 12,
    int topS = 10,
    int topC = 10,
    int topOpp = 8,
  }) async {
    final resp = await _client.get(
      _uri('/lighthouse/analysis/cube', {
        if (period != null && period.isNotEmpty) 'period': period,
        if (date != null && date.isNotEmpty) 'date': date,
        if (fuel != null && fuel.isNotEmpty && fuel != '全部') 'fuel': fuel,
        if (offset != null && offset != 0) 'offset': '$offset',
        'top_p': '$topP',
        'top_s': '$topS',
        'top_c': '$topC',
        'top_opp': '$topOpp',
      }),
      headers: _headers,
    );
    if (resp.statusCode == 403) {
      throw Exception('暂无权限');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('分析数据加载失败: HTTP ${resp.statusCode}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('分析数据格式错误');
    }

    final map = Map<String, dynamic>.from(decoded);
    if (map['success'] == false) {
      throw Exception((map['message'] ?? '分析数据加载失败').toString());
    }

    final data = map['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return map;
  }

  Map<String, dynamic> _unwrapPayload(Map<String, dynamic> body) {
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '灯塔数据加载失败').toString());
    }

    if (body['data'] is Map &&
        (body.containsKey('product_detail') ||
            body.containsKey('supply_detail') ||
            body.containsKey('channel_detail') ||
            body.containsKey('metrics'))) {
      return body;
    }

    final data = body['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    return body;
  }
}
