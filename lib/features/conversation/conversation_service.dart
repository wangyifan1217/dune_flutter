import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../auth/auth_session.dart';
import '../nova/nova_history_utils.dart';
import 'conversation_models.dart';

/// 上传分块大小：把文件切成小块逐块写入，配合 socket 背压才能得到真实的
/// 上传进度（直接用 fromBytes 会一次性吐出全部字节导致进度瞬间到 100%）。
const int _uploadChunkSize = 64 * 1024;

/// 构造一个按块上报进度的 multipart 文件部件。
http.MultipartFile _progressMultipartFile(
  String field,
  Uint8List bytes,
  String filename,
  void Function(int sent, int total)? onProgress,
) {
  final total = bytes.length;
  Stream<List<int>> chunked() async* {
    var offset = 0;
    if (total == 0) {
      onProgress?.call(0, 0);
      return;
    }
    while (offset < total) {
      final end = (offset + _uploadChunkSize < total)
          ? offset + _uploadChunkSize
          : total;
      yield bytes.sublist(offset, end);
      offset = end;
      onProgress?.call(offset, total);
    }
  }

  return http.MultipartFile(
    field,
    http.ByteStream(chunked()),
    total,
    filename: filename,
  );
}

class ConversationService {
  ConversationService({required AuthSession session, http.Client? client})
    : this._(session, client ?? http.Client());

  ConversationService._(this._session, this._client);

  final AuthSession _session;
  final http.Client _client;
  static const int _maxSendAttempts = 3;

  Uri _uri(String path) => Uri.parse('${_session.apiBase}$path');

  Map<String, String> get _headers => <String, String>{
    'Authorization': 'Bearer ${_session.token}',
    'Content-Type': 'application/json',
  };

  Future<List<NativeConversation>> fetchConversations() async {
    final resp = await _client.get(_uri('/conversations'), headers: _headers);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('会话列表加载失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '会话列表加载失败').toString());
    }
    final data = (body['data'] as List<dynamic>? ?? const <dynamic>[]);
    return data
        .whereType<Map<String, dynamic>>()
        .map(_mapConversation)
        .toList(growable: false);
  }

  /// 服务端统一未读总数（与 TPNS 推送 badgeCount 口径一致）。
  Future<int?> fetchTotalUnread() async {
    final uri = _uri('/comm/unread-total');
    final resp = await _client.get(uri, headers: _headers);
    print(
      '[BadgeAPI] GET $uri status=${resp.statusCode} body=${resp.body}',
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('未读总数加载失败: HTTP ${resp.statusCode} ${resp.body}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '未读总数加载失败').toString());
    }
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      return (data['totalUnread'] as num?)?.toInt();
    }
    return (body['totalUnread'] as num?)?.toInt();
  }

