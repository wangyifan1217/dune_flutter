/// 腾讯云 TPNS（移动推送）配置。
///
/// Android Gradle 侧请在 `android/local.properties` 中配置（与 Dart 侧保持一致）：
/// ```
/// tpns.accessId=你的ACCESS_ID
/// tpns.accessKey=你的ACCESS_KEY
/// ```
///
/// iOS 需在 TPNS 控制台单独创建 iOS 应用，上传 APNs 推送证书（p12 或 p8），
/// 并使用该 iOS 应用的 AccessID / AccessKey（可与 Android 不同）。
///
/// 运行时也可通过 `--dart-define` 覆盖：
/// `--dart-define=TPNS_ACCESS_ID=... --dart-define=TPNS_ACCESS_KEY=...`
///
/// 小米厂商通道（Redmi/POCO 等，可选）：
/// `--dart-define=TPNS_MI_APP_ID=... --dart-define=TPNS_MI_APP_KEY=...`
///
/// 非广州集群域名（可选，如上海 `tpns.sh.tencent.com`）：
/// `--dart-define=TPNS_CLUSTER=tpns.sh.tencent.com`
abstract final class TpnsConfig {
  static const accessId = String.fromEnvironment(
    'TPNS_ACCESS_ID',
    defaultValue: 'your_tpns_access_id',
  );

  static const accessKey = String.fromEnvironment(
    'TPNS_ACCESS_KEY',
    defaultValue: 'your_tpns_access_key',
  );

  static const miPushAppId = String.fromEnvironment(
    'TPNS_MI_APP_ID',
    defaultValue: '',
  );

  static const miPushAppKey = String.fromEnvironment(
    'TPNS_MI_APP_KEY',
    defaultValue: '',
  );

  static const clusterDomain = String.fromEnvironment(
    'TPNS_CLUSTER',
    defaultValue: '',
  );

  static bool get isConfigured =>
      accessId.isNotEmpty &&
      accessId != 'your_tpns_access_id' &&
      accessKey.isNotEmpty &&
      accessKey != 'your_tpns_access_key';
}
