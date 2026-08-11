import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../../core/config/nova_config.dart';
import '../../core/util/friendly_error.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import 'nova_draft.dart';
import 'nova_file_utils.dart';
import 'nova_generating_storage.dart';
import 'nova_history_sync.dart';
import 'nova_history_utils.dart';
import 'nova_image_utils.dart';
import 'nova_inbox_preview.dart';
import 'nova_model_utils.dart';
import 'nova_stream_parser.dart';
import 'nova_web_storage.dart';

class NovaChatAttachmentUpload {
  const NovaChatAttachmentUpload({
    required this.attachmentId,
    required this.fileName,
    this.chars = 0,
    this.truncated = false,
    this.preview = '',
    this.expiresAt = 0,
  });

  final String attachmentId;
  final String fileName;
  final int chars;
  final bool truncated;
  final String preview;
  final int expiresAt;
}

class NovaMessageAttachment {
  const NovaMessageAttachment({
    required this.url,
    required this.objectKey,
    required this.fileName,
    required this.mimeType,
    required this.kind,
    this.previewBytes,
  });

  final String url;
  final String objectKey;
  final String fileName;
  final String mimeType;
  final String kind;

  /// 发送中本地预览（对齐 WebView 上传前即显示缩略图）。
  final Uint8List? previewBytes;

  NovaMessageAttachment copyWith({
    String? url,
    String? objectKey,
    String? fileName,
    String? mimeType,
    String? kind,
    Uint8List? previewBytes,
  }) {
    return NovaMessageAttachment(
      url: url ?? this.url,
      objectKey: objectKey ?? this.objectKey,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      kind: kind ?? this.kind,
      previewBytes: previewBytes ?? this.previewBytes,
    );
  }

  factory NovaMessageAttachment.fromJson(Map<String, dynamic> json) {
    final url =
        (json['url'] ??
                json['accessUrl'] ??
                json['publicUrl'] ??
                json['previewUrl'] ??
                '')
            .toString();
    var objectKey = (json['objectKey'] ?? '').toString();
    if (objectKey.isEmpty &&
        url.isNotEmpty &&
        !RegExp(r'^https?:', caseSensitive: false).hasMatch(url)) {
      objectKey = url;
    }
    return NovaMessageAttachment(
      url: url,
      objectKey: objectKey,
      fileName: (json['fileName'] ?? 'file').toString(),
      mimeType: (json['mimeType'] ?? 'application/octet-stream').toString(),
      kind: (json['kind'] ?? 'FILE').toString(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'objectKey': objectKey,
    'fileName': fileName,
    'mimeType': mimeType,
    'kind': kind,
    'bucket': 'im-attachments',
  };
}

class NativeNovaMessage {
  const NativeNovaMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.kind = 'TEXT',
    this.isWelcome = false,
    this.attachments = const <NovaMessageAttachment>[],
    this.thinkText = '',
    this.thinkStatus = '',
    this.streaming = false,
    this.durationSec = 0,
    this.payload,
    this.ragUsed = false,
  });

  final int id;
  final String role;
  final String text;
  final DateTime? createdAt;
  final String kind;
  final bool isWelcome;
  final List<NovaMessageAttachment> attachments;
  final String thinkText;
  final String thinkStatus;
  final bool streaming;
  final int durationSec;
  final Map<String, dynamic>? payload;
  final bool ragUsed;

  NativeNovaMessage copyWith({
    int? id,
    String? role,
    String? text,
    DateTime? createdAt,
    String? kind,
    bool? isWelcome,
    List<NovaMessageAttachment>? attachments,
    String? thinkText,
    String? thinkStatus,
    bool? streaming,
    int? durationSec,
    Map<String, dynamic>? payload,
    bool? ragUsed,
  }) {
    return NativeNovaMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      kind: kind ?? this.kind,
      isWelcome: isWelcome ?? this.isWelcome,
      attachments: attachments ?? this.attachments,
      thinkText: thinkText ?? this.thinkText,
      thinkStatus: thinkStatus ?? this.thinkStatus,
      streaming: streaming ?? this.streaming,
      durationSec: durationSec ?? this.durationSec,
      payload: payload ?? this.payload,
      ragUsed: ragUsed ?? this.ragUsed,
    );
  }
}

/// 对齐 WebView `inferAwaitingNovaReply`。
bool inferNovaAwaitingReply(List<NativeNovaMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    if (m.isWelcome) continue;
    return m.role == 'user';
  }
  return false;
}

/// 会话消息按时间排序；同一时刻 user 在 assistant 之前。
List<NativeNovaMessage> sortNovaMessages(List<NativeNovaMessage> items) {
  if (items.length < 2) return items;
  final out = [...items];
  out.sort((a, b) {
    if (a.isWelcome && !b.isWelcome) return -1;
    if (b.isWelcome && !a.isWelcome) return 1;
    final ta = a.createdAt?.millisecondsSinceEpoch ?? a.id;
    final tb = b.createdAt?.millisecondsSinceEpoch ?? b.id;
    if (ta != tb) return ta.compareTo(tb);
    if (a.role != b.role) {
      if (a.role == 'user') return -1;
      if (b.role == 'user') return 1;
    }
    return a.id.compareTo(b.id);
  });
  return out;
}

/// 去掉 AI 回声（assistant 正文与用户提问完全一致），并按问答轮次重排。
/// 解决服务端忽略 createdAt、用户消息晚落库导致 id 大于 AI 回复的问题。
List<NativeNovaMessage> repairNovaConversationMessages(
  List<NativeNovaMessage> raw,
) {
  final welcome = raw.where((m) => m.isWelcome).toList(growable: false);
  var items = raw
      .where(
        (m) =>
            !m.isWelcome &&
            !(m.role == 'assistant' && m.streaming && m.text.trim().isEmpty),
      )
      .toList(growable: false);
  if (items.isEmpty) return welcome;

  final userTexts = items
      .where((m) => m.role == 'user')
      .map((m) => m.text.trim())
      .where((t) => t.isNotEmpty)
      .toSet();

  final nonEchoAssistants = items
      .where((m) => m.role == 'assistant' && m.text.trim().isNotEmpty)
      .where((m) => !userTexts.contains(m.text.trim()))
      .length;

  if (nonEchoAssistants > 0) {
    items = items
        .where((m) {
          if (m.role != 'assistant') return true;
          final t = m.text.trim();
          if (t.isEmpty) return false;
          return !userTexts.contains(t);
        })
        .toList(growable: false);
  }

  final users = items.where((m) => m.role == 'user').toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  final assistants =
      items
          .where((m) => m.role == 'assistant' && m.text.trim().isNotEmpty)
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));

  if (users.isEmpty) {
    return sortNovaMessages([...welcome, ...items]);
  }

  final buckets = <int, List<NativeNovaMessage>>{
    for (final u in users) u.id: <NativeNovaMessage>[],
  };
  final usedAssistantIds = <int>{};

  for (final a in assistants) {
    NativeNovaMessage? owner;
    for (final u in users) {
      if (u.id <= a.id) owner = u;
    }
    owner ??= users.first;
    buckets[owner.id]!.add(a);
    usedAssistantIds.add(a.id);
  }

  // 用单调递增时间戳保证 U1→A1→U2→A2… 不会因同秒/同毫秒塌缩成
  // U1,U2,U3,A1,A2,A3（重新发送后 repair 全量重排时尤其容易触发）。
  final out = <NativeNovaMessage>[];
  DateTime? cursor;
  for (final u in users) {
    var userAt =
        u.createdAt ??
        (u.id > 0 ? DateTime.fromMillisecondsSinceEpoch(u.id) : DateTime.now());
    if (cursor != null && !userAt.isAfter(cursor)) {
      userAt = cursor.add(const Duration(milliseconds: 1));
    }
    out.add(u.copyWith(createdAt: userAt));
    cursor = userAt;
    final turnAssistants = buckets[u.id] ?? const <NativeNovaMessage>[];
    for (final a in turnAssistants) {
      var aiAt = a.createdAt;
      if (aiAt == null || !aiAt.isAfter(cursor!)) {
        aiAt = cursor!.add(const Duration(milliseconds: 1));
      }
      out.add(a.copyWith(createdAt: aiAt));
      cursor = aiAt;
    }
  }

  return sortNovaMessages([...welcome, ...out]);
}

int novaHistoryRichness(NativeNovaMessage m) {
  var score = 0;
  if (m.streaming) score += 20;
  if (m.thinkText.trim().isNotEmpty) score += 15;
  if (m.thinkStatus.isNotEmpty) score += 3;
  if (m.attachments.isNotEmpty) score += 10;
  final k = m.kind.toUpperCase();
  if (k == 'IMAGE' || k == 'FILE' || k == 'AUDIO') score += 8;
  if (m.payload != null && m.payload!.isNotEmpty) score += 5;
  if (m.text.trim().isNotEmpty) score += 1;
  return score;
}

bool isEchoAssistantOfUserMessage(
  List<NativeNovaMessage> prior,
  NativeNovaMessage candidate,
) {
  if (candidate.role != 'assistant') return false;
  final reply = candidate.text.trim();
  if (reply.isEmpty) return false;
  for (final m in prior) {
    if (m.role != 'user') continue;
    final user = m.text.trim();
    if (user.isEmpty || user != reply) continue;
    final ta = m.createdAt;
    final tb = candidate.createdAt;
    if (ta == null || tb == null) return true;
    if (ta.difference(tb).inMinutes.abs() <= 5) return true;
  }
  return false;
}

/// 短展示文案 vs 长模型指令：退出再进时常被当成两条用户消息。
bool isNovaPrdDisplayAndPromptPair(String a, String b) {
  final at = a.trim();
  final bt = b.trim();
  if (at.isEmpty || bt.isEmpty || at == bt) return false;
  bool looksPrd(String t) =>
      t.contains('PRD') && (t.contains('知识库') || t.contains('文档'));
  if (!looksPrd(at) || !looksPrd(bt)) return false;
  if (at.contains(bt) || bt.contains(at)) return true;
  final re = RegExp(r'「([^」]+)」');
  final am = re.firstMatch(at);
  final bm = re.firstMatch(bt);
  return am != null && bm != null && am.group(1) == bm.group(1);
}

NativeNovaMessage preferNovaPrdUserBubble(
  NativeNovaMessage a,
  NativeNovaMessage b,
) {
  final short = a.text.trim().length <= b.text.trim().length ? a : b;
  bool tempId(int id) => id >= 1000000000000;
  final keepId = (!tempId(a.id) && tempId(b.id))
      ? a
      : ((!tempId(b.id) && tempId(a.id)) ? b : short);
  return keepId.copyWith(
    text: short.text,
    createdAt: keepId.createdAt ?? short.createdAt,
    streaming: keepId.streaming || short.streaming,
    thinkStatus: keepId.thinkStatus.isNotEmpty
        ? keepId.thinkStatus
        : short.thinkStatus,
  );
}

bool isDuplicateNovaHistoryMessage(NativeNovaMessage a, NativeNovaMessage b) {
  if (a.id > 0 && b.id > 0 && a.id == b.id) return true;
  if (a.role != b.role) return false;
  final ta = a.createdAt;
  final tb = b.createdAt;
  if (ta != null && tb != null && ta.difference(tb).inMinutes.abs() > 5) {
    return false;
  }
  final at = a.text.trim();
  final bt = b.text.trim();
  final secondsApart = (ta != null && tb != null)
      ? ta.difference(tb).inSeconds.abs()
      : 999;

  // PRD：本地短展示 + IM 长指令，退出再进必须合并。
  if (a.role == 'user' &&
      secondsApart <= 180 &&
      isNovaPrdDisplayAndPromptPair(at, bt)) {
    return true;
  }

  // 不同 id：短窗口内同文案=本地/服务端镜像（退出再进会翻倍）；
  // 间隔更长则视为另一轮提问，保留。
  // 用户消息除外：连续发/重发相同文案（如「测试」）是合法多轮，绝不能按文案合并。
  if (a.id > 0 && b.id > 0 && a.id != b.id) {
    if (a.role == 'user') {
      // 仅附件占位与正文镜像可合并；纯文本同文案一律保留为独立轮次。
      if (((a.attachments.isNotEmpty) != (b.attachments.isNotEmpty)) &&
          secondsApart < 90) {
        if (at == bt ||
            at.isEmpty ||
            bt.isEmpty ||
            at == '[图片]' ||
            bt == '[图片]' ||
            at == '[附件消息]' ||
            bt == '[附件消息]' ||
            at == '[文件]' ||
            bt == '[文件]') {
          return true;
        }
      }
      return false;
    }
    if (at.isNotEmpty && bt.isNotEmpty && secondsApart <= 12) {
      if (at == bt) return true;
      if (a.role == 'assistant' &&
          at.length > 40 &&
          bt.length > 40 &&
          at.substring(0, 40) == bt.substring(0, 40)) {
        return true;
      }
    }
    return false;
  }

  if (at.isNotEmpty && bt.isNotEmpty) {
    // 无稳定 id 时也只用短窗口；用户同文案仍保留（避免「测试」连发被吞）。
    if (a.role != 'user' && at == bt && secondsApart <= 12) return true;
    if (a.role == 'assistant' &&
        secondsApart <= 12 &&
        at.length > 40 &&
        bt.length > 40 &&
        at.substring(0, 40) == bt.substring(0, 40)) {
      return true;
    }
  }
  if (a.role == 'user' &&
      secondsApart < 90 &&
      ((a.attachments.isNotEmpty) != (b.attachments.isNotEmpty))) {
    return true;
  }
  return false;
}

/// 去掉同一条消息里重复渲染的附件（解析时 raw + payload 双读、历史重建等会导致翻倍）。
List<NovaMessageAttachment> dedupeNovaMessageAttachments(
  List<NovaMessageAttachment> items,
) {
  if (items.length <= 1) return items;
  final out = <NovaMessageAttachment>[];
  final seen = <String>{};
  for (final a in items) {
    final key = [
      a.kind.toUpperCase(),
      a.objectKey.trim().isNotEmpty ? a.objectKey.trim() : a.url.trim(),
      a.fileName.trim().toLowerCase(),
      a.mimeType.trim().toLowerCase(),
    ].join('\u0001');
    if (!seen.add(key)) continue;
    out.add(a);
  }
  return out;
}

List<NativeNovaMessage> dedupeNovaHistoryMessages(
  List<NativeNovaMessage> items,
) {
  if (items.isEmpty) return items;
  final sorted = [...items]
    ..sort((a, b) {
      final ta = a.createdAt?.millisecondsSinceEpoch ?? a.id;
      final tb = b.createdAt?.millisecondsSinceEpoch ?? b.id;
      return ta.compareTo(tb);
    });
  final out = <NativeNovaMessage>[];
  for (final m in sorted) {
    final dup = out.indexWhere((e) => isDuplicateNovaHistoryMessage(e, m));
    if (dup >= 0) {
      if (isNovaPrdDisplayAndPromptPair(out[dup].text, m.text)) {
        out[dup] = preferNovaPrdUserBubble(out[dup], m);
      } else if (novaHistoryRichness(m) > novaHistoryRichness(out[dup])) {
        out[dup] = m;
      }
    } else if (isEchoAssistantOfUserMessage(out, m)) {
      continue;
    } else {
      out.add(m);
    }
  }
  return out;
}

/// draft 合并时：服务端已落库的用户消息 id 可能与本地 afterMessageId 不一致。
bool novaHasMatchingUserMessage(
  List<NativeNovaMessage> rows, {
  required int afterMessageId,
  required String userText,
}) {
  if (afterMessageId > 0 && rows.any((m) => m.id == afterMessageId)) {
    return true;
  }
  final text = userText.trim();
  if (text.isEmpty) return false;
  final draftAt = DateTime.fromMillisecondsSinceEpoch(afterMessageId);
  return rows.any((m) {
    if (m.role != 'user') return false;
    final mt = m.text.trim();
    if (mt != text && !isNovaPrdDisplayAndPromptPair(mt, text)) return false;
    final at = m.createdAt;
    if (at == null) return true;
    return at.difference(draftAt).inSeconds.abs() <= 180;
  });
}

/// kb-go `messages/local` 曾忽略 role、一律落库为 assistant，导致历史回放时
/// 用户消息被当成 AI 回复而左对齐。当列表中完全没有 user 时，按问答轮次恢复 role。
List<NativeNovaMessage> reconcileMisclassifiedNovaRoles(
  List<NativeNovaMessage> raw,
) {
  if (raw.length < 2) return raw;
  final items = raw.where((m) => !m.isWelcome).toList(growable: false);
  if (items.length < 2) return raw;
  if (items.any((m) => m.role == 'user')) return raw;

  final sorted = sortNovaMessages(items);
  final fixed = <NativeNovaMessage>[];
  for (var i = 0; i < sorted.length; i++) {
    final m = sorted[i];
    fixed.add(i.isEven ? m.copyWith(role: 'user') : m);
  }
  final welcome = raw.where((m) => m.isWelcome).toList(growable: false);
  return sortNovaMessages([...welcome, ...fixed]);
}

bool _novaHasAiReplyAfter(List<NativeNovaMessage> rows, int afterMessageId) {
  if (afterMessageId <= 0) return false;
  var seen = false;
  for (final m in rows) {
    if (m.isWelcome) continue;
    if (m.id == afterMessageId) {
      seen = true;
      continue;
    }
    if (!seen) continue;
    if (m.streaming) continue;
    if (m.role == 'assistant' && m.text.trim().isNotEmpty) return true;
  }
  return false;
}

class NovaHistoryLoadResult {
  const NovaHistoryLoadResult({
    required this.messages,
    this.assistantGenerating = false,
    this.generatingStatus = '',
    this.generatingAfterMessageId = 0,
  });

  final List<NativeNovaMessage> messages;
  final bool assistantGenerating;
  final String generatingStatus;
  final int generatingAfterMessageId;
}

