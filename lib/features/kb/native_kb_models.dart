class NativeKbDocument {
  const NativeKbDocument({
    required this.id,
    required this.title,
    required this.fileName,
    required this.fileExtension,
    required this.ingestionStatus,
    required this.indexed,
    this.runStatus = '',
    this.fileObjectKey = '',
    this.fileUrl = '',
    this.localDocId = '',
    this.ragflowDocId = '',
    this.fileSizeBytes = 0,
    this.folderId,
  });

  final String id;
  final String title;
  final String fileName;
  final String fileExtension;
  final String ingestionStatus;
  final bool indexed;
  final String runStatus;
  final String fileObjectKey;
  final String fileUrl;
  final String localDocId;
  final String ragflowDocId;
  final int fileSizeBytes;
  final int? folderId;

  /// kb-go 本地文档 ID（数字），用于 GET /api/v1/kb/documents/{id}。
  String get dunesDocumentId {
    if (_isNumericId(localDocId)) return localDocId.trim();
    if (_isNumericId(id)) return id.trim();
    return '';
  }

  /// Nova / RAGFlow 文档 ID。列表删除优先走 kb-go 本地 ID，这个只作 Nova 回退。
  String get novaDocumentId {
    final rag = ragflowDocId.trim();
    if (rag.isNotEmpty) return rag;
    final id = this.id.trim();
    if (id.isNotEmpty && !_isNumericId(id)) return id;
    return id;
  }

  String get statusLabel {
    if (indexed || ingestionStatus.toUpperCase() == 'INDEXED') {
      return '已索引';
    }
    final run = runStatus.toUpperCase();
    final ingestion = ingestionStatus.toUpperCase();
    if (run == 'RUNNING' ||
        run == '1' ||
        ingestion == 'PARSING' ||
        ingestion == 'INDEXING' ||
        ingestion == 'PROCESSING') {
      return '解析中';
    }
    if (run == 'FAIL' ||
        run == 'FAILED' ||
        ingestion == 'FAILED' ||
        ingestion == 'ERROR') {
      return '解析失败';
    }
    if (run == 'DONE' || ingestion == 'DONE') {
      return '已索引';
    }
    return '已上传';
  }

  factory NativeKbDocument.fromJson(
    Map<String, dynamic> json, {
    int index = 0,
  }) {
    final runStatus = (json['runStatus'] ?? json['run'] ?? '')
        .toString()
        .trim();
    final runUpper = runStatus.toUpperCase();
    final progress = (json['progress'] as num?)?.toDouble();
    final chunkCount =
        (json['chunk_count'] ?? json['chunkCount'] as num?)?.toInt() ?? 0;
    var indexed =
        json['indexed'] == true ||
        (json['ingestionStatus'] ?? '').toString().toUpperCase() == 'INDEXED';
    if (!indexed &&
        runUpper == 'DONE' &&
        ((progress != null && progress >= 1) || chunkCount > 0)) {
      indexed = true;
    }
    final id =
        (json['id'] ??
                json['documentId'] ??
                json['ragflowDocId'] ??
                'doc-$index')
            .toString();
    var ragflowDocId = (json['ragflowDocId'] ?? json['ragflow_doc_id'] ?? '')
        .toString()
        .trim();
    if (ragflowDocId.isEmpty && id.trim().isNotEmpty && !_isNumericId(id)) {
      ragflowDocId = id.trim();
    }
    return NativeKbDocument(
      id: id,
      title: (json['title'] ?? json['name'] ?? json['fileName'] ?? '知识库文档')
          .toString(),
      fileName: (json['fileName'] ?? json['name'] ?? json['title'] ?? '')
          .toString(),
      fileExtension: (json['fileExtension'] ?? '').toString().isNotEmpty
          ? (json['fileExtension'] ?? '').toString()
          : _extensionFromFileName(
              (json['fileName'] ?? json['name'] ?? json['title'] ?? '')
                  .toString(),
            ),
      ingestionStatus:
          (json['ingestionStatus'] ??
                  (indexed
                      ? 'INDEXED'
                      : (runUpper == 'DONE' ? 'DONE' : 'UPLOADED')))
              .toString(),
      indexed: indexed,
      runStatus: runStatus,
      fileObjectKey:
          (json['fileObjectKey'] ??
                  json['objectKey'] ??
                  json['storageKey'] ??
                  json['file_object_key'] ??
                  '')
              .toString(),
      fileUrl:
          (json['url'] ??
                  json['downloadUrl'] ??
                  json['publicUrl'] ??
                  json['accessUrl'] ??
                  json['previewUrl'] ??
                  '')
              .toString(),
      localDocId:
          (json['localDocId'] ??
                  json['local_doc_id'] ??
                  json['dunesDocumentId'] ??
                  '')
              .toString(),
      ragflowDocId: ragflowDocId,
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
      folderId: _readOptionalInt(
        json['folderId'] ?? json['folder_id'] ?? json['orgFolderId'] ?? json['org_folder_id'],
      ),
    );
  }

  NativeKbDocument copyWith({
    String? id,
    String? title,
    String? fileName,
    String? fileExtension,
    String? ingestionStatus,
    bool? indexed,
    String? runStatus,
    String? fileObjectKey,
    String? fileUrl,
    String? localDocId,
    String? ragflowDocId,
    int? fileSizeBytes,
    int? folderId,
  }) {
    return NativeKbDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      fileName: fileName ?? this.fileName,
      fileExtension: fileExtension ?? this.fileExtension,
      ingestionStatus: ingestionStatus ?? this.ingestionStatus,
      indexed: indexed ?? this.indexed,
      runStatus: runStatus ?? this.runStatus,
      fileObjectKey: fileObjectKey ?? this.fileObjectKey,
      fileUrl: fileUrl ?? this.fileUrl,
      localDocId: localDocId ?? this.localDocId,
      ragflowDocId: ragflowDocId ?? this.ragflowDocId,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      folderId: folderId ?? this.folderId,
    );
  }
}

