/// DUNES 本地开发默认端口，与 [scripts/dunes-ports.ps1] 保持一致。
abstract final class DunesDefaults {
  static const gatewayPort = 6090;
  static const apiBase = 'http://localhost:$gatewayPort/api/v1';
  static const wsBase = 'ws://127.0.0.1:$gatewayPort/connection/websocket';
}
