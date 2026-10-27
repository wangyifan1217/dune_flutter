import 'dart:io';

bool get supportsDesktopNetworkPolicy => Platform.isWindows || Platform.isMacOS;

/// 每次新建请求时解析模式；现存 HttpClient 也能切换，不关闭正在传输的连接。
class DesktopNetworkHttpOverrides extends HttpOverrides {
  DesktopNetworkHttpOverrides({
    required this.direct,
    this.previous,
    this.defaultProxy,
  });

  final bool Function() direct;
  final HttpOverrides? previous;
  final String Function(Uri)? defaultProxy;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client =
        previous?.createHttpClient(context) ?? super.createHttpClient(context);
    client.findProxy = (uri) => direct()
        ? 'DIRECT'
        : (defaultProxy?.call(uri) ?? HttpClient.findProxyFromEnvironment(uri));
    return client;
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      previous?.findProxyFromEnvironment(url, environment) ??
      super.findProxyFromEnvironment(url, environment);
}

bool _installed = false;

void installDesktopNetworkPolicy(bool Function() direct) {
  if (_installed || !supportsDesktopNetworkPolicy) return;
  HttpOverrides.global = DesktopNetworkHttpOverrides(
    direct: direct,
    previous: HttpOverrides.current,
  );
  _installed = true;
}

Future<void> probeDesktopWebSocket(Uri uri, Duration timeout) async {
  final client = HttpClient()..connectionTimeout = timeout;
  WebSocket? socket;
  try {
    socket = await WebSocket.connect(
      uri.toString(),
      customClient: client,
    ).timeout(timeout);
  } finally {
    client.close(force: true);
    if (socket != null) {
      await socket.close().timeout(const Duration(seconds: 2));
    }
  }
}
