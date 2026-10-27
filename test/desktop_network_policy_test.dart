import 'dart:io';
import 'dart:async';

import 'package:dunes_app/core/network/desktop_network_settings.dart';
import 'package:dunes_app/core/network/desktop_network_transport_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('network preference persists across controller recreation', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = DesktopNetworkSettings();
    await settings.ensureLoaded();
    expect(settings.mode, DesktopNetworkMode.defaultConnection);
    var changes = 0;
    settings.addListener(() => changes++);
    await settings.setMode(DesktopNetworkMode.direct);
    await settings.setMode(DesktopNetworkMode.direct);
    expect(changes, 1);
    final restored = DesktopNetworkSettings();
    await restored.ensureLoaded();
    expect(restored.direct, isTrue);
    await restored.setMode(DesktopNetworkMode.defaultConnection);
    final defaults = DesktopNetworkSettings();
    await defaults.ensureLoaded();
    expect(defaults.direct, isFalse);
    settings.dispose();
    restored.dispose();
    defaults.dispose();
  });

  test(
    'existing HTTP client switches proxy/direct/default without interrupting an in-flight request',
    () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var direct = false;
      final slowStarted = Completer<void>();
      final releaseSlow = Completer<void>();
      origin.listen((request) {
        request.response.write('origin');
        request.response.close();
      });
      proxy.listen((request) async {
        if (request.uri.path == '/slow') {
          slowStarted.complete();
          await releaseSlow.future;
        }
        request.response.write('proxy');
        request.response.close();
      });
      final overrides = DesktopNetworkHttpOverrides(
        direct: () => direct,
        defaultProxy: (_) => 'PROXY 127.0.0.1:${proxy.port}',
      );
      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          final client = http.Client();
          final uri = Uri.parse('http://127.0.0.1:${origin.port}/probe');
          try {
            expect((await client.get(uri)).body, 'proxy');
            final pending = client.get(uri.replace(path: '/slow'));
            await slowStarted.future;
            direct = true;
            expect((await client.get(uri)).body, 'origin');
            releaseSlow.complete();
            expect((await pending).body, 'proxy');
            direct = false;
            expect((await client.get(uri)).body, 'proxy');
          } finally {
            client.close();
          }
        }, overrides);
      } finally {
        if (!releaseSlow.isCompleted) releaseSlow.complete();
        await origin.close(force: true);
        await proxy.close(force: true);
      }
    },
  );

  test('new WebSocket connections use the same proxy policy', () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var direct = false;
    var originHits = 0;
    var proxyHits = 0;
    final sockets = <WebSocket>[];
    origin.listen((request) async {
      originHits++;
      sockets.add(await WebSocketTransformer.upgrade(request));
    });
    proxy.listen((request) async {
      proxyHits++;
      sockets.add(await WebSocketTransformer.upgrade(request));
    });
    final overrides = DesktopNetworkHttpOverrides(
      direct: () => direct,
      defaultProxy: (_) => 'PROXY 127.0.0.1:${proxy.port}',
    );
    try {
      await HttpOverrides.runWithHttpOverrides(() async {
        final uri = Uri.parse(
          'ws://127.0.0.1:${origin.port}/connection/websocket',
        );
        await probeDesktopWebSocket(uri, const Duration(seconds: 3));
        expect(proxyHits, 1);
        direct = true;
        await probeDesktopWebSocket(uri, const Duration(seconds: 3));
        expect(originHits, 1);
      }, overrides);
    } finally {
      for (final socket in sockets) {
        await socket.close();
      }
      await origin.close(force: true);
      await proxy.close(force: true);
    }
  });
}
