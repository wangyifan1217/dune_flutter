// C1 云枢会话列表预览，对齐 WebView `assistantPreview` / `novaConvPreviewText`。
import 'dart:convert';

import 'nova_web_storage.dart';

const kNovaWelcomeIntro = '你好，我是你的云枢助手';

bool isNovaWelcomePreview(String text) {
  final s = text.trim();
  if (s.isEmpty) return true;
  if (s.startsWith(kNovaWelcomeIntro)) return true;
  if (s.contains('沙丘助手')) return true;
  return false;
}

String stripMarkdownPreview(String text) {
  var s = text;
  s = s.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
  s = s.replaceAll(RegExp(r'\*([^*]+)\*'), r'$1');
  s = s.replaceAll(RegExp(r'^#+\s*', multiLine: true), '');
  s = s.replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return s;
}

String novaAssistantInboxPreview(String rawPreview) {
  var s = stripMarkdownPreview(rawPreview);
  if (s.isEmpty || isNovaWelcomePreview(s)) return kNovaWelcomeIntro;
  if (s.length > 48) s = '${s.substring(0, 48)}…';
  return s;
}

String novaInboxPreviewOrIntro(String? preview) {
  final text = (preview ?? '').trim();
  if (text.isEmpty) return kNovaWelcomeIntro;
  return novaAssistantInboxPreview(text);
}

/// 对齐 WebView `resolveNovaConvIdForEnter`：仅读 `dunes_nova_conv_id`，不用 C1 列表 AI 行 id。
int novaActiveConvIdFromStorage(Map<String, String> storage, {int fallback = 0}) {
  final saved = int.tryParse(storage['dunes_nova_conv_id'] ?? '') ?? 0;
  if (saved > 0) return saved;
  return fallback > 0 ? fallback : 0;
}

String _novaSessionAssistantPreview(Map<String, String> storage, int convId) {
  final raw = storage['dunes_nova_msgs_$convId'];
  if (raw == null || raw.isEmpty) return '';
  try {
    final items = jsonDecode(raw);
    if (items is! List) return '';
    for (var i = items.length - 1; i >= 0; i--) {
      final m = items[i];
      if (m is! Map) continue;
      final role = (m['role'] ?? '').toString().toLowerCase();
      final kind = (m['kind'] ?? '').toString().toUpperCase();
      if (role == 'assistant' || kind.contains('AI')) {
        return (m['bodyText'] ?? m['content'] ?? '').toString().trim();
      }
    }
  } catch (_) {}
  return '';
}

String _novaLocalTurnPreview(Map<String, String> storage, int convId) {
  try {
    final raw = storage['dunes_nova_local_history'];
    if (raw == null || raw.isEmpty) return '';
    final local = jsonDecode(raw);
    if (local is! List) return '';
    for (final item in local) {
      if (item is! Map) continue;
      if ((item['conversationId'] as num?)?.toInt() != convId) continue;
      return (item['lastMessagePreview'] ?? '').toString().trim();
    }
  } catch (_) {}
  return '';
}

/// 对齐 WebView `novaConvPreviewText`：优先本地会话里最新 assistant 正文。
String novaConvPreviewTextFromStorage(
  Map<String, String> storage, {
  required int convId,
  required String serverPreview,
  bool allowLocalCache = true,
}) {
  final server = serverPreview.trim();
  final serverUsable = server.isNotEmpty && !isNovaWelcomePreview(server);
  if (!allowLocalCache && serverUsable) return server;
  final originalId = convId;
  var cid = originalId;
  if (originalId > 0) {
    final active = novaActiveConvIdFromStorage(storage, fallback: originalId);
    if (active > 0) cid = active;
  } else {
    cid = novaActiveConvIdFromStorage(storage);
  }

  if (cid > 0) {
    final session = _novaSessionAssistantPreview(storage, cid);
    if (session.isNotEmpty && !isNovaWelcomePreview(session)) return session;
    final localTurn = _novaLocalTurnPreview(storage, cid);
    if (localTurn.isNotEmpty && !isNovaWelcomePreview(localTurn)) return localTurn;
    if (cid > 0 && originalId > 0 && cid != originalId) return '';
  }

  if (serverUsable) return server;
  return '';
}

String resolveNovaInboxPreview({
  Map<String, String> storage = const {},
  int convId = 0,
  String? serverPreview,
  bool generating = false,
  String generatingStatus = '',
  bool allowLocalCache = true,
}) {
  if (generating) {
    final status = generatingStatus.trim();
    return status.isNotEmpty ? status : '正在生成…';
  }
  final text = novaConvPreviewTextFromStorage(
    storage,
    convId: convId,
    serverPreview: (serverPreview ?? '').trim(),
    allowLocalCache: allowLocalCache,
  );
  return novaInboxPreviewOrIntro(text.isEmpty ? null : text);
}

Future<Map<String, String>> persistNovaSessionMessages({
  required int userId,
  required int conversationId,
  required List<Map<String, dynamic>> messages,
}) {
  if (userId <= 0 || conversationId <= 0 || messages.isEmpty) {
    return NovaWebStorage.load(userId);
  }
  return NovaWebStorage.merge(userId, <String, dynamic>{
    'dunes_nova_conv_id': conversationId.toString(),
    'dunes_nova_msgs_$conversationId': jsonEncode(messages),
  });
}
