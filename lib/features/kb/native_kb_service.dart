import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/config/nova_config.dart';
import '../../core/widgets/org_folder_bar.dart';
import '../auth/auth_session.dart';
import '../meeting/meeting_minutes_export.dart';
import '../meeting/native_meeting_models.dart';
import '../meeting/native_meeting_service.dart';
import '../nova/nova_file_utils.dart';
import 'native_kb_models.dart';

class NativeKbService {
  NativeKbService({required this.session, http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  final AuthSession session;
  final http.Client _client;
  final bool _ownsClient;

  void close() {
    if (_ownsClient) _client.close();
  }

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
    _novaApiKey = (session.novaLocalStorage?['dunes_nova_api_key'] ?? '')
        .trim();
    _novaBase = NovaConfig.resolveBaseUrl(
      session.novaLocalStorage?['dunes_nova_base'],
    );
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
    _novaApiKey = (data['api_token'] ?? data['apiToken'] ?? '')
        .toString()
        .trim();
    _novaBase = NovaConfig.resolveBaseUrl(
      (data['baseUrl'] as String?)?.trim() ?? _novaBase,
    );
    if (_novaApiKey.isEmpty) {
      throw Exception('Nova 知识库未就绪，请重新登录');
    }
  }

  Future<void> syncRagflow() async {
    final resp = await _client.post(
      _dunesUri('/kb/sync'),
      headers: _dunesHeaders,
    );
    final body = _decode(resp.body);
    if (resp.statusCode < 200 ||
        resp.statusCode >= 300 ||
        body['success'] == false) {
      throw Exception(
        (body['message'] ?? body['error']?['message'] ?? '同步失败').toString(),
      );
    }
  }

  Future<NativeKbSummary> fetchSummary() async {
    await ensureNovaReady();
    final resp = await _client.get(
      Uri.parse('$_novaBase/v1/app/kb/status'),
      headers: _novaHeaders(),
    );
    final body = _decode(resp.body);
    if (resp.statusCode < 200 ||
        resp.statusCode >= 300 ||
        body['success'] == false) {
      throw Exception(
        (body['message'] ?? body['error']?['message'] ?? '知识库状态获取失败')
            .toString(),
      );
    }
    final st = body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : body;
    final summary = _parseSummary(st);
    await _enrichDocumentsWithDunesLinks(summary.documents);
    return summary;
  }

  Future<List<NativeKbDocument>> searchDocuments({
    required String keyword,
    int page = 0,
    int size = 50,
  }) async {
    final result = await listDocuments(
      keyword: keyword,
      page: page,
      size: size,
    );
    return result.items;
  }

  /// 分页列出当前用户知识库文档。keyword 为空时返回全部。
  Future<List<OrgFolderItem>> listFolders() async {
    final resp = await _client.get(
      _dunesUri('/kb/folders'),
      headers: _dunesHeaders,
    );
    final data = _asDataMap(_unwrap(resp));
    final content =
        (data['content'] as List?) ?? (data['items'] as List?) ?? const [];
    return content
        .whereType<Map>()
        .map((e) => OrgFolderItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id > 0 && e.name.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<OrgFolderItem> createFolder(String name) async {
    final resp = await _client.post(
      _dunesUri('/kb/folders'),
      headers: {..._dunesHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'name': name.trim()}),
    );
    return OrgFolderItem.fromJson(_asDataMap(_unwrap(resp)));
  }

  Future<OrgFolderItem> renameFolder(int folderId, String name) async {
    final resp = await _client.patch(
      _dunesUri('/kb/folders/$folderId'),
      headers: {..._dunesHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'name': name.trim()}),
    );
    return OrgFolderItem.fromJson(_asDataMap(_unwrap(resp)));
  }

  Future<void> deleteFolder(int folderId) async {
    final resp = await _client.delete(
      _dunesUri('/kb/folders/$folderId'),
      headers: _dunesHeaders,
    );
    if (resp.statusCode == 204) return;
    _unwrap(resp);
  }

  Future<void> moveDocuments({
    required List<String> documentIds,
    required List<String> ragflowDocIds,
    int? folderId,
  }) async {
    final localIds = <int>[];
    final ragIds = <String>[...ragflowDocIds.where((e) => e.trim().isNotEmpty)];
    for (final raw in documentIds) {
      final id = int.tryParse(raw.trim());
      if (id != null && id > 0) {
        localIds.add(id);
      } else if (raw.trim().isNotEmpty && !ragIds.contains(raw.trim())) {
        ragIds.add(raw.trim());
      }
    }
    final resp = await _client.post(
      _dunesUri('/kb/documents/move'),
      headers: {..._dunesHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'documentIds': localIds,
        'ragflowDocIds': ragIds,
        'folderId': folderId,
      }),
    );
    _unwrap(resp);
  }

  Future<NativeKbDocumentPage> listDocuments({
    String keyword = '',
    int page = 0,
    int size = 20,
    String? folderId,
  }) async {
    final query = <String, String>{
      'q': keyword.trim(),
      'page': page.toString(),
      'size': size.toString(),
      if (folderId != null && folderId.trim().isNotEmpty) 'folderId': folderId,
    };
    final resp = await _client.get(
      _dunesUri('/kb/documents?${Uri(queryParameters: query).query}'),
      headers: _dunesHeaders,
    );
    final body = _decode(resp.body);
    if (resp.statusCode < 200 ||
        resp.statusCode >= 300 ||
        body['success'] == false) {
      throw Exception(
        (body['message'] ?? body['error']?['message'] ?? '知识库列表获取失败')
            .toString(),
      );
    }
    final data = body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : body;
    return NativeKbDocumentPage.fromJson(
      data,
      fallbackPage: page,
      fallbackSize: size,
    );
  }

