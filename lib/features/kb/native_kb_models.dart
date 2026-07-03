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
    this.fileSizeBytes = 0,
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
  final int fileSizeBytes;

  /// kb-go 本地文档 ID（数字），用于 GET /api/v1/kb/documents/{id}。
  String get dunesDocumentId {
    if (_isNumericId(localDocId)) return localDocId.trim();
    if (_isNumericId(id)) return id.trim();
    return '';
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

  factory NativeKbDocument.fromJson(Map<String, dynamic> json, {int index = 0}) {
    final runStatus = (json['runStatus'] ?? json['run'] ?? '').toString().trim();
    final runUpper = runStatus.toUpperCase();
    final progress = (json['progress'] as num?)?.toDouble();
    final chunkCount = (json['chunk_count'] ?? json['chunkCount'] as num?)?.toInt() ?? 0;
    var indexed = json['indexed'] == true ||
        (json['ingestionStatus'] ?? '').toString().toUpperCase() == 'INDEXED';
    if (!indexed &&
        runUpper == 'DONE' &&
        ((progress != null && progress >= 1) || chunkCount > 0)) {
      indexed = true;
    }
    return NativeKbDocument(
      id: (json['id'] ??
              json['documentId'] ??
              json['ragflowDocId'] ??
              'doc-$index')
          .toString(),
      title: (json['title'] ?? json['name'] ?? json['fileName'] ?? '知识库文档')
          .toString(),
      fileName: (json['fileName'] ?? json['name'] ?? json['title'] ?? '').toString(),
      fileExtension: (json['fileExtension'] ?? '').toString().isNotEmpty
          ? (json['fileExtension'] ?? '').toString()
          : _extensionFromFileName(
              (json['fileName'] ?? json['name'] ?? json['title'] ?? '').toString(),
            ),
      ingestionStatus: (json['ingestionStatus'] ??
              (indexed ? 'INDEXED' : (runUpper == 'DONE' ? 'DONE' : 'UPLOADED')))
          .toString(),
      indexed: indexed,
      runStatus: runStatus,
      fileObjectKey: (json['fileObjectKey'] ??
              json['objectKey'] ??
              json['storageKey'] ??
              json['file_object_key'] ??
              '')
          .toString(),
      fileUrl: (json['url'] ??
              json['downloadUrl'] ??
              json['publicUrl'] ??
              json['accessUrl'] ??
              json['previewUrl'] ??
              '')
          .toString(),
      localDocId: (json['localDocId'] ??
              json['local_doc_id'] ??
              json['dunesDocumentId'] ??
              '')
          .toString(),
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
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
