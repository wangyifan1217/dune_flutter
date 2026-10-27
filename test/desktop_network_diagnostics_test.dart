import 'dart:async';

import 'package:dunes_app/core/network/network_diagnostics.dart';
import 'package:dunes_app/features/auth/auth_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  AuthSession session({String avatar = ''}) => AuthSession(
    phone: '',
    userId: 1,
    token: 'test-secret',
    apiBase: 'https://app.example/api/v1',
    roles: [],
    avatarUrl: avatar,
  );

  test('relative avatar URL resolves against the application origin', () async {
    final probe = DesktopNetworkDiagnostics(
      clientFactory: () => MockClient((request) async {
        if (!request.url.path.endsWith('/users/me')) {
          expect(
            request.url.toString(),
            'https://app.example/api/v1/storage/download?objectKey=a',
          );
        }
        return http.Response(
          request.url.path.endsWith('/users/me') ? '{}' : 'file',
          200,
        );
      }),
      webSocketProbe: (_, _) async {},
    );
    final results = await probe.run(
      session(avatar: '/api/v1/storage/download?objectKey=a'),
    );
    expect(results.last.success, isTrue);
  });

  test(
    'tests API, WebSocket and actual file without uploading or downloading entire file',
    () async {
      final requests = <http.Request>[];
      final probe = DesktopNetworkDiagnostics(
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          expect(request.followRedirects, isFalse);
          expect(request.headers['Authorization'], 'Bearer test-secret');
          return http.Response(
            request.url.path.endsWith('/users/me') ? '{"data":{}}' : 'avatar',
            200,
          );
        }),
        webSocketProbe: (uri, timeout) async {
          expect(
            uri.toString(),
            'wss://app.example/connection/websocket?format=protobuf',
          );
        },
      );
      final results = await probe.run(session(avatar: 'avatars/a.png'));
      expect(results.every((result) => result.success), isTrue);
      expect(requests, hasLength(2));
      expect(requests.last.url.queryParameters['objectKey'], 'avatars/a.png');
      expect(requests.last.headers['Range'], 'bytes=0-1023');
    },
  );

  test(
    'external avatar and redirects never receive the application token',
    () async {
      final probe = DesktopNetworkDiagnostics(
        clientFactory: () => MockClient((request) async {
          if (request.url.host == 'cdn.example') {
            expect(request.headers.containsKey('Authorization'), isFalse);
            expect(request.followRedirects, isFalse);
            return http.Response(
              '',
              302,
              headers: {'location': 'https://other.example/file'},
            );
          }
          return http.Response('{}', 200);
        }),
        webSocketProbe: (_, _) async {},
      );
      final results = await probe.run(
        session(avatar: 'https://cdn.example/avatar.png'),
      );
      expect(results.last.success, isFalse);
      expect(results.last.message, contains('跳转'));
    },
  );

  test(
    'does not report expired login or captive portal as a successful connection',
    () async {
      for (final code in [200, 401, 503]) {
        final probe = DesktopNetworkDiagnostics(
          clientFactory: () => MockClient(
            (_) async => http.Response('<html>sign in</html>', code),
          ),
          webSocketProbe: (_, _) async {},
        );
        final results = await probe.run(session());
        expect(results.first.success, isFalse);
        expect(results.last.skipped, isTrue);
      }
    },
  );

  test('connection errors are bounded and do not expose credentials', () async {
    final probe = DesktopNetworkDiagnostics(
      clientFactory: () => MockClient(
        (_) async => throw http.ClientException('test-secret request failed'),
      ),
      webSocketProbe: (_, _) async => throw TimeoutException('test-secret'),
    );
    final results = await probe.run(session());
    expect(results.first.message, isNot(contains('test-secret')));
    expect(results[1].message, contains('超时'));
  });

  test('no logged-in session is reported as untested', () async {
    final results = await DesktopNetworkDiagnostics().run(null);
    expect(results.single.skipped, isTrue);
  });
}