  NativeKbSummary _parseSummary(Map<String, dynamic> st) {
    final rawDocs = st['documents'] is List
        ? st['documents'] as List
        : const [];
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
    final folderId =
        (st['folderId'] ??
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
    var ready =
        st['canChat'] == true ||
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

  Future<void> _enrichDocumentsWithDunesLinks(
    List<NativeKbDocument> docs,
  ) async {
    if (docs.isEmpty) return;
    final needsLink = docs.where((d) => d.dunesDocumentId.isEmpty).toList();
    if (needsLink.isEmpty) return;

    final homeRecents = await _fetchHomeRecentDocuments();
    for (var i = 0; i < docs.length; i++) {
      final doc = docs[i];
      if (doc.dunesDocumentId.isNotEmpty) continue;

      NativeKbDocument? linked;
      if (homeRecents.length == 1 && docs.length == 1) {
        linked = homeRecents.first;
      }
      linked ??= _matchHomeDocument(doc, homeRecents);

      if (linked != null && linked.dunesDocumentId.isNotEmpty) {
        docs[i] = doc.copyWith(
          title: doc.title.isNotEmpty ? doc.title : linked.title,
          fileName: doc.fileName.isNotEmpty ? doc.fileName : linked.fileName,
          fileExtension: doc.fileExtension.isNotEmpty
              ? doc.fileExtension
              : linked.fileExtension,
          ingestionStatus: doc.ingestionStatus.isNotEmpty
              ? doc.ingestionStatus
              : linked.ingestionStatus,
          indexed: doc.indexed || linked.indexed,
          runStatus: doc.runStatus.isNotEmpty
              ? doc.runStatus
              : linked.runStatus,
          fileObjectKey: linked.fileObjectKey,
          fileUrl: linked.fileUrl,
          localDocId: linked.dunesDocumentId,
          ragflowDocId: doc.ragflowDocId.isNotEmpty
              ? doc.ragflowDocId
              : linked.ragflowDocId,
          fileSizeBytes: linked.fileSizeBytes > 0
              ? linked.fileSizeBytes
              : doc.fileSizeBytes,
        );
      }
    }
  }

  Future<List<NativeKbDocument>> _fetchHomeRecentDocuments() async {
    try {
      final resp = await _client.get(
        _dunesUri('/kb/home'),
        headers: _dunesHeaders,
      );
      if (resp.statusCode < 200 || resp.statusCode >= 300) return const [];
      final body = _decode(resp.body);
      final data = body['data'] is Map<String, dynamic>
          ? body['data'] as Map<String, dynamic>
          : body;
      final raw = data['recents'] is List ? data['recents'] as List : const [];
      final out = <NativeKbDocument>[];
      for (var i = 0; i < raw.length; i++) {
        final row = raw[i];
        if (row is Map<String, dynamic>) {
          out.add(NativeKbDocument.fromJson(row, index: i));
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  NativeKbDocument? _matchHomeDocument(
    NativeKbDocument doc,
    List<NativeKbDocument> homeDocs,
  ) {
    final names = <String>{
      doc.title.trim().toLowerCase(),
      doc.fileName.trim().toLowerCase(),
    }..removeWhere((s) => s.isEmpty);
    if (names.isEmpty) return null;
    NativeKbDocument? unique;
    for (final candidate in homeDocs) {
      final cNames = <String>{
        candidate.title.trim().toLowerCase(),
        candidate.fileName.trim().toLowerCase(),
      }..removeWhere((s) => s.isEmpty);
      if (names.intersection(cNames).isEmpty) continue;
      if (unique != null) return null;
      unique = candidate;
    }
    return unique;
  }

  Future<String> _resolveDunesDocumentIdForPreview({
    NativeKbDocument? doc,
    String docId = '',
  }) async {
    final direct = await resolveDunesDocumentIdAsync(doc: doc, docId: docId);
    if (direct.isNotEmpty) return direct;

    final homeRecents = await _fetchHomeRecentDocuments();
    if (homeRecents.length == 1) {
      return homeRecents.first.dunesDocumentId;
    }
    if (doc != null) {
      final matched = _matchHomeDocument(doc, homeRecents);
      if (matched != null && matched.dunesDocumentId.isNotEmpty) {
        return matched.dunesDocumentId;
      }
    }
    return '';
  }

  Exception _kbContentReadException(Object? lastError, {int? statusCode}) {
    if (statusCode == 502 || statusCode == 503) {
      return Exception('文档存储服务暂不可用，请联系管理员检查 MinIO 配置');
    }
    if (lastError is Exception) return lastError;
    if (lastError != null) return Exception('$lastError');
    return Exception('无法读取文档内容');
  }

  Future<void> uploadDocument({
    required List<int> bytes,
    required String fileName,
    String? title,
    int? folderId,
    void Function(int sent, int total)? onProgress,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('文件为空');
    }
    final initResp = await _client.post(
      _dunesUri('/kb/documents/uploads'),
      headers: {..._dunesHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'fileName': fileName,
        'title': (title ?? '').trim(),
        'fileSizeBytes': bytes.length,
        'contentType': _guessContentType(fileName),
        if (folderId != null && folderId > 0) 'folderId': folderId,
      }),
    );
    final init = _asDataMap(_unwrap(initResp));
    final uploadId = '${init['uploadId'] ?? ''}'.trim();
    if (uploadId.isEmpty) {
      throw Exception('初始化分片上传失败');
    }
    final partSize = (init['partSize'] as num?)?.toInt() ?? (8 * 1024 * 1024);
    try {
      var offset = 0;
      var partNumber = 1;
      while (offset < bytes.length) {
        final end = min(offset + partSize, bytes.length);
        final chunk = bytes.sublist(offset, end);
        final partResp = await _client.put(
          _dunesUri('/kb/documents/uploads/$uploadId/parts/$partNumber'),
          headers: {
            ..._dunesHeaders,
            'Content-Type': 'application/octet-stream',
            'Content-Length': '${chunk.length}',
          },
          body: chunk,
        );
        _unwrap(partResp);
        offset = end;
        partNumber++;
        onProgress?.call(offset, bytes.length);
      }
      final completeResp = await _client.post(
        _dunesUri('/kb/documents/uploads/$uploadId/complete'),
        headers: {..._dunesHeaders, 'Content-Type': 'application/json'},
        body: '{}',
      );
      _unwrap(completeResp);
    } catch (e) {
      try {
        await _client.delete(
          _dunesUri('/kb/documents/uploads/$uploadId'),
          headers: _dunesHeaders,
        );
      } catch (_) {}
      rethrow;
    }
    unawaited(syncRagflow());
  }

  String _guessContentType(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.') + 1).toLowerCase()
        : '';
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'md':
        return 'text/markdown';
      case 'txt':
        return 'text/plain';
      case 'html':
      case 'htm':
        return 'text/html';
      default:
        return 'application/octet-stream';
    }
  }

  Map<String, dynamic> _asDataMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }

  dynamic _unwrap(http.Response resp) {
    final body = _decode(resp.body);
    if (resp.statusCode >= 400 || body['success'] == false) {
      throw Exception(
        (body['message'] ??
                body['error']?['message'] ??
                '上传失败 HTTP ${resp.statusCode}')
            .toString(),
      );
    }
    return body['data'] ?? body;
  }

  NativeKbDocument? findMeetingMinutesDocumentInSummary(
    NativeKbSummary summary, {
    required int meetingId,
    required String kbFileName,
    required String kbTitle,
  }) {
    if (meetingId <= 0) return null;
    for (final doc in summary.documents) {
      if (_matchesMeetingMinutesDocument(
        doc,
        meetingId: meetingId,
        kbFileName: kbFileName,
        kbTitle: kbTitle,
      )) {
        return doc;
      }
    }
    return null;
  }

  Future<NativeKbDocument?> findMeetingMinutesDocument({
    required int meetingId,
    required String kbFileName,
    required String kbTitle,
    int? kbDocumentId,
  }) async {
    if (meetingId <= 0) return null;
    final summary = await fetchSummary();
    if (kbDocumentId != null && kbDocumentId > 0) {
      final idStr = '$kbDocumentId';
      for (final doc in summary.documents) {
        if (doc.dunesDocumentId == idStr ||
            doc.localDocId == idStr ||
            doc.id == idStr) {
          return doc;
        }
      }
    }
    return findMeetingMinutesDocumentInSummary(
      summary,
      meetingId: meetingId,
      kbFileName: kbFileName,
      kbTitle: kbTitle,
    );
  }

  /// 仅返回已在知识库中且完成索引的会议纪要文档。
  Future<NativeKbDocument?> findIndexedMeetingMinutesDocument({
    required int meetingId,
    required String kbFileName,
    required String kbTitle,
  }) async {
    final doc = await findMeetingMinutesDocument(
      meetingId: meetingId,
      kbFileName: kbFileName,
      kbTitle: kbTitle,
    );
    if (doc == null || !nativeKbDocumentIndexed(doc)) return null;
    return doc;
  }

  /// 筛选出已在知识库中完成索引、可用于 PRD 的会议纪要。
  Future<List<NativeMeetingSummary>> filterMeetingsWithIndexedKb(
    List<NativeMeetingSummary> meetings,
  ) async {
    if (meetings.isEmpty) return const [];
    await ensureNovaReady();
    final summary = await fetchSummary();
    final out = <NativeMeetingSummary>[];
    for (final meeting in meetings) {
      final doc = findMeetingMinutesDocumentInSummary(
        summary,
        meetingId: meeting.meetingId,
        kbFileName: MeetingMinutesExport.kbUploadFileNameFromSummary(meeting),
        kbTitle: MeetingMinutesExport.kbUploadTitleFromSummary(meeting),
      );
      if (doc != null && nativeKbDocumentIndexed(doc)) {
        out.add(meeting);
      }
    }
    return out;
  }

  /// 已完成索引、可用于「基于知识库生成 PRD」的文档列表。
  Future<List<NativeKbDocument>> listIndexedDocumentsForPrd() async {
    await ensureNovaReady();
    final summary = await fetchSummary();
    final docs = summary.documents.where(nativeKbDocumentIndexed).toList();
    // 会议纪要类文档优先，其余已索引文档排后。
    docs.sort((a, b) {
      final aScore = _prdDocSortScore(a);
      final bScore = _prdDocSortScore(b);
      if (aScore != bScore) return bScore.compareTo(aScore);
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return docs;
  }

  int _prdDocSortScore(NativeKbDocument doc) {
    final name = '${doc.fileName} ${doc.title}'.toLowerCase();
    if (name.contains('会议纪要') || name.contains('meeting-minutes')) return 2;
    if (name.contains('会议') || name.contains('纪要') || name.contains('prd')) {
      return 1;
    }
    return 0;
  }

  bool _matchesMeetingMinutesDocument(
    NativeKbDocument doc, {
    required int meetingId,
    required String kbFileName,
    required String kbTitle,
  }) {
    final fileName = doc.fileName.trim().toLowerCase();
    final title = doc.title.trim().toLowerCase();
    final expectedFile = kbFileName.trim().toLowerCase();
    final expectedTitle = kbTitle.trim().toLowerCase();
    if (expectedFile.isNotEmpty &&
        (fileName == expectedFile ||
            fileName == expectedFile.replaceAll('.md', ''))) {
      return true;
    }
    if (expectedTitle.isNotEmpty && title == expectedTitle) return true;
    if (expectedTitle.isNotEmpty && fileName.contains(expectedTitle))
      return true;

    // 兼容 minutes-go upload-to-kb：meeting-minutes-{id}.md
    final backendFile = 'meeting-minutes-$meetingId'.toLowerCase();
    if (fileName == backendFile ||
        fileName == '$backendFile.md' ||
        fileName.contains(backendFile)) {
      return true;
    }
    if (title.contains(backendFile)) return true;
    final objectKey = doc.fileObjectKey.trim().toLowerCase();
    if (objectKey.contains(backendFile)) return true;
    return objectKey.contains(backendFile);
  }

  Future<void> deleteDocument(String documentId, {String? folderId}) async {
    await ensureNovaReady();
    var url =
        '$_novaBase/v1/app/kb/documents/${Uri.encodeComponent(documentId)}';
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

  Future<NativeKbDocument?> findDocumentById(String documentId) async {
    final id = documentId.trim();
    if (id.isEmpty) return null;
    final summary = await fetchSummary();
    for (final doc in summary.documents) {
      if (doc.id == id || doc.dunesDocumentId == id || doc.localDocId == id) {
        return doc;
      }
    }
    return null;
  }

  String resolveDunesDocumentId({NativeKbDocument? doc, String docId = ''}) {
    final fromDoc = doc?.dunesDocumentId ?? '';
    if (fromDoc.isNotEmpty) return fromDoc;
    final trimmed = docId.trim();
    if (trimmed.isNotEmpty && int.tryParse(trimmed) != null) return trimmed;
    return '';
  }

  Future<String> resolveDunesDocumentIdAsync({
    NativeKbDocument? doc,
    String docId = '',
  }) async {
    try {
      return await _ensureDunesDocumentId(doc: doc, docId: docId);
    } catch (_) {
      return '';
    }
  }

  /// 按 RAGFlow id 向 kb-go 要本地副本；没有则让后端从 RAGFlow 静默回填到 MinIO。
  Future<String> _ensureDunesDocumentId({
    NativeKbDocument? doc,
    String docId = '',
  }) async {
    final direct = resolveDunesDocumentId(doc: doc, docId: docId);
    if (direct.isNotEmpty) return direct;
    final ragId =
        (doc?.ragflowDocId.trim().isNotEmpty == true
                ? doc!.ragflowDocId
                : (doc?.id ?? docId))
            .trim();
    if (ragId.isEmpty || int.tryParse(ragId) != null) return '';
    final detail = await fetchDunesDocumentByRagflowId(ragId);
    return detail.dunesDocumentId;
  }

  Future<NativeKbDocument> fetchDunesDocumentByRagflowId(
    String ragflowDocId,
  ) async {
    final id = ragflowDocId.trim();
    if (id.isEmpty) {
      throw Exception('文档 ID 无效');
    }
    final resp = await _client.get(
      _dunesUri('/kb/documents/by-ragflow/${Uri.encodeComponent(id)}'),
      headers: _dunesHeaders,
    );
    final body = _decode(resp.body);
    if (resp.statusCode < 200 ||
        resp.statusCode >= 300 ||
        body['success'] == false) {
      throw Exception((body['message'] ?? '文档不存在或暂不可用').toString());
    }
    final data = body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : body;
    final dunesId = (data['id'] ?? '').toString();
    return NativeKbDocument.fromJson(<String, dynamic>{
      ...data,
      if (dunesId.isNotEmpty) 'localDocId': dunesId,
      'ragflowDocId': id,
    });
  }

  Future<NativeKbDocument> fetchDunesDocument(String dunesDocId) async {
    final id = dunesDocId.trim();
    if (id.isEmpty || int.tryParse(id) == null) {
      throw Exception('文档 ID 无效');
    }
    final resp = await _client.get(
      _dunesUri('/kb/documents/$id'),
      headers: _dunesHeaders,
    );
    final body = _decode(resp.body);
    if (resp.statusCode < 200 ||
        resp.statusCode >= 300 ||
        body['success'] == false) {
      throw Exception((body['message'] ?? '文档不存在或暂不可用').toString());
    }
    final data = body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : body;
    return NativeKbDocument.fromJson(<String, dynamic>{
      ...data,
      'id': id,
      'localDocId': id,
    });
  }

  Future<({String downloadUrl, String fileName})> fetchDocumentDownload(
    String dunesDocId,
  ) async {
    final id = dunesDocId.trim();
    if (id.isEmpty || int.tryParse(id) == null) {
      throw Exception('文档 ID 无效');
    }
    final resp = await _client.get(
      _dunesUri('/kb/documents/$id/download'),
      headers: _dunesHeaders,
    );
    final body = _decode(resp.body);
    if (resp.statusCode < 200 ||
        resp.statusCode >= 300 ||
        body['success'] == false) {
      throw Exception((body['message'] ?? '获取下载链接失败').toString());
    }
    final data = body['data'] is Map<String, dynamic>
        ? body['data'] as Map<String, dynamic>
        : body;
    final url = (data['downloadUrl'] ?? data['url'] ?? '').toString().trim();
    if (url.isEmpty) {
      throw Exception('下载链接无效');
    }
    final fileName = (data['fileName'] ?? '').toString().trim();
    return (downloadUrl: url, fileName: fileName);
  }

  /// 下载知识库文档字节，用于转发到 IM（上传到会话附件）。
  Future<({Uint8List bytes, String fileName})> downloadDocumentBytes({
    required String docId,
    NativeKbDocument? hint,
  }) async {
    String pickName(NativeKbDocument? doc) {
      final fromDoc = (doc?.fileName.trim().isNotEmpty == true)
          ? doc!.fileName.trim()
          : (doc?.title.trim() ?? '');
      if (fromDoc.isNotEmpty) return fromDoc;
      return 'document';
    }

    Object? lastError;

    bool isMissingObject(Object e) {
      final text = e.toString();
      return text.contains('HTTP 403') ||
          text.contains('HTTP 404') ||
          text.contains('HTTP 401');
    }

    void rememberError(Object e, {bool guessedKey = false}) {
      if (guessedKey && isMissingObject(e)) return;
      lastError = e;
    }

    Future<Uint8List?> tryStorage(
      NativeKbDocument doc, {
      bool guessedKeys = false,
    }) async {
      final keys = guessedKeys
          ? _kbStorageKeyCandidates(doc)
          : <String>[
              if (doc.fileObjectKey.trim().isNotEmpty) doc.fileObjectKey.trim(),
            ];
      for (final key in keys) {
        try {
          final bytes = await _downloadBytesViaStorageProxy(key);
          if (bytes.isNotEmpty) return bytes;
        } catch (e) {
          rememberError(
            e,
            guessedKey: guessedKeys || doc.fileObjectKey.trim() != key,
          );
        }
      }
      return null;
    }

    Future<({Uint8List bytes, String fileName})?> tryDirectUrl(
      NativeKbDocument? doc,
    ) async {
      final directUrl = doc?.fileUrl.trim() ?? '';
      if (!isDirectHttpUrl(directUrl) ||
          !isUrlLikelyDeviceReachable(directUrl)) {
        return null;
      }
      try {
        final fetched = await _downloadBytesFromUrl(directUrl);
        if (fetched.isNotEmpty) {
          return (bytes: fetched, fileName: pickName(doc));
        }
      } catch (e) {
        rememberError(e, guessedKey: isMissingObject(e));
      }
      return null;
    }

    // 已镜像到 Dunes MinIO 的文档：只用真实 objectKey。猜路径容易 MinIO 403，
    // 不能盖掉后面的 RAGFlow 回填。
    if (hint != null && hint.fileObjectKey.trim().isNotEmpty) {
      final bytes = await tryStorage(hint);
      if (bytes != null && bytes.isNotEmpty) {
        return (bytes: bytes, fileName: pickName(hint));
      }
    }

    final viaHintUrl = await tryDirectUrl(hint);
    if (viaHintUrl != null) return viaHintUrl;

    var dunesId = '';
    try {
      dunesId = await _ensureDunesDocumentId(doc: hint, docId: docId);
    } catch (e) {
      rememberError(e);
    }
    // 列表来自 Nova，打开要走 Dunes MinIO。后台 sync 可能还没回填完，点开时再静默拉一次。
    if (dunesId.isEmpty) {
      try {
        await syncRagflow();
      } catch (e) {
        rememberError(e, guessedKey: true);
      }
      try {
        dunesId = await _ensureDunesDocumentId(doc: hint, docId: docId);
      } catch (e) {
        rememberError(e);
      }
    }
    if (dunesId.isEmpty) {
      // kb-go 回填可能已把文件写入 MinIO（`{userId}/ragflow/{ragId}/{文件名}`），
      // 但 INSERT 因 content_type 超长失败。此时仍可按猜测 key 下载。
      if (hint != null) {
        final bytes = await tryStorage(hint, guessedKeys: true);
        if (bytes != null && bytes.isNotEmpty) {
          return (bytes: bytes, fileName: pickName(hint));
        }
      }
      throw Exception('该文档尚未同步到本地存储，请稍后重试或下拉刷新');
    }
    NativeKbDocument? doc = hint;
    try {
      doc = await fetchDunesDocument(dunesId);
    } catch (_) {
      doc ??= hint;
    }
    final fileName = pickName(doc);

    if (doc != null) {
      final bytes = await tryStorage(doc);
      if (bytes != null && bytes.isNotEmpty) {
        return (bytes: bytes, fileName: fileName);
      }
    }

    try {
      final download = await fetchDocumentDownload(dunesId);
      final name = download.fileName.trim().isNotEmpty
          ? download.fileName.trim()
          : fileName;
      try {
        final bytes = await _downloadBytesFromUrl(download.downloadUrl);
        if (bytes.isNotEmpty) {
          return (bytes: bytes, fileName: name);
        }
      } catch (e) {
        rememberError(e, guessedKey: isMissingObject(e));
        final signedKey = _extractObjectKeyFromUrl(
          download.downloadUrl,
          bucket: 'kb-documents',
        );
        if (signedKey.isNotEmpty) {
          final proxied = await _downloadBytesViaStorageProxy(signedKey);
          if (proxied.isNotEmpty) {
            return (bytes: proxied, fileName: name);
          }
        }
      }
    } catch (e) {
      rememberError(e);
    }

    if (doc != null) {
      final guessed = await tryStorage(doc, guessedKeys: true);
      if (guessed != null && guessed.isNotEmpty) {
        return (bytes: guessed, fileName: fileName);
      }
    }

    final err = lastError;
    if (err is Exception) throw err;
    throw Exception(err?.toString() ?? '下载文档失败');
  }

  Future<Uint8List> _downloadBytesViaStorageProxy(
    String objectKey, {
    String bucket = 'kb-documents',
  }) async {
    final raw = objectKey.trim();
    if (raw.isEmpty) {
      throw Exception('文档路径无效');
    }
    final candidates = <String>[];
    void add(String value) {
      final v = value.trim();
      if (v.isEmpty || candidates.contains(v)) return;
      candidates.add(v);
    }

    add(_normalizeObjectKeyForBucket(raw, bucket: bucket));
    add(raw);
    final fromUrl = _extractObjectKeyFromUrl(raw, bucket: bucket);
    if (fromUrl.isNotEmpty) {
      add(_normalizeObjectKeyForBucket(fromUrl, bucket: bucket));
      add(fromUrl);
    }

    Object? lastError;
    for (final key in candidates) {
      final resp = await _client.get(
        _dunesUri(
          '/storage/download?bucket=$bucket&objectKey=${Uri.encodeComponent(key)}&proxy=1',
        ),
        headers: _dunesHeaders,
      );
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.bodyBytes.isNotEmpty) {
        return resp.bodyBytes;
      }
      lastError = Exception('下载文档失败（HTTP ${resp.statusCode}）');
    }
    throw lastError ?? Exception('下载文档失败');
  }

  Future<Uint8List> _downloadBytesFromUrl(String downloadUrl) async {
    final url = downloadUrl.trim();
    if (!isDirectHttpUrl(url)) {
      throw Exception('下载链接无效');
    }
    // 预签名 URL 不能追加 query，否则签名校验失败 → 403。
    final resp = await _client.get(Uri.parse(url));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('下载文档失败（HTTP ${resp.statusCode}）');
    }
    if (resp.bodyBytes.isEmpty) {
      throw Exception('文档内容为空');
    }
    return resp.bodyBytes;
  }

  Future<NativeKbDocument> fetchDocumentDetail(String documentId) async {
    final hint = await findDocumentById(documentId);
    final dunesId = await resolveDunesDocumentIdAsync(
      doc: hint,
      docId: documentId,
    );
    if (dunesId.isEmpty) {
      throw Exception('该文档尚未关联本地知识库，请返回刷新后重试');
    }
    return fetchDunesDocument(dunesId);
  }

  Future<void> recordDocumentView(String documentId) async {
    final dunesId = resolveDunesDocumentId(docId: documentId);
    if (dunesId.isEmpty) return;
    try {
      await _client.post(
        _dunesUri('/kb/documents/$dunesId/view'),
        headers: _dunesHeaders,
      );
    } catch (_) {}
  }

  /// 使用后端签名的 downloadUrl 直读正文（签名约 1 小时有效）。
  Future<String> fetchTextFromSignedUrl(String downloadUrl) async {
    final url = downloadUrl.trim();
    if (!isDirectHttpUrl(url)) {
      throw Exception('下载链接无效');
    }
    // 预签名 URL 不能追加 cache-bust query，否则签名失效返回 403。
    final resp = await _client.get(Uri.parse(url));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('无法读取文档内容（HTTP ${resp.statusCode}）');
    }
    if (resp.body.isEmpty) {
      throw Exception('文档内容为空');
    }
    return decodeHttpResponseText(
      resp.bodyBytes,
      contentType: resp.headers['content-type'] ?? '',
    );
  }

  Future<String> fetchTextViaStorageProxy(
    String objectKey, {
    String bucket = 'kb-documents',
  }) async {
    final raw = objectKey.trim();
    if (raw.isEmpty) {
      throw Exception('文档路径无效');
    }
    final candidates = <String>[];
    void add(String value) {
      final v = value.trim();
      if (v.isEmpty) return;
      if (candidates.contains(v)) return;
      candidates.add(v);
    }

    final normalized = _normalizeObjectKeyForBucket(raw, bucket: bucket);
    add(normalized);
    add(raw);
    final fromUrl = _extractObjectKeyFromUrl(raw, bucket: bucket);
    if (fromUrl.isNotEmpty) {
      add(_normalizeObjectKeyForBucket(fromUrl, bucket: bucket));
      add(fromUrl);
    }

    Object? lastError;
    int? lastStatus;
    for (final key in candidates) {
      final resp = await _client.get(
        Uri.parse(
          _withCacheBust(
            _dunesUri(
              '/storage/download?bucket=$bucket&objectKey=${Uri.encodeComponent(key)}&proxy=1',
            ).toString(),
          ),
        ),
        headers: _dunesHeaders,
      );
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.body.isNotEmpty) {
        return decodeHttpResponseText(
          resp.bodyBytes,
          contentType: resp.headers['content-type'] ?? '',
        );
      }
      if (resp.statusCode >= 200 &&
          resp.statusCode < 300 &&
          resp.body.isEmpty) {
        lastError = Exception('文档内容为空');
        lastStatus = resp.statusCode;
        continue;
      }
      lastStatus = resp.statusCode;
      lastError = Exception('无法读取文档内容（HTTP ${resp.statusCode}）');
    }
    throw _kbContentReadException(lastError, statusCode: lastStatus);
  }

  List<String> _kbStorageKeyCandidates(NativeKbDocument doc) {
    final userId = session.userId;
    final out = <String>[];
    void add(String value) {
      final v = value.trim();
      if (v.isEmpty || out.contains(v)) return;
      out.add(v);
    }

    add(doc.fileObjectKey);
    final ragId = doc.ragflowDocId.trim().isNotEmpty
        ? doc.ragflowDocId.trim()
        : doc.id.trim();
    final names = <String>{doc.fileName.trim(), doc.title.trim()}
      ..removeWhere((s) => s.isEmpty);

    for (final name in names) {
      add('$userId/$name');
      if (ragId.isNotEmpty && int.tryParse(ragId) == null) {
        add('$userId/ragflow/$ragId/$name');
      }
      final meetingMatch = RegExp(
        r'meeting-minutes-(\d+)',
        caseSensitive: false,
      ).firstMatch(name);
      if (meetingMatch != null) {
        add('$userId/meeting-minutes-${meetingMatch.group(1)}.md');
      }
    }

    final objectKey = doc.fileObjectKey.trim().toLowerCase();
    final legacyInKey = RegExp(r'meeting-minutes-(\d+)').firstMatch(objectKey);
    if (legacyInKey != null) {
      add('$userId/meeting-minutes-${legacyInKey.group(1)}.md');
    }
    return out;
  }

  Future<List<String>> _meetingMinutesLegacyStorageKeys(
    NativeKbDocument doc,
  ) async {
    final title = doc.title.trim();
    final fileName = doc.fileName.trim();
    final looksLikeMeetingMinutes =
        title.startsWith('会议纪要') ||
        fileName.startsWith('会议纪要') ||
        title.contains('meeting-minutes') ||
        fileName.contains('meeting-minutes');
    if (!looksLikeMeetingMinutes) return const [];

    final out = <String>[];
    void add(String value) {
      final v = value.trim();
      if (v.isEmpty || out.contains(v)) return;
      out.add(v);
    }

    final meetingMatch = RegExp(
      r'meeting-minutes-(\d+)',
      caseSensitive: false,
    ).firstMatch('$title $fileName ${doc.fileObjectKey}');
    final meetingId = meetingMatch != null
        ? int.tryParse(meetingMatch.group(1) ?? '')
        : null;

    try {
      final meetings = await NativeMeetingService(
        session: session,
      ).fetchList(page: 0, size: 100);
      for (final meeting in meetings) {
        if (meeting.meetingId <= 0) continue;
        if (meetingId != null && meeting.meetingId != meetingId) continue;
        add('${session.userId}/meeting-minutes-${meeting.meetingId}.md');
        final kbTitle = MeetingMinutesExport.kbUploadTitleFromSummary(meeting);
        final kbFile = MeetingMinutesExport.kbUploadFileNameFromSummary(
          meeting,
        );
        add('${session.userId}/$kbFile');
        add('${session.userId}/${kbTitle}.md');
      }
    } catch (_) {}
    return out;
  }

  /// 优先读文档记录关联的对象；仅在记录缺失时扫描 MinIO 遗留路径。
  Future<String?> _tryFetchKbMarkdownLegacyFallback(
    NativeKbDocument doc,
  ) async {
    final ragId = doc.id.trim();
    // RAGFlow 直传文档没有 MinIO 镜像时，遗留路径会命中旧版 meeting-minutes 文件。
    if (ragId.isNotEmpty && int.tryParse(ragId) == null) {
      return null;
    }

    final keys = <String>[..._kbStorageKeyCandidates(doc)];
    keys.addAll(await _meetingMinutesLegacyStorageKeys(doc));
    for (final key in keys) {
      try {
        final text = await fetchTextViaStorageProxy(key);
        if (text.trim().isNotEmpty) return text;
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _fetchMarkdownFromDocumentRecord({
    required NativeKbDocument doc,
    required String docId,
  }) async {
    try {
      final md = await fetchKbDocumentText(
        downloadUrl: doc.fileUrl,
        objectKey: doc.fileObjectKey,
      );
      if (md.trim().isNotEmpty) return md;
    } catch (_) {}

    try {
      final dunesId = await _resolveDunesDocumentIdForPreview(
        doc: doc,
        docId: docId,
      );
      if (dunesId.isEmpty) return null;
      final fresh = await fetchDunesDocument(dunesId);
      final download = await fetchDocumentDownload(dunesId);
      final md = await fetchKbDocumentText(
        downloadUrl: download.downloadUrl,
        objectKey: fresh.fileObjectKey,
      );
      if (md.trim().isNotEmpty) {
        await recordDocumentView(dunesId);
        return md;
      }
    } catch (_) {}

    final ragId = doc.id.trim();
    if (ragId.isNotEmpty && int.tryParse(ragId) == null) {
      try {
        final mirrored = await fetchDunesDocumentByRagflowId(ragId);
        final md = await fetchKbDocumentText(
          downloadUrl: mirrored.fileUrl,
          objectKey: mirrored.fileObjectKey,
        );
        if (md.trim().isNotEmpty) return md;
      } catch (_) {}
    }
    return null;
  }

  static String _withCacheBust(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return url;
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            '_': '${DateTime.now().millisecondsSinceEpoch}',
          },
        )
        .toString();
  }

  Future<String> fetchKbDocumentText({
    required String downloadUrl,
    required String objectKey,
    String bucket = 'kb-documents',
  }) async {
    final key = objectKey.trim();
    if (key.isNotEmpty && !isDirectHttpUrl(key)) {
      return fetchTextViaStorageProxy(key, bucket: bucket);
    }
    final keyFromUrl = _extractObjectKeyFromUrl(key, bucket: bucket);
    if (keyFromUrl.isNotEmpty) {
      return fetchTextViaStorageProxy(keyFromUrl, bucket: bucket);
    }

    final signed = downloadUrl.trim();
    if (signed.isNotEmpty && isDirectHttpUrl(signed)) {
      if (isUrlLikelyDeviceReachable(signed)) {
        try {
          return await fetchTextFromSignedUrl(signed);
        } catch (_) {}
      }
      final signedKey = _extractObjectKeyFromUrl(signed, bucket: bucket);
      if (signedKey.isNotEmpty) {
        return fetchTextViaStorageProxy(signedKey, bucket: bucket);
      }
    }

    if (key.isNotEmpty &&
        isDirectHttpUrl(key) &&
        isUrlLikelyDeviceReachable(key)) {
      try {
        return await fetchTextFromSignedUrl(key);
      } catch (_) {}
    }
    if (signed.isNotEmpty && isDirectHttpUrl(signed)) {
      return fetchTextFromSignedUrl(signed);
    }
    throw Exception('无法读取文档内容');
  }

  static String _normalizeObjectKeyForBucket(
    String key, {
    required String bucket,
  }) {
    var out = key.trim().replaceFirst(RegExp(r'^/'), '');
    final prefixed = '$bucket/';
    if (out.startsWith(prefixed)) {
      out = out.substring(prefixed.length);
    }
    return out;
  }

  static String _extractObjectKeyFromUrl(
    String value, {
    required String bucket,
  }) {
    final raw = value.trim();
    if (raw.isEmpty || !isDirectHttpUrl(raw)) return '';
    final uri = Uri.tryParse(raw);
    if (uri == null) return '';
    final qKey = uri.queryParameters['objectKey']?.trim() ?? '';
    if (qKey.isNotEmpty) return qKey;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return '';
    final bucketIdx = segments.indexOf(bucket);
    if (bucketIdx >= 0 && bucketIdx + 1 < segments.length) {
      return segments.sublist(bucketIdx + 1).join('/');
    }
    return '';
  }

  String storageProxyDownloadUrl(
    String objectKey, {
    String bucket = 'kb-documents',
  }) {
    final key = objectKey.trim();
    if (key.isEmpty) return '';
    return _dunesUri(
      '/storage/download?bucket=$bucket&objectKey=${Uri.encodeComponent(key)}&proxy=1',
    ).toString();
  }

  bool isMarkdownDocument(NativeKbDocument doc, {String fileName = ''}) {
    final name = fileName.isNotEmpty ? fileName : doc.fileName;
    if (novaIsMarkdownFile(name)) return true;
    if (doc.fileExtension.toLowerCase() == 'md') return true;
    return doc.title.toLowerCase().endsWith('.md');
  }

  Future<
    ({
      NativeKbDocument doc,
      String fileName,
      String? downloadUrl,
      String? markdown,
    })
  >
  loadDocumentPreview({
    required String docId,
    NativeKbDocument? initialDoc,
  }) async {
    final refreshed = await findDocumentById(docId);
    final hint = refreshed ?? initialDoc;
    if (hint == null) {
      throw Exception('文档不存在或暂不可用');
    }

    final fileName = hint.fileName.isNotEmpty ? hint.fileName : hint.title;
    String? downloadUrl;
    if (isDirectHttpUrl(hint.fileUrl)) {
      downloadUrl = hint.fileUrl.trim();
    } else if (hint.fileObjectKey.isNotEmpty) {
      downloadUrl = storageProxyDownloadUrl(hint.fileObjectKey);
    }

    if (isMarkdownDocument(hint, fileName: fileName)) {
      var md = await _fetchMarkdownFromDocumentRecord(doc: hint, docId: docId);
      md ??= await _tryFetchKbMarkdownLegacyFallback(hint);

      if (md != null && md.trim().isNotEmpty) {
        return (
          doc: hint,
          fileName: fileName,
          downloadUrl: downloadUrl,
          markdown: md,
        );
      }
      throw Exception('无法读取文档内容');
    }

    if (downloadUrl != null || hint.fileObjectKey.isNotEmpty) {
      return (
        doc: hint,
        fileName: fileName,
        downloadUrl: downloadUrl,
        markdown: null,
      );
    }
    throw Exception('该文档尚未关联本地知识库，请返回刷新后重试');
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
    final model =
        (session.novaLocalStorage?['dunes_nova_chat_model'] ??
                session.novaLocalStorage?['dunes_nova_default_model'] ??
                NovaConfig.defaultChatModel)
            .trim();
    final bizUser =
        (session.novaLocalStorage?['dunes_nova_biz_user_id'] ??
                session.userId.toString())
            .trim();
    final req = http.Request(
      'POST',
      Uri.parse('$_novaBase/v1/chat/completions'),
    );
    req.headers.addAll(
      _novaHeaders(
        extra: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          if (sessionId.isNotEmpty) 'X-Nova-Chat-Session-Id': sessionId,
        },
      ),
    );
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
          streamError =
              (json['error']?['message'] ?? json['message'] ?? 'Nova 流式错误')
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
          sourceTitle:
              (map['sourceTitle'] ??
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
      return (j['error']?['message'] ??
              j['message'] ??
              'Nova 请求失败 HTTP $status')
          .toString();
    } catch (_) {
      return text.isEmpty
          ? 'Nova 请求失败 HTTP $status'
          : text.substring(0, min(320, text.length));
    }
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return const {};
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }
}
