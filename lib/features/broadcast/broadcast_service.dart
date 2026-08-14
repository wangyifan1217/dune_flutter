import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/http/session_http.dart';
import '../auth/auth_session.dart';

class BroadcastChannel {
  const BroadcastChannel({
    required this.id,
    required this.title,
    this.lastMessagePreview = '',
  });

  final int id;
  final String title;
  final String lastMessagePreview;

  factory BroadcastChannel.fromJson(Map<String, dynamic> json) {
    return BroadcastChannel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? '').toString(),
      lastMessagePreview: (json['lastMessagePreview'] ?? '').toString(),
    );
  }
}

class BroadcastHistoryItem {
  const BroadcastHistoryItem({
    required this.id,
    required this.conversationId,
    required this.conversationTitle,
    required this.bodyText,
    required this.senderName,
    this.createdAt,
  });

  final int id;
  final int conversationId;
  final String conversationTitle;
  final String bodyText;
  final String senderName;
  final DateTime? createdAt;

  factory BroadcastHistoryItem.fromJson(Map<String, dynamic> json) {
    return BroadcastHistoryItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      conversationId: (json['conversationId'] as num?)?.toInt() ?? 0,
      conversationTitle: (json['conversationTitle'] ?? '').toString(),
      bodyText: (json['bodyText'] ?? '').toString(),
      senderName: (json['senderName'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
    );
  }
}

class BroadcastService {
  BroadcastService({required this.session, http.Client? client})
    : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }

  dynamic _unwrap(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('公司广播请求失败：HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['success'] == false) {
      throw Exception((decoded['message'] ?? '公司广播请求失败').toString());
    }
    if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
    return decoded;
  }

  Future<bool> canAccess() async {
    final response = await dunesHttpGet(
      session,
      '/admin/broadcasts/access',
      client: _client,
    );
    final data = _unwrap(response);
    return data is Map && data['enabled'] == true;
  }

  Future<List<BroadcastChannel>> listChannels() async {
    final response = await dunesHttpGet(
      session,
      '/admin/broadcasts',
      client: _client,
    );
    final data = _unwrap(response);
    final rows = data is List ? data : const [];
    return rows
        .whereType<Map>()
        .map((row) => BroadcastChannel.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<BroadcastHistoryItem>> listHistory({
    int? conversationId,
    int limit = 50,
  }) async {
    final params = <String, String>{'limit': '$limit'};
    if (conversationId != null && conversationId > 0) {
      params['conversationId'] = '$conversationId';
    }
    final qs = Uri(queryParameters: params).query;
    final response = await dunesHttpGet(
      session,
      '/admin/broadcasts/messages${qs.isEmpty ? '' : '?$qs'}',
      client: _client,
    );
    final data = _unwrap(response);
    final rows = data is List ? data : const [];
    return rows
        .whereType<Map>()
        .map(
          (row) => BroadcastHistoryItem.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  Future<void> send({
    required String bodyText,
    int? conversationId,
    String? title,
  }) async {
    final payload = <String, dynamic>{
      'bodyText': bodyText.trim(),
      if (conversationId != null && conversationId > 0)
        'conversationId': conversationId,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
    };
    final response = await dunesHttpPost(
      session,
      '/admin/broadcasts/messages',
      body: jsonEncode(payload),
      client: _client,
    );
    _unwrap(response);
  }

  Future<void> deleteMessage(int id) async {
    if (id <= 0) return;
    final response = await dunesHttpDelete(
      session,
      '/admin/broadcasts/messages/$id',
      client: _client,
    );
    _unwrap(response);
  }
}
