import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/kb/native_kb_models.dart';
import 'package:dunes_app/features/kb/native_kb_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const session = AuthSession(
    phone: '13800138000',
    userId: 7,
    token: 'token',
    apiBase: 'http://example.test/api/v1',
    roles: [],
  );

  test('kbNovaFolderIdForDelete drops mine and org folder ids', () {
    expect(kbNovaFolderIdForDelete('mine'), isNull);
    expect(kbNovaFolderIdForDelete('uncategorized'), isNull);
    expect(kbNovaFolderIdForDelete('12'), isNull);
    expect(kbNovaFolderIdForDelete(''), isNull);
    expect(kbNovaFolderIdForDelete('ds-abc'), 'ds-abc');
  });

  test('deleteDocument with local id hits kb-go not Nova', () async {
    final requests = <http.Request>[];
    final service = NativeKbService(
      session: session,
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'DELETE' &&
            request.url.path == '/api/v1/kb/documents/88') {
          return http.Response('', 204);
        }
        return http.Response('unexpected ${request.method} ${request.url}', 500);
      }),
    );
    addTearDown(service.close);

    final doc = NativeKbDocument.fromJson({
      'id': 88,
      'localDocId': 88,
      'title': '标签四',
      'fileName': '标签四.docx',
      'ingestionStatus': 'INDEXED',
      'ragflowDocId': 'rag-2',
    });
    await service.deleteDocument(
      doc.novaDocumentId,
      folderId: 'mine',
      doc: doc,
    );

    expect(requests, hasLength(1));
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/api/v1/kb/documents/88');
    expect(requests.single.url.query, isEmpty);
  });

  test('deleteDocument ragflow-only hits kb-go by-ragflow', () async {
    final requests = <http.Request>[];
    final service = NativeKbService(
      session: session,
      client: MockClient((request) async {
        requests.add(request);
        if (request.method == 'DELETE' &&
            request.url.path.endsWith('/kb/documents/by-ragflow/rag-only-1')) {
          return http.Response('', 204);
        }
        return http.Response('unexpected ${request.method} ${request.url}', 500);
      }),
    );
    addTearDown(service.close);

    final doc = NativeKbDocument.fromJson({
      'id': 'rag-only-1',
      'name': 'nova-only.docx',
      'ingestionStatus': 'INDEXED',
    });
    await service.deleteDocument(doc.novaDocumentId, folderId: '12', doc: doc);

    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/api/v1/kb/documents/by-ragflow/rag-only-1');
  });
}
