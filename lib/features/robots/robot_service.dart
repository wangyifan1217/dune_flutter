import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'robot_catalog_cache.dart';
import 'robot_models.dart';

/// APP 拉取机器人目录（flow-go GET /api/v1/robots）。
class RobotService {
  RobotService({required this.session});

  final AuthSession session;

  Future<List<RobotRole>> listRobots() async {
    final uri = Uri.parse('${session.apiBase}/robots');
    final resp = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${session.token}',
        'Accept': 'application/json',
      },
    );
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final msg = decoded is Map ? '${decoded['message'] ?? ''}' : '';
      throw Exception(msg.isEmpty ? '加载机器人失败 (${resp.statusCode})' : msg);
    }
    if (decoded is Map && decoded['success'] == false) {
      throw Exception('${decoded['message'] ?? '加载机器人失败'}');
    }
    final data = decoded is Map ? decoded['data'] : decoded;
    final list = data is List
        ? data
        : (data is Map && data['items'] is List
              ? data['items'] as List
              : const []);
    final roles = list
        .whereType<Map>()
        .map((e) => RobotRole.fromApi(Map<String, dynamic>.from(e)))
        .where((r) => r.id.isNotEmpty && r.name.isNotEmpty)
        .toList();
    RobotCatalogCache.instance.rememberAll(roles);
    return roles;
  }
}
