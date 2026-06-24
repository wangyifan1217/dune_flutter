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
  final int fileSizeBytes;

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
      fileExtension: (json['fileExtension'] ?? '').toString(),
      ingestionStatus: (json['ingestionStatus'] ??
              (indexed ? 'INDEXED' : (runUpper == 'DONE' ? 'DONE' : 'UPLOADED')))
          .toString(),
      indexed: indexed,
      runStatus: runStatus,
      fileObjectKey: (json['fileObjectKey'] ?? '').toString(),
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

bool nativeKbHasPendingParse(List<NativeKbDocument> docs) {
  return docs.any((doc) {
    final run = doc.runStatus.toUpperCase();
    if (run.isNotEmpty && run != 'DONE' && run != 'FAIL' && run != 'FAILED') {
      return true;
    }
    return doc.statusLabel == '解析中';
  });
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
