/// Nova API 网关（与 DunesDefaults :6090 业务网关分离）。
abstract final class NovaConfig {
  static const baseUrl = String.fromEnvironment(
    'NOVA_BASE_URL',
    defaultValue: 'http://124.221.216.24:3000',
  );

  static const defaultChatModel = 'nova_deepseek';
  static const asrModel = 'glm-asr-2512';

  /// 产品对外名称（原 NOVA）。
  static const displayName = '云枢';

  /// JS 注入占位符，由 [bindNovaBase] 在运行时替换为 [baseUrl]。
  static const baseUrlPlaceholder = '__NOVA_BASE_URL__';

  static String bindNovaBase(String source) =>
      source.replaceAll(baseUrlPlaceholder, baseUrl);
}
