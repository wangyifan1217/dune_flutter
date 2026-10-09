import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:dunes_app/features/chat/chat_file_upload_source.dart';
import 'package:dunes_app/features/conversation/conversation_service.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const session = AuthSession(
  phone: '',
  userId: 7,
  token: 'test',
  apiBase: 'https://api.test/api/v1',
  roles: [],
);

void main() {
  test('desktop clients do not cap ordinary file size', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(chatCurrentFileLimitBytes, isNull);

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(chatCurrentFileLimitBytes, isNull);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(chatCurrentFileLimitBytes, chatAppMaxFileBytes);
  });

  test(
    'cancelling an active file upload stops before message publication',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final cancel = ChatUploadCancelToken();
      final received = Completer<void>();
      var messages = 0;
      server.listen((request) {
        if (!request.uri.path.endsWith('/storage/upload')) messages++;
        request.listen((chunk) {
          if (!received.isCompleted) {
            received.complete();
            cancel.cancel();
          }
        }, onError: (Object _) {});
      });
      final service = ConversationService(
        session: AuthSession(
          phone: '',
          userId: 7,
          token: 'test',
          roles: [],
          apiBase: 'http://127.0.0.1:${server.port}/api/v1',
        ),
      );
      addTearDown(service.close);
      final sending = service.sendFile(
        conversationId: 77,
        bytes: Uint8List(8 * 1024 * 1024),
        fileName: 'cancel.bin',
        mimeType: 'application/octet-stream',
        cancelToken: cancel,
      );
      await expectLater(sending, throwsA(isA<ChatUploadCancelledException>()));
      expect(received.isCompleted, isTrue);
      expect(messages, 0);
    },
  );

  test(
    'file source stays lazy, reopens after failure and detects changed files',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'im-source-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/payload.bin');
      await file.writeAsBytes(List.generate(150000, (i) => i % 256));
      final source = await ChatFileUploadSource.fromFile(XFile(file.path));
      final first = await source.openRead().expand((chunk) => chunk).toList();
      final second = await source.openRead().expand((chunk) => chunk).toList();
      expect(first, second);
      expect(first.length, 150000);
      await file.writeAsString('changed');
      await expectLater(
        source.openRead().drain<void>(),
        throwsA(isA<ChatFileChangedException>()),
      );
    },
  );

  test(
    'ordinary file retries only its upload, then sends compatible FILE payload',
    () async {
      var uploads = 0;
      var messages = 0;
      final progress = <double>[];
      final bytes = Uint8List.fromList(List.generate(300000, (i) => i % 256));
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/storage/upload')) {
          uploads++;
          expect(
            request.url.queryParameters['uploadMode'],
            'im-file-stream-v1',
          );
          expect(request.headers['authorization'], 'Bearer test');
          final body = latin1.decode(request.bodyBytes);
          expect(body, contains('name="fileSize"\r\n\r\n300000'));
          expect(body, contains('name="conversationId"\r\n\r\n77'));
          expect(
            body.indexOf('name="bucket"'),
            lessThan(body.indexOf('filename="payload.bin"')),
          );
          if (uploads == 1) return http.Response('unavailable', 503);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'url': 'https://files.test/payload.bin',
                'objectKey': 'https://files.test/payload.bin',
              },
            }),
            200,
          );
        }
        messages++;
        expect(progress.last, lessThan(1));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['kind'], 'FILE');
        expect(body['payload']['size'], 300000);
        expect(body['payload']['fileName'], 'payload.bin');
        return http.Response('{"success":true}', 200);
      });
      final service = ConversationService(session: session, client: client);
      addTearDown(service.close);
      await service.sendFile(
        conversationId: 77,
        bytes: bytes,
        fileName: 'payload.bin',
        mimeType: 'application/octet-stream',
        onProgress: progress.add,
      );
      expect(uploads, 2);
      expect(messages, 1);
      expect(progress.last, 1);
      expect(progress.length, lessThan(10));
    },
  );

  test(
    'permanent upload failures do not retransmit or send a message',
    () async {
      for (final status in [400, 401, 403, 413]) {
        var calls = 0;
        final service = ConversationService(
          session: session,
          client: MockClient((request) async {
            calls++;
            expect(request.url.path, endsWith('/storage/upload'));
            return http.Response('rejected', status);
          }),
        );
        await expectLater(
          service.sendFile(
            conversationId: 77,
            bytes: Uint8List(2),
            fileName: 'file.bin',
            mimeType: 'application/octet-stream',
          ),
          throwsException,
        );
        expect(calls, 1);
        service.close();
      }
    },
  );

  test(
    'other attachment callers keep their existing upload URL and metadata',
    () async {
      final service = ConversationService(
        session: session,
        client: MockClient((request) async {
          expect(request.url.query, isEmpty);
          expect(
            latin1.decode(request.bodyBytes),
            isNot(contains('name="fileSize"')),
          );
          return http.Response(
            '{"success":true,"data":{"objectKey":"legacy-key"}}',
            200,
          );
        }),
      );
      addTearDown(service.close);
      final result = await service.uploadAttachment(
        conversationId: 77,
        bytes: Uint8List(2),
        fileName: 'image.png',
        mimeType: 'image/png',
      );
      expect(result.objectKey, 'legacy-key');
    },
  );

  test('message retry reuses already uploaded URL', () async {
    var uploads = 0;
    var messages = 0;
    final service = ConversationService(
      session: session,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/storage/upload')) {
          uploads++;
          return http.Response(
            '{"success":true,"data":{"url":"https://files.test/file.bin"}}',
            200,
          );
        }
        messages++;
        return http.Response(
          messages == 1 ? 'retry' : '{"success":true}',
          messages == 1 ? 503 : 200,
        );
      }),
    );
    addTearDown(service.close);
    await service.sendFile(
      conversationId: 77,
      bytes: Uint8List(2),
      fileName: 'file.bin',
      mimeType: 'application/octet-stream',
    );
    expect(uploads, 1);
    expect(messages, 2);
  });
}
