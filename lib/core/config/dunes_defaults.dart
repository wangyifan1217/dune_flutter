/// DUNES API 地址配置，端口与 [new_dune/scripts/dunes-ports.ps1] 保持一致。
abstract final class DunesDefaults {
  static const gatewayPort = 6090;

  /// 联调/生产服务器 IP 或域名。留空则本机用 localhost，局域网访问时自动用页面 host。
  ///
  /// 也可启动时覆盖：`--dart-define=DUNES_API_HOST=1.2.3.4`
  static const devServerHost = '115.159.46.108';

  static const _hostFromDefine = String.fromEnvironment(
    'DUNES_API_HOST',
    defaultValue: '',
  );

  /// JS 注入占位符，由 [bindApiBase] 在运行时替换为 [apiBase]。
  static const apiBasePlaceholder = '__DUNES_API_BASE__';

  static String resolveGatewayHost() {
    if (_hostFromDefine.isNotEmpty) return _hostFromDefine;
    if (devServerHost.isNotEmpty) return devServerHost;
    final pageHost = Uri.base.host;
    if (pageHost.isNotEmpty &&
        pageHost != 'localhost' &&
        pageHost != '127.0.0.1') {
      return pageHost;
    }
    return 'localhost';
  }

  static String get apiBase =>
      'http://${resolveGatewayHost()}:$gatewayPort/api/v1';

  static String get wsBase =>
      'ws://${resolveGatewayHost()}:$gatewayPort/connection/websocket';

  static String bindApiBase(String source) =>
      source.replaceAll(apiBasePlaceholder, apiBase);
}
