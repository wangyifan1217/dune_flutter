/// Nova API 网关（与业务 `/api/v1` 同域时共用 HTTPS 根地址）。
abstract final class NovaConfig {
  static const baseUrl = String.fromEnvironment(
    'NOVA_BASE_URL',
    defaultValue: 'https://nova.heunion.com',
  );

  static const defaultChatModel = 'nova_deepseek';
  static const asrModel = 'glm-asr-2512';

  /// 产品对外名称。
  static const displayName = 'NOVA';

  /// Nova 聊天输入栏「上传文件」按钮（当轮文件提问）。
  static const fileUploadInChatEnabled = true;

  /// JS 注入占位符，由 [bindNovaBase] 在运行时替换为 [baseUrl]。
  static const baseUrlPlaceholder = '__NOVA_BASE_URL__';

  static String get baseUrlNormalized =>
      baseUrl.replaceAll(RegExp(r'/$'), '');

  /// 归一化 Nova 基址：后端若仍下发旧 `http://IP:3000`，改走 HTTPS 域名。
  static String resolveBaseUrl([String? raw]) {
    final fallback = baseUrlNormalized;
    final value = (raw ?? '').trim().replaceAll(RegExp(r'/$'), '');
    if (value.isEmpty) return fallback;

    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) return fallback;

    final host = uri.host.toLowerCase();
    final isLegacyIp = host == '124.221.216.24';
    final isLegacyHttpPort =
        uri.hasPort ? uri.port == 3000 : uri.scheme == 'http';
    if (isLegacyIp && isLegacyHttpPort) return fallback;

    if (host == 'nova.heunion.com' && uri.scheme == 'http') {
      return fallback;
    }
    return value;
  }

  static String bindNovaBase(String source) =>
      source.replaceAll(baseUrlPlaceholder, baseUrlNormalized);
}
