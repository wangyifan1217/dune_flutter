bool get supportsDesktopNetworkPolicy => false;

void installDesktopNetworkPolicy(bool Function() direct) {}

Future<void> probeDesktopWebSocket(Uri uri, Duration timeout) =>
    Future.error(UnsupportedError('当前平台不支持此连接检测'));
