import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../core/config/nova_config.dart';
import '../auth/auth_session.dart';
import 'native_kb_models.dart';

class NativeKbService {
  NativeKbService({
    required this.session,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final AuthSession session;
  final http.Client _client;

  String _novaApiKey = '';
  String _novaBase = NovaConfig.baseUrl;

  Uri _dunesUri(String path) =>
      Uri.parse('${session.apiBase.replaceAll(RegExp(r'/$'), '')}$path');

  Map<String, String> get _dunesHeaders => <String, String>{
        'Authorization': 'Bearer ${session.token}',
        'Accept': 'application/json',
      };

  Map<String, String> _novaHeaders({Map<String, String>? extra}) {
    final headers = <String, String>{
      if (_novaApiKey.isNotEmpty) 'Authorization': 'Bearer $_novaApiKey',
      'Accept': 'application/json',
      ...?extra,
    };
    return headers;
  }

  Future<void> ensureNovaReady() async {
    _novaApiKey =
        (session.novaLocalStorage?['dunes_nova_api_key'] ?? '').trim();
    _novaBase = (session.novaLocalStorage?['dunes_nova_base'] ?? NovaConfig.baseUrl)
        .replaceAll(RegExp(r'/$'), '');
    if (_novaApiKey.isNotEmpty) return;

    final resp = await _client.get(
      _dunesUri('/me/nova-credentials'),
      headers: _dunesHeaders,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Nova 凭证获取失败: HTTP ${resp.statusCode}');
    }
    final body = _decode(resp.body);
    final data = body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : body;
    _novaApiKey = (data['api_token'] ?? data['apiToken'] ?? '').toString().trim();
    _novaBase = (data['baseUrl'] as String?)?.trim().replaceAll(RegExp(r'/$'), '') ??
        _novaBase;
    if (_novaApiKey.isEmpty) {
      throw Exception('Nova 知识库未就绪，请重新登录');
    }
  }

  Future<NativeKbSummary> fetchSummary() async {
    await ensureNovaReady();
    final resp = await _client.get(
      Uri.parse('$_novaBase/v1/app/kb/status'),
      headers: _novaHeaders(),
    );
    final body = _decode(resp.body);
    if (resp.statusCode < 200 || resp.statusCode >= 300 || body['success'] == false) {
      throw Exception(
        (body['message'] ?? body['error']?['message'] ?? '知识库状态获取失败')
            .toString(),
      );
    }
    final st = body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : body;
    return _parseSummary(st);
  }

  NativeKbSummary _parseSummary(Map<String, dynamic> st) {
    final rawDocs = st['documents'] is List ? st['documents'] as List : const [];
    final docs = <NativeKbDocument>[];
    for (var i = 0; i < rawDocs.length; i++) {
      final row = rawDocs[i];
      if (row is Map<String, dynamic>) {
        docs.add(NativeKbDocument.fromJson(row, index: i));
      }
    }
    final folders = st['folders'] is List
        ? st['folders'] as List
        : (st['datasets'] is List ? st['datasets'] as List : const []);
    var docCount = _num(st['documentCount']);
    if (docCount == 0) docCount = _num(st['documentsCount']);
    if (docCount == 0) docCount = _num(st['total']);
    if (docCount == 0) docCount = _num((st['stats'] as Map?)?['documentCount']);
    if (docCount == 0) docCount = docs.length;
    var categoryCount = folders.length;
    final folderId = (st['folderId'] ??
            st['datasetId'] ??
            st['dataset_id'] ??
            (folders.isNotEmpty
                ? ((folders.first as Map?)?['id'] ??
                    (folders.first as Map?)?['datasetId'])
                : null) ??
            'mine')
        .toString();
    if (categoryCount == 0 &&
        (folderId.isNotEmpty || docCount > 0 || st['ready'] == true)) {
      categoryCount = 1;
    }
    final unreadCount = _num(st['unreadCount']) > 0
        ? _num(st['unreadCount'])
        : (_num(st['unreadDocuments']) > 0
            ? _num(st['unreadDocuments'])
            : _num((st['stats'] as Map?)?['unreadCount']));
    var ready = st['canChat'] == true ||
        st['ready'] == true ||
        (st['status'] ?? '').toString().toLowerCase() == 'ready' ||
        (st['kb_status'] ?? '').toString().toLowerCase() == 'ready';
    final rag = st['rag'] is Map ? st['rag'] as Map : const {};
    final rf = st['ragflow'] is Map ? st['ragflow'] as Map : const {};
    if (!ready && (rag['ready'] == true || rf['ready'] == true)) ready = true;
    if (!ready && docCount > 0) {
      final indexed = docs.where((d) => d.indexed).length;
      if (indexed > 0) ready = true;
    }
    return NativeKbSummary(
      documentCount: docCount,
      categoryCount: categoryCount,
      unreadCount: unreadCount,
      ready: ready,
      documents: docs,
      folderId: folderId,
      message: (st['message'] ?? '').toString(),
    );
  }

  int _num(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  Future<void> uploadDocument({
    required List<int> bytes,
    required String fileName,
  }) async {
    await ensureNovaReady();
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$_novaBase/v1/app/kb/documents'),
    );
    req.headers.addAll(_novaHeaders());
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    final streamed = await _client.send(req);
    final resp = await http.Response.fromStream(streamed);
    final body = _decode(resp.body);
    if (resp.statusCode < 200 ||
        resp.statusCode >= 300 ||
        body['success'] == false) {
      throw Exception(
        (body['message'] ?? body['error']?['message'] ?? '上传失败').toString(),
      );
    }
  }

  Future<void> deleteDocument(String documentId, {String? folderId}) async {
    await ensureNovaReady();
    var url = '$_novaBase/v1/app/kb/documents/${Uri.encodeComponent(documentId)}';
    if (folderId != null && folderId.isNotEmpty) {
      url += '?folderId=${Uri.encodeComponent(folderId)}';
    }
    final resp = await _client.delete(Uri.parse(url), headers: _novaHeaders());
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final body = _decode(resp.body);
      throw Exception(
        (body['message'] ?? body['error']?['message'] ?? '删除失败').toString(),
      );
    }
  }

  Future<NativeKbDocument> fetchDocumentDetail(String documentId) async {
    final resp = await _client.get(
      _dunesUri('/kb/documents/$documentId'),
      headers: _dunesHeaders,
    );
    final body = _decode(resp.body);
    if (resp.statusCode < 200 || resp.statusCode >= 300 || body['success'] == false) {
      throw Exception((body['message'] ?? '文档不存在').toString());
    }
    final data = body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : body;
    return NativeKbDocument.fromJson(data);
  }

  Future<void> recordDocumentView(String documentId) async {
    try {
      await _client.post(
        _dunesUri('/kb/documents/$documentId/view'),
        headers: _dunesHeaders,
      );
    } catch (_) {}
  }

  Future<String?> resolveDownloadUrl(String objectKey) async {
    if (objectKey.isEmpty) return null;
    final resp = await _client.get(
      _dunesUri(
        '/storage/presigned-get?bucket=kb-documents&objectKey=${Uri.encodeQueryComponent(objectKey)}',
      ),
      headers: _dunesHeaders,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
    final body = _decode(resp.body);
    final data = body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : body;
    return (data['url'] ?? data['downloadUrl'] ?? body['url']).toString();
  }

  Future<String> fetchMarkdownContent(String objectKey) async {
    final url = await resolveDownloadUrl(objectKey);
    if (url == null || url.isEmpty) {
      final proxy = _dunesUri(
        '/storage/download?bucket=kb-documents&objectKey=${Uri.encodeQueryComponent(objectKey)}',
      );
      final resp = await _client.get(proxy, headers: _dunesHeaders);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('无法读取文档内容');
      }
      return resp.body;
    }
    final resp = await _client.get(Uri.parse(url));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('无法读取文档内容');
    }
    return resp.body;
  }

