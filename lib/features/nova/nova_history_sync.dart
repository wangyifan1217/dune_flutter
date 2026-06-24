import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import 'native_nova_service.dart';
import 'nova_stream_parser.dart';
import 'nova_web_storage.dart';

const _queueKey = 'dunes_nova_history_sync_queue';

/// 对齐 WebView `registerNovaHistoryTurn` / `flushNovaHistorySyncQueue` /
/// `syncNovaLocalTurnPreview` / `flushNovaConvToLocalHistory`。
class NovaHistorySync {
  NovaHistorySync({
    required this.session,
    required this.client,
    required this.selectedModel,
    required this.novaBizUserId,
    required this.novaProfileSessionId,
    required this.displayName,
  });

  final AuthSession session;
  final http.Client client;
  final String selectedModel;
  final String novaBizUserId;
  final String novaProfileSessionId;
  final String displayName;

  String _lastServerSyncSig = '';

  Uri get _turnsUri => Uri.parse('${session.apiBase}/ai/history/turns');

  Map<String, String> get _headers => <String, String>{
        'Authorization': 'Bearer ${session.token}',
        'Content-Type': 'application/json',
      };

  static String turnTitleFromUser(String userLabel, {Map<String, dynamic>? payload}) {
    var label = userLabel.trim();
    if (label.isNotEmpty && label != '[图片]' && label != '[文件]' && label != '[消息]') {
      return label.length > 24 ? label.substring(0, 24) : label;
    }
    final attachments = payload?['attachments'];
    if (attachments is List && attachments.isNotEmpty) {
      return attachments.length > 1 ? '图文对话' : '图片对话';
    }
    if (label.isNotEmpty) return label.length > 24 ? label.substring(0, 24) : label;
    return '对话';
  }

  Map<String, dynamic> buildTurnPayload({
    required int conversationId,
    required int messageId,
    required String title,
    required String userMessage,
    required String assistantMessage,
    String? lastMessagePreview,
    String? lastMessageAt,
    String? model,
  }) {
    final assistant = stripHermesProgressLines(assistantMessage.trim());
    final user = userMessage.trim();
    var preview = (lastMessagePreview ?? '').trim();
    if (preview.isEmpty) {
      preview = assistant.length > 200 ? assistant.substring(0, 200) : assistant;
    }
    if (preview.isEmpty) {
      preview = user.length > 200 ? user.substring(0, 200) : user;
    }
    return <String, dynamic>{
      'conversationId': conversationId,
      'messageId': messageId,
      'title': title.length > 64 ? title.substring(0, 64) : title,
      'lastMessagePreview': preview.length > 200 ? preview.substring(0, 200) : preview,
      'lastMessageAt': lastMessageAt ?? DateTime.now().toUtc().toIso8601String(),
      'source': 'app',
      'userId': session.userId,
      'userDisplayName': displayName,
      'bizUserId': novaBizUserId,
      'novaSessionId': novaProfileSessionId,
      'model': (model ?? selectedModel).trim(),
      'userMessage': user.length > 8000 ? user.substring(0, 8000) : user,
      'assistantMessage': assistant.length > 32000 ? assistant.substring(0, 32000) : assistant,
    };
  }

  String _payloadSig(Map<String, dynamic> payload) => [
        payload['conversationId'],
        payload['messageId'],
        payload['userMessage'],
        payload['assistantMessage'],
      ].join('\x1e');

