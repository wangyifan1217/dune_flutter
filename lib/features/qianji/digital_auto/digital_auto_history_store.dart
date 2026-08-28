import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../auth/auth_session.dart';
import 'digital_auto_config.dart';

class DigitalAutoHistorySnapshot {
  const DigitalAutoHistorySnapshot({
    required this.lines,
    required this.messages,
  });

  final List<Map<String, String>> lines;
  final List<Map<String, dynamic>> messages;

  bool get isEmpty => lines.isEmpty;
}

class DigitalAutoHistoryStore {
  DigitalAutoHistoryStore({
    required this.session,
    required this.configuration,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final AuthSession session;
  final DigitalAutoAssistantConfig configuration;
  final http.Client _http;

  Uri get _uri {
    final base = session.apiBase.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base${configuration.historyPath}');
  }

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  Future<DigitalAutoHistorySnapshot?> load() async {
    try {
      final resp = await _http
          .get(_uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode == 404) return null;
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      final decoded = jsonDecode(resp.body);
      final data = decoded is Map && decoded['data'] is Map
          ? decoded['data'] as Map
          : decoded is Map
          ? decoded
          : null;
      if (data == null) return null;
      final lines = <Map<String, String>>[];
      final rawLines = data['lines'];
      if (rawLines is List) {
        for (final item in rawLines) {
          if (item is! Map) continue;
          final role = (item['role'] ?? '').toString();
          final text = (item['text'] ?? '').toString();
          if (role.isEmpty || text.trim().isEmpty) continue;
          lines.add({'role': role, 'text': text});
        }
      }
      final messages = <Map<String, dynamic>>[];
      final rawMessages = data['messages'];
      if (rawMessages is List) {
        for (final item in rawMessages) {
          if (item is Map) {
            messages.add(Map<String, dynamic>.from(item));
          }
        }
      }
      if (lines.isEmpty) return null;
      return DigitalAutoHistorySnapshot(lines: lines, messages: messages);
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required List<Map<String, String>> lines,
    required List<Map<String, dynamic>> messages,
  }) async {
    final kept = [
      for (final line in lines)
        if ((line['text'] ?? '').trim().isNotEmpty) line,
    ];
    try {
      if (kept.isEmpty) {
        await clear();
        return;
      }
      await _http
          .put(
            _uri,
            headers: _headers,
            body: jsonEncode({'lines': kept, 'messages': messages}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {}
  }

  Future<void> clear() async {
    try {
      await _http
          .delete(_uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
    } catch (_) {}
  }
}