  Future<int?> ensurePrivateConversationForPeer(int peerUserId) async {
    if (peerUserId <= 0 || peerUserId == _session.userId) return null;
    final rows = await fetchConversations();
    for (final c in rows) {
      if (c.kind != 'PRIVATE') continue;
      if ((c.peerUserId ?? 0) == peerUserId && c.isVisible) return c.id;
    }
    final resp = await _client.post(
      _uri('/conversations'),
      headers: _headers,
      body: jsonEncode(<String, dynamic>{
        'kind': 'PRIVATE',
        'title': '私聊',
        'memberUserIds': <int>[peerUserId],
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('创建私聊会话失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '创建私聊会话失败').toString());
    }
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      return (data['conversationId'] as num?)?.toInt() ??
          (data['id'] as num?)?.toInt();
    }
    return null;
  }

  Future<NativeConversation?> createConversation({
    required String kind,
    required List<int> memberUserIds,
    String? title,
  }) async {
    final ids = memberUserIds
        .where((id) => id > 0 && id != _session.userId)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return null;
    final resp = await _client.post(
      _uri('/conversations'),
      headers: _headers,
      body: jsonEncode(<String, dynamic>{
        'kind': kind,
        'title': (title ?? '').trim().isEmpty
            ? (kind == 'PRIVATE' ? '私聊' : '群聊')
            : title!.trim(),
        'memberUserIds': ids,
      }),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('创建会话失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '创建会话失败').toString());
    }
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      if (data.containsKey('kind') ||
          data.containsKey('title') ||
          data.containsKey('peer')) {
        return _mapConversation(data);
      }
      final convId =
          (data['conversationId'] as num?)?.toInt() ??
          (data['id'] as num?)?.toInt() ??
          0;
      if (convId > 0) {
        return fetchConversation(convId);
      }
    }
    return null;
  }

  Future<NativeConversation?> fetchConversation(int conversationId) async {
    final resp = await _client.get(
      _uri('/conversations/$conversationId'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('会话详情加载失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '会话详情加载失败').toString());
    }
    final data = body['data'];
    if (data is! Map<String, dynamic>) return null;
    return _mapConversation(data);
  }

  Future<List<NativeChatMessage>> fetchMessages(
    int conversationId, {
    int size = 30,
    int? before,
    int? after,
    int? around,
  }) async {
    final page = await fetchMessagePage(
      conversationId,
      size: size,
      before: before,
      after: after,
      around: around,
    );
    return page.items;
  }

  Future<NativeMessagePage> fetchMessagePage(
    int conversationId, {
    int size = 30,
    int? before,
    int? after,
    int? around,
  }) async {
    final query = <String>['size=$size'];
    if (before != null && before > 0) query.add('before=$before');
    if (after != null && after > 0) query.add('after=$after');
    if (around != null && around > 0) query.add('around=$around');
    final resp = await _client.get(
      _uri('/conversations/$conversationId/messages?${query.join('&')}'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('消息加载失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '消息加载失败').toString());
    }
    final data = body['data'];
    final rows = _rowsFromData(data);
    final items = rows
        .whereType<Map<String, dynamic>>()
        .map(_mapMessage)
        .toList(growable: false);
    return NativeMessagePage(
      items: items,
      hasMore: _readBoolField(data, 'hasMore'),
      hasNewer: _readBoolField(data, 'hasNewer'),
      peerLastReadMessageId: _readIntField(data, 'peerLastReadMessageId'),
    );
  }

  Future<NativeMessagePage> fetchMessagesAround(
    int conversationId,
    int messageId, {
    NativeChatMessage? hint,
  }) async {
    if (messageId <= 0) {
      return fetchMessagePage(conversationId, size: 20);
    }
    var page = await fetchMessagePage(
      conversationId,
      size: 40,
      around: messageId,
    );
    if (page.items.any((m) => m.id == messageId)) {
      return page;
    }
    if (hint != null && hint.id == messageId) {
      final merged = _mergeMessages(<NativeChatMessage>[hint], page.items);
      return NativeMessagePage(
        items: merged,
        hasMore: page.hasMore,
        hasNewer: page.hasNewer,
        peerLastReadMessageId: page.peerLastReadMessageId,
      );
    }
    final older = await fetchMessagePage(
      conversationId,
      size: 25,
      before: messageId,
    );
    final newer = await fetchMessagePage(
      conversationId,
      size: 25,
      after: messageId,
    );
    var merged = _mergeMessages(older.items, newer.items);
    if (!merged.any((m) => m.id == messageId)) {
      final hit = hint ?? await _findMessageInSearch(conversationId, messageId);
      if (hit != null) {
        merged = _mergeMessages(merged, <NativeChatMessage>[hit]);
      }
    }
    merged.sort((a, b) => a.id.compareTo(b.id));
    return NativeMessagePage(
      items: merged,
      hasMore: older.hasMore || older.items.isNotEmpty,
      hasNewer: newer.hasNewer || newer.items.isNotEmpty,
      peerLastReadMessageId:
          page.peerLastReadMessageId ?? newer.peerLastReadMessageId,
    );
  }

  Future<NativeChatMessage?> _findMessageInSearch(
    int conversationId,
    int messageId,
  ) async {
    var before = messageId + 1;
    for (var i = 0; i < 12; i++) {
      final resp = await _client.get(
        _uri(
          '/conversations/$conversationId/messages/search?q=&size=50&before=$before',
        ),
        headers: _headers,
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) break;
      final body = _decode(resp.body);
      final data = body['data'];
      final rows = _rowsFromData(data);
      final items = rows
          .whereType<Map<String, dynamic>>()
          .map(_mapMessage)
          .toList();
      for (final m in items) {
        if (m.id == messageId) return m;
      }
      if (items.isEmpty) break;
      final oldest = items.first.id;
      if (oldest >= before) break;
      before = oldest;
    }
    return null;
  }

  List<NativeChatMessage> _mergeMessages(
    List<NativeChatMessage> a,
    List<NativeChatMessage> b,
  ) {
    final map = <int, NativeChatMessage>{};
    for (final m in [...a, ...b]) {
      if (m.id > 0) map[m.id] = m;
    }
    final out = map.values.toList()..sort((x, y) => x.id.compareTo(y.id));
    return out;
  }

  bool _readBoolField(dynamic data, String key) {
    if (data is Map && data[key] == true) return true;
    return false;
  }

  int? _readIntField(dynamic data, String key) {
    if (data is Map) {
      final v = data[key];
      if (v is num) return v.toInt();
    }
    return null;
  }

  Future<void> sendText(
    int conversationId,
    String text, {
    Map<String, dynamic>? payload,
  }) async {
    for (var attempt = 1; attempt <= _maxSendAttempts; attempt++) {
      try {
        final resp = await _client.post(
          _uri('/conversations/$conversationId/messages'),
          headers: _headers,
          body: jsonEncode(<String, dynamic>{
            'kind': 'TEXT',
            'bodyText': text,
            'payload': payload,
          }),
        );
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          if (_isRetryableStatus(resp.statusCode) &&
              attempt < _maxSendAttempts) {
            await _delayForRetry(attempt);
            continue;
          }
          throw Exception('发送失败: HTTP ${resp.statusCode}');
        }
        final body = _decode(resp.body);
        if (body['success'] == false) {
          throw Exception((body['message'] ?? '发送失败').toString());
        }
        return;
      } catch (_) {
        if (attempt >= _maxSendAttempts) rethrow;
        await _delayForRetry(attempt);
      }
    }
  }

  Future<void> markConversationRead(int conversationId) async {
    final resp = await _client.post(
      _uri('/conversations/$conversationId/read'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) return;
  }

  Future<void> sendImage({
    required int conversationId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String sourceLabel,
    Uint8List? previewBytes,
    String? previewFileName,
    String? previewMimeType,
    void Function(double progress)? onProgress,
  }) async {
    final uploaded = await uploadAttachment(
      conversationId: conversationId,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      onProgress: onProgress,
    );
    final url = uploaded.bestUrl;
    final objectKey = _isPublicMediaUrl(url) ? '' : url;

    // 默认预览即原图（兼容压缩失败/无预览的情况）。
    var previewUrl = url;
    var previewObjectKey = objectKey;
    if (previewBytes != null && previewBytes.isNotEmpty) {
      try {
        final preview = await uploadAttachment(
          conversationId: conversationId,
          bytes: previewBytes,
          fileName: previewFileName ?? fileName,
          mimeType: previewMimeType ?? 'image/jpeg',
        );
        previewUrl = preview.bestUrl;
        previewObjectKey = _isPublicMediaUrl(previewUrl) ? '' : previewUrl;
      } catch (_) {
        previewUrl = url;
        previewObjectKey = objectKey;
      }
    }

    await _sendAttachment(
      conversationId: conversationId,
      kind: 'IMAGE',
      bodyText: '[$sourceLabel] $fileName',
      payload: <String, dynamic>{
        'url': url,
        'objectKey': objectKey,
        'previewUrl': previewUrl,
        'previewObjectKey': previewObjectKey,
        'fileName': fileName,
        'mimeType': mimeType,
      },
    );
  }

  Future<void> sendFile({
    required int conversationId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final uploaded = await uploadAttachment(
      conversationId: conversationId,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      onProgress: onProgress,
    );
    final url = uploaded.bestUrl;
    await _sendAttachment(
      conversationId: conversationId,
      kind: 'FILE',
      bodyText: fileName,
      payload: <String, dynamic>{
        'url': url,
        'objectKey': _isPublicMediaUrl(url) ? '' : url,
        'mimeType': mimeType,
        'fileName': fileName,
        'size': bytes.length,
      },
    );
  }

  Future<void> sendAudio({
    required int conversationId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required int durationSec,
  }) async {
    final uploaded = await uploadAttachment(
      conversationId: conversationId,
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    final url = uploaded.bestUrl;
    await _sendAttachment(
      conversationId: conversationId,
      kind: 'AUDIO',
      bodyText: '[语音] ${durationSec}s',
      payload: <String, dynamic>{
        'url': url,
        'objectKey': _isPublicMediaUrl(url) ? '' : url,
        'mimeType': mimeType,
        'durationSec': durationSec,
        'fileName': fileName,
        'size': bytes.length,
      },
    );
  }

  Future<UploadedAttachment> uploadAttachment({
    required int conversationId,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    for (var attempt = 1; attempt <= _maxSendAttempts; attempt++) {
      try {
        final req = http.MultipartRequest('POST', _uri('/storage/upload'));
        req.headers['Authorization'] = 'Bearer ${_session.token}';
        req.fields['bucket'] = 'im-attachments';
        req.fields['conversationId'] = '$conversationId';
        req.files.add(
          _progressMultipartFile(
            'file',
            bytes,
            fileName,
            onProgress == null
                ? null
                : (sent, total) {
                    if (total > 0) onProgress((sent / total).clamp(0.0, 1.0));
                  },
          ),
        );
        final streamed = await _client.send(req);
        final bodyText = await streamed.stream.bytesToString();
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          if (_isRetryableStatus(streamed.statusCode) &&
              attempt < _maxSendAttempts) {
            await _delayForRetry(attempt);
            continue;
          }
          throw Exception('上传失败: HTTP ${streamed.statusCode}');
        }
        final body = _decode(bodyText);
        if (body['success'] == false) {
          throw Exception((body['message'] ?? '上传失败').toString());
        }
        final data = body['data'];
        if (data is! Map<String, dynamic>) {
          throw Exception('上传失败: 返回数据异常');
        }
        final url = (data['url'] ?? '').toString();
        final objectKey = (data['objectKey'] ?? url).toString();
        if (url.isEmpty && objectKey.isEmpty) {
          throw Exception('上传失败: 未返回文件地址');
        }
        return UploadedAttachment(url: url, objectKey: objectKey);
      } catch (e) {
        if (attempt >= _maxSendAttempts) rethrow;
        await _delayForRetry(attempt);
      }
    }
    throw Exception('上传失败: 重试次数已达上限');
  }

  Future<void> _sendAttachment({
    required int conversationId,
    required String kind,
    required String bodyText,
    required Map<String, dynamic> payload,
  }) async {
    for (var attempt = 1; attempt <= _maxSendAttempts; attempt++) {
      try {
        final resp = await _client.post(
          _uri('/conversations/$conversationId/messages'),
          headers: _headers,
          body: jsonEncode(<String, dynamic>{
            'kind': kind,
            'bodyText': bodyText,
            'payload': payload,
          }),
        );
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          if (_isRetryableStatus(resp.statusCode) &&
              attempt < _maxSendAttempts) {
            await _delayForRetry(attempt);
            continue;
          }
          throw Exception('发送失败: HTTP ${resp.statusCode}');
        }
        final body = _decode(resp.body);
        if (body['success'] == false) {
          throw Exception((body['message'] ?? '发送失败').toString());
        }
        return;
      } catch (e) {
        if (attempt >= _maxSendAttempts) rethrow;
        await _delayForRetry(attempt);
      }
    }
  }

  bool _isRetryableStatus(int statusCode) =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;

  Future<void> _delayForRetry(int attempt) async {
    await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
  }

  Future<void> recallMessage({
    required int conversationId,
    required int messageId,
  }) async {
    if (conversationId <= 0 || messageId <= 0) return;
    final resp = await _client.post(
      _uri('/conversations/$conversationId/messages/$messageId/recall'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('撤回失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '撤回失败').toString());
    }
  }

  Future<List<NativeChatMessage>> searchMessages({
    required int conversationId,
    required String query,
    int size = 20,
    int page = 1,
    int? before,
  }) async {
    final pageResult = await searchMessagePage(
      conversationId: conversationId,
      query: query,
      size: size,
      page: page,
      before: before,
    );
    return pageResult.items;
  }

  Future<NativeSearchMessagePage> searchMessagePage({
    required int conversationId,
    required String query,
    int size = 20,
    int page = 1,
    int? before,
  }) async {
    final q = Uri.encodeQueryComponent(query.trim());
    final beforeQ = before != null && before > 0 ? '&before=$before' : '';
    final resp = await _client.get(
      _uri(
        '/conversations/$conversationId/messages/search?q=$q&size=$size&page=$page$beforeQ',
      ),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('搜索失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '搜索失败').toString());
    }
    final data = body['data'];
    final rows = _rowsFromData(data);
    final items = rows
        .whereType<Map<String, dynamic>>()
        .map(_mapMessage)
        .toList(growable: false);
    final hasMore = _readBoolField(data, 'hasMore') || items.length >= size;
    return NativeSearchMessagePage(items: items, hasMore: hasMore);
  }

  /// im-go 消息类接口：`data` 为 `{ items: [...] }`；会话列表等仍为数组。
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

  List<Map<String, dynamic>> _memberRowsFromPayload(dynamic data) {
    if (data is! Map) return const <Map<String, dynamic>>[];
    final members = data['members'];
    if (members is! List) return const <Map<String, dynamic>>[];
    return members
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .where((m) => ((m['userId'] as num?)?.toInt() ?? 0) > 0)
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _statusRowsFromPayload(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(Map<String, dynamic>.from)
          .toList(growable: false);
    }
    if (data is Map<String, dynamic>) {
      final rows = data['members'] ?? data['items'] ?? data['readers'];
      if (rows is List) {
        return rows
            .whereType<Map<String, dynamic>>()
            .map(Map<String, dynamic>.from)
            .toList(growable: false);
      }
    }
    return _rowsFromData(data)
        .whereType<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchGroupReadStatus(
    int conversationId,
  ) async {
    final resp = await _client.get(
      _uri('/conversations/$conversationId/read-status'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return const <Map<String, dynamic>>[];
    }
    final body = _decode(resp.body);
    final data = body['data'];
    return _statusRowsFromPayload(data);
  }

  Future<NativeGroupInfo> fetchGroupInfo(int conversationId) async {
    final resp = await _client.get(
      _uri('/conversations/$conversationId/info'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('群信息加载失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '群信息加载失败').toString());
    }
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('群信息加载失败: 数据为空');
    }
    return _mapGroupInfo(data, conversationId);
  }

  Future<int> fetchMediaCount(int conversationId) async {
    final resp = await _client.get(
      _uri('/conversations/$conversationId/media?size=1'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) return 0;
    final body = _decode(resp.body);
    final data = body['data'];
    if (data is Map) {
      final total = data['total'];
      if (total is num) return total.toInt();
      final items = data['items'];
      if (items is List) return items.length;
    }
    if (data is List) return data.length;
    return 0;
  }

  Future<List<NativeChatMessage>> fetchConversationMedia(
    int conversationId, {
    int size = 50,
    int? before,
  }) async {
    final query = <String>['size=$size'];
    if (before != null && before > 0) query.add('before=$before');
    final resp = await _client.get(
      _uri('/conversations/$conversationId/media?${query.join('&')}'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('媒体列表加载失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '媒体列表加载失败').toString());
    }
    final data = body['data'];
    return _rowsFromData(data)
        .whereType<Map<String, dynamic>>()
        .map(_mapMessage)
        .toList(growable: false);
  }

  Future<void> patchMySettings(
    int conversationId, {
    bool? muted,
    bool? pinned,
  }) async {
    final payload = <String, dynamic>{};
    if (muted != null) payload['muted'] = muted;
    if (pinned != null) payload['pinned'] = pinned;
    final resp = await _client.patch(
      _uri('/conversations/$conversationId/my-settings'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('设置失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '设置失败').toString());
    }
  }

  Future<void> patchConversationTitle(int conversationId, String title) async {
    final resp = await _client.patch(
      _uri('/conversations/$conversationId'),
      headers: _headers,
      body: jsonEncode(<String, dynamic>{'title': title}),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('修改群名称失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '修改群名称失败').toString());
    }
  }

  Future<int> addGroupMembers(int conversationId, List<int> userIds) async {
    final resp = await _client.post(
      _uri('/conversations/$conversationId/members'),
      headers: _headers,
      body: jsonEncode(<String, dynamic>{'userIds': userIds}),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('添加成员失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '添加成员失败').toString());
    }
    final data = body['data'];
    if (data is Map && data['added'] is num)
      return (data['added'] as num).toInt();
    return userIds.length;
  }

  Future<void> removeGroupMember(int conversationId, int userId) async {
    final resp = await _client.delete(
      _uri('/conversations/$conversationId/members/$userId'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('移除成员失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '移除成员失败').toString());
    }
  }

  Future<void> dissolveGroup(int conversationId) async {
    final resp = await _client.post(
      _uri('/conversations/$conversationId/dissolve'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('解散群聊失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '解散群聊失败').toString());
    }
  }

  /// 与 WebView `exitGroupMembership` 对齐：优先 leave，失败时尝试删除自己的成员关系。
  Future<bool> exitGroupMembership(
    int conversationId, {
    bool dissolved = false,
  }) async {
    try {
      final resp = await _client.post(
        _uri('/conversations/$conversationId/leave'),
        headers: _headers,
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = _decode(resp.body);
        if (body['success'] != false) return true;
        final msg = (body['message'] ?? '退出失败').toString();
        if (!dissolved && !_isDissolvedExitError(msg)) throw Exception(msg);
      } else if (!dissolved) {
        throw Exception('退出失败: HTTP ${resp.statusCode}');
      }
    } catch (e) {
      final msg = e.toString();
      if (!dissolved && !_isDissolvedExitError(msg)) rethrow;
    }
    final me = _session.userId;
    if (me <= 0) return false;
    try {
      await removeGroupMember(conversationId, me);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isDissolvedExitError(String msg) =>
      RegExp(r'dissolved|解散|该群已解散', caseSensitive: false).hasMatch(msg);

  NativeGroupInfo _mapGroupInfo(Map<String, dynamic> raw, int fallbackId) {
    final membersRaw = raw['members'];
    final members = membersRaw is List
        ? membersRaw
              .whereType<Map<String, dynamic>>()
              .map(
                (m) => NativeGroupMember(
                  userId: (m['userId'] as num?)?.toInt() ?? 0,
                  displayName: (m['displayName'] ?? m['name'] ?? '成员')
                      .toString(),
                  role: m['role']?.toString(),
                  roleLabel: (m['roleLabel'] ?? m['title'])?.toString(),
                  avatarPreset:
                      (m['avatarPreset'] ?? '').toString().trim().isEmpty
                      ? null
                      : (m['avatarPreset'] ?? '').toString(),
                  avatarObjectKey:
                      (m['avatarObjectKey'] ?? '').toString().trim().isEmpty
                      ? null
                      : (m['avatarObjectKey'] ?? '').toString(),
                ),
              )
              .where((m) => m.userId > 0)
              .toList(growable: false)
        : const <NativeGroupMember>[];
    final dissolved =
        raw['dissolved'] == true ||
        raw['isDissolved'] == true ||
        raw['status']?.toString() == 'DISSOLVED' ||
        raw['frozen'] == true;
    return NativeGroupInfo(
      id: (raw['id'] as num?)?.toInt() ?? fallbackId,
      kind: (raw['kind'] ?? '').toString(),
      title: (raw['title'] ?? '群聊').toString(),
      members: members,
      muted: raw['muted'] == true,
      pinned: raw['pinned'] == true,
      isOwner: raw['isOwner'] == true,
      canLeave: raw['canLeave'] == true,
      dissolved: dissolved,
      createdAt: DateTime.tryParse((raw['createdAt'] ?? '').toString()),
      businessType: raw['businessType']?.toString(),
      businessId: raw['businessId']?.toString(),
    );
  }

  Future<Map<String, dynamic>?> fetchApprovalTrail(
    String businessType,
    String businessId,
  ) async {
    final resp = await _client.get(
      _uri('/approvals/${Uri.encodeComponent(businessType)}/$businessId'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    final body = _decode(resp.body);
    if (body['success'] == false) return null;
    final data = body['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchConversationMembers(
    int conversationId,
  ) async {
    if (conversationId <= 0) return const <Map<String, dynamic>>[];

    // 对齐 WebView loadChat：优先 /info，回退 GET /conversations/:id
    final infoResp = await _client.get(
      _uri('/conversations/$conversationId/info'),
      headers: _headers,
    );
    if (infoResp.statusCode >= 200 && infoResp.statusCode < 300) {
      final body = _decode(infoResp.body);
      if (body['success'] is! bool || body['success'] != false) {
        final rows = _memberRowsFromPayload(body['data']);
        if (rows.isNotEmpty) return rows;
      }
    }

    final convResp = await _client.get(
      _uri('/conversations/$conversationId'),
      headers: _headers,
    );
    if (convResp.statusCode >= 200 && convResp.statusCode < 300) {
      final body = _decode(convResp.body);
      if (body['success'] is! bool || body['success'] != false) {
        final rows = _memberRowsFromPayload(body['data']);
        if (rows.isNotEmpty) return rows;
      }
    }

    throw Exception('成员加载失败: HTTP ${infoResp.statusCode}');
  }

  Future<List<NativeConversation>> fetchBroadcastConversations() async {
    final resp = await _client.get(
      _uri('/conversations?kind=BROADCAST'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('广播加载失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    if (body['success'] == false) {
      throw Exception((body['message'] ?? '广播加载失败').toString());
    }
    final data = (body['data'] as List<dynamic>? ?? const <dynamic>[]);
    return data
        .whereType<Map<String, dynamic>>()
        .map(_mapConversation)
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchMessageReadReceipts({
    required int conversationId,
    required int messageId,
  }) async {
    final resp = await _client.get(
      _uri('/conversations/$conversationId/messages/$messageId/read-receipts'),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      return const <Map<String, dynamic>>[];
    }
    final body = _decode(resp.body);
    if (body['success'] is bool && body['success'] == false) {
      return const <Map<String, dynamic>>[];
    }
    final data = body['data'];
    return _statusRowsFromPayload(data);
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return const <String, dynamic>{};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    return const <String, dynamic>{};
  }

  NativeConversation mapConversation(Map<String, dynamic> raw) =>
      _mapConversation(raw);

  NativeChatMessage mapMessage(Map<String, dynamic> raw) => _mapMessage(raw);

  NativeConversation _mapConversation(Map<String, dynamic> raw) {
    final peer = raw['peer'];
    var peerMap = peer is Map<String, dynamic>
        ? peer
        : const <String, dynamic>{};
    final membersRaw = raw['members'];
    if (peerMap.isEmpty && membersRaw is List) {
      for (final m in membersRaw) {
        if (m is! Map<String, dynamic>) continue;
        final uid = (m['userId'] as num?)?.toInt() ?? 0;
        if (uid > 0 && uid != _session.userId) {
          peerMap = m;
          break;
        }
      }
    } else {
      final peerId =
          (peerMap['userId'] as num?)?.toInt() ??
          (raw['peerUserId'] as num?)?.toInt() ??
          0;
      if (peerId > 0 && peerId == _session.userId && membersRaw is List) {
        for (final m in membersRaw) {
          if (m is! Map<String, dynamic>) continue;
          final uid = (m['userId'] as num?)?.toInt() ?? 0;
          if (uid > 0 && uid != _session.userId) {
            peerMap = m;
            break;
          }
        }
      }
    }
    final preview = _previewFrom(raw);
    final kind = (raw['kind'] ?? '').toString();
    final peerName = (raw['peerDisplayName'] ?? peerMap['displayName'])
        ?.toString()
        .trim();
    final rawTitle = (raw['title'] ?? '').toString().trim();
    final title = kind == 'PRIVATE' && peerName != null && peerName.isNotEmpty
        ? peerName
        : rawTitle.isNotEmpty
        ? rawTitle
        : (peerName?.isNotEmpty ?? false)
        ? peerName!
        : '会话';
    return NativeConversation(
      id: (raw['id'] as num?)?.toInt() ?? 0,
      kind: (raw['kind'] ?? '').toString(),
      title: title,
      unreadCount: (raw['unreadCount'] as num?)?.toInt() ?? 0,
      preview: preview,
      updatedAt: parseNovaDateTime(raw['updatedAt'] ?? raw['lastMessageAt']),
      peerUserId:
          (peerMap['userId'] as num?)?.toInt() ??
          (raw['peerUserId'] as num?)?.toInt(),
      peerDisplayName: peerName,
      memberCount: (raw['memberCount'] as num?)?.toInt() ?? 0,
      muted: raw['muted'] == true,
      pinned: raw['pinned'] == true,
      businessType: raw['businessType']?.toString(),
      peerDepartment:
          (raw['peerDepartment'] ??
                  peerMap['department'] ??
                  peerMap['departmentName'])
              ?.toString(),
      peerRoleLabel:
          (raw['peerRoleLabel'] ??
                  raw['peerTitle'] ??
                  peerMap['title'] ??
                  peerMap['roleLabel'])
              ?.toString(),
      peerAvatarPreset: (raw['peerAvatarPreset'] ?? peerMap['avatarPreset'])
          ?.toString(),
      peerAvatarObjectKey:
          (raw['peerAvatarObjectKey'] ?? peerMap['avatarObjectKey'])
              ?.toString(),
      dissolved:
          raw['dissolved'] == true ||
          raw['isDissolved'] == true ||
          raw['status']?.toString() == 'DISSOLVED' ||
          raw['frozen'] == true,
      membershipStatus: (raw['membershipStatus'] ?? raw['memberStatus'])
          ?.toString(),
      assistantGenerating: raw['assistantGenerating'] == true,
      assistantGeneratingStatus: (raw['assistantGeneratingStatus'] ?? '')
          .toString(),
    );
  }

  NativeChatMessage _mapMessage(Map<String, dynamic> raw) {
    final sender = raw['sender'];
    final senderMap = sender is Map<String, dynamic>
        ? sender
        : sender is Map
        ? Map<String, dynamic>.from(sender)
        : const <String, dynamic>{};
    final senderName = (senderMap['displayName'] ?? raw['senderName'] ?? '')
        .toString()
        .trim();
    final payloadRaw = raw['payload'];
    final payload = payloadRaw is Map<String, dynamic>
        ? payloadRaw
        : payloadRaw is Map
        ? Map<String, dynamic>.from(payloadRaw)
        : null;
    return NativeChatMessage(
      id: (raw['id'] as num?)?.toInt() ?? 0,
      senderUserId:
          (senderMap['userId'] as num?)?.toInt() ??
          (raw['senderId'] as num?)?.toInt() ??
          (raw['senderUserId'] as num?)?.toInt() ??
          0,
      senderName: senderName.isEmpty ? '系统' : senderName,
      kind: (raw['kind'] ?? 'TEXT').toString(),
      bodyText: (raw['bodyText'] ?? '').toString(),
      createdAt: DateTime.tryParse((raw['createdAt'] ?? '').toString()),
      payload: payload,
      peerRead: raw['peerRead'] == true || raw['isPeerRead'] == true,
      senderAvatarPreset: _avatarField(
        senderMap['avatarPreset'] ?? raw['senderAvatarPreset'],
      ),
      senderAvatarObjectKey: _avatarField(
        senderMap['avatarObjectKey'] ?? raw['senderAvatarObjectKey'],
      ),
    );
  }

  String? _avatarField(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  /// 从群成员列表构建 userId -> 头像字段，供历史消息回填。
  Map<int, ({String? preset, String? objectKey})> avatarMapFromMembers(
    List<Map<String, dynamic>> members,
  ) {
    final out = <int, ({String? preset, String? objectKey})>{};
    for (final member in members) {
      final uid = (member['userId'] as num?)?.toInt() ?? 0;
      if (uid <= 0) continue;
      out[uid] = (
        preset: _avatarField(member['avatarPreset']),
        objectKey: _avatarField(member['avatarObjectKey']),
      );
    }
    return out;
  }

  List<NativeChatMessage> enrichMessagesWithAvatars(
    List<NativeChatMessage> messages, {
    required Map<int, ({String? preset, String? objectKey})> avatarByUserId,
    String? peerAvatarPreset,
    String? peerAvatarObjectKey,
    int? peerUserId,
    int selfUserId = 0,
    String? selfAvatarPreset,
    String? selfAvatarObjectKey,
  }) {
    return messages
        .map((m) {
          if (_hasAvatar(m.senderAvatarPreset, m.senderAvatarObjectKey)) {
            return m;
          }
          if (m.senderUserId > 0) {
            final member = avatarByUserId[m.senderUserId];
            if (member != null &&
                _hasAvatar(member.preset, member.objectKey)) {
              return m.copyWith(
                senderAvatarPreset: member.preset,
                senderAvatarObjectKey: member.objectKey,
              );
            }
          }
          if (peerUserId != null &&
              peerUserId > 0 &&
              m.senderUserId == peerUserId &&
              _hasAvatar(peerAvatarPreset, peerAvatarObjectKey)) {
            return m.copyWith(
              senderAvatarPreset: peerAvatarPreset,
              senderAvatarObjectKey: peerAvatarObjectKey,
            );
          }
          if (selfUserId > 0 &&
              m.senderUserId == selfUserId &&
              _hasAvatar(selfAvatarPreset, selfAvatarObjectKey)) {
            return m.copyWith(
              senderAvatarPreset: selfAvatarPreset,
              senderAvatarObjectKey: selfAvatarObjectKey,
            );
          }
          return m;
        })
        .toList(growable: false);
  }

  bool _hasAvatar(String? preset, String? objectKey) {
    return (preset ?? '').trim().isNotEmpty ||
        (objectKey ?? '').trim().isNotEmpty;
  }

  String _previewFrom(Map<String, dynamic> raw) {
    final convKind = (raw['kind'] ?? '').toString().toUpperCase();
    final isGroup =
        convKind == 'GROUP' ||
        convKind == 'WORKGROUP' ||
        convKind == 'WORKGROUP_APPROVAL';
    final isPrivate = convKind == 'PRIVATE';

    final last = raw['lastMessage'];
    final lastMap = last is Map<String, dynamic>
        ? last
        : last is Map
        ? Map<String, dynamic>.from(last)
        : null;

    final kind =
        (raw['lastMessageKind'] ??
                raw['lastKind'] ??
                raw['messageKind'] ??
                lastMap?['kind'] ??
                '')
            .toString()
            .toUpperCase();

    final rawText =
        (raw['lastMessagePreview'] ??
                raw['preview'] ??
                raw['lastMessageBodyText'] ??
                raw['lastMessageText'] ??
                lastMap?['bodyText'] ??
                (last is String ? last : '') ??
                '')
            .toString()
            .trim();

    if (rawText.isEmpty) return '';
    final effectiveKind = kind.isNotEmpty
        ? kind
        : _inferKindFromPreview(rawText);
    if (_isSystemMsgKind(effectiveKind))
      return _compactPreview(effectiveKind, rawText);

    // 群聊预览里服务端通常会把发送者名字拼进去（如 "张三: [图片]"），先拆出来，
    // 这样既能正确压缩媒体描述，又能在缺少结构化字段时回退用拆出的名字。
    final parsed = isGroup
        ? _splitPreviewSender(rawText)
        : (sender: '', body: rawText);
    final bodySource = parsed.body.isNotEmpty ? parsed.body : rawText;
    final compact = _compactPreview(effectiveKind, bodySource);
    final media = _isMediaPreviewBody(bodySource, effectiveKind);
    if ((isGroup || media) && compact.isNotEmpty) {
      final sender = _resolvePreviewSenderName(
        raw,
        isPrivate: isPrivate,
        parsedSender: parsed.sender,
      );
      if (sender.isEmpty) return compact;
      if (compact.startsWith('$sender:') || compact.startsWith('$sender：'))
        return compact;
      return '$sender: $compact';
    }
    return compact;
  }

  /// 从 "名字: 正文" 形式的预览中拆出发送者与正文。
  ({String sender, String body}) _splitPreviewSender(String text) {
    final s = text.trim();
    final m = RegExp(r'^([^:：]{1,24})[:：]\s*(.+)$').firstMatch(s);
    if (m == null) return (sender: '', body: s);
    return (sender: m.group(1)!.trim(), body: m.group(2)!.trim());
  }

  String _inferKindFromPreview(String text) {
    final s = text.trim();
    if (RegExp(r'^\[(相册|拍照|图片)\]', caseSensitive: false).hasMatch(s))
      return 'IMAGE';
    if (RegExp(r'^\[文件\]').hasMatch(s)) return 'FILE';
    if (RegExp(r'^\[语音\]').hasMatch(s)) return 'AUDIO';
    return 'TEXT';
  }

  String _resolvePreviewSenderName(
    Map<String, dynamic> raw, {
    required bool isPrivate,
    String parsedSender = '',
  }) {
    final direct =
        (raw['lastMessageSenderDisplayName'] ??
                raw['lastSenderDisplayName'] ??
                raw['lastMessageSenderName'] ??
                raw['lastSenderName'] ??
                raw['senderName'] ??
                '')
            .toString()
            .trim();
    if (direct.isNotEmpty) return direct;

    final senderId =
        (raw['lastMessageSenderUserId'] as num?)?.toInt() ??
        (raw['lastSenderUserId'] as num?)?.toInt() ??
        ((raw['lastMessage'] is Map &&
                (raw['lastMessage'] as Map)['sender'] is Map)
            ? (((raw['lastMessage'] as Map)['sender'] as Map)['userId'] as num?)
                  ?.toInt()
            : null);
    if (senderId != null && senderId > 0) {
      if (senderId == _session.userId)
        return _session.displayName?.trim().isNotEmpty == true
            ? _session.displayName!.trim()
            : '我';
      final peerDisplayName = (raw['peerDisplayName'] ?? '').toString().trim();
      final peerUserId = (raw['peerUserId'] as num?)?.toInt();
      if (peerUserId != null &&
          peerUserId == senderId &&
          peerDisplayName.isNotEmpty) {
        return peerDisplayName;
      }
    }

    final last = raw['lastMessage'];
    if (last is Map) {
      final sender = last['sender'];
      if (sender is Map) {
        final name =
            (sender['displayName'] ??
                    sender['name'] ??
                    sender['username'] ??
                    '')
                .toString()
                .trim();
        if (name.isNotEmpty) return name;
      }
    }
    if (parsedSender.isNotEmpty) return parsedSender;
    if (isPrivate && ((raw['unreadCount'] as num?)?.toInt() ?? 0) > 0) {
      final peerDisplayName = (raw['peerDisplayName'] ?? '').toString().trim();
      if (peerDisplayName.isNotEmpty) return peerDisplayName;
    }
    return '';
  }

  String _compactPreview(String kind, String text) {
    final trimmed = text.trim();
    if (kind == 'IMAGE' ||
        RegExp(r'^\[(相册|拍照|图片)\]', caseSensitive: false).hasMatch(trimmed)) {
      return '发送了一张图片';
    }
    if (kind == 'AUDIO' || RegExp(r'^\[语音\]').hasMatch(trimmed)) {
      return '发送了一条语音';
    }
    if (kind == 'FILE' || RegExp(r'^\[文件\]').hasMatch(trimmed)) {
      return '发送了一个文件';
    }
    if (RegExp(
      r'\.(png|jpe?g|gif|webp|bmp|heic|heif)$',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return '发送了一张图片';
    }
    if (RegExp(
      r'\.(pdf|docx?|xlsx?|pptx?|zip|rar|7z|txt|csv|md|pages|numbers|key)$',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return '发送了一个文件';
    }
    if (kind == 'SYSTEM_FLOW') return text.isNotEmpty ? text : '[系统消息]';
    return trimmed;
  }

  bool _isSystemMsgKind(String kind) {
    return kind == 'SYSTEM' ||
        kind == 'SYSTEM_JOIN' ||
        kind == 'SYSTEM_LEAVE' ||
        kind == 'SYSTEM_REMOVE' ||
        kind == 'SYSTEM_FLOW';
  }

  bool _isMediaPreviewBody(String body, String kind) {
    final compact = _compactPreview(kind, body);
    return compact == '发送了一张图片' || compact == '发送了一个文件' || compact == '发送了一条语音';
  }

  bool _isPublicMediaUrl(String value) {
    final v = value.toLowerCase();
    return v.startsWith('http://') ||
        v.startsWith('https://') ||
        v.startsWith('blob:');
  }

  Future<String> resolveMediaUrl(
    String source, {
    String bucket = 'im-attachments',
  }) async {
    if (bucket == 'user-avatars') {
      final raw = source.trim();
      if (raw.isEmpty) {
        throw Exception('媒体地址解析失败: objectKey 为空');
      }
      return mediaProxyUrl(raw, bucket: bucket);
    }
    if (_isPublicMediaUrl(source)) {
      return _normalizeBucketPathInUrl(source.trim(), bucket: bucket);
    }
    final raw = source.trim();
    if (raw.isEmpty) {
      throw Exception('媒体地址解析失败: objectKey 为空');
    }
    final candidates = <String>[raw];
    final prefixed = '$bucket/';
    if (raw.startsWith(prefixed) && raw.length > prefixed.length) {
      candidates.add(raw.substring(prefixed.length));
    }
    if (raw.startsWith('/')) {
      candidates.add(raw.substring(1));
    }

    Exception? lastError;
    for (final key in candidates.toSet()) {
      try {
        final resp = await _client.get(
          _uri(
            '/storage/presigned-get?bucket=$bucket&objectKey=${Uri.encodeQueryComponent(key)}',
          ),
          headers: _headers,
        );
        if (resp.statusCode < 200 || resp.statusCode >= 300) {
          throw Exception('媒体地址解析失败: HTTP ${resp.statusCode}');
        }
        final body = _decode(resp.body);
        final data = body['data'];
        if (data is! Map<String, dynamic>) {
          throw Exception('媒体地址解析失败: data 为空');
        }
        final url = (data['url'] ?? '').toString().trim();
        if (url.isEmpty) throw Exception('媒体地址解析失败: url 为空');
        return _normalizeBucketPathInUrl(url, bucket: bucket);
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }
    throw lastError ?? Exception('媒体地址解析失败');
  }

  String mediaProxyUrl(
    String source, {
    String bucket = 'im-attachments',
  }) {
    final raw = source.trim();
    if (raw.isEmpty) return raw;
    return _uri(
      '/storage/download?bucket=$bucket&objectKey=${Uri.encodeQueryComponent(raw)}&proxy=1',
    ).toString();
  }

  String _normalizeBucketPathInUrl(String url, {required String bucket}) {
    if (url.isEmpty) return url;
    final repeated = '/$bucket/$bucket/';
    if (!url.contains(repeated)) return url;
    return url.replaceAll(repeated, '/$bucket/');
  }

  Uri downloadUri({
    required String objectKey,
    String bucket = 'im-attachments',
    String? fileName,
  }) {
    final q = <String, String>{'bucket': bucket, 'objectKey': objectKey};
    if (fileName != null && fileName.isNotEmpty) {
      q['fileName'] = fileName;
    }
    return _uri('/storage/download?${Uri(queryParameters: q).query}');
  }

  Future<Uint8List> downloadAttachmentBytes({
    required String objectKey,
    String bucket = 'im-attachments',
    String? fileName,
  }) async {
    if (objectKey.isEmpty) throw Exception('附件地址为空');
    if (_isPublicMediaUrl(objectKey)) {
      final resp = await _client.get(Uri.parse(objectKey));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('下载失败: HTTP ${resp.statusCode}');
      }
      return resp.bodyBytes;
    }
    final resp = await _client.get(
      downloadUri(objectKey: objectKey, bucket: bucket, fileName: fileName),
      headers: _headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('下载失败: HTTP ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  Future<Uint8List> loadChatMediaBytes(Map<String, dynamic>? payload) async {
    final objectKey = mediaObjectKey(payload);
    if (objectKey.isNotEmpty) {
      return downloadAttachmentBytes(
        objectKey: objectKey,
        fileName: mediaFileName(payload),
      );
    }
    final url = mediaDirectUrl(payload);
    if (url.isNotEmpty) {
      throw Exception('请使用公网图片地址直接展示');
    }
    throw Exception('附件地址为空');
  }

  /// 加载完整原图字节（鉴权附件或公网直链均统一返回 bytes），
  /// 供「查看原图 / 保存到相册」使用。
  Future<Uint8List> loadFullImageBytes(Map<String, dynamic>? payload) async {
    if (hasAuthMedia(payload)) {
      return loadChatMediaBytes(payload);
    }
    final url = mediaDirectUrl(payload);
    if (url.isNotEmpty) {
      return downloadAttachmentBytes(
        objectKey: url,
        fileName: mediaFileName(payload),
      );
    }
    throw Exception('图片地址为空');
  }

  /// 返回用于会话内联展示的「预览图」payload；旧消息或无预览时回退为原 payload。
  static Map<String, dynamic>? previewMediaPayload(
    Map<String, dynamic>? payload,
  ) {
    if (payload == null) return null;
    final previewObjectKey = (payload['previewObjectKey'] ?? '')
        .toString()
        .trim();
    final previewUrl = (payload['previewUrl'] ?? '').toString().trim();
    if (previewObjectKey.isEmpty && previewUrl.isEmpty) return payload;
    final objectKey = (payload['objectKey'] ?? '').toString().trim();
    final url = (payload['url'] ?? '').toString().trim();
    // 预览与原图一致（旧消息把 previewUrl 设为原图）则直接复用原 payload。
    if (previewObjectKey == objectKey && previewUrl == url) return payload;
    return <String, dynamic>{
      'objectKey': previewObjectKey,
      'url': previewUrl,
      'fileName': payload['fileName'],
      'mimeType': payload['mimeType'],
    };
  }

  /// 公网 CDN 图片可直接展示；私有附件走鉴权下载。
  static String? mediaPublicImageUrl(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    if (mediaObjectKey(payload).isNotEmpty) return null;
    final url = mediaDirectUrl(payload);
    return url.isNotEmpty ? url : null;
  }

  static bool hasAuthMedia(Map<String, dynamic>? payload) =>
      mediaObjectKey(payload).isNotEmpty;

  static String mediaObjectKey(Map<String, dynamic>? payload) {
    if (payload == null) return '';
    final key = (payload['objectKey'] ?? '').toString().trim();
    if (key.isNotEmpty && !_isPublicMediaUrlStatic(key)) return key;
    final url = (payload['url'] ?? '').toString().trim();
    if (url.isNotEmpty && !_isPublicMediaUrlStatic(url)) return url;
    final preview = (payload['previewUrl'] ?? '').toString().trim();
    if (preview.isNotEmpty && !_isPublicMediaUrlStatic(preview)) return preview;
    return '';
  }

  static String mediaDirectUrl(Map<String, dynamic>? payload) {
    if (payload == null) return '';
    final objectKey = (payload['objectKey'] ?? '').toString().trim();
    if (objectKey.isNotEmpty && _isPublicMediaUrlStatic(objectKey))
      return objectKey;
    final url = (payload['url'] ?? payload['previewUrl'] ?? '')
        .toString()
        .trim();
    if (url.isNotEmpty && _isPublicMediaUrlStatic(url)) return url;
    return '';
  }

  static String mediaFileName(
    Map<String, dynamic>? payload, {
    String fallback = 'download',
  }) {
    if (payload == null) return fallback;
    final name = (payload['fileName'] ?? '').toString().trim();
    return name.isNotEmpty ? name : fallback;
  }

  static bool _isPublicMediaUrlStatic(String value) {
    final v = value.toLowerCase();
    return v.startsWith('http://') ||
        v.startsWith('https://') ||
        v.startsWith('blob:');
  }
}
