import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/auth_session.dart';
import 'digital_auto_config.dart';
import 'mcp_jsonrpc_client.dart';

class DigitalAutoTurnEvent {
  const DigitalAutoTurnEvent({
    this.reply = '',
    this.toolStatus = '',
    this.error = '',
  });

  final String reply;
  final String toolStatus;
  final String error;
}

class DigitalAutoAgent {
  DigitalAutoAgent({
    required this.session,
    required this.configuration,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client(),
       _mcp = McpJsonRpcClient(
         session: session,
         configuration: configuration,
         httpClient: httpClient,
       );

  final AuthSession session;
  final DigitalAutoAssistantConfig configuration;
  final http.Client _http;
  final McpJsonRpcClient _mcp;

  List<McpToolDef> tools = const [];
  final List<Map<String, dynamic>> _messages = [];

  Future<void> connect({bool resetMessages = true}) async {
    await _mcp.initialize();
    tools = await _mcp.listTools();
    if (resetMessages) startFresh();
  }

  void startFresh() {
    _messages
      ..clear()
      ..add({'role': 'system', 'content': configuration.systemPrompt});
  }

  void hydrateMessages(List<Map<String, dynamic>> messages) {
    _messages
      ..clear()
      ..addAll(messages.map((m) => Map<String, dynamic>.from(m)));
    if (_messages.isEmpty ||
        (_messages.first['role']?.toString() != 'system')) {
      _messages.insert(0, {
        'role': 'system',
        'content': configuration.systemPrompt,
      });
    } else {
      _messages[0] = {'role': 'system', 'content': configuration.systemPrompt};
    }
  }

  List<Map<String, dynamic>> exportMessages() {
    return [for (final m in _messages) Map<String, dynamic>.from(m)];
  }

  Future<void> reset() async {
    await connect();
  }

  Future<void> send(
    String userText, {
    required void Function(DigitalAutoTurnEvent event) onUpdate,
    Future<bool> Function(DigitalAutoToolConfirmation confirmation)?
    onConfirmToolCall,
  }) async {
    if (tools.isEmpty) {
      throw Exception('MCP 尚未连上，请稍后重试');
    }
    _messages.add({'role': 'user', 'content': userText});

    for (var round = 0; round < 8; round++) {
      final outcome = await _complete(onUpdate);
      if (outcome.toolCalls.isEmpty) {
        final reply = outcome.text.trim();
        if (reply.isNotEmpty) {
          _messages.add({'role': 'assistant', 'content': reply});
          onUpdate(DigitalAutoTurnEvent(reply: reply));
        }
        return;
      }
      _messages.add({
        'role': 'assistant',
        'content': outcome.text.isEmpty ? null : outcome.text,
        'tool_calls': [
          for (final call in outcome.toolCalls)
            {
              'id': call.id,
              'type': 'function',
              'function': {'name': call.name, 'arguments': call.arguments},
            },
        ],
      });
      for (final call in outcome.toolCalls) {
        Map<String, dynamic> args = const {};
        try {
          final decoded = jsonDecode(
            call.arguments.isEmpty ? '{}' : call.arguments,
          );
          if (decoded is Map) {
            args = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          args = const {};
        }
        if (call.name == 'minutes_complete_action_item') {
          final confirmation = DigitalAutoToolConfirmation(
            toolName: call.name,
            arguments: args,
          );
          final approved = await onConfirmToolCall?.call(confirmation) ?? false;
          if (!approved) {
            _messages.add({
              'role': 'tool',
              'tool_call_id': call.id,
              'content': '用户未确认完成该行动项，未执行操作。',
            });
            continue;
          }
        }
        onUpdate(DigitalAutoTurnEvent(toolStatus: '正在调用 ${call.name}'));
        String result;
        try {
          result = await _mcp.callTool(call.name, args);
        } catch (e) {
          result = e.toString();
        }
        _messages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': result,
        });
      }
    }
    throw Exception('工具调用轮次过多，请简化问题后重试');
  }

  Uri get _chatUri {
    final base = session.apiBase.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base${configuration.chatPath}');
  }

  Future<_Completion> _complete(
    void Function(DigitalAutoTurnEvent event) onUpdate,
  ) async {
    final headers = <String, String>{
      'Authorization': 'Bearer ${session.token}',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };
    final body = <String, dynamic>{
      'stream': true,
      'tool_choice': 'auto',
      'messages': _messages,
      'tools': [for (final t in tools) t.toOpenAiTool()],
    };
    final req = http.Request('POST', _chatUri);
    req.headers.addAll(headers);
    req.body = jsonEncode(body);
    final streamed = await _http.send(req);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final err = await streamed.stream.bytesToString();
      throw Exception('模型请求失败 (${streamed.statusCode}) $err');
    }

    final acc = _ToolCallAccumulator();
    final text = StringBuffer();
    var pending = '';
    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      pending += chunk;
      final parts = pending.split('\n');
      pending = parts.removeLast();
      for (final raw in parts) {
        _consumeSseLine(raw, text, acc, onUpdate);
      }
    }
    if (pending.trim().isNotEmpty) {
      _consumeSseLine(pending, text, acc, onUpdate);
    }
    return _Completion(text: text.toString(), toolCalls: acc.done());
  }

  void _consumeSseLine(
    String raw,
    StringBuffer text,
    _ToolCallAccumulator acc,
    void Function(DigitalAutoTurnEvent event) onUpdate,
  ) {
    var line = raw.trim();
    if (line.isEmpty || line.startsWith(':')) return;
    if (line.startsWith('data:')) line = line.substring(5).trim();
    if (line.isEmpty || line == '[DONE]') return;
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return;
      json = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) return;
    final first = Map<String, dynamic>.from(choices.first as Map);
    final delta = first['delta'];
    if (delta is Map) {
      final dm = Map<String, dynamic>.from(delta);
      final content = dm['content'];
      if (content is String && content.isNotEmpty) {
        text.write(content);
        onUpdate(DigitalAutoTurnEvent(reply: text.toString()));
      }
      acc.feed(dm['tool_calls']);
    }
  }
}

