/// DUNES API 地址配置。
///
/// 默认走 Nginx HTTPS 域名；本地联调仍可用 host 覆盖拼 `http://host:端口`。
abstract final class DunesDefaults {
  static const gatewayPort = 6090;
  static const flowPort = 6087;

  /// 生产 HTTPS 根地址（不含 `/api/v1`）。
  static const publicOrigin = String.fromEnvironment(
    'DUNES_PUBLIC_ORIGIN',
    defaultValue: 'https://nova.heunion.com',
  );

  /// 完整业务 API 基址覆盖，例如：
  /// `--dart-define=DUNES_API_BASE=https://nova.heunion.com/api/v1`
  static const _apiBaseFromDefine = String.fromEnvironment(
    'DUNES_API_BASE',
    defaultValue: '',
  );

  /// 仅传 host 时的覆盖：
  /// - `127.0.0.1` / 内网 IP → `http://host:6090/api/v1`
  /// - 域名（如 `nova.heunion.com`）→ `https://host/api/v1`
  ///
  /// `--dart-define=DUNES_API_HOST=127.0.0.1`
  static const _hostFromDefine = String.fromEnvironment(
    'DUNES_API_HOST',
    defaultValue: '',
  );

  /// 兼容旧变量；非空时等同于 [DUNES_API_HOST]。
  static const _devServerHost = String.fromEnvironment(
    'DUNES_DEV_SERVER_HOST',
    defaultValue: '',
  );

  /// JS 注入占位符，由 [bindApiBase] 在运行时替换为 [apiBase]。
  static const apiBasePlaceholder = '__DUNES_API_BASE__';

  static String get publicOriginNormalized =>
      publicOrigin.replaceAll(RegExp(r'/$'), '');

  static String resolveGatewayHost() {
    final override = _firstNonEmpty(_hostFromDefine, _devServerHost);
    if (override.isNotEmpty) return _hostFromValue(override);
    final originHost = Uri.tryParse(publicOriginNormalized)?.host ?? '';
    if (originHost.isNotEmpty) return originHost;
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

  static String get apiBase {
    if (_apiBaseFromDefine.isNotEmpty) {
      return _apiBaseFromDefine.replaceAll(RegExp(r'/$'), '');
    }
    final override = _firstNonEmpty(_hostFromDefine, _devServerHost);
    if (override.isNotEmpty) {
      return _apiBaseFromHostOverride(override);
    }
    return '$publicOriginNormalized/api/v1';
  }

  /// flow-go 直连；HTTPS 域名下与 [apiBase] 相同（经网关），本地 host 覆盖仍走 :6087。
  static String get flowApiBase {
    final override = _firstNonEmpty(_hostFromDefine, _devServerHost);
    if (override.isNotEmpty && _useLegacyHttpPort(override)) {
      final host = _hostFromValue(override);
      return 'http://$host:$flowPort/api/v1';
    }
    return apiBase;
  }

  static String get wsBase {
    final base = Uri.parse(apiBase);
    return Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/connection/websocket',
    ).toString();
  }

  static String bindApiBase(String source) =>
      source.replaceAll(apiBasePlaceholder, apiBase);

  static String _apiBaseFromHostOverride(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final uri = Uri.parse(trimmed);
      if (uri.path.isEmpty || uri.path == '/') {
        return '${trimmed.replaceAll(RegExp(r'/$'), '')}/api/v1';
      }
      return trimmed.replaceAll(RegExp(r'/$'), '');
    }
    final host = _hostFromValue(trimmed);
    if (_useLegacyHttpPort(trimmed)) {
      return 'http://$host:$gatewayPort/api/v1';
    }
    return 'https://$host/api/v1';
  }

  static bool _useLegacyHttpPort(String raw) {
    final host = _hostFromValue(raw);
    if (host == 'localhost' || host == '127.0.0.1' || host == '0.0.0.0') {
      return true;
    }
    // IPv4（含内网）走旧端口直连，便于本地 Docker / 真机联调。
    final parts = host.split('.');
    if (parts.length == 4 && parts.every((p) => int.tryParse(p) != null)) {
      return true;
    }
    return false;
  }

  static String _hostFromValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Uri.parse(trimmed).host;
    }
    // host:port → host
    if (trimmed.contains(':') && !trimmed.contains('://')) {
      return trimmed.split(':').first;
    }
    return trimmed;
  }

  static String _firstNonEmpty(String a, String b) {
    if (a.trim().isNotEmpty) return a.trim();
    if (b.trim().isNotEmpty) return b.trim();
    return '';
  }
}
