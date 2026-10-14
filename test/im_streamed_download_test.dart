import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:dunes_app/features/chat/file_download_io.dart';
import 'package:dunes_app/features/chat/file_download.dart' as downloads;
import 'package:dunes_app/features/chat/im_file_save_dir.dart';
import 'package:dunes_app/features/chat/download_progress.dart';
import 'package:dunes_app/features/conversation/conversation_service.dart';
import 'package:dunes_app/features/auth/auth_session.dart';

class _DownloadTestPaths extends PathProviderPlatform {
  _DownloadTestPaths(this.path);
  final String path;
  @override
  Future<String?> getDownloadsPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late HttpServer server;
  late String url;
  setUp(() async {
    // These are integration tests against an isolated loopback HTTP server.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('dunes-download-test-');
    PathProviderPlatform.instance = _DownloadTestPaths(root.path);
    await ImFileSaveDir.setPath(root.path);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/file';
  });
  tearDown(() async {
    await server.close(force: true);
    await ImFileSaveDir.clear();
    // Only this freshly created test directory is removed.
    await root.delete(recursive: true);
  });

  test(
    'streams a large file to disk before the response finishes and commits cache afterwards',
    () async {
      final firstSent = Completer<void>(), finish = Completer<void>();
      final chunk = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 7);
      server.listen((r) async {
        expect(r.headers.value('x-download-test'), 'yes');
        r.response.contentLength = chunk.length * 64;
        for (var i = 0; i < 16; i++) {
          r.response.add(chunk);
        }
        await r.response.flush();
        firstSent.complete();
        await finish.future;
        for (var i = 16; i < 64; i++) {
          r.response.add(chunk);
        }
        await r.response.close();
      });
      final progress = <double>[];
      final download = openUrlAsFileImpl(
        url,
        '报告.bin',
        cacheKey: 'key-1',
        conversationId: 42,
        headers: {'x-download-test': 'yes'},
        onProgress: progress.add,
      );
      await firstSent.future;
      File? partial;
      for (var attempt = 0; attempt < 100; attempt++) {
        final entries = await root.list(recursive: true).toList();
        for (final entry in entries.whereType<File>()) {
          if (entry.path.endsWith('.part') && await entry.length() > 0) {
            partial = entry;
          }
        }
        if (partial != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        partial,
        isNotNull,
        reason: 'File must be written before the network stream completes',
      );
      expect(
        await findCachedChatFileImpl('key-1', '报告.bin', conversationId: 42),
        isNull,
      );
      finish.complete();
      final saved = await download;
      expect(await File(saved).length(), chunk.length * 64);
      expect(
        await findCachedChatFileImpl('key-1', '报告.bin', conversationId: 42),
        saved,
      );
      expect(progress.last, 1);
      expect(
        (await root.list().toList()).where(
          (e) => e.path.contains('.dunes-download-'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'different messages with the same filename keep separate complete files',
    () async {
      var count = 0;
      server.listen((r) async {
        r.response.write('${++count}');
        await r.response.close();
      });
      final a = await openUrlAsFileImpl(
        url,
        '同名.txt',
        cacheKey: 'a',
        conversationId: 42,
      );
      final b = await openUrlAsFileImpl(
        url,
        '同名.txt',
        cacheKey: 'b',
        conversationId: 42,
      );
      expect(a, isNot(b));
      expect(await File(a).readAsString(), '1');
      expect(await File(b).readAsString(), '2');
      expect(
        await findCachedChatFileImpl('a', '同名.txt', conversationId: 42),
        a,
      );
      expect(
        await findCachedChatFileImpl('b', '同名.txt', conversationId: 42),
        b,
      );
    },
  );

  test(
    'cancel removes partial data and never marks the file complete',
    () async {
      final sent = Completer<void>();
      server.listen((r) async {
        r.response.contentLength = 10 * 1024 * 1024;
        r.response.add(Uint8List(1024 * 1024));
        try {
          await r.response.flush();
        } catch (_) {}
        if (!sent.isCompleted) sent.complete();
      });
      final token = ChatUploadCancelToken();
      final download = openUrlAsFileImpl(
        url,
        '取消.bin',
        cacheKey: 'cancel',
        conversationId: 42,
        cancelToken: token,
      );
      final expectation = expectLater(
        download,
        throwsA(isA<ChatDownloadCancelledException>()),
      );
      await sent.future;
      token.cancel();
      await expectation;
      expect(
        await findCachedChatFileImpl('cancel', '取消.bin', conversationId: 42),
        isNull,
      );
      expect(
        (await root.list(recursive: true).toList()).whereType<File>(),
        isEmpty,
      );
    },
  );

  test(
    'a broken transfer preserves the previously downloaded version',
    () async {
      final old = await saveBytesAsCachedFileImpl(
        Uint8List.fromList([1, 2, 3]),
        'same',
        '旧文件.bin',
        conversationId: 42,
      );
      server.listen((r) async {
        r.response.contentLength = 1024 * 1024;
        final socket = await r.response.detachSocket(writeHeaders: true);
        socket.add([4, 5, 6]);
        await socket.flush();
        socket.destroy();
      });
      await expectLater(
        openUrlAsFileImpl(url, '旧文件.bin', cacheKey: 'same', conversationId: 42),
        throwsA(anything),
      );
      expect(await File(old).readAsBytes(), [1, 2, 3]);
      expect(
        await findCachedChatFileImpl('same', '旧文件.bin', conversationId: 42),
        old,
      );
      expect(
        (await root.list().toList()).where(
          (e) => e.path.contains('.dunes-download-'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'encoded HTTP responses do not compare decoded bytes to compressed length',
    () async {
      final body = List<int>.filled(65536, 65),
          compressed = gzip.encode(List<int>.filled(65536, 65));
      server.listen((r) async {
        r.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        r.response.contentLength = compressed.length;
        r.response.add(compressed);
        await r.response.close();
      });
      final saved = await openUrlAsFileImpl(url, 'gzip.txt');
      expect(await File(saved).readAsBytes(), body);
    },
  );

  test(
    'shared attachment entry streams authenticated files with the existing API',
    () async {
      server.listen((r) async {
        expect(r.uri.path, '/api/v1/storage/download');
        expect(r.headers.value('authorization'), 'Bearer test-token');
        r.response.write('authenticated-file');
        await r.response.close();
      });
      final service = ConversationService(
        session: AuthSession(
          phone: 'test',
          userId: 7,
          token: 'test-token',
          apiBase: 'http://127.0.0.1:${server.port}/api/v1',
          roles: [],
        ),
      );
      final saved = await downloads.downloadChatAttachment(
        service,
        {'objectKey': 'im-attachments/test/file.pdf'},
        '文件.pdf',
        cacheKey: 'auth',
        conversationId: 42,
      );
      expect(await File(saved!).readAsString(), 'authenticated-file');
      expect(
        await findCachedChatFileImpl('auth', '文件.pdf', conversationId: 42),
        saved,
      );
    },
  );

  test(
    'progress throttles bursts and only explicitly completes at 100 percent',
    () {
      final events = <double>[];
      final reporter = DownloadProgressReporter(events.add);
      for (var i = 0; i < 1000; i++) {
        reporter.received(i, 1000);
      }
      expect(events.length, 1);
      expect(events.every((p) => p < 1), isTrue);
      reporter.complete();
      expect(events.last, 1);
    },
  );

  test(
    'streaming keeps authenticated object paths and excludes auth on public URLs',
    () {
      final service = ConversationService(
        session: const AuthSession(
          phone: 'test',
          userId: 7,
          token: 'secret-test',
          apiBase: 'http://localhost/api/v1',
          roles: [],
        ),
      );
      final auth = service.attachmentDownloadRequest(
        objectKey: 'im-attachments/test/file.pdf',
        fileName: '文件.pdf',
      );
      expect(auth.url.path, endsWith('/storage/download'));
      expect(auth.headers['authorization'], 'Bearer secret-test');
      final public = service.attachmentDownloadRequest(
        objectKey: 'https://example.com/files/file.pdf',
      );
      expect(public.url.toString(), 'https://example.com/files/file.pdf');
      expect(public.headers.containsKey('authorization'), isFalse);
    },
  );
}