class NativeKbDocumentPage {
  const NativeKbDocumentPage({
    required this.items,
    required this.page,
    required this.size,
    required this.total,
  });

  final List<NativeKbDocument> items;
  final int page;
  final int size;
  final int total;

  int get totalPages {
    if (size <= 0) return 1;
    final pages = (total + size - 1) ~/ size;
    return pages < 1 ? 1 : pages;
  }

  factory NativeKbDocumentPage.fromJson(
    Map<String, dynamic> json, {
    int fallbackPage = 0,
    int fallbackSize = 20,
  }) {
    final content =
        (json['content'] as List?) ??
        (json['items'] as List?) ??
        (json['documents'] as List?) ??
        const [];
    final items = content
        .whereType<Map>()
        .toList(growable: false)
        .asMap()
        .entries
        .map(
          (entry) => NativeKbDocument.fromJson(
            Map<String, dynamic>.from(entry.value),
            index: entry.key,
          ),
        )
        .toList(growable: false);
    final size = _jsonInt(json['size'], fallbackSize);
    final total = _jsonInt(
      json['total'] ?? json['totalElements'] ?? json['count'],
      items.length,
    );
    return NativeKbDocumentPage(
      items: items,
      page: _jsonInt(json['page'] ?? json['number'], fallbackPage),
      size: size <= 0 ? fallbackSize : size,
      total: total,
    );
  }
}

int _jsonInt(dynamic value, int fallback) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

int? _readOptionalInt(dynamic value) {
  if (value is num) {
    final n = value.toInt();
    return n > 0 ? n : null;
  }
  final parsed = int.tryParse('$value');
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

class NativeKbSummary {
  const NativeKbSummary({
    required this.documentCount,
    required this.categoryCount,
    required this.unreadCount,
    required this.ready,
    required this.documents,
    required this.folderId,
    this.message = '',
  });

  final int documentCount;
  final int categoryCount;
  final int unreadCount;
  final bool ready;
  final List<NativeKbDocument> documents;
  final String folderId;
  final String message;
}

String _extensionFromFileName(String fileName) {
  final name = fileName.trim().toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot >= name.length - 1) return '';
  return name.substring(dot + 1);
}

bool _isNumericId(String raw) {
  final s = raw.trim();
  return s.isNotEmpty && int.tryParse(s) != null;
}

/// Nova 删除接口的 folderId 必须是 RAGFlow dataset id。
/// 个人库占位（mine）、未分类、组织文件夹数字 ID 都不能传，否则后端会报 folder not found。
String? kbNovaFolderIdForDelete(String? folderId) {
  final id = folderId?.trim() ?? '';
  if (id.isEmpty) return null;
  switch (id.toLowerCase()) {
    case 'mine':
    case 'uncategorized':
    case 'all':
    case 'default':
      return null;
  }
  if (int.tryParse(id) != null) return null;
  return id;
}

bool nativeKbHasPendingParse(List<NativeKbDocument> docs) {
  return docs.any((doc) {
    final run = doc.runStatus.toUpperCase();
    if (run.isNotEmpty && run != 'DONE' && run != 'FAIL' && run != 'FAILED') {
      return true;
    }
    return doc.statusLabel == '解析中';
  });
}

