import 'package:dunes_app/features/kb/native_kb_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NativeKbDocumentPage paginates totalPages', () {
    final page = NativeKbDocumentPage(
      items: const [],
      page: 5,
      size: 20,
      total: 103,
    );
    expect(page.totalPages, 6);
  });

  test('parses kb-go local document with object key and ragflow id', () {
    final page = NativeKbDocumentPage.fromJson({
      'content': [
        {
          'id': 88,
          'localDocId': 88,
          'title': '卫健委混改项目会议纪要及行动规划0902.docx',
          'fileName': '卫健委混改项目会议纪要及行动规划0902.docx',
          'fileObjectKey': '7/ragflow/rag-2/file.docx',
          'ingestionStatus': 'INDEXED',
          'ragflowDocId': 'rag-2',
          'runStatus': 'DONE',
        },
      ],
      'page': 1,
      'size': 20,
      'total': 103,
    });
    expect(page.page, 1);
    expect(page.size, 20);
    expect(page.total, 103);
    expect(page.totalPages, 6);
    expect(page.items, hasLength(1));
    final doc = page.items.first;
    expect(doc.dunesDocumentId, '88');
    expect(doc.novaDocumentId, 'rag-2');
    expect(doc.fileObjectKey, contains('ragflow'));
    expect(doc.indexed, isTrue);
  });

  test('parses ragflow-only document without local id', () {
    final doc = NativeKbDocument.fromJson({
      'id': 'rag-only-1',
      'name': 'nova-only.docx',
      'ingestionStatus': 'INDEXED',
      'runStatus': 'DONE',
      'chunkNum': 2,
    });
    expect(doc.dunesDocumentId, isEmpty);
    expect(doc.novaDocumentId, 'rag-only-1');
    expect(doc.ragflowDocId, 'rag-only-1');
    expect(doc.indexed, isTrue);
  });
}