  Future<void> upsertLocalTurn(Map<String, dynamic> turn) async {
    if (session.userId <= 0) return;
    final convId = (turn['conversationId'] as num?)?.toInt() ?? 0;
    if (convId <= 0) return;
    final storage = await NovaWebStorage.load(session.userId);
    final list = <Map<String, dynamic>>[];
    final raw = storage['dunes_nova_local_history'];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) list.add(Map<String, dynamic>.from(item));
          }
        }
      } catch (_) {}
    }
    var found = false;
    for (var i = 0; i < list.length; i++) {
      if ((list[i]['conversationId'] as num?)?.toInt() == convId) {
        list[i] = {...list[i], ...turn, 'conversationId': convId};
        found = true;
        break;
      }
    }
    if (!found) list.insert(0, turn);
    if (list.length > 40) list.removeRange(40, list.length);
    await NovaWebStorage.merge(session.userId, {
      'dunes_nova_local_history': jsonEncode(list),
    });
  }

  Future<void> enqueueSync(Map<String, dynamic> payload) async {
    if (session.userId <= 0) return;
    final storage = await NovaWebStorage.load(session.userId);
    final list = <Map<String, dynamic>>[];
    final raw = storage[_queueKey];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) list.add(Map<String, dynamic>.from(item));
          }
        }
      } catch (_) {}
    }
    list.add(<String, dynamic>{
      'payload': payload,
      'at': DateTime.now().millisecondsSinceEpoch,
      'tries': 0,
    });
    if (list.length > 50) list.removeRange(0, list.length - 50);
    await NovaWebStorage.merge(session.userId, {_queueKey: jsonEncode(list)});
  }

  Future<void> dequeueSync(Map<String, dynamic> payload) async {
    if (session.userId <= 0) return;
    final sig = _payloadSig(payload);
    final storage = await NovaWebStorage.load(session.userId);
    final raw = storage[_queueKey];
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final remain = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final p = item['payload'];
        if (p is! Map) {
          remain.add(Map<String, dynamic>.from(item));
          continue;
        }
        final itemSig = _payloadSig(Map<String, dynamic>.from(p));
        if (itemSig != sig) remain.add(Map<String, dynamic>.from(item));
      }
      await NovaWebStorage.merge(session.userId, {_queueKey: jsonEncode(remain)});
    } catch (_) {}
  }

  /// 对齐 WebView `registerNovaHistoryTurn`。
  Future<void> registerHistoryTurn({
    required int conversationId,
    required int messageId,
    required String userMessage,
    required String assistantMessage,
    String? title,
    String? lastMessagePreview,
    String? lastMessageAt,
    String? model,
    Map<String, dynamic>? userPayload,
  }) async {
    if (conversationId <= 0 || session.userId <= 0) return;
    final reply = stripHermesProgressLines(assistantMessage.trim());
    if (reply.isEmpty) return;
    final effectiveMessageId = messageId > 0 ? messageId : DateTime.now().millisecondsSinceEpoch;

    final resolvedTitle = title ?? turnTitleFromUser(userMessage, payload: userPayload);
    final payload = buildTurnPayload(
      conversationId: conversationId,
      messageId: effectiveMessageId,
      title: resolvedTitle,
      userMessage: userMessage,
      assistantMessage: reply,
      lastMessagePreview: lastMessagePreview ?? reply,
      lastMessageAt: lastMessageAt,
      model: model,
    );
    final sig = _payloadSig(payload);
    if (sig == _lastServerSyncSig) return;
    _lastServerSyncSig = sig;

    await upsertLocalTurn(<String, dynamic>{
      'conversationId': conversationId,
      'title': payload['title'],
      'lastMessagePreview': payload['lastMessagePreview'],
      'lastMessageAt': payload['lastMessageAt'],
      'messageId': effectiveMessageId,
      'source': 'app',
    });

    try {
      final resp = await client.post(
        _turnsUri,
        headers: _headers,
        body: jsonEncode(payload),
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        await dequeueSync(payload);
        if (kDebugMode) {
          debugPrint(
            '[NovaHistorySync] register ok '
            'conv=${payload['conversationId']} msg=${payload['messageId']}',
          );
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            '[NovaHistorySync] register failed '
            'status=${resp.statusCode} conv=${payload['conversationId']} '
            'msg=${payload['messageId']} body=${resp.body}',
          );
        }
        await enqueueSync(payload);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[NovaHistorySync] register exception '
          'conv=${payload['conversationId']} msg=${payload['messageId']} err=$e',
        );
      }
      await enqueueSync(payload);
    }
  }

  /// 对齐 WebView `flushNovaHistorySyncQueue`（进入 C4 时重试）。
  Future<void> flushSyncQueue() async {
    if (session.userId <= 0) return;
    final storage = await NovaWebStorage.load(session.userId);
    final raw = storage[_queueKey];
    if (raw == null || raw.isEmpty) return;
    List<dynamic> queue;
    try {
      queue = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return;
    }
    if (queue.isEmpty) return;

    final remain = <Map<String, dynamic>>[];
    for (final item in queue) {
      if (item is! Map) continue;
      final payloadRaw = item['payload'];
      if (payloadRaw is! Map) continue;
      final payload = Map<String, dynamic>.from(payloadRaw);
      try {
        final resp = await client.post(
          _turnsUri,
          headers: _headers,
          body: jsonEncode(payload),
        );
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          continue;
        }
      } catch (_) {}
      final tries = (item['tries'] as num?)?.toInt() ?? 0;
      if (tries < 5) {
        remain.add(<String, dynamic>{
          'payload': payload,
          'at': item['at'] ?? DateTime.now().millisecondsSinceEpoch,
          'tries': tries + 1,
        });
      }
    }
    await NovaWebStorage.merge(session.userId, {_queueKey: jsonEncode(remain)});
  }

  /// 对齐 WebView `syncNovaLocalTurnPreview`。
  Future<void> syncLocalTurnPreviewFromMessages(
    int conversationId,
    List<NativeNovaMessage> messages,
  ) async {
    if (conversationId <= 0 || session.userId <= 0) return;
    final items = messages.where((m) => !m.isWelcome).toList(growable: false);
    if (items.isEmpty) return;

    var preview = '';
    for (var i = items.length - 1; i >= 0; i--) {
      final m = items[i];
      if (m.role == 'assistant' && m.text.trim().isNotEmpty) {
        preview = m.text.trim();
        break;
      }
    }
    if (preview.isEmpty) {
      for (var i = items.length - 1; i >= 0; i--) {
        if (items[i].role == 'user' && items[i].text.trim().isNotEmpty) {
          preview = items[i].text.trim();
          break;
        }
      }
    }
    if (preview.isEmpty) return;

    var title = '对话';
    for (var i = items.length - 1; i >= 0; i--) {
      if (items[i].role == 'user') {
        title = turnTitleFromUser(items[i].text, payload: items[i].payload);
        break;
      }
    }

    var turnMessageId = 0;
    for (var i = items.length - 1; i >= 0; i--) {
      if (items[i].role == 'user' && items[i].id > 0) {
        turnMessageId = items[i].id;
        break;
      }
    }
    final last = items.last;
    await upsertLocalTurn(<String, dynamic>{
      'conversationId': conversationId,
      'title': title,
      'lastMessagePreview': preview.length > 200 ? preview.substring(0, 200) : preview,
      'lastMessageAt': (last.createdAt ?? DateTime.now()).toUtc().toIso8601String(),
      'messageId': turnMessageId > 0 ? turnMessageId : last.id,
      'source': 'app',
    });
  }

  /// 对齐 WebView `flushNovaConvToLocalHistory`。
  Future<void> flushConvToLocalHistory(
    int conversationId,
    List<NativeNovaMessage> messages,
  ) =>
      syncLocalTurnPreviewFromMessages(conversationId, messages);

  Future<void> persistActiveConversationId(int conversationId) async {
    if (conversationId <= 0 || session.userId <= 0) return;
    await NovaWebStorage.merge(session.userId, {
      'dunes_nova_conv_id': conversationId.toString(),
    });
  }
}
