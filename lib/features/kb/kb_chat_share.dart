import 'native_kb_models.dart';

/// 会话内「知识库文档」卡片的 payload 约定：`payload.kbDoc`。
class KbChatDocShare {
  const KbChatDocShare({
    required this.id,
    required this.title,
    this.localDocId = '',
    this.fileName = '',
    this.fileExtension = '',
    this.indexed = false,
    this.fileSizeBytes = 0,
  });

  final String id;
  final String localDocId;
  final String title;
  final String fileName;
  final String fileExtension;
  final bool indexed;
  final int fileSizeBytes;

  /// 打开预览用的文档 ID（优先本地数字 ID）。
  String get openDocId {
    final local = localDocId.trim();
    if (local.isNotEmpty) return local;
    return id.trim();
  }

  String get typeLabel {
    final ext = fileExtension.trim();
    if (ext.isNotEmpty) return ext.toUpperCase();
    final name = fileName.trim().isNotEmpty ? fileName : title;
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      return name.substring(dot + 1).toUpperCase();
    }
    return 'DOC';
  }

  String get sizeLabel {
    if (fileSizeBytes <= 0) return '';
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get bodyText => '[知识库] ${title.trim().isEmpty ? '文档' : title.trim()}';

  Map<String, dynamic> toMessagePayload() {
    return <String, dynamic>{
      'kbDoc': <String, dynamic>{
        'id': id,
        'localDocId': localDocId,
        'title': title,
        'fileName': fileName,
        'fileExtension': fileExtension,
        'indexed': indexed,
        'fileSizeBytes': fileSizeBytes,
      },
    };
  }

  NativeKbDocument toDocument() {
    final resolvedId = id.isNotEmpty ? id : openDocId;
    return NativeKbDocument(
      id: resolvedId,
      title: title.isNotEmpty ? title : '知识库文档',
      fileName: fileName.isNotEmpty ? fileName : title,
      fileExtension: fileExtension,
      ingestionStatus: indexed ? 'INDEXED' : 'UPLOADED',
      indexed: indexed,
      localDocId: localDocId,
      ragflowDocId: int.tryParse(resolvedId.trim()) == null ? resolvedId : '',
      fileSizeBytes: fileSizeBytes,
    );
  }

  factory KbChatDocShare.fromDocument(NativeKbDocument doc) {
    return KbChatDocShare(
      id: doc.novaDocumentId.isNotEmpty ? doc.novaDocumentId : doc.id,
      localDocId: doc.dunesDocumentId,
      title: doc.title.trim().isNotEmpty ? doc.title.trim() : doc.fileName,
      fileName: doc.fileName,
      fileExtension: doc.fileExtension,
      indexed: doc.indexed,
      fileSizeBytes: doc.fileSizeBytes,
    );
  }

  static KbChatDocShare? fromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final raw = payload['kbDoc'];
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final id = (map['id'] ?? map['docId'] ?? '').toString().trim();
    final localDocId = (map['localDocId'] ?? map['dunesDocumentId'] ?? '')
        .toString()
        .trim();
    final title = (map['title'] ?? map['fileName'] ?? '').toString().trim();
    if (id.isEmpty && localDocId.isEmpty && title.isEmpty) return null;
    return KbChatDocShare(
      id: id.isNotEmpty ? id : localDocId,
      localDocId: localDocId,
      title: title.isNotEmpty ? title : '知识库文档',
      fileName: (map['fileName'] ?? '').toString(),
      fileExtension: (map['fileExtension'] ?? '').toString(),
      indexed: map['indexed'] == true,
      fileSizeBytes: (map['fileSizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}
