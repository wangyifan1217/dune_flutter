import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/config/nova_config.dart';
import '../auth/auth_session.dart';
import '../conversation/conversation_models.dart';
import 'nova_draft.dart';
import 'nova_generating_storage.dart';
import 'nova_history_sync.dart';
import 'nova_history_utils.dart';
import 'nova_image_utils.dart';
import 'nova_inbox_preview.dart';
import 'nova_stream_parser.dart';
import 'nova_web_storage.dart';

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
    return NovaMessageAttachment(
      url: (json['url'] ?? json['accessUrl'] ?? json['publicUrl'] ?? json['previewUrl'] ?? '').toString(),
      objectKey: (json['objectKey'] ?? '').toString(),
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
List<NativeNovaMessage> repairNovaConversationMessages(List<NativeNovaMessage> raw) {
  final welcome = raw.where((m) => m.isWelcome).toList(growable: false);
  var items = raw
      .where((m) => !m.isWelcome && !(m.role == 'assistant' && m.streaming && m.text.trim().isEmpty))
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
  final assistants = items
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

  final out = <NativeNovaMessage>[];
  for (final u in users) {
    final userAt = u.createdAt ??
        (u.id > 0 ? DateTime.fromMillisecondsSinceEpoch(u.id) : DateTime.now());
    out.add(u.copyWith(createdAt: userAt));
    final turnAssistants = buckets[u.id] ?? const <NativeNovaMessage>[];
    for (var i = 0; i < turnAssistants.length; i++) {
      final a = turnAssistants[i];
      final aiAt = userAt.add(Duration(milliseconds: 1000 + i * 500));
      out.add(a.copyWith(createdAt: aiAt));
    }
  }

  return sortNovaMessages([...welcome, ...out]);
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
    this.assistantGenerating = false,
    this.assistantGeneratingStatus = '',
    this.assistantGeneratingAfterMessageId = 0,
    this.messages = const <NativeNovaMessage>[],
  });

  final int conversationId;
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
  const NovaReadiness({
    required this.ready,
    this.message,
  });

  final bool ready;
  final String? message;
}