  String newChatSessionId() {
    final rand = Random().nextInt(0xFFFFFF).toRadixString(36);
    return 'kb-sess-${DateTime.now().millisecondsSinceEpoch}-$rand';
  }

  Future<void> sendKbMessage({
    required String text,
    required String sessionId,
    required void Function(String delta) onDelta,
    required void Function(List<NativeKbCitation> citations) onCitations,
  }) async {
    await ensureNovaReady();
    final model = (session.novaLocalStorage?['dunes_nova_chat_model'] ??
            session.novaLocalStorage?['dunes_nova_default_model'] ??
            NovaConfig.defaultChatModel)
        .trim();
    final bizUser = (session.novaLocalStorage?['dunes_nova_biz_user_id'] ??
            session.userId.toString())
        .trim();
    final req = http.Request('POST', Uri.parse('$_novaBase/v1/chat/completions'));
    req.headers.addAll(_novaHeaders(extra: {
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      if (sessionId.isNotEmpty) 'X-Nova-Chat-Session-Id': sessionId,
    }));
    req.body = jsonEncode(<String, dynamic>{
      'model': model.isEmpty ? NovaConfig.defaultChatModel : model,
      'stream': true,
      'messages': [
        <String, dynamic>{'role': 'user', 'content': text},
      ],
      if (bizUser.isNotEmpty) 'user': bizUser,
    });

    final streamed = await _client.send(req);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final errBody = await streamed.stream.bytesToString();
      throw Exception(_parseNovaError(streamed.statusCode, errBody));
    }

