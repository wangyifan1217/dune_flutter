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

  test('kbNovaFolderIdForDelete ignores summary placeholders', () {
    expect(kbNovaFolderIdForDelete('mine'), isNull);
    expect(kbNovaFolderIdForDelete('uncategorized'), isNull);
    expect(kbNovaFolderIdForDelete('3'), isNull);
    expect(kbNovaFolderIdForDelete('dataset-uuid'), 'dataset-uuid');
  });

  test('only meeting-uploaded kb files are excluded from nova kb picker', () {
    final uploaded = NativeKbDocument.fromJson({
      'id': 1,
      'title': '会议纪要-需求评审',
      'fileName': '会议纪要-需求评审.md',
      'ingestionStatus': 'INDEXED',
    });
    final backend = NativeKbDocument.fromJson({
      'id': 2,
      'title': '周会',
      'fileName': 'meeting-minutes-88.md',
      'ingestionStatus': 'INDEXED',
    });
    final ordinary = NativeKbDocument.fromJson({
      'id': 3,
      'title': '报价规范',
      'fileName': '报价规范.pdf',
      'ingestionStatus': 'INDEXED',
    });
    final userMinutesDoc = NativeKbDocument.fromJson({
      'id': 5,
      'title': '卫健委混改项目会议纪要及行动规划0902.docx',
      'fileName': '卫健委混改项目会议纪要及行动规划0902.docx',
      'ingestionStatus': 'INDEXED',
    });
    expect(isKbMeetingMinutesDocument(uploaded), isTrue);
    expect(isKbMeetingMinutesDocument(backend), isTrue);
    expect(isKbMeetingMinutesDocument(ordinary), isFalse);
    expect(isKbMeetingMinutesDocument(userMinutesDoc), isFalse);
    expect(novaKbDocumentAllowedInPicker(userMinutesDoc), isTrue);
    expect(isKbMeetingMinutesUploadName('会议纪要-需求评审.md'), isTrue);
    expect(isKbMeetingMinutesUploadName('会议纪要'), isFalse);
    expect(isKbMeetingMinutesUploadName('制度文档'), isFalse);

    final keyed = NativeKbDocument.fromJson({
      'id': 4,
      'title': '周会摘要',
      'fileName': 'weekly.md',
      'fileObjectKey': '7/meeting-minutes-12.md',
      'ingestionStatus': 'INDEXED',
    });
    expect(isKbMeetingMinutesDocument(keyed), isTrue);
    expect(
      novaKbDocumentAllowedInPicker(
        ordinary,
        meetingKbIds: {3},
      ),
      isFalse,
    );
    expect(
      novaKbDocumentAllowedInPicker(
        ordinary,
        meetingKbIds: {99},
      ),
      isTrue,
    );
  });
}
