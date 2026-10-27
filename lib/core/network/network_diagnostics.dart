import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../features/auth/auth_session.dart';
import 'desktop_network_transport_stub.dart'
    if (dart.library.io) 'desktop_network_transport_io.dart'
    as transport;

class NetworkProbeResult {
  const NetworkProbeResult(
    this.name,
    this.message, {
    this.success = false,
    this.skipped = false,
  });
  final String name;
  final String message;
  final bool success;
  final bool skipped;
}

class DesktopNetworkDiagnostics {
  DesktopNetworkDiagnostics({
    http.Client Function()? clientFactory,
    Future<void> Function(Uri, Duration)? webSocketProbe,
    this.timeout = const Duration(seconds: 8),
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _webSocketProbe = webSocketProbe ?? transport.probeDesktopWebSocket;

  final http.Client Function() _clientFactory;
  final Future<void> Function(Uri, Duration) _webSocketProbe;
  final Duration timeout;

  Future<List<NetworkProbeResult>> run(AuthSession? session) async {
    if (session == null || session.token.isEmpty) {
      return const [NetworkProbeResult('连接检测', '请登录后再测试连接', skipped: true)];
    }
    final base = Uri.parse(session.apiBase.replaceAll(RegExp(r'/$'), ''));
    final api = base.replace(
      path: '${base.path}/users/me',
      query: null,
      fragment: null,
    );
    final ws = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/connection/websocket',
      query: 'format=protobuf',
      fragment: null,
    );
    return Future.wait([
      _probeHttp('业务接口', api, session, json: true),
      _probeWebSocket(ws),
      _probeAttachment(base, session),
    ]);
  }

  Future<NetworkProbeResult> _probeWebSocket(Uri uri) async {
    final watch = Stopwatch()..start();
    try {
      await _webSocketProbe(uri, timeout).timeout(timeout);
      return NetworkProbeResult(
        '消息连接',
        '消息通道可达 · ${watch.elapsedMilliseconds} ms',
        success: true,
      );
    } catch (error) {
      return NetworkProbeResult('消息连接', _errorMessage(error));
    }
  }

  Future<NetworkProbeResult> _probeAttachment(
    Uri base,
    AuthSession session,
  ) async {
    final avatar = session.avatarUrl.trim();
    if (avatar.isEmpty) {
      return const NetworkProbeResult(
        '附件下载',
        '没有可用于测试的头像文件，暂未检测下载',
        skipped: true,
      );
    }
    final parsed = Uri.tryParse(avatar);
    final Uri uri;
    if (parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https')) {
      uri = parsed;
    } else if (avatar.startsWith('/')) {
      uri = base.resolve(avatar);
    } else if (parsed != null && parsed.hasScheme) {
      return const NetworkProbeResult(
        '附件下载',
        '当前头像不是网络文件，暂未检测下载',
        skipped: true,
      );
    } else {
      uri = base.replace(
        path: '${base.path}/storage/download',
        queryParameters: {
          'bucket': 'user-avatars',
          'objectKey': avatar,
          'proxy': '1',
        },
      );
    }
    return _probeHttp('附件下载', uri, session, json: false);
  }

  Future<NetworkProbeResult> _probeHttp(
    String name,
    Uri uri,
    AuthSession session, {
    required bool json,
  }) async {
    final client = _clientFactory();
    final watch = Stopwatch()..start();
    try {
      final request = http.Request('GET', uri)..followRedirects = false;
      final base = Uri.parse(session.apiBase);
      // 外部头像/CDN 不携带沙丘凭证；跳转也不自动转送凭证。
      if (base.origin == uri.origin) {
        request.headers['Authorization'] = 'Bearer ${session.token}';
      }
      request.headers['Accept'] = json ? 'application/json' : '*/*';
      if (!json) request.headers['Range'] = 'bytes=0-1023';
      final response = await client.send(request).timeout(timeout);
      if (response.statusCode == 401 || response.statusCode == 403) {
        return NetworkProbeResult(
          name,
          '服务可达，但登录或文件访问权限失效（${response.statusCode}）',
        );
      }
      if (response.statusCode >= 300 && response.statusCode < 400) {
        return NetworkProbeResult(name, '服务发生跳转，请检查网络或登录状态');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return NetworkProbeResult(name, '服务返回 HTTP ${response.statusCode}');
      }
      final first = await response.stream.first.timeout(timeout);
      if (first.isEmpty ||
          (json &&
              !utf8
                  .decode(first, allowMalformed: true)
                  .trimLeft()
                  .startsWith('{'))) {
        return NetworkProbeResult(name, '收到非预期响应，请检查代理或网络登录页面');
      }
      return NetworkProbeResult(
        name,
        '连接正常 · ${watch.elapsedMilliseconds} ms',
        success: true,
      );
    } catch (error) {
      return NetworkProbeResult(name, _errorMessage(error));
    } finally {
      client.close();
    }
  }

  String _errorMessage(Object error) {
    if (error is TimeoutException) return '连接超时，请检查网络或切换连接方式';
    final text = error.toString().toLowerCase();
    if (text.contains('certificate') || text.contains('handshake')) {
      return '安全连接失败，请检查系统时间或代理证书';
    }
    if (text.contains('host lookup') || text.contains('name resolution')) {
      return '域名解析失败，请检查 DNS 或网络';
    }
    return '无法连接，请检查网络或代理设置';
  }
}
