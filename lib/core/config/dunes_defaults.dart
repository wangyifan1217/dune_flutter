/// DUNES API 地址配置，端口与 [new_dune/scripts/dunes-ports.ps1] 保持一致。
abstract final class DunesDefaults {
  static const gatewayPort = 6090;
  static const flowPort = 6087;

  /// 联调/生产服务器 IP 或域名。留空则本机用 localhost，局域网访问时自动用页面 host。
  ///
  /// 也可启动时覆盖：`--dart-define=DUNES_API_HOST=127.0.0.1`（本地 lighthouse 三级下钻）
  /// 或 `--dart-define=DUNES_API_HOST=192.168.x.x`（真机连本机 Docker 网关）
  static const devServerHost = String.fromEnvironment(
    'DUNES_DEV_SERVER_HOST',
    defaultValue: '124.221.216.24',
  );

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

  /// 本地联调（127.0.0.1 / localhost）时跳过灯塔账号权限校验。
  static bool get localLighthouseAccessBypass {
    final host = resolveGatewayHost();
    return host == '127.0.0.1' || host == 'localhost';
  }

  static String get apiBase =>
      'http://${resolveGatewayHost()}:$gatewayPort/api/v1';

  /// flow-go 直连（XFlow 模板/提交；网关 6090 可能未代理 /xflow）
  static String get flowApiBase =>
      'http://${resolveGatewayHost()}:$flowPort/api/v1';

  static String get wsBase =>
      'ws://${resolveGatewayHost()}:$gatewayPort/connection/websocket';

  static String bindApiBase(String source) =>
      source.replaceAll(apiBasePlaceholder, apiBase);
}