class DigitalAutoToolConfirmation {
  const DigitalAutoToolConfirmation({
    required this.toolName,
    required this.arguments,
  });

  final String toolName;
  final Map<String, dynamic> arguments;
}

class _Completion {
  const _Completion({required this.text, required this.toolCalls});
  final String text;
  final List<_ToolCall> toolCalls;
}

class _ToolCall {
  const _ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
  final String id;
  final String name;
  final String arguments;
}

class _ToolCallAccumulator {
  final Map<int, _ToolCallDraft> _byIndex = {};

  void feed(Object? raw) {
    if (raw is! List) return;
    for (final item in raw) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final index = m['index'] is int
          ? m['index'] as int
          : int.tryParse('${m['index'] ?? 0}') ?? 0;
      final draft = _byIndex.putIfAbsent(index, _ToolCallDraft.new);
      final id = (m['id'] ?? '').toString();
      if (id.isNotEmpty) draft.id = id;
      final fn = m['function'];
      if (fn is Map) {
        final name = (fn['name'] ?? '').toString();
        if (name.isNotEmpty) draft.name = name;
        final args = fn['arguments'];
        if (args != null) draft.arguments.write(args.toString());
      }
    }
  }

  List<_ToolCall> done() {
    final keys = _byIndex.keys.toList()..sort();
    return [
      for (final k in keys)
        _ToolCall(
          id: _byIndex[k]!.id,
          name: _byIndex[k]!.name,
          arguments: _byIndex[k]!.arguments.toString(),
        ),
    ].where((c) => c.name.isNotEmpty).toList();
  }
}

class _ToolCallDraft {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}