    final buffer = StringBuffer();
    var sseBuffer = '';
    var hadOutput = false;
    var streamError = '';
    final citations = <NativeKbCitation>[];

    await for (final chunk in streamed.stream.transform(utf8.decoder)) {
      sseBuffer += chunk;
      while (true) {
        final sep = sseBuffer.indexOf('\n\n');
        if (sep < 0) break;
        final block = sseBuffer.substring(0, sep);
        sseBuffer = sseBuffer.substring(sep + 2);
        final json = _parseSseBlock(block);
        if (json == null) continue;
        if (json['error'] != null) {
          streamError = (json['error']?['message'] ?? json['message'] ?? 'Nova 流式错误')
              .toString();
          continue;
        }
        if (json['rag'] is Map) {
          citations
            ..clear()
            ..addAll(_mapRagCitations(json['rag'] as Map<String, dynamic>));
          onCitations(List<NativeKbCitation>.from(citations));
        }
        final delta = json['choices']?[0]?['delta'];
        final msg = json['choices']?[0]?['message'];
        String? piece;
        if (delta is Map) {
          piece = (delta['content'] ?? delta['text'])?.toString();
        } else if (msg is Map && msg['content'] != null) {
          piece = msg['content'].toString();
        }
        if (piece != null && piece.isNotEmpty) {
          hadOutput = true;
          buffer.write(piece);
          onDelta(buffer.toString());
        }
      }
    }

    if (streamError.isNotEmpty) throw Exception(streamError);
    if (!hadOutput) throw Exception('Nova 未返回任何内容');
  }

  List<NativeKbCitation> _mapRagCitations(Map<String, dynamic> rag) {
    final chunks = rag['chunks'];
    if (chunks is! List) return const [];
    final out = <NativeKbCitation>[];
    for (final c in chunks) {
      if (c is! Map) continue;
      final map = Map<String, dynamic>.from(c);
      out.add(
        NativeKbCitation(
          sourceTitle: (map['sourceTitle'] ??
                  map['documentTitle'] ??
                  map['title'] ??
                  map['fileName'] ??
                  '引用')
              .toString(),
          chunkText: (map['text'] ?? map['chunkText'] ?? map['content'] ?? '')
              .toString(),
          page: (map['page'] ?? map['pageNo'] as num?)?.toInt(),
        ),
      );
    }
    return out;
  }

  Map<String, dynamic>? _parseSseBlock(String block) {
    var dataLine = '';
    for (final line in block.split('\n')) {
      final t = line.trim();
      if (t.startsWith('data:')) dataLine = t.substring(5).trim();
    }
    if (dataLine.isEmpty || dataLine == '[DONE]') return null;
    try {
      final decoded = jsonDecode(dataLine);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String _parseNovaError(int status, String text) {
    try {
      final j = _decode(text);
      return (j['error']?['message'] ?? j['message'] ?? 'Nova 请求失败 HTTP $status')
          .toString();
    } catch (_) {
      return text.isEmpty ? 'Nova 请求失败 HTTP $status' : text.substring(0, min(320, text.length));
    }
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return const {};
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }
}
