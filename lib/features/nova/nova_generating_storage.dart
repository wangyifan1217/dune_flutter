import 'dart:convert';

import 'nova_web_storage.dart';

const kNovaGeneratingTtlMs = 15 * 60 * 1000;

String novaGeneratingStorageKey(int convId) => 'dunes_nova_generating_$convId';

String novaStreamDraftStorageKey(int convId) => 'dunes_nova_stream_draft_$convId';

class NovaGeneratingState {
  const NovaGeneratingState({
    required this.at,
    required this.status,
    required this.afterMessageId,
    required this.conversationId,
  });

  final int at;
  final String status;
  final int afterMessageId;
  final int conversationId;

  bool get expired => DateTime.now().millisecondsSinceEpoch - at > kNovaGeneratingTtlMs;

  factory NovaGeneratingState.fromJson(Map<String, dynamic> json, {required int convId}) {
    return NovaGeneratingState(
      at: (json['at'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? '正在生成…').toString(),
      afterMessageId: (json['after'] as num?)?.toInt() ?? 0,
      conversationId: convId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'at': at,
        'status': status,
        'after': afterMessageId,
      };
}

class NovaStreamDraft {
  const NovaStreamDraft({
    required this.at,
    required this.status,
    required this.afterMessageId,
    required this.userText,
    required this.thinkText,
    required this.text,
    required this.streaming,
  });

  final int at;
  final String status;
  final int afterMessageId;
  final String userText;
  final String thinkText;
  final String text;
  final bool streaming;

  bool get expired => DateTime.now().millisecondsSinceEpoch - at > kNovaGeneratingTtlMs;

  factory NovaStreamDraft.fromJson(Map<String, dynamic> json) {
    return NovaStreamDraft(
      at: (json['at'] as num?)?.toInt() ?? 0,
      status: (json['status'] ?? '正在生成…').toString(),
      afterMessageId: (json['after'] as num?)?.toInt() ?? 0,
      userText: (json['userText'] ?? '').toString(),
      thinkText: (json['thinkStream'] ?? json['thinkText'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      streaming: json['streaming'] != false,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'at': at,
        'status': status,
        'after': afterMessageId,
        'userText': userText,
        'thinkStream': thinkText,
        'text': text,
        'streaming': streaming,
      };
}

NovaGeneratingState? readNovaGeneratingFromStorage(
  Map<String, String> storage, {
  int convId = 0,
  int activeConvId = 0,
}) {
  final ids = <int>{};
  if (convId > 0) ids.add(convId);
  if (activeConvId > 0) ids.add(activeConvId);
  final active = int.tryParse(storage['dunes_nova_conv_id'] ?? '') ?? 0;
  if (active > 0) ids.add(active);

  for (final id in ids) {
    final raw = storage[novaGeneratingStorageKey(id)];
    if (raw == null || raw.isEmpty) continue;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) continue;
      final state = NovaGeneratingState.fromJson(Map<String, dynamic>.from(json), convId: id);
      if (state.expired) continue;
      return state;
    } catch (_) {}
  }
  return null;
}

bool isNovaStoppedGeneratingStatus(String status) => status.trim().contains('停止');

bool novaStreamDraftHasContent(NovaStreamDraft? draft) {
  if (draft == null || draft.expired) return false;
  return draft.text.trim().isNotEmpty || draft.thinkText.trim().isNotEmpty;
}

/// 对齐 WebView `applyNovaGeneratingState`：无活跃流时，仅「已有正文草稿」才算 generating。
bool shouldPersistNovaGenerating({
  NovaGeneratingState? localGen,
  NovaStreamDraft? draft,
  bool streamInFlight = false,
  bool hasAiReplyAfter = false,
}) {
  if (streamInFlight) return true;
  if (hasAiReplyAfter) return false;
  if (draft == null || draft.expired) {
    if (localGen == null) return false;
    if (localGen.expired) return false;
    if (isNovaStoppedGeneratingStatus(localGen.status)) return false;
    return false;
  }
  final hasDraftContent =
      draft.text.trim().isNotEmpty || draft.userText.trim().isNotEmpty;
  if (!hasDraftContent) {
    if (localGen == null) return false;
    if (localGen.expired) return false;
    if (isNovaStoppedGeneratingStatus(localGen.status)) return false;
    return false;
  }
  // SSE 中断后 generating 标记可能被清掉，但草稿仍在：仍需恢复/轮询。
  if (localGen == null) return draft.text.trim().isNotEmpty;
  if (localGen.expired) return draft.text.trim().isNotEmpty;
  if (isNovaStoppedGeneratingStatus(localGen.status)) return false;
  return true;
}

NovaStreamDraft? readNovaStreamDraftFromStorage(Map<String, String> storage, int convId) {
  if (convId <= 0) return null;
  final raw = storage[novaStreamDraftStorageKey(convId)];
  if (raw == null || raw.isEmpty) return null;
  try {
    final json = jsonDecode(raw);
    if (json is! Map) return null;
    final draft = NovaStreamDraft.fromJson(Map<String, dynamic>.from(json));
    if (draft.expired) return null;
    return draft;
  } catch (_) {
    return null;
  }
}

Future<void> persistNovaGeneratingState({
  required int userId,
  required int conversationId,
  required String status,
  int afterMessageId = 0,
}) async {
  if (userId <= 0 || conversationId <= 0) return;
  final payload = NovaGeneratingState(
    at: DateTime.now().millisecondsSinceEpoch,
    status: status.isNotEmpty ? status : '正在生成…',
    afterMessageId: afterMessageId,
    conversationId: conversationId,
  );
  await NovaWebStorage.merge(userId, <String, dynamic>{
    novaGeneratingStorageKey(conversationId): jsonEncode(payload.toJson()),
    'dunes_nova_conv_id': conversationId.toString(),
  });
}

Future<void> clearNovaGeneratingState({
  required int userId,
  required int conversationId,
}) async {
  if (userId <= 0 || conversationId <= 0) return;
  final existing = await NovaWebStorage.load(userId);
  final merged = Map<String, String>.from(existing);
  merged.remove(novaGeneratingStorageKey(conversationId));
  await NovaWebStorage.save(userId, Map<String, dynamic>.from(merged));
}

Future<void> clearNovaStreamDraftState({
  required int userId,
  required int conversationId,
}) async {
  if (userId <= 0 || conversationId <= 0) return;
  final existing = await NovaWebStorage.load(userId);
  final merged = Map<String, String>.from(existing);
  merged.remove(novaStreamDraftStorageKey(conversationId));
  await NovaWebStorage.save(userId, Map<String, dynamic>.from(merged));
}

Future<void> persistNovaStreamDraftState({
  required int userId,
  required int conversationId,
  required String status,
  int afterMessageId = 0,
  String userText = '',
  String thinkText = '',
  String text = '',
  bool streaming = true,
}) async {
  if (userId <= 0 || conversationId <= 0) return;
  final draft = NovaStreamDraft(
    at: DateTime.now().millisecondsSinceEpoch,
    status: status.isNotEmpty ? status : '正在生成…',
    afterMessageId: afterMessageId,
    userText: userText,
    thinkText: thinkText,
    text: text,
    streaming: streaming,
  );
  await NovaWebStorage.merge(userId, <String, dynamic>{
    novaStreamDraftStorageKey(conversationId): jsonEncode(draft.toJson()),
  });
}