/// `sessions/ensure` 或 `GET /ai/conversations/{id}?all=true` 的统一快照。
class NovaConversationSnapshot {
  const NovaConversationSnapshot({
    required this.conversationId,
    this.novaSessionId = '',
    this.assistantGenerating = false,
    this.assistantGeneratingStatus = '',
    this.assistantGeneratingAfterMessageId = 0,
    this.messages = const <NativeNovaMessage>[],
  });

  final int conversationId;
  final String novaSessionId;
  final bool assistantGenerating;
  final String assistantGeneratingStatus;
  final int assistantGeneratingAfterMessageId;
  final List<NativeNovaMessage> messages;
}

class NovaStreamUpdate {
  const NovaStreamUpdate({
    required this.replyText,
    this.thinkText = '',
    this.thinkStatus = '',
    this.ragUsed = false,
  });

  final String replyText;
  final String thinkText;
  final String thinkStatus;
  final bool ragUsed;
}

class NovaReadiness {
  const NovaReadiness({required this.ready, this.message});

  final bool ready;
  final String? message;
}

class NovaHistoryPageResult {
  const NovaHistoryPageResult({required this.items, required this.hasMore});

  final List<NovaHistoryTurn> items;
  final bool hasMore;
}

class NovaHistoryTurn {
  const NovaHistoryTurn({
    required this.conversationId,
    required this.messageId,
    required this.title,
    required this.preview,
    this.lastMessageAt,
  });

  final int conversationId;
  final int messageId;
  final String title;
  final String preview;
  final DateTime? lastMessageAt;
}

class NativeNovaService {
  NativeNovaService({required this.session, http.Client? client})
    : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;
  String? _cachedApiKey;
  String? _selectedModelOverride;
  List<String> _availableChatModels = const <String>[];
  http.Client? _streamClient;
  bool userStoppedStream = false;
  NovaConversationSnapshot? _lastSessionSnapshot;
  final Map<int, DateTime> _userMessageAtByConv = <int, DateTime>{};

  /// SSE 仍在进行（离开 C4 后共享 service 上可能仍在跑）。
  bool get isStreamInFlight => _streamClient != null && !userStoppedStream;

  NovaConversationSnapshot? get lastSessionSnapshot => _lastSessionSnapshot;
  NovaHistorySync? _historySync;

  NovaHistorySync get _history => _historySync ??= NovaHistorySync(
    session: session,
    client: _client,
    selectedModel: selectedModel,
    novaBizUserId: novaBizUserId,
    novaProfileSessionId: novaProfileSessionId,
    displayName: (session.displayName ?? '').trim().isNotEmpty
        ? session.displayName!.trim()
        : '我',
  );

  Uri _dunesUri(String path) => Uri.parse('${session.apiBase}$path');

  String mediaProxyUrl(String source, {String bucket = 'im-attachments'}) {
    final raw = source.trim();
    if (raw.isEmpty) return raw;
    return _dunesUri(
      '/storage/download?bucket=$bucket&objectKey=${Uri.encodeQueryComponent(raw)}&proxy=1',
    ).toString();
  }

  Map<String, String> get _dunesHeaders => <String, String>{
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  String get novaBase => NovaConfig.resolveBaseUrl(
        session.novaLocalStorage?['dunes_nova_base'],
      );
  String get novaApiKey =>
      (_cachedApiKey ?? session.novaLocalStorage?['dunes_nova_api_key'] ?? '')
          .trim();
  String get selectedModel {
    final override = _selectedModelOverride?.trim() ?? '';
    if (override.isNotEmpty) return override;
    return (session.novaLocalStorage?['dunes_nova_chat_model'] ??
            session.novaLocalStorage?['dunes_nova_default_model'] ??
            NovaConfig.defaultChatModel)
        .trim();
  }

  void setSelectedChatModel(String model, {bool persist = false}) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    _selectedModelOverride = trimmed;
    _historySync = null;
    if (!persist) return;
    final uid = session.userId;
    if (uid > 0) {
      unawaited(NovaWebStorage.merge(uid, {'dunes_nova_chat_model': trimmed}));
    }
  }

  /// 同步岗位可用对话模型，供多模态静默挑视觉模型。
  void setAvailableChatModels(List<String> models) {
    _availableChatModels = resolveNovaChatModels(models);
  }