class NovaHistoryPageResult {
  const NovaHistoryPageResult({
    required this.items,
    required this.hasMore,
  });

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
  NativeNovaService({
    required this.session,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;
  String? _cachedApiKey;
  String? _selectedModelOverride;
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
        displayName: (session.displayName ?? '').trim().isNotEmpty ? session.displayName!.trim() : '我',
      );

  Uri _dunesUri(String path) => Uri.parse('${session.apiBase}$path');

  Map<String, String> get _dunesHeaders => <String, String>{
    'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  String get novaBase =>
      (session.novaLocalStorage?['dunes_nova_base'] ?? NovaConfig.baseUrl).replaceAll(RegExp(r'/$'), '');
  String get novaApiKey =>
      (_cachedApiKey ?? session.novaLocalStorage?['dunes_nova_api_key'] ?? '').trim();
  String get selectedModel {
    final override = _selectedModelOverride?.trim() ?? '';
    if (override.isNotEmpty) return override;
    return (session.novaLocalStorage?['dunes_nova_chat_model'] ??
            session.novaLocalStorage?['dunes_nova_default_model'] ??
            NovaConfig.defaultChatModel)
        .trim();
  }

  void setSelectedChatModel(String model) {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    _selectedModelOverride = trimmed;
    _historySync = null;
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
  }) =>
      _history.registerHistoryTurn(
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

  /// 离开 C4 / 新对话前刷新本地历史预览。
  Future<void> flushConvToLocalHistory(
    int conversationId,
    List<NativeNovaMessage> messages,
  ) =>
      _history.flushConvToLocalHistory(conversationId, messages);

  Future<void> persistActiveConversationId(int conversationId) =>
      _history.persistActiveConversationId(conversationId);

  static String friendlyError(Object error) {
    final raw = error.toString();
    var msg = raw.startsWith('Exception: ') ? raw.substring('Exception: '.length) : raw;
    // 云枢 C4 不阻断知识库/RAG 状态（对齐 WebView：创建会话失败静默降级）。
    if (msg.contains('rag_not_ready') || msg.contains('知识库账号')) {
      return '';
    }
    if (msg.contains('HTTP 400')) return '云枢会话初始化异常，请发送一条消息或稍后重试';
    if (msg.contains('HTTP 503')) return '云枢服务暂不可用，请稍后再试';
    if (msg.contains('凭证') || msg.contains('api_key')) return '云枢账号尚未就绪，请重新登录后再试';
    if (msg.contains('尚未开通')) return msg;
    return msg;
  }

  Future<({String avatarPreset, String avatarUrl})> fetchCurrentUserAvatar() async {
    try {
      final resp = await _client.get(_dunesUri('/users/me'), headers: _dunesHeaders);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return (avatarPreset: '', avatarUrl: '');
      }
      final body = _decode(resp.body);
      final data = body['data'] is Map<String, dynamic> ? body['data'] as Map<String, dynamic> : body;
      final preset = (data['avatarPreset'] ?? data['peerAvatarPreset'] ?? '').toString();
      var url = (data['avatarUrl'] ?? data['avatar'] ?? '').toString();
      final objectKey = (data['avatarObjectKey'] ?? '').toString();
      if (url.isEmpty && objectKey.isNotEmpty) {
        try {
          final pre = await _client.get(
            _dunesUri(
              '/storage/presigned-get?bucket=user-avatars&objectKey=${Uri.encodeQueryComponent(objectKey)}',
            ),
            headers: _dunesHeaders,
          );
          if (pre.statusCode >= 200 && pre.statusCode < 300) {
            final preBody = _decode(pre.body);
            final preData = preBody['data'] is Map<String, dynamic>
                ? preBody['data'] as Map<String, dynamic>
                : preBody;
            url = (preData['url'] ?? '').toString();
          }
        } catch (_) {}
      }
      return (avatarPreset: preset, avatarUrl: url);
    } catch (_) {
      return (avatarPreset: '', avatarUrl: '');
    }
  }

  Future<NovaReadiness> checkReadiness() async {
    return _refreshNovaCredentials();
  }

  /// 对齐 admin-web `refreshNovaCredentials`：每次进入/发消息前拉最新凭证。
  Future<NovaReadiness> _refreshNovaCredentials() async {
    try {
      final resp = await _client.get(_dunesUri('/me/nova-credentials'), headers: _dunesHeaders);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        if (novaApiKey.isNotEmpty) return const NovaReadiness(ready: true);
        return const NovaReadiness(
          ready: false,
          message: '云枢账号尚未开通，请稍后再试',
        );
      }
      final body = _decode(resp.body);
      final data = body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : body;
      final ready = data['ready'] == true;
      final key = ((data['api_token'] ?? data['apiKey']) ?? '').toString().trim();
      if (key.isNotEmpty) _cachedApiKey = key;
      if (ready && key.isNotEmpty) return const NovaReadiness(ready: true);
      if (novaApiKey.isNotEmpty) return const NovaReadiness(ready: true);
      final message = (data['lastError'] ?? data['message'] ?? '云枢账号尚未开通，请稍后再试')
          .toString()
          .trim();
      return NovaReadiness(ready: false, message: message);
    } catch (_) {
      if (novaApiKey.isNotEmpty) return const NovaReadiness(ready: true);
      return const NovaReadiness(ready: false, message: '云枢服务暂不可用');
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
      await clearNovaGeneratingState(userId: userId, conversationId: previousConversationId);
      await clearNovaStreamDraftState(userId: userId, conversationId: previousConversationId);
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
    if (previousConversationId > 0 && previousConversationId == conversationId) {
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
    await resetNovaNewChatPlaceholder(userId: uid, previousConversationId: previousConversationId);
    final id = await ensureConversation();
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
    final fromStorage = (session.novaLocalStorage?['dunes_storage_public_base'] ??
            session.novaLocalStorage?['dunes_ftp_public_base'] ??
            '')
        .trim();
    if (fromStorage.isNotEmpty) return fromStorage.replaceAll(RegExp(r'/$'), '');
    return 'https://image.heunion.com/zdfiles';
  }

  String resolvePublicAttachmentUrl({
    required String url,
    required String objectKey,
    String bucket = 'im-attachments',
    String backend = '',
  }) {
    final direct = url.trim();
    if (direct.startsWith('http://') || direct.startsWith('https://')) return direct;
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
    final resolved = accessUrl.isNotEmpty ? accessUrl : (url.isNotEmpty ? url : objectKey);
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
          final kept = decoded.whereType<Map>().where((item) {
            final cid = (item['conversationId'] as num?)?.toInt() ?? 0;
            return cid != conversationId;
          }).toList(growable: false);
          patch['dunes_nova_local_history'] = jsonEncode(kept);
        }
      }
    } catch (_) {}
    if (patch.isNotEmpty) await NovaWebStorage.merge(uid, patch);
    await NovaWebStorage.removeKeys(uid, ['dunes_nova_msgs_$conversationId']);
  }

  Future<int> _createConversation({bool forceNew = false}) async {
    return _postAiConversationSessionEnsure();
  }

  /// `POST /ai/conversations/sessions/ensure`
  Future<NovaConversationSnapshot> sessionEnsure() async {
    final resp = await _client.post(
      _dunesUri('/ai/conversations/sessions/ensure'),
      headers: _dunesHeaders,
      body: jsonEncode(<String, dynamic>{
        'kind': 'AI_ASSISTANT',
        'title': NovaConfig.displayName,
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_parseApiError(resp, fallback: '云枢会话初始化失败'));
    }
    final snap = _parseConversationSnapshot(_decode(resp.body));
    _lastSessionSnapshot = snap;
    if (kDebugMode) {
      debugPrint(
        '[NativeNova] sessions/ensure convId=${snap.conversationId} '
        'generating=${snap.assistantGenerating}',
      );
    }
    return snap;
  }

  /// `GET /ai/conversations/{id}?all=true`
  Future<NovaConversationSnapshot> fetchConversationAll(int conversationId) async {
    if (conversationId <= 0) {
      return const NovaConversationSnapshot(conversationId: 0);
    }
    final resp = await _client.get(
      _dunesUri('/ai/conversations/$conversationId?all=true'),
      headers: _dunesHeaders,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_parseApiError(resp, fallback: '加载云枢会话失败'));
    }
    final snap = _parseConversationSnapshot(_decode(resp.body), fallbackConvId: conversationId);
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
    final convId = (d['conversationId'] as num?)?.toInt() ?? fallbackConvId;
    final gen = _parseGeneratingFields(d);
    final rawMsgs = d['messages'] ?? d['items'] ?? d['rows'];
    final msgs = _messagesFromServerList(rawMsgs);
    return NovaConversationSnapshot(
      conversationId: convId,
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
      (d['assistantGeneratingStatus'] ?? d['assistant_generating_status'] ?? '').toString(),
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
    return repairNovaConversationMessages(out);
  }

  Future<int> _postAiConversationSessionEnsure() async {
    try {
      final snap = await sessionEnsure();
      return snap.conversationId;
    } catch (_) {
      return 0;
    }
  }

  Future<List<NativeNovaMessage>> fetchHistory(int conversationId, {int size = 80}) async {
    final full = await fetchFullHistory(conversationId);
    return full.messages;
  }

  Future<NovaHistoryLoadResult> fetchFullHistory(
    int conversationId, {
    int? aroundMessageId,
    bool applyViewSinceFilter = true,
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

    var generating = server.assistantGenerating;
    var genStatus = server.assistantGeneratingStatus;
    var genAfter = server.assistantGeneratingAfterMessageId;

    NovaGeneratingState? localGen;
    NovaStreamDraft? streamDraft;
    if (session.userId > 0) {
      final storage = await NovaWebStorage.load(session.userId);
      localGen = readNovaGeneratingFromStorage(
        storage,
        convId: conversationId,
        activeConvId: conversationId,
      );
      streamDraft = readNovaStreamDraftFromStorage(storage, conversationId);
    }

    final localMsgs = await _loadPersistedSessionMessages(conversationId);
    var msgs = server.messages;
    final shouldUseLocalFallback = generating ||
        server.assistantGenerating ||
        isStreamInFlight ||
        shouldPersistNovaGenerating(
          localGen: localGen,
          draft: streamDraft,
          streamInFlight: isStreamInFlight,
        );
    if (msgs.isEmpty && shouldUseLocalFallback) {
      msgs = localMsgs;
    }

    if (_shouldRebuildFromTurns(msgs)) {
      final turns = await _fetchTurnRows(200, conversationId: conversationId);
      if (turns.isNotEmpty) {
        final turnMsgs = _novaMsgsFromTurns(_dedupeNovaTurns(turns), conversationId);
        if (turnMsgs.isNotEmpty) {
          if (kDebugMode) {
            debugPrint(
              '[NativeNova] rebuilt history from turns conv=$conversationId '
              'turns=${turns.length} msgs=${turnMsgs.length}',
            );
          }
          msgs = _mergeTurnsWithSessionCache(turnMsgs, localMsgs);
        }
      }
    }

    msgs = applyViewSinceFilter ? await _applyViewSinceFilter(msgs) : msgs;

    if (!isStreamInFlight) {
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
        unawaited(clearNovaGeneratingState(
          userId: session.userId,
          conversationId: conversationId,
        ));
      }
    } else if (hasReplyAfter) {
      generating = false;
      unawaited(clearNovaGeneratingState(
        userId: session.userId,
        conversationId: conversationId,
      ));
    }

    if (msgs.isNotEmpty && !generating) {
      unawaited(_persistSessionMessages(conversationId, msgs));
    }
    return NovaHistoryLoadResult(
      messages: repairNovaConversationMessages(
        sortNovaMessages(_dedupeNovaHistory(msgs)),
      ),
      assistantGenerating: generating,
      generatingStatus: genStatus,
      generatingAfterMessageId: genAfter,
    );
  }

  bool _shouldRebuildFromTurns(List<NativeNovaMessage> msgs) {
    if (msgs.isEmpty) return true;
    final hasUser = msgs.any((m) => m.role == 'user');
    final hasAssistant = msgs.any((m) => m.role == 'assistant' && m.text.trim().isNotEmpty);
    if (!hasAssistant) return false;
    if (!hasUser) return true;
    final firstFew = msgs.take(6).toList(growable: false);
    final assistantOnlyPrefix = firstFew.isNotEmpty && firstFew.every((m) => m.role == 'assistant');
    return assistantOnlyPrefix;
  }

  List<NativeNovaMessage> _mergeTurnsWithSessionCache(
    List<NativeNovaMessage> turns,
    List<NativeNovaMessage> local,
  ) {
    if (local.isEmpty) return turns;
    final map = <int, NativeNovaMessage>{};
    for (final m in turns) {
      if (m.id > 0) map[m.id] = m;
    }
    for (final m in local) {
      if (m.id <= 0) continue;
      final prev = map[m.id];
      if (prev == null) {
        map[m.id] = m;
        continue;
      }
      if (_novaHistoryRichness(m) > _novaHistoryRichness(prev)) {
        map[m.id] = m;
        continue;
      }
      if (m.attachments.isNotEmpty && prev.attachments.isEmpty) {
        map[m.id] = prev.copyWith(
          attachments: m.attachments,
          payload: m.payload ?? prev.payload,
          kind: m.kind != 'TEXT' ? m.kind : prev.kind,
        );
      }
    }
    for (final m in local) {
      if (m.id <= 0 || map.containsKey(m.id)) continue;
      // 避免把仅存在本地缓存、服务端未正式落库的 assistant 假消息重新拼回详情页。
      if (m.role == 'assistant' && !m.streaming) continue;
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
        final textMatch = tText == lText ||
            (tText.isEmpty && lText.isEmpty) ||
            (lText.isNotEmpty && tText.contains(lText)) ||
            (tText.isNotEmpty && lText.contains(tText));
        if (!textMatch &&
            !(lText.isEmpty && loc.attachments.isNotEmpty) &&
            !(_isNovaImagePlaceholderText(tText) && loc.attachments.isNotEmpty)) continue;
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

  Future<List<NativeNovaMessage>> _applyViewSinceFilter(List<NativeNovaMessage> msgs) async {
    if (msgs.isEmpty || session.userId <= 0) return msgs;
    final storage = await NovaWebStorage.load(session.userId);
    final raw = (storage['dunes_nova_view_since'] ?? '').trim();
    if (raw.isEmpty) return msgs;
    final since = DateTime.tryParse(raw);
    if (since == null) return msgs;
    final threshold = since.subtract(const Duration(seconds: 5));
    final filtered = msgs.where((m) {
      final at = m.createdAt;
      if (at == null) return true;
      return !at.isBefore(threshold);
    }).toList(growable: false);
    // 对齐 WebView filterNovaViewMessages：view-since 生效时，过滤为空则视为新对话空白页。
    return filtered;
  }

  Future<List<NativeNovaMessage>> _loadPersistedSessionMessages(int conversationId) async {
    if (conversationId <= 0 || session.userId <= 0) return const <NativeNovaMessage>[];
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
        final attachments = <NovaMessageAttachment>[];
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
            if (a is Map) attachments.add(NovaMessageAttachment.fromJson(Map<String, dynamic>.from(a)));
          }
        }
        final kind = (map['kind'] ?? 'TEXT').toString().toUpperCase();
        if (attachments.isEmpty && payload != null) {
          attachments.addAll(_attachmentsFromPayload(payload, kind));
        }
        final role = (map['role'] ?? 'user').toString().toLowerCase();
        final text = (map['bodyText'] ?? map['content'] ?? '').toString();
        final streaming = map['streaming'] == true;
        final thinkText = (map['thinkText'] ?? '').toString();
        final thinkStatus = (map['thinkStatus'] ?? '').toString();
        final isPendingAssistant = streaming && role == 'assistant';
        if (isPendingAssistant && text.trim().isEmpty && !isStreamInFlight) continue;
        if (text.isEmpty && attachments.isEmpty && kind == 'TEXT' && !isPendingAssistant) continue;
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

  List<NativeNovaMessage> _dedupeNovaHistory(List<NativeNovaMessage> items) {
    if (items.isEmpty) return items;
    final sorted = [...items]
      ..sort((a, b) {
        final ta = a.createdAt?.millisecondsSinceEpoch ?? a.id;
        final tb = b.createdAt?.millisecondsSinceEpoch ?? b.id;
        return ta.compareTo(tb);
      });
    final out = <NativeNovaMessage>[];
    for (final m in sorted) {
      final dup = out.indexWhere((e) => _isDuplicateNovaHistory(e, m));
      if (dup >= 0) {
        if (_novaHistoryRichness(m) > _novaHistoryRichness(out[dup])) {
          out[dup] = m;
        }
      } else if (_isEchoAssistantOfUser(out, m)) {
        continue;
      } else {
        out.add(m);
      }
    }
    return out;
  }

  /// 去掉「assistant 正文与用户提问完全一致」的误落库回声。
  bool _isEchoAssistantOfUser(List<NativeNovaMessage> prior, NativeNovaMessage candidate) {
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

  int _novaHistoryRichness(NativeNovaMessage m) {
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

  bool _isDuplicateNovaHistory(NativeNovaMessage a, NativeNovaMessage b) {
    if (a.id > 0 && b.id > 0 && a.id == b.id) return true;
    if (a.role != b.role) return false;
    final ta = a.createdAt;
    final tb = b.createdAt;
    if (ta != null && tb != null && ta.difference(tb).inMinutes.abs() > 5) return false;
    final at = a.text.trim();
    final bt = b.text.trim();
    if (at.isNotEmpty && bt.isNotEmpty) {
      if (at == bt) return true;
      if (a.role == 'assistant' && at.length > 40 && bt.length > 40) {
        if (at.substring(0, 40) == bt.substring(0, 40)) return true;
      }
    }
    if (a.role == 'user' &&
        ta != null &&
        tb != null &&
        ta.difference(tb).inSeconds.abs() < 90 &&
        ((a.attachments.isNotEmpty) != (b.attachments.isNotEmpty))) {
      return true;
    }
    return false;
  }

  List<Map<String, dynamic>> _dedupeNovaTurns(List<Map<String, dynamic>> turns) {
    final seen = <String>{};
    final sorted = [...turns];
    sorted.sort((a, b) {
      final atA = parseNovaDateTime(_novaTurnAt(a)) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final atB = parseNovaDateTime(_novaTurnAt(b)) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return atA.compareTo(atB);
    });
    final out = <Map<String, dynamic>>[];
    for (final t in sorted) {
      final key = [
        _novaTurnConvId(t),
        _novaTurnMessageId(t),
        _novaTurnUserText(t),
        _novaTurnAssistantText(t).isNotEmpty ? _novaTurnAssistantText(t) : _novaTurnPreviewText(t),
        _novaTurnAt(t),
      ].join('\x1e');
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(t);
    }
    return out;
  }

  String _novaTurnAt(Map<String, dynamic> turn) =>
      (turn['lastMessageAt'] ?? turn['last_message_at'] ?? turn['createdAt'] ?? turn['created_at'] ?? '')
          .toString();

  int _novaTurnConvId(Map<String, dynamic> turn) =>
      (turn['conversationId'] as num?)?.toInt() ??
      (turn['conversation_id'] as num?)?.toInt() ??
      0;

  int _novaTurnMessageId(Map<String, dynamic> turn) =>
      (turn['messageId'] as num?)?.toInt() ?? (turn['message_id'] as num?)?.toInt() ?? 0;

  String _novaTurnUserText(Map<String, dynamic> turn) => (turn['userMessage'] ??
          turn['user_message'] ??
          turn['prompt'] ??
          turn['question'] ??
          turn['userText'] ??
          '')
      .toString()
      .trim();

  String _novaTurnAssistantText(Map<String, dynamic> turn) => (turn['assistantMessage'] ??
          turn['assistant_message'] ??
          turn['answer'] ??
          turn['response'] ??
          turn['assistantText'] ??
          '')
      .toString()
      .trim();

  String _novaTurnPreviewText(Map<String, dynamic> turn) => (turn['lastMessagePreview'] ??
          turn['last_message_preview'] ??
          turn['preview'] ??
          '')
      .toString()
      .trim();

  String _novaTurnTitleText(Map<String, dynamic> turn) =>
      (turn['title'] ?? turn['name'] ?? turn['subject'] ?? '').toString().trim();

  List<NativeNovaMessage> _novaMsgsFromTurns(List<Map<String, dynamic>> turns, int conversationId) {
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
      final fallbackBase = (conversationId > 0 ? conversationId : 1) * 1000000 + (idx * 10 + 1);
      final userMsgId = allocMsgId(turnMid, fallbackBase);
      final aiMsgId = allocMsgId(turnMid > 0 ? turnMid + 1 : 0, userMsgId + 1);

      var userText = _novaTurnUserText(t);
      if (userText.isEmpty) userText = _novaTurnTitleText(t);
      Map<String, dynamic>? userPayload;
      final payloadRaw = t['userPayload'] ?? t['userMetadata'] ?? t['user_payload'] ?? t['metadata'];
      if (payloadRaw is Map) {
        userPayload = Map<String, dynamic>.from(payloadRaw);
      }
      var attachments = _parseAttachmentsFromRaw(
        userPayload ?? const <String, dynamic>{},
        userPayload,
        'TEXT',
      );
      var userKind = 'TEXT';
      if (attachments.isNotEmpty) {
        final allImages = attachments.every(_attachmentIsImage);
        if (allImages && (userText.isEmpty || _isNovaImagePlaceholderText(userText))) {
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

  Future<List<Map<String, dynamic>>> _fetchAllTurnsForConversation(int conversationId, {int pageSize = 100}) async {
    final all = <Map<String, dynamic>>[];
    var before = '';
    for (var i = 0; i < 15; i++) {
      final rows = await _fetchTurnRows(pageSize, before: before, conversationId: conversationId);
      if (rows.isEmpty) break;
      all.addAll(rows);
      if (rows.length < pageSize) break;
      final oldestAt = (rows.last['lastMessageAt'] ?? rows.last['createdAt'] ?? '').toString();
      if (oldestAt.isEmpty || oldestAt == before) break;
      before = oldestAt;
    }
    return all;
  }

  Future<List<Map<String, dynamic>>> _fetchTurnRows(int size, {String before = '', int? conversationId}) async {
    final convQ = conversationId != null && conversationId > 0 ? '&conversationId=$conversationId' : '';
    final beforeQ = before.trim().isEmpty ? '' : '&before=${Uri.encodeQueryComponent(before.trim())}';
    try {
      final resp = await _client.get(
        _dunesUri('/ai/history/turns?size=$size$beforeQ$convQ'),
        headers: _dunesHeaders,
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final rows = _extractTurns(_decode(resp.body));
        if (rows.isNotEmpty) return rows;
      }
    } catch (_) {}
    try {
      final resp = await _client.get(
        _dunesUri('/ai/history?view=turns&size=$size$beforeQ$convQ'),
        headers: _dunesHeaders,
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return _extractTurns(_decode(resp.body));
      }
    } catch (_) {}
    return const <Map<String, dynamic>>[];
  }

  Future<void> persistSession(int conversationId, List<NativeNovaMessage> messages) =>
      _persistSessionMessages(conversationId, messages);

  List<NativeNovaMessage> _stripIncompleteStreamingMessages(List<NativeNovaMessage> messages) {
    return messages
        .where((m) => !(m.role == 'assistant' && m.streaming && m.text.trim().isEmpty))
        .toList();
  }

  /// 离开页面后流中断时，清掉会话缓存里的半成品 assistant 气泡。
  Future<void> stripStreamingFromSession(int conversationId) async {
    if (conversationId <= 0 || session.userId <= 0) return;
    final local = await _loadPersistedSessionMessages(conversationId);
    final cleaned = _stripIncompleteStreamingMessages(local);
    if (cleaned.length == local.length) return;
    if (cleaned.isEmpty) {
      await NovaWebStorage.removeKeys(session.userId, ['dunes_nova_msgs_$conversationId']);
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
    var rows = _stripIncompleteStreamingMessages(await _loadPersistedSessionMessages(conversationId));
    for (var i = rows.length - 1; i >= 0; i--) {
      if (rows[i].role == 'user' && rows[i].text.trim() == text) {
        if (kDebugMode) {
          debugPrint('[NativeNova] skip echo assistant in session conv=$conversationId');
        }
        return;
      }
    }
    if (rows.any((m) => m.role == 'assistant' && !m.streaming && m.text.trim() == text)) {
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
          thinkStatus: (thinkText.isNotEmpty ? thinkText : m.thinkText).trim().isNotEmpty
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

  Future<void> _upsertLocalSessionMessage(int conversationId, NativeNovaMessage message) async {
    if (conversationId <= 0 || message.text.trim().isEmpty && message.attachments.isEmpty) return;
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
    if (conversationId <= 0 || (text.isEmpty && (metadata == null || metadata.isEmpty))) {
      return conversationId;
    }
    final hasAttachments = metadata != null &&
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
        attachments: const <NovaMessageAttachment>[],
      ),
    );
    return conversationId;
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

    final serverRows = existingMessages.where((m) => !m.isWelcome).toList(growable: false);
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
        debugPrint('[NativeNova] skip history sync: no user conv=$activeConvId');
      }
      return;
    }

    await registerHistoryTurn(
      conversationId: activeConvId,
      messageId: effectiveMessageId > 0
          ? effectiveMessageId
          : DateTime.now().millisecondsSinceEpoch,
      userMessage: effectiveUser,
      assistantMessage: reply,
      lastMessagePreview: reply.length > 200 ? reply.substring(0, 200) : reply,
      userPayload: userPayload,
    );
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
    if (conversationId <= 0 || (trimmedUser.isEmpty && trimmedReply.isEmpty)) return;

    final serverRows = existingMessages.where((m) => !m.isWelcome).toList(growable: false);
    final trackedUserAt = _userMessageAtByConv[conversationId];
    final hasUser = trimmedUser.isNotEmpty &&
        (serverRows.any((m) => m.role == 'user' && m.text.trim() == trimmedUser) ||
            trackedUserAt != null);
    final hasAssistant = trimmedReply.isNotEmpty &&
        serverRows.any((m) => m.role == 'assistant' && m.text.trim() == trimmedReply);

    final activeConvId = conversationId;
    if (!hasUser && trimmedUser.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('[NativeNova] finalize persist missing user conv=$conversationId');
      }
      final recovered = await resolveLatestUserMessage(conversationId, fallbackText: trimmedUser);
      final userId = recovered?.id ?? 0;
      final userAt = trackedUserAt ??
          recovered?.createdAt ??
          (userId > 0 ? DateTime.fromMillisecondsSinceEpoch(userId) : DateTime.now());
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
    if (!hasAssistant && trimmedReply.isNotEmpty && trimmedReply != trimmedUser) {
      if (kDebugMode) {
        debugPrint('[NativeNova] finalize persist missing assistant conv=$conversationId');
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
      createdAt: _userMessageAtByConv[conversationId] ??
          (fallbackId > 0 ? DateTime.fromMillisecondsSinceEpoch(fallbackId) : DateTime.now()),
    );
  }

  Future<void> _persistSessionMessages(int conversationId, List<NativeNovaMessage> messages) async {
    final uid = session.userId;
    if (uid <= 0 || conversationId <= 0 || messages.isEmpty) return;
    final rows = _stripIncompleteStreamingMessages(messages)
        .where((m) => !m.isWelcome)
        .map(
          (m) => <String, dynamic>{
            'id': m.id,
            'role': m.role,
            'kind': m.streaming && m.role == 'assistant' ? 'AI_ASSISTANT' : m.kind,
            'bodyText': m.text,
            'content': m.text,
            'createdAt': (m.createdAt ?? DateTime.now()).toUtc().toIso8601String(),
            if (m.streaming) 'streaming': true,
            if (m.thinkText.isNotEmpty) 'thinkText': m.thinkText,
            if (m.thinkStatus.isNotEmpty) 'thinkStatus': m.thinkStatus,
            if (m.payload != null)
              'payload': m.payload
            else if (m.attachments.isNotEmpty)
              'payload': <String, dynamic>{
                'attachments': m.attachments.map((a) => a.toJson()).toList(growable: false),
              },
            if (m.attachments.isNotEmpty)
              'attachments': m.attachments.map((a) => a.toJson()).toList(growable: false),
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

  List<Map<String, dynamic>> _filterNovaMsgsForSelf(List<Map<String, dynamic>> rows) {
    final self = session.userId;
    if (self <= 0) return rows;
    return rows.where((m) {
      final kind = (m['kind'] ?? 'TEXT').toString().toUpperCase();
      if (kind == 'AI_ASSISTANT' || kind == 'AI_TOOL_CALL') return true;
      final role = (m['role'] ?? '').toString().toLowerCase();
      if (role == 'assistant' || role == 'system') return true;
      if (role == 'user') return true;
      final sender = m['sender'] is Map ? m['sender'] as Map : const {};
      final sid = (sender['userId'] as num?)?.toInt() ??
          (m['senderUserId'] as num?)?.toInt() ??
          (m['userId'] as num?)?.toInt() ??
          0;
      return sid <= 0 || sid == self;
    }).toList(growable: false);
  }

  NativeNovaMessage _mapRawMessage(Map<String, dynamic> raw) {
    final kind = (raw['kind'] ?? 'TEXT').toString().toUpperCase();
    final sender = raw['sender'] is Map ? Map<String, dynamic>.from(raw['sender'] as Map) : <String, dynamic>{};
    final senderUid = _novaSenderUid(raw, sender);
    final senderName = (sender['displayName'] ?? raw['senderDisplayName'] ?? '').toString().trim();
    final role = _novaMessageRole(raw, kind: kind, senderUid: senderUid, senderName: senderName);
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
      durationSec = (payload['durationSec'] as num?)?.toInt() ??
          int.tryParse(text.replaceAll(RegExp(r'\D'), '')) ??
          1;
      if (text.isEmpty) text = "[语音] ${durationSec}s";
    }
    if (effectiveKind == 'IMAGE' && (text.isEmpty || _isNovaImagePlaceholderText(text))) {
      text = (payload?['fileName'] ??
              (attachments.isNotEmpty ? attachments.first.fileName : null) ??
              '图片')
          .toString();
    }
    if (effectiveKind == 'FILE' && text.isEmpty) text = (payload?['fileName'] ?? '文件').toString();
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
    for (final source in [raw['attachments'], payload?['attachments']]) {
      if (source is! List) continue;
      for (final row in source) {
        if (row is Map) {
          out.add(NovaMessageAttachment.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }
    if (out.isEmpty) {
      out.addAll(_attachmentsFromPayload(payload, kind));
    }
    return out;
  }

  bool _attachmentIsImage(NovaMessageAttachment a) {
    if (a.kind.toUpperCase() == 'IMAGE') return true;
    if (a.mimeType.startsWith('image/')) return true;
    final ext = a.fileName.split('.').last.toLowerCase();
    return ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'gif' || ext == 'webp' || ext == 'heic';
  }

  bool _isNovaImagePlaceholderText(String text) {
    final t = text.trim();
    return t == '[图片]' || t.startsWith('[图片]');
  }

  List<NovaMessageAttachment> _attachmentsFromPayload(Map<String, dynamic>? payload, String kind) {
    if (payload == null) return const <NovaMessageAttachment>[];
    final list = payload['attachments'];
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => NovaMessageAttachment.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    if (kind == 'IMAGE' || kind == 'FILE' || kind == 'AUDIO') {
      if (payload['url'] != null || payload['objectKey'] != null) {
        return [NovaMessageAttachment.fromJson(<String, dynamic>{...payload, 'kind': kind})];
      }
    }
    return const <NovaMessageAttachment>[];
  }

  bool _readBoolField(dynamic data, String key) {
    if (data is! Map) return false;
    return data[key] == true;
  }

  Future<String> resolveMediaUrl(String source, {String bucket = 'im-attachments'}) async {
    if (source.startsWith('http://') || source.startsWith('https://')) return source;
    final resp = await _client.get(
      _dunesUri('/storage/presigned-get?bucket=$bucket&objectKey=${Uri.encodeQueryComponent(source)}'),
      headers: _dunesHeaders,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('媒体地址解析失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      final url = (data['url'] ?? '').toString();
      if (url.isNotEmpty) return url;
    }
    throw Exception('媒体地址解析失败');
  }

  Future<NovaHistoryPageResult> fetchHistoryTurns({
    int size = 20,
    String before = '',
  }) async {
    final beforeQ = before.trim().isEmpty ? '' : '&before=${Uri.encodeQueryComponent(before.trim())}';
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
    final items = turns.map(_mapHistoryTurn).where((t) => t.conversationId > 0).toList();
    return NovaHistoryPageResult(items: items, hasMore: turns.length >= size);
  }

  NovaHistoryTurn _mapHistoryTurn(Map<String, dynamic> raw) {
    final preview = novaTurnPreview(raw);
    return NovaHistoryTurn(
      conversationId: _turnConvId(raw),
      messageId: (raw['messageId'] as num?)?.toInt() ??
          (raw['message_id'] as num?)?.toInt() ??
          0,
      title: novaTurnTitle(raw),
      preview: preview,
      lastMessageAt: parseNovaDateTime(
        raw['lastMessageAt'] ?? raw['last_message_at'] ?? raw['createdAt'] ?? raw['created_at'],
      ),
    );
  }

  void cancelActiveStream() {
    userStoppedStream = true;
    _streamClient?.close();
    _streamClient = null;
  }

  String get novaBizUserId {
    final stored = (session.novaLocalStorage?['dunes_nova_biz_user_id'] ?? '').trim();
    if (stored.isNotEmpty) return stored;
    return 'dune_${session.userId}';
  }

  String get novaProfileSessionId => 'profile-$novaBizUserId';

  String get asrModel =>
      (session.novaLocalStorage?['dunes_nova_asr_model'] ?? NovaConfig.asrModel).trim();

  String imagePartTypeForModel(String model) {
    final stored = (session.novaLocalStorage?['dunes_nova_image_part_type'] ?? '').trim();
    if (stored == 'image_url' || stored == 'input_image') return stored;
    if (RegExp(r'gpt|nova_gpt', caseSensitive: false).hasMatch(model)) return 'image_url';
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
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
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

  Future<String> transcribeAudio(Uint8List bytes, String fileName) async {
    final req = http.MultipartRequest('POST', Uri.parse('$novaBase/v1/audio/transcriptions'));
    req.headers.addAll(novaHeaders());
    req.fields['model'] = asrModel;
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
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
      if (data is Map) (data['text'] ?? data['transcript'] ?? data['result'])?.toString().trim(),
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

  Future<dynamic> buildMultimodalContent({
    required String text,
    required List<NovaDraftAttachment> attachments,
    String? model,
  }) async {
    final imagePartType = imagePartTypeForModel(model ?? selectedModel);
    final parts = <Map<String, dynamic>>[];
    final trimmed = text.trim();
    if (trimmed.isNotEmpty) parts.add(<String, dynamic>{'type': 'text', 'text': trimmed});
    for (final a in attachments) {
      if (a.isImage) {
        final normalized = await normalizeImageForVision(a.bytes, fileName: a.fileName);
        final b64 = base64Encode(normalized.bytes);
        final dataUrl = 'data:${normalized.mimeType};base64,$b64';
        // 优先用已上传的公网/签名 URL（对齐 WebView resolveMultimodalFile），否则 data URL。
        final uploadedUrl = _resolveVisionImageUrl(a);
        final visionUrl = uploadedUrl ?? dataUrl;
        parts.add(_visionImagePart(imagePartType, visionUrl));
      } else {
        final b64 = base64Encode(a.bytes);
        parts.add(<String, dynamic>{
          'type': 'file',
          'file': <String, dynamic>{'filename': a.fileName, 'file_data': b64},
        });
      }
    }
    if (parts.isEmpty) return '';
    if (parts.length == 1 && parts.first['type'] == 'text') return parts.first['text'];
    return parts;
  }

  String? _resolveVisionImageUrl(NovaDraftAttachment draft) {
    final payload = draft.payload;
    if (payload == null) return null;
    for (final key in ['url', 'accessUrl', 'publicUrl', 'previewUrl']) {
      final raw = (payload[key] ?? '').toString().trim();
      if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    }
    return null;
  }

  /// 云枢 API 上下文：仅 system（当前用户）+ 本条 user；历史靠 X-Nova-Chat-Session-Id 服务端记忆。
  List<Map<String, dynamic>> buildNovaChatMessages(dynamic latestContent) {
    final out = <Map<String, dynamic>>[];
    final sys = _buildNovaUserSystemMessage();
    if (sys != null) out.add(sys);
    final hasLatest = latestContent != null &&
        !(latestContent is String && latestContent.toString().trim().isEmpty);
    if (hasLatest) out.add(<String, dynamic>{'role': 'user', 'content': latestContent});
    return out;
  }

  Map<String, dynamic>? _buildNovaUserSystemMessage() {
    final name = (session.displayName ?? '').trim();
    final uid = session.userId > 0 ? '${session.userId}' : '';
    final phone = session.phone.trim();
    final biz = novaBizUserId;
    if (name.isEmpty && uid.isEmpty && phone.isEmpty && biz.isEmpty) return null;
    final lines = <String>[
      '你是沙丘 APP 内置的企业助手「云枢」。',
      '以下「当前登录用户」信息来自沙丘账号系统，回答身份/称呼/手机号等问题时必须以此为准，不要臆造或使用其它昵称、历史测试名。',
    ];
    if (name.isNotEmpty) lines.add('姓名：$name');
    if (phone.isNotEmpty) lines.add('手机：$phone');
    if (uid.isNotEmpty) lines.add('用户ID：$uid');
    if (biz.isNotEmpty) lines.add('系统账号：$biz');
    lines.add('除非用户明确要求生成/下载文件，否则不要主动附带历史文件或杜撰附件。');
    return <String, dynamic>{'role': 'system', 'content': lines.join('\n')};
  }

  String _extractUserPromptText(dynamic userContent, {required String displayText}) {
    if (userContent is String && userContent.trim().isNotEmpty) return userContent.trim();
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
    int? userMessageId,
    bool skipUserPersist = false,
    required void Function(NovaStreamUpdate update) onUpdate,
    void Function(int conversationId)? onConversationId,
  }) async {
    final readiness = await checkReadiness();
    if (!readiness.ready) {
      throw Exception(readiness.message ?? '云枢账号尚未开通，请稍后再试');
    }
    if (novaApiKey.isEmpty) {
      throw Exception('云枢账号尚未就绪，请重新登录后再试');
    }
    var activeConvId = conversationId;
    final contentLabel = displayText ?? (userContent is String ? userContent : '[附件消息]');
    final userPrompt = _extractUserPromptText(userContent, displayText: contentLabel.toString());
    userStoppedStream = false;
    if (!skipUserPersist) {
      final fallbackId = userMessageId ?? DateTime.now().millisecondsSinceEpoch;
      await persistUserMessage(
        conversationId: activeConvId,
        messageId: fallbackId,
        content: contentLabel.toString(),
        metadata: userMetadata,
      );
    }

    _streamClient?.close();
    _streamClient = http.Client();
    final streamClient = _streamClient!;

    final model = selectedModel.isEmpty ? NovaConfig.defaultChatModel : selectedModel;

    var replyBuffer = '';
    var thinkBuffer = '';
    var hadOutput = false;
    String? streamError;

    void applySseEvent(NovaOpenAiSseEvent event) {
      if (event.error != null && event.error!.isNotEmpty) {
        streamError = event.error;
        return;
      }
      if (event.think.isNotEmpty) {
        hadOutput = true;
        thinkBuffer += event.think;
        onUpdate(NovaStreamUpdate(
          replyText: replyBuffer,
          thinkText: thinkBuffer.trim(),
          thinkStatus: event.status.isNotEmpty ? event.status : '思考中…',
        ));
      }
      if (event.text.isNotEmpty) {
        hadOutput = true;
        if (isHermesThinkLine(event.text)) {
          thinkBuffer += event.text;
          onUpdate(NovaStreamUpdate(
            replyText: replyBuffer,
            thinkText: thinkBuffer.trim(),
            thinkStatus: event.status.isNotEmpty ? event.status : '思考中…',
          ));
        } else {
          replyBuffer += event.text;
          onUpdate(NovaStreamUpdate(
            replyText: replyBuffer,
            thinkText: thinkBuffer.trim(),
            thinkStatus: event.status,
          ));
        }
      }
    }

    try {
      // 对齐 admin-web / WebView：直连 Nova /v1/chat/completions。
      final requestMessages = buildNovaChatMessages(userContent);
      final req = http.Request(
        'POST',
        Uri.parse('$novaBase/v1/chat/completions'),
      );
      final headers = novaHeaders(<String, String>{
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      });
      final sessionId = novaProfileSessionId.trim();
      if (sessionId.isNotEmpty) headers['X-Nova-Chat-Session-Id'] = sessionId;
      req.headers.addAll(headers);
      final body = <String, dynamic>{
        'model': model,
        'stream': true,
        'messages': requestMessages,
      };
      final bizUser = novaBizUserId.trim();
      if (bizUser.isNotEmpty) body['user'] = bizUser;
      req.body = jsonEncode(body);
      if (kDebugMode) {
        debugPrint(
          '[NativeNova] POST chat/completions conv=$activeConvId model=$model '
          'user=$bizUser session=$sessionId',
        );
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
          await _clearGeneratingMarkersForConversation(activeConvId);
          await stripStreamingFromSession(activeConvId);
          rethrow;
        }
      }

      if (streamError != null && streamError!.isNotEmpty) {
        throw Exception(streamError);
      }

      if (userStoppedStream) {
        final partial = novaFinalReplyText(replyBuffer, thinkBuffer, finalPass: true);
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
      var reply = novaFinalReplyText(finalParts.reply, thinkBuffer, finalPass: true);
      if (reply.isEmpty && thinkBuffer.trim().isNotEmpty) reply = thinkBuffer.trim();
      if (!hadOutput || reply.isEmpty) throw Exception('云枢未返回正文，请重试');
      if (reply.trim() == userPrompt.trim()) {
        throw Exception('云枢未返回正文，请重试');
      }
      await _saveLocalMessage(
        activeConvId,
        role: 'assistant',
        content: reply,
        kind: 'AI_ASSISTANT',
        messageId: (userMessageId ?? 0) > 0 ? userMessageId! + 1 : null,
        createdAt: _assistantCreatedAt(activeConvId),
      );
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
      throw Exception(readiness.message ?? '云枢账号尚未开通，请稍后再试');
    }
    if (novaApiKey.isEmpty) {
      throw Exception('云枢账号尚未就绪，请重新登录后再试');
    }
    await _saveLocalMessage(conversationId, role: 'user', content: text, kind: 'TEXT');
    final requestMessages = buildNovaChatMessages(text);
    final headers = novaHeaders(<String, String>{
      'Content-Type': 'application/json',
    });
    final sessionId = novaProfileSessionId.trim();
    if (sessionId.isNotEmpty) headers['X-Nova-Chat-Session-Id'] = sessionId;
    final requestBody = <String, dynamic>{
      'model': selectedModel.isEmpty ? NovaConfig.defaultChatModel : selectedModel,
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
    if (reply.isEmpty) throw Exception('云枢未返回正文，请重试');
    await _saveLocalMessage(conversationId, role: 'assistant', content: reply, kind: 'AI_ASSISTANT');
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

  Future<void> _clearGeneratingMarkersForConversation(int conversationId) async {
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
    final at = createdAt ??
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
  }

  Future<bool> _postLocalMessage(int conversationId, Map<String, dynamic> body) async {
    if (conversationId <= 0 || await isImInboxPlaceholderConvId(conversationId)) return false;
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
      if (kDebugMode) debugPrint('[NativeNova] messages/local error conv=$conversationId: $e');
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
    if (resp.statusCode == 400) return '云枢会话初始化异常，请发送一条消息重试';
    if (resp.statusCode == 503) return '云枢服务暂不可用';
    return '$fallback（HTTP ${resp.statusCode}）';
  }

  String _parseNovaHttpError(int status, String bodyText) {
    try {
      final body = _decode(bodyText);
      final msg = (body['error']?['message'] ?? body['message'] ?? '').toString().trim();
      if (msg.isNotEmpty) return msg;
    } catch (_) {}
    if (status == 503) return '云枢服务暂不可用';
    return '云枢回复失败（HTTP $status）';
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const <String, dynamic>{};
  }

  List<Map<String, dynamic>> _extractTurns(Map<String, dynamic> body) {
    final data = body['data'];
    if (data is List) return data.whereType<Map<String, dynamic>>().toList(growable: false);
    if (data is Map<String, dynamic>) {
      final items = data['items'];
      if (items is List) return items.whereType<Map<String, dynamic>>().toList(growable: false);
      final turns = data['turns'];
      if (turns is List) return turns.whereType<Map<String, dynamic>>().toList(growable: false);
    }
    return const <Map<String, dynamic>>[];
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
