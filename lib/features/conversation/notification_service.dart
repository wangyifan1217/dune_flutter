import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';

class NativeNotificationItem {
  const NativeNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.createdAt,
    this.clickAction,
    this.unread = false,
  });

  final int id;
  final String title;
  final String body;
  final String kind;
  final DateTime? createdAt;
  final String? clickAction;
  final bool unread;

  bool get isAiSummary => kind.toUpperCase() == 'AI_SUMMARY';
}

class NativeNotificationSummary {
  const NativeNotificationSummary({
    required this.unreadCount,
    this.latest,
    this.aiSummaryUnreadCount = 0,
  });

  final int unreadCount;
  final NativeNotificationItem? latest;
  final int aiSummaryUnreadCount;
}

class NotificationService {
  NotificationService({
    required AuthSession session,
    http.Client? client,
  }) : _session = session,
       _client = client ?? http.Client();

  final AuthSession _session;
  final http.Client _client;
  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    _client.close();
  }

  Future<NativeNotificationSummary> fetchSummary() async {
    final items = await fetchAll();
    final unread = items.where((e) => e.unread).length;
    final aiUnread = items.where((e) => e.unread && e.isAiSummary).length;
    return NativeNotificationSummary(
      unreadCount: unread,
      latest: items.isEmpty ? null : items.first,
      aiSummaryUnreadCount: aiUnread,
    );
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
    String text;
    try {
      text = utf8.decode(resp.bodyBytes, allowMalformed: true);
    } catch (_) {
      text = resp.body;
    }
    Object decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      debugPrint('[NotificationService] json decode failed: $e');
      throw Exception('通知加载失败，请稍后重试');
    }
    final body = decoded;
    if (body is! Map<String, dynamic>) return const <NativeNotificationItem>[];
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '通知加载失败').toString());
    }
    final data = body['data'];
    final items = data is Map<String, dynamic> ? data['items'] : null;
    if (items is! List) return const <NativeNotificationItem>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map(_mapItem)
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

  Future<void> markRead(int id) async {
    if (id <= 0) return;
    final resp = await _client.post(
      Uri.parse('${_session.apiBase}/notifications/$id/read'),
      headers: <String, String>{
        'Authorization': 'Bearer ${_session.token}',
        'Content-Type': 'application/json',
      },
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('标记已读失败: HTTP ${resp.statusCode}');
    }
  }

  /// 将未读的智能总结通知标为已读（打开智能总结时调用，对齐 IM 进会话消未读）。
  Future<int> markAiSummaryNotificationsRead() async {
    final items = await fetchAll();
    final unread = items.where((e) => e.unread && e.isAiSummary).toList();
    for (final item in unread) {
      try {
        await markRead(item.id);
      } catch (_) {}
    }
    return unread.length;
  }

  NativeNotificationItem _mapItem(Map<String, dynamic> first) {
    final readAt = first['readAt'];
    final unreadFlag = first['unread'];
    final unread = unreadFlag is bool
        ? unreadFlag
        : readAt == null || readAt.toString().trim().isEmpty;
    return NativeNotificationItem(
      id: (first['id'] as num?)?.toInt() ?? 0,
      title: (first['title'] ?? '').toString(),
      body: (first['body'] ?? first['content'] ?? '').toString(),
      kind: (first['kind'] ?? first['category'] ?? '').toString(),
      clickAction: first['clickAction']?.toString(),
      createdAt: DateTime.tryParse((first['createdAt'] ?? '').toString()),
      unread: unread,
    );
  }
}
