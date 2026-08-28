import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/auth_session.dart';
import 'digital_auto_config.dart';

class McpToolDef {
  const McpToolDef({
    required this.name,
    this.description = '',
    this.inputSchema = const <String, dynamic>{},
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  Map<String, dynamic> toOpenAiTool() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': inputSchema.isEmpty
            ? {'type': 'object', 'properties': <String, dynamic>{}}
            : inputSchema,
      },
    };
  }
}

class McpJsonRpcClient {
  McpJsonRpcClient({
    required this.session,
    required this.configuration,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final AuthSession session;
  final DigitalAutoAssistantConfig configuration;
  final http.Client _http;
  int _id = 0;

  Uri get _uri {
    final base = session.apiBase.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base${configuration.mcpPath}');
  }

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Future<void> initialize() async {
    await _rpc('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': <String, dynamic>{},
      'clientInfo': {'name': 'dunes-flutter', 'version': '1.0.0'},
    });
    try {
      await _rpc('notifications/initialized', null, notification: true);
    } catch (_) {}
  }

  Future<List<McpToolDef>> listTools() async {
    final result = await _rpc('tools/list', <String, dynamic>{});
    final tools = result['tools'];
    if (tools is! List) return const [];
    return [
      for (final raw in tools)
        if (raw is Map)
          McpToolDef(
            name: (raw['name'] ?? '').toString(),
            description: (raw['description'] ?? '').toString(),
            inputSchema: raw['inputSchema'] is Map
                ? Map<String, dynamic>.from(raw['inputSchema'] as Map)
                : const <String, dynamic>{},
          ),
    ].where((t) => t.name.isNotEmpty).toList();
  }

  Future<String> callTool(String name, Map<String, dynamic> arguments) async {
    final result = await _rpc('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    return _stringifyResult(result);
  }

  Future<Map<String, dynamic>> _rpc(
    String method,
    Object? params, {
    bool notification = false,
  }) async {
    final body = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      if (!notification) 'id': ++_id,
    };
    if (params != null) body['params'] = params;
    final resp = await _http
        .post(_uri, headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    if (notification && (resp.statusCode == 204 || resp.body.trim().isEmpty)) {
      return const {};
    }
    if (resp.statusCode == 401) {
      throw Exception('登录已失效，请重新登录后再试');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('MCP 请求失败 (${resp.statusCode})');
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map) {
      throw Exception('MCP 返回格式无法解析');
    }
    if (decoded['error'] != null) {
      final err = decoded['error'];
      final msg = err is Map
          ? (err['message'] ?? err).toString()
          : err.toString();
      throw Exception(msg);
    }
    final result = decoded['result'];
    if (result is Map<String, dynamic>) return result;
    if (result is Map) return Map<String, dynamic>.from(result);
    return {'result': result};
  }

  String _stringifyResult(Map<String, dynamic> result) {
    final content = result['content'];
    if (content is List) {
      final texts = <String>[];
      for (final item in content) {
        if (item is Map && item['text'] != null) {
          texts.add(item['text'].toString());
        }
      }
      if (texts.isNotEmpty) return texts.join('\n');
    }
    return jsonEncode(result);
  }
}