/// 知识库文档是否已完成索引（可用于 NOVA RAG / PRD 生成）。
bool nativeKbDocumentIndexed(NativeKbDocument doc) {
  if (doc.indexed) return true;
  final ingestion = doc.ingestionStatus.toUpperCase();
  if (ingestion == 'INDEXED') return true;
  return doc.statusLabel == '已索引';
}

/// 是否由「会议纪要 → 上传知识库」写入，而不是用户自己传到知识库的普通文件。
bool isKbMeetingMinutesDocument(NativeKbDocument doc) {
  return isKbMeetingMinutesUploadName(doc.fileName) ||
      isKbMeetingMinutesUploadName(doc.title) ||
      isKbMeetingMinutesUploadName(doc.fileObjectKey);
}

bool isKbMeetingMinutesName(String raw) => isKbMeetingMinutesUploadName(raw);

/// 会议详情页上传知识库时的命名：`会议纪要-{标题}.md` 或 `meeting-minutes-{id}.md`。
bool isKbMeetingMinutesUploadName(String raw) {
  final name = raw.trim().toLowerCase().replaceAll('\\', '/');
  if (name.isEmpty) return false;
  final base = name.split('/').last;
  if (base.startsWith('会议纪要-')) return true;
  if (base == 'meeting-minutes.md' || base.startsWith('meeting-minutes-')) {
    return true;
  }
  return name.contains('/meeting-minutes-') || name.endsWith('/meeting-minutes.md');
}

/// 小饕知识库选择器：只去掉会议纪要上传进来的文档，以及会议已绑定的 kb 文档。
bool novaKbDocumentAllowedInPicker(
  NativeKbDocument doc, {
  Set<int> meetingKbIds = const <int>{},
}) {
  if (isKbMeetingMinutesDocument(doc)) return false;
  final local = int.tryParse(doc.dunesDocumentId) ?? 0;
  if (local > 0 && meetingKbIds.contains(local)) return false;
  return true;
}

class NativeKbChunk {
  const NativeKbChunk({
    required this.docId,
    required this.title,
    required this.chunk,
  });

  final int docId;
  final String title;
  final String chunk;

  factory NativeKbChunk.fromJson(Map<String, dynamic> json) {
    return NativeKbChunk(
      docId: _chunkDocId(json),
      title: (json['title'] ??
              json['documentTitle'] ??
              json['fileName'] ??
              json['name'] ??
              '')
          .toString()
          .trim(),
      chunk: (json['chunk'] ??
              json['excerpt'] ??
              json['text'] ??
              json['content'] ??
              json['chunkText'] ??
              '')
          .toString()
          .trim(),
    );
  }
}

int _chunkDocId(Map<String, dynamic> json) {
  final raw = json['docId'] ?? json['documentId'] ?? json['id'];
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw') ?? 0;
}

List<NativeKbChunk> parseNovaKbRetrieveBody(Map<String, dynamic> body) {
  final data = body['data'];
  var rows = const <dynamic>[];
  if (data is List) {
    rows = data;
  } else if (data is Map) {
    final map = Map<String, dynamic>.from(data);
    final nested =
        map['content'] ?? map['items'] ?? map['chunks'] ?? map['records'];
    if (nested is List) rows = nested;
  } else if (body['content'] is List) {
    rows = body['content'] as List;
  } else if (body['chunks'] is List) {
    rows = body['chunks'] as List;
  }
  return rows
      .whereType<Map>()
      .map((row) => NativeKbChunk.fromJson(Map<String, dynamic>.from(row)))
      .where((chunk) => chunk.chunk.isNotEmpty)
      .toList(growable: false);
}

class NativeKbCitation {
  const NativeKbCitation({
    required this.sourceTitle,
    required this.chunkText,
    this.page,
  });

  final String sourceTitle;
  final String chunkText;
  final int? page;
}

class NativeKbMessage {
  const NativeKbMessage({
    required this.id,
    required this.role,
    required this.text,
    this.citations = const <NativeKbCitation>[],
    this.createdAt,
    this.streaming = false,
  });

  final int id;
  final String role;
  final String text;
  final List<NativeKbCitation> citations;
  final DateTime? createdAt;
  final bool streaming;

  NativeKbMessage copyWith({
    String? text,
    List<NativeKbCitation>? citations,
    bool? streaming,
  }) {
    return NativeKbMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      citations: citations ?? this.citations,
      createdAt: createdAt,
      streaming: streaming ?? this.streaming,
    );
  }
}
