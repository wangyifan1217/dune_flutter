import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';

class NativeNotificationItem {
  const NativeNotificationItem({
    required this.title,
    required this.body,
    required this.kind,
    required this.createdAt,
  });

  final String title;
  final String body;
  final String kind;
  final DateTime? createdAt;
}

class NativeNotificationSummary {
  const NativeNotificationSummary({
    required this.unreadCount,
    this.latest,
  });

  final int unreadCount;
  final NativeNotificationItem? latest;
}

class NotificationService {
  NotificationService({
    required AuthSession session,
    http.Client? client,
  }) : _session = session,
       _client = client ?? http.Client();

  final AuthSession _session;
  final http.Client _client;

  Future<NativeNotificationSummary> fetchSummary() async {
    final resp = await _client.get(
      Uri.parse('${_session.apiBase}/notifications'),
      headers: <String, String>{
        'Authorization': 'Bearer ${_session.token}',
        'Content-Type': 'application/json',
      },
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('通知加载失败: HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) {
      return const NativeNotificationSummary(unreadCount: 0);
    }
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '通知加载失败').toString());
    }
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      return const NativeNotificationSummary(unreadCount: 0);
    }
    final unread = (data['unreadCount'] as num?)?.toInt() ?? 0;
    final items = data['items'];
    NativeNotificationItem? latest;
    if (items is List && items.isNotEmpty) {
      final first = items.first;
      if (first is Map<String, dynamic>) {
        latest = NativeNotificationItem(
          title: (first['title'] ?? '').toString(),
          body: (first['body'] ?? first['content'] ?? '').toString(),
          kind: (first['kind'] ?? first['category'] ?? '').toString(),
          createdAt: DateTime.tryParse((first['createdAt'] ?? '').toString()),
        );
      }
    }
    return NativeNotificationSummary(unreadCount: unread, latest: latest);
  }

  Future<List<NativeNotificationItem>> fetchAll() async {
    final resp = await _client.get(
      Uri.parse('${_session.apiBase}/notifications'),
      headers: <String, String>{
        'Authorization': 'Bearer ${_session.token}',
        'Content-Type': 'application/json',
      },
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('通知加载失败: HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    if (body is! Map<String, dynamic>) return const <NativeNotificationItem>[];
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '通知加载失败').toString());
    }
    final data = body['data'];
    final items = data is Map<String, dynamic> ? data['items'] : null;
    if (items is! List) return const <NativeNotificationItem>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map(
          (first) => NativeNotificationItem(
            title: (first['title'] ?? '').toString(),
            body: (first['body'] ?? first['content'] ?? '').toString(),
            kind: (first['kind'] ?? first['category'] ?? '').toString(),
            createdAt: DateTime.tryParse((first['createdAt'] ?? '').toString()),
          ),
        )
        .toList(growable: false);
  }

  Future<void> markAllRead() async {
    final resp = await _client.post(
      Uri.parse('${_session.apiBase}/notifications/read-all'),
      headers: <String, String>{
        'Authorization': 'Bearer ${_session.token}',
        'Content-Type': 'application/json',
      },
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('标记已读失败: HTTP ${resp.statusCode}');
    }
  }
}