  List<String> get availableChatModels {
    if (_availableChatModels.isNotEmpty) return _availableChatModels;
    final raw = session.novaLocalStorage?['dunes_allowed_models'];
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return resolveNovaChatModels(decoded.map((e) => e.toString()).toList());
      }
    } catch (_) {}
    return const <String>[];
  }

  /// 有图片时若当前模型不支持视觉，返回原模型（由 UI 提示切换，不再静默改派）。
  String resolveModelForContent(dynamic userContent, {String? preferred}) {
    final selected = (preferred ?? selectedModel).trim().isEmpty
        ? NovaConfig.defaultChatModel
        : (preferred ?? selectedModel).trim();
    return selected;
  }

  String resolveModelForVision({required bool needsVision, String? preferred}) {
    return resolveModelForContent(null, preferred: preferred);
  }

  /// 进入 C4 时重试失败的历史同步队列。
  Future<void> flushHistorySyncQueue() => _history.flushSyncQueue();

  /// 对齐 WebView `registerNovaHistoryTurn`（AI 回复完成后 POST）。
  Future<void> registerHistoryTurn({
    required int conversationId,
    required int messageId,
    required String userMessage,
    required String assistantMessage,
    String? title,
    String? lastMessagePreview,
    String? lastMessageAt,
    Map<String, dynamic>? userPayload,
  }) => _history.registerHistoryTurn(
    conversationId: conversationId,
    messageId: messageId,
    userMessage: userMessage,
    assistantMessage: assistantMessage,
    title: title,
    lastMessagePreview: lastMessagePreview,
    lastMessageAt: lastMessageAt,
    model: selectedModel,
    userPayload: userPayload,
  );

  /// 审计入库用的 userPayload：保证带 `attachments` 数组，避免 IM 平铺
  /// `{objectKey,fileName}` 写进 flow-go 后管理端解析不到附件。
  Map<String, dynamic>? historyUserPayloadFromMessage(
    NativeNovaMessage user, {
    Map<String, dynamic>? fallback,
  }) {
    return historyUserPayloadFromParts(
      payload: user.payload ?? fallback,
      attachments: user.attachments,
      kind: user.kind,
    );
  }

  Map<String, dynamic>? historyUserPayloadFromParts({
    Map<String, dynamic>? payload,
    List<NovaMessageAttachment> attachments = const <NovaMessageAttachment>[],
    String kind = 'TEXT',
  }) {
    final out = <String, dynamic>{};
    if (payload != null && payload.isNotEmpty) {
      for (final e in payload.entries) {
        out[e.key] = e.value;
      }
    }

    final atts = <Map<String, dynamic>>[];
    final nested = out['attachments'];
    if (nested is List) {
      for (final row in nested) {
        if (row is Map) {
          atts.add(Map<String, dynamic>.from(row));
        }
      }
    }
    if (atts.isEmpty && attachments.isNotEmpty) {
      for (final a in attachments) {
        atts.add(a.toJson());
      }
    }
    if (atts.isEmpty) {
      final k = kind.toUpperCase();
      final hasFile =
          (out['url'] != null && out['url'].toString().trim().isNotEmpty) ||
          (out['objectKey'] != null &&
              out['objectKey'].toString().trim().isNotEmpty) ||
          (out['previewUrl'] != null &&
              out['previewUrl'].toString().trim().isNotEmpty);
      if (hasFile && (k == 'IMAGE' || k == 'FILE' || k == 'AUDIO')) {
        atts.add(<String, dynamic>{
          ...out,
          'kind': k,
          'fileName': (out['fileName'] ?? out['name'] ?? 'file').toString(),
          'bucket': (out['bucket'] ?? 'im-attachments').toString(),
        });
      }
    }
    if (atts.isNotEmpty) {
      out['attachments'] = atts;
    }
    return out.isEmpty ? null : out;
  }

  /// 以 IM 会话中的真实消息 ID 回填审计轮次。
  ///
  /// `/ai/assistant/messages` 会在服务端创建新的 user/assistant 消息，
  /// 但客户端发送前生成的毫秒时间戳不是 IM 消息 ID。审计若使用该临时 ID
  /// upsert，会覆盖旧轮次，导致工作台少轮或问答错配。
  Future<List<NativeNovaMessage>> syncCanonicalHistoryTurns(
    int conversationId,
  ) async {
    final snapshot = await fetchConversationAll(conversationId);
    final canonicalConversationId = snapshot.conversationId > 0
        ? snapshot.conversationId
        : conversationId;
    final rows = sortNovaMessages(
      snapshot.messages,
    ).where((m) => !m.isWelcome).toList(growable: false);

    // 先与本地合并，把多模态/附件元数据带进审计写入；否则 IM 纯文本会冲掉
    // 已有 userPayload.attachments。
    final localRows = await _loadPersistedSessionMessages(
      canonicalConversationId,
    );
    final mergedRows = _mergeTurnsWithSessionCache(rows, localRows)
        .where((m) => !m.isWelcome)
        .toList(growable: false);

    for (var index = 0; index < mergedRows.length; index++) {
      final user = mergedRows[index];
      if (user.role != 'user' || user.id <= 0) continue;

      NativeNovaMessage? assistant;
      for (var next = index + 1; next < mergedRows.length; next++) {
        final candidate = mergedRows[next];
        if (candidate.role == 'user') break;
        if (candidate.role == 'assistant' &&
            !candidate.streaming &&
            candidate.text.trim().isNotEmpty) {
          assistant = candidate;
          break;
        }
      }
      if (assistant == null) continue;

      await registerHistoryTurn(
        conversationId: canonicalConversationId,
        messageId: user.id,
        userMessage: user.text,
        assistantMessage: assistant.text,
        lastMessageAt: (assistant.createdAt ?? user.createdAt ?? DateTime.now())
            .toUtc()
            .toIso8601String(),
        userPayload: historyUserPayloadFromMessage(user),
      );
    }
    return mergedRows;
  }

  /// 离开 C4 / 新对话前刷新本地历史预览。
  Future<void> flushConvToLocalHistory(
    int conversationId,
    List<NativeNovaMessage> messages,
  ) => _history.flushConvToLocalHistory(conversationId, messages);

  Future<void> persistActiveConversationId(int conversationId) =>
      _history.persistActiveConversationId(conversationId);

  int _canonicalConversationIdFromBody(
    Map<String, dynamic> body, {
    required int fallback,
  }) {
    final data = body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : body;
    final canonical =
        (data['canonicalConversationId'] as num?)?.toInt() ??
        (data['conversationId'] as num?)?.toInt() ??
        fallback;
    return canonical > 0 ? canonical : fallback;
  }

  Future<void> remapConversationId(int oldId, int newId) async {
    if (oldId <= 0 || newId <= 0 || oldId == newId) return;
    final uid = session.userId;
    if (uid <= 0) return;
    final storage = await NovaWebStorage.load(uid);
    final patch = <String, dynamic>{'dunes_nova_conv_id': newId.toString()};

    final oldMsgsKey = 'dunes_nova_msgs_$oldId';
    final newMsgsKey = 'dunes_nova_msgs_$newId';
    final oldMsgs = storage[oldMsgsKey];
    if (oldMsgs != null && oldMsgs.isNotEmpty) {
      final newMsgs = storage[newMsgsKey];
      if (newMsgs == null || newMsgs.isEmpty) {
        patch[newMsgsKey] = oldMsgs;
      }
    }

    final oldGenKey = novaGeneratingStorageKey(oldId);
    final newGenKey = novaGeneratingStorageKey(newId);
    if (storage[oldGenKey] != null && storage[newGenKey] == null) {
      patch[newGenKey] = storage[oldGenKey];
    }

    final oldDraftKey = novaStreamDraftStorageKey(oldId);
    final newDraftKey = novaStreamDraftStorageKey(newId);
    if (storage[oldDraftKey] != null && storage[newDraftKey] == null) {
      patch[newDraftKey] = storage[oldDraftKey];
    }

    try {
      final rawHistory = storage['dunes_nova_local_history'];
      if (rawHistory != null && rawHistory.isNotEmpty) {
        final decoded = jsonDecode(rawHistory);
        if (decoded is List) {
          final updated = decoded
              .map((item) {
                if (item is! Map) return item;
                final copy = Map<String, dynamic>.from(item);
                if ((copy['conversationId'] as num?)?.toInt() == oldId) {
                  copy['conversationId'] = newId;
                }
                return copy;
              })
              .toList(growable: false);
          patch['dunes_nova_local_history'] = jsonEncode(updated);
        }
      }
    } catch (_) {}

    try {
      final rawQueue = storage['dunes_nova_history_sync_queue'];
      if (rawQueue != null && rawQueue.isNotEmpty) {
        final decoded = jsonDecode(rawQueue);
        if (decoded is List) {
          final updated = decoded
              .map((item) {
                if (item is! Map) return item;
                final copy = Map<String, dynamic>.from(item);
                final payload = copy['payload'];
                if (payload is Map) {
                  final payloadCopy = Map<String, dynamic>.from(payload);
                  if ((payloadCopy['conversationId'] as num?)?.toInt() ==
                      oldId) {
                    payloadCopy['conversationId'] = newId;
                    payloadCopy['imConversationId'] = newId;
                  }
                  copy['payload'] = payloadCopy;
                }
                return copy;
              })
              .toList(growable: false);
          patch['dunes_nova_history_sync_queue'] = jsonEncode(updated);
        }
      }
    } catch (_) {}

    await NovaWebStorage.merge(uid, patch);
    await NovaWebStorage.removeKeys(uid, [oldMsgsKey, oldGenKey, oldDraftKey]);
    if (kDebugMode) {
      debugPrint('[NativeNova] remapConversationId $oldId -> $newId');
    }
  }

  Future<int> _adoptCanonicalConversationId(
    int requestedId,
    int canonicalId,
  ) async {
    if (canonicalId <= 0) return requestedId > 0 ? requestedId : 0;
    if (requestedId > 0 && requestedId != canonicalId) {
      await remapConversationId(requestedId, canonicalId);
    } else {
      await persistActiveConversationId(canonicalId);
    }
    return canonicalId;
  }

  static String friendlyError(Object error) {
    final raw = error.toString();
    var msg = raw.startsWith('Exception: ')
        ? raw.substring('Exception: '.length)
        : raw;
    // 云枢 C4 不阻断知识库/RAG 状态（对齐 WebView：创建会话失败静默降级）。
    if (msg.contains('rag_not_ready') || msg.contains('知识库账号')) {
      return '';
    }
    if (msg.contains('HTTP 400')) return 'NOVA会话初始化异常，请发送一条消息或稍后重试';
    if (msg.contains('HTTP 503')) return 'NOVA服务暂不可用，请稍后再试';
    if (msg.contains('凭证') || msg.contains('api_key'))
      return 'NOVA账号尚未就绪，请重新登录后再试';
    if (msg.contains('尚未开通')) return msg;
    if (msg.contains('NOVA未返回正文') || msg.contains('NOVA回复失败')) return msg;
    final low = msg.toLowerCase();
    if (low.contains('context length') ||
        low.contains('maximum context') ||
        low.contains('token limit') ||
        low.contains('too large') ||
        low.contains('payload too large') ||
        low.contains('request entity too large')) {
      return '附件内容过大，请缩短会议纪要或稍后重试';
    }
    if (low.contains('unsupported') && low.contains('file')) {
      return '当前内容暂无法处理，请稍后重试或换一张图片';
    }
    if ((low.contains('vision') || low.contains('image')) &&
        (low.contains('not support') ||
            low.contains('unsupported') ||
            msg.contains('不支持'))) {
      return '图片识别暂时不可用，请稍后重试';
    }
    if (low.contains('attachment') &&
        (low.contains('expir') ||
            low.contains('not found') ||
            low.contains('invalid') ||
            msg.contains('过期'))) {
      return '附件已过期，请重新上传';
    }
    return friendlyErrorText(msg, fallback: 'NOVA 请求失败，请稍后重试');
  }

  Future<({String avatarPreset, String avatarObjectKey, String avatarUrl})>
  fetchCurrentUserAvatar() async {
    try {
      final resp = await _client.get(
        _dunesUri('/users/me'),
        headers: _dunesHeaders,
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return (avatarPreset: '', avatarObjectKey: '', avatarUrl: '');
      }
      final body = _decode(resp.body);
      final data = body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : body;
      final preset = (data['avatarPreset'] ?? data['peerAvatarPreset'] ?? '')
          .toString();
      var url =
          (data['avatarUrl'] ??
                  data['avatarFullUrl'] ??
                  data['avatarImageUrl'] ??
                  data['avatar'] ??
                  '')
              .toString();
      final objectKey = (data['avatarObjectKey'] ?? '').toString();
      if (url.isEmpty && _isHttpUrl(objectKey)) {
        url = objectKey;
      }
      if (url.isEmpty && objectKey.isNotEmpty && !_isHttpUrl(objectKey)) {
        url = mediaProxyUrl(objectKey, bucket: 'user-avatars');
      }
      return (avatarPreset: preset, avatarObjectKey: objectKey, avatarUrl: url);
    } catch (_) {
      return (avatarPreset: '', avatarObjectKey: '', avatarUrl: '');
    }
  }

  Future<NovaReadiness> checkReadiness() async {
    return _refreshNovaCredentials();
  }

  bool _isHttpUrl(String value) {
    final v = value.toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  /// 对齐 admin-web `refreshNovaCredentials`：每次进入/发消息前拉最新凭证。
  Future<NovaReadiness> _refreshNovaCredentials() async {
    try {
      final resp = await _client.get(
        _dunesUri('/me/nova-credentials'),
        headers: _dunesHeaders,
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (novaApiKey.isNotEmpty) return const NovaReadiness(ready: true);
        return const NovaReadiness(ready: false, message: 'NOVA账号尚未开通，请稍后再试');
      }
      final body = _decode(resp.body);
      final data = body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : body;
      final ready = data['ready'] == true;
      final key = ((data['api_token'] ?? data['apiKey']) ?? '')
          .toString()
          .trim();
      if (key.isNotEmpty) _cachedApiKey = key;
      if (ready && key.isNotEmpty) return const NovaReadiness(ready: true);
      if (novaApiKey.isNotEmpty) return const NovaReadiness(ready: true);
      final message =
          (data['lastError'] ?? data['message'] ?? 'NOVA账号尚未开通，请稍后再试')
              .toString()
              .trim();
      return NovaReadiness(ready: false, message: message);
    } catch (_) {
      if (novaApiKey.isNotEmpty) return const NovaReadiness(ready: true);
      return const NovaReadiness(ready: false, message: 'NOVA服务暂不可用');
    }
  }

  /// 启动/进入云枢：仅 `POST sessions/ensure`，缓存 `data.conversationId`。
  Future<int> ensureConversation({bool preferCreate = false}) async {
    final webStorage = await NovaWebStorage.load(session.userId);
    final saved = int.tryParse(webStorage['dunes_nova_conv_id'] ?? '') ?? 0;
    final viewSince = (webStorage['dunes_nova_view_since'] ?? '').trim();

    // 重新进入云枢时优先恢复本地会话，避免反复 sessions/ensure 拿到新 convId 导致错位/空白页。
    if (!preferCreate && saved > 0) {
      if (kDebugMode) {
        debugPrint('[NativeNova] restore saved convId=$saved');
      }
      return saved;
    }

    if (preferCreate || viewSince.isNotEmpty) {
      if (viewSince.isNotEmpty && saved > 0) return saved;
    }

    final snap = await sessionEnsure();
    if (snap.conversationId > 0) {
      await persistActiveConversationId(snap.conversationId);
      return snap.conversationId;
    }
    return saved;
  }

  Future<int> createFreshConversation() async {
    return beginNewConversation();
  }

  Future<int> createNovaServerConversation({bool forceNew = false}) =>
      _createConversation(forceNew: forceNew);

  /// 对齐 WebView `startNewConversation` 前置：convId=0 + view-since，不立刻调创建接口。
  Future<void> resetNovaNewChatPlaceholder({
    required int userId,
    int previousConversationId = 0,
  }) async {
    if (previousConversationId > 0 && userId > 0) {
      await clearNovaGeneratingState(
        userId: userId,
        conversationId: previousConversationId,
      );
      await clearNovaStreamDraftState(
        userId: userId,
        conversationId: previousConversationId,
      );
    }
    if (userId <= 0) return;
    await NovaWebStorage.merge(userId, <String, dynamic>{
      'dunes_nova_conv_id': '',
      'dunes_nova_view_since': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> applyNovaNewChatStorage({
    required int userId,
    required int conversationId,
    required int previousConversationId,
  }) async {
    if (userId <= 0 || conversationId <= 0) return;
    final patch = <String, dynamic>{
      'dunes_nova_conv_id': conversationId.toString(),
      'dunes_nova_msgs_$conversationId': '[]',
    };
    if (previousConversationId > 0 &&
        previousConversationId == conversationId) {
      patch['dunes_nova_view_since'] = '';
    } else {
      patch['dunes_nova_view_since'] = DateTime.now().toUtc().toIso8601String();
    }
    await NovaWebStorage.merge(userId, patch);
  }

  /// 创建接口失败时本地模拟新对话（view-since 隔离历史），不依赖服务端新建会话。
  Future<int> applyNewChatLocalFallback({
    required int userId,
    required int previousConversationId,
  }) async {
    if (userId <= 0 || previousConversationId <= 0) return 0;
    if (await isImInboxPlaceholderConvId(previousConversationId)) return 0;
    await NovaWebStorage.merge(userId, <String, dynamic>{
      'dunes_nova_conv_id': previousConversationId.toString(),
      'dunes_nova_view_since': DateTime.now().toUtc().toIso8601String(),
      'dunes_nova_msgs_$previousConversationId': '[]',
    });
    return previousConversationId;
  }

  /// 对齐 WebView `startNewConversation`：创建失败静默降级，不抛知识库相关错误。
  Future<int> beginNewConversation({int previousConversationId = 0}) async {
    final uid = session.userId;
    await resetNovaNewChatPlaceholder(
      userId: uid,
      previousConversationId: previousConversationId,
    );
    // `sessions/ensure` 会返回已有的最近会话，不能用于「新对话」；
    // 否则新问题会被追加到历史会话并在重新进入时一并回放。
    final fresh = await sessionNew();
    final id = fresh.conversationId;
    if (id > 0) {
      await applyNovaNewChatStorage(
        userId: uid,
        conversationId: id,
        previousConversationId: previousConversationId,
      );
      return id;
    }
    if (previousConversationId > 0) {
      return applyNewChatLocalFallback(
        userId: uid,
        previousConversationId: previousConversationId,
      );
    }
    return 0;
  }

  String _storagePublicBase() {
    final fromStorage =
        (session.novaLocalStorage?['dunes_storage_public_base'] ??
                session.novaLocalStorage?['dunes_ftp_public_base'] ??
                '')
            .trim();
    if (fromStorage.isNotEmpty)
      return fromStorage.replaceAll(RegExp(r'/$'), '');
    return 'https://image.heunion.com/zdfiles';
  }

  String resolvePublicAttachmentUrl({
    required String url,
    required String objectKey,
    String bucket = 'im-attachments',
    String backend = '',
  }) {
    final direct = url.trim();
    if (direct.startsWith('http://') || direct.startsWith('https://'))
      return direct;
    final key = objectKey.trim().isNotEmpty ? objectKey.trim() : direct;
    if (key.startsWith('http://') || key.startsWith('https://')) return key;
    if (key.isEmpty) return '';
    if (backend == 'ftp' ||
        bucket == 'im-attachments' ||
        key.startsWith('proposals/') ||
        key.startsWith('im/')) {
      return '${_storagePublicBase()}/${key.replaceFirst(RegExp(r'^/'), '')}';
    }
    return '';
  }

  Map<String, dynamic> buildUploadedAttachmentPayload({
    required String url,
    required String objectKey,
    required String fileName,
    required String mimeType,
    required String kind,
    String bucket = 'im-attachments',
    String backend = '',
  }) {
    final accessUrl = resolvePublicAttachmentUrl(
      url: url,
      objectKey: objectKey,
      bucket: bucket,
      backend: backend,
    );
    final resolved = accessUrl.isNotEmpty
        ? accessUrl
        : (url.isNotEmpty ? url : objectKey);
    return <String, dynamic>{
      'url': resolved,
      'objectKey': objectKey,
      'accessUrl': accessUrl.isNotEmpty ? accessUrl : '',
      'publicUrl': accessUrl.isNotEmpty ? accessUrl : '',
      'previewUrl': accessUrl.isNotEmpty ? accessUrl : resolved,
      'fileName': fileName,
      'mimeType': mimeType,
      'kind': kind,
      'bucket': bucket,
      if (backend.isNotEmpty) 'backend': backend,
    };
  }

  /// 已废弃：云枢 convId 仅来自 `sessions/ensure`，不再读 C1 IM 列表。
  Future<bool> isImInboxPlaceholderConvId(int conversationId) async => false;

  Future<void> sanitizeNovaConvStorage() async {}

  Future<bool> validateNovaConversationId(int conversationId) async {
    if (conversationId <= 0) return false;
    try {
      await fetchConversationAll(conversationId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearInvalidNovaConvId(int conversationId) async {
    final uid = session.userId;
    if (uid <= 0 || conversationId <= 0) return;
    final storage = await NovaWebStorage.load(uid);
    final saved = int.tryParse(storage['dunes_nova_conv_id'] ?? '') ?? 0;
    final patch = <String, dynamic>{};
    if (saved == conversationId) patch['dunes_nova_conv_id'] = '';
    try {
      final raw = storage['dunes_nova_local_history'];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final kept = decoded
              .whereType<Map>()
              .where((item) {
                final cid = (item['conversationId'] as num?)?.toInt() ?? 0;
                return cid != conversationId;
              })
              .toList(growable: false);
          patch['dunes_nova_local_history'] = jsonEncode(kept);
        }
      }
    } catch (_) {}
    if (patch.isNotEmpty) await NovaWebStorage.merge(uid, patch);
    await NovaWebStorage.removeKeys(uid, ['dunes_nova_msgs_$conversationId']);
  }

  Future<int> _createConversation({bool forceNew = false}) async {
    if (forceNew) return sessionNew().then((snap) => snap.conversationId);
    return _postAiConversationSessionEnsure();
  }

  /// IM 服务是 NOVA 的唯一会话来源；不得再混用 KB 会话 ID。
  Future<NovaConversationSnapshot> sessionEnsure({
    int legacyConversationId = 0,
  }) async {
    final resp = await _client.post(
      _dunesUri('/ai/assistant/sessions/ensure'),
      headers: _dunesHeaders,
      body: jsonEncode(<String, dynamic>{
        'kind': 'AI_ASSISTANT',
        'title': NovaConfig.displayName,
        if (legacyConversationId > 0) 'conversationId': legacyConversationId,
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_parseApiError(resp, fallback: 'NOVA会话初始化失败'));
    }
    final decoded = _decode(resp.body);
    final canonical = _canonicalConversationIdFromBody(
      decoded,
      fallback: legacyConversationId,
    );
    if (legacyConversationId > 0) {
      await _adoptCanonicalConversationId(legacyConversationId, canonical);
    } else if (canonical > 0) {
      await persistActiveConversationId(canonical);
    }
    final snap = _parseConversationSnapshot(decoded, fallbackConvId: canonical);
    await persistNovaChatSessionId(snap.conversationId, snap.novaSessionId);
    _lastSessionSnapshot = snap;
    if (kDebugMode) {
      debugPrint(
        '[NativeNova] sessions/ensure convId=${snap.conversationId} '
        'legacy=$legacyConversationId generating=${snap.assistantGenerating}',
      );
    }
    return snap;
  }

  /// 强制新建一个独立的 NOVA 会话，不能回退到 `sessions/ensure` 的最近会话。
  Future<NovaConversationSnapshot> sessionNew() async {
    final resp = await _client.post(
      _dunesUri('/ai/assistant/sessions/new'),
      headers: _dunesHeaders,
      body: jsonEncode(<String, dynamic>{
        'kind': 'AI_ASSISTANT',
        'title': '新对话',
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_parseApiError(resp, fallback: '创建NOVA新会话失败'));
    }
    final snap = _parseConversationSnapshot(_decode(resp.body));
    await persistNovaChatSessionId(snap.conversationId, snap.novaSessionId);
    _lastSessionSnapshot = snap;
    if (kDebugMode) {
      debugPrint('[NativeNova] sessions/new convId=${snap.conversationId}');
    }
    return snap;
  }

  /// `GET /ai/conversations/{id}?all=true`
  Future<NovaConversationSnapshot> fetchConversationAll(
    int conversationId,
  ) async {
    if (conversationId <= 0) {
      return const NovaConversationSnapshot(conversationId: 0);
    }
    final resp = await _client.get(
      _dunesUri('/conversations/$conversationId/messages?size=50'),
      headers: _dunesHeaders,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_parseApiError(resp, fallback: '加载NOVA会话失败'));
    }
    final decoded = _decode(resp.body);
    final canonical = _canonicalConversationIdFromBody(
      decoded,
      fallback: conversationId,
    );
    await _adoptCanonicalConversationId(conversationId, canonical);
    final snap = _parseConversationSnapshot(decoded, fallbackConvId: canonical);
    await persistNovaChatSessionId(snap.conversationId, snap.novaSessionId);
    _lastSessionSnapshot = snap;
    return snap;
  }

  NovaConversationSnapshot _parseConversationSnapshot(
    Map<String, dynamic> body, {
    int fallbackConvId = 0,
  }) {
    final d = body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : body;
    final convId =
        (d['canonicalConversationId'] as num?)?.toInt() ??
        (d['conversationId'] as num?)?.toInt() ??
        fallbackConvId;
    final gen = _parseGeneratingFields(d);
    final rawMsgs = d['messages'] ?? d['items'] ?? d['rows'];
    final msgs = _messagesFromServerList(rawMsgs);
    return NovaConversationSnapshot(
      conversationId: convId,
      novaSessionId: (d['novaSessionId'] ?? d['nova_session_id'] ?? '')
          .toString(),
      assistantGenerating: gen.$1,
      assistantGeneratingStatus: gen.$2,
      assistantGeneratingAfterMessageId: gen.$3,
      messages: msgs,
    );
  }

  (bool, String, int) _parseGeneratingFields(Map<String, dynamic> d) {
    final nested = d['assistantGenerating'];
    if (nested is Map) {
      return (
        nested['active'] == true || nested['generating'] == true,
        (nested['status'] ?? nested['message'] ?? '').toString(),
        (nested['afterMessageId'] as num?)?.toInt() ??
            (nested['after_message_id'] as num?)?.toInt() ??
            0,
      );
    }
    return (
      d['assistantGenerating'] == true,
      (d['assistantGeneratingStatus'] ?? d['assistant_generating_status'] ?? '')
          .toString(),
      (d['assistantGeneratingAfterMessageId'] as num?)?.toInt() ??
          (d['assistant_generating_after_message_id'] as num?)?.toInt() ??
          0,
    );
  }

  List<NativeNovaMessage> _messagesFromServerList(dynamic raw) {
    if (raw is! List) return const <NativeNovaMessage>[];
    final out = <NativeNovaMessage>[];
    for (final item in raw) {
      if (item is! Map) continue;
      out.add(_mapRawMessage(Map<String, dynamic>.from(item)));
    }
    out.sort((a, b) {
      final ta = a.createdAt?.millisecondsSinceEpoch ?? a.id;
      final tb = b.createdAt?.millisecondsSinceEpoch ?? b.id;
      if (ta != tb) return ta.compareTo(tb);
      if (a.role != b.role) {
        if (a.role == 'user') return -1;
        if (b.role == 'user') return 1;
      }
      return a.id.compareTo(b.id);
    });
    // IM 返回的顺序、ID 和 createdAt 是会话的权威数据。不要在这里套
    // repairNovaConversationMessages：它按启发式重新配对，会让相同文案的
    // 多轮「测试」错配。
    return reconcileMisclassifiedNovaRoles(out);
  }

  Future<int> _postAiConversationSessionEnsure() async {
    try {
      final snap = await sessionEnsure();
      return snap.conversationId;
    } catch (_) {
      return 0;
    }
  }

  Future<List<NativeNovaMessage>> fetchHistory(
    int conversationId, {
    int size = 80,
  }) async {
    final full = await fetchFullHistory(conversationId);
    return full.messages;
  }

  Future<NovaHistoryLoadResult> fetchFullHistory(
    int conversationId, {
    int? aroundMessageId,
    bool applyViewSinceFilter = true,
    bool restoreFromHistory = false,
  }) async {
    if (conversationId <= 0) {
      return const NovaHistoryLoadResult(messages: <NativeNovaMessage>[]);
    }

    NovaConversationSnapshot server;
    try {
      server = await fetchConversationAll(conversationId);
    } catch (_) {
      server = NovaConversationSnapshot(conversationId: conversationId);
    }
    final effectiveConvId = server.conversationId > 0
        ? server.conversationId
        : conversationId;

    var generating = server.assistantGenerating;
    var genStatus = server.assistantGeneratingStatus;
    var genAfter = server.assistantGeneratingAfterMessageId;

    NovaGeneratingState? localGen;
    NovaStreamDraft? streamDraft;
    if (session.userId > 0) {
      final storage = await NovaWebStorage.load(session.userId);
      localGen = readNovaGeneratingFromStorage(
        storage,
        convId: effectiveConvId,
        activeConvId: effectiveConvId,
      );
      streamDraft = readNovaStreamDraftFromStorage(storage, effectiveConvId);
    }

    final localMsgs = await _loadPersistedSessionMessages(effectiveConvId);
    // IM 快照可能为空、落库延迟，或只返回最新一轮；多模态轮次也只在本地。
    // 始终合并本地缓存，避免把已有完整会话截断成一轮。服务端同 ID 的消息
    // 仍优先作为权威数据，临时 ID 则由去重逻辑按角色、内容和时间窗口合并。
    var msgs = _mergeTurnsWithSessionCache(server.messages, localMsgs);

    // 修复：后台完成生成后重新进入会话时，服务端快照可能只回了用户消息而漏掉助手
    // 回复（助手 turn 尚未在服务端落库/回显）。若不补齐，下面的持久化会用「仅用户
    // 消息」覆盖本地缓存，导致已生成的回复永久丢失。这里用本地已保存的完整回复补齐。
    if (server.messages.isEmpty) {
      msgs = _mergeTrailingAssistantFromLocal(msgs, localMsgs);
    }

    final preserveGeneratingSnapshot = shouldPersistNovaGenerating(
      localGen: localGen,
      draft: streamDraft,
      streamInFlight: isStreamInFlight,
    );
    // 始终拉取 flow-go `/ai/history/turns`：附件与多模态轮次写在 userPayload，
    // IM 快照通常只有正文。此前仅在 server.messages 为空时才请求，导致回看
    // 看不到图片、文件。有 turns 时以审计时间线为主，再合并 IM/本地。
    final turns = await _fetchTurnRows(200, conversationId: conversationId);
    final scoped = _filterTurnsForConversation(turns, conversationId);
    if (scoped.isNotEmpty) {
      final turnMsgs = _novaMsgsFromTurns(
        _dedupeNovaTurns(scoped),
        conversationId,
      );
      if (turnMsgs.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[NativeNova] merge history turns conv=$conversationId '
            'turns=${scoped.length} im=${server.messages.length} '
            'local=${localMsgs.length}',
          );
        }
        // turns 优先：含 Excel/图片等仅存在于审计表的轮次。
        msgs = _mergeTurnsWithSessionCache(turnMsgs, server.messages);
        msgs = _mergeTurnsWithSessionCache(msgs, localMsgs);
        if (restoreFromHistory) {
          unawaited(
            _backfillImMissingAttachmentTurns(
              conversationId,
              scoped,
              server.messages,
            ),
          );
        }
      }
    } else if (turns.isNotEmpty && kDebugMode) {
      debugPrint(
        '[NativeNova] skip turns merge: none match conv=$conversationId '
        '(got ${turns.length})',
      );
    }

    msgs = applyViewSinceFilter ? await _applyViewSinceFilter(msgs) : msgs;

    if (!isStreamInFlight && !preserveGeneratingSnapshot) {
      msgs = _stripIncompleteStreamingMessages(msgs);
    }

    final hasReplyAfter = localGen != null && localGen.afterMessageId > 0
        ? _novaHasAiReplyAfter(msgs, localGen.afterMessageId)
        : false;

    if (!generating) {
      if (shouldPersistNovaGenerating(
        localGen: localGen,
        draft: streamDraft,
        streamInFlight: isStreamInFlight,
        hasAiReplyAfter: hasReplyAfter,
      )) {
        generating = true;
        genStatus = (localGen?.status ?? streamDraft?.status ?? '').trim();
        if (genStatus.isEmpty) genStatus = '正在生成…';
        genAfter = localGen?.afterMessageId ?? streamDraft?.afterMessageId ?? 0;
      } else if (localGen != null) {
        unawaited(
          clearNovaGeneratingState(
            userId: session.userId,
            conversationId: effectiveConvId,
          ),
        );
      }
    } else if (hasReplyAfter) {
      generating = false;
      unawaited(
        clearNovaGeneratingState(
          userId: session.userId,
          conversationId: effectiveConvId,
        ),
      );
    }

    if (msgs.isNotEmpty && !generating) {
      unawaited(_persistSessionMessages(effectiveConvId, msgs));
    }
    return NovaHistoryLoadResult(
      messages: sortNovaMessages(_dedupeNovaHistory(msgs)),
      assistantGenerating: generating,
      generatingStatus: genStatus,
      generatingAfterMessageId: genAfter,
    );
  }

  /// 审计表有附件轮次、IM 没有时补写到 IM（需 im-svc `/ai/assistant/turns`）。
  Future<void> _backfillImMissingAttachmentTurns(
    int conversationId,
    List<Map<String, dynamic>> turns,
    List<NativeNovaMessage> imMessages,
  ) async {
    if (conversationId <= 0 || turns.isEmpty) return;
    final imTexts = imMessages
        .where((m) => m.role == 'user')
        .map((m) => m.text.trim())
        .where((t) => t.isNotEmpty)
        .toSet();
    for (final t in turns) {
      Map<String, dynamic>? payload;
      final raw =
          t['userPayload'] ?? t['userMetadata'] ?? t['user_payload'] ?? t['metadata'];
      if (raw is Map) payload = Map<String, dynamic>.from(raw);
      final atts = payload?['attachments'];
      if (atts is! List || atts.isEmpty) continue;
      final user = _novaTurnUserText(t);
      final assist = _novaTurnAssistantText(t);
      if (user.isEmpty || assist.isEmpty) continue;
      if (imTexts.contains(user)) continue;
      await persistImAssistantTurn(
        conversationId: conversationId,
        userMessage: user,
        assistantMessage: assist,
        userPayload: payload,
      );
    }
  }

  /// 当服务端快照缺失结尾的助手回复，但本地缓存已保存完整回复时，补齐该回复。
  /// 保守判断：本地最后一条有效消息必须是非流式、有文本的助手消息；服务端最后一条
  /// 有效消息必须是用户消息；且服务端尚未包含该回复文本。
  List<NativeNovaMessage> _mergeTrailingAssistantFromLocal(
    List<NativeNovaMessage> server,
    List<NativeNovaMessage> local,
  ) {
    if (server.isEmpty || local.isEmpty) return server;
    final localMeaningful = local
        .where((m) => m.text.trim().isNotEmpty || m.attachments.isNotEmpty)
        .toList(growable: false);
    if (localMeaningful.isEmpty) return server;
    final localReply = localMeaningful.last;
    if (localReply.role != 'assistant' ||
        localReply.streaming ||
        localReply.text.trim().isEmpty) {
      return server;
    }
    final serverMeaningful = server
        .where((m) => m.text.trim().isNotEmpty || m.attachments.isNotEmpty)
        .toList(growable: false);
    if (serverMeaningful.isEmpty || serverMeaningful.last.role != 'user') {
      return server;
    }
    final replyText = localReply.text.trim();
    final alreadyHas = server.any(
      (m) => m.role == 'assistant' && m.text.trim() == replyText,
    );
    if (alreadyHas) return server;
    if (kDebugMode) {
      debugPrint('[NativeNova] 服务端缺失助手回复，使用本地缓存补齐');
    }
    return <NativeNovaMessage>[...server, localReply];
  }

  bool _shouldRebuildFromTurns(List<NativeNovaMessage> msgs) {
    if (msgs.isEmpty) return true;
    final hasUser = msgs.any((m) => m.role == 'user');
    final hasAssistant = msgs.any(
      (m) => m.role == 'assistant' && m.text.trim().isNotEmpty,
    );
    if (!hasAssistant) return false;
    if (!hasUser) return true;
    final firstFew = msgs.take(6).toList(growable: false);
    final assistantOnlyPrefix =
        firstFew.isNotEmpty && firstFew.every((m) => m.role == 'assistant');
    return assistantOnlyPrefix;
  }

  /// 客户端发送前用 `DateTime.now().millisecondsSinceEpoch` 作临时 id；
  /// IM BIGSERIAL 远小于 1e12。用于识别「本地镜像 vs 服务端真消息」。
  bool _isClientTempMessageId(int id) => id >= 1000000000000;

  List<NativeNovaMessage> _mergeTurnsWithSessionCache(
    List<NativeNovaMessage> turns,
    List<NativeNovaMessage> local,
  ) {
    if (local.isEmpty) return turns;
    final map = <int, NativeNovaMessage>{};
    final serverIds = <int>{};
    for (final m in turns) {
      if (m.id <= 0) continue;
      map[m.id] = m;
      serverIds.add(m.id);
    }
    final consumedServerIds = <int>{};
    final localSorted = [...local]
      ..sort((a, b) {
        final ta = a.createdAt?.millisecondsSinceEpoch ?? a.id;
        final tb = b.createdAt?.millisecondsSinceEpoch ?? b.id;
        return ta.compareTo(tb);
      });

    for (final m in localSorted) {
      if (m.id <= 0) continue;
      final prev = map[m.id];
      if (prev != null) {
        map[m.id] = _mergeNovaHistoryById(prev, m);
        continue;
      }

      // 本地临时气泡与 IM 真消息内容相同、时间接近时，合并到服务端 id，
      // 避免「测试1」先本地出现再被 sync 成第二条。
      final mirror = _findServerMirrorForLocal(
        map.values
            .where(
              (s) =>
                  serverIds.contains(s.id) && !consumedServerIds.contains(s.id),
            )
            .toList(growable: false),
        m,
      );
      if (mirror != null) {
        consumedServerIds.add(mirror.id);
        map[mirror.id] = _mergeNovaHistoryById(
          mirror,
          m.copyWith(id: mirror.id, createdAt: mirror.createdAt ?? m.createdAt),
        );
        continue;
      }

      // 多模态走 chat/completions 时用户/助手可能仅落本地；必须保留。
      map[m.id] = m;
    }
    var out = map.values.toList()
      ..sort((a, b) {
        final ta = a.createdAt?.millisecondsSinceEpoch ?? a.id;
        final tb = b.createdAt?.millisecondsSinceEpoch ?? b.id;
        return ta.compareTo(tb);
      });
    out = _applyFuzzyAttachmentMerge(out, local);
    return sortNovaMessages(_dedupeNovaHistory(out));
  }

  NativeNovaMessage? _findServerMirrorForLocal(
    List<NativeNovaMessage> serverCandidates,
    NativeNovaMessage local,
  ) {
    if (!_isClientTempMessageId(local.id)) return null;
    final lText = local.text.trim();
    for (final s in serverCandidates) {
      if (s.role != local.role) continue;
      if (_isClientTempMessageId(s.id)) continue;
      if (!_novaMsgNearTime(s.createdAt, local.createdAt, seconds: 180)) {
        continue;
      }
      final sText = s.text.trim();
      final textMatch =
          sText == lText ||
          (lText.isEmpty && sText.isEmpty) ||
          isNovaPrdDisplayAndPromptPair(sText, lText) ||
          (local.attachments.isNotEmpty &&
              (sText.isEmpty ||
                  _isNovaImagePlaceholderText(sText) ||
                  sText == '[附件消息]' ||
                  sText == '[文件]' ||
                  sText == '[图片]'));
      if (!textMatch) continue;
      return s;
    }
    return null;
  }

  bool _novaMsgNearTime(DateTime? a, DateTime? b, {int seconds = 180}) {
    if (a == null || b == null) return true;
    return a.difference(b).inSeconds.abs() <= seconds;
  }

  /// turns 合成 id 与本地缓存 id 不一致时，按角色+文本+时间窗口合并附件。
  List<NativeNovaMessage> _applyFuzzyAttachmentMerge(
    List<NativeNovaMessage> turns,
    List<NativeNovaMessage> local,
  ) {
    if (local.isEmpty) return turns;
    final out = [...turns];
    for (final loc in local) {
      if (loc.attachments.isEmpty) continue;
      var idx = -1;
      for (var i = 0; i < out.length; i++) {
        final t = out[i];
        if (t.role != loc.role || t.attachments.isNotEmpty) continue;
        final tText = t.text.trim();
        final lText = loc.text.trim();
        final textMatch =
            tText == lText ||
            (tText.isEmpty && lText.isEmpty) ||
            (lText.isNotEmpty && tText.contains(lText)) ||
            (tText.isNotEmpty && lText.contains(tText));
        if (!textMatch &&
            !(lText.isEmpty && loc.attachments.isNotEmpty) &&
            !(_isNovaImagePlaceholderText(tText) && loc.attachments.isNotEmpty))
          continue;
        if (!_novaMsgNearTime(t.createdAt, loc.createdAt)) continue;
        idx = i;
        break;
      }
      if (idx < 0) continue;
      out[idx] = out[idx].copyWith(
        attachments: loc.attachments,
        payload: loc.payload ?? out[idx].payload,
        kind: loc.kind != 'TEXT' ? loc.kind : out[idx].kind,
      );
    }
    return out;
  }

  Future<List<NativeNovaMessage>> _applyViewSinceFilter(
    List<NativeNovaMessage> msgs,
  ) async {
    if (msgs.isEmpty || session.userId <= 0) return msgs;
    final storage = await NovaWebStorage.load(session.userId);
    final raw = (storage['dunes_nova_view_since'] ?? '').trim();
    if (raw.isEmpty) return msgs;
    final since = DateTime.tryParse(raw);
    if (since == null) return msgs;
    final threshold = since.subtract(const Duration(seconds: 5));
    final filtered = msgs
        .where((m) {
          final at = m.createdAt;
          if (at == null) return true;
          return !at.isBefore(threshold);
        })
        .toList(growable: false);
    // 对齐 WebView filterNovaViewMessages：view-since 生效时，过滤为空则视为新对话空白页。
    return filtered;
  }

  Future<List<NativeNovaMessage>> _loadPersistedSessionMessages(
    int conversationId,
  ) async {
    if (conversationId <= 0 || session.userId <= 0)
      return const <NativeNovaMessage>[];
    final storage = await NovaWebStorage.load(session.userId);
    final raw = storage['dunes_nova_msgs_$conversationId'];
    if (raw == null || raw.isEmpty) return const <NativeNovaMessage>[];
    try {
      final items = jsonDecode(raw);
      if (items is! List) return const <NativeNovaMessage>[];
      final out = <NativeNovaMessage>[];
      for (final item in items) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        var attachments = <NovaMessageAttachment>[];
        final payloadRaw = map['payload'];
        final metadataRaw = map['metadata'];
        Map<String, dynamic>? payload;
        if (payloadRaw is Map) {
          payload = Map<String, dynamic>.from(payloadRaw);
        } else if (metadataRaw is Map) {
          payload = Map<String, dynamic>.from(metadataRaw);
        }
        final attList = map['attachments'] ?? payload?['attachments'];
        if (attList is List) {
          for (final a in attList) {
            if (a is Map)
              attachments.add(
                NovaMessageAttachment.fromJson(Map<String, dynamic>.from(a)),
              );
          }
        }
        final kind = (map['kind'] ?? 'TEXT').toString().toUpperCase();
        if (attachments.isEmpty && payload != null) {
          attachments.addAll(_attachmentsFromPayload(payload, kind));
        }
        attachments = dedupeNovaMessageAttachments(attachments);
        final role = (map['role'] ?? 'user').toString().toLowerCase();
        final text = (map['bodyText'] ?? map['content'] ?? '').toString();
        final streaming = map['streaming'] == true;
        final thinkText = (map['thinkText'] ?? '').toString();
        final thinkStatus = (map['thinkStatus'] ?? '').toString();
        final isPendingAssistant = streaming && role == 'assistant';
        if (isPendingAssistant && text.trim().isEmpty && !isStreamInFlight)
          continue;
        if (text.isEmpty &&
            attachments.isEmpty &&
            kind == 'TEXT' &&
            !isPendingAssistant)
          continue;
        out.add(
          NativeNovaMessage(
            id: (map['id'] as num?)?.toInt() ?? 0,
            role: role == 'assistant' ? 'assistant' : 'user',
            text: text,
            createdAt: parseNovaDateTime(map['createdAt'] ?? map['created_at']),
            kind: kind,
            attachments: attachments,
            payload: payload,
            thinkText: thinkText,
            thinkStatus: thinkStatus,
            streaming: streaming,
          ),
        );
      }
      return sortNovaMessages(out);
    } catch (_) {
      return const <NativeNovaMessage>[];
    }
  }

  List<NativeNovaMessage> _dedupeNovaHistory(List<NativeNovaMessage> items) =>
      dedupeNovaHistoryMessages(items);

  NativeNovaMessage _mergeNovaHistoryById(
    NativeNovaMessage base,
    NativeNovaMessage incoming,
  ) {
    if (base.role == 'user' &&
        incoming.role == 'user' &&
        isNovaPrdDisplayAndPromptPair(base.text, incoming.text)) {
      return preferNovaPrdUserBubble(base, incoming);
    }
    final preferIncoming =
        novaHistoryRichness(incoming) > novaHistoryRichness(base);
    final rich = preferIncoming ? incoming : base;
    final plain = preferIncoming ? base : incoming;
    var role = rich.role;
    if (base.role != incoming.role &&
        (base.role == 'user' || incoming.role == 'user')) {
      role = 'user';
    }
    return rich.copyWith(
      role: role,
      text: rich.text.trim().isNotEmpty ? rich.text : plain.text,
      attachments: rich.attachments.isNotEmpty
          ? rich.attachments
          : plain.attachments,
      payload: rich.payload ?? plain.payload,
      kind: rich.kind != 'TEXT' ? rich.kind : plain.kind,
      thinkText: rich.thinkText.trim().isNotEmpty
          ? rich.thinkText
          : plain.thinkText,
      thinkStatus: rich.thinkStatus.isNotEmpty
          ? rich.thinkStatus
          : plain.thinkStatus,
    );
  }

  List<Map<String, dynamic>> _dedupeNovaTurns(
    List<Map<String, dynamic>> turns,
  ) {
    final seen = <String>{};
    final sorted = [...turns];
    sorted.sort((a, b) {
      final atA =
          parseNovaDateTime(_novaTurnAt(a)) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final atB =
          parseNovaDateTime(_novaTurnAt(b)) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return atA.compareTo(atB);
    });
    final out = <Map<String, dynamic>>[];
    for (final t in sorted) {
      final key = [
        _novaTurnConvId(t),
        _novaTurnMessageId(t),
        _novaTurnUserText(t),
        _novaTurnAssistantText(t).isNotEmpty
            ? _novaTurnAssistantText(t)
            : _novaTurnPreviewText(t),
        _novaTurnAt(t),
      ].join('\x1e');
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(t);
    }
    return out;
  }

  String _novaTurnAt(Map<String, dynamic> turn) =>
      (turn['lastMessageAt'] ??
              turn['last_message_at'] ??
              turn['createdAt'] ??
              turn['created_at'] ??
              '')
          .toString();

  int _novaTurnConvId(Map<String, dynamic> turn) =>
      (turn['conversationId'] as num?)?.toInt() ??
      (turn['conversation_id'] as num?)?.toInt() ??
      0;

  int _novaTurnMessageId(Map<String, dynamic> turn) =>
      (turn['messageId'] as num?)?.toInt() ??
      (turn['message_id'] as num?)?.toInt() ??
      0;

  String _novaTurnUserText(Map<String, dynamic> turn) =>
      (turn['userMessage'] ??
              turn['user_message'] ??
              turn['prompt'] ??
              turn['question'] ??
              turn['userText'] ??
              '')
          .toString()
          .trim();

  String _novaTurnAssistantText(Map<String, dynamic> turn) =>
      (turn['assistantMessage'] ??
              turn['assistant_message'] ??
              turn['answer'] ??
              turn['response'] ??
              turn['assistantText'] ??
              '')
          .toString()
          .trim();

  String _novaTurnPreviewText(Map<String, dynamic> turn) =>
      (turn['lastMessagePreview'] ??
              turn['last_message_preview'] ??
              turn['preview'] ??
              '')
          .toString()
          .trim();

  String _novaTurnTitleText(Map<String, dynamic> turn) =>
      (turn['title'] ?? turn['name'] ?? turn['subject'] ?? '')
          .toString()
          .trim();

  List<NativeNovaMessage> _novaMsgsFromTurns(
    List<Map<String, dynamic>> turns,
    int conversationId,
  ) {
    final out = <NativeNovaMessage>[];
    final usedMsgIds = <int>{};

    int allocMsgId(int seed, int fallbackSeed) {
      var id = seed > 0 ? seed : fallbackSeed;
      if (id <= 0) id = DateTime.now().millisecondsSinceEpoch;
      while (usedMsgIds.contains(id)) {
        id += 1;
      }
      usedMsgIds.add(id);
      return id;
    }

    for (var idx = 0; idx < turns.length; idx++) {
      final t = turns[idx];
      final at = parseNovaDateTime(_novaTurnAt(t));
      final turnMid = _novaTurnMessageId(t);
      final fallbackBase =
          (conversationId > 0 ? conversationId : 1) * 1000000 + (idx * 10 + 1);
      final userMsgId = allocMsgId(turnMid, fallbackBase);
      final aiMsgId = allocMsgId(turnMid > 0 ? turnMid + 1 : 0, userMsgId + 1);

      var userText = _novaTurnUserText(t);
      if (userText.isEmpty) userText = _novaTurnTitleText(t);
      Map<String, dynamic>? userPayload;
      final payloadRaw =
          t['userPayload'] ??
          t['userMetadata'] ??
          t['user_payload'] ??
          t['metadata'];
      if (payloadRaw is Map) {
        userPayload = Map<String, dynamic>.from(payloadRaw);
      }
      var attachments = _parseAttachmentsFromRaw(
        const <String, dynamic>{},
        userPayload,
        'TEXT',
      );
      var userKind = 'TEXT';
      if (attachments.isNotEmpty) {
        final allImages = attachments.every(_attachmentIsImage);
        if (allImages &&
            (userText.isEmpty || _isNovaImagePlaceholderText(userText))) {
          userKind = 'IMAGE';
        }
      }
      if (userText.isNotEmpty || attachments.isNotEmpty) {
        final userAt = at ?? DateTime.now();
        out.add(
          NativeNovaMessage(
            id: userMsgId,
            role: 'user',
            text: userText,
            createdAt: userAt,
            kind: userKind,
            attachments: attachments,
            payload: userPayload,
          ),
        );
      }

      var aiText = _novaTurnAssistantText(t);
      if (aiText.isEmpty) {
        final preview = _novaTurnPreviewText(t);
        if (preview.isNotEmpty && preview != userText) aiText = preview;
      }
      if (aiText.isNotEmpty) {
        final userAt = at ?? DateTime.now();
        final aiAt = userText.isNotEmpty || attachments.isNotEmpty
            ? userAt.add(const Duration(milliseconds: 1))
            : userAt;
        out.add(
          NativeNovaMessage(
            id: aiMsgId,
            role: 'assistant',
            text: aiText,
            createdAt: aiAt,
            kind: 'AI_ASSISTANT',
          ),
        );
      }
    }

    return sortNovaMessages(out);
  }

  Future<List<Map<String, dynamic>>> _fetchAllTurnsForConversation(
    int conversationId, {
    int pageSize = 100,
  }) async {
    final all = <Map<String, dynamic>>[];
    var before = '';
    for (var i = 0; i < 15; i++) {
      final rows = await _fetchTurnRows(
        pageSize,
        before: before,
        conversationId: conversationId,
      );
      if (rows.isEmpty) break;
      all.addAll(rows);
      if (rows.length < pageSize) break;
      final oldestAt =
          (rows.last['lastMessageAt'] ?? rows.last['createdAt'] ?? '')
              .toString();
      if (oldestAt.isEmpty || oldestAt == before) break;
      before = oldestAt;
    }
    return all;
  }

  Future<List<Map<String, dynamic>>> _fetchTurnRows(
    int size, {
    String before = '',
    int? conversationId,
  }) async {
    final convQ = conversationId != null && conversationId > 0
        ? '&conversationId=$conversationId'
        : '';
    final beforeQ = before.trim().isEmpty
        ? ''
        : '&before=${Uri.encodeQueryComponent(before.trim())}';
    try {
      final resp = await _client.get(
        _dunesUri('/ai/history/turns?size=$size$beforeQ$convQ'),
        headers: _dunesHeaders,
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final rows = _extractTurns(_decode(resp.body));
        if (rows.isNotEmpty) {
          return conversationId != null && conversationId > 0
              ? _filterTurnsForConversation(rows, conversationId)
              : rows;
        }
      }
    } catch (_) {}
    try {
      final resp = await _client.get(
        _dunesUri('/ai/history?view=turns&size=$size$beforeQ$convQ'),
        headers: _dunesHeaders,
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final rows = _extractTurns(_decode(resp.body));
        return conversationId != null && conversationId > 0
            ? _filterTurnsForConversation(rows, conversationId)
            : rows;
      }
    } catch (_) {}
    return const <Map<String, dynamic>>[];
  }

  /// 防止 history/turns 未按 conversationId 过滤时把其它会话拼进当前窗口。
  List<Map<String, dynamic>> _filterTurnsForConversation(
    List<Map<String, dynamic>> turns,
    int conversationId,
  ) {
    if (conversationId <= 0 || turns.isEmpty) return turns;
    final matched = <Map<String, dynamic>>[];
    var tagged = 0;
    for (final t in turns) {
      final cid =
          (t['conversationId'] as num?)?.toInt() ??
          (t['imConversationId'] as num?)?.toInt() ??
          (t['conversation_id'] as num?)?.toInt() ??
          0;
      if (cid > 0) {
        tagged += 1;
        if (cid == conversationId) matched.add(t);
      }
    }
    // 全部无 conversationId 字段时保持原样（兼容旧数据）。
    if (tagged == 0) return turns;
    return matched;
  }

  Future<void> persistSession(
    int conversationId,
    List<NativeNovaMessage> messages,
  ) => _persistSessionMessages(conversationId, messages);

  List<NativeNovaMessage> _stripIncompleteStreamingMessages(
    List<NativeNovaMessage> messages,
  ) {
    return messages
        .where(
          (m) =>
              !(m.role == 'assistant' &&
                  m.streaming &&
                  m.text.trim().isEmpty &&
                  m.thinkStatus.trim().isEmpty),
        )
        .toList();
  }

  /// 离开页面后流中断时，清掉会话缓存里的半成品 assistant 气泡。
  Future<void> stripStreamingFromSession(int conversationId) async {
    if (conversationId <= 0 || session.userId <= 0) return;
    final local = await _loadPersistedSessionMessages(conversationId);
    final cleaned = _stripIncompleteStreamingMessages(local);
    if (cleaned.length == local.length) return;
    if (cleaned.isEmpty) {
      await NovaWebStorage.removeKeys(session.userId, [
        'dunes_nova_msgs_$conversationId',
      ]);
      return;
    }
    await _persistSessionMessages(conversationId, cleaned);
  }

  /// 流式结束（含后台）：把最终 assistant 正文写入 `dunes_nova_msgs_*`。
  Future<void> commitAssistantReplyToSession(
    int conversationId, {
    required String replyText,
    String thinkText = '',
  }) async {
    final text = replyText.trim();
    if (conversationId <= 0 || text.isEmpty) return;
    var rows = _stripIncompleteStreamingMessages(
      await _loadPersistedSessionMessages(conversationId),
    );
    for (var i = rows.length - 1; i >= 0; i--) {
      if (rows[i].role == 'user' && rows[i].text.trim() == text) {
        if (kDebugMode) {
          debugPrint(
            '[NativeNova] skip echo assistant in session conv=$conversationId',
          );
        }
        return;
      }
    }
    if (rows.any(
      (m) => m.role == 'assistant' && !m.streaming && m.text.trim() == text,
    )) {
      return;
    }
    var replaced = false;
    for (var i = rows.length - 1; i >= 0; i--) {
      final m = rows[i];
      if (m.role == 'assistant' && (m.streaming || m.text.trim().isEmpty)) {
        rows[i] = m.copyWith(
          text: text,
          thinkText: thinkText.isNotEmpty ? thinkText : m.thinkText,
          streaming: false,
          thinkStatus:
              (thinkText.isNotEmpty ? thinkText : m.thinkText).trim().isNotEmpty
              ? '已完成思考'
              : m.thinkStatus,
          kind: 'AI_ASSISTANT',
        );
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      rows.add(
        NativeNovaMessage(
          id: DateTime.now().millisecondsSinceEpoch,
          role: 'assistant',
          text: text,
          thinkText: thinkText,
          createdAt: DateTime.now(),
          kind: 'AI_ASSISTANT',
        ),
      );
    }
    await _persistSessionMessages(conversationId, rows);
    await flushConvToLocalHistory(conversationId, rows);
  }

  DateTime _assistantCreatedAt(int conversationId) {
    final userAt = _userMessageAtByConv[conversationId];
    if (userAt != null) return userAt.add(const Duration(seconds: 2));
    return DateTime.now();
  }

  Future<void> _upsertLocalSessionMessage(
    int conversationId,
    NativeNovaMessage message,
  ) async {
    if (conversationId <= 0 ||
        message.text.trim().isEmpty && message.attachments.isEmpty)
      return;
    var rows = await _loadPersistedSessionMessages(conversationId);
    final idx = rows.indexWhere((m) => m.id == message.id);
    if (idx >= 0) {
      rows[idx] = message;
    } else {
      rows.add(message);
    }
    await _persistSessionMessages(conversationId, sortNovaMessages(rows));
  }

  /// 对齐 WebView `persistNovaUserMessage`：先落库用户提问，再发起流式生成。
  Future<int> persistUserMessage({
    required int conversationId,
    required int messageId,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    final text = content.trim();
    if (conversationId <= 0 ||
        (text.isEmpty && (metadata == null || metadata.isEmpty))) {
      return conversationId;
    }
    final hasAttachments =
        metadata != null &&
        metadata['attachments'] is List &&
        (metadata['attachments'] as List).isNotEmpty;
    final createdAt = messageId > 0
        ? DateTime.fromMillisecondsSinceEpoch(messageId)
        : DateTime.now();
    final saved = await _saveLocalMessage(
      conversationId,
      role: 'user',
      content: text.isNotEmpty ? text : (hasAttachments ? '[附件消息]' : text),
      kind: 'TEXT',
      metadata: metadata,
      messageId: messageId > 0 ? messageId : null,
      createdAt: createdAt,
      requireSuccess: true,
    );
    if (!saved) {
      throw Exception('用户消息落库失败，请稍后重试');
    }
    _userMessageAtByConv[conversationId] = createdAt;
    await _upsertLocalSessionMessage(
      conversationId,
      NativeNovaMessage(
        id: messageId > 0 ? messageId : createdAt.millisecondsSinceEpoch,
        role: 'user',
        text: text.isNotEmpty ? text : (hasAttachments ? '[附件消息]' : text),
        createdAt: createdAt,
        kind: 'TEXT',
        payload: metadata,
        attachments: hasAttachments
            ? _parseAttachmentsFromRaw(
                const <String, dynamic>{},
                metadata,
                'TEXT',
              )
            : const <NovaMessageAttachment>[],
      ),
    );
    return conversationId;
  }

  Future<void> persistAssistantAttachmentTurn({
    required int conversationId,
    required int assistantMessageId,
    required String displayText,
    required List<Map<String, dynamic>> attachments,
  }) async {
    if (conversationId <= 0 || displayText.trim().isEmpty) return;
    await _saveLocalMessage(
      conversationId,
      role: 'assistant',
      content: displayText.trim(),
      kind: 'TEXT',
      metadata: <String, dynamic>{'attachments': attachments},
      messageId: assistantMessageId > 0 ? assistantMessageId : null,
      createdAt: assistantMessageId > 0
          ? DateTime.fromMillisecondsSinceEpoch(assistantMessageId)
          : null,
    );
  }

  /// 对齐 WebView `persistNovaAssistantReply`：assistant 写入 messages/local 并 upsert history/turns。
  Future<void> persistAssistantTurn({
    required int conversationId,
    required int messageId,
    required String userMessage,
    required String assistantMessage,
    String thinkText = '',
    Map<String, dynamic>? userPayload,
    List<NativeNovaMessage> existingMessages = const <NativeNovaMessage>[],
  }) async {
    final user = userMessage.trim();
    final reply = stripHermesProgressLines(assistantMessage.trim());
    if (conversationId <= 0 || reply.isEmpty) return;
    if (reply == user) {
      if (kDebugMode) {
        debugPrint('[NativeNova] skip echo assistant conv=$conversationId');
      }
      return;
    }

    final serverRows = existingMessages
        .where((m) => !m.isWelcome)
        .toList(growable: false);
    final localRows = await _loadPersistedSessionMessages(conversationId);
    final knownRows = <NativeNovaMessage>[...serverRows, ...localRows];
    final hasAssistant = knownRows.any(
      (m) => m.role == 'assistant' && m.text.trim() == reply,
    );

    var activeConvId = conversationId;
    if (!hasAssistant) {
      if (kDebugMode) {
        debugPrint(
          '[NativeNova] persist assistant message conv=$conversationId len=${reply.length}',
        );
      }
      await _saveLocalMessage(
        activeConvId,
        role: 'assistant',
        content: reply,
        kind: 'AI_ASSISTANT',
        messageId: messageId > 0 ? messageId + 1 : null,
        createdAt: _assistantCreatedAt(activeConvId),
      );
    }
    await commitAssistantReplyToSession(
      activeConvId,
      replyText: reply,
      thinkText: thinkText,
    );

    var effectiveUser = user;
    var effectiveMessageId = messageId;
    if (effectiveUser.isEmpty || effectiveMessageId <= 0) {
      final recovered = await resolveLatestUserMessage(
        activeConvId,
        fallbackText: user,
        fallbackId: messageId,
      );
      if (recovered != null) {
        effectiveUser = recovered.text.trim();
        if (effectiveMessageId <= 0) effectiveMessageId = recovered.id;
      }
    }
    if (effectiveUser.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[NativeNova] skip history sync: no user conv=$activeConvId',
        );
      }
      return;
    }

    final lastMessageAt = resolveHistoryTurnLastMessageAt(
      knownRows,
      assistantReply: reply,
    );

    NativeNovaMessage? userRow;
    for (var i = knownRows.length - 1; i >= 0; i--) {
      final m = knownRows[i];
      if (m.role != 'user') continue;
      if (effectiveMessageId > 0 && m.id == effectiveMessageId) {
        userRow = m;
        break;
      }
      if (m.text.trim() == effectiveUser) {
        userRow = m;
        break;
      }
    }
    final payloadForHistory = userRow != null
        ? historyUserPayloadFromMessage(userRow, fallback: userPayload)
        : historyUserPayloadFromParts(
            payload: userPayload,
            kind: 'TEXT',
          );

    await registerHistoryTurn(
      conversationId: activeConvId,
      messageId: effectiveMessageId > 0
          ? effectiveMessageId
          : DateTime.now().millisecondsSinceEpoch,
      userMessage: effectiveUser,
      assistantMessage: reply,
      lastMessagePreview: reply.length > 200 ? reply.substring(0, 200) : reply,
      lastMessageAt: lastMessageAt,
      userPayload: payloadForHistory,
    );

    // 直连 completions / PRD 等场景 IM 不会自动落库；统一补写一轮，
    // 避免回看只剩审计表或本地气泡。
    unawaited(
      persistImAssistantTurn(
        conversationId: activeConvId,
        userMessage: effectiveUser,
        assistantMessage: reply,
        userPayload: payloadForHistory,
      ),
    );
  }

  /// 将已完成的多模态轮次写入 IM（不调用模型）。
  Future<void> persistImAssistantTurn({
    required int conversationId,
    required String userMessage,
    required String assistantMessage,
    Map<String, dynamic>? userPayload,
    String kind = 'TEXT',
  }) async {
    if (conversationId <= 0) return;
    final user = userMessage.trim();
    final assist = stripHermesProgressLines(assistantMessage.trim());
    if (user.isEmpty && assist.isEmpty) return;
    try {
      final resp = await _client.post(
        _dunesUri('/ai/assistant/turns'),
        headers: _dunesHeaders,
        body: jsonEncode(<String, dynamic>{
          'conversationId': conversationId,
          'userMessage': user,
          'assistantMessage': assist,
          'kind': kind,
          if (userPayload != null && userPayload.isNotEmpty)
            'userPayload': userPayload,
        }),
      );
      if (kDebugMode && (resp.statusCode < 200 || resp.statusCode >= 300)) {
        debugPrint(
          '[NativeNova] persist IM turn failed conv=$conversationId '
          'status=${resp.statusCode} body=${resp.body}',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[NativeNova] persist IM turn error conv=$conversationId: $e');
      }
    }
  }

  /// 后台生成完成时，若服务端/本地尚未形成正式消息，使用草稿内容补做一次持久化。
  Future<void> finalizeBackgroundCompletion(
    int conversationId, {
    String userText = '',
    String assistantText = '',
    String thinkText = '',
    List<NativeNovaMessage> existingMessages = const <NativeNovaMessage>[],
  }) async {
    final trimmedUser = userText.trim();
    final trimmedReply = assistantText.trim();
    if (conversationId <= 0 || (trimmedUser.isEmpty && trimmedReply.isEmpty))
      return;

    final serverRows = existingMessages
        .where((m) => !m.isWelcome)
        .toList(growable: false);
    final trackedUserAt = _userMessageAtByConv[conversationId];
    final hasUser =
        trimmedUser.isNotEmpty &&
        (serverRows.any(
              (m) => m.role == 'user' && m.text.trim() == trimmedUser,
            ) ||
            trackedUserAt != null);
    final hasAssistant =
        trimmedReply.isNotEmpty &&
        serverRows.any(
          (m) => m.role == 'assistant' && m.text.trim() == trimmedReply,
        );

    final activeConvId = conversationId;
    if (!hasUser && trimmedUser.isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[NativeNova] finalize persist missing user conv=$conversationId',
        );
      }
      final recovered = await resolveLatestUserMessage(
        conversationId,
        fallbackText: trimmedUser,
      );
      final userId = recovered?.id ?? 0;
      final userAt =
          trackedUserAt ??
          recovered?.createdAt ??
          (userId > 0
              ? DateTime.fromMillisecondsSinceEpoch(userId)
              : DateTime.now());
      await _saveLocalMessage(
        activeConvId,
        role: 'user',
        content: trimmedUser,
        kind: 'TEXT',
        messageId: userId > 0 ? userId : null,
        createdAt: userAt,
      );
      _userMessageAtByConv[conversationId] = userAt;
    }
    if (!hasAssistant &&
        trimmedReply.isNotEmpty &&
        trimmedReply != trimmedUser) {
      if (kDebugMode) {
        debugPrint(
          '[NativeNova] finalize persist missing assistant conv=$conversationId',
        );
      }
      await _saveLocalMessage(
        activeConvId,
        role: 'assistant',
        content: trimmedReply,
        kind: 'AI_ASSISTANT',
        messageId: _userMessageIdFromRows(serverRows) > 0
            ? _userMessageIdFromRows(serverRows) + 1
            : null,
        createdAt: _assistantCreatedAt(activeConvId),
      );
    }
    if (trimmedReply.isNotEmpty && trimmedReply != trimmedUser) {
      await commitAssistantReplyToSession(
        activeConvId,
        replyText: trimmedReply,
        thinkText: thinkText,
      );
    }
  }

  int _userMessageIdFromRows(List<NativeNovaMessage> rows) {
    for (var i = rows.length - 1; i >= 0; i--) {
      if (rows[i].role == 'user' && rows[i].id > 0) return rows[i].id;
    }
    return 0;
  }

  Future<NativeNovaMessage?> resolveLatestUserMessage(
    int conversationId, {
    String fallbackText = '',
    int fallbackId = 0,
  }) async {
    final local = await _loadPersistedSessionMessages(conversationId);
    for (var i = local.length - 1; i >= 0; i--) {
      final row = local[i];
      if (row.role == 'user' && row.text.trim().isNotEmpty) return row;
    }
    final storage = await NovaWebStorage.load(session.userId);
    final draft = readNovaStreamDraftFromStorage(storage, conversationId);
    final text = (draft?.userText ?? fallbackText).trim();
    if (text.isEmpty) return null;
    return NativeNovaMessage(
      id: draft?.afterMessageId ?? fallbackId,
      role: 'user',
      text: text,
      createdAt:
          _userMessageAtByConv[conversationId] ??
          (fallbackId > 0
              ? DateTime.fromMillisecondsSinceEpoch(fallbackId)
              : DateTime.now()),
    );
  }

  Future<void> _persistSessionMessages(
    int conversationId,
    List<NativeNovaMessage> messages,
  ) async {
    final uid = session.userId;
    if (uid <= 0 || conversationId <= 0 || messages.isEmpty) return;
    final rows = _stripIncompleteStreamingMessages(messages)
        .where((m) => !m.isWelcome)
        .map(
          (m) => <String, dynamic>{
            'id': m.id,
            'role': m.role,
            'kind': m.streaming && m.role == 'assistant'
                ? 'AI_ASSISTANT'
                : m.kind,
            'bodyText': m.text,
            'content': m.text,
            'createdAt': (m.createdAt ?? DateTime.now())
                .toUtc()
                .toIso8601String(),
            if (m.streaming) 'streaming': true,
            if (m.thinkText.isNotEmpty) 'thinkText': m.thinkText,
            if (m.thinkStatus.isNotEmpty) 'thinkStatus': m.thinkStatus,
            if (m.payload != null)
              'payload': m.payload
            else if (m.attachments.isNotEmpty)
              'payload': <String, dynamic>{
                'attachments': m.attachments
                    .map((a) => a.toJson())
                    .toList(growable: false),
              },
            if (m.attachments.isNotEmpty)
              'attachments': m.attachments
                  .map((a) => a.toJson())
                  .toList(growable: false),
          },
        )
        .toList(growable: false);
    if (rows.isEmpty) return;
    await persistNovaSessionMessages(
      userId: uid,
      conversationId: conversationId,
      messages: rows,
    );
  }

  int _novaSenderUid(Map<String, dynamic> raw, Map<String, dynamic> sender) {
    if (sender['userId'] != null) return (sender['userId'] as num).toInt();
    return (raw['senderUserId'] as num?)?.toInt() ??
        (raw['sender_user_id'] as num?)?.toInt() ??
        (raw['userId'] as num?)?.toInt() ??
        0;
  }

  String _novaMessageRole(
    Map<String, dynamic> raw, {
    required String kind,
    required int senderUid,
    required String senderName,
  }) {
    final rawRole = (raw['role'] ?? '').toString().toLowerCase();
    if (rawRole == 'user') return 'user';
    if (rawRole == 'assistant' || rawRole == 'system') return 'assistant';
    if (kind == 'AI_ASSISTANT' || kind == 'AI_TOOL_CALL') return 'assistant';

    const userKinds = {'TEXT', 'IMAGE', 'FILE', 'AUDIO'};
    if (senderUid > 0 && userKinds.contains(kind)) return 'user';

    if (senderName == '云枢' || senderName == 'NOVA') return 'assistant';
    if (kind.contains('AI')) return 'assistant';

    if (userKinds.contains(kind)) return 'user';
    return senderUid > 0 ? 'user' : 'assistant';
  }

  List<Map<String, dynamic>> _filterNovaMsgsForSelf(
    List<Map<String, dynamic>> rows,
  ) {
    final self = session.userId;
    if (self <= 0) return rows;
    return rows
        .where((m) {
          final kind = (m['kind'] ?? 'TEXT').toString().toUpperCase();
          if (kind == 'AI_ASSISTANT' || kind == 'AI_TOOL_CALL') return true;
          final role = (m['role'] ?? '').toString().toLowerCase();
          if (role == 'assistant' || role == 'system') return true;
          if (role == 'user') return true;
          final sender = m['sender'] is Map ? m['sender'] as Map : const {};
          final sid =
              (sender['userId'] as num?)?.toInt() ??
              (m['senderUserId'] as num?)?.toInt() ??
              (m['userId'] as num?)?.toInt() ??
              0;
          return sid <= 0 || sid == self;
        })
        .toList(growable: false);
  }

  NativeNovaMessage _mapRawMessage(Map<String, dynamic> raw) {
    final kind = (raw['kind'] ?? 'TEXT').toString().toUpperCase();
    final sender = raw['sender'] is Map
        ? Map<String, dynamic>.from(raw['sender'] as Map)
        : <String, dynamic>{};
    final senderUid = _novaSenderUid(raw, sender);
    final senderName = (sender['displayName'] ?? raw['senderDisplayName'] ?? '')
        .toString()
        .trim();
    final role = _novaMessageRole(
      raw,
      kind: kind,
      senderUid: senderUid,
      senderName: senderName,
    );
    var text = (raw['bodyText'] ?? raw['content'] ?? '').toString();
    final payloadRaw = raw['payload'];
    final metadataRaw = raw['metadata'];
    Map<String, dynamic>? payload;
    if (payloadRaw is Map<String, dynamic>) {
      payload = payloadRaw;
    } else if (payloadRaw is Map) {
      payload = Map<String, dynamic>.from(payloadRaw);
    } else if (metadataRaw is Map<String, dynamic>) {
      payload = metadataRaw;
    } else if (metadataRaw is Map) {
      payload = Map<String, dynamic>.from(metadataRaw);
    }
    var effectiveKind = kind;
    final attachments = _parseAttachmentsFromRaw(raw, payload, kind);
    if (effectiveKind == 'TEXT' &&
        attachments.isNotEmpty &&
        attachments.every(_attachmentIsImage) &&
        (text.isEmpty || _isNovaImagePlaceholderText(text))) {
      effectiveKind = 'IMAGE';
    }
    var durationSec = 0;
    if (effectiveKind == 'AUDIO' && payload != null) {
      durationSec =
          (payload['durationSec'] as num?)?.toInt() ??
          int.tryParse(text.replaceAll(RegExp(r'\D'), '')) ??
          1;
      if (text.isEmpty) text = "[语音] ${durationSec}s";
    }
    if (effectiveKind == 'IMAGE' &&
        (text.isEmpty || _isNovaImagePlaceholderText(text))) {
      text =
          (payload?['fileName'] ??
                  (attachments.isNotEmpty
                      ? attachments.first.fileName
                      : null) ??
                  '图片')
              .toString();
    }
    if (effectiveKind == 'FILE' && text.isEmpty)
      text = (payload?['fileName'] ?? '文件').toString();
    if (role == 'assistant') {
      text = stripHermesProgressLines(text);
    }
    return NativeNovaMessage(
      id: (raw['id'] as num?)?.toInt() ?? 0,
      role: role,
      text: text,
      createdAt: parseNovaDateTime(raw['createdAt'] ?? raw['created_at']),
      kind: effectiveKind,
      attachments: attachments,
      durationSec: durationSec,
      payload: payload,
    );
  }

  List<NovaMessageAttachment> _parseAttachmentsFromRaw(
    Map<String, dynamic> raw,
    Map<String, dynamic>? payload,
    String kind,
  ) {
    final out = <NovaMessageAttachment>[];
    // 只读一处附件列表，避免 raw/payload 同含 attachments 时翻倍。
    List? source;
    final top = raw['attachments'];
    if (top is List && top.isNotEmpty) {
      source = top;
    } else if (!identical(raw, payload)) {
      final nested = payload?['attachments'];
      if (nested is List && nested.isNotEmpty) source = nested;
    }
    if (source is List) {
      for (final row in source) {
        if (row is Map) {
          out.add(
            NovaMessageAttachment.fromJson(Map<String, dynamic>.from(row)),
          );
        }
      }
    }
    if (out.isEmpty) {
      out.addAll(_attachmentsFromPayload(payload, kind));
    }
    return dedupeNovaMessageAttachments(out);
  }

  bool _attachmentIsImage(NovaMessageAttachment a) {
    if (a.kind.toUpperCase() == 'IMAGE') return true;
    if (a.mimeType.startsWith('image/')) return true;
    final ext = a.fileName.split('.').last.toLowerCase();
    return ext == 'jpg' ||
        ext == 'jpeg' ||
        ext == 'png' ||
        ext == 'gif' ||
        ext == 'webp' ||
        ext == 'heic';
  }

  bool _isNovaImagePlaceholderText(String text) {
    final t = text.trim();
    return t == '[图片]' || t.startsWith('[图片]');
  }

  List<NovaMessageAttachment> _attachmentsFromPayload(
    Map<String, dynamic>? payload,
    String kind,
  ) {
    if (payload == null) return const <NovaMessageAttachment>[];
    final list = payload['attachments'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map(
            (e) => NovaMessageAttachment.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
    }
    if (kind == 'IMAGE' || kind == 'FILE' || kind == 'AUDIO') {
      if (payload['url'] != null || payload['objectKey'] != null) {
        return [
          NovaMessageAttachment.fromJson(<String, dynamic>{
            ...payload,
            'kind': kind,
          }),
        ];
      }
    }
    return const <NovaMessageAttachment>[];
  }

  bool _readBoolField(dynamic data, String key) {
    if (data is! Map) return false;
    return data[key] == true;
  }

  Future<String> resolveMediaUrl(
    String source, {
    String bucket = 'im-attachments',
  }) async {
    final trimmed = source.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    // 移动端走 API 代理，避免 presigned URL 指向 Docker 内网 MinIO 导致无法访问。
    return mediaProxyUrl(trimmed, bucket: bucket);
  }

  Future<String> fetchTextViaStorageProxy(
    String objectKey, {
    String bucket = 'im-attachments',
  }) async {
    final key = objectKey.trim();
    if (key.isEmpty) {
      throw Exception('文件路径无效');
    }
    final resp = await _client.get(
      Uri.parse(mediaProxyUrl(key, bucket: bucket)),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('读取失败（HTTP ${resp.statusCode}）');
    }
    if (resp.body.isEmpty) {
      throw Exception('文件内容为空');
    }
    return decodeHttpResponseText(
      resp.bodyBytes,
      contentType: resp.headers['content-type'] ?? '',
    );
  }

  Future<NovaHistoryPageResult> fetchHistoryTurns({
    int size = 20,
    String before = '',
  }) async {
    final beforeQ = before.trim().isEmpty
        ? ''
        : '&before=${Uri.encodeQueryComponent(before.trim())}';
    var turns = await _fetchTurnRows(size, before: before.trim());
    if (turns.isEmpty && before.trim().isEmpty) {
      try {
        final resp = await _client.get(
          _dunesUri('/ai/history/turns?size=$size$beforeQ'),
          headers: _dunesHeaders,
        );
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          turns = _extractTurns(_decode(resp.body));
        }
      } catch (_) {}
    }
    final items = turns
        .map(_mapHistoryTurn)
        .where((t) => t.conversationId > 0)
        .toList();
    return NovaHistoryPageResult(items: items, hasMore: turns.length >= size);
  }

  NovaHistoryTurn _mapHistoryTurn(Map<String, dynamic> raw) {
    final preview = novaTurnPreview(raw);
    return NovaHistoryTurn(
      conversationId: _turnConvId(raw),
      messageId:
          (raw['messageId'] as num?)?.toInt() ??
          (raw['message_id'] as num?)?.toInt() ??
          0,
      title: novaTurnTitle(raw),
      preview: preview,
      lastMessageAt: parseNovaDateTime(
        raw['lastMessageAt'] ??
            raw['last_message_at'] ??
            raw['createdAt'] ??
            raw['created_at'],
      ),
    );
  }

  void cancelActiveStream() {
    userStoppedStream = true;
    _streamClient?.close();
    _streamClient = null;
  }

  String get novaBizUserId {
    final stored = (session.novaLocalStorage?['dunes_nova_biz_user_id'] ?? '')
        .trim();
    if (stored.isNotEmpty) return stored;
    return 'dune_${session.userId}';
  }

  String get novaProfileSessionId => 'profile-$novaBizUserId';

  static const _contextTurnLimit = 20;

  String _chatSessionStorageKey(int conversationId) =>
      'dunes_nova_chat_session_$conversationId';

  String _summaryStorageKey(int conversationId) =>
      'dunes_nova_summary_$conversationId';

  /// 每个聊天窗口都有独立、持久化的 Nova 会话 UUID。不能使用用户级
  /// `profile-*`，否则不同窗口会被 Nova 服务端视为同一个上下文。
  Future<String> novaChatSessionId(int conversationId) async {
    if (conversationId <= 0) return '';
    final storage = await NovaWebStorage.load(session.userId);
    final key = _chatSessionStorageKey(conversationId);
    final existing = (storage[key] ?? '').trim();
    if (existing.isNotEmpty) return 'chat-$existing';

    final random = Random.secure();
    final groups = <String>[
      for (final length in const [8, 4, 4, 4, 12])
        List<String>.generate(
          length,
          (_) => random.nextInt(16).toRadixString(16),
        ).join(),
    ];
    final uuid = groups.join('-');
    await NovaWebStorage.merge(session.userId, {key: uuid});
    return 'chat-$uuid';
  }

  Future<void> persistNovaChatSessionId(
    int conversationId,
    String sessionId,
  ) async {
    final value = sessionId.trim();
    if (conversationId <= 0 || value.isEmpty || !value.startsWith('chat-')) {
      return;
    }
    await NovaWebStorage.merge(session.userId, {
      _chatSessionStorageKey(conversationId): value.substring('chat-'.length),
    });
  }

  String get asrModel =>
      (session.novaLocalStorage?['dunes_nova_asr_model'] ?? NovaConfig.asrModel)
          .trim();

  String imagePartTypeForModel(String model) {
    final stored =
        (session.novaLocalStorage?['dunes_nova_image_part_type'] ?? '').trim();
    if (stored == 'image_url' || stored == 'input_image') return stored;
    if (RegExp(r'gpt|nova_gpt', caseSensitive: false).hasMatch(model))
      return 'image_url';
    // 云枢 completions 仅支持 image_url / input_image，不再发送 type=image。
    return 'image_url';
  }

  Map<String, dynamic> _visionImagePart(String imagePartType, String dataUrl) {
    if (imagePartType == 'input_image') {
      return <String, dynamic>{
        'type': 'input_image',
        'input_image': <String, dynamic>{'url': dataUrl},
      };
    }
    return <String, dynamic>{
      'type': 'image_url',
      'image_url': <String, dynamic>{'url': dataUrl},
    };
  }

  Future<UploadedAttachment> uploadAttachment({
    required int conversationId,
    required Uint8List bytes,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(1);
    final req = http.MultipartRequest('POST', _dunesUri('/storage/upload'));
    req.headers['Authorization'] = 'Bearer ${session.token}';
    req.fields['bucket'] = 'im-attachments';
    req.fields['conversationId'] = '$conversationId';
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: fileName),
    );
    onProgress?.call(40);
    final streamed = await req.send();
    final bodyText = await streamed.stream.bytesToString();
    onProgress?.call(90);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception('上传失败: HTTP ${streamed.statusCode}');
    }
    final body = _decode(bodyText);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '上传失败').toString());
    }
    final data = body['data'];
    if (data is! Map<String, dynamic>) throw Exception('上传失败: 返回数据异常');
    final url = (data['url'] ?? '').toString();
    final objectKey = (data['objectKey'] ?? url).toString();
    final backend = (data['backend'] ?? '').toString();
    final accessUrl = resolvePublicAttachmentUrl(
      url: url,
      objectKey: objectKey,
      backend: backend,
    );
    onProgress?.call(100);
    return UploadedAttachment(
      url: accessUrl.isNotEmpty ? accessUrl : url,
      objectKey: objectKey,
    );
  }

  /// 当轮文件提问：上传到 Nova 抽文本缓存，返回 `attachment_id`（不进知识库）。
  Future<NovaChatAttachmentUpload> uploadNovaChatAttachment({
    required Uint8List bytes,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    final reject = novaChatAttachmentRejectReason(
      fileName: fileName,
      byteLength: bytes.length,
    );
    if (reject != null) throw Exception(reject);
    if (novaApiKey.isEmpty) {
      throw Exception('NOVA账号尚未就绪，请重新登录后再试');
    }
    onProgress?.call(5);
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$novaBase/v1/app/chat/attachments'),
    );
    req.headers.addAll(novaHeaders());
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: fileName),
    );
    onProgress?.call(35);
    final streamed = await _client.send(req);
    final bodyText = await streamed.stream.bytesToString();
    onProgress?.call(85);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception(_parseNovaHttpError(streamed.statusCode, bodyText));
    }
    final body = _decode(bodyText);
    if (body['success'] == false) {
      throw Exception(
        _friendlyChatAttachmentMessage(
          (body['message'] ?? '文件上传失败').toString(),
        ),
      );
    }
    final data = body['data'];
    if (data is! Map) {
      throw Exception('文件上传失败: 返回数据异常');
    }
    final map = Map<String, dynamic>.from(data);
    final id = (map['attachment_id'] ?? map['attachmentId'] ?? '')
        .toString()
        .trim();
    if (id.isEmpty) throw Exception('文件上传失败: 未返回 attachment_id');
    onProgress?.call(100);
    return NovaChatAttachmentUpload(
      attachmentId: id,
      fileName: (map['filename'] ?? fileName).toString(),
      chars: (map['chars'] as num?)?.toInt() ?? 0,
      truncated: map['truncated'] == true,
      preview: (map['preview'] ?? '').toString(),
      expiresAt: (map['expires_at'] as num?)?.toInt() ?? 0,
    );
  }

  String _friendlyChatAttachmentMessage(String raw) {
    final msg = raw.trim();
    final low = msg.toLowerCase();
    if (low.contains('file is required')) return '未选到文件，请重新选择';
    if (low.contains('too large') || low.contains('15mb')) {
      return '文件超过 15MB，请压缩后再试';
    }
    if (low.contains('unsupported format')) {
      return '暂不支持该格式，请转成 docx/xlsx/pdf/txt';
    }
    if (low.contains('no extractable text')) {
      return '未能从文件中提取文字，请换一份有文字的文件';
    }
    if (low.contains('no text layer')) {
      return '该 PDF 为扫描件，暂不支持 OCR，请换有文字层的 PDF';
    }
    if (low.contains('unauthorized')) return 'NOVA 登录已失效，请重新登录';
    return msg.isNotEmpty ? msg : '文件上传失败';
  }

  MediaType _audioMediaType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.mp3')) return MediaType('audio', 'mpeg');
    if (lower.endsWith('.m4a')) return MediaType('audio', 'mp4');
    return MediaType('audio', 'wav');
  }

  Future<String> transcribeAudio(Uint8List bytes, String fileName) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$novaBase/v1/audio/transcriptions'),
    );
    req.headers.addAll(novaHeaders());
    req.fields['model'] = asrModel;
    req.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
        contentType: _audioMediaType(fileName),
      ),
    );
    final streamed = await _client.send(req);
    final bodyText = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception(_parseNovaHttpError(streamed.statusCode, bodyText));
    }
    final body = _decode(bodyText);
    final data = body['data'];
    final candidates = <String?>[
      body['text']?.toString().trim(),
      body['transcript']?.toString().trim(),
      body['result']?.toString().trim(),
      if (data is String) data.trim(),
      if (data is Map)
        (data['text'] ?? data['transcript'] ?? data['result'])
            ?.toString()
            .trim(),
    ];
    for (final c in candidates) {
      if (c != null && c.isNotEmpty) return c;
    }
    throw Exception('语音识别未得到有效转写');
  }

  Map<String, String> novaHeaders([Map<String, String>? extra]) {
    final h = <String, String>{...?extra};
    if (novaApiKey.isNotEmpty) h['Authorization'] = 'Bearer $novaApiKey';
    return h;
  }

  Future<Uint8List> _resolveMultimodalFileBytes(
    NovaDraftAttachment attachment,
  ) async {
    if (attachment.bytes.isNotEmpty) return attachment.bytes;
    final payload = attachment.payload;
    if (payload == null) return attachment.bytes;
    for (final key in ['url', 'accessUrl', 'publicUrl', 'previewUrl']) {
      final raw = (payload[key] ?? '').toString().trim();
      if (!raw.startsWith('http://') && !raw.startsWith('https://')) continue;
      final resp = await _client.get(Uri.parse(raw));
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.bodyBytes.isNotEmpty) {
        return resp.bodyBytes;
      }
    }
    final objectKey = (payload['objectKey'] ?? '').toString().trim();
    if (objectKey.isNotEmpty) {
      final url = await resolveMediaUrl(objectKey);
      final resp = await _client.get(Uri.parse(url));
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.bodyBytes.isNotEmpty) {
        return resp.bodyBytes;
      }
    }
    return attachment.bytes;
  }

  Future<dynamic> buildMultimodalContent({
    required String text,
    required List<NovaDraftAttachment> attachments,
    String? model,
  }) async {
    final imagePartType = imagePartTypeForModel(model ?? selectedModel);
    final parts = <Map<String, dynamic>>[];
    final trimmed = text.trim();
    if (trimmed.isNotEmpty) {
      parts.add(<String, dynamic>{'type': 'text', 'text': trimmed});
    }
    for (final a in attachments) {
      if (!a.isImage) continue;
      // 对齐 admin-web / 旧 WebView：视觉部分始终走 data URL。
      var imageBytes = a.bytes;
      if (imageBytes.isEmpty) {
        imageBytes = await _resolveMultimodalFileBytes(a);
      }
      if (imageBytes.isEmpty) continue;
      final normalized = await normalizeImageForVision(
        imageBytes,
        fileName: a.fileName,
      );
      if (normalized.bytes.isEmpty) continue;
      final b64 = base64Encode(normalized.bytes);
      final dataUrl = 'data:${normalized.mimeType};base64,$b64';
      parts.add(_visionImagePart(imagePartType, dataUrl));
    }
    // 文档类走 attachment_ids，不再往 content 塞 type=file（Hermes 不接受）。
    if (parts.isEmpty) return '';
    if (parts.length == 1 && parts.first['type'] == 'text') {
      return parts.first['text'];
    }
    return parts;
  }

  List<String> collectNovaAttachmentIds(List<NovaDraftAttachment> attachments) {
    final out = <String>[];
    final seen = <String>{};
    for (final a in attachments) {
      if (a.isImage) continue;
      final id = (a.novaAttachmentId ?? '').trim();
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(id);
    }
    return out;
  }

  /// 构造独立聊天窗口的请求上下文：用户规则、旧消息摘要、最近 20 轮和本条提问。
  ///
  /// 历史只为模型理解本条提问，不能要求模型逐条回复；跨窗口的长期偏好仍由
  /// Hermes Memory 维护，不把其它窗口消息带入本次请求。
  Future<List<Map<String, dynamic>>> buildNovaChatMessages({
    required int conversationId,
    required dynamic latestContent,
  }) async {
    final out = <Map<String, dynamic>>[];
    final sys = _buildNovaUserSystemMessage();
    if (sys != null) out.add(sys);

    final cached = await _loadPersistedSessionMessages(conversationId);
    final previous = [...cached];
    final latestText = _extractUserPromptText(
      latestContent,
      displayText: latestContent is String ? latestContent : '',
    );
    if (previous.isNotEmpty &&
        previous.last.role == 'user' &&
        previous.last.text.trim() == latestText.trim()) {
      previous.removeLast();
    }

    final contextMessageLimit = _contextTurnLimit * 2;
    if (previous.length > contextMessageLimit) {
      final older = previous.sublist(0, previous.length - contextMessageLimit);
      final summary = _buildConversationSummary(older);
      if (summary.isNotEmpty) {
        await NovaWebStorage.merge(session.userId, {
          _summaryStorageKey(conversationId): summary,
        });
        out.add(<String, dynamic>{
          'role': 'system',
          'content':
              '以下是本聊天窗口较早对话的摘要，仅用于理解当前问题；'
              '请只回答最后一条用户消息，不要逐条回应摘要内容。\n$summary',
        });
      }
    } else {
      final storage = await NovaWebStorage.load(session.userId);
      final summary = (storage[_summaryStorageKey(conversationId)] ?? '')
          .trim();
      if (summary.isNotEmpty) {
        out.add(<String, dynamic>{
          'role': 'system',
          'content':
              '以下是本聊天窗口较早对话的摘要，仅用于理解当前问题；'
              '请只回答最后一条用户消息，不要逐条回应摘要内容。\n$summary',
        });
      }
    }

    final recent = previous.length > contextMessageLimit
        ? previous.sublist(previous.length - contextMessageLimit)
        : previous;
    for (final message in recent) {
      final text = message.text.trim();
      if (text.isEmpty) continue;
      out.add(<String, dynamic>{
        'role': message.role == 'assistant' ? 'assistant' : 'user',
        'content': text,
      });
    }
    final hasLatest =
        latestContent != null &&
        !(latestContent is String && latestContent.toString().trim().isEmpty);
    if (hasLatest)
      out.add(<String, dynamic>{'role': 'user', 'content': latestContent});
    return out;
  }

  String _buildConversationSummary(List<NativeNovaMessage> messages) {
    final lines = <String>[];
    for (final message in messages) {
      final text = message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;
      final clipped = text.length > 180 ? '${text.substring(0, 180)}…' : text;
      lines.add('${message.role == 'assistant' ? 'NOVA' : '用户'}：$clipped');
    }
    if (lines.isEmpty) return '';
    final summary = lines.join('\n');
    return summary.length > 6000
        ? summary.substring(summary.length - 6000)
        : summary;
  }

  Map<String, dynamic>? _buildNovaUserSystemMessage() {
    final name = (session.displayName ?? '').trim();
    final uid = session.userId > 0 ? '${session.userId}' : '';
    final phone = session.phone.trim();
    final biz = novaBizUserId;
    if (name.isEmpty && uid.isEmpty && phone.isEmpty && biz.isEmpty)
      return null;
    final lines = <String>[
      '你是沙丘 APP 内置的企业助手「NOVA」。',
      '以下「当前登录用户」信息来自沙丘账号系统，回答身份/称呼/手机号等问题时必须以此为准，不要臆造或使用其它昵称、历史测试名。',
    ];
    if (name.isNotEmpty) lines.add('姓名：$name');
    if (phone.isNotEmpty) lines.add('手机：$phone');
    if (uid.isNotEmpty) lines.add('用户ID：$uid');
    if (biz.isNotEmpty) lines.add('系统账号：$biz');
    lines.add('除非用户明确要求生成/下载文件，否则不要主动附带历史文件或杜撰附件。');
    return <String, dynamic>{'role': 'system', 'content': lines.join('\n')};
  }

  String _extractUserPromptText(
    dynamic userContent, {
    required String displayText,
  }) {
    if (userContent is String && userContent.trim().isNotEmpty)
      return userContent.trim();
    if (displayText.trim().isNotEmpty) return displayText.trim();
    if (userContent is List) {
      final parts = <String>[];
      for (final row in userContent) {
        if (row is Map && (row['type'] ?? '').toString() == 'text') {
          final t = (row['text'] ?? '').toString().trim();
          if (t.isNotEmpty) parts.add(t);
        }
      }
      if (parts.isNotEmpty) return parts.join('\n');
    }
    return displayText;
  }

  Future<String> sendAndReplyStream({
    required int conversationId,
    required dynamic userContent,
    String? displayText,
    Map<String, dynamic>? userMetadata,
    List<String> attachmentIds = const <String>[],
    int? userMessageId,
    bool skipUserPersist = false,
    bool stream = true,
    required void Function(NovaStreamUpdate update) onUpdate,
    void Function(int conversationId)? onConversationId,
  }) async {
    final readiness = await checkReadiness();
    if (!readiness.ready) {
      throw Exception(readiness.message ?? 'NOVA账号尚未开通，请稍后再试');
    }
    var activeConvId = conversationId;
    final contentLabel =
        displayText ?? (userContent is String ? userContent : '[附件消息]');
    final userPrompt = _extractUserPromptText(
      userContent,
      displayText: contentLabel.toString(),
    );
    final skipEchoCheck = userContent is List;
    userStoppedStream = false;

    _streamClient?.close();
    _streamClient = http.Client();
    final streamClient = _streamClient!;

    final model = resolveModelForContent(
      userContent,
      preferred: selectedModel.isEmpty
          ? NovaConfig.defaultChatModel
          : selectedModel,
    );

    var replyBuffer = '';
    var thinkBuffer = '';
    var hadOutput = false;
    String? streamError;

    void applySseEvent(NovaOpenAiSseEvent event) {
      if (event.error != null && event.error!.isNotEmpty) {
        streamError = event.error;
        return;
      }
      if (event.conversationId > 0 && event.conversationId != activeConvId) {
        final previous = activeConvId;
        activeConvId = event.conversationId;
        unawaited(remapConversationId(previous, activeConvId));
        onConversationId?.call(activeConvId);
      }
      if (event.think.isNotEmpty) {
        hadOutput = true;
        thinkBuffer += event.think;
        onUpdate(
          NovaStreamUpdate(
            replyText: replyBuffer,
            thinkText: thinkBuffer.trim(),
            thinkStatus: event.status.isNotEmpty ? event.status : '思考中…',
          ),
        );
      }
      if (event.text.isNotEmpty) {
        hadOutput = true;
        if (isHermesThinkLine(event.text)) {
          thinkBuffer += event.text;
          onUpdate(
            NovaStreamUpdate(
              replyText: replyBuffer,
              thinkText: thinkBuffer.trim(),
              thinkStatus: event.status.isNotEmpty ? event.status : '思考中…',
            ),
          );
        } else {
          replyBuffer += event.text;
          onUpdate(
            NovaStreamUpdate(
              replyText: replyBuffer,
              thinkText: thinkBuffer.trim(),
              thinkStatus: event.status,
            ),
          );
        }
      }
    }

    try {
      // 纯文本由 im-svc 持久化并统一构造会话上下文；多模态仍直连 Nova，
      // 以保留 image parts / attachment_ids。
      final novaAttachmentIds = attachmentIds
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      if (userContent is List || novaAttachmentIds.isNotEmpty) {
        return await _streamMultimodalViaNovaCompletions(
          conversationId: activeConvId,
          userContent: userContent is String && userContent.trim().isEmpty
              ? contentLabel.toString()
              : userContent,
          displayText: contentLabel.toString(),
          userMetadata: userMetadata,
          attachmentIds: novaAttachmentIds,
          userMessageId: userMessageId,
          model: model,
          onUpdate: onUpdate,
          onConversationId: onConversationId,
          streamClient: streamClient,
        );
      }

      // 通过 im-svc 执行生成并持久化完整问答。服务端使用不随客户端断开的
      // context 继续处理，因此离开 C4 或 SSE 断开后仍可从会话历史恢复。
      final req = http.Request('POST', _dunesUri('/ai/assistant/messages'));
      final headers = <String, String>{
        ..._dunesHeaders,
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      };
      if (stream) headers['Accept'] = 'text/event-stream';
      req.headers.addAll(headers);
      final body = <String, dynamic>{
        'conversationId': activeConvId,
        'model': model,
        'kind': 'TEXT',
        'content': userPrompt,
        'bodyText': contentLabel,
        if (userMetadata != null && userMetadata.isNotEmpty)
          'payload': userMetadata,
      };
      req.body = jsonEncode(body);
      if (kDebugMode) {
        debugPrint(
          '[NativeNova] POST assistant/messages conv=$activeConvId '
          'model=$model stream=$stream bodyBytes=${req.body.length}',
        );
      }

      if (!stream) {
        onUpdate(const NovaStreamUpdate(replyText: '', thinkStatus: '正在分析…'));
        final resp = await streamClient.post(
          req.url,
          headers: req.headers,
          body: req.body,
        );
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw Exception(_parseNovaHttpError(resp.statusCode, resp.body));
        }
        final decoded = _decode(resp.body);
        final choices =
            decoded['choices'] as List<dynamic>? ?? const <dynamic>[];
        final first =
            choices.isNotEmpty && choices.first is Map<String, dynamic>
            ? choices.first as Map<String, dynamic>
            : const <String, dynamic>{};
        final message = first['message'] is Map<String, dynamic>
            ? first['message'] as Map<String, dynamic>
            : const <String, dynamic>{};
        var reply = _extractAssistantText(message).trim();
        if (reply.isEmpty) throw Exception('NOVA未返回正文，请重试');
        if (!skipEchoCheck && reply.trim() == userPrompt.trim()) {
          throw Exception('NOVA未返回正文，请重试');
        }
        onUpdate(NovaStreamUpdate(replyText: reply, thinkStatus: ''));
        await commitAssistantReplyToSession(activeConvId, replyText: reply);
        await _clearGeneratingMarkersForConversation(activeConvId);
        return reply;
      }

      final streamed = await streamClient.send(req);
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final errBody = await streamed.stream.bytesToString();
        throw Exception(_parseNovaHttpError(streamed.statusCode, errBody));
      }

      final sseAcc = NovaOpenAiSseAccumulator();
      try {
        await for (final chunk in streamed.stream.transform(utf8.decoder)) {
          if (userStoppedStream) break;
          sseAcc.feed(chunk, applySseEvent);
          if (streamError != null) break;
        }
        if (!userStoppedStream) sseAcc.flush(applySseEvent);
      } on http.ClientException {
        if (!userStoppedStream) {
          // 后台/断网时保留 generating 与草稿，由页面 resume 或后台轮询恢复。
          await stripStreamingFromSession(activeConvId);
          rethrow;
        }
      }

      if (streamError != null && streamError!.isNotEmpty) {
        throw Exception(streamError);
      }

      if (userStoppedStream) {
        final partial = novaFinalReplyText(
          replyBuffer,
          thinkBuffer,
          finalPass: true,
        );
        if (partial.isNotEmpty &&
            partial != '已停止生成' &&
            partial.trim() != userPrompt.trim()) {
          await _saveLocalMessage(
            activeConvId,
            role: 'assistant',
            content: partial,
            kind: 'AI_ASSISTANT',
            messageId: (userMessageId ?? 0) > 0 ? userMessageId! + 1 : null,
            createdAt: _assistantCreatedAt(activeConvId),
          );
          await commitAssistantReplyToSession(
            activeConvId,
            replyText: partial,
            thinkText: thinkBuffer.trim(),
          );
        }
        await _clearGeneratingMarkersForConversation(activeConvId);
        return partial;
      }

      final finalParts = splitNovaStreamText(replyBuffer, finalPass: true);
      var reply = novaFinalReplyText(
        finalParts.reply,
        thinkBuffer,
        finalPass: true,
      );
      if (reply.isEmpty && thinkBuffer.trim().isNotEmpty) {
        reply = thinkBuffer.trim();
      }
      if (reply.isEmpty && replyBuffer.trim().isNotEmpty) {
        reply = stripHermesProgressLines(replyBuffer.trim());
      }
      if (reply.isEmpty && finalParts.thinking.trim().isNotEmpty) {
        reply = finalParts.thinking.trim();
      }
      if (!hadOutput || reply.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[NativeNova] empty stream reply hadOutput=$hadOutput '
            'replyLen=${replyBuffer.length} thinkLen=${thinkBuffer.length}',
          );
        }
        throw Exception('NOVA未返回正文，请重试');
      }
      if (!skipEchoCheck && reply.trim() == userPrompt.trim()) {
        throw Exception('NOVA未返回正文，请重试');
      }
      await commitAssistantReplyToSession(
        activeConvId,
        replyText: reply,
        thinkText: thinkBuffer.trim(),
      );
      await _clearGeneratingMarkersForConversation(activeConvId);
      return reply;
    } finally {
      if (_streamClient == streamClient) _streamClient = null;
    }
  }

  /// 多模态附件：直接走云枢 `/v1/chat/completions`（与 admin-web 一致），
  /// 避免 im-svc 纯文本通道丢掉 image_url / file parts。
  Future<String> _streamMultimodalViaNovaCompletions({
    required int conversationId,
    required dynamic userContent,
    required String displayText,
    required Map<String, dynamic>? userMetadata,
    List<String> attachmentIds = const <String>[],
    required int? userMessageId,
    required String model,
    required void Function(NovaStreamUpdate update) onUpdate,
    required void Function(int conversationId)? onConversationId,
    required http.Client streamClient,
  }) async {
    if (novaApiKey.isEmpty) {
      throw Exception('NOVA账号尚未就绪，请重新登录后再试');
    }
    var activeConvId = conversationId;
    final userPrompt = _extractUserPromptText(
      userContent,
      displayText: displayText,
    );

    // 先落本地用户气泡（含附件元数据），保证会话内能立刻看到图片/文件。
    if (userMessageId != null && userMessageId > 0) {
      final attachments = <NovaMessageAttachment>[];
      final rawAtt = userMetadata?['attachments'];
      if (rawAtt is List) {
        for (final row in rawAtt) {
          if (row is Map) {
            attachments.add(
              NovaMessageAttachment.fromJson(Map<String, dynamic>.from(row)),
            );
          }
        }
      }
      await _upsertLocalSessionMessage(
        activeConvId,
        NativeNovaMessage(
          id: userMessageId,
          role: 'user',
          text: displayText,
          createdAt: DateTime.fromMillisecondsSinceEpoch(userMessageId),
          kind: 'TEXT',
          attachments: attachments,
          payload: userMetadata,
        ),
      );
    }

    var replyBuffer = '';
    var thinkBuffer = '';
    var hadOutput = false;
    String? streamError;

    void applySseEvent(NovaOpenAiSseEvent event) {
      if (event.error != null && event.error!.isNotEmpty) {
        streamError = event.error;
        return;
      }
      if (event.conversationId > 0 && event.conversationId != activeConvId) {
        final previous = activeConvId;
        activeConvId = event.conversationId;
        unawaited(remapConversationId(previous, activeConvId));
        onConversationId?.call(activeConvId);
      }
      if (event.think.isNotEmpty) {
        hadOutput = true;
        thinkBuffer += event.think;
        onUpdate(
          NovaStreamUpdate(
            replyText: replyBuffer,
            thinkText: thinkBuffer.trim(),
            thinkStatus: event.status.isNotEmpty ? event.status : '思考中…',
          ),
        );
      }
      if (event.text.isNotEmpty) {
        hadOutput = true;
        if (isHermesThinkLine(event.text)) {
          thinkBuffer += event.text;
          onUpdate(
            NovaStreamUpdate(
              replyText: replyBuffer,
              thinkText: thinkBuffer.trim(),
              thinkStatus: event.status.isNotEmpty ? event.status : '思考中…',
            ),
          );
        } else {
          replyBuffer += event.text;
          onUpdate(
            NovaStreamUpdate(
              replyText: replyBuffer,
              thinkText: thinkBuffer.trim(),
              thinkStatus: event.status,
            ),
          );
        }
      }
    }

    final requestMessages = await buildNovaChatMessages(
      conversationId: activeConvId,
      latestContent: userContent,
    );
    final headers = novaHeaders(<String, String>{
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    });
    final sessionId = await novaChatSessionId(activeConvId);
    if (sessionId.isNotEmpty) headers['X-Nova-Chat-Session-Id'] = sessionId;
    final requestBody = <String, dynamic>{
      'model': model,
      'stream': true,
      'messages': requestMessages,
      if (attachmentIds.isNotEmpty) 'attachment_ids': attachmentIds,
    };
    final bizUser = novaBizUserId.trim();
    if (bizUser.isNotEmpty) requestBody['user'] = bizUser;

    if (kDebugMode) {
      debugPrint(
        '[NativeNova] POST chat/completions (multimodal) conv=$activeConvId '
        'model=$model parts=${userContent is List ? userContent.length : 0} '
        'attachmentIds=${attachmentIds.length}',
      );
    }

    onUpdate(const NovaStreamUpdate(replyText: '', thinkStatus: '正在分析…'));
    final req = http.Request(
      'POST',
      Uri.parse('$novaBase/v1/chat/completions'),
    );
    req.headers.addAll(headers);
    req.body = jsonEncode(requestBody);

    final streamed = await streamClient.send(req);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final errBody = await streamed.stream.bytesToString();
      throw Exception(_parseNovaHttpError(streamed.statusCode, errBody));
    }

    final sseAcc = NovaOpenAiSseAccumulator();
    try {
      await for (final chunk in streamed.stream.transform(utf8.decoder)) {
        if (userStoppedStream) break;
        sseAcc.feed(chunk, applySseEvent);
        if (streamError != null) break;
      }
      if (!userStoppedStream) sseAcc.flush(applySseEvent);
    } on http.ClientException {
      if (!userStoppedStream) {
        await stripStreamingFromSession(activeConvId);
        rethrow;
      }
    }

    if (streamError != null && streamError!.isNotEmpty) {
      throw Exception(streamError);
    }

    if (userStoppedStream) {
      final partial = novaFinalReplyText(
        replyBuffer,
        thinkBuffer,
        finalPass: true,
      );
      if (partial.isNotEmpty &&
          partial != '已停止生成' &&
          partial.trim() != userPrompt.trim()) {
        await commitAssistantReplyToSession(
          activeConvId,
          replyText: partial,
          thinkText: thinkBuffer.trim(),
        );
        await persistAssistantTurn(
          conversationId: activeConvId,
          messageId: userMessageId ?? 0,
          userMessage: displayText,
          assistantMessage: partial,
          thinkText: thinkBuffer.trim(),
          userPayload: userMetadata,
        );
      }
      await _clearGeneratingMarkersForConversation(activeConvId);
      return partial;
    }

    final finalParts = splitNovaStreamText(replyBuffer, finalPass: true);
    var reply = novaFinalReplyText(
      finalParts.reply,
      thinkBuffer,
      finalPass: true,
    );
    if (reply.isEmpty && thinkBuffer.trim().isNotEmpty) {
      reply = thinkBuffer.trim();
    }
    if (reply.isEmpty && replyBuffer.trim().isNotEmpty) {
      reply = stripHermesProgressLines(replyBuffer.trim());
    }
    if (reply.isEmpty && finalParts.thinking.trim().isNotEmpty) {
      reply = finalParts.thinking.trim();
    }
    if (!hadOutput || reply.isEmpty) {
      throw Exception('NOVA未返回正文，请重试');
    }
    await commitAssistantReplyToSession(
      activeConvId,
      replyText: reply,
      thinkText: thinkBuffer.trim(),
    );
    await persistAssistantTurn(
      conversationId: activeConvId,
      messageId: userMessageId ?? 0,
      userMessage: displayText,
      assistantMessage: reply,
      thinkText: thinkBuffer.trim(),
      userPayload: userMetadata,
    );
    await _clearGeneratingMarkersForConversation(activeConvId);
    return reply;
  }

  Map<String, dynamic>? _parseSseBlock(String block) {
    for (final line in block.split('\n')) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty || data == '[DONE]') return null;
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    return null;
  }

  Future<String> sendAndReply({
    required int conversationId,
    required String text,
  }) async {
    final readiness = await checkReadiness();
    if (!readiness.ready) {
      throw Exception(readiness.message ?? 'NOVA账号尚未开通，请稍后再试');
    }
    if (novaApiKey.isEmpty) {
      throw Exception('NOVA账号尚未就绪，请重新登录后再试');
    }
    await _saveLocalMessage(
      conversationId,
      role: 'user',
      content: text,
      kind: 'TEXT',
    );
    final requestMessages = await buildNovaChatMessages(
      conversationId: conversationId,
      latestContent: text,
    );
    final headers = novaHeaders(<String, String>{
      'Content-Type': 'application/json',
    });
    final sessionId = await novaChatSessionId(conversationId);
    if (sessionId.isNotEmpty) headers['X-Nova-Chat-Session-Id'] = sessionId;
    final requestBody = <String, dynamic>{
      'model': selectedModel.isEmpty
          ? NovaConfig.defaultChatModel
          : selectedModel,
      'stream': false,
      'messages': requestMessages,
    };
    final bizUser = novaBizUserId.trim();
    if (bizUser.isNotEmpty) requestBody['user'] = bizUser;
    final resp = await _client.post(
      Uri.parse('$novaBase/v1/chat/completions'),
      headers: headers,
      body: jsonEncode(requestBody),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_parseNovaHttpError(resp.statusCode, resp.body));
    }
    final body = _decode(resp.body);
    final choices = body['choices'] as List<dynamic>? ?? const <dynamic>[];
    final first = choices.isNotEmpty && choices.first is Map<String, dynamic>
        ? choices.first as Map<String, dynamic>
        : const <String, dynamic>{};
    final message = first['message'] is Map<String, dynamic>
        ? first['message'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final reply = _extractAssistantText(message).trim();
    if (reply.isEmpty) throw Exception('NOVA未返回正文，请重试');
    await _saveLocalMessage(
      conversationId,
      role: 'assistant',
      content: reply,
      kind: 'AI_ASSISTANT',
    );
    return reply;
  }

  /// 一次性补全（不写入会话），用于会议纪要 → PRD 等离线生成场景。
  Future<String> generateCompletionWithModel({
    required String model,
    required String systemPrompt,
    required String userText,
  }) async {
    final readiness = await checkReadiness();
    if (!readiness.ready) {
      throw Exception(readiness.message ?? 'NOVA账号尚未开通，请稍后再试');
    }
    if (novaApiKey.isEmpty) {
      throw Exception('NOVA账号尚未就绪，请重新登录后再试');
    }
    final trimmed = userText.trim();
    if (trimmed.isEmpty) {
      throw Exception('输入内容为空，无法生成');
    }
    final effectiveModel = model.trim().isNotEmpty
        ? model.trim()
        : (selectedModel.isEmpty ? NovaConfig.defaultChatModel : selectedModel);
    final requestMessages = <Map<String, dynamic>>[
      <String, dynamic>{'role': 'system', 'content': systemPrompt.trim()},
      <String, dynamic>{'role': 'user', 'content': trimmed},
    ];
    final headers = novaHeaders(<String, String>{
      'Content-Type': 'application/json',
    });
    final sessionId = novaProfileSessionId.trim();
    if (sessionId.isNotEmpty) headers['X-Nova-Chat-Session-Id'] = sessionId;
    final requestBody = <String, dynamic>{
      'model': effectiveModel,
      'stream': false,
      'messages': requestMessages,
    };
    final bizUser = novaBizUserId.trim();
    if (bizUser.isNotEmpty) requestBody['user'] = bizUser;
    final resp = await _client.post(
      Uri.parse('$novaBase/v1/chat/completions'),
      headers: headers,
      body: jsonEncode(requestBody),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_parseNovaHttpError(resp.statusCode, resp.body));
    }
    final body = _decode(resp.body);
    final choices = body['choices'] as List<dynamic>? ?? const <dynamic>[];
    final first = choices.isNotEmpty && choices.first is Map<String, dynamic>
        ? choices.first as Map<String, dynamic>
        : const <String, dynamic>{};
    final message = first['message'] is Map<String, dynamic>
        ? first['message'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final reply = _extractAssistantText(message).trim();
    if (reply.isEmpty) throw Exception('NOVA未返回正文，请重试');
    return reply;
  }

  String _extractAssistantText(Map<String, dynamic> message) {
    final content = message['content'];
    if (content is String) return content;
    if (content is List) {
      final parts = <String>[];
      for (final row in content) {
        if (row is Map<String, dynamic>) {
          final text = (row['text'] ?? '').toString().trim();
          if (text.isNotEmpty) parts.add(text);
        }
      }
      return parts.join('\n').trim();
    }
    return '';
  }

  Future<void> _clearGeneratingMarkersForConversation(
    int conversationId,
  ) async {
    final uid = session.userId;
    if (uid <= 0 || conversationId <= 0) return;
    await clearNovaGeneratingState(userId: uid, conversationId: conversationId);
  }

  /// 对齐 WebView `saveNovaServerMessage`：优先保留当前会话，避免失败时切走 convId。
  Future<bool> _saveLocalMessage(
    int conversationId, {
    required String role,
    required String content,
    required String kind,
    Map<String, dynamic>? metadata,
    int? messageId,
    DateTime? createdAt,
    bool requireSuccess = false,
  }) async {
    if (content.trim().isEmpty && metadata == null) return !requireSuccess;
    // `/ai/assistant/messages` already persists both turns in im-go. Sending
    // the same message to KB's `messages/local` reintroduces a second,
    // unrelated conversation store and breaks ID stability.
    return true;
    /*
    final body = <String, dynamic>{
      'role': role,
      'content': content,
      'kind': kind,
    };
    if (metadata != null && metadata.isNotEmpty) body['metadata'] = metadata;
    if (messageId != null && messageId > 0) {
      body['id'] = messageId;
      body['messageId'] = messageId;
    }
    final at =
        createdAt ??
        ((messageId != null && messageId > 0)
            ? DateTime.fromMillisecondsSinceEpoch(messageId)
            : null);
    if (at != null) body['createdAt'] = at.toUtc().toIso8601String();

    if (conversationId > 0) {
      if (await _postLocalMessage(conversationId, body)) return true;
      if (kDebugMode) {
        debugPrint(
          '[NativeNova] keep conv=$conversationId after messages/local miss '
          'role=$role kind=$kind',
        );
      }
      return false;
    }

    final newId = await _postAiConversationSessionEnsure();
    if (newId <= 0) return false;
    await persistActiveConversationId(newId);
    return _postLocalMessage(newId, body);
    */
  }

  Future<bool> _postLocalMessage(
    int conversationId,
    Map<String, dynamic> body,
  ) async {
    if (conversationId <= 0 || await isImInboxPlaceholderConvId(conversationId))
      return false;
    try {
      final resp = await _client.post(
        _dunesUri('/ai/conversations/$conversationId/messages/local'),
        headers: _dunesHeaders,
        body: jsonEncode(body),
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) return true;
      if (kDebugMode) {
        debugPrint(
          '[NativeNova] messages/local failed conv=$conversationId '
          'status=${resp.statusCode} body=${resp.body}',
        );
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint(
          '[NativeNova] messages/local error conv=$conversationId: $e',
        );
    }
    return false;
  }

  int _turnConvId(Map<String, dynamic> turn) {
    return (turn['conversationId'] as num?)?.toInt() ??
        (turn['conversation_id'] as num?)?.toInt() ??
        0;
  }

  String _parseApiError(http.Response resp, {required String fallback}) {
    try {
      final body = _decode(resp.body);
      final msg = (body['message'] ?? body['error'] ?? '').toString().trim();
      final code = (body['code'] ?? body['errorCode'] ?? '').toString().trim();
      if (msg.isNotEmpty && code.isNotEmpty) return '$msg|code=$code';
      if (msg.isNotEmpty) return msg;
      if (code.isNotEmpty) return '$fallback|code=$code';
    } catch (_) {}
    if (resp.statusCode == 400) return 'NOVA会话初始化异常，请发送一条消息重试';
    if (resp.statusCode == 503) return 'NOVA服务暂不可用';
    return '$fallback（HTTP ${resp.statusCode}）';
  }

  String _parseNovaHttpError(int status, String bodyText) {
    try {
      final body = _decode(bodyText);
      final msg = (body['error']?['message'] ?? body['message'] ?? '')
          .toString()
          .trim();
      if (msg.isNotEmpty) return msg;
    } catch (_) {}
    if (status == 503) return 'NOVA服务暂不可用';
    return 'NOVA回复失败（HTTP $status）';
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _extractTurns(Map<String, dynamic> body) {
    List<Map<String, dynamic>> asMaps(dynamic raw) {
      if (raw is! List) return const <Map<String, dynamic>>[];
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    }

    final data = body['data'];
    if (data is List) return asMaps(data);
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final items = asMaps(map['items']);
      if (items.isNotEmpty) return items;
      final turns = asMaps(map['turns']);
      if (turns.isNotEmpty) return turns;
    }
    return asMaps(body['items']);
  }

  List<dynamic> _rowsFromData(dynamic data) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      final items = data['items'];
      if (items is List) return items;
    }
    if (data is Map) {
      final items = data['items'];
      if (items is List) return List<dynamic>.from(items);
    }
    return const <dynamic>[];
  }
}
